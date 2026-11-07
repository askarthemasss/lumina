import Foundation

// MARK: - Supported formats

enum SupportedFileTypes {
    static let text: Set<String> = [
        "txt", "md", "markdown", "rst", "log", "json", "yaml", "yml",
        "toml", "ini", "conf", "cfg", "xml", "tex", "org", "opml"
    ]

    static let code: Set<String> = [
        "swift", "py", "pyw", "js", "jsx", "mjs", "cjs", "ts", "tsx",
        "go", "rs", "java", "kt", "kts", "c", "cc", "cpp", "cxx", "h",
        "hpp", "cs", "rb", "php", "sh", "bash", "zsh", "fish", "sql",
        "css", "scss", "sass", "less", "vue", "svelte", "dart", "lua",
        "r", "m", "mm", "pl", "pm", "ex", "exs", "clj", "cljs", "hs",
        "elm", "zig", "nim", "sol", "proto", "graphql", "gql", "dockerfile",
        "makefile", "cmake"
    ]

    static let documents: Set<String> = [
        "pdf", "docx", "doc", "rtf", "rtfd", "html", "htm", "odt"
    ]

    static let spreadsheets: Set<String> = [
        "xlsx", "ods", "csv", "tsv"
    ]

    static let presentations: Set<String> = [
        "pptx", "odp"
    ]

    static let images: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "webp", "gif",
        "tiff", "tif", "bmp", "avif"
    ]

    static let audio: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ogg", "opus", "caf"
    ]

    static let video: Set<String> = [
        "mp4", "mov", "m4v", "avi"
    ]

    static func kind(forExtension ext: String, includeCode: Bool) -> ContentKind? {
        let lower = ext.lowercased()
        if images.contains(lower) { return .image }
        if audio.contains(lower) { return .audio }
        if video.contains(lower) { return .video }
        if presentations.contains(lower) { return .presentation }
        if spreadsheets.contains(lower) { return .spreadsheet }
        if documents.contains(lower) { return .document }
        if includeCode, code.contains(lower) { return .code }
        if text.contains(lower) { return .text }
        return nil
    }
}

// MARK: - Candidate

struct FileCandidate: Sendable, Identifiable {
    var id: String { path.path }
    let url: URL
    let name: String
    let kind: ContentKind
    let fileSize: Int64
    let modifiedAt: Date
    let folderID: Int64
    let relativePath: String

    var path: URL { url }
}

struct FileScanReport: Sendable {
    var candidates: [FileCandidate] = []
    var seenPaths: Set<String> = []
    var skipped: Int = 0
    var unsupported: Int = 0
    var inaccessible: Int = 0
}

// MARK: - Exclusions

struct ExclusionRules: Sendable {
    var userPatterns: [String] = []
    var skipSensitive: Bool = true

    static let excludedDirectories: Set<String> = [
        ".git", ".svn", ".hg", ".ssh", ".gnupg", ".password-store",
        "node_modules", ".build", ".swiftpm", "deriveddata", "__pycache__",
        ".venv", "venv", ".tox", ".next", ".nuxt", ".cache", "caches",
        ".npm", ".pnpm-store", ".yarn", ".gradle", ".m2", ".docker",
        ".trash", "trash", "xcuserdata", ".idea", ".vs", "tmp", "temp",
        ".venv3", "site-packages", "pods", ".cocoapods"
    ]

    static let sensitiveExtensions: Set<String> = [
        "key", "pem", "p12", "pfx", "cer", "crt", "der", "gpg", "asc",
        "kdbx", "keychain", "mobileprovision", "provisionprofile",
        "ovpn", "keystore", "jks", "ppk", "p8"
    ]

    static let sensitiveNames: Set<String> = [
        "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519", ".env", ".git-credentials",
        ".netrc", ".npmrc", ".pypirc", ".htpasswd", "authorized_keys",
        "known_hosts", "credentials.json", "secrets.yaml", "secrets.yml"
    ]

    func shouldSkip(directoryName name: String, relativePath: String) -> Bool {
        let lower = name.lowercased()
        if Self.excludedDirectories.contains(lower) { return true }
        if lower.hasSuffix(".photoslibrary") || lower.hasSuffix(".fcpbundle")
            || lower.hasSuffix(".sparsebundle") || lower.hasSuffix(".xcarchive") {
            return true
        }
        return matchesUserPattern(name: name, relativePath: relativePath)
    }

