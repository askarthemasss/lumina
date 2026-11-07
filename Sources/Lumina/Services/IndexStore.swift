import Foundation

// MARK: - Write inputs

struct FileWriteInput: Sendable {
    var folderID: Int64?
    var path: String
    var name: String
    var kind: ContentKind
    var fileSize: Int64
    var modifiedAt: Date
    var pageCount: Int?
    var duration: TimeInterval?
    var thumbnailPath: String?
    var featurePrint: Data?
    var embeddingModel: String?
}

struct ChunkWriteInput: Sendable {
    var index: Int
    var text: String
    var locator: ContentLocator
    var embedding: [Float]?
}

struct ExistingFileSnapshot: Sendable {
    let id: Int64
    let modifiedAt: Date
    let fileSize: Int64
    let chunkCount: Int
    let embeddedChunks: Int
    let embeddingModel: String?
    let status: String
}

struct ExistingFileRef: Sendable {
    let id: Int64
    let path: String
}

enum StoreMapping {
    /// The canonical file column projection used by every query that returns
    /// an `IndexedFile`. Keep in sync with `file(from:offset:)`.
    static let fileColumns = """
        f.id, f.folder_id, f.path, f.name, f.kind, f.size, f.modified_at,
        f.indexed_at, f.page_count, f.duration, f.thumbnail_path,
        f.chunk_count, f.embedded_chunks, f.pinned, f.error
        """

    static func file(from statement: SQLiteStatement, offset: Int32 = 0) -> IndexedFile {
        let kind = ContentKind(rawValue: statement.string(offset + 4) ?? "") ?? .text
        let pageCount = statement.isNull(offset + 8) ? nil : statement.int(offset + 8)
        let duration = statement.isNull(offset + 9) ? nil : statement.double(offset + 9)
        let thumbnailPath = statement.string(offset + 10)
        let chunkCount = statement.int(offset + 11)
        let embeddedChunks = statement.int(offset + 12)
        return IndexedFile(
            id: statement.int64(offset),
            folderID: statement.isNull(offset + 1) ? nil : statement.int64(offset + 1),
            path: statement.string(offset + 2) ?? "",
            name: statement.string(offset + 3) ?? "Untitled",
            kind: kind,
            fileSize: statement.int64(offset + 5),
            modifiedAt: Date(timeIntervalSince1970: statement.double(offset + 6)),
            indexedAt: Date(timeIntervalSince1970: statement.double(offset + 7)),
            pageCount: pageCount,
            duration: duration,
            thumbnailPath: thumbnailPath,
            chunkCount: chunkCount,
            isPinned: statement.bool(offset + 13),
            hasEmbeddings: chunkCount > 0 && embeddedChunks >= chunkCount,
            errorMessage: statement.string(offset + 14)
        )
    }
}

enum IndexStoreError: LocalizedError {
    case folderMissing
    case fileMissing

    var errorDescription: String? {
        switch self {
        case .folderMissing: "That folder is no longer available."
        case .fileMissing: "That file is no longer available."
        }
    }
}

// MARK: - Store

