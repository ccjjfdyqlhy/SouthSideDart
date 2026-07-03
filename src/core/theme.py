from darkdetect import isDark as isDarkDarkdetect
import darkdetect

_is_dark = isDarkDarkdetect()


def isDark() -> bool:
    return bool(_is_dark)


def isLight() -> bool:
    return not bool(_is_dark)


def getDarkdetect():
    return darkdetect
