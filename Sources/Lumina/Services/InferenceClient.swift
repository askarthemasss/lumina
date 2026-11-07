import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

// MARK: - Value types

struct ChatPromptMessage: Sendable {
    let role: ChatRole
    let content: String
    var imagesBase64: [String] = []
}

struct ChatOptions: Sendable {
    var temperature: Double = 0.2
    var contextWindow: Int = 8_192
    var maxTokens: Int?
}

enum InferenceError: LocalizedError {
    case invalidEndpoint
    case remoteEndpoint
    case httpStatus(Int, String)
    case invalidResponse(String)
    case modelMissing(String)
    case runtimeUnsupported(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "The local endpoint is not a valid URL."
        case .remoteEndpoint:
            "Lumina only connects to model servers running on this Mac. Use localhost, 127.0.0.1, or ::1."
        case .httpStatus(let code, let message):
            "The local model server returned HTTP \(code). \(message)"
        case .invalidResponse(let message):
            "The local model server returned an unexpected response. \(message)"
        case .modelMissing(let model):
            "The model “\(model)” isn't installed or loaded."
        case .runtimeUnsupported(let detail):
            detail
        }
    }
}

// MARK: - Client

/// A small client for the two local inference runtimes Lumina supports.
/// It speaks Ollama's native API when available (for model discovery and
/// pulling) and falls back to the OpenAI-compatible HTTP shape for MLX.
///
/// The client refuses non-loopback endpoints so that the app's privacy
/// promise is enforced in code, not just in the UI.
final class LocalInferenceClient: Sendable {
    let runtime: RuntimeKind
    let baseURL: URL
    private let session: URLSession

    init(configuration: InferenceConfiguration, session: URLSession? = nil) throws {
        guard let url = configuration.baseURL else {
            throw InferenceError.invalidEndpoint
        }
        guard Self.isLoopback(url) else {
            throw InferenceError.remoteEndpoint
        }
        self.runtime = configuration.runtime
        self.baseURL = url

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = 600
        sessionConfiguration.timeoutIntervalForResource = 3_600
        sessionConfiguration.waitsForConnectivity = false
        sessionConfiguration.urlCache = nil
        self.session = session ?? URLSession(configuration: sessionConfiguration)
    }

    static func isLoopback(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "localhost"
            || host == "127.0.0.1"
            || host == "::1"
            || host == "[::1]"
            || host.hasSuffix(".localhost")
    }

    // MARK: Health & models

    func health() async throws -> String? {
        switch runtime {
        case .ollama:
            let request = try makeRequest(path: "/api/version", method: "GET")
            let (data, response) = try await session.data(for: request)
            try validate(response: response, data: data)
            struct Version: Decodable { let version: String? }
            return (try? JSONDecoder().decode(Version.self, from: data))?.version
        case .openAICompatible:
            let request = try makeRequest(path: "/v1/models", method: "GET")
            let (data, response) = try await session.data(for: request)
            try validate(response: response, data: data)
            return nil
        }
    }

