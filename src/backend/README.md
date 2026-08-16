# SouthsideMusic Core Backend

This package is the first step toward a UI-independent application core.

## What exists now

- `CoreContext` — UI-free state container for core services.
- `ThreadTaskScheduler` — fallback scheduler for headless runs.
- `CoreBackendService` — initializes config, NetEase API, favorites, audio
  player, lyric parsers, playback manager, LLM and WebSocket bridge without
  creating any view/page widget.
- `Signal`, `QTimer`, `QPropertyAnimation`, `Property`, `MessageBox` — minimal
  Qt-free shims so core modules can run without PySide6.
- `standalone.py` — a headless entrypoint that has no dependency on PySide6
  (uses a plain event loop / threading) and can serve a newline-delimited JSON
  protocol over stdin/stdout.
- `scripts/check_backend_no_qt.py` — verifies the backend core import chain
  works without PySide6 installed.

## Quick start

```bash
python scripts/check_backend_no_qt.py

printf '{"id":1,"method":"ping"}\n{"id":2,"method":"shutdown"}\n' |
  python src/backend/standalone.py
```

## Status

Every module under `src/core/` can now be imported without PySide6 installed.
`scripts/check_backend_no_qt.py` imports the full core module list and verifies
this.

- Core audio/playback/websocket/download modules use the small Qt-free shims in
  this package when PySide6 is absent, and automatically use real PySide6 when
  it is available (so the desktop UI keeps native Qt behavior).
- The desktop UI still uses real PySide6 widgets; the backend can run headless
  with no Qt at all.

## Remaining Qt when calling UI-only helpers

Some core modules (dialogs, LLM tool UI, lyric-video Qt renderer, icon helper)
are import-safe without Qt, but their UI-facing functions still require PySide6
when actually called. Those functions are not part of the standalone backend
service and will be rewritten/moved when the UI is replaced.
