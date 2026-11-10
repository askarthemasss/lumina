# Lumina architecture

Lumina is a single-process AppKit/SwiftUI app backed by one SQLite database and a loopback-only HTTP client. There is no daemon, no account service, no background uploader, and no bundled web view.

This document describes how the pieces fit together, where state lives, and what a change to one layer implies for the others.

---

## 1. Design constraints

1. **The privacy boundary is enforced in code.** User content may only be sent to a model server on the same machine. The check lives in `LocalInferenceClient.init`, not in the UI.
2. **Everything useful degrades gracefully.** Keyword search, browsing, previews, notes, and pins work without any model. Missing models produce warnings, not a broken app.
3. **One local source of truth.** Extracted text, vectors, metadata, conversations, and notes are rows in one SQLite file. No cache is authoritative over it.
4. **Native patterns only.** SwiftUI for screens, AppKit where the platform demands it (windows, hot keys, open panels, NSWorkspace), Apple frameworks for media understanding.
5. **Small, inspectable surface.** Direct SQLite C API, no ORM. A tiny HTTP client, no SDK. No third-party runtime dependency.

---

## 2. Process and layer map

```text
┌────────────────────────────────────────────────────────────────────┐
│ AppDelegate (AppKit)                                                │
│  ├── NSWindow + NSHostingController<RootView>                       │
│  ├── QuickSearchPanel (borderless NSPanel)                          │
│  ├── HotKeyManager (Carbon global shortcut)                         │
│  └── NotificationCenter bridge (.luminaOpenMainWindow, …)           │
│                                                                     │
│ LuminaApp (SwiftUI)  → Settings scene, LuminaCommands                │
└───────────────────────────────┬────────────────────────────────────┘
                                │ environment
┌───────────────────────────────▼────────────────────────────────────┐
│ AppEnvironment.shared         creates once, owns nothing else       │
│  └── AppModel (@MainActor, @Observable)                             │
│       ├── route, errors, banners, setup snapshot                    │
│       ├── folders, stats, library/timeline collections              │
│       ├── chat state, streaming task, indexing task                  │
│       └── services: IndexStore, SearchService, RAGService,          │
│                     IndexingEngine, AppSettings                     │
└───────┬───────────────────────┬───────────────────────┬─────────────┘
        │                       │                       │
        ▼                       ▼                       ▼
  IndexStore (actor)     SearchService (value)     IndexingEngine (actor)
  SQLite + FTS5          RRF fusion                scan → extract → embed
        │                       │                       │
        └───────────┬───────────┴───────────┬───────────┘
                    ▼                       ▼
              RAGService (actor)      LocalInferenceClient (Sendable)
              prompt + citations      Ollama / OpenAI-compatible
                    │                 loopback only
                    ▼
             AsyncThrowingStream<String>
```

### Why `AppDelegate` owns the window

Lumina is a single-window app that must also be reopenable from a menu-bar-style Quick Search panel and a global shortcut. Owning one `NSWindow` explicitly in `AppDelegate` avoids SwiftUI's automatic last-window teardown and makes “close ≠ discard state” deterministic. The SwiftUI `App` still supplies the Settings scene and command menus; it does not create the main window.

`QuickSearchPanelController` builds a borderless `NSPanel` with a SwiftUI search field and result list. It is not a SwiftUI `.sheet`, so it can appear over other apps without activating Lumina's main window. `HotKeyManager` registers one Carbon hot key (`⇧⌘Space` by default) and posts a notification; all UI mutations remain on the main actor.

---

## 3. State ownership

| State | Owner | Persistence |
| --- | --- | --- |
| Navigation route, banners, chat stream | `AppModel` | none (session) |
| Folders, files, chunks, vectors | `IndexStore` | `lumina.sqlite` |
| Conversations, messages, citations | `IndexStore` | `lumina.sqlite` |
| Notes and pins | `IndexStore` | `lumina.sqlite` |
| Runtime endpoint, model names, indexing options, appearance, shortcut | `AppSettings` | `UserDefaults`, key `lumina.settings.v1` |
| Thumbnails | `IndexingEngine` / `ContentExtractor` | `thumbnails/` directory |
| Setup snapshot (reachability, installed models) | refresh from `RuntimeDiscovery` | none |

`AppModel` is the only `@Observable` type the views bind to. Services are injected at init, not looked up globally. `AppEnvironment` exists because the custom window and menu commands need a reference outside the SwiftUI environment; it is created once and never replaced.

