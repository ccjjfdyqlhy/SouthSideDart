"""Standalone core backend entrypoint.

Run from the repository root:

    uv run python -m backend.standalone

or directly:

    python src/backend/standalone.py

This starts the UI-independent core (config, NetEase API, audio player,
playback manager, WebSocket bridge) inside a ``QCoreApplication`` and serves a
newline-delimited JSON protocol on stdin/stdout. It is the first step toward
letting a future cross-platform UI talk to the same core as a separate process.
"""

from __future__ import annotations

import json
import os
import sys
import threading
from typing import Any

_SRC_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if _SRC_DIR not in sys.path:
    sys.path.insert(0, _SRC_DIR)

from PySide6.QtCore import QCoreApplication

from backend.core_context import CoreContext
from backend.protocol import encode_error, encode_response, parse_request
from backend.service import CoreBackendService


def _handle_request(
    service: CoreBackendService,
    request: dict[str, Any],
) -> str:
    request_id = request.get('id')
    method = request.get('method')
    params = request.get('params') or {}

    if method == 'ping':
        return encode_response(request_id, {'pong': True})

    if method == 'get_status':
        ctx = service.context
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

    if method == 'shutdown':
        service.shutdown()
        return encode_response(request_id, {'shutdown': True})

    return encode_error(request_id, f'unknown method: {method}', code=404)


def main() -> int:
    app = QCoreApplication(sys.argv)

    service = CoreBackendService(context=CoreContext())
    service.initialize(
        app=app,
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
                app.quit()
                break

    thread = threading.Thread(target=_stdin_loop, name='backend-stdin', daemon=True)
    thread.start()

    return app.exec()


if __name__ == '__main__':
    raise SystemExit(main())
