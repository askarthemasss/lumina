import Foundation
import Speech
import AVFoundation

struct TranscriptionSegment: Sendable {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}

struct TranscriptionResult: Sendable {
    let segments: [TranscriptionSegment]
    var duration: TimeInterval { segments.map(\.end).max() ?? 0 }
    var text: String { segments.map(\.text).joined(separator: " ") }
}

enum TranscriptionError: LocalizedError {
    case unauthorized
    case unavailable
    case onDeviceUnavailable
    case failed(String)
    case audioExtractionFailed

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Speech recognition permission is off. Enable it in System Settings → Privacy & Security → Speech Recognition."
        case .unavailable:
            "Speech recognition isn't available right now."
        case .onDeviceUnavailable:
            "On-device speech recognition isn't available for this language. Lumina won't send audio to a server, so transcription was skipped."
        case .failed(let message):
            "Transcription failed. \(message)"
        case .audioExtractionFailed:
            "Lumina couldn't extract an audio track from this video."
        }
    }
}

/// Local-only transcription using Apple's on-device Speech framework.
/// `requiresOnDeviceRecognition` is always true: if the device cannot do it
/// locally, Lumina skips transcription rather than uploading audio.
struct TranscriptionService: Sendable {
    static func authorizationStatus() -> SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func transcribe(fileURL: URL) async throws -> TranscriptionResult {
        var status = Self.authorizationStatus()
        if status == .notDetermined {
            _ = await Self.requestAuthorization()
            status = Self.authorizationStatus()
        }
        guard status == .authorized else {
            throw TranscriptionError.unauthorized
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current), recognizer.isAvailable else {
            throw TranscriptionError.unavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw TranscriptionError.onDeviceUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.taskHint = .dictation

        return try await withCheckedThrowingContinuation { continuation in
            let gate = ContinuationGate()
            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    guard gate.claim() else { return }
                    let segments = result.bestTranscription.segments.map { segment in
                        TranscriptionSegment(
                            text: segment.substring,
                            start: max(0, segment.timestamp),
                            end: max(segment.timestamp + segment.duration, segment.timestamp)
                        )
                    }
                    continuation.resume(returning: TranscriptionResult(segments: segments))
                } else if let error {
                    guard gate.claim() else { return }
                    continuation.resume(throwing: TranscriptionError.failed(error.localizedDescription))
                }
            }
        }
    }

    /// Extracts a temporary audio track from a video for local transcription.
    /// The temporary file is removed by the caller.
    func extractAudio(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumina-audio-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw TranscriptionError.audioExtractionFailed
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .m4a

        await withCheckedContinuation { continuation in
            exporter.exportAsynchronously {
                continuation.resume()
            }
        }

        guard exporter.status == .completed else {
            throw TranscriptionError.audioExtractionFailed
        }
        return outputURL
    }
}

private final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
