import Foundation

struct KeywordMatch: Sendable {
    let chunkID: Int64
    let file: IndexedFile
    let text: String
    let snippet: String
    let locator: ContentLocator
}

struct SemanticMatch: Sendable {
    let chunkID: Int64
    let file: IndexedFile
    let text: String
    let locator: ContentLocator
    let similarity: Double
}

struct StoredChunk: Sendable {
    let chunkID: Int64
    let file: IndexedFile
    let text: String
    let locator: ContentLocator
}

extension IndexStore {
    static func searchTerms(in query: String) -> [String] {
        query
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { terms, term in
                if !terms.contains(term) { terms.append(term) }
            }
    }

    static func ftsQuery(from query: String, exactPhrase: Bool) -> String? {
        let terms = searchTerms(in: query)
        guard !terms.isEmpty else { return nil }
        if exactPhrase {
            let phrase = terms.joined(separator: " ").replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(phrase)\""
        }
        return terms
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            .joined(separator: " OR ")
    }

    private static func filterClause(_ filters: SearchFilters) -> String {
        var clauses: [String] = []
        if !filters.kinds.isEmpty {
            let kinds = filters.kinds.map { "'\($0.rawValue)'" }.joined(separator: ",")
            clauses.append("f.kind IN (\(kinds))")
        }
        if !filters.folderIDs.isEmpty {
            let ids = filters.folderIDs.map { String($0) }.joined(separator: ",")
            clauses.append("f.folder_id IN (\(ids))")
        }
        if let from = filters.dateFrom {
            clauses.append("f.modified_at >= \(from.timeIntervalSince1970)")
        }
        if let to = filters.dateTo {
            clauses.append("f.modified_at <= \(to.timeIntervalSince1970)")
        }
        return clauses.isEmpty ? "" : " AND " + clauses.joined(separator: " AND ")
    }

    func keywordSearch(
        query: String,
        filters: SearchFilters,
        limit: Int = 100
    ) throws -> [KeywordMatch] {
        guard let fts = Self.ftsQuery(from: query, exactPhrase: filters.exactPhrase) else {
            return []
        }
        let sql = """
            SELECT \(StoreMapping.fileColumns),
                   c.id, c.text, c.page, c.line_start, c.time_start, c.time_end,
                   snippet(chunks_fts, 0, '[[', ']]', '…', 34) AS snip,
                   bm25(chunks_fts) AS rank
            FROM chunks_fts
            JOIN chunks c ON c.id = chunks_fts.rowid
            JOIN files f ON f.id = c.file_id
            WHERE chunks_fts MATCH ?
              AND f.status = 'indexed'
              \(Self.filterClause(filters))
            ORDER BY rank ASC
            LIMIT ?
            """
        let statement = try db.prepare(sql)
        statement.bind(1, fts)
        statement.bind(2, limit)

        var results: [KeywordMatch] = []
        while try statement.step() {
            let file = StoreMapping.file(from: statement, offset: 0)
            let chunkID = statement.int64(15)
            let text = statement.string(16) ?? ""
            let page = statement.isNull(17) ? nil : statement.int(17)
            let line = statement.isNull(18) ? nil : statement.int(18)
            let start = statement.isNull(19) ? nil : statement.double(19)
            let end = statement.isNull(20) ? nil : statement.double(20)
            let snippet = statement.string(21) ?? String(text.prefix(240))
            results.append(KeywordMatch(
                chunkID: chunkID,
                file: file,
                text: text,
                snippet: snippet,
                locator: ContentLocator(page: page, line: line, timeStart: start, timeEnd: end)
            ))
        }
        return results
    }

    func semanticSearch(
        queryVector: [Float],
        model: String,
        filters: SearchFilters,
        limit: Int = 80
    ) throws -> [SemanticMatch] {
        guard !queryVector.isEmpty else { return [] }
        let sql = """
            SELECT \(StoreMapping.fileColumns),
                   c.id, c.text, c.page, c.line_start, c.time_start, c.time_end, c.embedding
            FROM chunks c
            JOIN files f ON f.id = c.file_id
            WHERE c.embedding IS NOT NULL
              AND c.embedding_model = ?
              AND f.status = 'indexed'
              \(Self.filterClause(filters))
            """
        let statement = try db.prepare(sql)
        statement.bind(1, model)
        let query = VectorMath.normalized(queryVector)
        var heap = BoundedTopK<SemanticRow>(limit: limit)
        var fileCache: [Int64: IndexedFile] = [:]

        while try statement.step() {
            let file = StoreMapping.file(from: statement, offset: 0)
            let chunkID = statement.int64(15)
            let text = statement.string(16) ?? ""
            guard let embeddingData = statement.data(21) else { continue }
            let vector = VectorMath.decode(embeddingData)
            guard vector.count == query.count else { continue }
            let similarity = Double(VectorMath.dot(query, vector))
            // Entirely unrelated vectors can have small positive cosine values.
            guard similarity > 0.02 else { continue }

            let page = statement.isNull(17) ? nil : statement.int(17)
            let line = statement.isNull(18) ? nil : statement.int(18)
            let start = statement.isNull(19) ? nil : statement.double(19)
            let end = statement.isNull(20) ? nil : statement.double(20)
            if fileCache[file.id] == nil { fileCache[file.id] = file }
            heap.offer(score: similarity, element: SemanticRow(
                chunkID: chunkID,
                file: file,
                text: text,
                locator: ContentLocator(page: page, line: line, timeStart: start, timeEnd: end),
                similarity: similarity
            ))
        }

        return heap.sortedDescending().map {
            SemanticMatch(
                chunkID: $0.chunkID,
                file: $0.file,
                text: $0.text,
                locator: $0.locator,
                similarity: $0.similarity
            )
        }
    }

