"""Standalone core backend entrypoint.

Run from the repository root:

    uv run python -m backend.standalone

or directly:

    python src/backend/standalone.py

This starts the UI-independent core (config, NetEase API, audio player,
playback manager, WebSocket bridge) with no PySide6/Qt dependency and serves a
newline-delimited JSON protocol on stdin/stdout. It is the first step toward
letting a future cross-platform UI talk to the same core as a separate process.
"""

from __future__ import annotations

import os
import sys
import threading
from typing import Any

_SRC_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if _SRC_DIR not in sys.path:
    sys.path.insert(0, _SRC_DIR)

from backend.core_context import CoreContext
from backend.protocol import encode_error, encode_response, parse_request
from backend.service import CoreBackendService
from services.events import PLAY_STATE_CHANGED, PLAYLAST, PLAYNEXT, event_bus


def _handle_request(
    service: CoreBackendService,
    request: dict[str, Any],
) -> str:
    request_id = request.get('id')
    method = request.get('method')
    params = request.get('params') or {}
    ctx = service.context

    if method == 'ping':
        return encode_response(request_id, {'pong': True})

    if method == 'get_status':
        return encode_response(
            request_id,
            {
                'initialized': ctx.player is not None,
                'playing': bool(ctx.player and ctx.player.isPlaying()),
                'playlist_size': (
                    len(ctx.playing_manager.playlist)
                    if ctx.playing_manager is not None
                    else 0
                ),
                'ws_running': bool(ctx.ws_server and ctx.ws_server.is_alive()),
            },
        )

    if method == 'get_config':
        cfg = ctx.config
        return encode_response(
            request_id,
            {
                'language': cfg.language if cfg else None,
                'volume': cfg.volume if cfg else None,
                'play_method': cfg.play_method if cfg else None,
            },
        )

    if method == 'get_playlist':
        manager = ctx.playing_manager
        if manager is None:
            return encode_response(request_id, {'current_index': -1, 'items': []})
        items = [
            {
                'index': index,
                'id': str(getattr(song, 'id', '')),
                'name': str(getattr(song, 'name', '')),
            }
            for index, song in enumerate(manager.playlist)
        ]
        return encode_response(
            request_id,
            {'current_index': manager.current_index, 'items': items},
        )

    if method == 'list_favorites':
        return encode_response(
            request_id,
            {
                'folders': [
                    {
                        'name': folder.folder_name,
                        'count': len(folder.songs),
                    }
                    for folder in ctx.favs
                ]
            },
        )

    if method == 'play_control':
        command = params.get('command')
        player = ctx.player
        manager = ctx.playing_manager
        if player is None or manager is None:
            return encode_error(request_id, 'backend not fully initialized')
        if command == 'toggle':
            if player.isPlaying():
                player.pause()
            else:
                player.resume()
            event_bus.emit(PLAY_STATE_CHANGED, player.isPlaying())
        elif command == 'next':
            event_bus.emit(PLAYNEXT)
        elif command == 'previous':
            event_bus.emit(PLAYLAST)
        elif command == 'seek':
            try:
                position = float(params.get('position', 0.0))
            except (TypeError, ValueError):
                return encode_error(request_id, 'invalid position')
            player.setPosition(max(0.0, position))
        else:
            return encode_error(request_id, f'unknown play_control: {command}')
        return encode_response(request_id, {'ok': True})

    if method == 'shutdown':
        service.shutdown()
        return encode_response(request_id, {'shutdown': True})

    return encode_error(request_id, f'unknown method: {method}', code=404)


def main() -> int:
    shutdown_event = threading.Event()

    service = CoreBackendService(context=CoreContext())
    service.initialize(
        app=None,
        progress=lambda message: print(f'[backend] {message}', file=sys.stderr),
    )
    service.start()

    def _stdin_loop() -> None:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            request = parse_request(line)
            if request is None:
                print(encode_error(None, 'invalid JSON request'), flush=True)
                continue
            response = _handle_request(service, request)
            print(response, flush=True)
            if request.get('method') == 'shutdown':
                shutdown_event.set()
                break

    thread = threading.Thread(target=_stdin_loop, name='backend-stdin', daemon=True)
    thread.start()

    shutdown_event.wait()
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