    func shouldSkip(fileName: String, fileExtension: String, relativePath: String) -> Bool {
        if skipSensitive {
            let lowerName = fileName.lowercased()
            if Self.sensitiveExtensions.contains(fileExtension.lowercased()) { return true }
            if Self.sensitiveNames.contains(lowerName) { return true }
            if lowerName.hasPrefix(".env.") { return true }
            if lowerName.contains("password") || lowerName.contains("passphrase")
                || lowerName.contains("credential") || lowerName.contains("secret") {
                return true
            }
        }
        return matchesUserPattern(name: fileName, relativePath: relativePath)
    }

    private func matchesUserPattern(name: String, relativePath: String) -> Bool {
        guard !userPatterns.isEmpty else { return false }
        let path = relativePath.lowercased()
        let components = path.split(separator: "/").map(String.init)
        let lowerName = name.lowercased()
        for raw in userPatterns {
            var pattern = raw.lowercased().trimmingCharacters(in: .whitespaces)
            guard !pattern.isEmpty else { continue }
            if pattern.hasPrefix("~/") { pattern = String(pattern.dropFirst(2)) }
            if pattern.hasSuffix("/") { pattern.removeLast() }
            if pattern.contains("*") || pattern.contains("?") {
                if Self.globMatch(pattern: pattern, value: lowerName) { return true }
                if Self.globMatch(pattern: pattern, value: path) { return true }
                if Self.globMatch(pattern: pattern, value: "/" + path) { return true }
            } else if lowerName == pattern || components.contains(pattern) || path == pattern {
                return true
            }
        }
        return false
    }

    private static func globMatch(pattern: String, value: String) -> Bool {
        var regex = "^"
        for character in pattern {
            switch character {
            case "*": regex += ".*"
            case "?": regex += "."
            default: regex += NSRegularExpression.escapedPattern(for: String(character))
            }
        }
        regex += "$"
        return value.range(of: regex, options: .regularExpression) != nil
    }
}

// MARK: - Scanner

enum FileScanner {
    private static let resourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
        .fileSizeKey, .contentModificationDateKey, .isPackageKey, .nameKey
    ]

    static func scan(
        folder: IndexedFolder,
        rules: ExclusionRules,
        maxFileSizeBytes: Int64,
        includeCode: Bool
    ) throws -> FileScanReport {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: folder.path, isDirectory: true)
        var report = FileScanReport()
        var enumerationErrors = 0

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in
                enumerationErrors += 1
                return true
            }
        ) else {
            throw CocoaError(.fileReadNoPermission)
        }

        var visited = 0
        while let url = enumerator.nextObject() as? URL {
            visited += 1
            if visited % 256 == 0 {
                try Task.checkCancellation()
            }

            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: resourceKeys)
            } catch {
                report.inaccessible += 1
                continue
            }

            if values.isSymbolicLink == true {
                continue
            }

            let relativePath: String
            if url.path.hasPrefix(root.path) {
                relativePath = String(url.path.dropFirst(root.path.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            } else {
                relativePath = url.lastPathComponent
            }

            if values.isDirectory == true {
                if rules.shouldSkip(directoryName: url.lastPathComponent, relativePath: relativePath) {
                    enumerator.skipDescendants()
                    report.skipped += 1
                }
                continue
            }

            guard values.isRegularFile == true else { continue }
            let ext = url.pathExtension
            let name = url.lastPathComponent
            report.seenPaths.insert(url.path)

            if rules.shouldSkip(fileName: name, fileExtension: ext, relativePath: relativePath) {
                report.skipped += 1
                continue
            }
            guard let kind = SupportedFileTypes.kind(forExtension: ext, includeCode: includeCode) else {
                report.unsupported += 1
                continue
            }
            let size = Int64(values.fileSize ?? 0)
            guard size <= maxFileSizeBytes else {
                report.skipped += 1
                continue
            }
            let modifiedAt = values.contentModificationDate ?? .distantPast
            report.candidates.append(FileCandidate(
                url: url,
                name: name,
                kind: kind,
                fileSize: size,
                modifiedAt: modifiedAt,
                folderID: folder.id,
                relativePath: relativePath
            ))
        }

        report.inaccessible += enumerationErrors
        return report
    }
}
