# SouthsideMusic Core Backend

This package is the first step toward a UI-independent application core.

## What exists now

- `CoreContext` — UI-free state container for core services.
- `ThreadTaskScheduler` — fallback scheduler for headless runs.
- `CoreBackendService` — initializes config, NetEase API, favorites, audio
  player, lyric parsers, playback manager, LLM and WebSocket bridge without
  creating any view/page widget.
- `standalone.py` — a headless `QCoreApplication` entrypoint that serves a
  simple newline-delimited JSON protocol over stdin/stdout.

## What is still coupled to Qt

The core modules themselves still use PySide6 `QObject`/`QTimer`/`Signal`
(`audio_player.py`, `playing_manager.py`, `ws_server.py`, `downloader.py`,
`event_bus.py`, etc.). This package currently removes the *UI widgets/views*
dependency, not the Qt runtime dependency. Removing Qt from those core modules
is the next major step before a non-Qt UI backend can be used.
