import Foundation

// MARK: - Content

/// The broad category Lumina assigns to a file. The category drives icons,
/// filters, and which extractor is used during indexing.
enum ContentKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case text
    case code
    case pdf
    case image
    case audio
    case video
    case document
    case spreadsheet
    case presentation

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .text: "Text"
        case .code: "Code"
        case .pdf: "PDF"
        case .image: "Image"
        case .audio: "Audio"
        case .video: "Video"
        case .document: "Document"
        case .spreadsheet: "Spreadsheet"
        case .presentation: "Presentation"
        }
    }

    var pluralName: String {
        switch self {
        case .text: "Notes & Text"
        case .code: "Code"
        case .pdf: "PDFs"
        case .image: "Images"
        case .audio: "Audio"
        case .video: "Video"
        case .document: "Documents"
        case .spreadsheet: "Spreadsheets"
        case .presentation: "Presentations"
        }
    }

    var systemImage: String {
        switch self {
        case .text: "doc.text"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .pdf: "doc.richtext"
        case .image: "photo"
        case .audio: "waveform"
        case .video: "film"
        case .document: "doc"
        case .spreadsheet: "tablecells"
        case .presentation: "rectangle.on.rectangle"
        }
    }

    /// A group used in compact filter menus.
    var group: KindGroup {
        switch self {
        case .image: .images
        case .audio, .video: .media
        case .pdf, .document, .spreadsheet, .presentation, .text: .documents
        case .code: .code
        }
    }
}

enum KindGroup: String, CaseIterable, Sendable {
    case all = "All"
    case documents = "Documents"
    case images = "Images"
    case media = "Audio & Video"
    case code = "Code"

    var kinds: Set<ContentKind> {
        switch self {
        case .all: Set(ContentKind.allCases)
        case .documents: [.pdf, .document, .spreadsheet, .presentation, .text]
        case .images: [.image]
        case .media: [.audio, .video]
        case .code: [.code]
        }
    }
}

// MARK: - Folders & files

struct IndexedFolder: Identifiable, Hashable, Sendable {
    let id: Int64
    let path: String
    let name: String
    let addedAt: Date
    let isEnabled: Bool

    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
}

struct IndexedFile: Identifiable, Hashable, Sendable {
    let id: Int64
    let folderID: Int64?
    let path: String
    let name: String
    let kind: ContentKind
    let fileSize: Int64
    let modifiedAt: Date
    let indexedAt: Date
    let pageCount: Int?
    let duration: TimeInterval?
    let thumbnailPath: String?
    let chunkCount: Int
    let isPinned: Bool
    let hasEmbeddings: Bool
    let errorMessage: String?

    var url: URL { URL(fileURLWithPath: path) }
    var isScreenshot: Bool {
        let lower = name.lowercased()
        return kind == .image && (
            lower.contains("screenshot") ||
            lower.contains("screen shot") ||
            lower.contains("cleanshot") ||
            lower.contains("capture")
        )
    }
}

struct FolderChoice: Identifiable, Hashable, Sendable {
    let id: Int64
    let name: String
    let path: String
}

struct LibraryStats: Sendable, Equatable {
    var fileCount: Int = 0
    var folderCount: Int = 0
    var chunkCount: Int = 0
    var embeddedChunkCount: Int = 0
    var totalBytes: Int64 = 0
    var failedFileCount: Int = 0
    var lastIndexedAt: Date?
    var countsByKind: [ContentKind: Int] = [:]

    var hasFiles: Bool { fileCount > 0 }
    var isSemanticReady: Bool { embeddedChunkCount > 0 && embeddedChunkCount == chunkCount }

    static let empty = LibraryStats()
}

// MARK: - Search

struct SearchFilters: Sendable, Equatable {
    var kinds: Set<ContentKind> = []
    var folderIDs: Set<Int64> = []
    var dateFrom: Date?
    var dateTo: Date?
    var exactPhrase: Bool = false

