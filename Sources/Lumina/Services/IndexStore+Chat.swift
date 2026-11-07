import Foundation

extension IndexStore {
    // MARK: Conversations

    func createConversation(mode: ChatMode, title: String = "New conversation") throws -> Conversation {
        let now = Date().timeIntervalSince1970
        let statement = try db.prepare("""
            INSERT INTO conversations(title, mode, created_at, updated_at)
            VALUES (?, ?, ?, ?)
            """)
        statement.bind(1, title)
        statement.bind(2, mode.rawValue)
        statement.bind(3, now)
        statement.bind(4, now)
        try statement.step()
        let id = db.lastInsertRowID
        return Conversation(
            id: id,
            title: title,
            mode: mode,
            createdAt: Date(timeIntervalSince1970: now),
            updatedAt: Date(timeIntervalSince1970: now),
            messageCount: 0
        )
    }

    func conversations(limit: Int = 40) throws -> [Conversation] {
        let statement = try db.prepare("""
            SELECT c.id, c.title, c.mode, c.created_at, c.updated_at,
                   (SELECT COUNT(*) FROM messages m WHERE m.conversation_id = c.id)
            FROM conversations c
            ORDER BY c.updated_at DESC LIMIT ?
            """)
        statement.bind(1, limit)
        var results: [Conversation] = []
        while try statement.step() {
            results.append(Conversation(
                id: statement.int64(0),
                title: statement.string(1) ?? "Conversation",
                mode: ChatMode(rawValue: statement.string(2) ?? "") ?? .answer,
                createdAt: Date(timeIntervalSince1970: statement.double(3)),
                updatedAt: Date(timeIntervalSince1970: statement.double(4)),
                messageCount: statement.int(5)
            ))
        }
        return results
    }

    func conversation(id: Int64) throws -> Conversation? {
        let statement = try db.prepare("""
            SELECT c.id, c.title, c.mode, c.created_at, c.updated_at,
                   (SELECT COUNT(*) FROM messages m WHERE m.conversation_id = c.id)
            FROM conversations c WHERE c.id = ?
            """)
        statement.bind(1, id)
        guard try statement.step() else { return nil }
        return Conversation(
            id: statement.int64(0),
            title: statement.string(1) ?? "Conversation",
            mode: ChatMode(rawValue: statement.string(2) ?? "") ?? .answer,
            createdAt: Date(timeIntervalSince1970: statement.double(3)),
            updatedAt: Date(timeIntervalSince1970: statement.double(4)),
            messageCount: statement.int(5)
        )
    }

    func updateConversationTitle(id: Int64, title: String) throws {
        let statement = try db.prepare("UPDATE conversations SET title = ?, updated_at = ? WHERE id = ?")
        statement.bind(1, title)
        statement.bind(2, Date().timeIntervalSince1970)
        statement.bind(3, id)
        try statement.step()
    }

    func updateConversationMode(id: Int64, mode: ChatMode) throws {
        let statement = try db.prepare("UPDATE conversations SET mode = ?, updated_at = ? WHERE id = ?")
        statement.bind(1, mode.rawValue)
        statement.bind(2, Date().timeIntervalSince1970)
        statement.bind(3, id)
        try statement.step()
    }

    func deleteConversation(id: Int64) throws {
        let statement = try db.prepare("DELETE FROM conversations WHERE id = ?")
        statement.bind(1, id)
        try statement.step()
    }

    func messages(conversationID: Int64) throws -> [ChatMessage] {
        let statement = try db.prepare("""
            SELECT id, conversation_id, role, content, citations, created_at, is_error
            FROM messages WHERE conversation_id = ? ORDER BY id ASC
            """)
        statement.bind(1, conversationID)
        var results: [ChatMessage] = []
        while try statement.step() {
            results.append(Self.message(from: statement))
        }
        return results
    }

    func appendMessage(
        conversationID: Int64,
        role: ChatRole,
        content: String,
        citations: [Citation] = [],
        isError: Bool = false
    ) throws -> ChatMessage {
        let now = Date().timeIntervalSince1970
        let citationData = try? JSONEncoder().encode(citations)
        let statement = try db.prepare("""
            INSERT INTO messages(conversation_id, role, content, citations, created_at, is_error)
            VALUES (?, ?, ?, ?, ?, ?)
            """)
        statement.bind(1, conversationID)
        statement.bind(2, role.rawValue)
        statement.bind(3, content)
        statement.bind(4, data: citationData)
        statement.bind(5, now)
        statement.bind(6, isError)
        try statement.step()

        let touch = try db.prepare("UPDATE conversations SET updated_at = ? WHERE id = ?")
        touch.bind(1, now)
        touch.bind(2, conversationID)
        try touch.step()

        return ChatMessage(
            id: db.lastInsertRowID,
            conversationID: conversationID,
            role: role,
            content: content,
            citations: citations,
            createdAt: Date(timeIntervalSince1970: now),
            isError: isError
        )
    }

    func updateMessage(id: Int64, content: String, citations: [Citation]) throws {
        let statement = try db.prepare("UPDATE messages SET content = ?, citations = ? WHERE id = ?")
        statement.bind(1, content)
        statement.bind(2, data: try? JSONEncoder().encode(citations))
        statement.bind(3, id)
        try statement.step()
    }

