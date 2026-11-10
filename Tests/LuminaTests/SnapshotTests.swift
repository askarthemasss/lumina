import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Lumina

/// Renders the shipping SwiftUI hierarchy offscreen with a synthetic library.
/// Screen capture requires macOS Screen Recording permission, which CI and
/// sandboxed terminals do not have; this produces the same views without it.
/// Run with:
///   LUMINA_RENDER_SNAPSHOTS=1 ./scripts/test.sh
@Suite(
    "Documentation snapshots",
    .enabled(if: ProcessInfo.processInfo.environment["LUMINA_RENDER_SNAPSHOTS"] == "1")
)
struct DocumentationSnapshotTests {
    @Test("Render the README screenshots")
    @MainActor
    func rendersReadmeScreenshots() async throws {
        let fixture = try await SnapshotFixture.make()
        defer { fixture.cleanUp() }

        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        try await fixture.capture(route: .home, to: output.appendingPathComponent("home.png"))

        fixture.model.pendingSearchQuery = "survey station 4A"
        try await fixture.capture(route: .search, to: output.appendingPathComponent("search.png"))

        if let conversation = fixture.model.conversations.first(where: {
            $0.title.hasPrefix("What did the keeper record")
        }) {
            await fixture.model.selectConversation(conversation)
        }
        try await fixture.capture(route: .chat, to: output.appendingPathComponent("chat.png"))

        try await fixture.capture(route: .library, to: output.appendingPathComponent("library.png"))
        try await fixture.capture(route: .timeline, to: output.appendingPathComponent("timeline.png"))
        try await fixture.capture(route: .settings, to: output.appendingPathComponent("settings.png"))

        let files = try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "png" }
        #expect(files.count >= 6)
    }
}

// MARK: - Fixture

@MainActor
private final class SnapshotFixture {
    let root: URL
    let model: AppModel
    private let defaults: UserDefaults
    private let defaultsSuite: String

