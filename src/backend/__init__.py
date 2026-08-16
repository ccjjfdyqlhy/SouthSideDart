"""Standalone core backend package for SouthsideMusic.

This package is meant to grow into the UI-independent application core:
audio playback, NetEase API, favorites, playing state, WebSocket bridge,
and LLM services. The current PySide6 UI lives in ``src/views`` and talks to
these services through ``AppContext``; the long-term goal is to expose the
same functionality over a transport so the UI backend can be replaced.
"""

from .core_context import CoreContext
from .scheduler import TaskScheduler, ThreadTaskScheduler
from .service import CoreBackendService
from .shim import QPropertyAnimation, QTimer, Property
from .signals import Signal

__all__ = [
    'CoreContext',
    'CoreBackendService',
    'QPropertyAnimation',
    'QTimer',
    'Property',
    'Signal',
    'TaskScheduler',
    'ThreadTaskScheduler',
]
