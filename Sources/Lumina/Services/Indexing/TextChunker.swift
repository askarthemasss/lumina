import Foundation

struct ChunkDraft: Sendable {
    var text: String
    var page: Int?
    var line: Int?
    var timeStart: TimeInterval?
    var timeEnd: TimeInterval?
}

enum TextChunker {
    static let targetCharacters = 1_400
    static let overlapCharacters = 180
    static let overlapLines = 3

    /// Line-aware chunking for source code and plain text. Line numbers mean
    /// search results can open exactly where the match was found.
    static func lineChunks(
        _ text: String,
        target: Int = targetCharacters,
        overlapLines: Int = overlapLines
    ) -> [ChunkDraft] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let lines = normalized.components(separatedBy: "\n")
        var chunks: [ChunkDraft] = []
        var start = 0

        while start < lines.count {
            var end = start
            var length = 0
            while end < lines.count {
                let lineLength = lines[end].count + 1
                if end > start, length + lineLength > target { break }
                length += lineLength
                end += 1
                if length >= target { break }
            }
            if end == start { end += 1 }

            let body = lines[start..<end].joined(separator: "\n")
            if body.count > target * 3 {
                for piece in characterChunks(body, target: target) {
                    chunks.append(ChunkDraft(text: piece, page: nil, line: start + 1,
                                             timeStart: nil, timeEnd: nil))
                }
            } else if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chunks.append(ChunkDraft(text: body, page: nil, line: start + 1,
                                         timeStart: nil, timeEnd: nil))
            }

            if end >= lines.count { break }
            let nextStart = max(start + 1, end - overlapLines)
            start = nextStart
        }
        return chunks
    }

    /// Character-window chunking for prose, PDFs, and extracted office text
    /// where exact line numbers are less meaningful than readable context.
    static func characterChunks(
        _ text: String,
        target: Int = targetCharacters,
        overlap: Int = overlapCharacters
    ) -> [String] {
        let cleaned = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{0000}", with: "")
        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        var chunks: [String] = []
        var start = cleaned.startIndex
        let end = cleaned.endIndex

        while start < end {
            let hardEnd = cleaned.index(start, offsetBy: target, limitedBy: end) ?? end
            var cut = hardEnd
            if hardEnd < end {
                let searchStart = cleaned.index(start, offsetBy: target / 2, limitedBy: hardEnd) ?? start
                let candidateRange = searchStart..<hardEnd
                if let breakPoint = cleaned[candidateRange].lastIndex(where: {
                    $0 == "\n" || $0 == "." || $0 == "!" || $0 == "?" || $0 == " "
                }) {
                    cut = cleaned.index(after: breakPoint)
                }
            }

            let piece = String(cleaned[start..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { chunks.append(piece) }
            guard cut < end else { break }

            let overlapStart = cleaned.index(cut, offsetBy: -overlap, limitedBy: start) ?? start
            if overlapStart == start {
                start = cut
            } else {
                // Start the next chunk at a word boundary near the overlap.
                let range = overlapStart..<cut
                if let boundary = cleaned[range].firstIndex(where: { $0 == " " || $0 == "\n" || $0 == "." }) {
                    start = cleaned.index(after: boundary)
                } else {
                    start = overlapStart
                }
            }
            if start <= cleaned.startIndex && cut == hardEnd { break }
        }
        return chunks
    }

    static func pageChunks(text: String, page: Int) -> [ChunkDraft] {
        characterChunks(text).map { piece in
            ChunkDraft(text: piece, page: page, line: nil, timeStart: nil, timeEnd: nil)
        }
    }

    static func normalizedWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Small HTML reader

/// HTML files are converted with a deliberately small, offline reader. It
/// never loads remote images, scripts, or stylesheets.
enum HTMLTextReader {
    static func read(url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        var text = raw
        for pattern in [
            "(?is)<script[^>]*>.*?</script>",
            "(?is)<style[^>]*>.*?</style>",
            "(?is)<head[^>]*>.*?</head>",
            "(?is)<!--.*?-->"
        ] {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        text = text
            .replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "(?i)</(p|div|li|h[1-6]|tr|section|article)>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "(?s)<[^>]+>", with: " ", options: .regularExpression)
        let entities = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&mdash;": "—",
            "&ndash;": "–", "&hellip;": "…", "&rsquo;": "’", "&lsquo;": "‘",
            "&ldquo;": "“", "&rdquo;": "”"
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return TextChunker.normalizedWhitespace(text)
    }
}
