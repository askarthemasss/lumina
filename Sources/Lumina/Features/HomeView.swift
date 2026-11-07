import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @State private var showSetupSheet = false

    var body: some View {
        ScreenScroll {
            PageHeader(
                eyebrow: eyebrow,
                title: greeting,
                subtitle: homeSubtitle
            ) {
                HStack(spacing: 9) {
                    Button {
                        NotificationCenter.default.post(name: .luminaShowQuickSearch, object: nil)
                    } label: {
                        Label("Quick Search", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.secondaryAction)

                    Button {
                        model.chooseFolder()
                    } label: {
                        Label("Add Folder", systemImage: "plus")
                    }
                    .buttonStyle(.primaryAction)
                }
            }

            searchPrompt

            if model.isIndexing {
                indexingCard
            }

            if !model.isFullyConfigured || !model.hasFolders {
                SetupGuideView()
            } else {
                readyCard

                if model.embeddingModelMismatch {
                    embeddingMismatchCard
                }
            }

            statsGrid

            if !model.pinnedFiles.isEmpty {
                pinnedSection
            }

            recentSection

            footerNote
        }
        .sheet(isPresented: $showSetupSheet) {
            setupSheet
                .environment(model)
                .environment(settings)
                .tint(settings.accent.color)
        }
    }

    // MARK: Header

    private var eyebrow: String {
        Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Good night"
        }
    }

    private var homeSubtitle: String {
        if model.stats.fileCount > 0 {
            let files = model.stats.fileCount.formatted()
            return "Search and ask across \(files) private file\(model.stats.fileCount == 1 ? "" : "s"). Nothing leaves this Mac."
        }
        if model.hasFolders {
            return "Your folders are connected. Keyword indexing works now; add local models for semantic search and grounded answers."
        }
        return "Illuminate your local knowledge. Add a folder and Lumina will make it searchable — privately."
    }

    // MARK: Search

    private var searchPrompt: some View {
        Button {
            NotificationCenter.default.post(name: .luminaShowQuickSearch, object: nil)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.accentColor)
                Text("Search documents, screenshots, media, and code…")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Palette.secondary)
                Spacer()
                KeyCap(label: "⌘K")
                KeyCap(label: settings.shortcut.display)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Palette.separator.opacity(0.55), lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
        .help("Open Quick Search")
    }

    // MARK: Status cards

    private var indexingCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.indexingProgress.phase.title)
                        .font(LuminaType.bodyEmphasis)
                        .foregroundStyle(Palette.label)
                    Text(indexingDetail)
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Pause") { model.cancelIndexing() }
                    .buttonStyle(.secondaryAction)
            }
            ThinProgressBar(value: model.indexingProgress.fraction)
            if !model.indexingProgress.currentFile.isEmpty {
                Text(model.indexingProgress.currentFile)
                    .font(LuminaType.monoSmall)
                    .foregroundStyle(Palette.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .luminaCard(padding: 16)
    }

    private var indexingDetail: String {
        let progress = model.indexingProgress
        var parts: [String] = []
        if progress.filesDiscovered > 0 {
            parts.append("\(progress.filesProcessed) of \(progress.filesDiscovered) files")
        }
        if progress.chunksCreated > 0 {
            parts.append("\(progress.chunksCreated.formatted()) passages")
        }
        if let remaining = progress.estimatedSecondsRemaining, remaining > 4 {
            parts.append("about \(Int(remaining.rounded()))s left")
        }
        return parts.isEmpty ? "Preparing the scan…" : parts.joined(separator: " · ")
    }

    private var readyCard: some View {
        HStack(alignment: .top, spacing: 13) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Lumina is ready")
                    .font(LuminaType.sectionTitle)
                    .foregroundStyle(Palette.label)
                Text("\(settings.chatModel) answers from your index. \(settings.embeddingModel) handles semantic search. Both run through \(settings.runtimeKind.title) at \(settings.endpoint).")
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button("Review Setup") { showSetupSheet = true }
                    .buttonStyle(.secondaryAction)
                Button {
                    model.startIndexing(force: true)
                } label: {
                    Label("Reindex", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.primaryAction)
            }
        }
        .luminaCard(padding: 16)
    }

    private var embeddingMismatchCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "vector.badge.exclamationmark")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.orange)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Semantic index uses a different model")
                    .font(LuminaType.bodyEmphasis)
                    .foregroundStyle(Palette.label)
                Text("The stored vectors were created with \(model.indexedEmbeddingModels.joined(separator: ", ")). Search still works with keywords. Reindex to use \(settings.embeddingModel) for semantic matches.")
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Reindex") { model.reindexAll() }
                .buttonStyle(.secondaryAction)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.18), lineWidth: 0.7)
        )
    }

    // MARK: Stats

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 11)], spacing: 11) {
            StatTile(
                label: "Files",
                value: model.stats.fileCount.formatted(),
                icon: "doc.on.doc",
                detail: model.stats.failedFileCount > 0 ? "\(model.stats.failedFileCount) couldn't be read" : nil
            )
            StatTile(
                label: "Searchable passages",
                value: model.stats.chunkCount.formatted(),
                icon: "text.line.first.and.arrowtriangle.forward",
                detail: model.pendingEmbeddingChunkCount > 0
                    ? "\(model.pendingEmbeddingChunkCount.formatted()) awaiting vectors"
                    : nil
            )
            StatTile(
                label: "Folders",
                value: model.stats.folderCount.formatted(),
                icon: "folder",
                detail: model.folders.filter { !$0.isEnabled }.isEmpty ? nil : "Some folders paused"
            )
            StatTile(
                label: "Index size",
                value: model.stats.totalBytes.luminaByteSize,
                icon: "externaldrive",
                detail: model.stats.lastIndexedAt.map { "Updated \($0.luminaRelative)" }
            )
        }
    }

    // MARK: File sections

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pinned")
                    .font(LuminaType.sectionTitle)
                    .foregroundStyle(Palette.label)
                Spacer()
                TextLinkButton(title: "View all", systemImage: nil) {
                    model.route = .timeline
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(model.pinnedFiles.prefix(4).enumerated()), id: \.element.id) { index, file in
                    if index > 0 {
                        Hairline().padding(.leading, 64)
                    }
                    Button {
                        model.showFileInLibrary(file)
                    } label: {
                        FileRow(file: file)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                }
            }
            .luminaCard(padding: 0)
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recently indexed")
                        .font(LuminaType.sectionTitle)
                        .foregroundStyle(Palette.label)
                    Text("Fresh passages from the library.")
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.tertiary)
                }
                Spacer()
                TextLinkButton(title: "Open Library", systemImage: "arrow.right") {
                    model.route = .library
                }
            }

            if model.recentFiles.isEmpty {
                EmptyStateView(
                    icon: model.hasFolders ? "tray" : "folder.badge.plus",
                    title: model.hasFolders ? "Nothing indexed yet" : "Add your first folder",
                    message: model.hasFolders
                        ? "Lumina has not committed any files yet. Start an index run to make this folder searchable."
                        : "Choose a folder of documents, photos, or notes. Lumina reads only what you select."
                ) {
                    Button(model.hasFolders ? "Index Now" : "Choose a Folder") {
                        if model.hasFolders {
                            model.startIndexing(force: false)
                        } else {
                            model.chooseFolder()
                        }
                    }
                    .buttonStyle(.primaryAction)
                    .disabled(model.hasFolders && model.isIndexing)
                }
                .frame(minHeight: 260)
                .luminaCard(padding: 0)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.recentFiles.prefix(6).enumerated()), id: \.element.id) { index, file in
                        if index > 0 {
                            Hairline().padding(.leading, 64)
                        }
                        Button {
                            model.showFileInLibrary(file)
                        } label: {
                            FileRow(file: file)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 9)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .luminaCard(padding: 0)
            }
        }
    }

    private var footerNote: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.tertiary)
            Text("No account. No telemetry. Model requests are restricted to loopback addresses.")
                .font(LuminaType.caption)
                .foregroundStyle(Palette.tertiary)
            Spacer()
            Button("Why local?") { model.showWhyLocal = true }
                .buttonStyle(.quietAction)
            Button("Setup") { showSetupSheet = true }
                .buttonStyle(.quietAction)
        }
        .padding(.top, 4)
    }

    // MARK: Setup sheet

    private var setupSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Setup & diagnostics")
                    .font(LuminaType.sectionTitle)
                    .foregroundStyle(Palette.label)
                Spacer()
                Button("Done") { showSetupSheet = false }
                    .buttonStyle(.secondaryAction)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)

            Hairline()

            ScrollView {
                SetupGuideView()
                    .padding(22)
            }
        }
        .frame(width: 790, height: 760)
        .background(Palette.canvas)
    }
}
