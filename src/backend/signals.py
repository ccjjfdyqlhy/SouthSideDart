"""Minimal Qt-like signals that do not depend on PySide6.

These are used by the standalone core backend so that audio, playback, WebSocket
and download services can be imported and run without Qt. The desktop UI may
keep using PySide6 signals in the view layer.

The implementation is a descriptor so each instance gets its own callback list,
matching the behavior of PySide6 signals.
"""

from __future__ import annotations

import logging
import threading
from typing import Any, Callable

_logger = logging.getLogger(__name__)


class _SignalInstance:
    def __init__(self) -> None:
        self._callbacks: list[Callable[..., Any]] = []
        self._lock = threading.Lock()

    def connect(self, callback: Callable[..., Any]) -> None:
        if callback not in self._callbacks:
            with self._lock:
                self._callbacks.append(callback)

    def disconnect(self, callback: Callable[..., Any] | None = None) -> None:
        with self._lock:
            if callback is None:
                self._callbacks.clear()
                return
            if callback in self._callbacks:
                self._callbacks.remove(callback)

    def emit(self, *args: Any, **kwargs: Any) -> None:
        with self._lock:
            callbacks = list(self._callbacks)
        for callback in callbacks:
            try:
                callback(*args, **kwargs)
            except Exception:
                _logger.exception('signal callback failed')


class Signal:
    """Descriptor that exposes a per-instance ``_SignalInstance``."""

    def __init__(self, *arg_types: Any) -> None:
        self._arg_types = arg_types
        self._name = ''

    def __set_name__(self, owner: Any, name: str) -> None:
        self._name = name

    def __get__(self, instance: Any, owner: Any = None) -> Any:
        if instance is None:
            return self
        data = instance.__dict__.get(self._name)
        if data is None:
            data = _SignalInstance()
            instance.__dict__[self._name] = data
        return data
