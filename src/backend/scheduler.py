"""UI-independent task scheduling helpers.

The desktop UI schedules work back onto Qt's main thread with ``QObject``
signals. A standalone backend does not have a Qt widget loop, so it needs a
small thread-safe scheduler instead. UI code can keep using its Qt scheduler;
backend code should depend only on this interface.
"""

from __future__ import annotations

import logging
import queue
import threading
from typing import Any, Callable, Protocol

_logger = logging.getLogger(__name__)

Task = tuple[Callable[..., Any], tuple[Any, ...], dict[str, Any]]


class TaskScheduler(Protocol):
    """Minimal interface used by core components to schedule UI work."""

    def addTask(self, task: Callable[..., Any], *args: Any, **kwargs: Any) -> None:
        """Schedule ``task(*args, **kwargs)`` to run on the owner thread."""
        ...


class ThreadTaskScheduler:
    """Run scheduled tasks on a single daemon worker thread.

    This is the fallback scheduler for headless/standalone backend runs. It is
    not a replacement for Qt's main-thread scheduling in the desktop UI; it
    exists so core services do not have to know about Qt.
    """

    def __init__(self) -> None:
        self._queue: queue.SimpleQueue[Task] = queue.SimpleQueue()
        self._thread = threading.Thread(
            target=self._run,
            name='backend-task-scheduler',
            daemon=True,
        )
        self._thread.start()

    def addTask(self, task: Callable[..., Any], *args: Any, **kwargs: Any) -> None:
        self._queue.put((task, args, kwargs))

    def close(self) -> None:
        """Stop the worker thread. Idempotent; queued tasks are abandoned."""
        if not self._thread.is_alive():
            return
        self._queue.put((self._stop, (), {}))
        self._thread.join(timeout=1)

    def _stop(self) -> None:
        raise SystemExit

    def _run(self) -> None:
        while True:
            task, args, kwargs = self._queue.get()
            try:
                task(*args, **kwargs)
            except SystemExit:
                break
            except Exception:
                _logger.exception('scheduled backend task failed')
