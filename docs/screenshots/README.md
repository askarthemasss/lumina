# Screenshots

These six PNGs are the images used in the project README. Each is 3200 × 2000: a 1600 × 1000 window rendered at 2× in light appearance.

| File | Screen |
| --- | --- |
| `home.png` | Home with setup status, stats, pins, and recent files |
| `search.png` | Hybrid search results with filters and the preview pane |
| `chat.png` | Citation-backed answers with their source cards |
| `library.png` | Library grid with generated thumbnails |
| `timeline.png` | Notes, conversations, pins, and indexed files |
| `settings.png` | Settings → Models |

## How they are made

`Tests/LuminaTests/SnapshotTests.swift` renders the shipping SwiftUI hierarchy — the real `RootView` and feature screens — into a real `NSWindow` placed far offscreen. It does not use `screencapture`, so it needs no Screen Recording permission and works in a terminal or CI.

The fixture builds a 12-file synthetic demo library in a temporary SQLite database, including generated thumbnails, notes, pins, and conversations. When a loopback Ollama `embeddinggemma` model is available, the renderer also embeds the demo passages so the semantic rows are real; otherwise it falls back to keyword results.

Regenerate the images with:

```bash
LUMINA_RENDER_SNAPSHOTS=1 ./scripts/test.sh
```

The test is skipped during normal runs so the deterministic suite stays fast.

## Content and privacy

Every path, document, note, and conversation in the images is invented. Paths use `/Users/demo/Documents/Lumina Demo`; no file from the developer's Mac is read into the render. The images are documentation renders, not captures of a live library.

If you replace them with live captures of your own library, publish only after confirming that every file name, path, note, conversation, and endpoint is safe to share. Position the window at 1600 × 1000 points and capture at 2× for a consistent size.
