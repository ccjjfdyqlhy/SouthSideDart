from __future__ import annotations

import io
from functools import lru_cache
from typing import Any

import numpy as np
from PIL import Image


def getAverageColor(pixmap: Any) -> list[float]:
    """Return the average RGB color of a Qt ``QPixmap``.

    This is a UI helper; it imports Qt lazily so the core backend can run
    without PySide6 installed.
    """
    from PySide6.QtGui import QImage

    if pixmap is None or pixmap.isNull():
        return [128, 128, 128]
    image = pixmap.toImage().convertToFormat(QImage.Format.Format_RGBA8888)
    return _avg_color_from_rgba_buffer(
        bytes(image.bits()[: image.sizeInBytes()]),
        image.width(),
        image.height(),
        image.bytesPerLine(),
    )


def getAverageColorFromBytes(image_bytes: bytes) -> list[float]:
    try:
        with Image.open(io.BytesIO(image_bytes)) as img:
            img = img.convert('RGB')
            arr = np.asarray(img, dtype=np.uint8)
            if arr.size == 0:
                return [128, 128, 128]
            return np.mean(arr, axis=(0, 1)).tolist()
    except Exception:
        return [128, 128, 128]


@lru_cache
def _getAverageColor(key: tuple, image_bytes: bytes) -> list[float]:
    return getAverageColorFromBytes(image_bytes)


def _avg_color_from_rgba_buffer(
    data: bytes,
    width: int,
    height: int,
    bytes_per_line: int,
) -> list[float]:
    arr = np.frombuffer(data, dtype=np.uint8).reshape(height, bytes_per_line)
    arr = arr[:, : width * 4].reshape(height, width, 4)
    return np.mean(arr[:, :, :3], axis=(0, 1)).tolist()
