# Screenshot placeholders

The README expects these captures at 1600 × 1000 (or a 16:10 ratio), light appearance unless a screen is intentionally dark:

| File | Screen |
| --- | --- |
| `home.png` | Home with setup status, stats, pins, and recent files |
| `search.png` | Hybrid search results with filters and the preview pane |
| `chat.png` | A citation-backed answer next to its sources |
| `library.png` | Library grid with thumbnails and file details |
| `timeline.png` | Notes, conversations, pins, and indexed files |
| `settings.png` | Settings → Models or Privacy |

Capture suggestions:

```bash
# With Lumina frontmost, after positioning the window:
screencapture -x -o docs/screenshots/home.png
```

Do not include personal file names, paths, conversations, or model endpoints in published screenshots. Use a demo folder with synthetic documents.
