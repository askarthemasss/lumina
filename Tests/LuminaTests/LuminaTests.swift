import Foundation
import Testing
@testable import Lumina

// The suite uses Swift Testing rather than XCTest so it builds with both a full
// Xcode installation and the Command Line Tools. `scripts/test.sh` adds the
// framework search path needed by CLT-only installs.

// MARK: - Vector math

@Suite("Vector math")
struct VectorMathTests {
    @Test("Normalization produces a unit vector")
    func normalizationProducesUnitLength() {
        let normalized = VectorMath.normalized([3, 4])
        #expect(abs(VectorMath.dot(normalized, normalized) - 1.0) < 0.0001)
        #expect(abs(normalized[0] - 0.6) < 0.0001)
        #expect(abs(normalized[1] - 0.8) < 0.0001)
    }

    @Test("A zero vector stays finite")
    func zeroVectorDoesNotDivideByZero() {
        let normalized = VectorMath.normalized([0, 0, 0])
        let allFinite = normalized.allSatisfy { $0.isFinite }
        #expect(normalized == [0, 0, 0])
        #expect(allFinite)
    }

    @Test("Encoding round-trips and empty data decodes to nothing")
    func encodingRoundTrip() {
        let original: [Float] = [0.125, -1.5, 42, 0, 3.14]
        #expect(VectorMath.decode(VectorMath.encode(original)) == original)
        #expect(VectorMath.decode(Data()).isEmpty)
    }

    @Test("Bounded top-K keeps the highest scores")
    func boundedTopKKeepsHighestScores() {
        var heap = BoundedTopK<String>(limit: 3)
        heap.offer(score: 0.1, element: "a")
        heap.offer(score: 0.9, element: "b")
        heap.offer(score: 0.4, element: "c")
        heap.offer(score: 0.8, element: "d")
        heap.offer(score: 0.2, element: "e")
        #expect(heap.sortedDescending() == ["b", "d", "c"])
        #expect(abs((heap.minimumScore ?? -1) - 0.4) < 0.0001)
    }
}

// MARK: - Chunking

@Suite("Text chunking")
struct TextChunkerTests {
    @Test("Long text becomes overlapping chunks")
    func characterChunksCoverLongTextWithOverlap() {
        let sentence = "Local retrieval keeps private knowledge searchable without a network. "
        let text = String(repeating: sentence, count: 180)
        let chunks = TextChunker.characterChunks(text)
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { !$0.isEmpty })
        #expect(chunks.contains { $0.contains("Local retrieval") })
    }

    @Test("Whitespace-only text produces no chunks")
    func characterChunksRejectWhitespaceOnly() {
        #expect(TextChunker.characterChunks(" \n\t ").isEmpty)
    }

    @Test("Line chunks carry line numbers")
    func lineChunksCarryLineNumbers() {
        let text = (1...160).map { "line \($0) contains example content" }.joined(separator: "\n")
        let chunks = TextChunker.lineChunks(text, target: 500, overlapLines: 2)
        #expect(chunks.count > 1)
        #expect(chunks.first?.line == 1)
        #expect(chunks.allSatisfy { ($0.line ?? 0) >= 1 })
        #expect(chunks.allSatisfy { $0.text.contains("line ") })
    }

    @Test("Page chunks attach their page number")
    func pageChunksAttachPageNumber() {
        let chunks = TextChunker.pageChunks(text: "A short page of text for the index.", page: 7)
        #expect(chunks.count == 1)
        #expect(chunks.first?.page == 7)
    }

    @Test("HTML reader removes scripts, styles, and the head")
    func htmlReaderRemovesScriptsAndHead() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LuminaHTML-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("page.html")
        let html = """
        <html><head><title>Ignored</title><style>.x { color: red; }</style></head>
        <body><h1>Local notes</h1><script>alert('no')</script>
        <p>Hello &amp; welcome to Lumina.</p></body></html>
        """
        try html.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: directory) }

        let text = try HTMLTextReader.read(url: url)
        #expect(text.contains("Local notes"))
        #expect(text.contains("Hello & welcome to Lumina."))
        #expect(!text.contains("alert"))
        #expect(!text.contains(".x {"))
        #expect(!text.contains("Ignored"))
    }
}