    private init(root: URL, model: AppModel, defaults: UserDefaults, defaultsSuite: String) {
        self.root = root
        self.model = model
        self.defaults = defaults
        self.defaultsSuite = defaultsSuite
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: defaultsSuite)
        try? FileManager.default.removeItem(at: root)
    }

    static func make() async throws -> SnapshotFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LuminaSnapshots-\(UUID().uuidString)", isDirectory: true)
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let thumbnails = support.appendingPathComponent("thumbnails", isDirectory: true)
        let demoPath = "/Users/demo/Documents/Lumina Demo"
        try FileManager.default.createDirectory(at: thumbnails, withIntermediateDirectories: true)

        let defaultsSuite = "com.lumina.snapshots.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsSuite))
        let settings = AppSettings(defaults: defaults)
        settings.endpoint = "http://127.0.0.1:11434"
        settings.runtimeKind = .ollama
        settings.embeddingModel = "embeddinggemma"
        settings.chatModel = "gemma4:e2b-it-qat"
        settings.appearance = .light
        settings.accent = .sapphire
        settings.autoIndexEnabled = true

        let store = try IndexStore(databaseURL: support.appendingPathComponent("lumina.sqlite"))
        let folder = try await store.addFolder(path: demoPath, bookmark: nil)

        let documents = demoDocuments()
        var texts: [String] = []
        for document in documents {
            texts.append(contentsOf: document.chunks.map(\.text))
        }

        var embeddings: [[Float]] = []
        if let client = try? LocalInferenceClient(configuration: settings.inferenceConfiguration) {
            embeddings = (try? await client.embed(texts: texts, model: settings.embeddingModel)) ?? []
        }
        if embeddings.count != texts.count {
            embeddings = []
        }

        var fileIDs: [String: Int64] = [:]
        var chunkIDs: [String: Int64] = [:]
        var offset = 0
        for (index, document) in documents.enumerated() {
            let thumbnail = thumbnails.appendingPathComponent("\(document.slug).png")
            try drawThumbnail(document.thumbnail, to: thumbnail)
            var chunks: [ChunkWriteInput] = []
            for (chunkIndex, chunk) in document.chunks.enumerated() {
                let embedding = embeddings.isEmpty ? nil : embeddings[offset]
                chunks.append(ChunkWriteInput(
                    index: chunkIndex,
                    text: chunk.text,
                    locator: chunk.locator,
                    embedding: embedding
                ))
                offset += 1
            }
            let modified = Date().addingTimeInterval(-Double(document.ageDays) * 86_400)
            let id = try await store.saveFile(
                FileWriteInput(
                    folderID: folder.id,
                    path: "\(demoPath)/\(document.name)",
                    name: document.name,
                    kind: document.kind,
                    fileSize: document.size,
                    modifiedAt: modified,
                    pageCount: document.pageCount,
                    duration: document.duration,
                    thumbnailPath: thumbnail.path,
                    featurePrint: nil,
                    embeddingModel: embeddings.isEmpty ? nil : settings.embeddingModel
                ),
                chunks: chunks
            )
            fileIDs[document.name] = id
            for chunk in document.chunks {
                if let localID = chunk.localID {
                    chunkIDs[localID] = id
                }
            }
            _ = index
        }

        for name in ["Lighthouse Keepers Log.txt", "Aurora Field Notes.md", "Harbor at Dawn.jpg"] {
            if let id = fileIDs[name] {
                _ = try await store.togglePin(fileID: id)
            }
        }

        _ = try await store.addNote(
            fileID: fileIDs["Lighthouse Keepers Log.txt"],
            text: "Ask the harbormaster whether the outer buoy light was working during the October fog."
        )
        _ = try await store.addNote(
            fileID: fileIDs["Aurora Field Notes.md"],
            text: "Print the 24 mm exposures for the field journal. Keep the unedited frames too."
        )
        _ = try await store.addNote(
            fileID: nil,
            text: "Decide whether the survey recommendation should move Station 4A before the spring tide."
        )

        let conversation = try await store.createConversation(
            mode: .answer,
            title: "What did the keeper record about the fog?"
        )
        _ = try await store.appendMessage(
            conversationID: conversation.id,
            role: .user,
            content: "What did the keeper record about the fog, and which ship passed the lighthouse?"
        )

        let lighthouseCitation = Citation(
            chunkID: 1,
            fileID: fileIDs["Lighthouse Keepers Log.txt"] ?? 0,
            fileName: "Lighthouse Keepers Log.txt",
            filePath: "\(demoPath)/Lighthouse Keepers Log.txt",
            kind: .text,
            locator: ContentLocator(line: 4),
            quote: "Fog closed in at 04:10. Visibility under 200 meters. The Aurora passed the outer buoy at 05:35.",
            relevance: 0.92
        )
        let surveyCitation = Citation(
            chunkID: 2,
            fileID: fileIDs["Coastal Survey 2026.pdf"] ?? 0,
            fileName: "Coastal Survey 2026.pdf",
            filePath: "\(demoPath)/Coastal Survey 2026.pdf",
            kind: .pdf,
            locator: ContentLocator(page: 2),
            quote: "The shoreline between Gull Point and the outer buoy shifted west by 6.3 meters since the 2023 survey.",
            relevance: 0.81
        )
        _ = try await store.appendMessage(
            conversationID: conversation.id,
            role: .assistant,
            content: """
            The keeper recorded two passages about fog that bear on the same night.

            - On **Tuesday 14**, fog closed in at **04:10**, with visibility under **200 meters** [1].
            - The ship **Aurora** passed the outer buoy at **05:35** and sounded three long blasts [1].
            - The **Coastal Survey 2026** later measured the shoreline west of Gull Point moving **6.3 meters** since 2023, which may explain the shifted channel near the buoy [2].

            The log does not say whether the buoy light itself was obscured, only that the vessel sounded signals in the fog.
            """,
            citations: [lighthouseCitation, surveyCitation]
        )

        let tideCitation = Citation(
            chunkID: 3,
            fileID: fileIDs["Tide Tables.csv"] ?? 0,
            fileName: "Tide Tables.csv",
            filePath: "\(demoPath)/Tide Tables.csv",
            kind: .spreadsheet,
            locator: ContentLocator(line: 4),
            quote: "2026-11-01,06:12,00:04,18:37,12:20",
            relevance: 0.76
        )
        _ = try await store.appendMessage(
            conversationID: conversation.id,
            role: .user,
            content: "Did the tide tables support that timing?"
        )
        _ = try await store.appendMessage(
            conversationID: conversation.id,
            role: .assistant,
            content: """
            The November table shows high water at **06:12** on 1 November and **06:55** on 2 November [1]. The keeper's 06:12 reading matches the first high tide, putting the fog entry and the Aurora's passage in the same tidal window [2].
            """,
            citations: [tideCitation, lighthouseCitation]
        )

        let summary = try await store.createConversation(
            mode: .summarize,
            title: "Summarize the coastal survey"
        )
        _ = try await store.appendMessage(
            conversationID: summary.id,
            role: .user,
            content: "Summarize the survey findings for the spring planning meeting."
        )
        _ = try await store.appendMessage(
            conversationID: summary.id,
            role: .assistant,
            content: "The shoreline moved west by 6.3 meters since 2023 [1]. The report recommends moving the Station 4A marker inland by eight meters before spring [1].",
            citations: [surveyCitation]
        )

        let comparison = try await store.createConversation(
            mode: .compare,
            title: "Compare the survey and tide tables"
        )
        _ = try await store.appendMessage(
            conversationID: comparison.id,
            role: .user,
            content: "Compare the survey recommendation with the November tide tables."
        )
        _ = try await store.appendMessage(
            conversationID: comparison.id,
            role: .assistant,
            content: "The survey recommends an eight-meter inland move at Station 4A [1]. The November high tides around 06:00–07:30 are the practical constraint for doing that work [2].",
            citations: [surveyCitation]
        )

        for (index, name) in documents.enumerated() {
            guard let id = fileIDs[name.name] else { continue }
            let indexed = Date().addingTimeInterval(-Double(index) * 10_800)
            try update(
                databaseURL: support.appendingPathComponent("lumina.sqlite"),
                sql: "UPDATE files SET indexed_at = \(indexed.timeIntervalSince1970) WHERE id = \(id)"
            )
        }

        let noteIDs = try await store.notes(limit: 10).map(\.id)
        for (index, id) in noteIDs.enumerated() {
            let date = Date().addingTimeInterval(-Double(index) * 86_400 * 0.4)
            try update(
                databaseURL: support.appendingPathComponent("lumina.sqlite"),
                sql: "UPDATE notes SET created_at = \(date.timeIntervalSince1970) WHERE id = \(id)"
            )
        }

        // Keep the selected conversation recent so its row and message
        // timestamps agree; push the others into the previous days.
        let conversations = try await store.conversations(limit: 10)
        for item in conversations {
            let age: TimeInterval
            if item.title.hasPrefix("What did the keeper record") {
                age = 0
            } else if item.title.hasPrefix("Summarize the coastal survey") {
                age = 86_400 * 1.1
            } else {
                age = 86_400 * 2.3
            }
            let date = Date().addingTimeInterval(-age)
            try update(
                databaseURL: support.appendingPathComponent("lumina.sqlite"),
                sql: "UPDATE conversations SET updated_at = \(date.timeIntervalSince1970) WHERE id = \(item.id)"
            )
        }

        let model = try AppModel(supportDirectory: support, defaults: defaults)
        await model.refreshFolders()
        await model.refreshLibrary()
        await model.refreshConversations()
        await model.refreshTimeline()
        model.lastIndexCompletedAt = Date()
        model.setup = SetupSnapshot(
            isChecking: false,
            isReachable: true,
            installation: OllamaInstallation(
                appURL: URL(fileURLWithPath: "/Applications/Ollama.app"),
                binaryURL: URL(fileURLWithPath: "/usr/local/bin/ollama"),
                isRunning: true,
                version: "0.40.12"
            ),
            models: [
                LocalModel(
                    name: "gemma4:e2b-it-qat",
                    sizeBytes: 4_300_000_000,
                    modifiedAt: Date(),
                    family: "gemma4",
                    parameterSize: "2B",
                    isEmbedding: false
                ),
                LocalModel(
                    name: "embeddinggemma",
                    sizeBytes: 621_000_000,
                    modifiedAt: Date(),
                    family: "embeddinggemma",
                    parameterSize: "300M",
                    isEmbedding: true
                )
            ],
            error: nil,
            lastChecked: Date()
        )
        if let first = model.conversations.first {
            await model.selectConversation(first)
        }

        return SnapshotFixture(
            root: root,
            model: model,
            defaults: defaults,
            defaultsSuite: defaultsSuite
        )
    }

    private static func update(databaseURL: URL, sql: String) throws {
        let database = try SQLiteDatabase(url: databaseURL)
        try database.execute(sql)
    }

    func capture(route: AppRoute, to url: URL) async throws {
        model.route = route

        let root = RootView(bootstrapOnAppear: false, settingsInitialTab: .models)
            .environment(model)
            .environment(model.settings)
            .tint(model.settings.accent.color)
            .preferredColorScheme(.light)
            .frame(width: 1_600, height: 1_000)

        let targetSize = NSSize(width: 1_600, height: 1_000)
        let controller = NSHostingController(rootView: root)
        // The window is larger than the app's minimum, so pin its content
        // size and keep SwiftUI from resizing it to an intrinsic height.
        controller.sizingOptions = []
        let window = NSWindow(contentViewController: controller)
        window.title = "Lumina"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.setContentSize(targetSize)
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.appearance = NSAppearance(named: .aqua)
        window.layoutIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .seconds(1.2))

        let host = controller.view
        host.frame = NSRect(origin: .zero, size: targetSize)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .seconds(0.3))

        let bounds = NSRect(origin: .zero, size: targetSize)
        guard let representation = host.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw SnapshotError.captureFailed
        }
        host.cacheDisplay(in: bounds, to: representation)
        guard let png = representation.representation(using: .png, properties: [:]) else {
            throw SnapshotError.captureFailed
        }
        try png.write(to: url)
        window.contentViewController = nil
    }
}

