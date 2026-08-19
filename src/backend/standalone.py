"""Standalone core backend entrypoint.

Run from the repository root:

    uv run python -m backend.standalone

or directly:

    python src/backend/standalone.py

This starts the UI-independent core (config, NetEase API, audio player,
playback manager, WebSocket bridge) with no PySide6/Qt dependency and serves a
newline-delimited JSON protocol on stdin/stdout and a TCP RPC server
(``127.0.0.1:15490``) with event push. It lets a cross-platform UI talk to the
same core as a separate process.
"""

from __future__ import annotations

import json
import os
import re
import socketserver
import sys
import threading
from typing import Any

_SRC_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if _SRC_DIR not in sys.path:
    sys.path.insert(0, _SRC_DIR)

# 默认 TCP RPC 端口(供 Flutter/外部 UI 连接)。
DEFAULT_TCP_PORT = 15490

# 启动时恢复的播放位置(未播放时 get_playback 返回它)。
_RESTORED_POSITION = 0.0

from backend.core_context import CoreContext
from backend.protocol import encode_error, encode_response, parse_request
from backend.service import CoreBackendService
from services.events import (
    LYRIC_LINE_CHANGED,
    PLAY_STATE_CHANGED,
    PLAYBACK_LYRICS_UPDATED,
    PLAYLIST_CHANGED,
    PLAYLAST,
    PLAYNEXT,
    SONG_CHANGED,
    event_bus,
)


# ---------------------------------------------------------------------------
# 序列化辅助
# ---------------------------------------------------------------------------

def _https(url: str) -> str:
    """把 http:// 封面地址升级为 https,避免客户端混合内容限制。"""
    if isinstance(url, str) and url.startswith('http://'):
        return 'https://' + url[7:]
    return url if isinstance(url, str) else ''


def _artist_to_dict(artist: Any) -> dict[str, Any]:
    return {
        'id': str(getattr(artist, 'id', '')),
        'name': str(getattr(artist, 'name', '')),
    }


def _song_to_dict(song: Any) -> dict[str, Any]:
    """SongStorable / SongInfo 等 -> JSON 字典。"""
    if song is None:
        return {
            'id': '',
            'name': '',
            'artists': [],
            'album': '',
            'cover_url': '',
            'duration': 0,
        }
    album = getattr(song, 'album', None)
    album_name = getattr(song, 'album_name', '') or (
        getattr(album, 'name', '')
        if album is not None and not isinstance(album, (str, bytes))
        else str(album) if isinstance(album, (str, bytes)) else ''
    )
    cover_url = getattr(song, 'cover_url', '') or (
        getattr(album, 'cover_url', '')
        if album is not None and not isinstance(album, (str, bytes))
        else ''
    )
    return {
        'id': str(getattr(song, 'id', '')),
        'name': str(getattr(song, 'name', '')),
        'artists': [_artist_to_dict(a) for a in getattr(song, 'artists', [])],
        'album': album_name,
        'cover_url': _https(cover_url),
        'duration': int(getattr(song, 'duration', 0) or 0),
    }


def _cloud_folder_to_dict(folder: Any) -> dict[str, Any]:
    return {
        'id': str(getattr(folder, 'id', '')),
        'name': str(getattr(folder, 'folder_name', '')),
        'cover_url': _https(str(getattr(folder, 'image_url', '') or '')),
        'song_count': int(getattr(folder, 'song_count', 0) or 0),
        'type': 'cloud',
    }


def _search_song_to_dict(song: Any) -> dict[str, Any]:
    album = getattr(song, 'album', None)
    return {
        'id': str(getattr(song, 'id', '')),
        'name': str(getattr(song, 'name', '')),
        'artists': [_artist_to_dict(a) for a in getattr(song, 'artists', [])],
        'album': getattr(album, 'name', '') if album is not None else '',
        'cover_url': _https(
            getattr(album, 'cover_url', '') if album is not None else ''
        ),
        'duration': int(getattr(song, 'duration', 0) or 0),
    }


def _lrc_lines(lrc_text: str) -> list[dict[str, Any]]:
    """把 LRC 文本解析成 [{'time': float秒, 'content': str}]。"""
    lines: list[dict[str, Any]] = []
    for raw in (lrc_text or '').splitlines():
        raw = raw.strip()
        m = re.match(r'\[(\d+):(\d+)[.:](\d+)\]', raw)
        if not m:
            continue
        minutes = int(m.group(1))
        seconds = int(m.group(2))
        ms_raw = m.group(3).ljust(3, '0')[:3]
        content = raw[m.end():].strip()
        if not content:
            continue
        lines.append({
            'time': minutes * 60 + seconds + int(ms_raw) / 1000,
            'content': content,
        })
    lines.sort(key=lambda x: x['time'])
    return lines


def _api_song_to_dict(song: dict[str, Any]) -> dict[str, Any]:
    """把 pyncm API 的歌曲 dict(ar/al/dt)转为统一 JSON。"""
    album = song.get('al') or {}
    return {
        'id': str(song.get('id', '')),
        'name': str(song.get('name', '')),
        'artists': [
            {'id': str(a.get('id', '')), 'name': str(a.get('name', ''))}
            for a in (song.get('ar') or [])
        ],
        'album': str(album.get('name', '')),
        'cover_url': _https(str(album.get('picUrl', ''))),
        'duration': int(song.get('dt') or 0),
    }


def _cloud_folder_from_api(playlist: dict[str, Any]) -> dict[str, Any]:
    return {
        'id': str(playlist.get('id', '')),
        'name': str(playlist.get('name', '')),
        'cover_url': _https(str(playlist.get('coverImgUrl', '') or '')),
        'song_count': int(playlist.get('trackCount', 0) or 0),
        'type': 'cloud',
    }


def _song_from_payload(payload: dict[str, Any]) -> Any:
    """把客户端歌曲 JSON 构造为 SongStorable(用于 play_songs)。"""
    from core.models import ArtistInfo, SongInfo, SongStorable

    info = SongInfo(
        name=str(payload.get('name') or ''),
        artists=[
            ArtistInfo(
                id=int(a.get('id') or 0),
                name=str(a.get('name') or ''),
            )
            for a in (payload.get('artists') or [])
        ],
        id=str(payload.get('id') or ''),
        privilege=0,
        duration=int(payload.get('duration') or 0),
    )
    return SongStorable(info)


# ---------------------------------------------------------------------------
# RPC handler
# ---------------------------------------------------------------------------