    private static func message(from statement: SQLiteStatement) -> ChatMessage {
        let citations: [Citation]
        if let data = statement.data(4),
           let decoded = try? JSONDecoder().decode([Citation].self, from: data) {
            citations = decoded
        } else {
            citations = []
        }
        return ChatMessage(
            id: statement.int64(0),
            conversationID: statement.int64(1),
            role: ChatRole(rawValue: statement.string(2) ?? "") ?? .assistant,
            content: statement.string(3) ?? "",
            citations: citations,
            createdAt: Date(timeIntervalSince1970: statement.double(5)),
            isError: statement.bool(6)
        )
    }

    // MARK: Notes

    func addNote(fileID: Int64?, text: String) throws -> UserNote {
        let now = Date().timeIntervalSince1970
        let statement = try db.prepare("""
            INSERT INTO notes(file_id, text, created_at, updated_at) VALUES (?, ?, ?, ?)
            """)
        if let fileID { statement.bind(1, fileID) } else { statement.bindNull(1) }
        statement.bind(2, text)
        statement.bind(3, now)
        statement.bind(4, now)
        try statement.step()
        let noteID = db.lastInsertRowID
        let file: IndexedFile?
        if let fileID {
            file = try self.file(id: fileID)
        } else {
            file = nil
        }
        return UserNote(
            id: noteID,
            fileID: fileID,
            text: text,
            createdAt: Date(timeIntervalSince1970: now),
            updatedAt: Date(timeIntervalSince1970: now),
            file: file
        )
    }

    func notes(limit: Int = 100) throws -> [UserNote] {
        let statement = try db.prepare("""
            SELECT n.id, n.file_id, n.text, n.created_at, n.updated_at,
                   \(StoreMapping.fileColumns)
            FROM notes n
            LEFT JOIN files f ON f.id = n.file_id
            ORDER BY n.created_at DESC LIMIT ?
            """)
        statement.bind(1, limit)
        var results: [UserNote] = []
        while try statement.step() {
            results.append(Self.note(from: statement))
        }
        return results
    }

    func notes(forFileID fileID: Int64) throws -> [UserNote] {
        let statement = try db.prepare("""
            SELECT n.id, n.file_id, n.text, n.created_at, n.updated_at,
                   \(StoreMapping.fileColumns)
            FROM notes n
            LEFT JOIN files f ON f.id = n.file_id
            WHERE n.file_id = ?
            ORDER BY n.created_at DESC
            """)
        statement.bind(1, fileID)
        var results: [UserNote] = []
        while try statement.step() {
            results.append(Self.note(from: statement))
        }
        return results
    }

    func deleteNote(id: Int64) throws {
        let statement = try db.prepare("DELETE FROM notes WHERE id = ?")
        statement.bind(1, id)
        try statement.step()
    }

    private static func note(from statement: SQLiteStatement) -> UserNote {
        let file: IndexedFile? = statement.isNull(5) ? nil : StoreMapping.file(from: statement, offset: 5)
        return UserNote(
            id: statement.int64(0),
            fileID: statement.isNull(1) ? nil : statement.int64(1),
            text: statement.string(2) ?? "",
            createdAt: Date(timeIntervalSince1970: statement.double(3)),
            updatedAt: Date(timeIntervalSince1970: statement.double(4)),
            file: file
        )
    }

    // MARK: Timeline

    func timeline(limit: Int = 80) throws -> [TimelineItem] {
        var items: [TimelineItem] = []
        var seenFiles = Set<Int64>()

        for file in try recentFiles(limit: limit) {
            seenFiles.insert(file.id)
            items.append(TimelineItem(
                id: "file-\(file.id)",
                kind: file.isPinned ? .pinned : .indexed,
                title: file.name,
                subtitle: "\(file.kind.displayName) · \(file.chunkCount) passage\(file.chunkCount == 1 ? "" : "s")",
                date: file.indexedAt,
                file: file,
                conversationID: nil,
                noteID: nil,
                isPinned: file.isPinned
            ))
        }

        for file in try pinnedFiles(limit: 20) where !seenFiles.contains(file.id) {
            items.append(TimelineItem(
                id: "file-\(file.id)",
                kind: .pinned,
                title: file.name,
                subtitle: "Pinned · \(file.kind.displayName)",
                date: file.indexedAt,
                file: file,
                conversationID: nil,
                noteID: nil,
                isPinned: true
            ))
        }

        for note in try notes(limit: limit) {
            let firstLine = note.text
                .split(whereSeparator: \.isNewline)
                .first
                .map(String.init) ?? "Note"
            items.append(TimelineItem(
                id: "note-\(note.id)",
                kind: .note,
                title: firstLine,
                subtitle: note.file?.name ?? "Private note",
                date: note.createdAt,
                file: note.file,
                conversationID: nil,
                noteID: note.id,
                isPinned: note.file?.isPinned ?? false
            ))
        }

        for conversation in try conversations(limit: 30) where conversation.messageCount > 0 {
            items.append(TimelineItem(
                id: "conversation-\(conversation.id)",
                kind: .conversation,
                title: conversation.title,
                subtitle: "Conversation · \(conversation.messageCount) message\(conversation.messageCount == 1 ? "" : "s")",
                date: conversation.updatedAt,
                file: nil,
                conversationID: conversation.id,
                noteID: nil,
                isPinned: false
            ))
        }

        return items.sorted { $0.date > $1.date }
    }
}