    var isEmpty: Bool {
        kinds.isEmpty && folderIDs.isEmpty && dateFrom == nil && dateTo == nil && !exactPhrase
    }
}

struct ContentLocator: Codable, Hashable, Sendable {
    var page: Int?
    var line: Int?
    var timeStart: TimeInterval?
    var timeEnd: TimeInterval?

    var displayText: String? {
        if let page { return "Page \(page)" }
        if let timeStart { return Self.timecode(timeStart) }
        if let line { return "Line \(line)" }
        return nil
    }

    var compactDisplay: String? {
        if let page { return "p. \(page)" }
        if let timeStart { return Self.timecode(timeStart) }
        if let line { return "L\(line)" }
        return nil
    }

    static func timecode(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

struct SearchHit: Identifiable, Hashable, Sendable {
    let id: Int64                 // chunk id
    let file: IndexedFile
    let snippet: String
    let fullText: String
    let locator: ContentLocator
    let semanticScore: Double?
    let keywordScore: Double?
    let score: Double
    let matchCount: Int
    let isExactNameMatch: Bool

    /// Used in citations and source lists.
    var citation: Citation {
        Citation(
            chunkID: id,
            fileID: file.id,
            fileName: file.name,
            filePath: file.path,
            kind: file.kind,
            locator: locator,
            quote: Self.quote(from: fullText),
            relevance: score
        )
    }

    private static func quote(from text: String) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsed.prefix(280))
    }
}

struct SearchOutcome: Sendable {
    let hits: [SearchHit]
    let semanticUsed: Bool
    let warning: String?
    let duration: TimeInterval
}

// MARK: - Chat

enum ChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

enum ChatMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case answer
    case summarize
    case extract
    case compare

    var id: String { rawValue }

    var title: String {
        switch self {
        case .answer: "Answer"
        case .summarize: "Summarize"
        case .extract: "Extract"
        case .compare: "Compare"
        }
    }

    var systemImage: String {
        switch self {
        case .answer: "text.bubble"
        case .summarize: "text.alignleft"
        case .extract: "tablecells.badge.ellipsis"
        case .compare: "arrow.left.arrow.right"
        }
    }

    var promptInstruction: String {
        switch self {
        case .answer:
            "Answer the user's question directly and concisely using the sources. Prefer specific facts, names, dates, and numbers."
        case .summarize:
            "Produce a faithful summary of the most relevant sources. Lead with a one-paragraph overview, then key points. Preserve important names, numbers, and dates."
        case .extract:
            "Extract the information the user asks for into a clean Markdown table. Use only values found in the sources. Write 'not found' for absent fields. After the table, add a short note about ambiguity. If JSON is requested, return valid JSON in a code block."
        case .compare:
            "Compare the relevant sources. Use a compact table for meaningful differences, then state similarities and the most important conclusion. Cite each claim. If only one source is relevant, say so."
        }
    }
}

struct Citation: Identifiable, Codable, Hashable, Sendable {
    var id: Int64 { chunkID }
    let chunkID: Int64
    let fileID: Int64
    let fileName: String
    let filePath: String
    let kind: ContentKind
    let locator: ContentLocator
    let quote: String
    let relevance: Double

    var url: URL { URL(fileURLWithPath: filePath) }
}

struct ChatMessage: Identifiable, Hashable, Sendable {
    let id: Int64
    let conversationID: Int64
    let role: ChatRole
    var content: String
    let citations: [Citation]
    let createdAt: Date
    let isError: Bool
}

struct Conversation: Identifiable, Hashable, Sendable {
    let id: Int64
    let title: String
    let mode: ChatMode
    let createdAt: Date
    let updatedAt: Date
    let messageCount: Int
}

// MARK: - Timeline

enum TimelineKind: String, Sendable {
    case indexed
    case note
    case conversation
    case pinned

    var systemImage: String {
        switch self {
        case .indexed: "sparkle.magnifyingglass"
        case .note: "note.text"
        case .conversation: "bubble.left.and.bubble.right"
        case .pinned: "pin"
        }
    }
}

