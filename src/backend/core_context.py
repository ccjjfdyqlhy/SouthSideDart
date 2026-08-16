"""UI-independent application core context.

``CoreContext`` holds the objects and state that belong to the application's
core: configuration, audio player, lyric parsers, playback manager, WebSocket
bridge, LLM state, favorites and background task scheduling.

It deliberately does not import PySide6 or any view module. The desktop UI's
``AppContext`` subclasses this and adds Qt/widget/page fields.
"""

from __future__ import annotations

import threading
from typing import TYPE_CHECKING, Any, Callable, cast

from .scheduler import TaskScheduler, ThreadTaskScheduler

if TYPE_CHECKING:
    from core.audio_player import AudioPlayer
    from core.config import Config
    from core.llm import LLM
    from core.lyrics import LRCLyricParser, YRCLyricParser
    from core.models import (
        CloudFolderInfo,
        LocalFolderInfo,
        SearchSongInfo,
        SongStorable,
    )
    from core.playing_manager import PlayingManager
    from core.ws_server import QObjectHandler, WebSocketServer


class CoreContext:
    """Shared state for a UI-independent SouthsideMusic backend."""

    def __init__(self, task_scheduler: TaskScheduler | None = None) -> None:
        self._task_scheduler: TaskScheduler = task_scheduler or ThreadTaskScheduler()

        # ``app`` is intentionally typed loosely: the desktop UI sets a
        # QApplication, while a standalone backend can set a QCoreApplication.
        # Core code only uses the Qt ``aboutToQuit`` lifecycle signal.
        self.app: Any = None

        self.config: Config = cast('Config', None)
        self.player: AudioPlayer = cast('AudioPlayer', None)
        self.mgr: LRCLyricParser = cast('LRCLyricParser', None)
        self.transmgr: LRCLyricParser = cast('LRCLyricParser', None)
        self.ymgr: YRCLyricParser = cast('YRCLyricParser', None)
        self.ws_server: WebSocketServer = cast('WebSocketServer', None)
        self.ws_handler: QObjectHandler = cast('QObjectHandler', None)

        self.favs: list[LocalFolderInfo | CloudFolderInfo] = []
        self.lock: threading.Lock = threading.Lock()
        self.playing_manager: PlayingManager = cast('PlayingManager', None)
        self.llm: LLM = cast('LLM', None)

        self.llm_song_handles: dict[str, SearchSongInfo | SongStorable] = {}
        self.llm_folder_handles: dict[str, LocalFolderInfo | CloudFolderInfo] = {}
        self.llm_cloud_search_query: str = ''
        self.llm_cloud_search_offset: int = 0

        self.dependences_available: bool = True
        self.debugging: bool = False
        self.process_pids: dict[str, int] = {}

    def addScheduledTask(
        self,
        task: Callable[..., Any],
        *args: Any,
        **kwargs: Any,
    ) -> None:
        self._task_scheduler.addTask(task, *args, **kwargs)
