from __future__ import annotations

from . import weapi


def getPersonalFM() -> dict:
    """Get private roaming / personal FM songs."""
    return weapi('/api/v1/radio/get', {})
