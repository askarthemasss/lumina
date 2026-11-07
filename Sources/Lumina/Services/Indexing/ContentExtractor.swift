import Foundation
import AppKit
import PDFKit
import Vision
import ImageIO
import UniformTypeIdentifiers
import AVFoundation
import CryptoKit

struct ExtractionResult: Sendable {
    var chunks: [ChunkDraft] = []
    var pageCount: Int?
    var duration: TimeInterval?
    var thumbnailPath: String?
    var featurePrint: Data?
    var warnings: [String] = []
}

enum ExtractionError: LocalizedError {
    case unreadable(String)
    case lockedPDF
    case tooLarge
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let detail): "Lumina couldn't read this file. \(detail)"
        case .lockedPDF: "Password-protected PDFs are intentionally skipped."
        case .tooLarge: "This file is too large for text extraction."
        case .unsupported(let detail): detail
        }
    }
}

/// Converts a file into searchable passages. This is the bridge between native
/// macOS readers (PDFKit, Vision, AVFoundation, AppKit) and the index.
struct ContentExtractor: Sendable {
    let options: IndexingOptions
    let inference: LocalInferenceClient?
    let chatModel: String
    let thumbnailsDirectory: URL

    private let textReadLimit = 24 * 1024 * 1024

    func extract(candidate: FileCandidate) async throws -> ExtractionResult {
        try Task.checkCancellation()
        switch candidate.kind {
        case .text, .code:
            return try extractPlainText(candidate)
        case .pdf:
            return try await extractPDF(candidate)
        case .image:
            return try await extractImage(candidate)
        case .audio:
            return try await extractAudio(candidate)
        case .video:
            return try await extractVideo(candidate)
        case .document:
            return try await extractDocument(candidate)
        case .spreadsheet:
            if ["csv", "tsv"].contains(candidate.url.pathExtension.lowercased()) {
                return try extractPlainText(candidate)
            }
            return try await extractOffice(candidate)
        case .presentation:
            return try await extractOffice(candidate)
        }
    }

    // MARK: Plain text

    private func extractPlainText(_ candidate: FileCandidate) throws -> ExtractionResult {
        let data: Data
        do {
            data = try Data(contentsOf: candidate.url, options: .mappedIfSafe)
        } catch {
            throw ExtractionError.unreadable(error.localizedDescription)
        }
        guard data.count <= textReadLimit else {
            throw ExtractionError.tooLarge
        }
        guard let text = decodeText(data) else {
            throw ExtractionError.unreadable("The text encoding isn't supported.")
        }
        let chunks = TextChunker.lineChunks(text)
        return ExtractionResult(chunks: chunks)
    }

    private func decodeText(_ data: Data) -> String? {
        let encodings: [String.Encoding] = [
            .utf8, .utf16, .utf16LittleEndian, .utf16BigEndian,
            .isoLatin1, .macOSRoman, .windowsCP1252
        ]
        for encoding in encodings {
            if let text = String(data: data, encoding: encoding), !text.isEmpty {
                return text
            }
        }
        return nil
    }

    // MARK: Documents

    private func extractDocument(_ candidate: FileCandidate) async throws -> ExtractionResult {
        let ext = candidate.url.pathExtension.lowercased()
        if ext == "pdf" {
            return try await extractPDF(candidate)
        }
        if ext == "html" || ext == "htm" {
            let text = try HTMLTextReader.read(url: candidate.url)
            return ExtractionResult(chunks: TextChunker.lineChunks(text))
        }
        return try await extractOffice(candidate)
    }

    private func extractOffice(_ candidate: FileCandidate) async throws -> ExtractionResult {
        try Task.checkCancellation()
        do {
            let sections = try OfficeTextExtractor.sections(url: candidate.url)
            var chunks: [ChunkDraft] = []
            for section in sections {
                let drafts = section.page == nil
                    ? TextChunker.lineChunks(section.text)
                    : TextChunker.characterChunks(section.text).map {
                        ChunkDraft(text: $0, page: section.page, line: nil, timeStart: nil, timeEnd: nil)
                    }
                chunks.append(contentsOf: drafts)
            }
            let pageCount = sections.compactMap(\.page).max()
            return ExtractionResult(chunks: chunks, pageCount: pageCount)
        } catch {
            throw ExtractionError.unreadable(error.localizedDescription)
        }
    }

    // MARK: PDF

