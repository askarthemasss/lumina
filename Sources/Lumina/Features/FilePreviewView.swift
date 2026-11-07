import AppKit
import PDFKit
import SwiftUI

struct FilePreviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    let file: IndexedFile

    @State private var currentFile: IndexedFile
    @State private var chunks: [StoredChunk] = []
    @State private var notes: [UserNote] = []
    @State private var noteDraft = ""
    @State private var isPinned: Bool
    @State private var isLoading = true
    @State private var isSavingNote = false

    init(file: IndexedFile) {
        self.file = file
        _currentFile = State(initialValue: file)
        _isPinned = State(initialValue: file.isPinned)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            HStack(spacing: 0) {
                FilePreviewCanvas(file: currentFile, chunks: chunks, isLoading: isLoading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle()
                    .fill(Palette.separator.opacity(0.55))
                    .frame(width: 0.7)
                sidebar
                    .frame(width: 322)
            }
        }
        .frame(minWidth: 920, idealWidth: 1_040, minHeight: 620, idealHeight: 740)
        .background(Palette.canvas)
        .task {
            await reload()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 11) {
            FileThumbnailView(file: currentFile, cornerRadius: 6)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(currentFile.name)
                        .font(LuminaType.bodyEmphasis)
                        .foregroundStyle(Palette.label)
                        .lineLimit(1)
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8.5))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(currentFile.path)
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 12)

            HStack(spacing: 2) {
                PreviewIconButton(
                    icon: isPinned ? "pin.fill" : "pin",
                    help: isPinned ? "Unpin" : "Pin",
                    tint: isPinned ? .accentColor : Palette.secondary
                ) {
                    Task { await togglePin() }
                }
                PreviewIconButton(icon: "doc.on.doc", help: "Copy path") {
                    FileActions.copyPath(currentFile)
                }
                PreviewIconButton(icon: "folder", help: "Reveal in Finder") {
                    FileActions.reveal(currentFile)
                }
                PreviewIconButton(icon: "arrow.up.forward.app", help: "Open in default app") {
                    FileActions.open(currentFile)
                }
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Palette.separator.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close")
            .padding(.leading, 4)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !FileManager.default.fileExists(atPath: currentFile.path) {
                    InlineNotice(
                        text: "The original file is no longer at this path. Extracted passages and notes remain available.",
                        tone: .warning
                    )
                }

                if let errorMessage = currentFile.errorMessage {
                    InlineNotice(text: errorMessage, tone: .warning)
                }

                metadata
                notesSection
                if !chunks.isEmpty {
                    passageSection
                }
            }
            .padding(17)
        }
        .background(Palette.sidebar.opacity(0.45))
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Details")
            VStack(alignment: .leading, spacing: 5) {
                MetadataRow(label: "Type", value: currentFile.kind.displayName)
                MetadataRow(label: "Size", value: currentFile.fileSize.luminaByteSize)
                MetadataRow(label: "Modified", value: currentFile.modifiedAt.luminaFullDate)
                MetadataRow(label: "Indexed", value: currentFile.indexedAt.luminaFullDate)
                MetadataRow(label: "Passages", value: "\(currentFile.chunkCount)")
                if let pageCount = currentFile.pageCount {
                    MetadataRow(label: "Pages", value: "\(pageCount)")
                }
                if let duration = currentFile.duration {
                    MetadataRow(label: "Duration", value: ContentLocator.timecode(duration))
                }
                MetadataRow(label: "Vectors", value: currentFile.hasEmbeddings ? "Complete" : "Keyword only")
                if let folderName {
                    MetadataRow(label: "Folder", value: folderName)
                }
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

            if notes.isEmpty {
                Text("Notes are stored in Lumina's local database, never attached to the original file.")
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(notes) { note in
                        HStack(alignment: .top, spacing: 6) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.text)
                                    .font(LuminaType.caption)
                                    .foregroundStyle(Palette.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                                Text(note.createdAt.luminaRelative)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(Palette.tertiary)
                            }
                            Spacer(minLength: 0)
                            Button {
                                Task {
                                    await model.deleteNote(id: note.id)
                                    notes = await model.loadNotes(for: currentFile.id)
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Palette.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help("Delete note")
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Palette.card)
                        )
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
            .frame(height: 31)
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

    private var passageSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(chunks.prefix(3)), id: \.chunkID) { chunk in
                    VStack(alignment: .leading, spacing: 2) {
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
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Palette.card)
                    )
                }
                if chunks.count > 3 {
                    Text("+ \(chunks.count - 3) more passages in the index")
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.tertiary)
                }
            }
            .padding(.top, 6)
        } label: {
            HStack {
                SectionLabel(text: "Indexed passages")
                Spacer()
                Text("\(chunks.count)")
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.tertiary)
            }
        }
        .font(LuminaType.caption)
        .foregroundStyle(Palette.secondary)
    }

    private var folderName: String? {
        guard let id = currentFile.folderID else { return nil }
        return model.folders.first { $0.id == id }?.name
    }

    // MARK: Actions

    private func reload() async {
        isLoading = true
        async let chunksTask = model.loadChunks(for: file.id)
        async let notesTask = model.loadNotes(for: file.id)
        let fetchedChunks = await chunksTask
        let fetchedNotes = await notesTask
        if let fresh = await model.loadFile(id: file.id) {
            currentFile = fresh
            isPinned = fresh.isPinned
        }
        chunks = fetchedChunks
        notes = fetchedNotes
        isLoading = false
    }

    private func togglePin() async {
        let pinned = await model.togglePin(fileID: currentFile.id)
        isPinned = pinned
        if let fresh = await model.loadFile(id: currentFile.id) {
            currentFile = fresh
        }
    }

    private func saveNote() {
        let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSavingNote = true
        Task {
            let saved = await model.addNote(text: trimmed, fileID: currentFile.id)
            isSavingNote = false
            if saved {
                noteDraft = ""
                notes = await model.loadNotes(for: currentFile.id)
            }
        }
    }
}

