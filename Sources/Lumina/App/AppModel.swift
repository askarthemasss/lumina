import Foundation
import AppKit
import Observation

// MARK: - Navigation

enum AppRoute: String, CaseIterable, Identifiable {
    case home
    case search
    case chat
    case library
    case timeline
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .search: "Search"
        case .chat: "Ask Lumina"
        case .library: "Library"
        case .timeline: "Timeline"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .search: "magnifyingglass"
        case .chat: "text.bubble"
        case .library: "square.grid.2x2"
        case .timeline: "clock"
        case .settings: "gearshape"
        }
    }

    var keyNumber: Int {
        switch self {
        case .home: 1
        case .search: 2
        case .chat: 3
        case .library: 4
        case .timeline: 5
        case .settings: 6
        }
    }
}

// MARK: - Verification

enum VerificationState: Equatable {
    case idle
    case testing
    case success(String)
    case failure(String)
}

// MARK: - App model

@MainActor
@Observable
final class AppModel {
    let settings: AppSettings
    private let store: IndexStore
    private let searchService: SearchService
    private let ragService: RAGService
    private let indexer: IndexingEngine
    let dataDirectory: URL
    let thumbnailsDirectory: URL

    // Navigation & global UI
    var route: AppRoute = .home
    var pendingSearchQuery: String?
    var pendingLibraryFileID: Int64?
    var errorBanner: UserFacingError?
    var infoMessage: String?
    var showWhyLocal = false
    var showEraseConfirmation = false

    // Setup
    var setup = SetupSnapshot(isChecking: true)
    var isRefreshingSetup = false
    var isPullingModels = false
    var pullProgress: PullProgress?
    var pullTask: Task<Void, Never>?
    var setupError: String?
    var verificationState: VerificationState = .idle

    // Library
    var folders: [IndexedFolder] = []
    var stats = LibraryStats.empty
    var recentFiles: [IndexedFile] = []
    var pinnedFiles: [IndexedFile] = []
    var indexedEmbeddingModels: [String] = []

    // Indexing
    var indexingProgress = IndexingProgress()
    var isIndexing = false
    var lastIndexSummary: IndexingSummary?
    var lastIndexCompletedAt: Date?
    private var indexTask: Task<Void, Never>?
    private var autoScanTask: Task<Void, Never>?
    private var hasBootstrapped = false

    // Timeline
    var timelineItems: [TimelineItem] = []
    var notes: [UserNote] = []

    // Chat
    var conversations: [Conversation] = []
    var activeConversation: Conversation?
    var chatMessages: [ChatMessage] = []
    var chatSources: [Citation] = []
    var chatMode: ChatMode = .answer
    var isStreaming = false
    var streamingText = ""
    var chatError: String?
    private var chatTask: Task<Void, Never>?

    init() throws {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lumina", isDirectory: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        let databaseURL = support.appendingPathComponent("lumina.sqlite")
        let thumbs = support.appendingPathComponent("thumbnails", isDirectory: true)
        try fileManager.createDirectory(at: thumbs, withIntermediateDirectories: true)

        self.dataDirectory = support
        self.thumbnailsDirectory = thumbs
        self.settings = AppSettings()
        let store = try IndexStore(databaseURL: databaseURL)
        self.store = store
        self.searchService = SearchService(store: store)
        self.ragService = RAGService(store: store)
        self.indexer = IndexingEngine(store: store, thumbnailsDirectory: thumbs)
    }

    // MARK: Derived state

    var isRuntimeReachable: Bool { setup.isReachable }

    var isEmbeddingModelInstalled: Bool {
        RuntimeDiscovery.isConfiguredModel(settings.embeddingModel, in: setup.models)
    }

    var isChatModelInstalled: Bool {
        RuntimeDiscovery.isConfiguredModel(settings.chatModel, in: setup.models)
    }

    var isFullyConfigured: Bool {
        setup.isReachable && isEmbeddingModelInstalled && isChatModelInstalled
    }

    var hasFolders: Bool { !folders.isEmpty }

    var pendingEmbeddingChunkCount: Int {
        max(0, stats.chunkCount - stats.embeddedChunkCount)
    }