    func filenameMatches(
        query: String,
        filters: SearchFilters,
        limit: Int = 24
    ) throws -> [IndexedFile] {
        let terms = Self.searchTerms(in: query)
        guard !terms.isEmpty else { return [] }
        let nameClauses = terms.prefix(3).map { _ in "(f.name LIKE ? OR f.path LIKE ?)" }
            .joined(separator: " OR ")
        let sql = """
            SELECT \(StoreMapping.fileColumns) FROM files f
            WHERE f.status = 'indexed'
              AND (\(nameClauses))
              \(Self.filterClause(filters))
            ORDER BY f.indexed_at DESC
            LIMIT ?
            """
        let statement = try db.prepare(sql)
        var bindIndex: Int32 = 1
        for term in terms.prefix(3) {
            statement.bind(bindIndex, "%\(term)%")
            bindIndex += 1
            statement.bind(bindIndex, "%\(term)%")
            bindIndex += 1
        }
        statement.bind(bindIndex, limit)
        var results: [IndexedFile] = []
        while try statement.step() {
            results.append(StoreMapping.file(from: statement))
        }
        return results
    }

    /// Returns every extracted passage for a file. Used by the in-app preview
    /// so users can inspect exactly what the index contains without opening
    /// another application.
    func chunks(forFileID fileID: Int64, limit: Int = 240) throws -> [StoredChunk] {
        let statement = try db.prepare("""
            SELECT \(StoreMapping.fileColumns),
                   c.id, c.text, c.page, c.line_start, c.time_start, c.time_end
            FROM files f
            JOIN chunks c ON c.file_id = f.id
            WHERE f.id = ?
            ORDER BY c.idx ASC LIMIT ?
            """)
        statement.bind(1, fileID)
        statement.bind(2, limit)
        var results: [StoredChunk] = []
        while try statement.step() {
            let file = StoreMapping.file(from: statement, offset: 0)
            let page = statement.isNull(17) ? nil : statement.int(17)
            let line = statement.isNull(18) ? nil : statement.int(18)
            let start = statement.isNull(19) ? nil : statement.double(19)
            let end = statement.isNull(20) ? nil : statement.double(20)
            results.append(StoredChunk(
                chunkID: statement.int64(15),
                file: file,
                text: statement.string(16) ?? "",
                locator: ContentLocator(page: page, line: line, timeStart: start, timeEnd: end)
            ))
        }
        return results
    }

    func firstChunk(forFileID fileID: Int64) throws -> StoredChunk? {
        let statement = try db.prepare("""
            SELECT \(StoreMapping.fileColumns),
                   c.id, c.text, c.page, c.line_start, c.time_start, c.time_end
            FROM files f
            JOIN chunks c ON c.file_id = f.id
            WHERE f.id = ?
            ORDER BY c.idx ASC LIMIT 1
            """)
        statement.bind(1, fileID)
        guard try statement.step() else { return nil }
        let file = StoreMapping.file(from: statement, offset: 0)
        let page = statement.isNull(17) ? nil : statement.int(17)
        let line = statement.isNull(18) ? nil : statement.int(18)
        let start = statement.isNull(19) ? nil : statement.double(19)
        let end = statement.isNull(20) ? nil : statement.double(20)
        return StoredChunk(
            chunkID: statement.int64(15),
            file: file,
            text: statement.string(16) ?? "",
            locator: ContentLocator(page: page, line: line, timeStart: start, timeEnd: end)
        )
    }

    func recentFilesFiltered(filters: SearchFilters, limit: Int = 40) throws -> [IndexedFile] {
        let sql = """
            SELECT \(StoreMapping.fileColumns) FROM files f
            WHERE f.status = 'indexed'
              \(Self.filterClause(filters))
            ORDER BY f.indexed_at DESC
            LIMIT ?
            """
        let statement = try db.prepare(sql)
        statement.bind(1, limit)
        var results: [IndexedFile] = []
        while try statement.step() {
            results.append(StoreMapping.file(from: statement))
        }
        return results
    }

    func indexedEmbeddingModels() throws -> [String] {
        let statement = try db.prepare("""
            SELECT DISTINCT embedding_model FROM chunks
            WHERE embedding_model IS NOT NULL ORDER BY embedding_model
            """)
        var models: [String] = []
        while try statement.step() {
            if let model = statement.string(0) { models.append(model) }
        }
        return models
    }

    func embeddedChunkCount(forModel model: String) throws -> Int {
        let statement = try db.prepare("""
            SELECT COUNT(*) FROM chunks WHERE embedding IS NOT NULL AND embedding_model = ?
            """)
        statement.bind(1, model)
        guard try statement.step() else { return 0 }
        return statement.int(0)
    }
}

private struct SemanticRow: Sendable {
    let chunkID: Int64
    let file: IndexedFile
    let text: String
    let locator: ContentLocator
    let similarity: Double
}