// MARK: - Model recommendations & endpoint policy

@Suite("Configuration")
struct ConfigurationTests {
    @Test("Recommended models follow unified memory")
    func memoryBasedModelRecommendations() {
        #expect(ModelRecommendation.recommended(forMemory: 8_000_000_000).chatModel == "gemma4:e2b")
        #expect(ModelRecommendation.recommended(forMemory: 16_000_000_000).chatModel == "gemma4:12b")
        #expect(ModelRecommendation.recommended(forMemory: 32_000_000_000).chatModel == "gemma4:26b")
        #expect(ModelRecommendation.recommended(forMemory: 64_000_000_000).chatModel == "gemma4:31b")
        #expect(ModelRecommendation.recommended(forMemory: 8_000_000_000).embeddingModel == "embeddinggemma")
    }

    @Test("Pull commands cover both models")
    func pullCommandsCoverBothModels() {
        let recommendation = ModelRecommendation.recommended(forMemory: 16_000_000_000)
        #expect(recommendation.pullCommands.count == 2)
        #expect(recommendation.pullCommands.contains("ollama pull embeddinggemma"))
        #expect(recommendation.pullCommands.contains("ollama pull gemma4:12b"))
    }

    @Test("Loopback detection accepts only local hosts")
    func loopbackEnforcement() {
        #expect(LocalInferenceClient.isLoopback(URL(string: "http://127.0.0.1:11434")!))
        #expect(LocalInferenceClient.isLoopback(URL(string: "http://localhost:8080")!))
        #expect(LocalInferenceClient.isLoopback(URL(string: "http://[::1]:8080")!))
        #expect(LocalInferenceClient.isLoopback(URL(string: "http://studio.localhost:9000")!))

        #expect(!LocalInferenceClient.isLoopback(URL(string: "https://api.example.com")!))
        #expect(!LocalInferenceClient.isLoopback(URL(string: "http://127.0.0.1.example.com")!))
        #expect(!LocalInferenceClient.isLoopback(URL(string: "http://192.168.1.5:11434")!))
        #expect(!LocalInferenceClient.isLoopback(URL(string: "http://localhost.example.com")!))
    }

    @Test("A remote endpoint is rejected by the client")
    func remoteEndpointIsRejectedByClient() {
        let configuration = InferenceConfiguration(
            runtime: .ollama,
            endpoint: "https://api.example.com",
            embeddingModel: "embeddinggemma",
            chatModel: "gemma4:e2b"
        )
        do {
            _ = try LocalInferenceClient(configuration: configuration)
            Issue.record("Expected the client to reject a remote endpoint.")
        } catch let error as InferenceError {
            #expect(error.errorDescription == InferenceError.remoteEndpoint.errorDescription)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

// MARK: - Search query construction

@Suite("Search query construction")
struct SearchQueryTests {
    @Test("Search terms are lowercased and deduplicated")
    func searchTermsAreDeduplicatedAndLowercased() {
        #expect(
            IndexStore.searchTerms(in: "Invoice invoice Q4, total: 42")
                == ["invoice", "q4", "total", "42"]
        )
    }

    @Test("FTS query joins quoted terms with OR")
    func ftsQueryUsesOrAndQuotesTerms() {
        #expect(
            IndexStore.ftsQuery(from: "quarterly invoice", exactPhrase: false)
                == "\"quarterly\" OR \"invoice\""
        )
    }

    @Test("Exact phrase mode quotes the whole phrase")
    func ftsQueryExactPhrase() {
        #expect(
            IndexStore.ftsQuery(from: "quarterly invoice", exactPhrase: true)
                == "\"quarterly invoice\""
        )
    }

    @Test("Embedded quotes are stripped")
    func ftsQueryEscapesEmbeddedQuotes() {
        #expect(
            IndexStore.ftsQuery(from: "say \"hello\"", exactPhrase: true)
                == "\"say hello\""
        )
    }

    @Test("Empty query produces no FTS query")
    func emptyQueryProducesNoFTSQuery() {
        #expect(IndexStore.ftsQuery(from: " — ", exactPhrase: false) == nil)
    }
}