    func listModels() async throws -> [LocalModel] {
        switch runtime {
        case .ollama:
            let request = try makeRequest(path: "/api/tags", method: "GET")
            let (data, response) = try await session.data(for: request)
            try validate(response: response, data: data)
            let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            return decoded.models.map { model in
                let name = model.name ?? model.model ?? "unknown"
                let details = model.details
                return LocalModel(
                    name: name,
                    sizeBytes: model.size ?? 0,
                    modifiedAt: model.modifiedAt.flatMap(Self.parseDate),
                    family: details?.family ?? "",
                    parameterSize: details?.parameterSize ?? "",
                    isEmbedding: Self.looksLikeEmbedding(name: name, family: details?.family ?? "")
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .openAICompatible:
            let request = try makeRequest(path: "/v1/models", method: "GET")
            let (data, response) = try await session.data(for: request)
            try validate(response: response, data: data)
            let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
            return decoded.data.map { model in
                LocalModel(
                    name: model.id,
                    sizeBytes: 0,
                    modifiedAt: nil,
                    family: model.ownedBy ?? "",
                    parameterSize: "",
                    isEmbedding: model.id.lowercased().contains("embed")
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    func hasModel(_ name: String) async throws -> Bool {
        let models = try await listModels()
        return models.contains { Self.modelNamesMatch($0.name, name) }
    }

    static func modelNamesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.lowercased()
        let right = rhs.lowercased()
        if left == right { return true }
        let leftBase = left.split(separator: ":").first.map(String.init) ?? left
        let rightBase = right.split(separator: ":").first.map(String.init) ?? right
        if leftBase == rightBase {
            // Treat `embeddinggemma` and `embeddinggemma:latest` as the same.
            if left.hasSuffix(":latest") || right.hasSuffix(":latest") || !left.contains(":") || !right.contains(":") {
                return true
            }
        }
        return false
    }

    /// The identifier used in vector metadata. Removing the implicit `:latest`
    /// tag avoids invalidating an index when Ollama reports a canonical name.
    static func canonicalModelName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasSuffix(":latest") {
            return String(trimmed.dropLast(":latest".count))
        }
        return trimmed
    }

    private static func looksLikeEmbedding(name: String, family: String) -> Bool {
        let haystack = (name + " " + family).lowercased()
        let hints = ["embed", "bge", "nomic", "mxbai", "minilm", "gte", "e5-", "snowflake"]
        return hints.contains { haystack.contains($0) }
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    // MARK: Embeddings

    func embed(texts: [String], model: String) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        let request: URLRequest
        switch runtime {
        case .ollama:
            request = try makeRequest(path: "/api/embed", body: [
                "model": model,
                "input": texts
            ])
        case .openAICompatible:
            request = try makeRequest(path: "/v1/embeddings", body: [
                "model": model,
                "input": texts
            ])
        }
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        switch runtime {
        case .ollama:
            let decoded = try JSONDecoder().decode(OllamaEmbeddingResponse.self, from: data)
            guard let embeddings = decoded.embeddings, !embeddings.isEmpty else {
                throw InferenceError.invalidResponse("No embeddings were returned.")
            }
            return embeddings
        case .openAICompatible:
            let decoded = try JSONDecoder().decode(OpenAIEmbeddingResponse.self, from: data)
            let ordered = decoded.data.sorted { ($0.index ?? 0) < ($1.index ?? 0) }
            guard !ordered.isEmpty else {
                throw InferenceError.invalidResponse("No embeddings were returned.")
            }
            return ordered.map(\.embedding)
        }
    }

    // MARK: Pull (Ollama only)

    func pullModel(_ name: String) -> AsyncThrowingStream<PullProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [self] in
                do {
                    guard runtime == .ollama else {
                        throw InferenceError.runtimeUnsupported(
                            "Automatic downloads are available with Ollama. For MLX, load the model in your local server first."
                        )
                    }
                    let request = try makeRequest(path: "/api/pull", body: [
                        "model": name,
                        "stream": true
                    ], timeout: 3_600)
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw InferenceError.invalidResponse("Missing HTTP response.")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var data = Data()
                        for try await byte in bytes {
                            data.append(byte)
                            if data.count > 16_384 { break }
                        }
                        throw Self.httpError(status: http.statusCode, data: data, runtime: runtime)
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard let data = line.data(using: .utf8), !data.isEmpty else { continue }
                        guard let update = try? JSONDecoder().decode(OllamaPullUpdate.self, from: data) else { continue }
                        if let error = update.error {
                            throw InferenceError.httpStatus(200, error)
                        }
                        let status = update.status ?? "Downloading"
                        continuation.yield(PullProgress(
                            model: name,
                            status: status,
                            completedBytes: update.completed ?? 0,
                            totalBytes: update.total ?? 0,
                            phase: status.lowercased() == "success" ? .complete : .pulling
                        ))
                        if status.lowercased() == "success" {
                            break
                        }
                    }
                    continuation.yield(PullProgress(
                        model: name,
                        status: "Ready",
                        completedBytes: 0,
                        totalBytes: 0,
                        phase: .complete
                    ))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: Chat

    func streamChat(
        model: String,
        messages: [ChatPromptMessage],
        options: ChatOptions = ChatOptions()
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [self] in
                do {
                    let request: URLRequest
                    switch runtime {
                    case .ollama:
                        let encodedMessages: [[String: Any]] = messages.map { message in
                            var encoded: [String: Any] = [
                                "role": message.role.rawValue,
                                "content": message.content
                            ]
                            if !message.imagesBase64.isEmpty {
                                encoded["images"] = message.imagesBase64
                            }
                            return encoded
                        }
                        var modelOptions: [String: Any] = [
                            "temperature": options.temperature,
                            "num_ctx": options.contextWindow
                        ]
                        if let maxTokens = options.maxTokens {
                            modelOptions["num_predict"] = maxTokens
                        }
                        request = try makeRequest(path: "/api/chat", body: [
                            "model": model,
                            "messages": encodedMessages,
                            "stream": true,
                            "options": modelOptions
                        ])
                    case .openAICompatible:
                        let encodedMessages = messages.map(Self.openAIMessage(_:))
                        var body: [String: Any] = [
                            "model": model,
                            "messages": encodedMessages,
                            "stream": true,
                            "temperature": options.temperature
                        ]
                        if let maxTokens = options.maxTokens {
                            body["max_tokens"] = maxTokens
                        }
                        request = try makeRequest(path: "/v1/chat/completions", body: body)
                    }

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw InferenceError.invalidResponse("Missing HTTP response.")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var data = Data()
                        for try await byte in bytes {
                            data.append(byte)
                            if data.count > 16_384 { break }
                        }
                        throw Self.httpError(status: http.statusCode, data: data, runtime: runtime)
                    }

                    switch runtime {
                    case .ollama:
                        for try await line in bytes.lines {
                            if Task.isCancelled { break }
                            guard let data = line.data(using: .utf8), !data.isEmpty else { continue }
                            guard let chunk = try? JSONDecoder().decode(OllamaChatChunk.self, from: data) else { continue }
                            if let error = chunk.error {
                                throw InferenceError.httpStatus(200, error)
                            }
                            if let content = chunk.message?.content, !content.isEmpty {
                                continuation.yield(content)
                            }
                            if chunk.done == true { break }
                        }
                    case .openAICompatible:
                        for try await line in bytes.lines {
                            if Task.isCancelled { break }
                            guard line.hasPrefix("data:") else { continue }
                            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                            if payload == "[DONE]" { break }
                            guard let data = payload.data(using: .utf8), !data.isEmpty else { continue }
                            guard let chunk = try? JSONDecoder().decode(OpenAIChatChunk.self, from: data) else { continue }
                            if let error = chunk.error?.message {
                                throw InferenceError.httpStatus(200, error)
                            }
                            if let content = chunk.choices?.first?.delta?.content, !content.isEmpty {
                                continuation.yield(content)
                            }
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    func completeChat(
        model: String,
        messages: [ChatPromptMessage],
        options: ChatOptions = ChatOptions()
    ) async throws -> String {
        var result = ""
        for try await token in streamChat(model: model, messages: messages, options: options) {
            result += token
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Builds a small local vision request. Base64 image data is sent only to
    /// the loopback inference server; it is never uploaded anywhere else.
    func describeImage(fileURL: URL, model: String, prompt: String) async throws -> String {
        guard let imageData = Self.downscaledJPEG(url: fileURL) else {
            throw InferenceError.invalidResponse("The image could not be read.")
        }
        let message = ChatPromptMessage(
            role: .user,
            content: prompt,
            imagesBase64: [imageData.base64EncodedString()]
        )
        let system = ChatPromptMessage(
            role: .system,
            content: "You describe images for a private local search index. Answer in one or two calm, factual sentences. Do not speculate about people's identity, emotions, or sensitive attributes."
        )
        return try await completeChat(
            model: model,
            messages: [system, message],
            options: ChatOptions(temperature: 0.1, contextWindow: 4_096, maxTokens: 100)
        )
    }

    private static func openAIMessage(_ message: ChatPromptMessage) -> [String: Any] {
        guard !message.imagesBase64.isEmpty else {
            return ["role": message.role.rawValue, "content": message.content]
        }
        var content: [[String: Any]] = [["type": "text", "text": message.content]]
        for image in message.imagesBase64 {
            content.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(image)"]
            ])
        }
        return ["role": message.role.rawValue, "content": content]
    }

    private static func downscaledJPEG(url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_024,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.72
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    // MARK: HTTP helpers

    private func makeRequest(path: String, method: String = "POST", body: [String: Any]? = nil, timeout: TimeInterval = 600) throws -> URLRequest {
        var normalizedPath = path
        if runtime == .openAICompatible,
           baseURL.path.hasSuffix("/v1"),
           normalizedPath.hasPrefix("/v1/") {
            normalizedPath = String(normalizedPath.dropFirst(3))
        }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw InferenceError.invalidEndpoint
        }
        var basePath = components.path
        if basePath.hasSuffix("/") { basePath.removeLast() }
        components.path = basePath + normalizedPath
        components.query = nil
        components.fragment = nil
        guard let url = components.url else {
            throw InferenceError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw InferenceError.invalidResponse("Missing HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.httpError(status: http.statusCode, data: data, runtime: runtime)
        }
    }

    private static func httpError(status: Int, data: Data, runtime: RuntimeKind) -> InferenceError {
        let message: String
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? String {
            message = error
        } else {
            let raw = String(data: data.prefix(800), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            message = raw.isEmpty ? "Check that the local model is installed." : raw
        }
        if status == 404 {
            let label = runtime == .ollama ? "Ollama" : "the local server"
            return .modelMissing("The request reached \(label), but the model or endpoint wasn't found. \(message)")
        }
        return .httpStatus(status, message)
    }
}

// MARK: - Ollama DTOs

private struct OllamaTagsResponse: Decodable {
    let models: [OllamaModelDTO]
}

private struct OllamaModelDTO: Decodable {
    let name: String?
    let model: String?
    let modifiedAt: String?
    let size: Int64?
    let details: OllamaDetailsDTO?
}

private struct OllamaDetailsDTO: Decodable {
    let family: String?
    let parameterSize: String?

    enum CodingKeys: String, CodingKey {
        case family
        case parameterSize = "parameter_size"
    }
}

private struct OllamaEmbeddingResponse: Decodable {
    let embeddings: [[Float]]?
}

private struct OllamaPullUpdate: Decodable {
    let status: String?
    let total: Int64?
    let completed: Int64?
    let error: String?
}

private struct OllamaChatChunk: Decodable {
    struct Message: Decodable {
        let content: String?
    }
    let message: Message?
    let done: Bool?
    let error: String?
}

// MARK: - OpenAI-compatible DTOs

private struct OpenAIModelsResponse: Decodable {
    struct Model: Decodable {
        let id: String
        let ownedBy: String?
        enum CodingKeys: String, CodingKey {
            case id
            case ownedBy = "owned_by"
        }
    }
    let data: [Model]
}

private struct OpenAIEmbeddingResponse: Decodable {
    struct Item: Decodable {
        let embedding: [Float]
        let index: Int?
    }
    let data: [Item]
}

private struct OpenAIChatChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }
        let delta: Delta?
    }
    struct APIError: Decodable {
        let message: String?
    }
    let choices: [Choice]?
    let error: APIError?
}
