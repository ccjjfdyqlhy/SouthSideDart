"""Check that the standalone core backend imports without PySide6/Qt.

Run from anywhere:

    python scripts/check_backend_no_qt.py
"""

from __future__ import annotations

import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SRC = os.path.join(ROOT, 'src')
if SRC not in sys.path:
    sys.path.insert(0, SRC)

BACKEND_MODULES = [
    'backend.core_context',
    'backend.scheduler',
    'backend.service',
    'backend.standalone',
    'core.audio_player',
    'core.app_context',
    'core.backend',
    'core.cache_cleanup',
    'core.color',
    'core.config',
    'core.crossfade',
    'core.debugging',
    'core.dialogs',
    'core.downloader',
    'core.favorites',
    'core.free_threaded_worker',
    'core.i18n',
    'core.icons',
    'core.image',
    'core.llm',
    'core.llm_tools',
    'core.loudness',
    'core.lyrics',
    'core.lyric_video_export',
    'core.models',
    'core.netease_backend',
    'core.playing_manager',
    'core.qt_utils',
    'core.smooth',
    'core.soundfile',
    'core.theme',
    'core.time_format',
    'core.weighted_random',
    'core.ws_server',
]

for module in BACKEND_MODULES:
    __import__(module)
    print(f'ok {module}')

print('backend core imports OK without PySide6')