def _handle_request(
    service: CoreBackendService,
    request: dict[str, Any],
) -> str:
    request_id = request.get('id')
    method = request.get('method')
    params = request.get('params') or {}
    ctx = service.context

    if method == 'ping':
        return encode_response(request_id, {'pong': True})

    if method == 'get_status':
        return encode_response(
            request_id,
            {
                'initialized': ctx.player is not None,
                'playing': bool(ctx.player and ctx.player.isPlaying()),
                'playlist_size': (
                    len(ctx.playing_manager.playlist)
                    if ctx.playing_manager is not None
                    else 0
                ),
                'ws_running': bool(ctx.ws_server and ctx.ws_server.is_alive()),
            },
        )

    if method == 'get_config':
        cfg = ctx.config
        if cfg is None:
            return encode_response(request_id, {})
        return encode_response(
            request_id,
            {
                'language': cfg.language,
                'volume': cfg.volume,
                'play_method': cfg.play_method,
                'show_advanced_settings': cfg.show_advanced_settings,
                'enable_desktop_lyrics': cfg.enable_desktop_lyrics,
                'data_cleanup_enabled': cfg.data_cleanup_enabled,
                'target_lufs': cfg.target_lufs,
                'show_translation': cfg.show_translation,
                'play_quality': cfg.play_quality,
            },
        )

    if method == 'get_playlist':
        manager = ctx.playing_manager
        if manager is None:
            return encode_response(request_id, {'current_index': -1, 'items': []})
        items = [_song_to_dict(song) for song in manager.playlist]
        return encode_response(
            request_id,
            {
                'current_index': manager.current_index,
                'items': items,
                'current_song': _song_to_dict(manager.current_song),
            },
        )

    if method == 'get_playback':
        manager = ctx.playing_manager
        player = ctx.player
        if manager is None:
            return encode_response(
                request_id,
                {
                    'playing': False,
                    'song': None,
                    'position': 0.0,
                    'duration': 0.0,
                    'playlist': [],
                    'current_index': -1,
                },
            )
        song = manager.current_song
        duration = float(getattr(song, 'duration', 0) or 0) / 1000
        position = float(player.getPosition()) if player else 0.0
        if not (player and player.isPlaying()):
            position = max(position, _RESTORED_POSITION)
        return encode_response(
            request_id,
            {
                'playing': bool(player and player.isPlaying()),
                'song': _song_to_dict(song),
                'position': position,
                'duration': duration,
                'playlist': [_song_to_dict(s) for s in manager.playlist],
                'current_index': manager.current_index,
                'ws_running': bool(
                    ctx.ws_server and ctx.ws_server.is_alive()
                ),
                'initialized': ctx.player is not None,
            },
        )

    if method == 'list_favorites':
        return encode_response(
            request_id,
            {
                'folders': [
                    {
                        'id': str(getattr(folder, 'id', '')),
                        'name': folder.folder_name,
                        'count': len(folder.songs),
                        'type': 'local'
                        if getattr(folder, 'id', None) is None
                        else 'cloud',
                    }
                    for folder in ctx.favs
                ]
            },
        )

    if method == 'search':
        from core.backend import getBackend

        query = str(params.get('query') or '').strip()
        stype = params.get('type') or 'songs'
        try:
            offset = int(params.get('offset') or 0)
        except (TypeError, ValueError):
            offset = 0
        if not query:
            return encode_error(request_id, 'empty query')
        try:
            if stype == 'playlists':
                result = getBackend().searchPlaylist(query, offset) or []
                items = [_cloud_folder_to_dict(f) for f in result]
                return encode_response(
                    request_id, {'type': 'playlists', 'items': items}
                )
            result = getBackend().searchSong(query, offset) or []
            items = [_search_song_to_dict(s) for s in result]
            return encode_response(request_id, {'type': 'songs', 'items': items})
        except Exception as exc:
            return encode_error(request_id, f'search failed: {exc}')

    if method == 'daily_recommend':
        from core.backend import getBackend

        try:
            folders = getBackend().getDailyRecommendFolders() or []
            songs = getBackend().getDailyRecommendSongs() or []
            return encode_response(
                request_id,
                {
                    'folders': [_cloud_folder_to_dict(f) for f in folders],
                    'songs': [_song_to_dict(s) for s in songs],
                },
            )
        except Exception as exc:
            return encode_error(request_id, f'daily recommend failed: {exc}')

    if method == 'user_playlists':
        from core.backend import getBackend

        try:
            # 红心歌单(我喜欢的音乐)固定在最前,其余为用户创建的歌单。
            result: list[dict[str, Any]] = []
            liked_id: str | None = None
            try:
                liked = getBackend().getLikedPlaylist()
                if liked is not None:
                    liked_dict = _cloud_folder_to_dict(liked)
                    liked_id = liked_dict['id']
                    result.append(liked_dict)
            except Exception:
                # 红心歌单失败不影响其余歌单。
                liked = None
            for folder in getBackend().getUserPlaylists() or []:
                fd = _cloud_folder_to_dict(folder)
                if fd['id'] != liked_id:
                    result.append(fd)
            return encode_response(request_id, {'folders': result})
        except Exception as exc:
            return encode_error(request_id, f'get user playlists failed: {exc}')

    if method == 'create_playlist':
        from core.backend import getBackend

        name = str(params.get('name') or '').strip()
        if not name:
            return encode_error(request_id, 'missing name')
        try:
            playlist_id = getBackend().createPlaylist(name)
            return encode_response(request_id, {'id': str(playlist_id)})
        except Exception as exc:
            return encode_error(request_id, f'create playlist failed: {exc}')

    if method == 'remove_playlist':
        from core.backend import getBackend

        playlist_id = str(params.get('playlist_id') or '')
        if not playlist_id:
            return encode_error(request_id, 'missing playlist_id')
        try:
            getBackend().removePlaylist(playlist_id)
            return encode_response(request_id, {'ok': True})
        except Exception as exc:
            return encode_error(request_id, f'remove playlist failed: {exc}')

    if method == 'get_liked_songs':
        from core.backend import getBackend

        try:
            liked = getBackend().getLikedPlaylist()
            if liked is None:
                return encode_response(request_id, {'ids': []})
            tracks = getBackend().getPlaylistTracks(str(liked.id)) or []
            return encode_response(
                request_id,
                {'ids': [str(song.id) for song in tracks]},
            )
        except Exception as exc:
            return encode_error(request_id, f'get liked songs failed: {exc}')

    if method == 'folder_songs':
        from core.backend import getBackend

        folder_id = str(params.get('folder_id') or '')
        ftype = params.get('type') or 'cloud'
        if not folder_id:
            return encode_error(request_id, 'missing folder_id')
        try:
            if ftype == 'local':
                songs: list[dict[str, Any]] = []
                for folder in ctx.favs:
                    if getattr(folder, 'id', None) == folder_id or (
                        folder.folder_name == folder_id
                    ):
                        songs = [_song_to_dict(s) for s in folder.songs]
                        break
                return encode_response(request_id, {'songs': songs})
            tracks = getBackend().getPlaylistTracks(folder_id) or []
            return encode_response(
                request_id, {'songs': [_song_to_dict(s) for s in tracks]}
            )
        except Exception as exc:
            return encode_error(request_id, f'get folder songs failed: {exc}')

    if method == 'play_songs':
        manager = ctx.playing_manager
        if manager is None:
            return encode_error(request_id, 'backend not fully initialized')
        raw = params.get('songs')
        if not isinstance(raw, list) or not raw:
            return encode_error(request_id, 'empty songs')
        try:
            songs = [_song_from_payload(s) for s in raw]
            manager.setPlaylist(songs)
            manager.playSongAtIndex(0)
            return encode_response(request_id, {'ok': True, 'count': len(songs)})
        except Exception as exc:
            return encode_error(request_id, f'play songs failed: {exc}')

    if method == 'play_playlist':
        from core.backend import getBackend

        manager = ctx.playing_manager
        if manager is None:
            return encode_error(request_id, 'backend not fully initialized')
        folder_id = str(params.get('folder_id') or '')
        ftype = params.get('type') or 'cloud'
        try:
            start = int(params.get('start_index') or 0)
        except (TypeError, ValueError):
            start = 0
        if not folder_id:
            return encode_error(request_id, 'missing folder_id')
        try:
            if ftype == 'local':
                tracks: list[Any] = []
                for folder in ctx.favs:
                    if getattr(folder, 'id', None) == folder_id or (
                        folder.folder_name == folder_id
                    ):
                        tracks = list(folder.songs)
                        break
            else:
                tracks = list(getBackend().getPlaylistTracks(folder_id) or [])
            if not tracks:
                return encode_response(request_id, {'ok': False, 'count': 0})
            manager.setPlaylist(tracks)
            manager.playSongAtIndex(max(0, min(start, len(tracks) - 1)))
            return encode_response(request_id, {'ok': True, 'count': len(tracks)})
        except Exception as exc:
            return encode_error(request_id, f'play playlist failed: {exc}')

    if method == 'play_mode':
        manager = ctx.playing_manager
        if manager is None:
            return encode_error(request_id, 'backend not fully initialized')
        mode = params.get('mode')
        try:
            if mode == 'heart':
                manager.startHeartMode()
            elif mode == 'fm':
                manager.startPersonalFM()
            elif mode == 'radar':
                manager.startPrivateRadar()
            elif mode == 'similar':
                manager.startSimilarSongs()
            else:
                return encode_error(request_id, f'unknown mode: {mode}')
        except Exception as exc:
            return encode_error(request_id, f'play mode failed: {exc}')
        return encode_response(request_id, {'ok': True})

    if method == 'get_lyrics':
        from core.backend import getBackend

        song_id = str(params.get('song_id') or '')
        if not song_id:
            return encode_error(request_id, 'missing song_id')
        try:
            info = getBackend().getTrackLyrics(song_id)
            lrc = str(getattr(info, 'lyric', '') or '') if info else ''
            translated = (
                str(getattr(info, 'translated_lyric', '') or '')
                if info
                else ''
            )
            return encode_response(
                request_id,
                {
                    'lines': _lrc_lines(lrc),
                    'translated': _lrc_lines(translated),
                },
            )
        except Exception as exc:
            return encode_error(request_id, f'get lyrics failed: {exc}')

    if method == 'set_config':
        cfg = ctx.config
        if cfg is None:
            return encode_error(request_id, 'backend not fully initialized')
        key = params.get('key')
        value = params.get('value')
        allowed: dict[str, type] = {
            'volume': float,
            'play_method': str,
            'language': str,
            'show_translation': bool,
            'show_advanced_settings': bool,
            'background_ratio': float,
            'play_speed': float,
            'play_pitch': float,
            'data_cleanup_enabled': bool,
            'data_cache_max_mb': int,
            'lyrics_smooth_factor': float,
            'enable_desktop_lyrics': bool,
            'target_lufs': int,
            'play_quality': int,
        }
        if key not in allowed:
            return encode_error(request_id, f'config key not allowed: {key}')
        try:
            from core.config import saveConfig

            setattr(cfg, key, allowed[key](value))
            saveConfig()
        except (TypeError, ValueError) as exc:
            return encode_error(request_id, f'invalid value for {key}: {exc}')
        return encode_response(request_id, {'ok': True})

    if method in ('like_song', 'unlike_song'):
        from core.backend import getBackend

        song_id = str(params.get('song_id') or '')
        if not song_id:
            return encode_error(request_id, 'missing song_id')
        try:
            folder_id = str(params.get('folder_id') or '')
            if not folder_id:
                liked = getBackend().getLikedPlaylist()
                folder_id = str(liked.id) if liked else ''
            if not folder_id:
                return encode_error(request_id, 'no liked playlist found')
            option = 'add' if method == 'like_song' else 'del'
            getBackend().editPlaylist(option, [song_id], folder_id)
            return encode_response(request_id, {'ok': True})
        except Exception as exc:
            return encode_error(request_id, f'{method} failed: {exc}')

    if method == 'remove_playlist_song':
        manager = ctx.playing_manager
        if manager is None:
            return encode_error(request_id, 'backend not fully initialized')
        try:
            index = int(params.get('index', -1))
        except (TypeError, ValueError):
            return encode_error(request_id, 'invalid index')
        if not 0 <= index < len(manager.playlist):
            return encode_error(request_id, 'index out of range')
        manager.playlist.pop(index)
        if index < manager.current_index:
            manager.current_index -= 1
        event_bus.emit(PLAYLIST_CHANGED)
        return encode_response(request_id, {'ok': True})

    if method == 'clear_playlist':
        manager = ctx.playing_manager
        if manager is None:
            return encode_error(request_id, 'backend not fully initialized')
        current = manager.current_song
        manager.playlist.clear()
        if current is not None:
            manager.playlist.append(current)
            manager.current_index = 0
        else:
            manager.current_index = -1
        event_bus.emit(PLAYLIST_CHANGED)
        return encode_response(request_id, {'ok': True, 'remaining': len(manager.playlist)})

    if method == 'queue_song':
        manager = ctx.playing_manager
        if manager is None:
            return encode_error(request_id, 'backend not fully initialized')
        try:
            song = _song_from_payload(params.get('song') or {})
            raw_index = params.get('index')
            if raw_index is None:
                insert_at = manager.current_index + 2
                if insert_at > len(manager.playlist):
                    insert_at = len(manager.playlist)
            else:
                insert_at = max(0, min(int(raw_index), len(manager.playlist)))
            manager.playlist.insert(insert_at, song)
            event_bus.emit(PLAYLIST_CHANGED)
            return encode_response(request_id, {'ok': True, 'index': insert_at})
        except Exception as exc:
            return encode_error(request_id, f'queue song failed: {exc}')

    if method == 'play_storable':
        manager = ctx.playing_manager
        if manager is None:
            return encode_error(request_id, 'backend not fully initialized')
        try:
            song = _song_from_payload(params.get('song') or {})
            manager.playStorable(song)
            return encode_response(request_id, {'ok': True})
        except Exception as exc:
            return encode_error(request_id, f'play storable failed: {exc}')

    if method == 'get_comments':
        from core.backend import getBackend

        song_id = str(params.get('song_id') or '')
        if not song_id:
            return encode_error(request_id, 'missing song_id')
        try:
            page = max(1, int(params.get('page') or 1))
            limit = max(1, min(50, int(params.get('limit') or 20)))
            info = getBackend().getComments(song_id, page, limit)
            comments = []
            for comment in info.comments:
                user = getattr(comment, 'user', None)
                comments.append(
                    {
                        'id': str(getattr(comment, 'id', '')),
                        'content': str(getattr(comment, 'content', '')),
                        'liked_count': int(getattr(comment, 'liked_count', 0) or 0),
                        'time': (
                            comment.time.isoformat()
                            if getattr(comment, 'time', None)
                            else ''
                        ),
                        'user': {
                            'id': str(getattr(user, 'id', '')),
                            'avatar_url': str(getattr(user, 'avatar_url', '') or ''),
                            'nickname': str(getattr(user, 'nickname', '')),
                        },
                        'be_replied': [
                            {
                                'content': str(getattr(be, 'content', '')),
                                'user': {
                                    'nickname': str(
                                        getattr(getattr(be, 'user', None), 'nickname', '')
                                    )
                                },
                            }
                            for be in (getattr(comment, 'be_replied', None) or [])
                        ],
                    }
                )
            return encode_response(
                request_id,
                {
                    'total': int(getattr(info, 'total_count', 0) or 0),
                    'cursor': str(getattr(info, 'cursor', '-1')),
                    'comments': comments,
                },
            )
        except Exception as exc:
            return encode_error(request_id, f'get comments failed: {exc}')

    if method == 'add_comment':
        from core.backend import getBackend

        song_id = str(params.get('song_id') or '')
        content = str(params.get('content') or '').strip()
        if not song_id:
            return encode_error(request_id, 'missing song_id')
        if not content:
            return encode_error(request_id, 'empty content')
        try:
            getBackend().addComment(song_id, content)
            return encode_response(request_id, {'ok': True})
        except Exception as exc:
            return encode_error(request_id, f'add comment failed: {exc}')

    if method == 'get_account_info':
        from core.backend import getBackend

        try:
            info = getBackend().getAccountInfo()
            return encode_response(
                request_id,
                {
                    'logged_in': bool(info.logged_in),
                    'nickname': str(info.nickname or ''),
                    'avatar_url': str(info.avatar_url or ''),
                    'user_id': str(info.user_id) if info.user_id else '',
                    'vip_type': str(info.vip_type or ''),
                },
            )
        except Exception as exc:
            return encode_error(request_id, f'get account info failed: {exc}')

    if method == 'login_qr_create':
        from core.backend import getBackend

        try:
            info = getBackend().createLoginQRCode()
            qr_b64 = ''
            try:
                import base64
                import io

                import qrcode

                img = qrcode.make(info.url)
                buf = io.BytesIO()
                img.save(buf, format='PNG')
                qr_b64 = base64.b64encode(buf.getvalue()).decode('ascii')
            except Exception:
                pass
            return encode_response(
                request_id,
                {'key': info.key, 'url': info.url, 'qr_base64': qr_b64},
            )
        except Exception as exc:
            return encode_error(request_id, f'create qr code failed: {exc}')

    if method == 'login_qr_check':
        from core.backend import getBackend

        key = str(params.get('key') or '')
        if not key:
            return encode_error(request_id, 'missing key')
        try:
            code = getBackend().checkLoginQRCode(key)
            result: dict[str, Any] = {'code': int(code)}
            if code == 803:
                from core.config import encryptSecret, saveConfig

                cfg = ctx.config
                cfg.session = encryptSecret(getBackend().dumpSession())
                cfg.login_status = getBackend().getCurrentLoginStatus()
                cfg.login_method = 'QR code'
                saveConfig()
                result['logged_in'] = True
            return encode_response(request_id, result)
        except Exception as exc:
            return encode_error(request_id, f'check qr code failed: {exc}')

    if method == 'login_cellphone_send':
        from core.backend import getBackend

        phone = str(params.get('phone') or '').strip()
        if not phone:
            return encode_error(request_id, 'missing phone')
        try:
            ok = getBackend().sendCellphoneVerificationCode(phone)
            return encode_response(request_id, {'ok': bool(ok)})
        except Exception as exc:
            return encode_error(request_id, f'send code failed: {exc}')

    if method == 'login_cellphone_verify':
        from core.backend import getBackend

        phone = str(params.get('phone') or '').strip()
        captcha = str(params.get('code') or '').strip()
        if not phone or not captcha:
            return encode_error(request_id, 'missing phone or code')
        try:
            from core.config import encryptSecret, saveConfig

            snapshot = getBackend().loginViaCellphone(phone, captcha)
            cfg = ctx.config
            cfg.session = encryptSecret(snapshot.session)
            cfg.login_status = snapshot.login_status
            cfg.login_method = 'cell phone'
            saveConfig()
            return encode_response(request_id, {'ok': True})
        except Exception as exc:
            return encode_error(request_id, f'cellphone login failed: {exc}')

    if method == 'login_cookie':
        from core.backend import getBackend

        cookie = str(params.get('cookie') or '').strip()
        if not cookie:
            return encode_error(request_id, 'missing cookie')
        try:
            from core.config import encryptSecret, saveConfig

            snapshot = getBackend().loginViaCookie(cookie)
            cfg = ctx.config
            cfg.session = encryptSecret(snapshot.session)
            cfg.login_status = snapshot.login_status
            cfg.login_method = 'cookie'
            saveConfig()
            return encode_response(request_id, {'ok': True})
        except Exception as exc:
            return encode_error(request_id, f'cookie login failed: {exc}')

    if method == 'logout':
        from core.backend import getBackend

        try:
            getBackend().logout()
            cfg = ctx.config
            cfg.session = None
            cfg.login_status = None
            cfg.login_method = None
            from core.config import saveConfig

            saveConfig()
            return encode_response(request_id, {'ok': True})
        except Exception as exc:
            return encode_error(request_id, f'logout failed: {exc}')

    if method == 'login_email':
        from core.backend import getBackend

        email = str(params.get('email') or '').strip()
        password = str(params.get('password') or '')
        if not email or not password:
            return encode_error(request_id, 'missing email or password')
        try:
            from core.config import encryptSecret, saveConfig

            snapshot = getBackend().loginViaEmail(email, password)
            cfg = ctx.config
            cfg.session = encryptSecret(snapshot.session)
            cfg.login_status = snapshot.login_status
            cfg.login_method = 'email'
            saveConfig()
            return encode_response(request_id, {'ok': True})
        except Exception as exc:
            return encode_error(request_id, f'email login failed: {exc}')

    if method == 'register_cellphone':
        from core.backend import getBackend

        phone = str(params.get('phone') or '').strip()
        captcha = str(params.get('code') or '').strip()
        nickname = str(params.get('nickname') or '').strip()
        password = str(params.get('password') or '')
        if not phone or not captcha or not nickname or not password:
            return encode_error(request_id, 'missing phone/code/nickname/password')
        try:
            result = getBackend().registerViaCellphone(
                phone, captcha, nickname, password
            )
            return encode_response(
                request_id, {'code': int(result.get('code', 0))}
            )
        except Exception as exc:
            return encode_error(request_id, f'register failed: {exc}')

    if method == 'cellphone_registered':
        from core.backend import getBackend

        phone = str(params.get('phone') or '').strip()
        if not phone:
            return encode_error(request_id, 'missing phone')
        try:
            result = getBackend().checkCellphoneRegistered(phone)
            registered = bool((result.get('exist') or False))
            return encode_response(request_id, {'registered': registered})
        except Exception as exc:
            return encode_error(request_id, f'check registered failed: {exc}')

    if method == 'refresh_login_token':
        from core.backend import getBackend

        try:
            result = getBackend().refreshLoginToken()
            return encode_response(request_id, {'ok': bool(result.get('code') == 200)})
        except Exception as exc:
            return encode_error(request_id, f'refresh token failed: {exc}')

    if method == 'daily_signin':
        from core.backend import getBackend

        try:
            dtype = 1 if params.get('dtype') == 'web' else 0
            result = getBackend().dailySignin(dtype)
            return encode_response(
                request_id, {'code': int(result.get('code', 0))}
            )
        except Exception as exc:
            return encode_error(request_id, f'daily signin failed: {exc}')

    if method == 'user_subs':
        from core.backend import getBackend

        try:
            sub_type = params.get('type') or 'artist'
            if sub_type == 'album':
                result = getBackend().getUserAlbumSubs()
            else:
                result = getBackend().getUserArtistSubs()
            # 兼容 data 为 list(直接是子项) 或 dict(含 artists/albums 子键)。
            data = result.get('data')
            if isinstance(data, dict):
                items = (
                    data.get('albums')
                    or data.get('artists')
                    or data.get('data')
                    or []
                )
            else:
                items = data if isinstance(data, list) else []
            if not isinstance(items, list):
                items = []
            return encode_response(
                request_id,
                {
                    'items': [
                        {
                            'id': str(item.get('id', '')),
                            'name': str(item.get('name', '')),
                            'cover_url': _https(
                                str(
                                    item.get('picUrl')
                                    or (item.get('album') or {}).get('picUrl', '')
                                    or item.get('avatar', '')
                                )
                            ),
                        }
                        for item in items
                        if isinstance(item, dict)
                    ],
                    'type': sub_type,
                },
            )
        except Exception as exc:
            return encode_error(request_id, f'get user subs failed: {exc}')

    if method == 'cloud_drive':
        from core.backend import getBackend

        try:
            limit = max(1, min(100, int(params.get('limit') or 30)))
            offset = max(0, int(params.get('offset') or 0))
            result = getBackend().getCloudDriveSongs(limit, offset)
            # 兼容 data 为 list(文件列表) 或 dict(含 files 子键) 两种返回。
            data = result.get('data')
            if isinstance(data, dict):
                files = (
                    data.get('files')
                    or data.get('data')
                    or data.get('songs')
                    or []
                )
            else:
                files = data if isinstance(data, list) else []
            if not isinstance(files, list):
                files = []
            return encode_response(
                request_id,
                {
                    'items': [
                        {
                            'id': str(
                                f.get('songId')
                                or (f.get('simpleSong') or {}).get('id', '')
                                or ''
                            ),
                            'name': str(
                                f.get('songName')
                                or (f.get('simpleSong') or {}).get('name', '')
                                or ''
                            ),
                            'artist': str(
                                f.get('artist')
                                or ((f.get('simpleSong') or {}).get('ar') or [{}])[0]
                                .get('name', '')
                                or ''
                            ),
                            'album': str(
                                f.get('album')
                                or (f.get('simpleSong') or {}).get('al', {})
                                .get('name', '')
                                or ''
                            ),
                            'cover_url': _https(
                                str(
                                    ((f.get('simpleSong') or {}).get('al') or {})
                                    .get('picUrl', '')
                                )
                            ),
                        }
                        for f in files
                        if isinstance(f, dict)
                    ],
                },
            )
        except Exception as exc:
            return encode_error(request_id, f'get cloud drive failed: {exc}')

    if method == 'upload_cloud_song':
        from core.backend import getBackend

        file_path = str(params.get('file_path') or '')
        if not file_path:
            return encode_error(request_id, 'missing file_path')
        try:
            result = getBackend().uploadCloudSong(
                file_path,
                song=str(params.get('song') or ''),
                artist=str(params.get('artist') or ''),
                album=str(params.get('album') or ''),
                bitrate=int(params.get('bitrate') or 128),
            )
            return encode_response(
                request_id, {'song_id': result['song_id'], 'ok': True}
            )
        except Exception as exc:
            return encode_error(request_id, f'upload cloud song failed: {exc}')

    if method == 'get_album_comments':
        from core.backend import getBackend

        album_id = str(params.get('album_id') or '')
        if not album_id:
            return encode_error(request_id, 'missing album_id')
        try:
            offset = max(0, int(params.get('offset') or 0))
            limit = max(1, min(50, int(params.get('limit') or 20)))
            result = getBackend().getAlbumComments(album_id, offset, limit)
            comments = result.get('comments') or []
            return encode_response(
                request_id,
                {
                    'total': int(result.get('total', 0) or 0),
                    'comments': [
                        {
                            'id': str(c.get('commentId', '')),
                            'content': str(c.get('content', '')),
                            'liked_count': int(c.get('likedCount', 0) or 0),
                            'time': str(c.get('time', 0)),
                            'user': {
                                'id': str((c.get('user') or {}).get('userId', '')),
                                'avatar_url': str(
                                    (c.get('user') or {}).get('avatarUrl', '')
                                ),
                                'nickname': str(
                                    (c.get('user') or {}).get('nickname', '')
                                ),
                            },
                        }
                        for c in comments
                    ],
                },
            )
        except Exception as exc:
            return encode_error(request_id, f'get album comments failed: {exc}')

    if method == 'get_playlist_comments':
        from core.backend import getBackend

        playlist_id = str(params.get('playlist_id') or '')
        if not playlist_id:
            return encode_error(request_id, 'missing playlist_id')
        try:
            offset = max(0, int(params.get('offset') or 0))
            limit = max(1, min(50, int(params.get('limit') or 20)))
            result = getBackend().getPlaylistComments(playlist_id, offset, limit)
            comments = result.get('comments') or []
            return encode_response(
                request_id,
                {
                    'total': int(result.get('total', 0) or 0),
                    'comments': [
                        {
                            'id': str(c.get('commentId', '')),
                            'content': str(c.get('content', '')),
                            'liked_count': int(c.get('likedCount', 0) or 0),
                            'time': str(c.get('time', 0)),
                            'user': {
                                'id': str((c.get('user') or {}).get('userId', '')),
                                'avatar_url': str(
                                    (c.get('user') or {}).get('avatarUrl', '')
                                ),
                                'nickname': str(
                                    (c.get('user') or {}).get('nickname', '')
                                ),
                            },
                        }
                        for c in comments
                    ],
                },
            )
        except Exception as exc:
            return encode_error(request_id, f'get playlist comments failed: {exc}')

    if method == 'get_mv':
        from core.backend import getBackend

        mv_id = str(params.get('mv_id') or '')
        if not mv_id:
            return encode_error(request_id, 'missing mv_id')
        try:
            detail = getBackend().getMVDetail(mv_id)
            mv = detail.get('data') or {}
            resource = getBackend().getMVResource(mv_id, 1080)
            urls = resource.get('data') or {}
            return encode_response(
                request_id,
                {
                    'id': str(mv.get('id', '')),
                    'name': str(mv.get('name', '')),
                    'artist': str(mv.get('artistName', '')),
                    'duration': int(mv.get('duration', 0) or 0),
                    'cover_url': _https(str(mv.get('cover', '') or '')),
                    'play_url': _https(
                        str((urls.get('url') or '')) if isinstance(urls, dict) else ''
                    ),
                },
            )
        except Exception as exc:
            return encode_error(request_id, f'get mv failed: {exc}')

    if method == 'get_mv_comments':
        from core.backend import getBackend

        mv_id = str(params.get('mv_id') or '')
        if not mv_id:
            return encode_error(request_id, 'missing mv_id')
        try:
            offset = max(0, int(params.get('offset') or 0))
            limit = max(1, min(50, int(params.get('limit') or 20)))
            result = getBackend().getMVComments(mv_id, offset, limit)
            comments = result.get('comments') or []
            return encode_response(
                request_id,
                {
                    'total': int(result.get('total', 0) or 0),
                    'comments': [
                        {
                            'id': str(c.get('commentId', '')),
                            'content': str(c.get('content', '')),
                            'liked_count': int(c.get('likedCount', 0) or 0),
                            'user': {
                                'id': str((c.get('user') or {}).get('userId', '')),
                                'nickname': str(
                                    (c.get('user') or {}).get('nickname', '')
                                ),
                            },
                        }
                        for c in comments
                    ],
                },
            )
        except Exception as exc:
            return encode_error(request_id, f'get mv comments failed: {exc}')

    if method == 'radio_control':
        from core.backend import getBackend

        action = str(params.get('action') or '')
        song_id = str(params.get('song_id') or '')
        if not action or not song_id:
            return encode_error(request_id, 'missing action or song_id')
        try:
            like = bool(params.get('like', True))
            result = getBackend().radioControl(action, song_id, like)
            return encode_response(
                request_id, {'ok': bool(result.get('code', 0) == 200)}
            )
        except Exception as exc:
            return encode_error(request_id, f'radio control failed: {exc}')

    if method == 'match_track_fp':
        from core.backend import getBackend

        audio_fp = str(params.get('audio_fp') or '')
        if not audio_fp:
            return encode_error(request_id, 'missing audio_fp')
        try:
            duration = float(params.get('duration') or 0)
            result = getBackend().matchTrackByFP(audio_fp, duration)
            return encode_response(
                request_id, {'result': result}
            )
        except Exception as exc:
            return encode_error(request_id, f'match track fp failed: {exc}')

    if method == 'track_audio_v1':
        from core.backend import getBackend

        song_id = str(params.get('song_id') or '')
        if not song_id:
            return encode_error(request_id, 'missing song_id')
        try:
            level = str(params.get('level') or 'standard')
            result = getBackend().getTrackAudioV1(song_id, level)
            data = result.get('data') or []
            first = data[0] if isinstance(data, list) and data else {}
            return encode_response(
                request_id,
                {
                    'url': _https(str(first.get('url', ''))),
                    'size': int(first.get('size', 0) or 0),
                    'level': str(first.get('level', '')),
                },
            )
        except Exception as exc:
            return encode_error(request_id, f'track audio v1 failed: {exc}')

    if method == 'track_download_url':
        from core.backend import getBackend

        song_id = str(params.get('song_id') or '')
        if not song_id:
            return encode_error(request_id, 'missing song_id')
        try:
            bitrate = int(params.get('bitrate') or 320000)
            result = getBackend().getTrackDownloadURL(song_id, bitrate)
            data = result.get('data') or []
            first = data[0] if isinstance(data, list) and data else {}
            return encode_response(
                request_id,
                {
                    'url': _https(str(first.get('url', ''))),
                    'size': int(first.get('size', 0) or 0),
                },
            )
        except Exception as exc:
            return encode_error(request_id, f'track download url failed: {exc}')

    if method == 'like_track':
        from core.backend import getBackend

        song_id = str(params.get('song_id') or '')
        if not song_id:
            return encode_error(request_id, 'missing song_id')
        try:
            like = bool(params.get('like', True))
            result = getBackend().likeTrack(song_id, like)
            return encode_response(
                request_id, {'ok': bool(result.get('code', 0) == 200)}
            )
        except Exception as exc:
            return encode_error(request_id, f'like track failed: {exc}')

    if method == 'get_track_comments':
        from core.backend import getBackend

        song_id = str(params.get('song_id') or '')
        if not song_id:
            return encode_error(request_id, 'missing song_id')
        try:
            offset = max(0, int(params.get('offset') or 0))
            limit = max(1, min(50, int(params.get('limit') or 20)))
            result = getBackend().getTrackComments(song_id, offset, limit)
            comments = result.get('comments') or []
            return encode_response(
                request_id,
                {
                    'total': int(result.get('total', 0) or 0),
                    'comments': [
                        {
                            'id': str(c.get('commentId', '')),
                            'content': str(c.get('content', '')),
                            'liked_count': int(c.get('likedCount', 0) or 0),
                            'user': {
                                'id': str((c.get('user') or {}).get('userId', '')),
                                'nickname': str(
                                    (c.get('user') or {}).get('nickname', '')
                                ),
                            },
                        }
                        for c in comments
                    ],
                },
            )
        except Exception as exc:
            return encode_error(request_id, f'get track comments failed: {exc}')

    if method == 'login_type_switch':
        from core.backend import getBackend

        try:
            result = getBackend().loginTypeSwitch()
            return encode_response(
                request_id, {'ok': bool(result.get('code', 0) == 200)}
            )
        except Exception as exc:
            return encode_error(request_id, f'login type switch failed: {exc}')

    if method == 'track_download_url_v1':
        from core.backend import getBackend

        song_id = str(params.get('song_id') or '')
        if not song_id:
            return encode_error(request_id, 'missing song_id')
        try:
            level = str(params.get('level') or 'standard')
            result = getBackend().getTrackDownloadURLV1(song_id, level)
            data = result.get('data') or []
            first = data[0] if isinstance(data, list) and data else {}
            return encode_response(
                request_id,
                {
                    'url': _https(str(first.get('url', ''))),
                    'size': int(first.get('size', 0) or 0),
                    'level': str(first.get('level', '')),
                },
            )
        except Exception as exc:
            return encode_error(request_id, f'track download url v1 failed: {exc}')

    if method == 'cloud_item_info':
        from core.backend import getBackend

        song_id = str(params.get('song_id') or '')
        if not song_id:
            return encode_error(request_id, 'missing song_id')
        try:
            result = getBackend().getCloudDriveItemInfo(song_id)
            return encode_response(request_id, {'result': result})
        except Exception as exc:
            return encode_error(request_id, f'cloud item info failed: {exc}')

    if method == 'rectify_cloud_song':
        from core.backend import getBackend

        old_song_id = str(params.get('old_song_id') or '')
        new_song_id = str(params.get('new_song_id') or '')
        if not old_song_id or not new_song_id:
            return encode_error(request_id, 'missing old_song_id or new_song_id')
        try:
            result = getBackend().rectifyCloudSong(old_song_id, new_song_id)
            return encode_response(
                request_id, {'ok': bool(result.get('code', 0) == 200)}
            )
        except Exception as exc:
            return encode_error(request_id, f'rectify cloud song failed: {exc}')

    if method == 'fm_more':
        from core.backend import getBackend

        try:
            limit = max(1, min(20, int(params.get('limit') or 3)))
            result = getBackend().getMoreRadioContent(limit)
            return encode_response(request_id, {'result': result})
        except Exception as exc:
            return encode_error(request_id, f'fm more failed: {exc}')

    if method == 'difm_playing':
        from core.backend import getBackend

        try:
            channel_id = int(params.get('channel_id') or 101)
            limit = max(1, min(50, int(params.get('limit') or 10)))
            result = getBackend().getDifmPlayingTracks(channel_id, limit)
            return encode_response(request_id, {'result': result})
        except Exception as exc:
            return encode_error(request_id, f'difm playing failed: {exc}')

    if method == 'difm_channels':
        from core.backend import getBackend

        try:
            result = getBackend().getDifmChannels()
            return encode_response(request_id, {'result': result})
        except Exception as exc:
            return encode_error(request_id, f'difm channels failed: {exc}')

    if method == 'difm_subscriptions':
        from core.backend import getBackend

        try:
            result = getBackend().getDifmSubscribedChannels()
            return encode_response(request_id, {'result': result})
        except Exception as exc:
            return encode_error(request_id, f'difm subscriptions failed: {exc}')

    if method == 'difm_subscribe':
        from core.backend import getBackend

        try:
            channel_id = int(params.get('channel_id') or 0)
            subscribe = bool(params.get('subscribe', True))
            result = getBackend().setDifmChannelSubscription(channel_id, subscribe)
            return encode_response(
                request_id, {'ok': bool(result.get('code', 0) == 200)}
            )
        except Exception as exc:
            return encode_error(request_id, f'difm subscribe failed: {exc}')

    if method == 'sports_fm':
        from core.backend import getBackend

        try:
            limit = max(1, min(20, int(params.get('limit') or 3)))
            bpm = max(30, min(200, int(params.get('bpm') or 50)))
            result = getBackend().getSportsFMRecommendations(limit, bpm)
            return encode_response(request_id, {'result': result})
        except Exception as exc:
            return encode_error(request_id, f'sports fm failed: {exc}')

    if method == 'sports_fm_status':
        from core.backend import getBackend

        try:
            result = getBackend().getCalculatedSportsFMStatus(
                distance=int(params.get('distance') or 0),
                maxbpm=int(params.get('maxbpm') or 0),
                time=int(params.get('time') or 0),
                song_list=params.get('song_list'),
                steps=int(params.get('steps') or 0),
                bpm=int(params.get('bpm') or 0),
            )
            return encode_response(request_id, {'result': result})
        except Exception as exc:
            return encode_error(request_id, f'sports fm status failed: {exc}')

    if method == 'zone_fm':
        from core.backend import getBackend

        try:
            zone = str(params.get('zone') or 'CLASSICAL')
            limit = max(1, min(20, int(params.get('limit') or 3)))
            result = getBackend().getZoneFMInfo(zone, limit)
            return encode_response(request_id, {'result': result})
        except Exception as exc:
            return encode_error(request_id, f'zone fm failed: {exc}')

    if method == 'zone_fm_skip':
        from core.backend import getBackend

        song_id = str(params.get('song_id') or '')
        if not song_id:
            return encode_error(request_id, 'missing song_id')
        try:
            zone = str(params.get('zone') or 'CLASSICAL')
            result = getBackend().skipZoneFMTrack(song_id, zone)
            return encode_response(
                request_id, {'ok': bool(result.get('code', 0) == 200)}
            )
        except Exception as exc:
            return encode_error(request_id, f'zone fm skip failed: {exc}')

    if method == 'login_anonymous':
        from core.backend import getBackend

        try:
            getBackend().loginViaAnonymousAccount()
            return encode_response(request_id, {'ok': True})
        except Exception as exc:
            return encode_error(request_id, f'anonymous login failed: {exc}')

    if method == 'get_artist':
        from pyncm import apis

        artist_id = str(params.get('artist_id') or '')
        if not artist_id:
            return encode_error(request_id, 'missing artist_id')
        try:
            detail = apis.artist.getArtistDetails(artist_id)
            artist = (detail.get('data') or {}).get('artist') or {}
            tracks = apis.artist.getArtistTracks(artist_id, limit=50)
            albums = apis.artist.getArtistAlbums(artist_id, limit=20)
            return encode_response(
                request_id,
                {
                    'id': str(artist.get('id', '')),
                    'name': str(artist.get('name', '')),
                    'avatar_url': _https(str(artist.get('avatar', '') or '')),
                    'brief': str(artist.get('briefDesc', '') or ''),
                    'music_count': int(artist.get('musicSize', 0) or 0),
                    'album_count': int(artist.get('albumSize', 0) or 0),
                    'hot_songs': [
                        _api_song_to_dict(s) for s in (tracks.get('songs') or [])
                    ],
                    'albums': [
                        {
                            'id': str(a.get('id', '')),
                            'name': str(a.get('name', '')),
                            'cover_url': str(a.get('picUrl', '') or ''),
                            'song_count': int(a.get('size', 0) or 0),
                        }
                        for a in (albums.get('hotAlbums') or [])
                    ],
                },
            )
        except Exception as exc:
            return encode_error(request_id, f'get artist failed: {exc}')

    if method == 'get_album_tracks':
        from pyncm import apis

        album_id = str(params.get('album_id') or '')
        if not album_id:
            return encode_error(request_id, 'missing album_id')
        try:
            info = apis.album.getAlbumInfo(album_id)
            album = info.get('album') or {}
            return encode_response(
                request_id,
                {
                    'id': str(album.get('id', '')),
                    'name': str(album.get('name', '')),
                    'cover_url': str(album.get('picUrl', '') or ''),
                    'artist': str(
                        ((album.get('artist') or {}).get('name') or '')
                    ),
                    'songs': [
                        _api_song_to_dict(s) for s in (info.get('songs') or [])
                    ],
                },
            )
        except Exception as exc:
            return encode_error(request_id, f'get album tracks failed: {exc}')

    if method == 'get_user':
        from pyncm import apis

        user_id = str(params.get('user_id') or '')
        if not user_id:
            return encode_error(request_id, 'missing user_id')
        try:
            profile = (apis.user.getUserDetail(user_id) or {}).get('profile') or {}
            playlists = (
                apis.user.getUserPlaylists(user_id) or {}
            ).get('playlist') or []
            return encode_response(
                request_id,
                {
                    'user_id': str(profile.get('userId', '')),
                    'nickname': str(profile.get('nickname', '')),
                    'avatar_url': _https(
                        str(profile.get('avatarUrl', '') or '')
                    ),
                    'signature': str(profile.get('signature', '') or ''),
                    'event_count': int(profile.get('eventCount', 0) or 0),
                    'playlists': [
                        _cloud_folder_from_api(p) for p in playlists
                    ],
                },
            )
        except Exception as exc:
            return encode_error(request_id, f'get user failed: {exc}')

    if method == 'download_song':
        from core.backend import getBackend

        song_id = str(params.get('song_id') or '')
        if not song_id:
            return encode_error(request_id, 'missing song_id')
        try:
            bitrate = int(params.get('bitrate') or 3200000)
            audio = getBackend().getTrackAudio(song_id, bitrate)
            return encode_response(
                request_id,
                {
                    'url': _https(str(audio.url)),
                    'size': int(getattr(audio, 'size', 0) or 0),
                },
            )
        except Exception as exc:
            return encode_error(request_id, f'download song failed: {exc}')

    if method == 'play_control':
        command = params.get('command')
        player = ctx.player
        manager = ctx.playing_manager
        if player is None or manager is None:
            return encode_error(request_id, 'backend not fully initialized')
        if command == 'toggle':
            if player.isPlaying():
                player.pause()
            else:
                player.resume()
            event_bus.emit(PLAY_STATE_CHANGED, player.isPlaying())
        elif command == 'next':
            event_bus.emit(PLAYNEXT)
        elif command == 'previous':
            event_bus.emit(PLAYLAST)
        elif command == 'seek':
            try:
                position = float(params.get('position', 0.0))
            except (TypeError, ValueError):
                return encode_error(request_id, 'invalid position')
            player.setPosition(max(0.0, position))
        elif command == 'volume':
            try:
                volume = float(params.get('volume', 1.0))
            except (TypeError, ValueError):
                return encode_error(request_id, 'invalid volume')
            player.setVolume(max(0.0, min(1.0, volume)))
        else:
            return encode_error(request_id, f'unknown play_control: {command}')
        return encode_response(request_id, {'ok': True})

    if method == 'shutdown':
        # 持久化播放状态,下次启动自动恢复。
        player = ctx.player
        manager = ctx.playing_manager
        cfg = ctx.config
        if player is not None and manager is not None and cfg is not None:
            try:
                cfg.last_playing_time = float(player.getPosition())
                cfg.last_playing_index = manager.current_index
                cfg.last_playlist = manager.playlist.copy()
                from core.config import saveConfig

                saveConfig()
            except Exception:
                pass
        service.shutdown()
        return encode_response(request_id, {'shutdown': True})

    return encode_error(request_id, f'unknown method: {method}', code=404)


