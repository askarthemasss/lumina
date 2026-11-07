import Foundation
import AppKit

struct OfficeSection: Sendable {
    var text: String
    var page: Int?
}

enum OfficeExtractionError: LocalizedError {
    case conversionFailed(String)
    case unzipFailed
    case emptyDocument

    var errorDescription: String? {
        switch self {
        case .conversionFailed(let detail):
            "This document couldn't be read. \(detail)"
        case .unzipFailed:
            "This Office file appears to be damaged or uses an unsupported format."
        case .emptyDocument:
            "No readable text was found in this document."
        }
    }
}

/// Extracts searchable text from office formats using native AppKit readers
/// where available and a small read-only unzip pass for OOXML packages.
/// Nothing is written to the source files and macros are never executed.
enum OfficeTextExtractor {
    static func sections(url: URL) throws -> [OfficeSection] {
        switch url.pathExtension.lowercased() {
        case "doc", "docx", "rtf", "odt":
            return try attributedSections(url: url)
        case "pptx":
            return try presentationSections(url: url)
        case "xlsx":
            return try spreadsheetSections(url: url)
        case "ods", "odp":
            return try openDocumentSections(url: url)
        default:
            throw OfficeExtractionError.conversionFailed("Unsupported office format.")
        }
    }

    private static func attributedSections(url: URL) throws -> [OfficeSection] {
        let type: NSAttributedString.DocumentType
        switch url.pathExtension.lowercased() {
        case "doc": type = .docFormat
        case "docx": type = .officeOpenXML
        case "rtf": type = .rtf
        case "odt": type = .openDocument
        default: type = .plain
        }
        do {
            let attributed = try NSAttributedString(
                url: url,
                options: [.documentType: type],
                documentAttributes: nil
            )
            let text = TextChunker.normalizedWhitespace(attributed.string)
            guard !text.isEmpty else { throw OfficeExtractionError.emptyDocument }
            return [OfficeSection(text: text, page: nil)]
        } catch let error as OfficeExtractionError {
            throw error
        } catch {
            if url.pathExtension.lowercased() == "docx" {
                return try docxFallback(url: url)
            }
            throw OfficeExtractionError.conversionFailed(error.localizedDescription)
        }
    }

    private static func docxFallback(url: URL) throws -> [OfficeSection] {
        let data = try unzip(archive: url, entry: "word/document.xml")
        let text = XMLTextCollector.collect(
            data: data,
            captureElements: ["t"],
            breakElements: ["p", "br", "tab"]
        )
        let cleaned = TextChunker.normalizedWhitespace(text)
        guard !cleaned.isEmpty else { throw OfficeExtractionError.emptyDocument }
        return [OfficeSection(text: cleaned, page: nil)]
    }

    private static func presentationSections(url: URL) throws -> [OfficeSection] {
        let listing = try unzipList(archive: url)
        let slides = listing
            .filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
            .sorted { lhs, rhs in
                slideNumber(from: lhs) < slideNumber(from: rhs)
            }
        guard !slides.isEmpty else { throw OfficeExtractionError.emptyDocument }

        var sections: [OfficeSection] = []
        for (index, entry) in slides.enumerated() {
            let data = try unzip(archive: url, entry: entry)
            let text = XMLTextCollector.collect(
                data: data,
                captureElements: ["t"],
                breakElements: ["p", "br"]
            )
            let cleaned = TextChunker.normalizedWhitespace(text)
            if !cleaned.isEmpty {
                sections.append(OfficeSection(text: cleaned, page: index + 1))
            }
        }
        guard !sections.isEmpty else { throw OfficeExtractionError.emptyDocument }
        return sections
    }

