import Foundation

struct IndexingSummary: Sendable {
    var processed: Int = 0
    var skipped: Int = 0
    var failed: Int = 0
    var removed: Int = 0
    var chunksCreated: Int = 0
    var warnings: [String] = []
    var cancelled: Bool = false
    var startedAt: Date?
    var finishedAt: Date?

    var duration: TimeInterval {
        guard let startedAt, let finishedAt else { return 0 }
        return finishedAt.timeIntervalSince(startedAt)
    }
}

actor IndexingEngine {
    private let store: IndexStore
    private let thumbnailsDirectory: URL
    private var progress = IndexingProgress()
    private var isRunning = false

    init(store: IndexStore, thumbnailsDirectory: URL) {
        self.store = store
        self.thumbnailsDirectory = thumbnailsDirectory
    }

    func snapshot() -> IndexingProgress {
        progress
    }

    /// Scans, extracts, embeds, and commits files. Individual file failures are
    /// recorded in the index and do not stop the rest of the run.
    func run(
        folders: [IndexedFolder],
        options: IndexingOptions,
        configuration: InferenceConfiguration,
        force: Bool
    ) async -> IndexingSummary {
        var summary = IndexingSummary(startedAt: Date())
        guard !isRunning else {
            summary.warnings.append("Indexing was already running.")
            return summary
        }
        isRunning = true
        defer { isRunning = false }

        progress = IndexingProgress(
            phase: .scanning,
            startedAt: Date(),
            error: nil
        )

        let client = try? LocalInferenceClient(configuration: configuration)
        let embeddingName = LocalInferenceClient.canonicalModelName(configuration.embeddingModel)
        var embeddingsAvailable = false

        if let client, !embeddingName.isEmpty {
            do {
                embeddingsAvailable = try await client.hasModel(configuration.embeddingModel)
                if !embeddingsAvailable {
                    summary.warnings.append("The embedding model “\(configuration.embeddingModel)” isn't installed. Files will be keyword-indexed, and embeddings will fill in after the model is available.")
                }
            } catch {
                summary.warnings.append("Semantic indexing is unavailable: \(error.localizedDescription)")
            }
        }

        let rules = ExclusionRules(
            userPatterns: options.excludedPatterns,
            skipSensitive: options.skipSensitive
        )
        let enabledFolders = folders.filter(\.isEnabled)
        guard !enabledFolders.isEmpty else {
            progress.phase = .idle
            progress.finishedAt = Date()
            summary.finishedAt = Date()
            summary.warnings.append("Add a folder to begin indexing.")
            return summary
        }

        var candidatesByPath: [String: FileCandidate] = [:]
        var folderSeenPaths: [Int64: Set<String>] = [:]
        var cleanupFolders: [IndexedFolder] = []

        do {
            for folder in enabledFolders {
                try Task.checkCancellation()
                progress.currentFile = folder.name
                guard FileManager.default.fileExists(atPath: folder.path) else {
                    summary.warnings.append("“\(folder.name)” is unavailable. Its existing index was kept.")
                    continue
                }

                let report: FileScanReport
                do {
                    report = try FileScanner.scan(
                        folder: folder,
                        rules: rules,
                        maxFileSizeBytes: options.maxFileSizeBytes,
                        includeCode: options.indexCode
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    summary.warnings.append("Couldn't scan “\(folder.name)”: \(error.localizedDescription)")
                    continue
                }

                folderSeenPaths[folder.id] = report.seenPaths
                if report.inaccessible == 0 {
                    cleanupFolders.append(folder)
                }
                for candidate in report.candidates {
                    if candidatesByPath[candidate.path.path] == nil {
                        candidatesByPath[candidate.path.path] = candidate
                    }
                }
            }

            // Remove files that have disappeared or become excluded. Skip
            // cleanup when a scan was incomplete so a permission problem can
            // never erase a valid index.
            for folder in cleanupFolders {
                guard let seen = folderSeenPaths[folder.id] else { continue }
                let existing = try await store.fileIDsAndPaths(folderID: folder.id)
                let stale = existing.filter { !seen.contains($0.path) }
                if !stale.isEmpty {
                    try await store.deleteFiles(ids: stale.map(\.id))
                    summary.removed += stale.count
                }
            }

            let candidates = candidatesByPath.values.sorted { $0.path.path < $1.path.path }
            progress.filesDiscovered = candidates.count
            progress.filesSkipped = 0
            let snapshots = try await store.existingSnapshots()
            let extractor = ContentExtractor(
                options: options,
                inference: client,
                chatModel: configuration.chatModel,
                thumbnailsDirectory: thumbnailsDirectory
            )

            progress.phase = .indexing
            progress.currentFile = ""
            let runStart = Date()

            for candidate in candidates {
                try Task.checkCancellation()
                progress.currentFile = candidate.relativePath.isEmpty ? candidate.name : candidate.relativePath
                progress.phase = .indexing

                if !force,
                   let existing = snapshots[candidate.path.path],
                   isUpToDate(
                       existing,
                       candidate: candidate,
                       embeddingModel: embeddingsAvailable ? embeddingName : nil
                   ) {
                    progress.filesProcessed += 1
                    progress.filesSkipped += 1
                    summary.skipped += 1
                    updateEstimate(startedAt: runStart)
                    continue
                }

                do {
                    let extraction = try await extractor.extract(candidate: candidate)
                    try Task.checkCancellation()
                    summary.warnings.append(contentsOf: extraction.warnings)

                    var vectors: [[Float]] = []
                    if embeddingsAvailable, !extraction.chunks.isEmpty, let client {
                        progress.phase = .embedding
                        let batchSize = 16
                        var index = 0
                        while index < extraction.chunks.count {
                            try Task.checkCancellation()
                            let upper = min(index + batchSize, extraction.chunks.count)
                            let drafts = extraction.chunks[index..<upper]
                            let inputs = drafts.map { embeddingText(for: candidate, chunk: $0) }
                            do {
                                let batchVectors = try await client.embed(
                                    texts: inputs,
                                    model: configuration.embeddingModel
                                )
                                guard batchVectors.count == inputs.count else {
                                    throw InferenceError.invalidResponse(
                                        "Expected \(inputs.count) embeddings, received \(batchVectors.count)."
                                    )
                                }
                                vectors.append(contentsOf: batchVectors.map(VectorMath.normalized))
                            } catch {
                                embeddingsAvailable = false
                                summary.warnings.append("Embedding paused at “\(candidate.name)”: \(error.localizedDescription)")
                                break
                            }
                            index = upper
                        }
                        progress.phase = .indexing
                    }

                    let chunkInputs = extraction.chunks.enumerated().map { offset, draft in
                        ChunkWriteInput(
                            index: offset,
                            text: draft.text,
                            locator: ContentLocator(
                                page: draft.page,
                                line: draft.line,
                                timeStart: draft.timeStart,
                                timeEnd: draft.timeEnd
                            ),
                            embedding: offset < vectors.count ? vectors[offset] : nil
                        )
                    }
                    let write = FileWriteInput(
                        folderID: candidate.folderID,
                        path: candidate.path.path,
                        name: candidate.name,
                        kind: candidate.kind,
                        fileSize: candidate.fileSize,
                        modifiedAt: candidate.modifiedAt,
                        pageCount: extraction.pageCount,
                        duration: extraction.duration,
                        thumbnailPath: extraction.thumbnailPath,
                        featurePrint: extraction.featurePrint,
                        embeddingModel: vectors.isEmpty ? nil : embeddingName
                    )
                    _ = try await store.saveFile(write, chunks: chunkInputs)
                    summary.processed += 1
                    summary.chunksCreated += max(1, chunkInputs.count)
                    progress.chunksCreated += max(1, chunkInputs.count)
                    progress.bytesProcessed += candidate.fileSize
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    summary.failed += 1
                    try? await store.recordFileError(
                        path: candidate.path.path,
                        name: candidate.name,
                        kind: candidate.kind,
                        fileSize: candidate.fileSize,
                        modifiedAt: candidate.modifiedAt,
                        folderID: candidate.folderID,
                        message: error.localizedDescription
                    )
                    summary.warnings.append("Skipped “\(candidate.name)”: \(error.localizedDescription)")
                }

                progress.filesProcessed += 1
                updateEstimate(startedAt: runStart)
            }

            progress.currentFile = ""
            progress.phase = .idle
            progress.finishedAt = Date()
            progress.estimatedSecondsRemaining = 0
            summary.finishedAt = Date()
            return summary
        } catch is CancellationError {
            progress.phase = .cancelled
            progress.finishedAt = Date()
            progress.currentFile = ""
            summary.cancelled = true
            summary.finishedAt = Date()
            return summary
        } catch {
            progress.phase = .failed
            progress.error = error.localizedDescription
            progress.finishedAt = Date()
            summary.finishedAt = Date()
            summary.warnings.append(error.localizedDescription)
            return summary
        }
    }

    private func isUpToDate(
        _ existing: ExistingFileSnapshot,
        candidate: FileCandidate,
        embeddingModel: String?
    ) -> Bool {
        guard existing.status == "indexed" else { return false }
        guard existing.fileSize == candidate.fileSize else { return false }
        guard abs(existing.modifiedAt.timeIntervalSince1970 - candidate.modifiedAt.timeIntervalSince1970) < 0.5 else {
            return false
        }
        guard existing.chunkCount > 0 else { return false }
        guard let embeddingModel else {
            return true // Keyword index is still valid without an embedding model.
        }
        return existing.embeddedChunks >= existing.chunkCount
            && existing.embeddingModel == embeddingModel
    }

    private func embeddingText(for candidate: FileCandidate, chunk: ChunkDraft) -> String {
        var header = "Document: \(candidate.name)."
        if let page = chunk.page {
            header += " Page \(page)."
        }
        if let time = chunk.timeStart {
            header += " At \(ContentLocator.timecode(time))."
        }
        return header + "\n" + chunk.text
    }

    private func updateEstimate(startedAt: Date) {
        guard progress.filesProcessed > 0 else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        let perFile = elapsed / Double(progress.filesProcessed)
        let remaining = max(0, progress.filesDiscovered - progress.filesProcessed)
        progress.estimatedSecondsRemaining = perFile * Double(remaining)
    }
}