private enum SnapshotError: Error {
    case captureFailed
}

// MARK: - Demo content

private struct DemoChunk {
    var text: String
    var locator: ContentLocator
    var localID: String?
}

private struct DemoDocument {
    var name: String
    var slug: String
    var kind: ContentKind
    var size: Int64
    var ageDays: Int
    var pageCount: Int?
    var duration: TimeInterval?
    var chunks: [DemoChunk]
    var thumbnail: ThumbnailStyle

    init(
        name: String,
        kind: ContentKind,
        size: Int64,
        ageDays: Int,
        pageCount: Int? = nil,
        duration: TimeInterval? = nil,
        chunks: [DemoChunk],
        thumbnail: ThumbnailStyle
    ) {
        self.name = name
        self.slug = name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        self.kind = kind
        self.size = size
        self.ageDays = ageDays
        self.pageCount = pageCount
        self.duration = duration
        self.chunks = chunks
        self.thumbnail = thumbnail
    }
}

@MainActor
private func demoDocuments() -> [DemoDocument] {
    [
        DemoDocument(
            name: "Aurora Field Notes.md",
            kind: .text,
            size: 18_420,
            ageDays: 0,
            chunks: [
                DemoChunk(
                    text: """
                    # Aurora Field Notes

                    The first clear night at Kirkjufell came after three days of cloud. At 22:40 the horizon turned a pale green, then folded into curtains of violet. The Kp index reached 5.2 around midnight.
                    """,
                    locator: ContentLocator(line: 1),
                    localID: "aurora-1"
                ),
                DemoChunk(
                    text: """
                    ## Camera settings
                    - 24 mm, f/2.0
                    - 8 seconds at ISO 1600
                    - Focus set just short of infinity

                    Next trip: bring the heavier tripod. The coastal wind moved the lighter one between exposures.
                    """,
                    locator: ContentLocator(line: 8),
                    localID: "aurora-2"
                )
            ],
            thumbnail: .document(title: "AURORA", subtitle: "FIELD NOTES", tint: .systemGreen)
        ),
        DemoDocument(
            name: "Lighthouse Keepers Log.txt",
            kind: .text,
            size: 12_770,
            ageDays: 1,
            chunks: [
                DemoChunk(
                    text: """
                    # Lighthouse Keepers Log — October

                    ## Tuesday 14
                    Fog closed in at 04:10. Visibility under 200 meters. The Aurora passed the outer buoy at 05:35 and sounded three long blasts.
                    """,
                    locator: ContentLocator(line: 1),
                    localID: "log-1"
                ),
                DemoChunk(
                    text: """
                    ## Wednesday 15
                    Wind southwest, force 5. Tide at 06:12 was 2.4 meters. Replaced the starboard lamp wick and cleaned the brass housing.

                    ## Thursday 16
                    Clear by noon. A tern circled the gallery twice, then headed south along the point. Barometer steady at 1016 hPa.
                    """,
                    locator: ContentLocator(line: 7),
                    localID: "log-2"
                )
            ],
            thumbnail: .document(title: "KEEPER'S LOG", subtitle: "NORTHERN REACH", tint: .systemBlue)
        ),
        DemoDocument(
            name: "Coastal Survey 2026.pdf",
            kind: .pdf,
            size: 4_382_100,
            ageDays: 2,
            pageCount: 18,
            chunks: [
                DemoChunk(
                    text: """
                    Coastal Survey 2026
                    Northern Reach — Station 4A

                    The shoreline between Gull Point and the outer buoy shifted west by 6.3 meters since the 2023 survey. Dune grass now covers the old access track.
                    """,
                    locator: ContentLocator(page: 2),
                    localID: "survey-1"
                ),
                DemoChunk(
                    text: """
                    Measurements
                    Transect A: 48.2 m
                    Transect B: 51.7 m
                    Transect C: 47.9 m

                    Recommendation: move the seasonal marker at Station 4A inland by eight meters before spring.
                    """,
                    locator: ContentLocator(page: 5),
                    localID: "survey-2"
                )
            ],
            thumbnail: .document(title: "COASTAL SURVEY", subtitle: "STATION 4A · 2026", tint: .systemTeal)
        ),
        DemoDocument(
            name: "Tide Tables.csv",
            kind: .spreadsheet,
            size: 3_840,
            ageDays: 3,
            chunks: [
                DemoChunk(
                    text: """
                    Date,High 1,Low 1,High 2,Low 2
                    2026-11-01,06:12,00:04,18:37,12:20
                    2026-11-02,06:55,00:47,19:21,13:03
                    2026-11-03,07:38,01:30,20:05,13:46
                    """,
                    locator: ContentLocator(line: 1),
                    localID: "tide-1"
                )
            ],
            thumbnail: .table
        ),
        DemoDocument(
            name: "Harbor at Dawn.jpg",
            kind: .image,
            size: 3_284_400,
            ageDays: 4,
            chunks: [
                DemoChunk(
                    text: "Harbor at dawn, November 2026. Two fishing boats and a low stone breakwater.",
                    locator: ContentLocator(),
                    localID: "harbor-1"
                )
            ],
            thumbnail: .harbor
        ),
        DemoDocument(
            name: "InferenceClient.swift",
            kind: .code,
            size: 22_560,
            ageDays: 5,
            chunks: [
                DemoChunk(
                    text: """
                    func streamAnswer(
                        model: String,
                        messages: [ChatMessage]
                    ) -> AsyncThrowingStream<String, Error> {
                        AsyncThrowingStream { continuation in
                            Task { try await readNDJSON(continuation) }
                        }
                    }
                    """,
                    locator: ContentLocator(line: 12),
                    localID: "code-1"
                )
            ],
            thumbnail: .code
        ),
        DemoDocument(
            name: "Tern Migration.jpg",
            kind: .image,
            size: 2_911_200,
            ageDays: 6,
            chunks: [
                DemoChunk(
                    text: "Arctic tern over the south point, wings angled against a pale sky.",
                    locator: ContentLocator(),
                    localID: "tern-1"
                )
            ],
            thumbnail: .tern
        ),
        DemoDocument(
            name: "Field Recording.m4a",
            kind: .audio,
            size: 14_200_000,
            ageDays: 7,
            duration: 872,
            chunks: [
                DemoChunk(
                    text: "Field recording: wind across the dune grass, distant surf, and the harbor bell at dusk.",
                    locator: ContentLocator(timeStart: 42, timeEnd: 68),
                    localID: "audio-1"
                )
            ],
            thumbnail: .audio
        ),
        DemoDocument(
            name: "Reflection on Private Search.md",
            kind: .text,
            size: 9_180,
            ageDays: 8,
            chunks: [
                DemoChunk(
                    text: """
                    The value of a local index is not only privacy. It is the freedom to ask a question without composing a query for someone else's ranking system. The answer can begin with the shape of your own notes.
                    """,
                    locator: ContentLocator(line: 1),
                    localID: "reflection-1"
                )
            ],
            thumbnail: .document(title: "PRIVATE SEARCH", subtitle: "A REFLECTION", tint: .systemBrown)
        ),
        DemoDocument(
            name: "Shoreline Access Notes.md",
            kind: .text,
            size: 7_640,
            ageDays: 9,
            chunks: [
                DemoChunk(
                    text: """
                    The old access track is now covered by dune grass. Use the marked path west of Gull Point and avoid the roped-off restoration plot. The gate is locked after sunset.
                    """,
                    locator: ContentLocator(line: 1),
                    localID: "shore-1"
                )
            ],
            thumbnail: .document(title: "SHORELINE ACCESS", subtitle: "FIELD NOTES", tint: .systemOrange)
        ),
        DemoDocument(
            name: "Station 4A Measurements.csv",
            kind: .spreadsheet,
            size: 5_210,
            ageDays: 10,
            chunks: [
                DemoChunk(
                    text: """
                    Transect,2023,2026,Change
                    A,46.1,48.2,+2.1
                    B,48.9,51.7,+2.8
                    C,45.4,47.9,+2.5
                    """,
                    locator: ContentLocator(line: 1),
                    localID: "measure-1"
                )
            ],
            thumbnail: .table
        ),
        DemoDocument(
            name: "North Reach Map.pdf",
            kind: .pdf,
            size: 8_920_400,
            ageDays: 11,
            pageCount: 1,
            chunks: [
                DemoChunk(
                    text: "North Reach map: Gull Point, Station 4A, the outer buoy, and the marked shoreline transects.",
                    locator: ContentLocator(page: 1),
                    localID: "map-1"
                )
            ],
            thumbnail: .document(title: "NORTH REACH", subtitle: "SURVEY MAP · 2026", tint: .systemIndigo)
        )
    ]
}

