import SwiftUI

struct TimelineView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    @State private var filter: TimelineFilter = .all
    @State private var noteDraft = ""
    @State private var isSavingNote = false
    @FocusState private var noteFocused: Bool

    var body: some View {
        ScreenScroll(maxWidth: 940) {
            PageHeader(
                eyebrow: "Your history",
                title: "Timeline",
                subtitle: "Indexed files, pinned material, private notes, and conversations in one local record."
            ) {
                Button {
                    model.newConversation(mode: .answer)
                    model.route = .chat
                } label: {
                    Label("Ask Lumina", systemImage: "text.bubble")
                }
                .buttonStyle(.secondaryAction)
            }

            noteComposer

            HStack {
                Picker("Filter", selection: $filter) {
                    ForEach(TimelineFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 430)

                Spacer()

                Text("\(filteredItems.count) event\(filteredItems.count == 1 ? "" : "s")")
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.tertiary)
            }

            if filteredItems.isEmpty {
                EmptyStateView(
                    icon: "clock",
                    title: emptyTitle,
                    message: emptyMessage
                )
                .frame(minHeight: 300)
                .luminaCard(padding: 0)
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(groups, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(group.day.luminaDayHeader)
                                    .font(LuminaType.sectionTitle)
                                    .foregroundStyle(Palette.label)
                                Text("\(group.items.count)")
                                    .font(LuminaType.caption)
                                    .foregroundStyle(Palette.tertiary)
                                Spacer()
                            }
                            VStack(spacing: 0) {
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                    if index > 0 {
                                        Hairline().padding(.leading, 55)
                                    }
                                    TimelineRow(
                                        item: item,
                                        noteText: noteText(for: item),
                                        action: { open(item) }
                                    )
                                    .contextMenu {
                                        contextMenu(for: item)
                                    }
                                }
                            }
                            .luminaCard(padding: 0)
                        }
                    }
                }
            }

            Text("The timeline is generated from Lumina's own database. Deleting the index removes these events; your original files are untouched.")
                .font(LuminaType.caption)
                .foregroundStyle(Palette.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
        }
        .background(Palette.canvas)
        .task {
            await model.refreshTimeline()
        }
    }

    // MARK: Note composer

    private var noteComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                IconTile(systemImage: "note.text", size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add a private note")
                        .font(LuminaType.bodyEmphasis)
                        .foregroundStyle(Palette.label)
                    Text("Notes are searchable in the timeline and attached to this Mac only.")
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.secondary)
                }
                Spacer()
            }

            ZStack(alignment: .topLeading) {
                if noteDraft.isEmpty {
                    Text("A thought, a decision, a reminder…")
                        .font(LuminaType.body)
                        .foregroundStyle(Palette.tertiary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $noteDraft)
                    .font(LuminaType.body)
                    .scrollContentBackground(.hidden)
                    .focused($noteFocused)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .frame(minHeight: 54, maxHeight: 96)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(noteFocused ? Color.accentColor.opacity(0.5) : Palette.separator.opacity(0.5),
                                  lineWidth: noteFocused ? 1 : 0.7)
            )

            HStack {
                Text("⌘↩ to save")
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.tertiary)
                Spacer()
                Button {
                    saveNote()
                } label: {
                    Label("Add Note", systemImage: "plus")
                }
                .buttonStyle(.primaryAction)
                .disabled(noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingNote)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .luminaCard(padding: 15)
    }

    // MARK: Derived

    private var filteredItems: [TimelineItem] {
        switch filter {
        case .all:
            return model.timelineItems
        case .files:
            return model.timelineItems.filter { $0.kind == .indexed || $0.kind == .pinned }
        case .notes:
            return model.timelineItems.filter { $0.kind == .note }
        case .conversations:
            return model.timelineItems.filter { $0.kind == .conversation }
        case .pinned:
            return model.timelineItems.filter(\.isPinned)
        }
    }

    private var groups: [(day: Date, items: [TimelineItem])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredItems) {
            calendar.startOfDay(for: $0.date)
        }
        return grouped
            .map { (day: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    private var emptyTitle: String {
        switch filter {
        case .all: "Nothing here yet"
        case .files: "No indexed files"
        case .notes: "No notes yet"
        case .conversations: "No conversations yet"
        case .pinned: "Nothing pinned"
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .all:
            "Index a folder, ask a question, or write a note. The timeline records activity without sending anything anywhere."
        case .files:
            "Start an index run in the Library to see files appear here."
        case .notes:
            "Use the note field above, or attach a note to any file from its preview."
        case .conversations:
            "Ask Lumina a question to start a grounded conversation."
        case .pinned:
            "Pin important files from the Library or a file preview to keep them close."
        }
    }

    // MARK: Actions

    private func noteText(for item: TimelineItem) -> String? {
        guard item.kind == .note, let noteID = item.noteID else { return nil }
        return model.notes.first { $0.id == noteID }?.text
    }

    private func open(_ item: TimelineItem) {
        switch item.kind {
        case .indexed, .pinned:
            if let file = item.file {
                model.showFileInLibrary(file)
            }
        case .conversation:
            guard let id = item.conversationID else { return }
            Task {
                if let conversation = model.conversations.first(where: { $0.id == id }) {
                    await model.selectConversation(conversation)
                }
                model.route = .chat
            }
        case .note:
            if let file = item.file {
                model.showFileInLibrary(file)
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for item: TimelineItem) -> some View {
        if let file = item.file {
            Button("Preview") { model.showFileInLibrary(file) }
            Button("Open") { FileActions.open(file) }
            Button("Reveal in Finder") { FileActions.reveal(file) }
            Divider()
            Button(file.isPinned ? "Unpin" : "Pin") {
                Task {
                    _ = await model.togglePin(fileID: file.id)
                    await model.refreshTimeline()
                }
            }
            Button("Copy Path") { FileActions.copyPath(file) }
        } else if item.kind == .note, let noteID = item.noteID {
            Button("Delete Note", role: .destructive) {
                Task {
                    await model.deleteNote(id: noteID)
                }
            }
        } else if item.kind == .conversation {
            Button("Open Conversation") { open(item) }
        }
    }

    private func saveNote() {
        let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSavingNote = true
        Task {
            let saved = await model.addNote(text: trimmed)
            isSavingNote = false
            if saved {
                noteDraft = ""
            }
        }
    }
}

// MARK: - Row

private struct TimelineRow: View {
    let item: TimelineItem
    let noteText: String?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 11) {
                icon
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(item.title)
                            .font(LuminaType.bodyEmphasis)
                            .foregroundStyle(Palette.label)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if item.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.accentColor)
                        }
                    }

                    if let noteText {
                        Text(noteText)
                            .font(LuminaType.caption)
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text(item.subtitle)
                            .font(LuminaType.caption)
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(item.date.formatted(date: .omitted, time: .shortened))
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.tertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .background(isHovering ? Palette.separator.opacity(0.06) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(item.isPinned ? Color.accentColor.opacity(0.1) : Palette.separator.opacity(0.1))
                .frame(width: 29, height: 29)
            Image(systemName: item.kind.systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(item.isPinned ? Color.accentColor : Palette.secondary)
        }
        .padding(.top, 1)
    }
}

// MARK: - Filter

private enum TimelineFilter: String, CaseIterable, Identifiable {
    case all
    case files
    case notes
    case conversations
    case pinned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .files: "Files"
        case .notes: "Notes"
        case .conversations: "Asks"
        case .pinned: "Pinned"
        }
    }
}
