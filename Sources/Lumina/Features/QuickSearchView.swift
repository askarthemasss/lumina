import SwiftUI

struct QuickSearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    let onClose: () -> Void

    @State private var query = ""
    @State private var entries: [QuickEntry] = []
    @State private var isSearching = false
    @State private var selectedIndex = 0
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            Hairline()
            results
            Hairline()
            footer
        }
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Palette.canvas)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Palette.separator.opacity(0.7), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .shadow(color: .black.opacity(0.24), radius: 28, y: 12)
        .padding(10)
        .tint(settings.accent.color)
        .accentColor(settings.accent.color)
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(70))
                fieldFocused = true
            }
        }
        .onExitCommand(perform: onClose)
        .onKeyPress(.downArrow) {
            moveSelection(1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveSelection(-1)
            return .handled
        }
        .onKeyPress(.return) {
            openSelected()
            return .handled
        }
        .task(id: query) {
            await runSearch()
        }
    }

    // MARK: Header

    private var searchHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.accentColor)

            TextField("Search your local library", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundStyle(Palette.label)
                .focused($fieldFocused)

            if isSearching {
                ProgressView().controlSize(.mini)
            }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.tertiary)
                }
                .buttonStyle(.plain)
            }

            KeyCap(label: "esc")
        }
        .padding(.horizontal, 18)
        .frame(height: 55)
    }

    // MARK: Results

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if !query.isEmpty {
                        HStack {
                            Text(isSearching ? "Searching…" : "\(entries.count) result\(entries.count == 1 ? "" : "s")")
                                .font(LuminaType.captionEmphasis)
                                .foregroundStyle(Palette.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                    } else {
                        HStack {
                            SectionLabel(text: "Recently indexed")
                            Spacer()
                            Text("Type to search everything")
                                .font(LuminaType.caption)
                                .foregroundStyle(Palette.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                    }

                    if entries.isEmpty && !isSearching {
                        quickEmptyState
                    } else {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            QuickResultRow(
                                entry: entry,
                                isSelected: index == selectedIndex
                            ) {
                                selectedIndex = index
                                open(entry)
                            }
                            .id(index)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
            .frame(maxHeight: 372)
            .onChange(of: selectedIndex) { _, newValue in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var quickEmptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: query.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(size: 21, weight: .light))
                .foregroundStyle(Palette.tertiary)
            Text(query.isEmpty ? "Nothing indexed yet" : "No matches")
                .font(LuminaType.bodyEmphasis)
                .foregroundStyle(Palette.label)
            Text(query.isEmpty
                ? "Add a folder in the main window and start an index run."
                : "Try fewer words or open the full Search view for filters.")
                .font(LuminaType.caption)
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 46)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                KeyCap(label: "↑↓")
                Text("Navigate")
            }
            HStack(spacing: 4) {
                KeyCap(label: "↵")
                Text("Open")
            }
            HStack(spacing: 4) {
                KeyCap(label: "esc")
                Text("Close")
            }
            .foregroundStyle(Palette.tertiary)

            Spacer()

            if !query.isEmpty {
                Button("See all results") {
                    model.showAllResults(for: query)
                    onClose()
                }
                .buttonStyle(.quietAction)
            }

            HStack(spacing: 5) {
                Image(systemName: "lock")
                    .font(.system(size: 8.5, weight: .semibold))
                Text("On this Mac")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(Palette.tertiary)
        }
        .font(LuminaType.caption)
        .foregroundStyle(Palette.secondary)
        .padding(.horizontal, 16)
        .frame(height: 39)
    }

    // MARK: Search

    private func runSearch() async {
        let activeQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if activeQuery.isEmpty {
            isSearching = false
            if model.recentFiles.isEmpty {
                await model.refreshLibrary()
            }
            entries = model.recentFiles.prefix(9).map { file in
                QuickEntry(
                    id: file.id,
                    file: file,
                    snippet: "\(file.kind.displayName) · \(file.chunkCount) passage\(file.chunkCount == 1 ? "" : "s")",
                    locator: nil,
                    semantic: false,
                    nameMatch: false
                )
            }
            selectedIndex = min(selectedIndex, max(0, entries.count - 1))
            return
        }

        isSearching = true
        try? await Task.sleep(for: .milliseconds(160))
        guard !Task.isCancelled else { return }
        let result = await model.search(
            query: activeQuery,
            filters: SearchFilters(),
            limit: 9
        )
        guard !Task.isCancelled, query.trimmingCharacters(in: .whitespacesAndNewlines) == activeQuery else {
            return
        }
        entries = result.hits.map { hit in
            QuickEntry(
                id: hit.file.id,
                file: hit.file,
                snippet: hit.snippet,
                locator: hit.locator.displayText,
                semantic: hit.semanticScore != nil,
                nameMatch: hit.isExactNameMatch
            )
        }
        selectedIndex = 0
        isSearching = false
    }

    private func moveSelection(_ delta: Int) {
        guard !entries.isEmpty else { return }
        selectedIndex = min(max(0, selectedIndex + delta), entries.count - 1)
    }

    private func openSelected() {
        guard entries.indices.contains(selectedIndex) else { return }
        open(entries[selectedIndex])
    }

    private func open(_ entry: QuickEntry) {
        model.showFileInLibrary(entry.file)
        onClose()
    }
}

// MARK: - Quick result

private struct QuickEntry: Identifiable {
    let id: Int64
    let file: IndexedFile
    let snippet: String
    let locator: String?
    let semantic: Bool
    let nameMatch: Bool
}

private struct QuickResultRow: View {
    let entry: QuickEntry
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                FileThumbnailView(file: entry.file, cornerRadius: 6)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.file.name)
                            .font(LuminaType.bodyEmphasis)
                            .foregroundStyle(Palette.label)
                            .lineLimit(1)
                        if entry.nameMatch {
                            LuminaTag(title: "Name", icon: nil, tint: .accentColor, filled: false)
                        }
                        if entry.semantic {
                            LuminaTag(title: "Semantic", icon: nil, tint: .accentColor, filled: false)
                        }
                    }
                    if entry.snippet.contains("[[") {
                        HighlightedSnippet(text: entry.snippet)
                            .font(LuminaType.caption)
                            .lineLimit(1)
                    } else {
                        Text(entry.snippet)
                            .font(LuminaType.caption)
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(entry.file.kind.displayName)
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.tertiary)
                    if let locator = entry.locator {
                        Text(locator)
                            .font(LuminaType.caption)
                            .foregroundStyle(Palette.tertiary)
                    } else {
                        Text(entry.file.modifiedAt.luminaShortDate)
                            .font(LuminaType.caption)
                            .foregroundStyle(Palette.tertiary)
                    }
                }

                if isSelected {
                    Image(systemName: "return")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 16)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected
                        ? Color.accentColor.opacity(0.09)
                        : (isHovering ? Palette.separator.opacity(0.06) : .clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
