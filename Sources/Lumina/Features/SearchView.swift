import SwiftUI

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    @State private var query = ""
    @State private var kindGroup: KindGroup = .all
    @State private var selectedFolders: Set<Int64> = []
    @State private var dateWindow: SearchDateWindow = .anyTime
    @State private var exactPhrase = false
    @State private var outcome: SearchOutcome?
    @State private var isSearching = false
    @State private var selection: SearchHit?
    @State private var previewChunks: [StoredChunk] = []
    @State private var previewNotes: [UserNote] = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            content
        }
        .background(Palette.canvas)
        .onAppear(perform: applyPendingQuery)
        .onChange(of: model.pendingSearchQuery) { _, _ in
            applyPendingQuery()
        }
        .task(id: searchKey) {
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try? await Task.sleep(for: .milliseconds(180))
            }
            guard !Task.isCancelled else { return }
            await runSearch()
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 13) {
            PageHeader(
                eyebrow: "Hybrid retrieval",
                title: "Search",
                subtitle: "Semantic meaning and exact keywords, merged from your local index."
            ) {
                HStack(spacing: 8) {
                    if isSearching {
                        ProgressView().controlSize(.small)
                    }
                    StatusPill(
                        text: outcome?.semanticUsed == true ? "Semantic + keyword" : "Keyword search",
                        tone: outcome?.semanticUsed == true ? .accentColor : .secondary
                    )
                }
            }

            HStack(spacing: 14) {
                LuminaSearchField(
                    text: $query,
                    placeholder: "Search everything you've indexed",
                    autoFocus: true,
                    onSubmit: openFirstResult
                )
                .frame(maxWidth: 620)

                Spacer(minLength: 4)

                filterControls
            }
        }
        .padding(.horizontal, 34)
        .padding(.top, 24)
        .padding(.bottom, 14)
        .background(Palette.canvas)
    }

    private var filterControls: some View {
        HStack(spacing: 7) {
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
                FilterChip(
                    icon: "square.grid.2x2",
                    title: kindGroup == .all ? "All types" : kindGroup.rawValue,
                    isActive: kindGroup != .all
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Menu {
                Button {
                    selectedFolders.removeAll()
                } label: {
                    if selectedFolders.isEmpty {
                        Label("All folders", systemImage: "checkmark")
                    } else {
                        Text("All folders")
                    }
                }
                if !model.folders.isEmpty {
                    Divider()
                    ForEach(model.folders) { folder in
                        Button {
                            if selectedFolders.contains(folder.id) {
                                selectedFolders.remove(folder.id)
                            } else {
                                selectedFolders.insert(folder.id)
                            }
                        } label: {
                            if selectedFolders.contains(folder.id) {
                                Label(folder.name, systemImage: "checkmark")
                            } else {
                                Text(folder.name)
                            }
                        }
                    }
                }
            } label: {
                FilterChip(
                    icon: "folder",
                    title: selectedFolders.isEmpty
                        ? "All folders"
                        : (selectedFolders.count == 1
                            ? (model.folders.first { selectedFolders.contains($0.id) }?.name ?? "1 folder")
                            : "\(selectedFolders.count) folders"),
                    isActive: !selectedFolders.isEmpty
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Menu {
                ForEach(SearchDateWindow.allCases) { window in
                    Button {
                        dateWindow = window
                    } label: {
                        if dateWindow == window {
                            Label(window.title, systemImage: "checkmark")
                        } else {
                            Text(window.title)
                        }
                    }
                }
            } label: {
                FilterChip(
                    icon: "calendar",
                    title: dateWindow == .anyTime ? "Any time" : dateWindow.title,
                    isActive: dateWindow != .anyTime
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                exactPhrase.toggle()
            } label: {
                FilterChip(icon: "quote.bubble", title: "Exact phrase", isActive: exactPhrase)
            }
            .buttonStyle(.plain)

            if hasActiveFilters {
                Button {
                    resetFilters()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear filters")
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let outcome {
            HStack(spacing: 0) {
                resultsPane(outcome)
                if selection != nil {
                    Rectangle()
                        .fill(Palette.separator.opacity(0.55))
                        .frame(width: 0.7)
                    previewPane
                        .frame(width: 386)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.16), value: selection?.file.id)
        } else {
            VStack(spacing: 10) {
                ProgressView()
                Text("Opening your local index…")
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func resultsPane(_ outcome: SearchOutcome) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(resultHeadline(outcome))
                    .font(LuminaType.captionEmphasis)
                    .foregroundStyle(Palette.secondary)
                if isSearching {
                    Text("searching…")
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.tertiary)
                }
                Spacer()
                if !outcome.hits.isEmpty {
                    Text("\(Int((outcome.duration * 1_000).rounded())) ms")
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.tertiary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if let warning = outcome.warning {
                InlineNotice(text: warning, tone: .warning)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 8)
            }

            if outcome.hits.isEmpty {
                emptyResults
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(outcome.hits) { hit in
                            SearchResultRow(
                                hit: hit,
                                isSelected: selection?.file.id == hit.file.id
                            ) {
                                selection = hit
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var previewPane: some View {
        Group {
            if let selection {
                SearchPreviewPane(
                    hit: selection,
                    chunks: previewChunks,
                    notes: previewNotes,
                    onOpenInLibrary: {
                        model.showFileInLibrary(selection.file)
                    },
                    onNoteAdded: {
                        Task { await reloadNotes(fileID: selection.file.id) }
                    }
                )
                .id(selection.file.id)
            }
        }
        .frame(maxHeight: .infinity)
        .background(Palette.canvas)
    }

    private var emptyResults: some View {
        EmptyStateView(
            icon: hasActiveFilters ? "line.3.horizontal.decrease.circle" : "magnifyingglass",
            title: emptyTitle,
            message: emptyMessage
        ) {
            HStack(spacing: 8) {
                if hasActiveFilters {
                    Button("Clear Filters") { resetFilters() }
                        .buttonStyle(.secondaryAction)
                }
                if query.isEmpty && !model.hasIndexedContent {
                    Button("Add Folder") { model.chooseFolder() }
                        .buttonStyle(.primaryAction)
                } else if !query.isEmpty {
                    Button("Clear Search") {
                        query = ""
                        resetFilters()
                    }
                    .buttonStyle(.secondaryAction)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Derived

    private var searchFilters: SearchFilters {
        SearchFilters(
            kinds: kindGroup == .all ? [] : kindGroup.kinds,
            folderIDs: selectedFolders,
            dateFrom: dateWindow.dateFrom,
            dateTo: nil,
            exactPhrase: exactPhrase
        )
    }

    private var searchKey: String {
        [
            query,
            kindGroup.rawValue,
            selectedFolders.map(String.init).sorted().joined(separator: ","),
            dateWindow.rawValue,
            exactPhrase ? "exact" : "any"
        ].joined(separator: "|")
    }

    private var hasActiveFilters: Bool {
        kindGroup != .all || !selectedFolders.isEmpty || dateWindow != .anyTime || exactPhrase
    }

    private var emptyTitle: String {
        if query.isEmpty {
            return model.hasIndexedContent ? "No files match these filters" : "Your library is empty"
        }
        return "No matches for “\(query)”"
    }

    private var emptyMessage: String {
        if query.isEmpty {
            return model.hasIndexedContent
                ? "Try a different folder or file type, or clear the filters."
                : "Add a folder and finish the local model setup. Lumina will make documents, images, media, and code searchable."
        }
        return hasActiveFilters
            ? "Try removing a filter. Semantic search can help when the exact words differ."
            : "Try fewer or broader words. If models are installed, semantic search also looks for related meaning."
    }

    private func resultHeadline(_ outcome: SearchOutcome) -> String {
        let count = outcome.hits.count
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return count == 0 ? "Recently indexed" : "\(count) recent file\(count == 1 ? "" : "s")"
        }
        return "\(count) file\(count == 1 ? "" : "s")"
    }

    // MARK: Actions

    private func applyPendingQuery() {
        guard let pending = model.pendingSearchQuery else { return }
        query = pending
        model.pendingSearchQuery = nil
    }

    private func openFirstResult() {
        guard let hit = selection ?? outcome?.hits.first else { return }
        model.showFileInLibrary(hit.file)
    }

    private func resetFilters() {
        kindGroup = .all
        selectedFolders.removeAll()
        dateWindow = .anyTime
        exactPhrase = false
    }

    private func runSearch() async {
        let keyAtStart = searchKey
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if outcome == nil || !trimmed.isEmpty {
            isSearching = true
        }
        let result = await model.search(query: query, filters: searchFilters)
        guard !Task.isCancelled, keyAtStart == searchKey else { return }
        outcome = result
        isSearching = false

        let previousFileID = selection?.file.id
        if let previousFileID,
           let updated = result.hits.first(where: { $0.file.id == previousFileID }) {
            selection = updated
        } else {
            selection = result.hits.first
        }
        if let selection {
            await loadPreview(selection)
        } else {
            previewChunks = []
            previewNotes = []
        }
    }

    private func loadPreview(_ hit: SearchHit) async {
        async let chunksTask = model.loadChunks(for: hit.file.id, limit: 80)
        async let notesTask = model.loadNotes(for: hit.file.id)
        let (chunks, notes) = await (chunksTask, notesTask)
        guard selection?.file.id == hit.file.id else { return }
        previewChunks = chunks
        previewNotes = notes
    }

    private func reloadNotes(fileID: Int64) async {
        previewNotes = await model.loadNotes(for: fileID)
    }
}

// MARK: - Result row

private struct SearchResultRow: View {
    let hit: SearchHit
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 11) {
                Rectangle()
                    .fill(isSelected ? Color.accentColor : .clear)
                    .frame(width: 2)
                    .clipShape(Capsule())

                FileThumbnailView(file: hit.file, cornerRadius: 7)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(hit.file.name)
                            .font(LuminaType.bodyEmphasis)
                            .foregroundStyle(Palette.label)
                            .lineLimit(1)
                        if hit.isExactNameMatch {
                            LuminaTag(title: "Name", icon: nil, tint: .accentColor, filled: true)
                        }
                        if hit.semanticScore != nil {
                            LuminaTag(title: "Semantic", icon: nil, tint: .accentColor, filled: false)
                        }
                        Spacer(minLength: 0)
                    }

                    HighlightedSnippet(text: hit.snippet)
                        .lineLimit(2)

                    HStack(spacing: 5) {
                        Text(hit.file.kind.displayName)
                        Text("·")
                        Text(hit.file.modifiedAt.luminaShortDate)
                        if let locator = hit.locator.compactDisplay {
                            Text("·")
                            Text(locator)
                        }
                        if hit.matchCount > 1 {
                            Text("·")
                            Text("\(hit.matchCount) passages")
                        }
                        Spacer(minLength: 0)
                    }
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.tertiary)
                    .lineLimit(1)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected
                        ? Color.accentColor.opacity(0.075)
                        : (isHovering ? Palette.separator.opacity(0.07) : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.18) : .clear, lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Preview

private struct SearchPreviewPane: View {
    @Environment(AppModel.self) private var model
    let hit: SearchHit
    let chunks: [StoredChunk]
    let notes: [UserNote]
    let onOpenInLibrary: () -> Void
    let onNoteAdded: () -> Void

    @State private var noteDraft = ""
    @State private var isSavingNote = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                fileHeader
                bestPassage
                if !otherPassages.isEmpty {
                    otherPassagesSection
                }
                metadata
                notesSection
                actions
            }
            .padding(20)
        }
    }

    private var fileHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 11) {
                FileThumbnailView(file: hit.file, cornerRadius: 8)
                    .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text(hit.file.name)
                        .font(LuminaType.bodyEmphasis)
                        .foregroundStyle(Palette.label)
                        .lineLimit(2)
                    Text("\(hit.file.kind.displayName) · \(hit.file.fileSize.luminaByteSize)")
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.secondary)
                    Text(hit.file.modifiedAt.luminaShortDate + " · " + (folderName ?? "Library"))
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 7) {
                Button {
                    FileActions.open(hit.file)
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.primaryAction)

                Button {
                    FileActions.reveal(hit.file)
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.secondaryAction)
                .help("Reveal in Finder")
            }
        }
    }

    private var bestPassage: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                SectionLabel(text: hit.locator.displayText == nil ? "Best passage" : "Best passage · \(hit.locator.displayText ?? "")")
                Spacer()
                if let semantic = hit.semanticScore {
                    Text("cosine \(String(format: "%.2f", semantic))")
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.tertiary)
                        .monospacedDigit()
                }
            }
            Text(hit.fullText.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(LuminaType.body)
                .foregroundStyle(Palette.label)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Palette.separator.opacity(0.45), lineWidth: 0.7)
        )
    }

    private var otherPassages: [StoredChunk] {
        chunks
            .filter { $0.chunkID != hit.id && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(4)
            .map { $0 }
    }

    private var otherPassagesSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: "More extracted passages")
            VStack(spacing: 0) {
                ForEach(Array(otherPassages.enumerated()), id: \.element.chunkID) { index, chunk in
                    if index > 0 { Hairline() }
                    VStack(alignment: .leading, spacing: 3) {
                        if let locator = chunk.locator.displayText {
                            Text(locator)
                                .font(LuminaType.captionEmphasis)
                                .foregroundStyle(Palette.tertiary)
                        }
                        Text(chunk.text.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(LuminaType.caption)
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(4)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.raised.opacity(0.55))
            )
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: "Metadata")
            VStack(alignment: .leading, spacing: 5) {
                MetadataRow(label: "Path", value: hit.file.path)
                MetadataRow(label: "Modified", value: hit.file.modifiedAt.luminaFullDate)
                MetadataRow(label: "Indexed", value: hit.file.indexedAt.luminaFullDate)
                MetadataRow(label: "Passages", value: "\(hit.file.chunkCount)")
                if let pageCount = hit.file.pageCount {
                    MetadataRow(label: "Pages", value: "\(pageCount)")
                }
                if let duration = hit.file.duration {
                    MetadataRow(label: "Duration", value: ContentLocator.timecode(duration))
                }
                MetadataRow(label: "Vectors", value: hit.file.hasEmbeddings ? "Complete" : "Keyword only")
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Private notes")
                Spacer()
                if !notes.isEmpty {
                    Text("\(notes.count)")
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.tertiary)
                }
            }

            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(notes.prefix(3)) { note in
                        Text(note.text)
                            .font(LuminaType.caption)
                            .foregroundStyle(Palette.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }

            HStack(spacing: 6) {
                TextField("Add a note…", text: $noteDraft)
                    .textFieldStyle(.plain)
                    .font(LuminaType.caption)
                    .onSubmit { saveNote() }
                Button {
                    saveNote()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Palette.tertiary : Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingNote)
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Palette.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Palette.separator.opacity(0.5), lineWidth: 0.7)
            )
        }
    }

    private var actions: some View {
        VStack(spacing: 7) {
            Button(action: onOpenInLibrary) {
                Label("Open in Library", systemImage: "square.grid.2x2")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.secondaryAction)

            Text("Search preview shows the exact passages stored in Lumina's local index.")
                .font(LuminaType.caption)
                .foregroundStyle(Palette.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private var folderName: String? {
        guard let id = hit.file.folderID else { return nil }
        return model.folders.first { $0.id == id }?.name
    }

    private func saveNote() {
        let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSavingNote = true
        Task {
            let saved = await model.addNote(text: trimmed, fileID: hit.file.id)
            isSavingNote = false
            if saved {
                noteDraft = ""
                onNoteAdded()
            }
        }
    }
}

// MARK: - Filters

private enum SearchDateWindow: String, CaseIterable, Identifiable {
    case anyTime
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anyTime: "Any time"
        case .week: "Last 7 days"
        case .month: "Last 30 days"
        case .year: "Last year"
        }
    }

    var dateFrom: Date? {
        let calendar = Calendar.current
        switch self {
        case .anyTime: return nil
        case .week: return calendar.date(byAdding: .day, value: -7, to: Date())
        case .month: return calendar.date(byAdding: .day, value: -30, to: Date())
        case .year: return calendar.date(byAdding: .year, value: -1, to: Date())
        }
    }
}

private struct FilterChip: View {
    let icon: String
    let title: String
    var isActive: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .medium))
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
                .opacity(0.55)
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
