from __future__ import annotations

from functools import lru_cache
from typing import Any


def mixColor(a: Any, b: Any, ratio: float = 0.5) -> Any:
    """Mix two Qt ``QColor`` values and return a new ``QColor``.

    Qt is imported lazily so the module can be imported by the Qt-free backend.
    """
    from PySide6.QtGui import QColor

    class HashableQColor(QColor):
        def __hash__(self) -> int:
            return hash((self.red(), self.green(), self.blue(), self.alpha()))

    return _mixColor(HashableQColor(a), HashableQColor(b), ratio)


@lru_cache
def _mixColor(a: Any, b: Any, ratio: float = 0.5) -> Any:
    from PySide6.QtGui import QColor

    return QColor(
        int(a.red() * ratio + b.red() * (1 - ratio)),
        int(a.green() * ratio + b.green() * (1 - ratio)),
        int(a.blue() * ratio + b.blue() * (1 - ratio)),
        int(a.alpha() * ratio + b.alpha() * (1 - ratio)),
    )
