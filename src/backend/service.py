"""UI-independent core backend service.

This service owns the initialization and lifecycle of the non-UI application
core. The current desktop UI can use it as the source of truth for ``AppContext``,
and a future standalone backend process can call the same code without importing
any PySide6 widget/view module.
"""

from __future__ import annotations

import logging
import os
from typing import Any, Callable

from .core_context import CoreContext
from .scheduler import TaskScheduler

_logger = logging.getLogger(__name__)


class CoreBackendService:
    """Initializes and owns a UI-independent ``CoreContext``."""

    def __init__(
        self,
        task_scheduler: TaskScheduler | None = None,
        context: CoreContext | None = None,
    ) -> None:
        self.context = context if context is not None else CoreContext(
            task_scheduler=task_scheduler
        )

    def initialize(
        self,
        app: Any = None,
        progress: Callable[[str], None] | None = None,
    ) -> CoreContext:
        """Create and populate the core context.

        This is intentionally called after any Qt application object exists so
        that core components which use ``QTimer``/``aboutToQuit`` work both in
        the desktop UI (``QApplication``) and in a headless backend
        (``QCoreApplication``).

        When a UI context (``AppContext``) is passed to the constructor, the
        service populates that same context so UI code and core code share one
        object graph.
        """
        ctx = self.context
        ctx.app = app

        def _progress(message: str) -> None:
            if progress is not None:
                progress(message)

        from core.audio_player import AudioPlayer
        from core.backend import initBackend
        from core.config import Config, loadConfig
        from core.favorites import favorites_manager
        from core.llm import LLM
        from core.lyrics import LRCLyricParser, YRCLyricParser
        from core.netease_backend import NeteaseCloudMusicBackend
        from core.playing_manager import PlayingManager
        from core.ws_server import ws_handler, ws_server

        _progress('Phase 1 (start core...)')
        backend = NeteaseCloudMusicBackend()
        initBackend(backend)

        cfg = Config.instance()
        if cfg.login_status and not backend.currentSessionIsAnonymous():
            backend.writeLoginInfo(cfg.login_status)
        else:
            cfg.login_status = backend.getCurrentLoginStatus()

        _progress('Loading config...')
        loadConfig()

        _progress('Loading favorites...')
        favorites_manager.load()

        _progress('Logging in...')
        if cfg.session is None:
            snapshot = backend.loginViaAnonymousAccount()
            cfg.session = snapshot.session
            cfg.login_status = snapshot.login_status
            _logger.info('logged into generated anonymous account')
        else:
            backend.loadSession(cfg.session)
            _logger.info('loaded session from config')

            if (
                cfg.login_method == 'cell phone'
                or cfg.login_method == 'QR code'
                or cfg.login_method == 'cookie'
            ) and cfg.login_status:
                backend.writeLoginInfo(cfg.login_status)
                _logger.info('wrote login info')

        backend.setRandomDeviceId()

        _progress('Phase 2 (initialize components...)')
        ctx.config = Config.instance()
        ctx.player = AudioPlayer()
        ctx.mgr = LRCLyricParser()
        ctx.transmgr = LRCLyricParser()
        ctx.ymgr = YRCLyricParser()
        ctx.ws_server = ws_server
        ctx.ws_handler = ws_handler
        ctx.llm = LLM()
        ctx.favs = list(favorites_manager.folders)
        ctx.playing_manager = PlayingManager(ctx)
        ctx.process_pids['main'] = os.getpid()

        _logger.debug('core backend initialized')
        return ctx

    def start(self) -> None:
        """Start long-running core services that should run without the UI."""
        ws_server = self.context.ws_server
        if ws_server is not None and not ws_server.is_alive():
            ws_server.start()
            _logger.info('websocket bridge started')

    def shutdown(self) -> None:
        """Shut down core services. Mirrors the UI's exit cleanup."""
        ctx = self.context
        if ctx.playing_manager is not None:
            ctx.playing_manager.shutdownWorkers()
        if ctx.player is not None:
            ctx.player.shutdown()
        if ctx.ws_server is not None:
            ctx.ws_server.stop(shutdown_json_sender=True)