struct TimelineItem: Identifiable, Hashable, Sendable {
    let id: String
    let kind: TimelineKind
    let title: String
    let subtitle: String
    let date: Date
    let file: IndexedFile?
    let conversationID: Int64?
    let noteID: Int64?
    let isPinned: Bool
}

struct UserNote: Identifiable, Hashable, Sendable {
    let id: Int64
    let fileID: Int64?
    let text: String
    let createdAt: Date
    let updatedAt: Date
    let file: IndexedFile?
}

// MARK: - Models & setup

enum RuntimeKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case ollama
    case openAICompatible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ollama: "Ollama"
        case .openAICompatible: "MLX / OpenAI-compatible"
        }
    }

    var shortTitle: String {
        switch self {
        case .ollama: "Ollama"
        case .openAICompatible: "MLX"
        }
    }
}

struct InferenceConfiguration: Sendable, Equatable {
    var runtime: RuntimeKind
    var endpoint: String
    var embeddingModel: String
    var chatModel: String

    var baseURL: URL? {
        URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static let `default` = InferenceConfiguration(
        runtime: .ollama,
        endpoint: "http://127.0.0.1:11434",
        embeddingModel: "embeddinggemma",
        chatModel: "gemma4:e2b"
    )
}

struct LocalModel: Identifiable, Hashable, Sendable {
    let name: String
    let sizeBytes: Int64
    let modifiedAt: Date?
    let family: String
    let parameterSize: String
    let isEmbedding: Bool

    var id: String { name }
    var sizeDescription: String { ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file) }
}

struct ModelRecommendation: Sendable, Equatable {
    let memoryBytes: UInt64
    let chatModel: String
    let embeddingModel: String
    let chatApproxSizeGB: Double
    let note: String

    var memoryDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryBytes), countStyle: .memory)
    }

    var hasAdequateMemory: Bool { memoryBytes >= 8_000_000_000 }

    var rationale: String {
        if memoryBytes < 16_000_000_000 {
            "A compact model that leaves room for macOS and indexing."
        } else if memoryBytes < 32_000_000_000 {
            "A strong general model that fits comfortably in unified memory."
        } else if memoryBytes < 64_000_000_000 {
            "A larger model for deeper reasoning, still responsive on Apple silicon."
        } else {
            "The largest Gemma 4 model, for maximum answer quality."
        }
    }

    var pullCommands: [String] {
        ["ollama pull \(embeddingModel)", "ollama pull \(chatModel)"]
    }

    static func recommended(forMemory bytes: UInt64) -> ModelRecommendation {
        // Ollama's Gemma 4 Q4 builds are roughly 4.6 GB (e2b), 8 GB (12b),
        // 17 GB (26b), and 20 GB (31b). Keep headroom for macOS and SQLite.
        if bytes >= 64_000_000_000 {
            return .init(memoryBytes: bytes, chatModel: "gemma4:31b", embeddingModel: "embeddinggemma",
                         chatApproxSizeGB: 20, note: "Recommended for 64 GB and above.")
        } else if bytes >= 32_000_000_000 {
            return .init(memoryBytes: bytes, chatModel: "gemma4:26b", embeddingModel: "embeddinggemma",
                         chatApproxSizeGB: 17, note: "Recommended for 32 GB and above.")
        } else if bytes >= 16_000_000_000 {
            return .init(memoryBytes: bytes, chatModel: "gemma4:12b", embeddingModel: "embeddinggemma",
                         chatApproxSizeGB: 8, note: "Recommended for 16 GB and above.")
        } else {
            return .init(memoryBytes: bytes, chatModel: "gemma4:e2b", embeddingModel: "embeddinggemma",
                         chatApproxSizeGB: 4.6, note: "Recommended for 8 GB systems. For better answers, close memory-heavy apps or choose a smaller context.")
        }
    }
}