// MARK: - Thumbnails

@MainActor
private enum ThumbnailStyle {
    case document(title: String, subtitle: String, tint: NSColor)
    case table
    case code
    case harbor
    case tern
    case audio
}

@MainActor
private struct ThumbnailPainter {
    let size = NSSize(width: 600, height: 340)

    func draw(_ style: ThumbnailStyle, to url: URL) throws {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw SnapshotError.captureFailed
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.setShouldAntialias(true)
        context.cgContext.interpolationQuality = .high

        switch style {
        case let .document(title, subtitle, tint):
            drawDocument(title: title, subtitle: subtitle, tint: tint)
        case .table:
            drawTable()
        case .code:
            drawCode()
        case .harbor:
            drawHarbor()
        case .tern:
            drawTern()
        case .audio:
            drawAudio()
        }

        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.captureFailed
        }
        try png.write(to: url)
    }

    private func drawDocument(title: String, subtitle: String, tint: NSColor) {
        NSColor(calibratedWhite: 0.965, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()

        tint.withAlphaComponent(0.14).setFill()
        NSBezierPath(rect: topRect(x: 0, y: 0, width: size.width, height: 12)).fill()

        drawText(title, rect: topRect(x: 42, y: 50, width: 500, height: 34),
                 font: .systemFont(ofSize: 27, weight: .semibold), color: NSColor(calibratedWhite: 0.16, alpha: 1))
        drawText(subtitle, rect: topRect(x: 43, y: 88, width: 500, height: 18),
                 font: .systemFont(ofSize: 11, weight: .medium), color: tint)

        tint.withAlphaComponent(0.7).setFill()
        NSBezierPath(rect: topRect(x: 42, y: 128, width: 120, height: 3)).fill()

        let widths: [CGFloat] = [440, 512, 388, 470, 330]
        for (index, width) in widths.enumerated() {
            NSColor(calibratedWhite: 0.72, alpha: 0.55).setFill()
            NSBezierPath(roundedRect: topRect(x: 42, y: 158 + CGFloat(index) * 22, width: width, height: 7),
                         xRadius: 3, yRadius: 3).fill()
        }

        tint.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: topRect(x: 42, y: 292, width: 108, height: 20), xRadius: 10, yRadius: 10).fill()
    }

    private func drawTable() {
        NSColor(calibratedWhite: 0.985, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()

        NSColor(calibratedRed: 0.18, green: 0.32, blue: 0.35, alpha: 1).setFill()
        NSBezierPath(rect: topRect(x: 30, y: 28, width: 540, height: 44)).fill()
        let headers = ["DATE", "HIGH", "LOW", "HIGH", "LOW"]
        for (index, header) in headers.enumerated() {
            drawText(header, rect: topRect(x: 46 + CGFloat(index) * 102, y: 42, width: 90, height: 18),
                     font: .monospacedSystemFont(ofSize: 11, weight: .semibold),
                     color: .white)
        }

        for row in 0..<8 {
            if row.isMultiple(of: 2) {
                NSColor(calibratedWhite: 0.94, alpha: 0.75).setFill()
                NSBezierPath(rect: topRect(x: 30, y: 82 + CGFloat(row) * 28, width: 540, height: 28)).fill()
            }
            for column in 0..<5 {
                let value = column == 0 ? "2026-11-0\(row + 1)" : String(format: "%02d:%02d", 6 + row, 12 + column * 9)
                drawText(value, rect: topRect(x: 46 + CGFloat(column) * 102, y: 90 + CGFloat(row) * 28, width: 94, height: 16),
                         font: .monospacedSystemFont(ofSize: 10.5, weight: .regular),
                         color: NSColor(calibratedWhite: 0.35, alpha: 1))
            }
        }
    }

    private func drawCode() {
        NSColor(calibratedRed: 0.075, green: 0.10, blue: 0.13, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()

        let dots = [NSColor(calibratedRed: 0.92, green: 0.36, blue: 0.30, alpha: 1),
                    NSColor(calibratedRed: 0.95, green: 0.72, blue: 0.26, alpha: 1),
                    NSColor(calibratedRed: 0.32, green: 0.76, blue: 0.42, alpha: 1)]
        for (index, color) in dots.enumerated() {
            color.setFill()
            NSBezierPath(ovalIn: topRect(x: 24 + CGFloat(index) * 18, y: 20, width: 9, height: 9)).fill()
        }

        let lines: [(CGFloat, NSColor)] = [
            (220, NSColor(calibratedRed: 0.55, green: 0.79, blue: 0.95, alpha: 1)),
            (330, NSColor(calibratedRed: 0.72, green: 0.80, blue: 0.86, alpha: 1)),
            (168, NSColor(calibratedRed: 0.88, green: 0.64, blue: 0.42, alpha: 1)),
            (390, NSColor(calibratedRed: 0.72, green: 0.80, blue: 0.86, alpha: 1)),
            (280, NSColor(calibratedRed: 0.55, green: 0.79, blue: 0.95, alpha: 1)),
            (348, NSColor(calibratedRed: 0.58, green: 0.84, blue: 0.66, alpha: 1)),
            (205, NSColor(calibratedRed: 0.72, green: 0.80, blue: 0.86, alpha: 1)),
            (312, NSColor(calibratedRed: 0.88, green: 0.64, blue: 0.42, alpha: 1))
        ]
        for (index, line) in lines.enumerated() {
            line.1.withAlphaComponent(0.82).setFill()
            NSBezierPath(roundedRect: topRect(x: 46, y: 62 + CGFloat(index) * 28, width: line.0, height: 7),
                         xRadius: 3, yRadius: 3).fill()
        }
    }

    private func drawHarbor() {
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.93, green: 0.72, blue: 0.52, alpha: 1),
            NSColor(calibratedRed: 0.80, green: 0.78, blue: 0.75, alpha: 1),
            NSColor(calibratedRed: 0.42, green: 0.55, blue: 0.62, alpha: 1)
        ])
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 90)

        NSColor(calibratedRed: 0.98, green: 0.88, blue: 0.66, alpha: 0.9).setFill()
        NSBezierPath(ovalIn: topRect(x: 410, y: 72, width: 74, height: 74)).fill()

        NSColor(calibratedRed: 0.19, green: 0.24, blue: 0.27, alpha: 1).setFill()
        NSBezierPath(rect: topRect(x: 0, y: 202, width: size.width, height: 6)).fill()

        NSColor(calibratedRed: 0.17, green: 0.26, blue: 0.31, alpha: 1).setFill()
        NSBezierPath(rect: topRect(x: 0, y: 208, width: size.width, height: 132)).fill()
        NSColor(calibratedRed: 0.30, green: 0.42, blue: 0.46, alpha: 0.7).setFill()
        for line in 0..<6 {
            NSBezierPath(rect: topRect(x: 0, y: 224 + CGFloat(line) * 17, width: size.width, height: 2)).fill()
        }

        NSColor(calibratedRed: 0.12, green: 0.15, blue: 0.17, alpha: 1).setFill()
        let hull = NSBezierPath()
        hull.move(to: CGPoint(x: 250, y: size.height - 208))
        hull.line(to: CGPoint(x: 360, y: size.height - 208))
        hull.line(to: CGPoint(x: 344, y: size.height - 186))
        hull.line(to: CGPoint(x: 266, y: size.height - 186))
        hull.close()
        hull.fill()
        NSBezierPath(rect: topRect(x: 302, y: 150, width: 3, height: 52)).fill()

        NSColor(calibratedRed: 0.25, green: 0.31, blue: 0.34, alpha: 1).setFill()
        NSBezierPath(roundedRect: topRect(x: 70, y: 186, width: 140, height: 8), xRadius: 3, yRadius: 3).fill()
        NSBezierPath(rect: topRect(x: 82, y: 156, width: 7, height: 30)).fill()
        NSBezierPath(rect: topRect(x: 190, y: 156, width: 7, height: 30)).fill()
    }

    private func drawTern() {
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.86, green: 0.90, blue: 0.90, alpha: 1),
            NSColor(calibratedRed: 0.70, green: 0.78, blue: 0.79, alpha: 1)
        ])
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 90)

        NSColor(calibratedRed: 0.37, green: 0.48, blue: 0.49, alpha: 1).setFill()
        NSBezierPath(rect: topRect(x: 0, y: 250, width: size.width, height: 90)).fill()

        NSColor(calibratedWhite: 1, alpha: 0.28).setFill()
        for index in 0..<12 {
            NSBezierPath(ovalIn: topRect(x: CGFloat(index) * 56 + 12, y: 268 + CGFloat(index % 3) * 10, width: 20, height: 3)).fill()
        }

        NSColor(calibratedRed: 0.17, green: 0.20, blue: 0.21, alpha: 1).setFill()
        let wing = NSBezierPath()
        wing.move(to: CGPoint(x: 238, y: size.height - 128))
        wing.curve(to: CGPoint(x: 190, y: size.height - 168),
                   controlPoint1: CGPoint(x: 222, y: size.height - 154),
                   controlPoint2: CGPoint(x: 208, y: size.height - 166))
        wing.curve(to: CGPoint(x: 238, y: size.height - 142),
                   controlPoint1: CGPoint(x: 214, y: size.height - 154),
                   controlPoint2: CGPoint(x: 228, y: size.height - 148))
        wing.curve(to: CGPoint(x: 292, y: size.height - 166),
                   controlPoint1: CGPoint(x: 262, y: size.height - 148),
                   controlPoint2: CGPoint(x: 280, y: size.height - 154))
        wing.curve(to: CGPoint(x: 238, y: size.height - 128),
                   controlPoint1: CGPoint(x: 274, y: size.height - 158),
                   controlPoint2: CGPoint(x: 250, y: size.height - 142))
        wing.fill()
        NSBezierPath(ovalIn: topRect(x: 234, y: 214, width: 9, height: 8)).fill()
    }

    private func drawAudio() {
        NSColor(calibratedRed: 0.09, green: 0.11, blue: 0.13, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()

        NSColor(calibratedRed: 0.23, green: 0.55, blue: 0.53, alpha: 1).setFill()
        NSBezierPath(ovalIn: topRect(x: 42, y: 38, width: 48, height: 48)).fill()
        NSColor(calibratedWhite: 1, alpha: 0.9).setFill()
        let triangle = NSBezierPath()
        triangle.move(to: CGPoint(x: 61, y: size.height - 63))
        triangle.line(to: CGPoint(x: 61, y: size.height - 82))
        triangle.line(to: CGPoint(x: 78, y: size.height - 72.5))
        triangle.close()
        triangle.fill()

        let heights: [CGFloat] = [18, 34, 52, 76, 44, 90, 62, 112, 72, 48, 94, 58, 30, 68, 42, 22, 56, 34, 18, 40, 26]
        for (index, height) in heights.enumerated() {
            NSColor(calibratedRed: 0.35, green: 0.68, blue: 0.65, alpha: 0.78).setFill()
            NSBezierPath(roundedRect: topRect(x: 112 + CGFloat(index) * 21, y: 132 - height / 2, width: 7, height: height),
                         xRadius: 3, yRadius: 3).fill()
        }

        drawText("FIELD RECORDING", rect: topRect(x: 42, y: 276, width: 300, height: 18),
                 font: .systemFont(ofSize: 13, weight: .semibold), color: NSColor(calibratedWhite: 0.92, alpha: 1))
        drawText("14:32 · THE POINT", rect: topRect(x: 42, y: 296, width: 300, height: 16),
                 font: .monospacedSystemFont(ofSize: 10.5, weight: .regular), color: NSColor(calibratedWhite: 0.58, alpha: 1))
    }

    private func drawText(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
    }

    private func topRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
        NSRect(x: x, y: size.height - y - height, width: width, height: height)
    }
}

@MainActor
private func drawThumbnail(_ style: ThumbnailStyle, to url: URL) throws {
    try ThumbnailPainter().draw(style, to: url)
}
