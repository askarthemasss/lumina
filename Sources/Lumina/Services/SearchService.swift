import Foundation

/// Hybrid retrieval: FTS5 keyword matching and local embedding similarity are
/// merged with reciprocal rank fusion. RRF is robust across the two very
/// different score scales and keeps exact matches strong.
struct SearchService: Sendable {
    let store: IndexStore

    func search(
        query: String,
        filters: SearchFilters,
        configuration: InferenceConfiguration,
        limit: Int = 50
    ) async -> SearchOutcome {
        let start = Date()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            let files = (try? await store.recentFilesFiltered(filters: filters, limit: limit)) ?? []
            var hits: [SearchHit] = []
            for file in files {
                if let chunk = try? await store.firstChunk(forFileID: file.id) {
                    hits.append(SearchHit(
                        id: chunk.chunkID,
                        file: file,
                        snippet: chunk.text.replacingOccurrences(of: "\n", with: " ").prefix(240).description,
                        fullText: chunk.text,
                        locator: chunk.locator,
                        semanticScore: nil,
                        keywordScore: nil,
                        score: 0,
                        matchCount: 1,
                        isExactNameMatch: false
                    ))
                } else {
                    hits.append(SearchHit(
                        id: -file.id,
                        file: file,
                        snippet: "Recently indexed \(file.kind.displayName.lowercased()).",
                        fullText: file.name,
                        locator: ContentLocator(),
                        semanticScore: nil,
                        keywordScore: nil,
                        score: 0,
                        matchCount: 1,
                        isExactNameMatch: false
                    ))
                }
            }
            return SearchOutcome(hits: hits, semanticUsed: false, warning: nil,
                                 duration: Date().timeIntervalSince(start))
        }

        async let keywordResult = loadKeyword(query: trimmed, filters: filters)
        async let semanticResult = loadSemantic(query: trimmed, filters: filters, configuration: configuration)
        async let filenameResult = loadFilenameMatches(query: trimmed, filters: filters)

        let (keyword, keywordError) = await keywordResult
        let (semantic, semanticError) = await semanticResult
        let filenameMatches = await filenameResult

        let hasConfiguredEmbedding = !configuration.embeddingModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var warning: String?
        if let semanticError, hasConfiguredEmbedding {
            warning = "Semantic search is unavailable right now, so these are keyword matches. \(semanticError)"
        } else if semanticError == nil, semantic.isEmpty, hasConfiguredEmbedding,
                  keyword.isEmpty == false {
            warning = "No semantic passages matched. Showing keyword results."
        } else if let keywordError {
            warning = "Keyword search had a problem. \(keywordError)"
        }

        struct Merged {
            var hit: SearchHit
            var rankScore: Double
            var exactName: Bool
        }

        var byChunk: [Int64: Merged] = [:]
        let semanticWeight = 1.0
        let keywordWeight = filters.exactPhrase ? 1.45 : 1.25

        for (rank, match) in keyword.enumerated() {
            let rankScore = keywordWeight / Double(60 + rank + 1)
            byChunk[match.chunkID] = Merged(
                hit: SearchHit(
                    id: match.chunkID,
                    file: match.file,
                    snippet: match.snippet,
                    fullText: match.text,
                    locator: match.locator,
                    semanticScore: nil,
                    keywordScore: rankScore,
                    score: rankScore,
                    matchCount: 1,
                    isExactNameMatch: false
                ),
                rankScore: rankScore,
                exactName: false
            )
        }

        for (rank, match) in semantic.enumerated() {
            let rankScore = semanticWeight / Double(60 + rank + 1)
            if var existing = byChunk[match.chunkID] {
                existing.rankScore += rankScore
                existing.hit = SearchHit(
                    id: existing.hit.id,
                    file: existing.hit.file,
                    snippet: existing.hit.snippet,
                    fullText: existing.hit.fullText,
                    locator: existing.hit.locator,
                    semanticScore: match.similarity,
                    keywordScore: existing.hit.keywordScore,
                    score: existing.rankScore,
                    matchCount: existing.hit.matchCount,
                    isExactNameMatch: existing.hit.isExactNameMatch
                )
                byChunk[match.chunkID] = existing
            } else {
                byChunk[match.chunkID] = Merged(
                    hit: SearchHit(
                        id: match.chunkID,
                        file: match.file,
                        snippet: snippet(from: match.text, query: trimmed),
                        fullText: match.text,
                        locator: match.locator,
                        semanticScore: match.similarity,
                        keywordScore: nil,
                        score: rankScore,
                        matchCount: 1,
                        isExactNameMatch: false
                    ),
                    rankScore: rankScore,
                    exactName: false
                )
            }
        }

        let loweredQuery = trimmed.lowercased()
        var nameMatchedFileIDs = Set<Int64>()
        for file in filenameMatches {
            nameMatchedFileIDs.insert(file.id)
            if let chunk = try? await store.firstChunk(forFileID: file.id) {
                if var existing = byChunk[chunk.chunkID] {
                    existing.exactName = true
                    existing.rankScore += 0.045
                    existing.hit = SearchHit(
                        id: existing.hit.id,
                        file: existing.hit.file,
                        snippet: existing.hit.snippet,
                        fullText: existing.hit.fullText,
                        locator: existing.hit.locator,
                        semanticScore: existing.hit.semanticScore,
                        keywordScore: existing.hit.keywordScore,
                        score: existing.rankScore,
                        matchCount: existing.hit.matchCount,
                        isExactNameMatch: true
                    )
                    byChunk[chunk.chunkID] = existing
                } else {
                    let rankScore = 0.05
                    byChunk[chunk.chunkID] = Merged(
                        hit: SearchHit(
                            id: chunk.chunkID,
                            file: file,
                            snippet: "File name matches “\(trimmed)”.",
                            fullText: chunk.text,
                            locator: chunk.locator,
                            semanticScore: nil,
                            keywordScore: 0.05,
                            score: rankScore,
                            matchCount: 1,
                            isExactNameMatch: true
                        ),
                        rankScore: rankScore,
                        exactName: true
                    )
                }
            } else {
                let rankScore = 0.045
                byChunk[-file.id] = Merged(
                    hit: SearchHit(
                        id: -file.id,
                        file: file,
                        snippet: "File name matches “\(trimmed)”.",
                        fullText: file.name,
                        locator: ContentLocator(),
                        semanticScore: nil,
                        keywordScore: 0.045,
                        score: rankScore,
                        matchCount: 1,
                        isExactNameMatch: true
                    ),
                    rankScore: rankScore,
                    exactName: true
                )
            }
        }