    var embeddingModelMismatch: Bool {
        guard stats.embeddedChunkCount > 0 else { return false }
        let current = LocalInferenceClient.canonicalModelName(settings.embeddingModel).lowercased()
        return !indexedEmbeddingModels.contains { LocalInferenceClient.canonicalModelName($0).lowercased() == current }
    }

    var hasIndexedContent: Bool { stats.fileCount > 0 }

    var currentEmbeddingModelIsInstalled: Bool { isEmbeddingModelInstalled }

    // MARK: Bootstrap

    func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        await refreshFolders()
        await refreshLibrary()
        await refreshSetup()
        await refreshConversations()
        await refreshTimeline()
        startAutoScanLoop()

        if settings.autoIndexEnabled, !folders.isEmpty, isFullyConfigured {
            startIndexing(force: false)
        }
    }

    private func startAutoScanLoop() {
        autoScanTask?.cancel()
        autoScanTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, !Task.isCancelled else { return }
                guard self.settings.autoIndexEnabled,
                      !self.isIndexing,
                      !self.isPullingModels,
                      !self.isStreaming,
                      !self.folders.isEmpty,
                      self.isFullyConfigured else { continue }
                let interval = TimeInterval(self.settings.autoScanMinutes * 60)
                let last = self.lastIndexCompletedAt ?? .distantPast
                if Date().timeIntervalSince(last) >= interval {
                    self.startIndexing(force: false)
                }
            }
        }
    }

    // MARK: Setup

    func refreshSetup() async {
        guard !isRefreshingSetup else { return }
        isRefreshingSetup = true
        setup.isChecking = true
        defer {
            isRefreshingSetup = false
            setup.isChecking = false
        }
        let snapshot = await RuntimeDiscovery.snapshot(configuration: settings.inferenceConfiguration)
        setup = snapshot
        if let error = snapshot.error {
            setupError = error
        } else {
            setupError = nil
        }
    }

    func verifySetup() async {
        verificationState = .testing
        await refreshSetup()
        guard setup.isReachable else {
            verificationState = .failure(setup.error ?? "The local model server isn't reachable.")
            return
        }
        guard isEmbeddingModelInstalled else {
            verificationState = .failure("Install the embedding model \(settings.embeddingModel), then try again.")
            return
        }
        guard isChatModelInstalled else {
            verificationState = .failure("Install the chat model \(settings.chatModel), then try again.")
            return
        }
        do {
            let client = try LocalInferenceClient(configuration: settings.inferenceConfiguration)
            let vectors = try await client.embed(
                texts: ["Lumina local index verification."],
                model: settings.embeddingModel
            )
            guard let vector = vectors.first, !vector.isEmpty else {
                verificationState = .failure("The embedding model responded without a vector.")
                return
            }
            verificationState = .success("Models responded locally. Lumina is ready.")
            infoMessage = "Local models are ready."
            if !folders.isEmpty, settings.autoIndexEnabled {
                startIndexing(force: false)
            }
        } catch {
            verificationState = .failure(error.localizedDescription)
        }
    }

    func openOllama() {
        guard let url = setup.installation.appURL else {
            openOllamaDownload()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            Task { @MainActor in
                if let error {
                    self?.errorBanner = UserFacingError("Couldn't open Ollama", message: error.localizedDescription)
                }
                try? await Task.sleep(for: .seconds(1.5))
                await self?.refreshSetup()
            }
        }
    }

    func openOllamaDownload() {
        if let url = URL(string: "https://ollama.com/download") {
            NSWorkspace.shared.open(url)
        }
    }

    func pullRecommendedModels() {
        guard !isPullingModels else { return }
        guard settings.runtimeKind == .ollama else {
            setupError = "Automatic downloads are available with Ollama. Load the models in your MLX server, then refresh."
            return
        }
        let recommendation = settings.recommendation
        isPullingModels = true
        setupError = nil
        verificationState = .idle
        pullProgress = nil

        pullTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isPullingModels = false
                self.pullProgress = nil
                self.pullTask = nil
            }
            do {
                await self.refreshSetup()
                guard self.setup.isReachable else {
                    throw InferenceError.invalidResponse(
                        self.setup.error ?? "Ollama isn't running. Open Ollama and try again."
                    )
                }
                guard let client = try? LocalInferenceClient(configuration: self.settings.inferenceConfiguration) else {
                    throw InferenceError.invalidEndpoint
                }

                let models = [recommendation.embeddingModel, recommendation.chatModel]
                for model in models {
                    let alreadyInstalled = RuntimeDiscovery.isConfiguredModel(model, in: self.setup.models)
                    if alreadyInstalled {
                        self.pullProgress = PullProgress(
                            model: model,
                            status: "Already installed",
                            completedBytes: 0,
                            totalBytes: 0,
                            phase: .complete
                        )
                        continue
                    }
                    try Task.checkCancellation()
                    for try await event in client.pullModel(model) {
                        self.pullProgress = event
                    }
                    let refreshed = await RuntimeDiscovery.snapshot(configuration: self.settings.inferenceConfiguration)
                    self.setup = refreshed
                }

                self.settings.embeddingModel = recommendation.embeddingModel
                self.settings.chatModel = recommendation.chatModel
                await self.refreshSetup()
                self.verificationState = .idle
                self.infoMessage = "Models are installed. You can verify them in the setup guide."
                if !self.folders.isEmpty, self.settings.autoIndexEnabled {
                    self.startIndexing(force: false, userInitiated: false)
                }
            } catch is CancellationError {
                self.infoMessage = "Model download stopped."
            } catch {
                self.setupError = error.localizedDescription
            }
        }
    }

    func cancelModelPull() {
        pullTask?.cancel()
    }

    // MARK: Folders

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Add a folder to Lumina"
        panel.message = "Choose a folder containing documents, photos, or media you want to search. Lumina only reads the folders you select."
        panel.prompt = "Add Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        Task { [weak self] in
            await self?.addFolder(url: url, bookmark: bookmark)
        }
    }

    func addFolder(url: URL, bookmark: Data? = nil) async {
        do {
            _ = try await store.addFolder(path: url.path, bookmark: bookmark)
            await refreshFolders()
            await refreshStats()
            infoMessage = "Added \(url.lastPathComponent)."
            if isFullyConfigured, settings.autoIndexEnabled {
                startIndexing(force: false)
            }
        } catch {
            present(error, title: "Couldn't add folder")
        }
    }

    func removeFolder(_ folder: IndexedFolder) async {
        await stopIndexing()
        do {
            try await store.removeFolder(id: folder.id)
            await refreshFolders()
            await refreshLibrary()
            await refreshTimeline()
            await cleanOrphanedThumbnails()
        } catch {
            present(error, title: "Couldn't remove folder")
        }
    }

    func setFolderEnabled(_ folder: IndexedFolder, enabled: Bool) async {
        do {
            try await store.setFolderEnabled(folder.id, enabled: enabled)
            await refreshFolders()
            if enabled, isFullyConfigured, settings.autoIndexEnabled {
                startIndexing(force: false)
            }
        } catch {
            present(error, title: "Couldn't update folder")
        }
    }

    func refreshFolders() async {
        do {
            folders = try await store.folders()
        } catch {
            present(error, title: "Couldn't load folders")
        }
    }

    // MARK: Library data

    func refreshLibrary() async {
        do {
            async let statsTask = store.stats()
            async let recentTask = store.recentFiles(limit: 12)
            async let pinnedTask = store.pinnedFiles(limit: 8)
            async let modelsTask = store.indexedEmbeddingModels()
            stats = try await statsTask
            recentFiles = try await recentTask
            pinnedFiles = try await pinnedTask
            indexedEmbeddingModels = try await modelsTask
        } catch {
            present(error, title: "Couldn't load the library")
        }
    }

    func refreshStats() async {
        do {
            stats = try await store.stats()
        } catch {
            present(error, title: "Couldn't read index statistics")
        }
    }

    func loadLibraryFiles(
        kinds: Set<ContentKind> = [],
        folderID: Int64? = nil,
        search: String = ""
    ) async -> [IndexedFile] {
        do {
            return try await store.libraryFiles(kinds: kinds, folderID: folderID, search: search)
        } catch {
            present(error, title: "Couldn't load files")
            return []
        }
    }

    func loadFile(id: Int64) async -> IndexedFile? {
        try? await store.file(id: id)
    }

    func loadNotes(for fileID: Int64) async -> [UserNote] {
        (try? await store.notes(forFileID: fileID)) ?? []
    }

    func loadChunks(for fileID: Int64, limit: Int = 240) async -> [StoredChunk] {
        (try? await store.chunks(forFileID: fileID, limit: limit)) ?? []
    }

    func togglePin(fileID: Int64) async -> Bool {
        do {
            let pinned = try await store.togglePin(fileID: fileID)
            await refreshLibrary()
            await refreshTimeline()
            return pinned
        } catch {
            present(error, title: "Couldn't update pin")
            return false
        }
    }

    // MARK: Search

    func search(query: String, filters: SearchFilters, limit: Int = 50) async -> SearchOutcome {
        await searchService.search(
            query: query,
            filters: filters,
            configuration: settings.inferenceConfiguration,
            limit: limit
        )
    }

    func showAllResults(for query: String) {
        pendingSearchQuery = query
        route = .search
        NotificationCenter.default.post(name: .luminaOpenMainWindow, object: nil)
    }

    /// Opens a specific file's preview inside the Library. Used by Quick Search
    /// and the timeline so every surface leads back to the same inspection view.
    func showFileInLibrary(_ file: IndexedFile) {
        pendingLibraryFileID = file.id
        route = .library
        NotificationCenter.default.post(name: .luminaOpenMainWindow, object: nil)
    }

    func showFileInLibrary(id: Int64) async {
        guard let file = await loadFile(id: id) else { return }
        showFileInLibrary(file)
    }

    // MARK: Indexing

    func startIndexing(force: Bool = false, userInitiated: Bool = true) {
        guard !isIndexing else {
            if userInitiated { infoMessage = "Indexing is already running." }
            return
        }
        guard !folders.isEmpty else {
            if userInitiated {
                errorBanner = UserFacingError("Add a folder first",
                                              message: "Choose at least one folder in Settings or from the Home screen.")
            }
            return
        }

        isIndexing = true
        indexingProgress = IndexingProgress(phase: .scanning, startedAt: Date())
        lastIndexSummary = nil
        let folderSnapshot = folders
        let options = settings.indexingOptions
        let configuration = settings.inferenceConfiguration

        indexTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let engine = self.indexer
            let pollTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    let snapshot = await engine.snapshot()
                    self?.indexingProgress = snapshot
                    try? await Task.sleep(for: .milliseconds(280))
                }
            }
            let summary = await engine.run(
                folders: folderSnapshot,
                options: options,
                configuration: configuration,
                force: force
            )
            pollTask.cancel()
            self.indexingProgress = await engine.snapshot()
            self.isIndexing = false
            self.lastIndexSummary = summary
            self.lastIndexCompletedAt = Date()
            self.indexTask = nil

            await self.refreshLibrary()
            await self.refreshTimeline()

            if summary.cancelled {
                self.infoMessage = "Indexing paused. Your existing index is intact."
            } else if summary.failed > 0 {
                self.infoMessage = "Indexed \(summary.processed) new or updated file\(summary.processed == 1 ? "" : "s"); \(summary.failed) couldn't be read."
            } else if userInitiated {
                self.infoMessage = summary.processed > 0
                    ? "Indexed \(summary.processed) file\(summary.processed == 1 ? "" : "s")."
                    : "Index is up to date."
            }
            if !summary.warnings.isEmpty, userInitiated {
                self.setupError = summary.warnings.first
            }
        }
    }

    func cancelIndexing() {
        indexTask?.cancel()
    }

    func stopIndexing() async {
        guard let task = indexTask else { return }
        task.cancel()
        await task.value
    }

    func reindexAll() {
        startIndexing(force: true)
    }

    func resetIndex() async {
        await stopIndexing()
        do {
            try await store.resetIndex()
            try? clearDirectoryContents(thumbnailsDirectory)
            await refreshLibrary()
            await refreshTimeline()
            infoMessage = "Index cleared. Your folders are still selected."
        } catch {
            present(error, title: "Couldn't reset the index")
        }
    }

    func eraseAllData() async {
        await stopIndexing()
        pullTask?.cancel()
        chatTask?.cancel()
        do {
            try await store.eraseAllContent()
            try? clearDirectoryContents(thumbnailsDirectory)
            settings.resetPreferences()
            route = .home
            activeConversation = nil
            chatMessages = []
            chatSources = []
            conversations = []
            timelineItems = []
            notes = []
            recentFiles = []
            pinnedFiles = []
            stats = .empty
            await refreshFolders()
            await refreshSetup()
            infoMessage = "All local Lumina data has been erased."
        } catch {
            present(error, title: "Couldn't erase data")
        }
    }

    func openDataFolder() {
        NSWorkspace.shared.open(dataDirectory)
    }

    private func cleanOrphanedThumbnails() async {
        // Thumbnails are content-addressed and cheap to regenerate. Removing
        // unreferenced files here keeps privacy guarantees after folder removal.
        let known = (try? await store.referencedThumbnailPaths()) ?? []
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: thumbnailsDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        for file in files where !known.contains(file.path) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func clearDirectoryContents(_ url: URL) throws {
        let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        for item in contents {
            try? FileManager.default.removeItem(at: item)
        }
    }

    // MARK: Timeline & notes

    func refreshTimeline() async {
        do {
            async let itemsTask = store.timeline(limit: 90)
            async let notesTask = store.notes(limit: 60)
            timelineItems = try await itemsTask
            notes = try await notesTask
        } catch {
            present(error, title: "Couldn't load the timeline")
        }
    }

    @discardableResult
    func addNote(text: String, fileID: Int64? = nil) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            _ = try await store.addNote(fileID: fileID, text: trimmed)
            await refreshTimeline()
            return true
        } catch {
            present(error, title: "Couldn't save note")
            return false
        }
    }

    func deleteNote(id: Int64) async {
        do {
            try await store.deleteNote(id: id)
            await refreshTimeline()
        } catch {
            present(error, title: "Couldn't delete note")
        }
    }

    // MARK: Chat

    func refreshConversations() async {
        conversations = (try? await store.conversations(limit: 60)) ?? []
    }

    func newConversation(mode: ChatMode? = nil) {
        if let mode { chatMode = mode }
        activeConversation = nil
        chatMessages = []
        chatSources = []
        chatError = nil
        streamingText = ""
        isStreaming = false
    }

    func selectConversation(_ conversation: Conversation) async {
        chatTask?.cancel()
        activeConversation = conversation
        chatMode = conversation.mode
        chatError = nil
        streamingText = ""
        isStreaming = false
        do {
            chatMessages = try await store.messages(conversationID: conversation.id)
            chatSources = chatMessages.last(where: { $0.role == .assistant })?.citations ?? []
        } catch {
            present(error, title: "Couldn't load conversation")
        }
    }

    func deleteConversation(_ conversation: Conversation) async {
        do {
            try await store.deleteConversation(id: conversation.id)
            if activeConversation?.id == conversation.id {
                newConversation()
            }
            await refreshConversations()
            await refreshTimeline()
        } catch {
            present(error, title: "Couldn't delete conversation")
        }
    }

    func setChatMode(_ mode: ChatMode) {
        chatMode = mode
        guard var conversation = activeConversation, conversation.mode != mode else { return }
        conversation = Conversation(
            id: conversation.id,
            title: conversation.title,
            mode: mode,
            createdAt: conversation.createdAt,
            updatedAt: Date(),
            messageCount: conversation.messageCount
        )
        activeConversation = conversation
        Task {
            try? await store.updateConversationMode(id: conversation.id, mode: mode)
            await refreshConversations()
        }
    }

    func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }
        chatError = nil
        chatSources = []
        streamingText = ""
        isStreaming = true
        chatTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performSend(trimmed)
            self.isStreaming = false
            self.streamingText = ""
            self.chatTask = nil
        }
    }

    func cancelChat() {
        chatTask?.cancel()
    }

    private func performSend(_ text: String) async {
        let history = chatMessages

        let conversation: Conversation
        do {
            if let activeConversation {
                conversation = activeConversation
            } else {
                let created = try await store.createConversation(mode: chatMode)
                conversation = created
                activeConversation = created
            }
            let userMessage = try await store.appendMessage(
                conversationID: conversation.id,
                role: .user,
                content: text
            )
            chatMessages.append(userMessage)
            if history.isEmpty || conversation.title == "New conversation" {
                let title = String(text.prefix(54))
                try? await store.updateConversationTitle(id: conversation.id, title: title)
                activeConversation = Conversation(
                    id: conversation.id,
                    title: title,
                    mode: chatMode,
                    createdAt: conversation.createdAt,
                    updatedAt: Date(),
                    messageCount: conversation.messageCount + 1
                )
            }
            await refreshConversations()
        } catch {
            present(error, title: "Couldn't save your message")
            return
        }

        if Task.isCancelled {
            await saveStoppedResponse(conversation: conversation, citations: [], partial: "")
            return
        }

        let request = await ragService.prepare(
            question: text,
            mode: chatMode,
            history: history,
            configuration: settings.inferenceConfiguration
        )
        chatSources = request.citations

        if Task.isCancelled {
            await finishCancelledStream(request: request, conversation: conversation)
            return
        }

        if !request.hasSources {
            let content = request.noSourcesMessage
            do {
                if let errorWarning = request.warning {
                    chatError = errorWarning
                }
                let message = try await store.appendMessage(
                    conversationID: conversation.id,
                    role: .assistant,
                    content: content,
                    citations: []
                )
                chatMessages.append(message)
                await refreshConversations()
                await refreshTimeline()
            } catch {
                present(error, title: "Couldn't save the response")
            }
            return
        }

        do {
            let stream = try await ragService.stream(
                request,
                configuration: settings.inferenceConfiguration
            )
            for try await token in stream {
                if Task.isCancelled { break }
                streamingText += token
            }

            if Task.isCancelled {
                await finishCancelledStream(request: request, conversation: conversation)
                return
            }

            let finalText = streamingText
            guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw InferenceError.invalidResponse("The model returned an empty answer.")
            }
            let saved = try await store.appendMessage(
                conversationID: conversation.id,
                role: .assistant,
                content: finalText,
                citations: request.citations
            )
            chatMessages.append(saved)
            await refreshConversations()
            await refreshTimeline()
        } catch is CancellationError {
            await finishCancelledStream(request: request, conversation: conversation)
        } catch {
            if Task.isCancelled || Self.isCancellation(error) {
                await finishCancelledStream(request: request, conversation: conversation)
                return
            }
            chatError = error.localizedDescription
            if let message = try? await store.appendMessage(
                conversationID: conversation.id,
                role: .assistant,
                content: "I couldn't finish that answer. \(error.localizedDescription)",
                citations: request.citations,
                isError: true
            ) {
                chatMessages.append(message)
                await refreshConversations()
            }
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    private func finishCancelledStream(request: RAGRequest, conversation: Conversation) async {
        let partial = streamingText
        streamingText = ""
        await saveStoppedResponse(
            conversation: conversation,
            citations: request.citations,
            partial: partial
        )
    }

    private func saveStoppedResponse(
        conversation: Conversation,
        citations: [Citation],
        partial: String
    ) async {
        let trimmed = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = trimmed.isEmpty ? "Stopped." : trimmed + "\n\n_(Stopped.)_"
        if let message = try? await store.appendMessage(
            conversationID: conversation.id,
            role: .assistant,
            content: content,
            citations: citations
        ) {
            chatMessages.append(message)
            await refreshConversations()
            await refreshTimeline()
        }
    }

    // MARK: Error presentation

    func present(_ error: Error, title: String) {
        errorBanner = UserFacingError(title, message: error.localizedDescription)
    }

    func dismissError() {
        errorBanner = nil
    }
}

// MARK: - Runtime environment

/// Creates the single app model before SwiftUI's first render so AppKit
/// services (global hotkey, quick search) can share the same state.
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let model: AppModel?
    let startupError: String?

    private init() {
        do {
            self.model = try AppModel()
            self.startupError = nil
        } catch {
            self.model = nil
            self.startupError = error.localizedDescription
        }
    }
}