// MARK: - Preview canvas

private struct FilePreviewCanvas: View {
    let file: IndexedFile
    let chunks: [StoredChunk]
    let isLoading: Bool

    var body: some View {
        ZStack {
            Palette.separator.opacity(0.035)

            if isLoading {
                ProgressView()
            } else {
                switch file.kind {
                case .image:
                    LargeImagePreview(file: file)
                        .padding(22)
                case .pdf:
                    if FileManager.default.fileExists(atPath: file.path) {
                        PDFPreviewView(url: file.url)
                            .padding(14)
                    } else {
                        extractedText
                    }
                case .audio, .video:
                    mediaPreview
                case .text, .code, .document, .spreadsheet, .presentation:
                    extractedText
                }
            }
        }
    }

    private var extractedText: some View {
        Group {
            if chunks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: file.kind.systemImage)
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Palette.tertiary)
                    Text("No extracted text")
                        .font(LuminaType.sectionTitle)
                        .foregroundStyle(Palette.label)
                    Text("This file has metadata in the index but no searchable passages. Open it in its original app to read the content.")
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                    Button {
                        FileActions.open(file)
                    } label: {
                        Label("Open File", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.secondaryAction)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 17) {
                        HStack {
                            SectionLabel(text: file.kind == .code ? "Extracted code" : "Extracted text")
                            Spacer()
                            Text("\(chunks.count) passage\(chunks.count == 1 ? "" : "s")")
                                .font(LuminaType.caption)
                                .foregroundStyle(Palette.tertiary)
                        }

                        ForEach(chunks, id: \.chunkID) { chunk in
                            VStack(alignment: .leading, spacing: 5) {
                                if let locator = chunk.locator.displayText {
                                    Text(locator)
                                        .font(LuminaType.captionEmphasis)
                                        .foregroundStyle(Palette.tertiary)
                                }
                                Text(chunk.text.trimmingCharacters(in: .whitespacesAndNewlines))
                                    .font(file.kind == .code
                                        ? .system(size: 11.5, design: .monospaced)
                                        : LuminaType.body)
                                    .foregroundStyle(Palette.label)
                                    .lineSpacing(3)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(13)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Palette.card)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(Palette.separator.opacity(0.4), lineWidth: 0.7)
                            )
                        }
                    }
                    .padding(22)
                    .frame(maxWidth: 780)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var mediaPreview: some View {
        VStack(spacing: 15) {
            Group {
                if let thumbnail = file.thumbnailPath,
                   FileManager.default.fileExists(atPath: thumbnail),
                   let image = NSImage(contentsOfFile: thumbnail) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 340)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Image(systemName: file.kind.systemImage)
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(Palette.tertiary)
                        .frame(width: 98, height: 98)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Palette.separator.opacity(0.1))
                        )
                }
            }

            VStack(spacing: 4) {
                Text(file.name)
                    .font(LuminaType.sectionTitle)
                    .foregroundStyle(Palette.label)
                if let duration = file.duration {
                    Text("\(file.kind.displayName) · \(ContentLocator.timecode(duration))")
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.secondary)
                }
            }

            if chunks.isEmpty {
                Text("Audio and video stay in their original files. Enable transcription in Settings → Indexing to make speech searchable on-device.")
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 390)
            } else {
                Text("\(chunks.count) indexed passages include frame descriptions\(chunks.contains { $0.locator.timeStart != nil } ? " and timestamps" : ""). Open the file in its default player to watch or listen.")
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 390)
            }

            Button {
                FileActions.open(file)
            } label: {
                Label("Open \(file.kind.displayName)", systemImage: "play.rectangle")
            }
            .buttonStyle(.primaryAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

// MARK: - Large image

private struct LargeImagePreview: View {
    let file: IndexedFile
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Palette.tertiary)
                    Text(FileManager.default.fileExists(atPath: file.path)
                        ? "Preview unavailable"
                        : "Original image not found")
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.secondary)
                }
            }
        }
        .task(id: file.id) {
            image = nil
            if let path = file.thumbnailPath,
               FileManager.default.fileExists(atPath: path),
               let loaded = NSImage(contentsOfFile: path) {
                image = loaded
            } else if FileManager.default.fileExists(atPath: file.path) {
                image = NSImage(contentsOfFile: file.path)
            }
        }
    }
}

// MARK: - PDF

private struct PDFPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.pageShadowsEnabled = false
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}

// MARK: - Buttons

private struct PreviewIconButton: View {
    let icon: String
    let help: String
    var tint: Color = Palette.secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 27, height: 27)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