/// Owns the SQLite index. All access is serialized through actor isolation,
/// which means the UI and indexing pipeline can query concurrently without
/// data races and without a global database lock.
actor IndexStore {
    nonisolated let databaseURL: URL
    let db: SQLiteDatabase

    init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        let directory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.db = try SQLiteDatabase(url: databaseURL)
        try Self.createSchema(db: db)
    }

    private static func createSchema(db: SQLiteDatabase) throws {
        try db.execute("""
        CREATE TABLE IF NOT EXISTS folders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT NOT NULL UNIQUE,
            bookmark BLOB,
            added_at REAL NOT NULL,
            is_enabled INTEGER NOT NULL DEFAULT 1
        );

        CREATE TABLE IF NOT EXISTS files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            folder_id INTEGER REFERENCES folders(id) ON DELETE CASCADE,
            path TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            kind TEXT NOT NULL,
            size INTEGER NOT NULL DEFAULT 0,
            modified_at REAL NOT NULL,
            indexed_at REAL NOT NULL,
            page_count INTEGER,
            duration REAL,
            thumbnail_path TEXT,
            feature_print BLOB,
            chunk_count INTEGER NOT NULL DEFAULT 0,
            embedded_chunks INTEGER NOT NULL DEFAULT 0,
            embedding_model TEXT,
            pinned INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'indexed',
            error TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_files_folder ON files(folder_id);
        CREATE INDEX IF NOT EXISTS idx_files_kind ON files(kind);
        CREATE INDEX IF NOT EXISTS idx_files_modified ON files(modified_at);
        CREATE INDEX IF NOT EXISTS idx_files_indexed ON files(indexed_at);

        CREATE TABLE IF NOT EXISTS chunks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
            idx INTEGER NOT NULL,
            text TEXT NOT NULL,
            page INTEGER,
            line_start INTEGER,
            time_start REAL,
            time_end REAL,
            embedding BLOB,
            embedding_model TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_chunks_file ON chunks(file_id);
        CREATE INDEX IF NOT EXISTS idx_chunks_embedding_model ON chunks(embedding_model);

        CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
            text,
            content='chunks',
            content_rowid='id',
            tokenize='unicode61 remove_diacritics 2'
        );

        CREATE TRIGGER IF NOT EXISTS chunks_fts_insert AFTER INSERT ON chunks BEGIN
            INSERT INTO chunks_fts(rowid, text) VALUES (new.id, new.text);
        END;

        CREATE TRIGGER IF NOT EXISTS chunks_fts_delete AFTER DELETE ON chunks BEGIN
            INSERT INTO chunks_fts(chunks_fts, rowid, text) VALUES ('delete', old.id, old.text);
        END;

        CREATE TRIGGER IF NOT EXISTS chunks_fts_update AFTER UPDATE OF text ON chunks BEGIN
            INSERT INTO chunks_fts(chunks_fts, rowid, text) VALUES ('delete', old.id, old.text);
            INSERT INTO chunks_fts(rowid, text) VALUES (new.id, new.text);
        END;

        CREATE TABLE IF NOT EXISTS conversations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            mode TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            conversation_id INTEGER NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            citations BLOB,
            created_at REAL NOT NULL,
            is_error INTEGER NOT NULL DEFAULT 0
        );

        CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id);

        CREATE TABLE IF NOT EXISTS notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_id INTEGER REFERENCES files(id) ON DELETE CASCADE,
            text TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_notes_file ON notes(file_id);

        CREATE TABLE IF NOT EXISTS meta (
            key TEXT PRIMARY KEY,
            value TEXT
        );

        PRAGMA user_version = 1;
        """)
    }

    // MARK: Folders

    func addFolder(path: String, bookmark: Data?) throws -> IndexedFolder {
        let now = Date().timeIntervalSince1970
        let statement = try db.prepare("""
            INSERT INTO folders(path, bookmark, added_at, is_enabled)
            VALUES (?, ?, ?, 1)
            ON CONFLICT(path) DO UPDATE SET is_enabled = 1
            """)
        statement.bind(1, path)
        statement.bind(2, data: bookmark)
        statement.bind(3, now)
        try statement.step()

        guard let folder = try folder(path: path) else {
            throw IndexStoreError.folderMissing
        }
        return folder
    }

    func folders() throws -> [IndexedFolder] {
        let statement = try db.prepare("""
            SELECT id, path, added_at, is_enabled FROM folders ORDER BY added_at ASC
            """)
        var results: [IndexedFolder] = []
        while try statement.step() {
            results.append(Self.folder(from: statement))
        }
        return results
    }

    func folder(path: String) throws -> IndexedFolder? {
        let statement = try db.prepare("""
            SELECT id, path, added_at, is_enabled FROM folders WHERE path = ?
            """)
        statement.bind(1, path)
        guard try statement.step() else { return nil }
        return Self.folder(from: statement)
    }

    func setFolderEnabled(_ id: Int64, enabled: Bool) throws {
        let statement = try db.prepare("UPDATE folders SET is_enabled = ? WHERE id = ?")
        statement.bind(1, enabled)
        statement.bind(2, id)
        try statement.step()
    }

    func removeFolder(id: Int64) throws {
        try db.transaction {
            let chunkDelete = try db.prepare("""
                DELETE FROM chunks WHERE file_id IN (SELECT id FROM files WHERE folder_id = ?)
                """)
            chunkDelete.bind(1, id)
            try chunkDelete.step()

            let folderDelete = try db.prepare("DELETE FROM folders WHERE id = ?")
            folderDelete.bind(1, id)
            try folderDelete.step()
        }
    }

    func bookmark(forFolderID id: Int64) throws -> Data? {
        let statement = try db.prepare("SELECT bookmark FROM folders WHERE id = ?")
        statement.bind(1, id)
        guard try statement.step() else { return nil }
        return statement.data(0)
    }

    private static func folder(from statement: SQLiteStatement) -> IndexedFolder {
        let path = statement.string(1) ?? ""
        return IndexedFolder(
            id: statement.int64(0),
            path: path,
            name: URL(fileURLWithPath: path, isDirectory: true).lastPathComponent,
            addedAt: Date(timeIntervalSince1970: statement.double(2)),
            isEnabled: statement.bool(3)
        )
    }

    // MARK: Files

    func existingSnapshots() throws -> [String: ExistingFileSnapshot] {
        let statement = try db.prepare("""
            SELECT path, id, modified_at, size, chunk_count, embedded_chunks, embedding_model, status
            FROM files
            """)
        var results: [String: ExistingFileSnapshot] = [:]
        while try statement.step() {
            guard let path = statement.string(0) else { continue }
            results[path] = ExistingFileSnapshot(
                id: statement.int64(1),
                modifiedAt: Date(timeIntervalSince1970: statement.double(2)),
                fileSize: statement.int64(3),
                chunkCount: statement.int(4),
                embeddedChunks: statement.int(5),
                embeddingModel: statement.string(6),
                status: statement.string(7) ?? "indexed"
            )
        }
        return results
    }

    func saveFile(_ input: FileWriteInput, chunks: [ChunkWriteInput]) throws -> Int64 {
        let now = Date().timeIntervalSince1970
        let validChunks = chunks.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let embeddedCount = validChunks.reduce(into: 0) { result, chunk in
            if chunk.embedding != nil { result += 1 }
        }
        let model = embeddedCount > 0 ? input.embeddingModel : nil

        return try db.transaction {
            let existing = try db.prepare("SELECT id FROM files WHERE path = ?")
            existing.bind(1, input.path)
            let existingID: Int64? = try existing.step() ? existing.int64(0) : nil
            let fileID: Int64

            if let existingID {
                let deleteChunks = try db.prepare("DELETE FROM chunks WHERE file_id = ?")
                deleteChunks.bind(1, existingID)
                try deleteChunks.step()

                let update = try db.prepare("""
                    UPDATE files SET
                        folder_id = ?, name = ?, kind = ?, size = ?, modified_at = ?,
                        indexed_at = ?, page_count = ?, duration = ?,
                        thumbnail_path = COALESCE(?, thumbnail_path),
                        feature_print = COALESCE(?, feature_print),
                        chunk_count = ?, embedded_chunks = ?, embedding_model = ?,
                        status = 'indexed', error = NULL
                    WHERE id = ?
                    """)
                bindFileFields(update, input, now: now, chunkCount: validChunks.count,
                               embeddedCount: embeddedCount, model: model)
                update.bind(14, existingID)
                try update.step()
                fileID = existingID
            } else {
                let insert = try db.prepare("""
                    INSERT INTO files(
                        folder_id, name, path, kind, size, modified_at, indexed_at,
                        page_count, duration, thumbnail_path, feature_print,
                        chunk_count, embedded_chunks, embedding_model, status
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'indexed')
                    """)
                if let folderID = input.folderID { insert.bind(1, folderID) } else { insert.bindNull(1) }
                insert.bind(2, input.name)
                insert.bind(3, input.path)
                insert.bind(4, input.kind.rawValue)
                insert.bind(5, input.fileSize)
                insert.bind(6, input.modifiedAt.timeIntervalSince1970)
                insert.bind(7, now)
                if let pageCount = input.pageCount { insert.bind(8, pageCount) } else { insert.bindNull(8) }
                if let duration = input.duration { insert.bind(9, duration) } else { insert.bindNull(9) }
                insert.bind(10, input.thumbnailPath)
                insert.bind(11, data: input.featurePrint)
                insert.bind(12, validChunks.count)
                insert.bind(13, embeddedCount)
                insert.bind(14, model)
                try insert.step()
                fileID = db.lastInsertRowID
            }

            let chunkInsert = try db.prepare("""
                INSERT INTO chunks(file_id, idx, text, page, line_start, time_start, time_end, embedding, embedding_model)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """)
            for chunk in validChunks {
                chunkInsert.reset()
                chunkInsert.bind(1, fileID)
                chunkInsert.bind(2, chunk.index)
                chunkInsert.bind(3, chunk.text)
                if let page = chunk.locator.page { chunkInsert.bind(4, page) } else { chunkInsert.bindNull(4) }
                if let line = chunk.locator.line { chunkInsert.bind(5, line) } else { chunkInsert.bindNull(5) }
                if let time = chunk.locator.timeStart { chunkInsert.bind(6, time) } else { chunkInsert.bindNull(6) }
                if let time = chunk.locator.timeEnd { chunkInsert.bind(7, time) } else { chunkInsert.bindNull(7) }
                if let embedding = chunk.embedding {
                    chunkInsert.bind(8, data: VectorMath.encode(embedding))
                    chunkInsert.bind(9, model)
                } else {
                    chunkInsert.bindNull(8)
                    chunkInsert.bindNull(9)
                }
                try chunkInsert.step()
            }

            // A file with no extractable text still deserves one metadata chunk
            // so its name and location are searchable.
            if validChunks.isEmpty {
                let fallback = try db.prepare("""
                    INSERT INTO chunks(file_id, idx, text, embedding, embedding_model)
                    VALUES (?, 0, ?, NULL, NULL)
                    """)
                fallback.bind(1, fileID)
                fallback.bind(2, "\(input.name)\n\(input.path)")
                try fallback.step()
                let countUpdate = try db.prepare("UPDATE files SET chunk_count = 1 WHERE id = ?")
                countUpdate.bind(1, fileID)
                try countUpdate.step()
            }

            return fileID
        }
    }

    private func bindFileFields(
        _ statement: SQLiteStatement,
        _ input: FileWriteInput,
        now: Double,
        chunkCount: Int,
        embeddedCount: Int,
        model: String?
    ) {
        if let folderID = input.folderID { statement.bind(1, folderID) } else { statement.bindNull(1) }
        statement.bind(2, input.name)
        statement.bind(3, input.kind.rawValue)
        statement.bind(4, input.fileSize)
        statement.bind(5, input.modifiedAt.timeIntervalSince1970)
        statement.bind(6, now)
        if let pageCount = input.pageCount { statement.bind(7, pageCount) } else { statement.bindNull(7) }
        if let duration = input.duration { statement.bind(8, duration) } else { statement.bindNull(8) }
        statement.bind(9, input.thumbnailPath)
        statement.bind(10, data: input.featurePrint)
        statement.bind(11, chunkCount)
        statement.bind(12, embeddedCount)
        statement.bind(13, model)
    }

    func recordFileError(
        path: String,
        name: String,
        kind: ContentKind,
        fileSize: Int64,
        modifiedAt: Date,
        folderID: Int64?,
        message: String
    ) throws {
        let now = Date().timeIntervalSince1970
        let statement = try db.prepare("""
            INSERT INTO files(folder_id, name, path, kind, size, modified_at, indexed_at, status, error)
            VALUES (?, ?, ?, ?, ?, ?, ?, 'error', ?)
            ON CONFLICT(path) DO UPDATE SET
                status = 'error',
                error = excluded.error,
                indexed_at = excluded.indexed_at
            """)
        if let folderID { statement.bind(1, folderID) } else { statement.bindNull(1) }
        statement.bind(2, name)
        statement.bind(3, path)
        statement.bind(4, kind.rawValue)
        statement.bind(5, fileSize)
        statement.bind(6, modifiedAt.timeIntervalSince1970)
        statement.bind(7, now)
        statement.bind(8, message)
        try statement.step()
    }

    func deleteFiles(ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        try db.transaction {
            let chunkDelete = try db.prepare("DELETE FROM chunks WHERE file_id = ?")
            let fileDelete = try db.prepare("DELETE FROM files WHERE id = ?")
            for id in ids {
                chunkDelete.reset()
                chunkDelete.bind(1, id)
                try chunkDelete.step()
                fileDelete.reset()
                fileDelete.bind(1, id)
                try fileDelete.step()
            }
        }
    }

    func fileIDsAndPaths(folderID: Int64) throws -> [ExistingFileRef] {
        let statement = try db.prepare("SELECT id, path FROM files WHERE folder_id = ?")
        statement.bind(1, folderID)
        var result: [ExistingFileRef] = []
        while try statement.step() {
            result.append(ExistingFileRef(id: statement.int64(0), path: statement.string(1) ?? ""))
        }
        return result
    }

    func file(id: Int64) throws -> IndexedFile? {
        let statement = try db.prepare("SELECT \(StoreMapping.fileColumns) FROM files f WHERE f.id = ?")
        statement.bind(1, id)
        guard try statement.step() else { return nil }
        return StoreMapping.file(from: statement)
    }

    func recentFiles(limit: Int = 12) throws -> [IndexedFile] {
        let statement = try db.prepare("""
            SELECT \(StoreMapping.fileColumns) FROM files f
            WHERE f.status = 'indexed'
            ORDER BY f.indexed_at DESC LIMIT ?
            """)
        statement.bind(1, limit)
        var results: [IndexedFile] = []
        while try statement.step() {
            results.append(StoreMapping.file(from: statement))
        }
        return results
    }

    func libraryFiles(
        kinds: Set<ContentKind> = [],
        folderID: Int64? = nil,
        search: String = "",
        limit: Int = 600
    ) throws -> [IndexedFile] {
        var clauses = ["f.status = 'indexed'"]
        if !kinds.isEmpty {
            let values = kinds.map { "'\($0.rawValue)'" }.joined(separator: ",")
            clauses.append("f.kind IN (\(values))")
        }
        if let folderID {
            clauses.append("f.folder_id = \(folderID)")
        }
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            clauses.append("(f.name LIKE ? OR f.path LIKE ?)")
        }
        let sql = """
            SELECT \(StoreMapping.fileColumns) FROM files f
            WHERE \(clauses.joined(separator: " AND "))
            ORDER BY f.indexed_at DESC LIMIT \(limit)
            """
        let statement = try db.prepare(sql)
        if !trimmed.isEmpty {
            statement.bind(1, "%\(trimmed)%")
            statement.bind(2, "%\(trimmed)%")
        }
        var results: [IndexedFile] = []
        while try statement.step() {
            results.append(StoreMapping.file(from: statement))
        }
        return results
    }

    func stats() throws -> LibraryStats {
        var stats = LibraryStats()
        let fileStats = try db.prepare("""
            SELECT COUNT(*), COALESCE(SUM(size), 0), MAX(indexed_at),
                   COALESCE(SUM(CASE WHEN status = 'error' THEN 1 ELSE 0 END), 0)
            FROM files
            """)
        if try fileStats.step() {
            stats.fileCount = fileStats.int(0)
            stats.totalBytes = fileStats.int64(1)
            if !fileStats.isNull(2) {
                stats.lastIndexedAt = Date(timeIntervalSince1970: fileStats.double(2))
            }
            stats.failedFileCount = fileStats.int(3)
        }

        stats.folderCount = Int(try db.scalarInt("SELECT COUNT(*) FROM folders"))
        stats.chunkCount = Int(try db.scalarInt("SELECT COUNT(*) FROM chunks"))
        stats.embeddedChunkCount = Int(try db.scalarInt("SELECT COUNT(*) FROM chunks WHERE embedding IS NOT NULL"))

        let kindStats = try db.prepare("SELECT kind, COUNT(*) FROM files WHERE status = 'indexed' GROUP BY kind")
        while try kindStats.step() {
            guard let raw = kindStats.string(0), let kind = ContentKind(rawValue: raw) else { continue }
            stats.countsByKind[kind] = kindStats.int(1)
        }
        return stats
    }

    func togglePin(fileID: Int64) throws -> Bool {
        let toggle = try db.prepare("UPDATE files SET pinned = CASE pinned WHEN 0 THEN 1 ELSE 0 END WHERE id = ?")
        toggle.bind(1, fileID)
        try toggle.step()
        let read = try db.prepare("SELECT pinned FROM files WHERE id = ?")
        read.bind(1, fileID)
        guard try read.step() else { return false }
        return read.bool(0)
    }

    func pinnedFiles(limit: Int = 8) throws -> [IndexedFile] {
        let statement = try db.prepare("""
            SELECT \(StoreMapping.fileColumns) FROM files f
            WHERE f.pinned = 1 AND f.status = 'indexed'
            ORDER BY f.modified_at DESC LIMIT ?
            """)
        statement.bind(1, limit)
        var results: [IndexedFile] = []
        while try statement.step() { results.append(StoreMapping.file(from: statement)) }
        return results
    }

    // MARK: Maintenance

    func referencedThumbnailPaths() throws -> Set<String> {
        let statement = try db.prepare("""
            SELECT thumbnail_path FROM files WHERE thumbnail_path IS NOT NULL
            """)
        var paths = Set<String>()
        while try statement.step() {
            if let path = statement.string(0) { paths.insert(path) }
        }
        return paths
    }

    func resetIndex() throws {
        try db.transaction {
            try db.execute("DELETE FROM chunks;")
            try db.execute("DELETE FROM files;")
        }
    }

    /// Used by the privacy "erase everything" action. Folders are removed so
    /// a subsequent launch starts from a clean, explicit setup.
    func eraseAllContent() throws {
        try db.transaction {
            try db.execute("DELETE FROM messages;")
            try db.execute("DELETE FROM conversations;")
            try db.execute("DELETE FROM notes;")
            try db.execute("DELETE FROM chunks;")
            try db.execute("DELETE FROM files;")
            try db.execute("DELETE FROM folders;")
            try db.execute("INSERT INTO chunks_fts(chunks_fts) VALUES('rebuild');")
        }
    }

    func checkpoint() throws {
        try db.execute("PRAGMA wal_checkpoint(TRUNCATE);")
    }
}