// MARK: - Database

@Suite("Indexing pipeline")
final class IndexingPipelineTests {
    private let directory: URL
    private let store: IndexStore
    private let engine: IndexingEngine

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LuminaPipeline-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = try IndexStore(databaseURL: directory.appendingPathComponent("index.sqlite"))
        let thumbnails = directory.appendingPathComponent("thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: thumbnails, withIntermediateDirectories: true)
        engine = IndexingEngine(store: store, thumbnailsDirectory: thumbnails)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test("Plain text is indexed and searchable without a model")
    func indexesPlainTextWithoutModels() async throws {
        let folderURL = directory.appendingPathComponent("Docs", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try """
        The lighthouse keeper records every ship that passes the point.
        The log mentions the Aurora on a foggy Tuesday.
        """.write(
            to: folderURL.appendingPathComponent("notes.txt"),
            atomically: true,
            encoding: .utf8
        )

        let folder = try await store.addFolder(path: folderURL.path, bookmark: nil)
        let configuration = InferenceConfiguration(
            runtime: .ollama,
            endpoint: "http://127.0.0.1:1",
            embeddingModel: "embeddinggemma",
            chatModel: "gemma4:e2b"
        )

        let summary = await engine.run(
            folders: [folder],
            options: .default,
            configuration: configuration,
            force: true
        )

        #expect(summary.processed == 1)
        #expect(summary.failed == 0)
        #expect(!summary.warnings.isEmpty)
        let stats = try await store.stats()
        #expect(stats.fileCount == 1)
        #expect(stats.chunkCount >= 1)
        #expect(stats.embeddedChunkCount == 0)

        let hits = try await store.keywordSearch(query: "lighthouse", filters: SearchFilters())
        #expect(hits.count == 1)
        #expect(hits.first?.file.name == "notes.txt")

        let progress = await engine.snapshot()
        #expect(progress.phase == .idle)
    }

    @Test("Scanner skips sensitive names, dependency folders, and excluded patterns")
    func scannerHonorsExclusions() async throws {
        let folderURL = directory.appendingPathComponent("Mixed", isDirectory: true)
        let modules = folderURL.appendingPathComponent("node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
        try "Lighthouse notes stay searchable.".write(
            to: folderURL.appendingPathComponent("keep.md"),
            atomically: true,
            encoding: .utf8
        )
        try "Dependency noise should never enter the index.".write(
            to: modules.appendingPathComponent("package.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "credentials".write(
            to: folderURL.appendingPathComponent("credentials.json"),
            atomically: true,
            encoding: .utf8
        )
        try "excluded".write(
            to: folderURL.appendingPathComponent("draft.psd"),
            atomically: true,
            encoding: .utf8
        )

        let folder = try await store.addFolder(path: folderURL.path, bookmark: nil)
        let configuration = InferenceConfiguration(
            runtime: .ollama,
            endpoint: "http://127.0.0.1:1",
            embeddingModel: "embeddinggemma",
            chatModel: "gemma4:e2b"
        )
        var options = IndexingOptions.default
        options.excludedPatterns = ["*.psd"]

        let summary = await engine.run(
            folders: [folder],
            options: options,
            configuration: configuration,
            force: true
        )

        #expect(summary.processed == 1)
        let files = try await store.recentFiles(limit: 20)
        #expect(files.count == 1)
        #expect(files.first?.name == "keep.md")
        let noise = try await store.keywordSearch(query: "dependency", filters: SearchFilters())
        #expect(noise.isEmpty)
    }
}

// MARK: - Opt-in live runtime

/// Run with `LUMINA_LIVE_OLLAMA=1 ./scripts/test.sh` to check the real
/// onboarding path against an Ollama instance on this Mac. Skipped by default
/// so the suite stays deterministic on machines without a local runtime.
@Suite("Live Ollama", .enabled(if: ProcessInfo.processInfo.environment["LUMINA_LIVE_OLLAMA"] == "1"))
struct LiveOllamaTests {
    @Test("Onboarding sees the runtime and its installed models")
    func onboardingSeesRuntimeAndModels() async throws {
        let configuration = InferenceConfiguration(
            runtime: .ollama,
            endpoint: "http://127.0.0.1:11434",
            embeddingModel: "embeddinggemma",
            chatModel: "gemma4:e2b"
        )
        let client = try LocalInferenceClient(configuration: configuration)
        let version = try await client.health()
        #expect(version?.isEmpty == false)

        let models = try await client.listModels()
        #expect(!models.isEmpty)
        #expect(models.contains { !$0.isEmbedding })
        #expect(models.allSatisfy { $0.sizeBytes >= 0 })

        let snapshot = await RuntimeDiscovery.snapshot(configuration: configuration)
        #expect(snapshot.isReachable)
        #expect(snapshot.error == nil)
        #expect(!snapshot.models.isEmpty)
    }
}

// MARK: - Database

@Suite("Index store")
final class IndexStoreTests {
    private let directory: URL
    private let store: IndexStore

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LuminaTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = try IndexStore(databaseURL: directory.appendingPathComponent("index.sqlite"))
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test("Keyword, semantic, filename, and filtered search work together")
    func keywordSemanticAndFilenameSearch() async throws {
        let folder = try await store.addFolder(
            path: directory.appendingPathComponent("Documents").path,
            bookmark: nil
        )
        let invoiceID = try await saveFile(
            folderID: folder.id,
            name: "Invoice Q4.pdf",
            kind: .pdf,
            text: "Quarterly invoice total is 1,240 dollars and payment is due Friday.",
            embedding: [1, 0, 0],
            model: "test-embed",
            page: 2
        )
        _ = try await saveFile(
            folderID: folder.id,
            name: "Budget notes.txt",
            kind: .text,
            text: "The budget draft mentions travel and a new laptop.",
            embedding: [0, 1, 0],
            model: "test-embed"
        )

        let keyword = try await store.keywordSearch(query: "invoice", filters: SearchFilters())
        #expect(keyword.count == 1)
        #expect(keyword.first?.file.id == invoiceID)
        #expect(keyword.first?.locator.page == 2)
        #expect(
            keyword.first?.snippet.contains("[[invoice]]") == true
                || keyword.first?.snippet.contains("[[Invoice]]") == true
        )

        let semantic = try await store.semanticSearch(
            queryVector: [1, 0, 0],
            model: "test-embed",
            filters: SearchFilters()
        )
        #expect(semantic.count == 1)
        #expect(semantic.first?.file.id == invoiceID)
        #expect(abs((semantic.first?.similarity ?? 0) - 1) < 0.0001)

        let filenames = try await store.filenameMatches(query: "budget", filters: SearchFilters())
        #expect(filenames.count == 1)
        #expect(filenames.first?.kind == .text)

        let filtered = try await store.keywordSearch(
            query: "invoice",
            filters: SearchFilters(kinds: [.text])
        )
        #expect(filtered.isEmpty)
    }

    @Test("Folder and date filters narrow keyword results")
    func folderAndDateFilters() async throws {
        let folder = try await store.addFolder(
            path: directory.appendingPathComponent("Notes").path,
            bookmark: nil
        )
        let fileID = try await saveFile(
            folderID: folder.id,
            name: "Meeting notes.txt",
            kind: .text,
            text: "Decisions from the planning meeting."
        )

        let inFolder = try await store.keywordSearch(
            query: "meeting",
            filters: SearchFilters(folderIDs: [folder.id])
        )
        #expect(inFolder.first?.file.id == fileID)

        let otherFolder = try await store.keywordSearch(
            query: "meeting",
            filters: SearchFilters(folderIDs: [folder.id + 999])
        )
        #expect(otherFolder.isEmpty)

        let future = try await store.keywordSearch(
            query: "meeting",
            filters: SearchFilters(dateFrom: Date().addingTimeInterval(3_600))
        )
        #expect(future.isEmpty)
    }

    @Test("Pins, notes, conversations, stats, and timeline persist")
    func statsPinsNotesAndConversations() async throws {
        let folder = try await store.addFolder(
            path: directory.appendingPathComponent("Mixed").path,
            bookmark: nil
        )
        let fileID = try await saveFile(
            folderID: folder.id,
            name: "Plan.md",
            kind: .code,
            text: "Ship the local search index this week."
        )

        _ = try await store.togglePin(fileID: fileID)
        let pinned = try await store.pinnedFiles()
        #expect(pinned.first?.id == fileID)

        let note = try await store.addNote(fileID: fileID, text: "Follow up with the team.")
        let notes = try await store.notes(forFileID: fileID)
        #expect(notes.first?.id == note.id)
        #expect(notes.first?.file?.name == "Plan.md")

        let conversation = try await store.createConversation(mode: .answer)
        let user = try await store.appendMessage(
            conversationID: conversation.id,
            role: .user,
            content: "What is planned?"
        )
        #expect(!user.content.isEmpty)
        _ = try await store.appendMessage(
            conversationID: conversation.id,
            role: .assistant,
            content: "The local search index ships this week [1].",
            citations: []
        )

        let messages = try await store.messages(conversationID: conversation.id)
        #expect(messages.count == 2)
        #expect(messages.last?.role == .assistant)

        let stats = try await store.stats()
        #expect(stats.fileCount == 1)
        #expect(stats.folderCount == 1)

        let timeline = try await store.timeline()
        #expect(timeline.contains { $0.kind == .note })
        #expect(timeline.contains { $0.kind == .conversation })
    }

    @Test("Resetting the index keeps the selected folders")
    func resetIndexKeepsFolders() async throws {
        let folder = try await store.addFolder(
            path: directory.appendingPathComponent("Keep").path,
            bookmark: nil
        )
        _ = try await saveFile(
            folderID: folder.id,
            name: "Disposable.txt",
            kind: .text,
            text: "Temporary searchable content."
        )

        try await store.resetIndex()
        let stats = try await store.stats()
        #expect(stats.fileCount == 0)
        #expect(stats.chunkCount == 0)
        let folders = try await store.folders()
        #expect(folders.count == 1)
        #expect(folders.first?.id == folder.id)
    }

    @Test("Erasing all content clears files, folders, notes, and conversations")
    func eraseAllContentClearsEverything() async throws {
        let folder = try await store.addFolder(
            path: directory.appendingPathComponent("Erase").path,
            bookmark: nil
        )
        _ = try await saveFile(
            folderID: folder.id,
            name: "Gone.txt",
            kind: .text,
            text: "This should disappear."
        )
        _ = try await store.addNote(fileID: nil, text: "A private note.")
        let conversation = try await store.createConversation(mode: .summarize)
        _ = try await store.appendMessage(
            conversationID: conversation.id,
            role: .user,
            content: "Hello"
        )

        try await store.eraseAllContent()

        let stats = try await store.stats()
        #expect(stats.fileCount == 0)
        let folders = try await store.folders()
        let notes = try await store.notes()
        let conversations = try await store.conversations()
        #expect(folders.isEmpty)
        #expect(notes.isEmpty)
        #expect(conversations.isEmpty)
    }

    private func saveFile(
        folderID: Int64,
        name: String,
        kind: ContentKind,
        text: String,
        embedding: [Float]? = nil,
        model: String? = nil,
        page: Int? = nil
    ) async throws -> Int64 {
        let input = FileWriteInput(
            folderID: folderID,
            path: directory.appendingPathComponent(name).path,
            name: name,
            kind: kind,
            fileSize: Int64(text.count),
            modifiedAt: Date(),
            pageCount: page,
            duration: nil,
            thumbnailPath: nil,
            featurePrint: nil,
            embeddingModel: model
        )
        return try await store.saveFile(input, chunks: [
            ChunkWriteInput(
                index: 0,
                text: text,
                locator: ContentLocator(page: page),
                embedding: embedding.map(VectorMath.normalized)
            )
        ])
    }
}
