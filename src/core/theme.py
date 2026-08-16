try:
    from darkdetect import isDark as isDarkDarkdetect
    import darkdetect
except ImportError:  # pragma: no cover - optional platform theme detection
    isDarkDarkdetect = lambda: False
    darkdetect = None  # type: ignore[assignment]

_is_dark = isDarkDarkdetect()


def isDark() -> bool:
    return bool(_is_dark)


def isLight() -> bool:
    return not bool(_is_dark)


def getDarkdetect():
    return darkdetect