struct OllamaInstallation: Sendable, Equatable {
    var appURL: URL?
    var binaryURL: URL?
    var isRunning: Bool
    var version: String?

    var isInstalled: Bool { appURL != nil || binaryURL != nil }

    static let missing = OllamaInstallation(appURL: nil, binaryURL: nil, isRunning: false, version: nil)
}

struct SetupSnapshot: Sendable, Equatable {
    var isChecking: Bool = false
    var isReachable: Bool = false
    var installation: OllamaInstallation = .missing
    var models: [LocalModel] = []
    var error: String?
    var lastChecked: Date?

    var isRuntimeReachable: Bool {
        isReachable
    }

    var isReady: Bool { isReachable && models.contains(where: { !$0.isEmbedding }) }
}

struct ModelSetupIssue: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let detail: String
}

// MARK: - Pull / progress

struct PullProgress: Sendable, Equatable {
    enum Phase: String, Sendable {
        case pulling
        case verifying
        case complete
    }

    var model: String
    var status: String
    var completedBytes: Int64
    var totalBytes: Int64
    var phase: Phase

    var fraction: Double? {
        guard totalBytes > 0 else { return nil }
        return min(1, max(0, Double(completedBytes) / Double(totalBytes)))
    }
}

enum IndexingPhase: String, Sendable {
    case idle
    case scanning
    case indexing
    case embedding
    case finishing
    case cancelled
    case failed

    var title: String {
        switch self {
        case .idle: "Ready"
        case .scanning: "Scanning folders"
        case .indexing: "Reading files"
        case .embedding: "Creating embeddings"
        case .finishing: "Finishing up"
        case .cancelled: "Paused"
        case .failed: "Indexing stopped"
        }
    }
}

struct IndexingProgress: Sendable {
    var phase: IndexingPhase = .idle
    var filesDiscovered: Int = 0
    var filesProcessed: Int = 0
    var filesSkipped: Int = 0
    var chunksCreated: Int = 0
    var bytesProcessed: Int64 = 0
    var currentFile: String = ""
    var startedAt: Date?
    var finishedAt: Date?
    var estimatedSecondsRemaining: TimeInterval?
    var error: String?

    var fraction: Double? {
        guard phase == .indexing || phase == .embedding, filesDiscovered > 0 else { return nil }
        return min(1, Double(filesProcessed) / Double(filesDiscovered))
    }

    var isRunning: Bool {
        switch phase {
        case .scanning, .indexing, .embedding, .finishing: true
        default: false
        }
    }

    var isComplete: Bool { phase == .finishing || phase == .idle }
}

struct IndexingOptions: Sendable, Equatable {
    var maxFileSizeBytes: Int64
    var ocrEnabled: Bool
    var visionCaptionsEnabled: Bool
    var transcriptionEnabled: Bool
    var indexCode: Bool
    var skipSensitive: Bool
    var excludedPatterns: [String]

    static let `default` = IndexingOptions(
        maxFileSizeBytes: 512 * 1024 * 1024,
        ocrEnabled: true,
        visionCaptionsEnabled: false,
        transcriptionEnabled: false,
        indexCode: true,
        skipSensitive: true,
        excludedPatterns: []
    )
}

// MARK: - Errors

struct UserFacingError: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let message: String
    let isRecoverable: Bool

    init(_ title: String, message: String, isRecoverable: Bool = true) {
        self.title = title
        self.message = message
        self.isRecoverable = isRecoverable
    }
}

enum LuminaError: LocalizedError {
    case notConfigured
    case modelUnavailable(String)
    case invalidEndpoint
    case malformedResponse
    case database(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Lumina isn't connected to a local model yet."
        case .modelUnavailable(let model):
            "The model “\(model)” isn't available. Check your local runtime."
        case .invalidEndpoint:
            "The local model endpoint is not a valid URL."
        case .malformedResponse:
            "The local model returned an unexpected response."
        case .database(let detail):
            "Lumina couldn't update its local index. \(detail)"
        }
    }
}
