import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    @State private var searchText = ""
    @State private var kindGroup: KindGroup = .all
    @State private var folderID: Int64?
    @State private var pinnedOnly = false
    @State private var viewMode: LibraryViewMode = .grid
    @State private var files: [IndexedFile] = []
    @State private var isLoading = true
    @State private var previewFile: IndexedFile?

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            content
        }
        .background(Palette.canvas)
        .onAppear {
            consumePendingFile()
        }
        .onChange(of: model.pendingLibraryFileID) { _, _ in
            consumePendingFile()
        }
        .task(id: reloadKey) {
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try? await Task.sleep(for: .milliseconds(170))
            }
            guard !Task.isCancelled else { return }
            await loadFiles()
        }
        .sheet(item: $previewFile, onDismiss: {
            Task { await loadFiles() }
        }) { file in
            FilePreviewView(file: file)
                .environment(model)
                .environment(settings)
                .tint(settings.accent.color)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 13) {
            PageHeader(
                eyebrow: "Your files",
                title: "Library",
                subtitle: librarySubtitle
            ) {
                HStack(spacing: 8) {
                    Button {
                        model.chooseFolder()
                    } label: {
                        Label("Add Folder", systemImage: "plus")
                    }
                    .buttonStyle(.secondaryAction)

                    Button {
                        model.startIndexing(force: false)
                    } label: {
                        Label(model.isIndexing ? "Indexing…" : "Index Now",
                              systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.primaryAction)
                    .disabled(model.isIndexing || model.folders.isEmpty)
                }
            }

            filterBar
        }
        .padding(.horizontal, 34)
        .padding(.top, 24)
        .padding(.bottom, 14)
    }

    private var librarySubtitle: String {
        if model.stats.fileCount == 0 {
            return "Everything Lumina can see. Add a folder to begin."
        }
        let files = model.stats.fileCount.formatted()
        let size = model.stats.totalBytes.luminaByteSize
        return "\(files) files · \(model.stats.chunkCount.formatted()) passages · \(size). Previews are read from the local index and original files."
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            LuminaSearchField(
                text: $searchText,
                placeholder: "Filter by file name or path",
                onSubmit: nil
            )
            .frame(maxWidth: 330)

            Menu {
                ForEach(KindGroup.allCases, id: \.self) { group in
                    Button {
                        kindGroup = group
                    } label: {
                        if kindGroup == group {
                            Label(group.rawValue, systemImage: "checkmark")
                        } else {
                            Text(group.rawValue)
                        }
                    }
                }
            } label: {
                LibraryFilterChip(
                    icon: "square.grid.2x2",
                    title: kindGroup == .all ? "All types" : kindGroup.rawValue,
                    isActive: kindGroup != .all
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Menu {
                Button {
                    folderID = nil
                } label: {
                    if folderID == nil {
                        Label("All folders", systemImage: "checkmark")
                    } else {
                        Text("All folders")
                    }
                }
                if !model.folders.isEmpty {
                    Divider()
                    ForEach(model.folders) { folder in
                        Button {
                            folderID = folder.id
                        } label: {
                            if folderID == folder.id {
                                Label(folder.name, systemImage: "checkmark")
                            } else {
                                Text(folder.name)
                            }
                        }
                    }
                }
            } label: {
                LibraryFilterChip(
                    icon: "folder",
                    title: folderID.flatMap { id in model.folders.first { $0.id == id }?.name } ?? "All folders",
                    isActive: folderID != nil
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                pinnedOnly.toggle()
            } label: {
                LibraryFilterChip(icon: "pin", title: "Pinned", isActive: pinnedOnly)
            }
            .buttonStyle(.plain)

            if hasFilters {
                Button {
                    searchText = ""
                    kindGroup = .all
                    folderID = nil
                    pinnedOnly = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear filters")
            }

            Spacer(minLength: 4)

            Picker("View", selection: $viewMode) {
                Image(systemName: "square.grid.2x2").tag(LibraryViewMode.grid)
                Image(systemName: "list.bullet").tag(LibraryViewMode.list)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 78)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if isLoading && files.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("Reading the local index…")
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if files.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    if !model.isFullyConfigured {
                        InlineNotice(
                            text: "Keyword search works now. Install the embedding and chat models to add semantic search and grounded answers.",
                            tone: .neutral
                        )
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text("\(files.count) file\(files.count == 1 ? "" : "s")")
                            .font(LuminaType.captionEmphasis)
                            .foregroundStyle(Palette.secondary)
                        if pinnedOnly {
                            Text("· pinned only")
                                .font(LuminaType.caption)
                                .foregroundStyle(Palette.tertiary)
                        }
                        Spacer()
                        if model.stats.failedFileCount > 0 {
                            Text("\(model.stats.failedFileCount) couldn't be read")
                                .font(LuminaType.caption)
                                .foregroundStyle(Palette.tertiary)
                        }
                    }

                    if viewMode == .grid {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 172, maximum: 226), spacing: 12)],
                            spacing: 12
                        ) {
                            ForEach(files) { file in
                                FileCard(file: file) {
                                    previewFile = file
                                }
                                .contextMenu {
                                    fileContextMenu(file)
                                }
                            }
                        }
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                                if index > 0 {
                                    Hairline().padding(.leading, 60)
                                }
                                Button {
                                    previewFile = file
                                } label: {
                                    FileRow(file: file)
                                        .padding(.horizontal, 15)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    fileContextMenu(file)
                                }
                            }
                        }
                        .luminaCard(padding: 0)
                    }
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 18)
                .frame(maxWidth: 1_180)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: hasFilters ? "line.3.horizontal.decrease.circle" : (model.hasFolders ? "tray" : "folder.badge.plus"),
            title: emptyTitle,
            message: emptyMessage
        ) {
            HStack(spacing: 8) {
                if hasFilters {
                    Button("Clear Filters") {
                        searchText = ""
                        kindGroup = .all
                        folderID = nil
                        pinnedOnly = false
                    }
                    .buttonStyle(.secondaryAction)
                }
                if !model.hasFolders {
                    Button("Add Folder") { model.chooseFolder() }
                        .buttonStyle(.primaryAction)
                } else if !model.isIndexing {
                    Button("Index Now") { model.startIndexing(force: false) }
                        .buttonStyle(.primaryAction)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Helpers

    private var hasFilters: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || kindGroup != .all
            || folderID != nil
            || pinnedOnly
    }

    private var emptyTitle: String {
        if hasFilters { return "No files match these filters" }
        return model.hasFolders ? "Nothing indexed yet" : "Your library is empty"
    }

    private var emptyMessage: String {
        if hasFilters {
            return "Try a different file type or folder, or clear the filters."
        }
        if model.hasFolders {
            return model.isFullyConfigured
                ? "Start an index run to read the folders you've added. Lumina only stores the passages it needs."
                : "Finish model setup to index these folders. Keyword indexing can still run while models are missing."
        }
        return "Add a folder of documents, images, notes, code, or media. Lumina reads only the folders you choose."
    }

    private var reloadKey: String {
        [
            searchText,
            kindGroup.rawValue,
            folderID.map(String.init) ?? "all",
            pinnedOnly ? "pinned" : "any",
            String(model.folders.count),
            String(model.stats.fileCount),
            model.stats.lastIndexedAt?.timeIntervalSince1970.description ?? "none"
        ].joined(separator: "|")
    }

    private func loadFiles() async {
        isLoading = true
        let kinds = kindGroup == .all ? [] : kindGroup.kinds
        let fetched = await model.loadLibraryFiles(
            kinds: kinds,
            folderID: folderID,
            search: searchText
        )
        guard !Task.isCancelled else { return }
        files = pinnedOnly ? fetched.filter(\.isPinned) : fetched
        isLoading = false
    }

    private func consumePendingFile() {
        guard let id = model.pendingLibraryFileID else { return }
        model.pendingLibraryFileID = nil
        Task {
            if let file = await model.loadFile(id: id) {
                previewFile = file
            }
        }
    }

    @ViewBuilder
    private func fileContextMenu(_ file: IndexedFile) -> some View {
        Button("Preview") { previewFile = file }
        Button("Open") { FileActions.open(file) }
        Button("Reveal in Finder") { FileActions.reveal(file) }
        Divider()
        Button(file.isPinned ? "Unpin" : "Pin") {
            Task {
                _ = await model.togglePin(fileID: file.id)
                await loadFiles()
            }
        }
        Button("Copy Path") { FileActions.copyPath(file) }
    }
}

// MARK: - View mode

private enum LibraryViewMode: Hashable {
    case grid
    case list
}

// MARK: - Filter chip

private struct LibraryFilterChip: View {
    let icon: String
    let title: String
    var isActive: Bool = false
    var hasChevron: Bool = true

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .medium))
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            if hasChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .opacity(0.55)
            }
        }
        .foregroundStyle(isActive ? Color.accentColor : Palette.secondary)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.08) : Palette.raised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(isActive ? Color.accentColor.opacity(0.28) : Palette.separator.opacity(0.5),
                              lineWidth: 0.7)
        )
    }
}
