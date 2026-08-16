"""Qt-free shims used by core modules.

The desktop UI keeps using real PySide6; these shims only exist so that the
core (audio, playback, WebSocket, downloads) can be imported and run without
PySide6. They implement the small subset of Qt APIs the core uses.
"""

from __future__ import annotations

import threading
import time
from typing import Any, Callable

from .signals import Signal, _SignalInstance


class Property:
    """Minimal stand-in for PySide6's ``@Property`` decorator."""

    def __init__(self, fget: Callable[[Any], Any] | None = None) -> None:
        self.fget = fget
        self.fset: Callable[[Any, Any], Any] | None = None

    def __call__(self, fget: Callable[[Any], Any]) -> 'Property':
        self.fget = fget
        return self

    def setter(self, fset: Callable[[Any, Any], Any]) -> 'Property':
        self.fset = fset
        return self

    def __get__(self, instance: Any, owner: Any = None) -> Any:
        if instance is None:
            return self
        if self.fget is None:
            raise AttributeError('unreadable attribute')
        return self.fget(instance)

    def __set__(self, instance: Any, value: Any) -> None:
        if self.fset is None:
            raise AttributeError('can\'t set attribute')
        self.fset(instance, value)


class QTimer:
    """Minimal stand-in for core uses of ``QTimer``/``QTimer.singleShot``."""

    def __init__(self, parent: Any = None) -> None:
        self.timeout = _SignalInstance()
        self._timer: threading.Timer | None = None
        self._interval_ms: int = 0
        self._single_shot: bool = False

    @staticmethod
    def singleShot(ms: int, callback: Callable[..., Any]) -> None:
        timer = threading.Timer(max(0, ms) / 1000.0, callback)
        timer.daemon = True
        timer.start()

    def start(self, ms: int) -> None:
        self._interval_ms = max(0, int(ms))
        self.stop()
        if self._interval_ms == 0:
            self.timeout.emit()
            return
        self._timer = threading.Timer(
            self._interval_ms / 1000.0, self._on_timeout
        )
        self._timer.daemon = True
        self._timer.start()

    def stop(self) -> None:
        if self._timer is not None:
            self._timer.cancel()
            self._timer = None

    def isActive(self) -> bool:
        return self._timer is not None and self._timer.is_alive()

    def setInterval(self, ms: int) -> None:
        self._interval_ms = max(0, int(ms))

    def _on_timeout(self) -> None:
        self._timer = None
        self.timeout.emit()


class QPropertyAnimation:
    """Minimal stand-in: applies the end value and emits ``finished``.

    This drops the actual easing for the core backend. The desktop UI can be
    migrated to a real animated wrapper later; the important property here is
    that audio/playback no longer depend on PySide6.
    """

    class State:
        Running = 'running'
        Stopped = 'stopped'

    def __init__(self, target: Any, property_name: bytes | str) -> None:
        self.target = target
        self.property_name = (
            property_name.decode() if isinstance(property_name, bytes) else property_name
        )
        self.finished = _SignalInstance()
        self._start_value: Any = None
        self._end_value: Any = None
        self._duration_ms: int = 0
        self._timer: threading.Timer | None = None
        self._state = self.State.Stopped

    def setStartValue(self, value: Any) -> None:
        self._start_value = value

    def setEndValue(self, value: Any) -> None:
        self._end_value = value

    def setDuration(self, ms: int) -> None:
        self._duration_ms = max(0, int(ms))

    def setEasingCurve(self, curve: Any) -> None:
        return

    def setKeyValueAt(self, position: float, value: Any) -> None:
        # Keyframes are ignored by the shim; the final value wins.
        return

    def start(self) -> None:
        self.stop()
        if self._end_value is not None:
            setattr(self.target, self.property_name, self._end_value)
        self._state = self.State.Running
        if self._duration_ms > 0:
            self._timer = threading.Timer(
                self._duration_ms / 1000.0, self._on_finished
            )
            self._timer.daemon = True
            self._timer.start()
        else:
            self._on_finished()

    def stop(self) -> None:
        if self._timer is not None:
            self._timer.cancel()
            self._timer = None
        self._state = self.State.Stopped

    def state(self) -> str:
        return self._state

    def _on_finished(self) -> None:
        self._timer = None
        self._state = self.State.Stopped
        self.finished.emit()


class QEasingCurve:
    class Type:
        Linear = 'linear'
        InOutCubic = 'inoutcubic'
        OutCubic = 'outcubic'


class _DummyButton:
    def setText(self, text: str) -> None:
        return

    def hide(self) -> None:
        return


class MessageBox:
    """No-op stand-in: logs instead of showing a native dialog."""

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        self.cancelButton = _DummyButton()
        self.yesButton = _DummyButton()

    def exec(self) -> int:
        return 0
