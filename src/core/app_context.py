from __future__ import annotations

import logging
import threading
from typing import TYPE_CHECKING, Any, Callable, cast

from backend.core_context import CoreContext
from backend.scheduler import TaskScheduler
try:
    from imports import QObject, Signal
except ImportError:  # pragma: no cover - Qt-free backend path
    from backend.signals import Signal

    QObject = object  # type: ignore[assignment,misc]

if TYPE_CHECKING:
    from core.audio_player import AudioPlayer
    from core.config import Config
    from core.debugging import Debugging
    from core.llm import LLM
    from core.lyrics import LRCLyricParser, YRCLyricParser
    from core.models import (
        CloudFolderInfo,
        LocalFolderInfo,
        SearchSongInfo,
        SongStorable,
    )
    from core.playing_manager import PlayingManager
    from core.ws_server import WebSocketServer, QObjectHandler
    from PySide6.QtWidgets import QApplication
    from services.services import EventsServices
    from views.comments_page import CommentsPage
    from views.desktop_lyrics import DesktopLyricsPage
    from views.dependences_window import DependencesWindow
    from views.favorites_page import FavoritesPage
    from views.launch_window import LaunchWindow
    from views.main_window import MainWindow
    from views.playing_page import PlayingPage
    from views.playlist_page import PlaylistPage
    from views.search_page import SearchPage
    from views.setting_page import SettingPage
    from views.home_page import HomePage
    from views.library_page import LibraryPage
    from views.lyric_editor_page import LyricEditorPage


class _ScheduledTaskRunner(QObject):
    scheduledTaskRequested = Signal()

    def __init__(self) -> None:
        super().__init__()
        self._logger = logging.getLogger(__name__)
        self._scheduled_tasks: list[
            tuple[Callable[..., Any], tuple[Any, ...], dict[str, Any]]
        ] = []
        self._scheduled_tasks_lock = threading.Lock()
        self.scheduledTaskRequested.connect(self._runScheduledTasks)

    def addTask(self, task: Callable[..., Any], *args: Any, **kwargs: Any) -> None:
        with self._scheduled_tasks_lock:
            self._scheduled_tasks.append((task, args, kwargs))
        self.scheduledTaskRequested.emit()

    def _runScheduledTasks(self) -> None:
        while True:
            with self._scheduled_tasks_lock:
                if not self._scheduled_tasks:
                    return
                task, args, kwargs = self._scheduled_tasks.pop(0)
            try:
                task(*args, **kwargs)
            except Exception as e:
                self._logger.exception('scheduled task failed')
                raise e


class AppContext(CoreContext):
    """Desktop UI context: core state plus all PySide6 page/widget references."""

    def __init__(self, task_scheduler: TaskScheduler | None = None) -> None:
        super().__init__(task_scheduler=task_scheduler)
        fallback_scheduler = self._task_scheduler
        self._scheduled_task_runner = _ScheduledTaskRunner()
        self._task_scheduler = self._scheduled_task_runner
        close = getattr(fallback_scheduler, 'close', None)
        if close is not None:
            close()

        # UI-only state
        self.app: QApplication = cast('QApplication', None)
        self.harmony_font_family: str = ''
        self.launch_window: LaunchWindow = cast('LaunchWindow', None)
        self.main_window: MainWindow = cast('MainWindow', None)
        self.playing_page: PlayingPage = cast('PlayingPage', None)
        self.search_page: SearchPage = cast('SearchPage', None)
        self.desktop_lyrics_page: DesktopLyricsPage = cast('DesktopLyricsPage', None)
        self.favorites_page: FavoritesPage = cast('FavoritesPage', None)
        self.setting_page: SettingPage = cast('SettingPage', None)
        self.playlist_page: PlaylistPage = cast('PlaylistPage', None)
        self.home_page: HomePage = cast('HomePage', None)
        self.library_page: LibraryPage = cast('LibraryPage', None)
        self.lyric_editor_page: LyricEditorPage = cast('LyricEditorPage', None)
        self.comments_page: CommentsPage = cast('CommentsPage', None)
        self.dependences_window: DependencesWindow = cast('DependencesWindow', None)
        self.debugging_obj: Debugging = cast('Debugging', None)
        self.events_service: EventsServices = cast('EventsServices', None)

    def addScheduledTask(
        self,
        task: Callable[..., Any],
        *args: Any,
        **kwargs: Any,
    ) -> None:
        self._task_scheduler.addTask(task, *args, **kwargs)