---

## 4. Storage layer

### 4.1 SQLite wrapper

`SQLiteDatabase` is a thin, synchronous wrapper over `sqlite3`:

- Opens with `SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX`.
- Enables WAL, foreign keys, and a busy timeout.
- Provides prepared statements with typed bind/read helpers (`bind`, `int`, `int64`, `double`, `string`, `data`, `bool`, `isNull`).
- Executes write batches inside `BEGIN IMMEDIATE` / `COMMIT` transactions.
- Closes the handle on deinit and checkpoints WAL on demand.

All database access flows through the `IndexStore` actor, so the wrapper itself does not need locking beyond SQLite's own full-mutex mode.

### 4.2 Schema (user_version = 1)

```sql
folders(id, path UNIQUE, bookmark BLOB, added_at, is_enabled)
files(id, folder_id → folders, path UNIQUE, name, kind, size,
      modified_at, indexed_at, page_count, duration, thumbnail_path,
      feature_print, chunk_count, embedded_chunks, embedding_model,
      pinned, status, error)
chunks(id, file_id → files, idx, text, page, line_start,
       time_start, time_end, embedding BLOB, embedding_model)
chunks_fts  -- FTS5 virtual table, external content = chunks
conversations(id, title, mode, created_at, updated_at)
messages(id, conversation_id → conversations, role, content,
         citations BLOB, created_at, is_error)
notes(id, file_id → files NULL, text, created_at, updated_at)
meta(key PRIMARY KEY, value)
```

Indexes cover folder, kind, modified/indexed dates, chunk→file, embedding model, messages→conversation, and notes→file.

`chunks_fts` is an external-content FTS5 table using `unicode61 remove_diacritics 2`. Triggers keep it in sync on insert, delete, and text update. Deleting a file cascades to chunks and therefore to FTS rows.

Vectors are stored as raw Float32 BLOBs (`VectorMath.encode` / `decode`). They are normalized before insert; similarity is a dot product. `files.embedding_model` and `chunks.embedding_model` make it possible to detect vectors produced by a different model and to query only the active one.

A file is only searchable in semantic mode when `files.status = 'indexed'` and the chunk has a non-null embedding for the requested model. Keyword search also requires `status = 'indexed'`.

### 4.3 File writes

`IndexStore.saveFile(_:chunks:)` is transactional:

1. Look up an existing row by path.
2. If present, delete its chunks (FTS triggers fire).
3. Insert or update the file row with counts and `embedding_model`.
4. Insert chunks with normalized embeddings.
5. Commit.

This makes reindexing idempotent and keeps each file row consistent with its chunks. An embedding failure can still leave a file with vectors on the completed batches and none on the rest; the extracted text is saved either way, and a later reindex fills the remaining vectors. Orphan thumbnails are cleaned separately after index reset/erase.

---

## 5. Ingestion pipeline

Entry point: `IndexingEngine.run(folders:options:configuration:force:)`, called from `AppModel.startIndexing`.

```text
enabled folders
     │  FileScanner.scan
     ▼
FileScanReport: candidates + seenPaths + skipped/unsupported/inaccessible
     │  remove stale rows only for folders fully scanned
     ▼
for each candidate:
  skip if unchanged and already embedded with the active model (unless force)
  ContentExtractor.extract
     ├── plain text / code       decode UTF-8, UTF-16, fallback
     ├── PDF                     PDFKit text; Vision OCR empty pages
     ├── image                   thumbnail, OCR, classification, optional caption
     ├── audio                   metadata + optional on-device transcript
     ├── video                   metadata, 4 frames, OCR/labels + optional transcript
     ├── document                AppKit attributed reader, OOXML fallback
     ├── spreadsheet             shared strings/cell XML or OpenDocument text
     └── presentation            PPTX slide XML in order; ODP document text
     │
  TextChunker (character / line / page chunks with locators)
     │
  embed in batches of 16 against the local embedding model
     │  on embedding failure: keep text, record warning, continue
     ▼
IndexStore.saveFile (single transaction)
     │
  progress → AppModel → UI
```

### Scanner rules