# ---------------------------------------------------------------------------
# TCP RPC 服务器(带事件推送)
# ---------------------------------------------------------------------------

def _make_tcp_server(
    service: CoreBackendService,
    shutdown_event: threading.Event,
    port: int = DEFAULT_TCP_PORT,
) -> socketserver.ThreadingTCPServer:
    """换行分隔 JSON 的 TCP RPC 服务器 + 事件总线推送。

    与 stdin/stdout 通道共享 ``_handle_request``;事件总线上的核心事件
    (歌曲变化、播放状态、播放列表、歌词)会推送给所有已连接客户端。
    """

    clients: set[Any] = set()
    clients_lock = threading.Lock()

    def _broadcast(event: str, data: dict[str, Any]) -> None:
        payload = (json.dumps({'event': event, 'data': data}) + '\n').encode(
            'utf-8'
        )
        with clients_lock:
            dead: list[Any] = []
            for writer in list(clients):
                if not writer.send(payload):
                    dead.append(writer)
            for writer in dead:
                clients.discard(writer)

    class _ClientWriter:
        def __init__(self, handler: socketserver.StreamRequestHandler) -> None:
            self._handler = handler
            self._write_lock = threading.Lock()

        def send(self, text: bytes | str) -> bool:
            try:
                with self._write_lock:
                    if isinstance(text, str):
                        text = text.encode('utf-8')
                    self._handler.wfile.write(text)
                    self._handler.wfile.flush()
                return True
            except OSError:
                return False

    class _JsonHandler(socketserver.StreamRequestHandler):
        def handle(self) -> None:  # noqa: D401
            writer = _ClientWriter(self)
            with clients_lock:
                clients.add(writer)
            try:
                while True:
                    line = self.rfile.readline()
                    if not line:
                        break
                    line = line.decode('utf-8', errors='replace').strip()
                    if not line:
                        continue
                    request = parse_request(line)
                    if request is None:
                        writer.send(encode_error(None, 'invalid JSON request'))
                        continue
                    print(f'[backend] rpc {request.get("method")} start', file=sys.stderr, flush=True)
                    response = _handle_request(service, request)
                    print(f'[backend] rpc {request.get("method")} done', file=sys.stderr, flush=True)
                    writer.send(response)
                    print(f'[backend] rpc {request.get("method")} sent', file=sys.stderr, flush=True)
                    if request.get('method') == 'shutdown':
                        shutdown_event.set()
                        break
            finally:
                with clients_lock:
                    clients.discard(writer)

    # 事件推送订阅。
    def _on_song_changed(song: Any) -> None:
        _broadcast('SONG_CHANGED', {'song': _song_to_dict(song)})

    def _on_play_state_changed(playing: Any) -> None:
        _broadcast('PLAY_STATE_CHANGED', {'playing': bool(playing)})

    def _on_playlist_changed(*_: Any) -> None:
        _broadcast('PLAYLIST_CHANGED', {})

    def _on_lyrics_updated(song: Any) -> None:
        _broadcast(
            'PLAYBACK_LYRICS_UPDATED',
            {'song_id': str(getattr(song, 'id', ''))},
        )

    def _on_lyric_line_changed(*_: Any) -> None:
        _broadcast('LYRIC_LINE_CHANGED', {})

    event_bus.subscribe(SONG_CHANGED, _on_song_changed)
    event_bus.subscribe(PLAY_STATE_CHANGED, _on_play_state_changed)
    event_bus.subscribe(PLAYLIST_CHANGED, _on_playlist_changed)
    event_bus.subscribe(PLAYBACK_LYRICS_UPDATED, _on_lyrics_updated)
    event_bus.subscribe(LYRIC_LINE_CHANGED, _on_lyric_line_changed)

    try:
        server: socketserver.ThreadingTCPServer = socketserver.ThreadingTCPServer(
            ('127.0.0.1', port),
            _JsonHandler,
        )
    except OSError as exc:
        print(
            f'[backend] error: 端口 {port} 已被占用,请先停止旧内核进程 '
            f'或使用 --port 指定其他端口 ({exc})',
            file=sys.stderr,
        )
        raise
    server.daemon_threads = True
    server.allow_reuse_address = True
    return server


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description='SouthsideMusic core backend')
    parser.add_argument(
        '--port',
        type=int,
        default=DEFAULT_TCP_PORT,
        help=f'TCP RPC 端口(默认 {DEFAULT_TCP_PORT})',
    )
    parser.add_argument(
        '--no-tcp',
        action='store_true',
        help='不启动 TCP RPC(由前端子进程经 stdin/stdout 通信)',
    )
    args = parser.parse_args()

    shutdown_event = threading.Event()

    service = CoreBackendService(context=CoreContext())
    service.initialize(
        app=None,
        progress=lambda message: print(f'[backend] {message}', file=sys.stderr),
    )
    service.start()

    # 恢复上次播放队列与进度(对齐 Qt 版 last_playlist 持久化)。
    global _RESTORED_POSITION
    _cfg = service.context.config
    _manager = service.context.playing_manager
    if _cfg is not None and _manager is not None and _cfg.last_playlist:
        try:
            _manager.setPlaylist(list(_cfg.last_playlist))
            if 0 <= _cfg.last_playing_index < len(_cfg.last_playlist):
                _manager.current_index = _cfg.last_playing_index
            _RESTORED_POSITION = float(_cfg.last_playing_time or 0)
            print(
                f'[backend] restored playlist ({len(_cfg.last_playlist)} '
                f'songs, index={_cfg.last_playing_index}, '
                f'position={_RESTORED_POSITION:.1f}s)',
                file=sys.stderr,
            )
        except Exception as exc:
            print(f'[backend] restore playlist failed: {exc}', file=sys.stderr)

    if not args.no_tcp:
        tcp_server = _make_tcp_server(service, shutdown_event, port=args.port)
        tcp_thread = threading.Thread(
            target=tcp_server.serve_forever,
            name='backend-tcp',
            daemon=True,
        )
        tcp_thread.start()
        print(
            f'[backend] tcp rpc listening on 127.0.0.1:{args.port}',
            file=sys.stderr,
        )

    def _stdin_loop() -> None:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            request = parse_request(line)
            if request is None:
                print(encode_error(None, 'invalid JSON request'), flush=True)
                continue
            response = _handle_request(service, request)
            print(response, flush=True)
            if request.get('method') == 'shutdown':
                shutdown_event.set()
                break

    thread = threading.Thread(target=_stdin_loop, name='backend-stdin', daemon=True)
    thread.start()

    shutdown_event.wait()
    if not args.no_tcp:
        tcp_server.shutdown()
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