        // Reward exact query text when it appears verbatim (invoice numbers,
        // error codes, names). This is deliberately a small tiebreaker.
        for (chunkID, var merged) in byChunk {
            let haystack = (merged.hit.file.name + "\n" + merged.hit.fullText).lowercased()
            if haystack.contains(loweredQuery) {
                merged.rankScore += 0.035
                merged.hit = SearchHit(
                    id: merged.hit.id,
                    file: merged.hit.file,
                    snippet: merged.hit.snippet,
                    fullText: merged.hit.fullText,
                    locator: merged.hit.locator,
                    semanticScore: merged.hit.semanticScore,
                    keywordScore: merged.hit.keywordScore,
                    score: merged.rankScore,
                    matchCount: merged.hit.matchCount,
                    isExactNameMatch: merged.hit.isExactNameMatch || nameMatchedFileIDs.contains(merged.hit.file.id)
                )
                byChunk[chunkID] = merged
            }
        }

        let all = byChunk.values.sorted { $0.rankScore > $1.rankScore }
        var bestByFile: [Int64: (hit: SearchHit, score: Double)] = [:]
        var matchCounts: [Int64: Int] = [:]
        for item in all {
            let fileID = item.hit.file.id
            matchCounts[fileID, default: 0] += 1
            if let current = bestByFile[fileID] {
                if item.rankScore > current.score {
                    bestByFile[fileID] = (item.hit, item.rankScore)
                }
            } else {
                bestByFile[fileID] = (item.hit, item.rankScore)
            }
        }

        let hits = bestByFile.values
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { entry -> SearchHit in
                let count = matchCounts[entry.hit.file.id] ?? 1
                return SearchHit(
                    id: entry.hit.id,
                    file: entry.hit.file,
                    snippet: entry.hit.snippet,
                    fullText: entry.hit.fullText,
                    locator: entry.hit.locator,
                    semanticScore: entry.hit.semanticScore,
                    keywordScore: entry.hit.keywordScore,
                    score: entry.score,
                    matchCount: count,
                    isExactNameMatch: entry.hit.isExactNameMatch
                )
            }

        return SearchOutcome(
            hits: Array(hits),
            semanticUsed: !semantic.isEmpty,
            warning: warning,
            duration: Date().timeIntervalSince(start)
        )
    }

    // MARK: Private loaders

    private func loadKeyword(query: String, filters: SearchFilters) async -> ([KeywordMatch], String?) {
        do {
            return (try await store.keywordSearch(query: query, filters: filters), nil)
        } catch {
            return ([], error.localizedDescription)
        }
    }

    private func loadSemantic(
        query: String,
        filters: SearchFilters,
        configuration: InferenceConfiguration
    ) async -> ([SemanticMatch], String?) {
        guard !configuration.embeddingModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ([], "No embedding model is selected.")
        }
        do {
            let client = try LocalInferenceClient(configuration: configuration)
            let vectors = try await client.embed(texts: [query], model: configuration.embeddingModel)
            guard let vector = vectors.first else {
                return ([], "The embedding model returned no vector.")
            }
            let model = LocalInferenceClient.canonicalModelName(configuration.embeddingModel)
            let matches = try await store.semanticSearch(
                queryVector: vector,
                model: model,
                filters: filters
            )
            return (matches, nil)
        } catch {
            return ([], error.localizedDescription)
        }
    }

    private func loadFilenameMatches(query: String, filters: SearchFilters) async -> [IndexedFile] {
        (try? await store.filenameMatches(query: query, filters: filters)) ?? []
    }

    private func snippet(from text: String, query: String) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let terms = IndexStore.searchTerms(in: query)
        let lower = collapsed.lowercased()
        var matchRange: Range<String.Index>?
        for term in terms {
            if let range = lower.range(of: term) {
                matchRange = range
                break
            }
        }
        let anchor = matchRange?.lowerBound ?? collapsed.startIndex
        let start = collapsed.index(anchor, offsetBy: -100, limitedBy: collapsed.startIndex) ?? collapsed.startIndex
        let end = collapsed.index(anchor, offsetBy: 260, limitedBy: collapsed.endIndex) ?? collapsed.endIndex
        var snippet = String(collapsed[start..<end])
        if start > collapsed.startIndex { snippet = "…" + snippet }
        if end < collapsed.endIndex { snippet += "…" }

        if let term = terms.first(where: { snippet.lowercased().contains($0) }),
           let range = snippet.range(of: term, options: .caseInsensitive) {
            let prefix = String(snippet[..<range.lowerBound])
            let match = String(snippet[range])
            let suffix = String(snippet[range.upperBound...])
            snippet = prefix + "[[" + match + "]]" + suffix
        }
        return snippet
    }
}