- Starts only from explicit user-selected folders.
- `skipsHiddenFiles`, `skipsPackageDescendants`, and skips symbolic links.
- Skips package-like directories (`.photoslibrary`, `.fcpbundle`, `.sparsebundle`, `.xcarchive`).
- Skips common dependency/build/cache directories (`node_modules`, `.build`, `DerivedData`, virtualenvs, etc.).
- Optional sensitive-file filter: keys, certificates, `.env*`, password stores, `*password*`, `*credential*`, `*secret*`.
- User glob/path exclusions are matched against the file name and relative path.
- Files over the configured limit are skipped rather than truncated.
- If a scan reports inaccessible entries, stale-file cleanup is skipped for that folder so a permission problem cannot erase a valid index.

### Chunking

`TextChunker` provides three strategies:

- `characterChunks` — sentence/whitespace-aware chunks around 1,400 characters with roughly 180 characters of overlap. Used for prose, images, and office text.
- `lineChunks` — line-aware chunks with a line locator, used for code and plain text.
- `pageChunks` — character chunks annotated with a page number, used for PDFs and slides.

Each chunk becomes a `ChunkDraft` with a `ContentLocator` (page, line, time range) so search results and citations can point to the right place. Embedding input prefixes the file name and a short heading hint to keep vectors file-aware.

### Failure policy

Per-file extraction or embedding failures do not stop the run. `IndexingEngine` records warnings, marks the file row (when appropriate), and continues. Cancellation is checked between files, before/after embeddings, and inside long loops. A cancelled run commits files already completed and leaves the rest untouched; `AppModel` clears the running state when the task ends.

---

## 6. Retrieval

`SearchService.search(query:filters:configuration:limit:)` runs three retrievers and merges them.

### 6.1 Keyword (FTS5)

`IndexStore.keywordSearch` builds a safe FTS expression from alphanumeric terms:

- Terms are lowercased, deduplicated, and quoted.
- Normal mode drops common stop words before joining the remaining terms with `OR`, so a full question does not match most of the library.
- Exact-phrase mode keeps stop words and quotes the whole phrase.
- The SQL uses `snippet(chunks_fts, 0, '[[', ']]', '…', 34)` and `bm25(chunks_fts)` for ordering.
- Filters add typed clauses for kind, folder IDs, and modified date range.

### 6.2 Semantic

`IndexStore.semanticSearch` streams every chunk matching the active embedding model and filters, decodes its BLOB, computes cosine similarity via a normalized dot product, and keeps the best `limit` with `BoundedTopK` (a min-heap). Vectors below a 0.02 similarity floor are discarded to avoid noise. Query vectors are normalized the same way as stored vectors.

This is brute-force search by design: it is fast enough for a personal library (tens of thousands of chunks) and avoids an ANN index that would need rebuilding and tuning. The seam is `BoundedTopK` plus the SQL query, so an ANN index can be added later without changing callers.

Cosine scores are model- and corpus-dependent, so `SearchService.relevantSemanticMatches` then keeps only the candidates within 90% of the best score. Without that relative cutoff, a broad query returns every file in the library because every pair has a nonzero similarity.

### 6.3 File-name matching

`filenameMatches` performs parameterized `LIKE` matching on name and path for up to three terms. When a query contains terms of three or more characters, shorter tokens are ignored so identifiers such as `4a` do not match a `.m4a` extension. Results without extracted chunks become synthetic hits with id `-fileID` so a file is still discoverable.

### 6.4 Fusion

Candidates are merged by chunk ID using reciprocal rank fusion:

```text
score = keywordWeight / (60 + keywordRank + 1)
      + semanticWeight / (60 + semanticRank + 1)
```

- `semanticWeight = 1.0`.
- `keywordWeight = 1.25`, or `1.45` in exact-phrase mode.
- An exact filename match adds `0.045` (or creates a baseline hit).
- A verbatim occurrence of the full query in name + text adds `0.035`.
- Results are then reduced to the best-scoring passage per file, with a `matchCount` for “N passages matched” UI.

The output is `SearchOutcome` with hits, a `semanticUsed` flag, warnings, and timing. A semantic failure (model down, missing model) degrades to keyword-only results rather than failing the request.

### 6.5 Filters

`SearchFilters` carries kinds, folder IDs, and a modified-date range. The same filter clause is applied to keyword, semantic, filename, and empty-query listing queries. The search UI exposes type chips, folder selection, and relative date presets, and translates them into this value type.

---

## 7. Grounded chat (RAG)

`RAGService` is an actor with a `SearchService` and an `IndexStore`.