    private static func spreadsheetSections(url: URL) throws -> [OfficeSection] {
        let listing = try unzipList(archive: url)
        var sections: [OfficeSection] = []

        if listing.contains("xl/sharedStrings.xml") {
            let data = try unzip(archive: url, entry: "xl/sharedStrings.xml")
            let text = XMLTextCollector.collect(
                data: data,
                captureElements: ["t"],
                breakElements: []
            )
            let cleaned = TextChunker.normalizedWhitespace(text)
            if !cleaned.isEmpty {
                sections.append(OfficeSection(text: "Shared strings\n" + cleaned, page: nil))
            }
        }

        let sheets = listing
            .filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
            .sorted { lhs, rhs in
                sheetNumber(from: lhs) < sheetNumber(from: rhs)
            }
        for (index, entry) in sheets.enumerated() {
            let data = try unzip(archive: url, entry: entry)
            let text = XMLTextCollector.collect(
                data: data,
                captureElements: ["t", "v"],
                breakElements: ["row"]
            )
            let cleaned = TextChunker.normalizedWhitespace(text)
            if !cleaned.isEmpty {
                sections.append(OfficeSection(text: cleaned, page: index + 1))
            }
        }
        guard !sections.isEmpty else { throw OfficeExtractionError.emptyDocument }
        return sections
    }

    private static func openDocumentSections(url: URL) throws -> [OfficeSection] {
        let data = try unzip(archive: url, entry: "content.xml")
        guard let raw = String(data: data, encoding: .utf8) else {
            throw OfficeExtractionError.conversionFailed("The document text is not UTF-8.")
        }
        var snippets: [String] = []
        let pattern = "(?is)<text:p[^>]*>(.*?)</text:p>"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
            regex.enumerateMatches(in: raw, range: range) { match, _, _ in
                guard let match, let contentRange = Range(match.range(at: 1), in: raw) else { return }
                var piece = String(raw[contentRange])
                piece = piece.replacingOccurrences(of: "(?s)<[^>]+>", with: " ", options: .regularExpression)
                piece = decodeEntities(piece)
                let cleaned = piece.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { snippets.append(cleaned) }
            }
        }
        let text = TextChunker.normalizedWhitespace(snippets.joined(separator: "\n"))
        guard !text.isEmpty else { throw OfficeExtractionError.emptyDocument }
        return [OfficeSection(text: text, page: nil)]
    }

    // MARK: Zip helpers

    private static func unzipList(archive: URL) throws -> [String] {
        let data = try runUnzip(arguments: ["-Z1", archive.path])
        guard let output = String(data: data, encoding: .utf8) else { throw OfficeExtractionError.unzipFailed }
        return output.split(whereSeparator: \.isNewline).map(String.init)
    }

    private static func unzip(archive: URL, entry: String) throws -> Data {
        try runUnzip(arguments: ["-p", archive.path, entry])
    }

    private static func runUnzip(arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw OfficeExtractionError.unzipFailed
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else {
            throw OfficeExtractionError.unzipFailed
        }
        return data
    }

    private static func slideNumber(from path: String) -> Int {
        Int(path.split(separator: "/").last?
            .replacingOccurrences(of: "slide", with: "")
            .replacingOccurrences(of: ".xml", with: "") ?? "") ?? 0
    }

    private static func sheetNumber(from path: String) -> Int {
        Int(path.split(separator: "/").last?
            .replacingOccurrences(of: "sheet", with: "")
            .replacingOccurrences(of: ".xml", with: "") ?? "") ?? 0
    }

    private static func decodeEntities(_ text: String) -> String {
        var output = text
        let entities = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&apos;": "'", "&#39;": "'", "&nbsp;": " "
        ]
        for (entity, replacement) in entities {
            output = output.replacingOccurrences(of: entity, with: replacement)
        }
        return output
    }
}

// MARK: - XML text collector

private final class XMLTextCollector: NSObject, XMLParserDelegate {
    private let captureElements: Set<String>
    private let breakElements: Set<String>
    private var capturing = false
    private var current = ""
    private var pieces: [String] = []

    private init(captureElements: Set<String>, breakElements: Set<String>) {
        self.captureElements = captureElements
        self.breakElements = breakElements
    }

    static func collect(data: Data, captureElements: Set<String>, breakElements: Set<String>) -> String {
        let collector = XMLTextCollector(
            captureElements: captureElements,
            breakElements: breakElements
        )
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.parse()
        let text = collector.pieces.joined(separator: " ")
        return text
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if captureElements.contains(elementName) {
            capturing = true
            current = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturing { current += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if captureElements.contains(elementName) {
            capturing = false
            let value = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { pieces.append(value) }
            current = ""
        }
        if breakElements.contains(elementName) {
            pieces.append("\n")
        }
    }
}