    private func extractPDF(_ candidate: FileCandidate) async throws -> ExtractionResult {
        guard let document = PDFDocument(url: candidate.url) else {
            throw ExtractionError.unreadable("The PDF couldn't be opened.")
        }
        if document.isLocked {
            throw ExtractionError.lockedPDF
        }
        let pageCount = document.pageCount
        guard pageCount > 0 else {
            throw ExtractionError.unreadable("The PDF has no pages.")
        }

        var result = ExtractionResult(pageCount: pageCount)
        if let firstPage = document.page(at: 0), let image = renderPDFPage(firstPage, maxDimension: 760) {
            result.thumbnailPath = saveThumbnail(image, key: candidate.url.path + "-pdf-thumb")
        }

        for index in 0..<pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { continue }
            var text = page.string ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               options.ocrEnabled,
               let image = renderPDFPage(page, maxDimension: 1_800) {
                text = recognizeText(in: image)
                if !text.isEmpty {
                    text = "Scanned page text:\n" + text
                }
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            result.chunks.append(contentsOf: TextChunker.pageChunks(text: text, page: index + 1))
        }
        return result
    }

    private func renderPDFPage(_ page: PDFPage, maxDimension: CGFloat) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(maxDimension / max(bounds.width, bounds.height), 2.0)
        let size = NSSize(width: bounds.width * scale, height: bounds.height * scale)
        let image = page.thumbnail(of: size, for: .mediaBox)
        var rect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    // MARK: Images

    private func extractImage(_ candidate: FileCandidate) async throws -> ExtractionResult {
        guard let source = CGImageSourceCreateWithURL(candidate.url as CFURL, nil) else {
            throw ExtractionError.unreadable("The image format isn't supported.")
        }
        let imageOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2_000,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, imageOptions as CFDictionary) else {
            throw ExtractionError.unreadable("The image couldn't be decoded.")
        }

        var result = ExtractionResult()
        result.thumbnailPath = saveThumbnail(image, key: candidate.url.path + "-image")

