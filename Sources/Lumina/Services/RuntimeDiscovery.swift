import Foundation

/// Discovers local runtimes and models without launching anything or using the
/// network. The only request is to the loopback endpoint the user configured.
enum RuntimeDiscovery {
    static func snapshot(configuration: InferenceConfiguration) async -> SetupSnapshot {
        var snapshot = SetupSnapshot(isChecking: false)
        let installation = detectOllamaInstallation()

        guard let client = try? LocalInferenceClient(configuration: configuration) else {
            snapshot.installation = installation
            snapshot.error = "The endpoint must be on this Mac (localhost, 127.0.0.1, or ::1)."
            snapshot.lastChecked = Date()
            return snapshot
        }

        do {
            let version = try await client.health()
            snapshot.isReachable = true
            snapshot.models = (try? await client.listModels()) ?? []
            snapshot.installation = OllamaInstallation(
                appURL: installation.appURL,
                binaryURL: installation.binaryURL,
                isRunning: configuration.runtime == .ollama,
                version: version
            )
        } catch {
            snapshot.installation = installation
            snapshot.error = friendlyConnectionError(error, runtime: configuration.runtime, endpoint: configuration.endpoint)
        }
        snapshot.lastChecked = Date()
        return snapshot
    }

    static func detectOllamaInstallation() -> OllamaInstallation {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser

        let appCandidates = [
            URL(fileURLWithPath: "/Applications/Ollama.app"),
            home.appendingPathComponent("Applications/Ollama.app", isDirectory: true)
        ]
        let appURL = appCandidates.first { fileManager.fileExists(atPath: $0.path) }

        let binaryCandidates = [
            URL(fileURLWithPath: "/usr/local/bin/ollama"),
            URL(fileURLWithPath: "/opt/homebrew/bin/ollama"),
            home.appendingPathComponent(".local/bin/ollama"),
            URL(fileURLWithPath: "/Applications/Ollama.app/Contents/Resources/ollama")
        ]
        let binaryURL = binaryCandidates.first { fileManager.isExecutableFile(atPath: $0.path) }

        return OllamaInstallation(
            appURL: appURL,
            binaryURL: binaryURL,
            isRunning: false,
            version: nil
        )
    }

    static func friendlyConnectionError(_ error: Error, runtime: RuntimeKind, endpoint: String) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .timedOut:
                if runtime == .ollama {
                    return "Lumina couldn't reach Ollama at \(endpoint). Open Ollama, wait for it to finish starting, then check again."
                }
                return "Lumina couldn't reach the local model server at \(endpoint). Start your MLX server, then check again."
            default:
                break
            }
        }
        return error.localizedDescription
    }

    static func isConfiguredModel(_ model: String, in models: [LocalModel]) -> Bool {
        models.contains { LocalInferenceClient.modelNamesMatch($0.name, model) }
    }

    static func firstEmbeddingModel(in models: [LocalModel]) -> String? {
        models.first(where: \.isEmbedding)?.name
    }

    static func firstChatModel(in models: [LocalModel]) -> String? {
        models
            .filter { !$0.isEmbedding }
            .sorted { $0.sizeBytes > $1.sizeBytes }
            .first?
            .name
    }
}
