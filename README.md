# Lumina

**Illuminate your local knowledge.**

[![CI](https://github.com/askarthemasss/lumina/actions/workflows/ci.yml/badge.svg)](https://github.com/askarthemasss/lumina/actions/workflows/ci.yml)

Lumina is a native macOS workspace for the files already on your Mac. It indexes folders you choose, searches them by keyword *and* meaning, answers questions from the retrieved passages with citations, and keeps notes and pins beside the sources.

There is no account, no telemetry, no cloud sync, and no upload. Chat and embedding requests only go to a model server running on your own machine.

![Lumina app icon](AppResources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png)

---

## Screenshots

Real captures belong in `docs/screenshots/`. The layout is designed for a 1600 × 1000 window in both appearances.

> **Placeholder — Home.** `docs/screenshots/home.png`  
> Onboarding, local model status, recent files, and the setup guide.

> **Placeholder — Search.** `docs/screenshots/search.png`  
> Hybrid search with type, folder, and date filters, highlighted snippets, and a preview pane.

> **Placeholder — Ask Lumina.** `docs/screenshots/chat.png`  
> A streamed, citation-backed answer beside its sources.

> **Placeholder — Library.** `docs/screenshots/library.png`  
> Grid and list views with thumbnails, pins, and file details.

> **Placeholder — Timeline.** `docs/screenshots/timeline.png`  
> Notes, conversations, pins, and recently indexed files in one chronological view.

> **Placeholder — Settings.** `docs/screenshots/settings.png`  
> Runtime, models, indexing rules, privacy controls, and local data.

---

## Why Lumina

Most "AI knowledge base" tools ask you to upload your work to someone else's computer. Lumina starts from a different premise:

- **Local by default, not by toggle.** The inference client rejects any endpoint that is not `localhost`, a `*.localhost` subdomain, `127.0.0.1`, or `::1`. Remote model servers cannot be configured by accident.
- **Your files stay where they are.** Lumina reads the folders you add. It never moves, renames, or edits the originals.
- **Useful before the models arrive.** Keyword indexing, browsing, previews, pins, and notes work without downloading a chat or embedding model. Semantic search and answers switch on when the local models are ready.
- **One honest database.** Passages, vectors, notes, conversations, and file metadata live in one SQLite file you can inspect, back up, or delete.
- **A native Mac app.** SwiftUI and AppKit, system colors, one accent color, real menus, keyboard navigation, and no decorative gradients.

## Features

### Search that handles both kinds of knowing

- SQLite **FTS5** keyword search with snippets and exact-phrase mode.
- **Local embedding search** over normalized vectors, using cosine similarity.
- **Reciprocal rank fusion** merges keyword and semantic results instead of letting one score scale dominate.
- Filters for content type, folder, and modification date.
- File-name matches and verbatim query bonuses for invoice numbers, error codes, and proper names.
- A preview pane that shows the extracted passages behind each result, with page and line locators where available.
- Global Quick Search (**⇧⌘Space**) and an in-app palette (**⌘K**).

### Grounded answers with citations

- Ask Lumina retrieves a small set of passages and sends only those passages to the local chat model.
- Every answer is prompted to cite its sources as `[1]`, `[2]`, and so on; citations are stored with the message and remain inspectable later.
- Streaming responses with Stop, retry-safe persistence, and a clear "I couldn't find this in your index" path.
- Modes for **Answer**, **Summarize**, **Extract** (Markdown tables/JSON), and **Compare**.
- Six recent messages of conversation are included for follow-up questions; old answers are never used as sources.

### Library and previews

- Grid and list views across text, code, PDFs, documents, spreadsheets, presentations, images, audio, and video.
- Generated thumbnails for images, video frames, and the first page of PDFs.
- Pins, per-file notes, extracted-text preview, metadata, and open-in-default-app.
- Timeline of indexing, notes, conversations, and pins.
- Manual indexing and cancellation, reindex-all, and optional background scans.

### Onboarding that explains the moving parts

- Detects an installed Ollama app or binary and checks whether the local server is reachable.
- Recommends a Gemma 4 model based on this Mac's unified memory, plus `embeddinggemma`.
- Copyable install and `ollama pull` commands, one-click downloads with progress and errors, and a test button that verifies a real embedding round-trip.
- A plain-language "Why local?" explanation.
- A working keyword-only path for people who want to try the app before downloading models.

### File understanding

| Category | Extraction |
| --- | --- |
| Text, Markdown, JSON, YAML, config | UTF-8/UTF-16 text with encoding fallbacks |
| Source code | Line-aware chunking that preserves line numbers for results |
| PDF | PDFKit text; Vision OCR for scanned pages; first-page thumbnail |
| Images | Vision OCR, image classification labels, and optional local chat-model captions |
| DOC/DOCX/RTF/ODT | Native AppKit readers; DOCX also has an OOXML text fallback |
| XLSX/ODS/CSV/TSV | XLSX shared strings and worksheet cells; ODS document text; CSV/TSV rows |
| PPTX/ODP | PPTX per-slide text with slide numbers; ODP document text |
| Audio | AVFoundation metadata; optional Apple on-device Speech transcription |
| Video | Metadata, sampled frames, frame OCR and labels; optional on-device transcription |

All OCR, classification, and transcription run through Apple frameworks on this Mac. Image captioning, when enabled, sends a downscaled image to the **local** chat model.

## Requirements

- macOS 14 Sonoma or later.
- Apple silicon recommended. Intel Macs with macOS 14+ can run the app, but local model performance will be limited.
- 8 GB unified memory minimum for the recommended small model; 16 GB or more is a better experience.
- [Ollama](https://ollama.com) **or** an OpenAI-compatible local server (for example MLX) for semantic search and chat.
- To build from source: Xcode 16+ with Swift 6, or Swift 6 Command Line Tools for the SwiftPM path.

Lumina deliberately does not bundle models. They are large, they update independently, and they belong to the runtime that manages them.

## Install and build

### Xcode (canonical project)

```bash
git clone https://github.com/askarthemasss/lumina.git
cd lumina
brew install xcodegen       # only needed if you change project.yml
xcodegen generate
open Lumina.xcodeproj
```

In Xcode:

1. Select the **Lumina** target → **Signing & Capabilities**.
2. Choose your development team. The app is intentionally unsandboxed (see [Privacy](#privacy-and-data)).
3. Run with **⌘R**.

`project.yml` is the source of truth for the Xcode project. Regenerate `Lumina.xcodeproj` after changing target settings or adding resource folders.

### Swift Package Manager (quick local build)

```bash
swift build
CONFIGURATION=release ./scripts/package_app.sh
open dist/Lumina.app
```

The packaging script assembles a minimal `.app`, compiles the generated `.icns`, applies the entitlements, and ad-hoc signs it. For distribution, set `SIGN_IDENTITY` to a Developer ID Application identity, build a DMG with `./scripts/make_dmg.sh`, and notarize it. The tag-driven GitHub release workflow and the full credential setup are documented in [`docs/RELEASING.md`](docs/RELEASING.md).

### Tests

```bash
./scripts/test.sh
```

The suite uses **Swift Testing** (27 deterministic tests) and covers vector math, chunking, HTML extraction, model recommendations, loopback enforcement, FTS query construction, keyword/semantic/filename search and filtering, notes/pins/conversations, reset/erase, the plain-text indexing pipeline, and Ollama/OpenAI-compatible streaming parsers. With a full Xcode installation you can also press **⌘U**; the `Lumina` scheme includes the `LuminaTests` target, and CI runs both SwiftPM and `xcodebuild test`.

To check the real onboarding path against Ollama on this Mac:

```bash
LUMINA_LIVE_OLLAMA=1 ./scripts/test.sh
```

That adds two opt-in tests: health, model discovery, and the runtime snapshot; plus a real embedding/indexing round-trip that verifies semantic search against your local `embeddinggemma` installation. They are skipped by default so the suite stays deterministic.

The wrapper exists because a Command Line Tools-only installation keeps `Testing.framework` outside SwiftPM's default framework search path. It adds that path only when it is needed.

## Model setup

Lumina speaks to Ollama's native API at `http://127.0.0.1:11434` by default. Start Ollama before opening the app:

```bash
ollama serve
```

Then pull one embedding model and one chat model:

```bash
ollama pull embeddinggemma
ollama pull gemma4:e2b     # < 16 GB
# ollama pull gemma4:12b   # 16–31 GB
# ollama pull gemma4:26b   # 32–63 GB
# ollama pull gemma4:31b   # 64 GB+
```

| Unified memory | Recommended chat model | Approx. download |
| --- | --- | --- |
| Under 16 GB | `gemma4:e2b` | ~4.6 GB |
| 16–31 GB | `gemma4:12b` | ~8 GB |
| 32–63 GB | `gemma4:26b` | ~17 GB |
| 64 GB+ | `gemma4:31b` | ~20 GB |

The embedding model is `embeddinggemma` at every tier. Lumina also has a **Use Recommended** and **Download Recommended** flow in Settings → Models, with progress and cancel support. If you already have models installed, choose them from the installed-model menu instead of downloading more.

### MLX or another OpenAI-compatible server

Set **Settings → Models → Runtime** to *MLX / OpenAI-compatible* and point the endpoint at your loopback server, for example `http://127.0.0.1:8080`. The server must expose:

- `GET /v1/models`
- `POST /v1/chat/completions` (streaming)
- `POST /v1/embeddings`

Enter the exact model identifiers your server reports. Lumina never accepts a non-loopback host, even for a "trusted" LAN machine.

### Models are optional for the first look

Keyword indexing works as soon as you add a folder. If the embedding model is missing, Lumina records a warning and keeps the extracted text searchable. Install the model later and run **Index → Reindex Everything** to fill in vectors. Changing the embedding model always requires a reindex; the app detects old vectors and warns you.

## How it works

```text
Folders ──► FileScanner ──► ContentExtractor ──► TextChunker ──► embeddings
                                                                  │
                                                                  ▼
                                             SQLite: files + chunks + FTS5 + vectors
                                                                  │
                     ┌────────────────────────────────────────────┴─────────────┐
                     ▼                                                          ▼
            FTS5 keyword search                                    local cosine similarity
                     └──────────────────────► RRF ◄─────────────────────────────┘
                                               │
                                               ▼
                                     passages + citations ──► local chat model
```

- **Storage:** one SQLite database with FTS5, Float32 embedding BLOBs, and metadata. No external database server.
- **Retrieval:** keyword and semantic candidates are fused with reciprocal rank fusion (`k = 60`), then deduplicated to the best passage per file.
- **Generation:** the top 8 passages (10 in Compare mode) are placed in a 9,000-character context budget with a strict "answer only from these sources" prompt.
- **Concurrency:** the UI model is `@MainActor`; the database, indexer, search, and RAG services are actors or `Sendable` values. Cancellation is cooperative end to end.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full component and schema reference.

## Privacy and data

Lumina was built so that the privacy claim is a property of the code, not a promise in a settings screen.

- **Loopback only.** `LocalInferenceClient` validates the host before creating a request. `localhost`, `*.localhost` subdomains, `127.0.0.1`, and `::1` are accepted; everything else throws `InferenceError.remoteEndpoint`.
- **No telemetry or accounts.** There is no analytics SDK, crash uploader, sign-in, sync, or remote logging.
- **Only chosen folders.** The scanner starts from folders you explicitly add, skips hidden files and package internals, and can skip credentials, keys, certificates, password stores, and databases.
- **On-device media processing.** Vision OCR/classification and Speech transcription use Apple frameworks. Transcription is optional and disabled by default.
- **Local data folder:**

  ```text
  ~/Library/Application Support/Lumina/
  ├── lumina.sqlite
  └── thumbnails/
  ```

  Preferences live in `UserDefaults` under `lumina.settings.v1`. **Settings → Privacy** can open the folder, reset the index (keeps folders and preferences), or erase everything.

### Why isn't Lumina sandboxed?

Lumina is a direct-distribution app that indexes folders anywhere the user points it, including external drives and development directories. The App Sandbox would add security-scoped bookmark plumbing for every file operation and still constrain tools and temporary files in ways that fight the indexing pipeline. Instead:

- Release builds enable the hardened runtime.
- It requests only the folder access the user grants through the standard open panel.
- It makes no network connections except to the configured loopback inference server.
- It is not distributed through the Mac App Store.

The trade-off is explicit: a sandboxed build would be safer by default for untrusted code, while an unsandboxed build is simpler and more predictable for a local knowledge tool. If you need the sandbox, the scanner and bookmark layer are the places to adapt.

### Limitations worth knowing

- **The SQLite database is not encrypted by Lumina.** FileVault protects the disk at rest. Anyone with access to your unlocked Mac and your home folder can read the index.
- **Backups include the index.** If you back up `~/Library/Application Support`, conversations and extracted text go with it.
- **No continuous screen capture.** Lumina indexes screenshots you already have; it does not record your screen.
- **No automatic media clustering or folder reorganization.** Media organization is browsing, filtering, thumbnails, pins, and notes.
- **No cloud models, sharing, or collaboration.** These are deliberate v1 non-goals.
- **MLX support is an OpenAI-compatible integration, not a bundled runtime.** You run and update the server yourself.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| **⇧⌘Space** | Open Quick Search from any app (configurable) |
| **⌘K** | Quick Search inside Lumina |
| **⌘1 … ⌘6** | Go to Home, Search, Ask, Library, Timeline, Settings |
| **⌘N** | New conversation |
| **⇧⌘O** | Add a folder |
| **⌘R** | Index now |
| **⇧⌘R** | Reindex everything |
| **⌘,** | Open Settings |
| **Return** | Run search / send message |
| **Esc** | Close Quick Search or cancel the current panel |

The global shortcut is registered with Carbon and does not require Accessibility permission. If macOS or another app already owns the combination, Lumina reports the registration failure and lets you pick another preset in Settings.

## Configuration

Settings are grouped into five tabs:

- **General:** system/light/dark appearance, six restrained accent colors, global shortcut, automatic indexing interval.
- **Models:** runtime, loopback endpoint, embedding/chat model, installed-model pickers, one-click pulls, and pipeline verification.
- **Indexing:** OCR, local image captions, on-device transcription, code indexing, sensitive-file skipping, maximum file size, and exclusion patterns.
- **Privacy:** what is enforced, where data lives, reset/erase actions, and the "Why Local?" explanation.
- **About:** version, frameworks, current scope, and a copyable diagnostics report (no file contents, paths, or conversations).

Exclusion patterns are one per line and accept names, relative paths, and `*`/`?` wildcards, for example:

```text
*.psd
Archive/**
node_modules
Final Cut Libraries
```

Indexing skips `.git`, `node_modules`, build output, package internals, virtual environments, caches, Photos libraries, and Final Cut bundles by default.

## Troubleshooting

**Lumina says Ollama is offline.**  
Run `ollama serve` in a terminal, or open the Ollama app and wait for its menu-bar icon. Check that `http://127.0.0.1:11434` responds:

```bash
curl http://127.0.0.1:11434/api/version
```

**"The embedding model isn't installed."**  
Run `ollama pull embeddinggemma`. If you use a different embedding model, enter its exact name in Settings → Models, then reindex. The app keeps keyword search working in the meantime.

**Search finds files but answers say no sources were found.**  
The passages may not exist yet, or the model is not installed. Check Library stats for passages and vectors, run **Index → Reindex Everything**, and confirm both models are green in Settings → Models.

**Semantic results disappear after changing models.**  
Vectors are tied to the embedding model that produced them. Lumina warns about the mismatch; reindex to rebuild them.

**A folder shows no files.**  
Confirm the folder is enabled and not covered by an exclusion. Hidden files and unsupported extensions are skipped by design. Large files above the configured limit are skipped.

**The global shortcut does nothing.**  
Open Settings → General and choose another preset. Another app may own the combination; macOS does not report which one.

**Transcription fails.**  
Enable transcription in Settings → Indexing, grant Speech Recognition permission when macOS asks, and confirm the current locale supports on-device recognition. Audio never leaves the Mac.

**The app is blocked by Gatekeeper after a local ad-hoc build.**  
Right-click the app and choose **Open**, or build with your own signing identity. Ad-hoc signatures are for local development only.

**Tests fail with `no such module 'Testing'`.**  
Use `./scripts/test.sh` on a Command Line Tools-only machine, or run the suite from Xcode. Both paths use the same source file.

## Development

### Project layout

```text
Sources/Lumina/
├── App/          App lifecycle, routing, menus, settings, global hot key
├── Design/       Palette, type ramp, reusable components, drawn mark
├── Features/     Home, Search, Chat, Library, Timeline, Settings, Quick Search
├── Models/       Domain types, content kinds, citations, vector math
└── Services/     SQLite, index store, inference, search, RAG, extraction, indexing
AppResources/     Info.plist, entitlements, privacy manifest, asset catalog
Tests/            Swift Testing suite
docs/             Architecture, release process, screenshot placeholders
scripts/          Icon generation, test wrapper, packaging, DMG, notarization
project.yml       XcodeGen source of truth
```

### Useful commands

```bash
swift build                        # type-check and build the executable
./scripts/test.sh                  # run Swift Testing
swift scripts/GenerateAppIcon.swift # regenerate icon PNGs + Contents.json
xcodegen generate                  # regenerate Lumina.xcodeproj
CONFIGURATION=debug ./scripts/package_app.sh
./scripts/make_dmg.sh              # package dist/Lumina-<version>.dmg
```

### Adding a file type

1. Add the extension to `SupportedFileTypes` in `Services/Indexing/FileScanner.swift`.
2. Add or extend the extractor in `Services/Indexing/ContentExtractor.swift`.
3. Return `ChunkDraft` values with a `ContentLocator` (page, line, or time range) so results can jump to the right place.
4. Add a test for extraction or chunking behavior.

### Code style

- Swift 6 language mode, strict concurrency, actors for shared mutable state.
- System colors and native controls first; one accent color; no decorative gradients.
- User-facing errors explain what happened and what to try next.
- Comments describe *why*, not *what*.

## Scope and roadmap

Lumina v1 is intentionally focused. The following are **not** implemented and are not promised:

- Cloud sync, sharing, collaboration, or accounts.
- Windows/Linux clients.
- Bundled large models or a model download service of our own.
- Continuous screen recording or background screenshot capture.
- Automatic photo clustering, duplicate detection, or media folder reorganization.
- Aggressive filesystem monitoring (the app polls changed files on an interval instead).

Natural next steps, in rough order: embedding-model change detection with incremental re-embedding, duplicate/near-duplicate detection using Vision feature prints, saved searches, export of answers with citations, and a signed/notarized release pipeline.

## License

[MIT](LICENSE) © 2026 Lumina.

Lumina is an independent project. Gemma, Ollama, MLX, and Apple frameworks are governed by their own licenses and terms.