        let ocr = options.ocrEnabled ? recognizeText(in: image) : ""
        let labels = classifyImage(image).prefix(7).map { $0 }
        var paragraphs: [String] = []
        if options.visionCaptionsEnabled, let inference {
            do {
                let caption = try await inference.describeImage(
                    fileURL: candidate.url,
                    model: chatModel,
                    prompt: "Describe the important visual content of this image for semantic search. Mention settings, objects, visible interfaces, and any text. Be factual and brief."
                )
                if !caption.isEmpty {
                    paragraphs.append("Visual description: \(caption)")
                }
            } catch {
                result.warnings.append("Image description was skipped: \(error.localizedDescription)")
            }
        }
        if !ocr.isEmpty {
            paragraphs.append("Visible text:\n\(ocr)")
        }
        if !labels.isEmpty {
            paragraphs.append("Image content: \(labels.joined(separator: ", "))")
        }
        if paragraphs.isEmpty {
            paragraphs.append("Image named \(candidate.name).")
        }
        let combined = paragraphs.joined(separator: "\n\n")
        result.chunks = TextChunker.characterChunks(combined).map {
            ChunkDraft(text: $0, page: nil, line: nil, timeStart: nil, timeEnd: nil)
        }
        return result
    }

    private func recognizeText(in image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }
        let observations = (request.results ?? []).sorted { lhs, rhs in
            let verticalDifference = abs(lhs.boundingBox.maxY - rhs.boundingBox.maxY)
            if verticalDifference > 0.025 {
                return lhs.boundingBox.maxY > rhs.boundingBox.maxY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    private func classifyImage(_ image: CGImage) -> [String] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        return (request.results ?? [])
            .filter { $0.confidence > 0.25 }
            .prefix(10)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
    }

    // MARK: Audio

    private func extractAudio(_ candidate: FileCandidate) async throws -> ExtractionResult {
        let asset = AVURLAsset(url: candidate.url)
        let duration = await loadDuration(asset)
        var result = ExtractionResult(duration: duration)
        var metadata = await audioMetadata(asset, fallbackName: candidate.name)

        if options.transcriptionEnabled {
            do {
                let transcript = try await TranscriptionService().transcribe(fileURL: candidate.url)
                if !transcript.segments.isEmpty {
                    metadata += "\n\nTranscript."
                    result.chunks.append(ChunkDraft(
                        text: metadata,
                        page: nil,
                        line: nil,
                        timeStart: 0,
                        timeEnd: duration
                    ))
                    result.chunks.append(contentsOf: transcriptChunks(transcript.segments))
                    return result
                }
            } catch {
                result.warnings.append("Audio transcription was skipped: \(error.localizedDescription)")
            }
        }

        result.chunks = [
            ChunkDraft(
                text: metadata,
                page: nil,
                line: nil,
                timeStart: nil,
                timeEnd: duration
            )
        ]
        return result
    }

    // MARK: Video

    private func extractVideo(_ candidate: FileCandidate) async throws -> ExtractionResult {
        let asset = AVURLAsset(url: candidate.url)
        let duration = await loadDuration(asset)
        var result = ExtractionResult(duration: duration)
        var description = await audioMetadata(asset, fallbackName: candidate.name)
        description += "\nVideo file. Duration \(ContentLocator.timecode(duration))."

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1_800, height: 1_800)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        var frames: [(time: TimeInterval, image: CGImage)] = []
        let times: [TimeInterval] = duration > 1
            ? [0.2, duration * 0.3, duration * 0.6, duration * 0.85]
            : [0]
        for time in times {
            try Task.checkCancellation()
            if let image = copyFrame(from: generator, at: time) {
                frames.append((time, image))
            }
        }

        if let first = frames.first {
            result.thumbnailPath = saveThumbnail(first.image, key: candidate.url.path + "-video")
            var seenText = Set<String>()
            for frame in frames {
                let ocr = options.ocrEnabled ? recognizeText(in: frame.image) : ""
                let labels = classifyImage(frame.image).prefix(4).joined(separator: ", ")
                var pieces: [String] = ["Frame at \(ContentLocator.timecode(frame.time))."]
                if !ocr.isEmpty, !seenText.contains(ocr) {
                    seenText.insert(ocr)
                    pieces.append("Visible text: \(ocr)")
                }
                if !labels.isEmpty {
                    pieces.append("Visual content: \(labels)")
                }
                let text = pieces.joined(separator: "\n")
                if pieces.count > 1 {
                    result.chunks.append(ChunkDraft(
                        text: text,
                        page: nil,
                        line: nil,
                        timeStart: frame.time,
                        timeEnd: min(duration, frame.time + 1)
                    ))
                }
            }
        }

        if options.transcriptionEnabled {
            let transcriber = TranscriptionService()
            var tempAudio: URL?
            do {
                let audioURL = try await transcriber.extractAudio(from: candidate.url)
                tempAudio = audioURL
                let transcript = try await transcriber.transcribe(fileURL: audioURL)
                if !transcript.segments.isEmpty {
                    description += "\n\nTranscript."
                    result.chunks.append(contentsOf: transcriptChunks(transcript.segments))
                }
            } catch {
                result.warnings.append("Video transcription was skipped: \(error.localizedDescription)")
            }
            if let tempAudio {
                try? FileManager.default.removeItem(at: tempAudio)
            }
        }

        result.chunks.insert(
            ChunkDraft(text: description, page: nil, line: nil, timeStart: 0, timeEnd: duration),
            at: 0
        )
        return result
    }

    private func copyFrame(from generator: AVAssetImageGenerator, at seconds: TimeInterval) -> CGImage? {
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        var actual = CMTime.zero
        return try? generator.copyCGImage(at: time, actualTime: &actual)
    }

    private func transcriptChunks(_ segments: [TranscriptionSegment]) -> [ChunkDraft] {
        guard !segments.isEmpty else { return [] }
        var chunks: [ChunkDraft] = []
        var buffer: [TranscriptionSegment] = []
        var characterCount = 0

        func flush() {
            guard let first = buffer.first, let last = buffer.last else { return }
            let text = buffer.map(\.text).joined(separator: " ")
            chunks.append(ChunkDraft(
                text: text,
                page: nil,
                line: nil,
                timeStart: first.start,
                timeEnd: last.end
            ))
            buffer.removeAll(keepingCapacity: true)
            characterCount = 0
        }

        for segment in segments {
            buffer.append(segment)
            characterCount += segment.text.count + 1
            if characterCount >= TextChunker.targetCharacters {
                flush()
            }
        }
        flush()
        return chunks
    }

    // MARK: Media helpers

    private func loadDuration(_ asset: AVURLAsset) async -> TimeInterval {
        guard let time = try? await asset.load(.duration) else { return 0 }
        let seconds = CMTimeGetSeconds(time)
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }

    private func audioMetadata(_ asset: AVURLAsset, fallbackName: String) async -> String {
        var parts: [String] = ["Media: \(fallbackName)"]
        if let items = try? await asset.load(.commonMetadata) {
            for item in items {
                guard let key = item.commonKey?.rawValue else { continue }
                if let value = try? await item.load(.stringValue), !value.isEmpty {
                    switch key {
                    case "title": parts.append("Title: \(value)")
                    case "artist": parts.append("Artist: \(value)")
                    case "albumName": parts.append("Album: \(value)")
                    case "creator": parts.append("Creator: \(value)")
                    default: break
                    }
                }
            }
        }
        return parts.joined(separator: "\n")
    }

    // MARK: Thumbnails

    private func saveThumbnail(_ image: CGImage, key: String) -> String? {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let hash = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(32)
        let destinationURL = thumbnailsDirectory
            .appendingPathComponent(String(hash))
            .appendingPathExtension("jpg")

        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let maxDimension: CGFloat = 720
        let scale = min(1, maxDimension / max(width, height))
        let targetWidth = max(1, Int(width * scale))
        let targetHeight = max(1, Int(height * scale))

        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        guard let resized = context.makeImage() else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, resized, [
            kCGImageDestinationLossyCompressionQuality: 0.82
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        do {
            try (data as Data).write(to: destinationURL, options: .atomic)
            return destinationURL.path
        } catch {
            return nil
        }
    }
}