1. **Query construction.** If the new question is under 120 characters and there is prior user history, the previous user message is prepended to the retrieval query so follow-ups like “what about the second one?” still retrieve relevant passages.
2. **Retrieval.** Top 8 hits (10 for Compare). No filters are applied; chat searches the whole enabled index.
3. **Context assembly.** Each source becomes `[n] file name — page/line/time` followed by the full passage. Blocks are added until a 9,000-character cap, always allowing the first block.
4. **Prompt.** A system prompt restricts the model to the sources, requires bracketed citations, forbids invented facts/citations, treats source text as data rather than instructions, and applies the mode instruction (`answer`, `summarize`, `extract`, `compare`).
5. **History.** Last six messages (user/assistant, non-error) are included with 1,200-character truncation.
6. **Generation.** `LocalInferenceClient.streamChat` returns an `AsyncThrowingStream<String>`; Ollama streams NDJSON lines, OpenAI-compatible servers stream SSE.
7. **Persistence.** The completed or stopped answer is stored in `messages` with its citations JSON. Citations are first-class `Citation` values with file ID, name, path, kind, locator, quote, and relevance.

`AppModel.sendMessage` owns exactly one chat `Task`. `isStreaming` is set before the task starts, streaming text is displayed inline, and cancellation paths persist a partial answer marked “(Stopped.)” or a plain “Stopped.” message. `CancellationError` and `URLError.cancelled` are treated the same. This avoids orphan tasks and duplicated assistant messages.

If retrieval returns nothing, Lumina does not call the model at all. It saves a deterministic “I couldn't find a relevant passage…” response; this keeps the model from hallucinating around an empty context.

---

## 8. Local inference client

`LocalInferenceClient` supports two protocol shapes:

| Runtime | Health | Models | Chat | Embeddings | Pull |
| --- | --- | --- | --- | --- | --- |
| Ollama | `GET /api/version` | `GET /api/tags` | `POST /api/chat` (NDJSON stream) | `POST /api/embed` | `POST /api/pull` |
| OpenAI-compatible | `GET /v1/models` | `GET /v1/models` | `POST /v1/chat/completions` (SSE) | `POST /v1/embeddings` | not supported |

Security properties:

- Init throws unless the URL has a host that is exactly `localhost`, `127.0.0.1`, or `::1`, or ends in `.localhost`.
- `URLSessionConfiguration.ephemeral` with no URL cache and no connectivity waiting.
- Request/response timeouts are long enough for local generation (600 s request, 3,600 s resource).
- Model names are canonicalized for comparison (`:latest` handling) so “installed” checks are not defeated by tag differences.
- Image captions downscale to JPEG before sending to the local multimodal model.

There is no hidden fallback to a cloud endpoint. If the local server is unreachable, the error surfaces to the user.

---

## 9. UI architecture

### Routes and screens

`RootView` is a `NavigationSplitView` with `SidebarView` and a switch over `AppRoute`:

- **Home** — setup status, first-run guide, stats, pins, recent files.
- **Search** — query field, filters, result list, preview pane.
- **Chat** — conversation list/sidebar, mode picker, streamed messages, citations.
- **Library** — grid/list modes, kind filters, folder filter, file detail.
- **Timeline** — merged notes, conversations, pins, and indexing events.
- **Settings** — five tabs, also hosted in the native Settings window.

`QuickSearchView` is a separate compact view embedded in the `NSPanel`; it shares the search service through `AppModel`.

### Design system

`Theme.swift` defines a restrained palette built on system colors (`windowBackgroundColor`, `controlBackgroundColor`, `labelColor`, etc.) plus three fixed brand values used by the mark and icon: ink, ivory, and a warm beam. `Components.swift` provides page headers, cards, tags, status pills, inline notices, metadata rows, progress bars, empty states, and the scroll container used by Settings. `LuminaMark.swift` draws the mark with `Canvas`, so it stays crisp in the sidebar, empty states, and about panel without asset variants.

One accent color is selected in Settings and applied via `.tint` and `.accentColor` (both are needed because explicit `Color.accentColor` usages do not follow `.tint`); the rest of the UI stays neutral. There are no decorative gradients, glows, or animated blobs.

### Error handling

`AppModel.present(_:title:)` converts errors into `UserFacingError` and shows a dismissible banner. Long-running failures (setup, indexing, pulls, chat) also surface inline notices in context. User-facing messages explain the next action rather than dumping a raw `NSError`.

---

## 10. Lifecycle

1. `main` runs `LuminaApp`; `@NSApplicationDelegateAdaptor` installs `AppDelegate`.
2. `AppDelegate.applicationDidFinishLaunching` creates `AppEnvironment.shared`, which creates `AppModel` and its services. If the database cannot open, a `StartupFailureView` is shown instead.
3. The main window is built with `RootView`, the model, settings, tint, and preferred color scheme.
4. `AppModel.bootstrap` refreshes setup, folders, stats, library, timeline, and conversations. It starts an automatic scan only when auto-indexing is enabled, at least one folder exists, and the runtime is reachable with both configured models installed (`isFullyConfigured`). The polling loop repeats that check on its interval.
5. Closing the window orders it out; the app and its state remain alive. Reopening from the dock, menu, or Quick Search reuses the same window.
6. Quitting ends the process and any running tasks. The database uses WAL mode, so an interrupted session is recovered on the next launch. There is no background agent.

---

## 11. Testing strategy

`Tests/LuminaTests/LuminaTests.swift` uses Swift Testing and a temporary SQLite database per suite instance. Coverage focuses on logic that is easy to get subtly wrong:

- Vector normalization, dot product, encode/decode round trip, bounded top-K.
- Character/line/page chunking, HTML text extraction.
- Memory-based model recommendations and pull commands.
- Loopback acceptance/rejection and remote-endpoint rejection.
- FTS term extraction and query construction, including quotes and empty queries.
- End-to-end store behavior: file save, keyword/semantic/filename search, filters, pins, notes, conversations, timeline, stats, reset, erase.
- The plain-text indexing pipeline and scanner exclusions without any model.
- Ollama NDJSON and OpenAI-compatible SSE streaming parsers, using a stubbed `URLProtocol`.

An opt-in suite (`LUMINA_LIVE_OLLAMA=1`) checks health, model discovery, a real embedding/indexing round-trip, and a grounded RAG answer streamed from a local chat model against a local Ollama instance. It is skipped by default so the suite stays deterministic.

The Swift Testing choice keeps the suite buildable with Command Line Tools. `scripts/test.sh` supplies the framework search path only when needed.

Not covered by automated tests: SwiftUI layout, live chat generation against a running model, Vision/Speech extraction, and filesystem permissions. The streaming parsers are covered with stubs; a full live chat run needs a model that fits the machine's memory.

---

## 12. Trade-offs and extension points

| Decision | Trade-off | Where to change |
| --- | --- | --- |
| Brute-force vector search | Linear scan; fine for personal libraries, not millions of chunks | `IndexStore.semanticSearch` / `BoundedTopK` |
| Per-file best passage only | Clean result list; hides other matching passages | `SearchService` file reduction |
| Unsandboxed direct distribution | Simpler folder access; not Mac App Store eligible | `Lumina.entitlements`, `FileScanner` |
| App-owned SQLite schema | No migrations framework yet | `IndexStore.createSchema`, `PRAGMA user_version` |
| Polling auto-index | Predictable and cheap; not instant on file changes | `AppModel` auto-scan loop, `FileScanner` |
| Ollama-native + OpenAI-compatible | Covers common local runtimes without an SDK | `LocalInferenceClient` |
| On-device Speech only | Privacy-preserving; locale/model availability varies | `TranscriptionService` |
| Keyword fallback | Search works before models; vectors fill in later | `IndexingEngine`, `saveFile` |

### Adding a new runtime

1. Add a case to `RuntimeKind`.
2. Implement health, list, chat, embed, and optional pull in `LocalInferenceClient`.
3. Update `RuntimeDiscovery` and the setup/manual command UI.
4. Keep the loopback check in `init`; do not add a bypass for “trusted” LAN hosts.

### Adding a new extracted type

1. Add the extension to `SupportedFileTypes` and a `ContentKind` if the UI needs a new category.
2. Implement extraction in `ContentExtractor`, returning `ChunkDraft`s with locators.
3. Add chunking behavior and a focused test.
4. Add a thumbnail path if previews matter; cleanup is automatic on reset.

### Adding a schema field

1. Add the column in `createSchema` and bump `PRAGMA user_version`.
2. Add a migration step for existing databases (currently absent; this is the main schema gap).
3. Update `StoreMapping.fileColumns` and `StoreMapping.file(from:)` together; the offsets are positional and must stay in sync.
4. Update writes and tests.
