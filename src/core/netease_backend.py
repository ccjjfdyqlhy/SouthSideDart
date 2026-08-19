from __future__ import annotations

from datetime import datetime
import json
import logging
import time
import urllib.parse
import uuid
from typing import Any, Literal

import pyncm
from pyncm import apis

from core.models import (
    AlbumInfo,
    ArtistInfo,
    BackendAccountInfo,
    BackendSessionSnapshot,
    BeReplyComment,
    CloudFolderInfo,
    Comment,
    CommentInfo,
    LoginQRCodeInfo,
    MusicServiceBackend,
    PrivilegeInfo,
    SearchSongInfo,
    SongInfo,
    SongStorable,
    TrackAudioInfo,
    TrackDetailInfo,
    TrackLyricsInfo,
    SearchCloudFolderInfo,
    UserInfo,
    getCachedHashes,
)

_logger = logging.getLogger(__name__)


class NeteaseCloudMusicBackend(MusicServiceBackend):
    def _sessionSnapshot(self) -> BackendSessionSnapshot:
        return BackendSessionSnapshot(
            session=self.dumpSession(),
            login_status=self.getCurrentLoginStatus(),
        )

    def getCurrentLoginStatus(self) -> dict:
        status = apis.login.getCurrentLoginStatus()
        assert isinstance(status, dict), 'Invalid login status response'
        return status

    def writeLoginInfo(self, login_status: dict | None) -> None:
        if login_status is None:
            return
        apis.login.writeLoginInfo(login_status)

    def currentSessionIsAnonymous(self) -> bool:
        return bool(pyncm.getCurrentSession().is_anonymous)

    def loadSession(self, session: str) -> None:
        pyncm.setCurrentSession(pyncm.loadSessionFromString(session))

    def dumpSession(self) -> str:
        return pyncm.dumpSessionAsString(pyncm.getCurrentSession())

    def loginViaAnonymousAccount(self) -> BackendSessionSnapshot:
        apis.login.loginViaAnonymousAccount()
        return self._sessionSnapshot()

    def setRandomDeviceId(self) -> None:
        session = pyncm.getCurrentSession()
        session.deviceId = uuid.uuid4().hex
        pyncm.setCurrentSession(session)

    def getSessionBindings(self) -> list[dict[str, Any]]:
        bindings = pyncm.getCurrentSession().bindings
        return [binding for binding in bindings if isinstance(binding, dict)]

    def refreshSessionIfNeeded(
        self, expiry_window_seconds: int = 300
    ) -> BackendSessionSnapshot | None:
        session = pyncm.getCurrentSession()
        bindings = session.bindings
        if not bindings:
            return None

        now = time.time()
        need_refresh = any(
            binding.get('expiresIn', 0) - now <= expiry_window_seconds
            for binding in bindings
            if isinstance(binding, dict)
        )
        if not need_refresh:
            return None

        apis.login.loginRefreshToken()
        return self._sessionSnapshot()

    def getAccountInfo(self) -> BackendAccountInfo:
        session = pyncm.getCurrentSession()
        login_status = self.getCurrentLoginStatus()
        user_id: int | str | None = None
        avatar_url = ''
        nickname = ''

        if isinstance(login_status, dict):
            account = login_status.get('account')
            if isinstance(account, dict):
                user_id = account.get('id')
                account_name = account.get('userName') or account.get('nickname')
                if isinstance(account_name, str) and account_name.strip():
                    nickname = account_name.strip()

            profile = login_status.get('profile')
            if isinstance(profile, dict):
                profile_name = profile.get('nickname')
                if isinstance(profile_name, str) and profile_name.strip():
                    nickname = profile_name.strip()
                profile_avatar = profile.get('avatarUrl')
                if isinstance(profile_avatar, str):
                    avatar_url = profile_avatar

        if user_id is not None:
            detail = apis.user.getUserDetail(user_id)
            if isinstance(detail, dict):
                profile = detail.get('profile')
                if isinstance(profile, dict):
                    detail_name = profile.get('nickname')
                    if isinstance(detail_name, str) and detail_name.strip():
                        nickname = detail_name.strip()
                    detail_avatar = profile.get('avatarUrl')
                    if isinstance(detail_avatar, str):
                        avatar_url = detail_avatar

        session_name = session.nickname
        if isinstance(session_name, str) and session_name.strip():
            nickname = session_name.strip()

        return BackendAccountInfo(
            user_id=user_id,
            nickname=nickname,
            avatar_url=avatar_url,
            logged_in=self.loggedIn(),
            vip_type=self.getUserVipType(),
        )

    def logout(self) -> BackendSessionSnapshot:
        apis.login.loginLogout()
        pyncm.setCurrentSession(pyncm.createNewSession())
        return BackendSessionSnapshot(session=self.dumpSession(), login_status=None)

    def createLoginQRCode(self) -> LoginQRCodeInfo:
        data = apis.login.loginQrcodeUnikey()
        assert isinstance(data, dict), 'Invalid QR login key response'
        key = str(data['unikey'])
        return LoginQRCodeInfo(key=key, url=apis.login.getLoginQRCodeUrl(key))

    def checkLoginQRCode(self, key: str) -> int:
        response = apis.login.loginQrcodeCheck(key)
        assert isinstance(response, dict), 'Invalid QR login check response'
        code = int(response.get('code', 0))
        if code == 803:
            self.writeLoginInfo(self.getCurrentLoginStatus())
        return code

    def sendCellphoneVerificationCode(self, phone: str, ctcode: int = 86) -> bool:
        response = apis.login.setSendRegisterVerificationCodeViaCellphone(phone, ctcode)
        assert isinstance(response, dict), 'Invalid cellphone code response'
        return response.get('code', 0) == 200

    def verifyCellphoneVerificationCode(
        self, phone: str, captcha: str, ctcode: int = 86
    ) -> bool:
        response = apis.login.getRegisterVerificationStatusViaCellphone(
            phone, captcha, ctcode
        )
        assert isinstance(response, dict), 'Invalid cellphone verify response'
        return response.get('code', 0) == 200

    def loginViaCellphone(
        self, phone: str, captcha: str, ctcode: int = 86
    ) -> BackendSessionSnapshot:
        apis.login.loginViaCellphone(phone, captcha=captcha, ctcode=ctcode)
        return self._sessionSnapshot()

    def loginViaCookie(self, music_u: str) -> BackendSessionSnapshot:
        apis.login.loginViaCookie(MUSIC_U=music_u)
        return self._sessionSnapshot()

    def _songStorableFromApiSong(self, song: dict[str, Any]) -> SongStorable | None:
        if not song:
            return None
        song_id = song.get('id')
        if song_id is None:
            return None
        artists_raw = song.get('ar', song.get('artists', []))
        cached = getCachedHashes(str(song_id))
        storable = SongStorable(
            info=SongInfo(
                name=str(song.get('name', '')),
                artists=[
                    ArtistInfo(id=obj.get('id', 0), name=obj.get('name', ''))
                    for obj in artists_raw
                    if isinstance(obj, dict)
                ],
                id=str(song_id),
                privilege=int(song.get('fee', -1) or -1),
                duration=int(song.get('dt', song.get('duration', 0)) or 0),
            ),
            image=None,
            image_cache_hash=cached.get('image_cache_hash', ''),
            content_cache_hash=cached.get('content_cache_hash', ''),
        )
        # 携带专辑/封面信息(供 UI 直接显示真实封面)。
        album = song.get('al') or song.get('album') or {}
        storable.album_name = str(
            album.get('name', '') if isinstance(album, dict) else album
        )
        storable.cover_url = str(
            album.get('picUrl', '') if isinstance(album, dict) else ''
        )
        return storable

    def _songsFromApiSongs(self, songs: object) -> list[SongStorable]:
        if not isinstance(songs, list):
            return []
        result: list[SongStorable] = []
        for song in songs:
            if not isinstance(song, dict):
                continue
            storable = self._songStorableFromApiSong(song)
            if storable is not None:
                result.append(storable)
        return result

    def _pcRecommendItems(self) -> list[dict[str, Any]]:
        response = apis.recommend.getPcRecommendResource()
        assert isinstance(response, dict), 'Invalid PC recommend response'
        assert response.get('code') == 200, f'API Error: {response}'
        data = response.get('data') or {}
        if not isinstance(data, dict):
            return []
        blocks = data.get('blocks') or []
        if not isinstance(blocks, list):
            return []

        result: list[dict[str, Any]] = []
        for block in blocks:
            if not isinstance(block, dict):
                continue
            block_data = block.get('blockData') or {}
            if not isinstance(block_data, dict):
                continue
            items = block_data.get('items') or []
            if not isinstance(items, list):
                continue
            result.extend(item for item in items if isinstance(item, dict))
        return result

    def _findPcRecommendItem(
        self,
        module_types: set[str],
        cover_texts: set[str],
        resource_types: set[str],
        position_codes: set[str],
    ) -> dict[str, Any] | None:
        for item in self._pcRecommendItems():
            module_type = str(item.get('moduleType') or '')
            cover_text = str(item.get('coverText') or '')
            resource_type = str(item.get('resourceType') or '')
            position_code = str(item.get('positionCode') or '')
            if module_type in module_types:
                return item
            if cover_text in cover_texts:
                return item
            if resource_type in resource_types:
                return item
            if position_code in position_codes:
                return item
        return None

    @staticmethod
    def _songIdsFromRecommendValue(value: object) -> list[str]:
        if value is None:
            return []
        if isinstance(value, int):
            return [str(value)]
        if isinstance(value, list):
            result: list[str] = []
            for item in value:
                result.extend(NeteaseCloudMusicBackend._songIdsFromRecommendValue(item))
            return list(dict.fromkeys(result))
        if not isinstance(value, str):
            return []

        text = value.strip()
        if not text:
            return []
        try:
            parsed = json.loads(text)
        except json.JSONDecodeError:
            return [text] if text.isdigit() else []
        return NeteaseCloudMusicBackend._songIdsFromRecommendValue(parsed)

    def _songIdsFromRecommendItem(self, item: dict[str, Any]) -> list[str]:
        result = self._songIdsFromRecommendValue(item.get('resourceId'))
        if result:
            return result

        target_url = item.get('targetUrl')
        if not isinstance(target_url, str):
            return []
        query = urllib.parse.parse_qs(urllib.parse.urlparse(target_url).query)
        result = []
        for value in query.get('sourceId', []):
            result.extend(self._songIdsFromRecommendValue(value))
        return list(dict.fromkeys(result))

    def searchSong(
        self, keywords: str, offset: int = 0, limit: int = 30
    ) -> list[SearchSongInfo]:
        resp = apis.cloudsearch.getSearchResult(
            keywords, stype=1, limit=limit, offset=offset
        )
        assert isinstance(resp, dict), 'Invalid search response'

        songs: list[SearchSongInfo] = []
        for songdict in resp.get('result', {}).get('songs', []):
            artists = [
                ArtistInfo(id=art.get('id', 0), name=art.get('name', ''))
                for art in songdict.get('ar', [])
            ]
            al = songdict.get('al', {})
            album = AlbumInfo(
                id=al.get('id', 0),
                name=al.get('name', ''),
                cover_url=al.get('picUrl', ''),
            )
            privilege_raw = songdict.get('privilege', {})
            privilege = PrivilegeInfo(
                fee=songdict.get('fee', 0),
                max_br=privilege_raw.get('maxbr', 0),
                is_vip_only=songdict.get('fee', 0) not in (0, 8),
            )
            songs.append(
                SearchSongInfo(
                    id=songdict['id'],
                    name=songdict['name'],
                    artists=artists,
                    album=album,
                    privilege=privilege,
                    duration=songdict.get('dt', 0),
                )
            )
        return songs

    def searchPlaylist(
        self, keywords: str, offset: int = 0, limit: int = 30
    ) -> list[SearchCloudFolderInfo]:
        resp = apis.cloudsearch.getSearchResult(
            keywords, stype=1000, limit=limit, offset=offset
        )
        assert isinstance(resp, dict), 'Invalid search response'

        playlists: list[SearchCloudFolderInfo] = []
        for playlist_dict in resp.get('result', {}).get('playlists', []):
            playlists.append(
                SearchCloudFolderInfo(
                    folder_name=playlist_dict['name'],
                    image_url=playlist_dict['coverImgUrl'],
                    id=str(playlist_dict['id']),
                    author=playlist_dict['creator']['nickname'],
                )
            )
        return playlists

    def getTrackDetail(self, track_id: int | str) -> TrackDetailInfo:
        response = apis.track.getTrackDetail(song_ids=[track_id])
        assert isinstance(response, dict), 'Invalid track detail response'
        detail = response['songs'][0]  # type: ignore
        al = detail.get('al', {})
        return TrackDetailInfo(
            cover_url=al.get('picUrl', ''),
            album_name=al.get('name', ''),
            cd=detail.get('cd', '1'),
            track_no=detail.get('no', 1),
            publish_time=detail.get('publishTime', 0),
            artists=[
                ArtistInfo(
                    id=obj['id'],
                    name=obj['name'],
                )
                for obj in detail.get('ar', [])
            ],
            duration=detail.get('dt', 0),
            name=detail.get('name', ''),
            aliases=[str(alias) for alias in detail.get('alia', []) if alias],
            display_tags=_tag_texts(detail.get('displayTags')),
            entertainment_tags=_tag_texts(detail.get('entertainmentTags')),
            award_tags=_tag_texts(detail.get('awardTags')),
            mark_tags=_tag_texts(detail.get('markTags')),
            song_feature=detail.get('songFeature'),
        )

    def getTrackAudio(
        self, track_id: int | str, bitrate: int = 999000
    ) -> TrackAudioInfo:
        resp = apis.track.getTrackAudio([str(track_id)], bitrate=bitrate)
        if isinstance(resp, bytes):
            resp = json.loads(resp.decode())
        assert isinstance(resp, dict), 'Invalid track audio response'
        url = resp['data'][0]['url']  # type: ignore
        return TrackAudioInfo(url=url)

    def getTrackLyrics(self, track_id: int | str) -> TrackLyricsInfo:
        data = apis.track.getTrackLyricsNew(str(track_id))
        assert isinstance(data, dict), 'Invalid track lyrics response'

        lyric = data.get('lrc', {}).get('lyric', '')

        tlyric = data.get('tlyric')
        if isinstance(tlyric, dict):
            translated_lyric = tlyric.get('lyric', '')
        else:
            translated_lyric = ''

        yrc_lyric = data.get('yrc', {}).get('lyric', '')
        ytlrc_lyric = data.get('ytlrc', {}).get('lyric', '')

        return TrackLyricsInfo(
            lyric=lyric,
            translated_lyric=translated_lyric,
            yrc_lyric=yrc_lyric,
            ytlrc_lyric=ytlrc_lyric,
        )

    def userPrivilegeLevel(self) -> int:
        return pyncm.getCurrentSession().vipType

    def loggedIn(self) -> bool:
        return bool(pyncm.getCurrentSession().logged_in)

    def getUserPlaylists(self) -> list[CloudFolderInfo]:
        with pyncm.getCurrentSession() as session:
            response = apis.user.getUserPlaylists(session.uid)
            assert isinstance(response, dict), 'Invaild Response'
            assert not session.is_anonymous, 'Anonymous Account'

            data = response['playlist']  # type: ignore

            return [
                CloudFolderInfo(
                    folder_name=p['name'],
                    image_url=p['coverImgUrl'],
                    id=str(p['id']),
                    song_count=p.get('trackCount'),
                    special_type=p.get('specialType'),
                )
                for p in data
            ]

    def getLikedPlaylist(self) -> CloudFolderInfo | None:
        playlists = self.getUserPlaylists()
        for folder in playlists:
            if folder.special_type == 5:
                return folder
        for folder in playlists:
            if folder.folder_name in ('我喜欢的音乐', 'I Like Music'):
                return folder
        return playlists[0] if playlists else None

    def createPlaylist(self, name: str) -> str:
        with pyncm.getCurrentSession():
            response = apis.playlist.setCreatePlaylist(name, False)
            assert isinstance(response, dict), 'Invalid Response'
            return str(response['id'])  # type: ignore

    def removePlaylist(self, id: str) -> None:
        with pyncm.getCurrentSession():
            apis.playlist.setRemovePlaylist(id)  # type: ignore

    def editPlaylist(
        self,
        option: Literal['add'] | Literal['del'],
        song_ids: list[str],
        folder_id: str,
    ) -> bool:
        with pyncm.getCurrentSession():
            result = apis.playlist.setManipulatePlaylistTracks(
                song_ids, folder_id, op=option
            )
            assert isinstance(result, dict), 'Invalid Response'
            if result.get('code') != 200:
                _logger.warning('edit_playlist(%s) failed: %s', option, result)
                return False
            return True

    def getPlaylistTracks(self, playlist_id: str) -> list[SongStorable]:
        with pyncm.getCurrentSession():
            response = apis.playlist.getPlaylistAllTracks(int(playlist_id))
            assert isinstance(response, dict), 'Invalid Response'
            assert response.get('code') == 200, f'API Error: {response}'
            songs = response['songs']  # type: ignore
            result: list[SongStorable] = []
            for s in songs:
                storable = self._songStorableFromApiSong(s)
                if storable is not None:
                    result.append(storable)
            return result

    def getUserVipType(self) -> int | str:
        return pyncm.getCurrentSession().vipType

    def getDailyRecommendSongs(self) -> list[SongStorable]:
        with pyncm.getCurrentSession():
            response = apis.user.getDailyRecommend()
            assert isinstance(response, dict), 'Invalid Response'
            assert response.get('code') == 200, f'API Error: {response}'
            result: list[SongStorable] = []
            for obj in response['recommend']:
                storable = self._songStorableFromApiSong(obj)
                if storable is not None:
                    result.append(storable)
            return result

    def getDailyRecommendFolders(self) -> list[CloudFolderInfo]:
        with pyncm.getCurrentSession():
            response = apis.user.getDailyRecommendResource()
            assert isinstance(response, dict), 'Invalid Response'
            assert response.get('code') == 200, f'API Error: {response}'
            return [
                CloudFolderInfo(
                    folder_name=obj['name'],
                    image_url=obj.get('picUrl', ''),
                    id=str(obj['id']),
                    song_count=obj.get('trackCount'),
                    special_type=obj.get('specialType'),
                )
                for obj in response.get('recommend') or []
            ]

    def getHeartModeSongs(
        self,
        seed_song_id: int | str,
        playlist_id: int | str,
        start_music_id: int | str | None = None,
        count: int = 20,
    ) -> list[SongStorable]:
        with pyncm.getCurrentSession():
            response = apis.playmode.getIntelligenceList(
                seed_song_id,
                playlist_id,
                start_music_id,
                count,
            )
            assert isinstance(response, dict), 'Invalid Response'
            assert response.get('code') == 200, f'API Error: {response}'
            data = response.get('data') or []
            result: list[SongStorable] = []
            for item in data:
                if not isinstance(item, dict):
                    continue
                song = item.get('songInfo') or item.get('song') or item
                if not isinstance(song, dict):
                    continue
                storable = self._songStorableFromApiSong(song)
                if storable is not None:
                    result.append(storable)
            return result

    def getPersonalFMSongs(self) -> list[SongStorable]:
        with pyncm.getCurrentSession():
            response = apis.radio.getPersonalFM()
            assert isinstance(response, dict), 'Invalid Response'
            assert response.get('code') == 200, f'API Error: {response}'
            result: list[SongStorable] = []
            for song in response.get('data') or []:
                if not isinstance(song, dict):
                    continue
                storable = self._songStorableFromApiSong(song)
                if storable is not None:
                    result.append(storable)
            return result

    def getPrivateRadarSongs(self) -> list[SongStorable]:
        with pyncm.getCurrentSession():
            item = self._findPcRecommendItem(
                module_types={'radar'},
                cover_texts={'私人雷达'},
                resource_types=set(),
                position_codes={'radar'},
            )
            if item is None:
                return []
            playlist_id = item.get('resourceId')
            if playlist_id is None:
                return []
            response = apis.playlist.getPlaylistInfoEapi(playlist_id)
            assert isinstance(response, dict), 'Invalid Response'
            assert response.get('code') == 200, f'API Error: {response}'
            playlist = response.get('playlist') or {}
            if not isinstance(playlist, dict):
                return []
            return self._songsFromApiSongs(playlist.get('tracks') or [])

    def getSimilarFMSongs(self) -> list[SongStorable]:
        with pyncm.getCurrentSession():
            item = self._findPcRecommendItem(
                module_types={'song_fm'},
                cover_texts={'相似歌曲'},
                resource_types={'similarSong'},
                position_codes={'song_fm'},
            )
            if item is None:
                return []
            seed_ids = self._songIdsFromRecommendItem(item)
            if not seed_ids:
                return []

            result: list[SongStorable] = []
            seen_ids: set[str] = set()
            for seed_id in seed_ids:
                response = apis.recommend.getSimilarSongs(seed_id)
                assert isinstance(response, dict), 'Invalid Response'
                assert response.get('code') == 200, f'API Error: {response}'
                for song in self._songsFromApiSongs(response.get('songs') or []):
                    if song.id in seen_ids:
                        continue
                    seen_ids.add(song.id)
                    result.append(song)
            return result

    def recordPlayed(self, song_id: str, song_name: str, time: float) -> None:
        apis.user.setWeblog(
            {
                'action': 'play',
                'json': {
                    'content': '',
                    'download': 0,
                    'end': 'ui',
                    'id': int(song_id),
                    'mainsite': '1',
                    'mainsiteWeb': '1',
                    'source': 'search',
                    'sourceId': song_name,
                    'time': int(time),
                    'type': 'song',
                    'wifi': 0,
                },
            }
        )

    def recordPlay(self, song_id: str) -> None:
        apis.user.setWeblog(
            {
                'action': 'startplay',
                'json': {
                    'content': '',
                    'id': int(song_id),
                    'mainsite': '1',
                    'mainsiteWeb': '1',
                    'type': 'song',
                },
            }
        )

    def getComments(
        self,
        song_id: str,
        page: int = 1,
        limit: int = 20,
        sort: Literal['recommend'] | Literal['time'] | Literal['hot'] = 'time',
        cursor: str = '-1',
    ):
        with pyncm.getCurrentSession():
            response = apis.track.getComments(song_id, page, limit, sort, cursor)
            assert isinstance(response, dict), 'Invaild response'
            data: dict = response.get('data', {})
        return CommentInfo(
            [
                Comment(
                    str(obj['commentId']),
                    UserInfo(
                        obj['user']['encryptUserId'],
                        obj['user']['avatarUrl'],
                        obj['user']['nickname'],
                    ),
                    obj['content'],
                    obj['likedCount'],
                    datetime.fromtimestamp(obj['time'] / 1000),
                    [BeReplyComment(
                        str(rep['beRepliedCommentId']),
                        UserInfo(
                            rep['user']['encryptUserId'],
                            rep['user']['avatarUrl'],
                            rep['user']['nickname'],
                        ),
                        rep['content'],
                    ) for rep in obj['beReplied']] if obj['beReplied'] else None,
                )
                for obj in data['comments']
            ],
            data['totalCount'],
            str(data.get('cursor', cursor)),
        )
    
    def addComment(self, song_id: str, content: str) -> None:
        apis.track.addComment(song_id, content)

    # ------------------------------------------------------------------
    # 以下为 standalone 后端为对标 pyncm 全量 API 补齐的封装。
    # 与现有方法保持一致,直接透传 pyncm 并做必要断言/类型归一。
    # ------------------------------------------------------------------

    def loginViaEmail(
        self, email: str, password: str, remember_login: bool = True
    ) -> BackendSessionSnapshot:
        """pyncm login.loginViaEmail."""
        apis.login.loginViaEmail(email, password, remeberLogin=remember_login)
        return self._sessionSnapshot()

    def registerViaCellphone(
        self, cell: str, captcha: str, nickname: str, password: str
    ) -> dict:
        """pyncm login.setRegisterAccountViaCellphone."""
        response = apis.login.setRegisterAccountViaCellphone(
            cell, captcha, nickname, password
        )
        assert isinstance(response, dict), 'Invalid register response'
        return response

    def checkCellphoneRegistered(self, cell: str, prefix: int = 86) -> dict:
        """pyncm login.checkIsCellphoneRegistered."""
        response = apis.login.checkIsCellphoneRegistered(cell, prefix=prefix)
        assert isinstance(response, dict), 'Invalid check response'
        return response

    def refreshLoginToken(self) -> dict:
        """pyncm login.loginRefreshToken."""
        response = apis.login.loginRefreshToken()
        assert isinstance(response, dict), 'Invalid refresh response'
        return response

    def dailySignin(self, dtype: int = 0) -> dict:
        """pyncm user.setSignin (0=mobile, 1=web)."""
        response = apis.user.setSignin(dtype)
        assert isinstance(response, dict), 'Invalid signin response'
        return response

    def getUserAlbumSubs(self, limit: int = 30) -> dict:
        """pyncm user.getUserAlbumSubs."""
        response = apis.user.getUserAlbumSubs(limit)
        assert isinstance(response, dict), 'Invalid album subs response'
        return response

    def getUserArtistSubs(self, limit: int = 30) -> dict:
        """pyncm user.getUserArtistSubs."""
        response = apis.user.getUserArtistSubs(limit)
        assert isinstance(response, dict), 'Invalid artist subs response'
        return response

    def getCloudDriveSongs(self, limit: int = 30, offset: int = 0) -> dict:
        """pyncm cloud.getCloudDriveInfo (云盘列表)."""
        response = apis.cloud.getCloudDriveInfo(limit=limit, offset=offset)
        assert isinstance(response, dict), 'Invalid cloud drive response'
        return response

    def uploadCloudSong(
        self,
        file_path: str,
        song: str = '',
        artist: str = '',
        album: str = '',
        bitrate: int = 128,
    ) -> dict:
        """上传本地音频到云盘(完整 pyncm cloud 链路).

        依次调用 getNosToken -> setUploadObject -> getCheckCloudUpload ->
        setUploadCloudInfo -> setPublishCloudResource。
        """
        import hashlib
        import os

        if not os.path.isfile(file_path):
            raise FileNotFoundError(file_path)
        filename = os.path.basename(file_path)
        ext = os.path.splitext(filename)[1].lstrip('.').lower()
        file_size = os.path.getsize(file_path)

        with open(file_path, 'rb') as f:
            stream = f.read()
        md5 = hashlib.md5(stream).hexdigest()

        token = apis.cloud.getNosToken(filename, md5, file_size, ext)
        assert isinstance(token, dict), 'Invalid nos token response'
        resource_id = str(token.get('resourceId') or '')
        object_key = str(token.get('objectKey') or '')
        nos_token = str(token.get('token') or '')
        if not (resource_id and object_key and nos_token):
            raise RuntimeError(f'nos token missing fields: {token}')

        upload = apis.cloud.setUploadObject(
            stream, md5, file_size, object_key, nos_token
        )
        assert isinstance(upload, dict), 'Invalid upload response'
        if upload.get('code') != 0 and upload.get('code') != 200:
            raise RuntimeError(f'upload failed: {upload}')

        check = apis.cloud.getCheckCloudUpload(md5, ext, file_size, bitrate)
        assert isinstance(check, dict), 'Invalid upload check response'
        song_id = str(check.get('songId') or '')
        if not song_id:
            raise RuntimeError(f'upload check failed: {check}')

        info = apis.cloud.setUploadCloudInfo(
            resource_id,
            song_id,
            md5,
            filename,
            song=song or filename,
            artist=artist,
            album=album,
            bitrate=bitrate,
        )
        assert isinstance(info, dict), 'Invalid cloud info response'

        publish = apis.cloud.setPublishCloudResource(song_id)
        assert isinstance(publish, dict), 'Invalid publish response'

        return {
            'song_id': song_id,
            'info': info,
            'publish': publish,
        }

    def getAlbumComments(self, album_id: str, offset: int = 0, limit: int = 20) -> dict:
        """pyncm album.getAlbumComments."""
        response = apis.album.getAlbumComments(album_id, offset=offset, limit=limit)
        assert isinstance(response, dict), 'Invalid album comments response'
        return response

    def getPlaylistComments(
        self, playlist_id: str, offset: int = 0, limit: int = 20
    ) -> dict:
        """pyncm playlist.getPlaylistComments."""
        response = apis.playlist.getPlaylistComments(
            playlist_id, offset=offset, limit=limit
        )
        assert isinstance(response, dict), 'Invalid playlist comments response'
        return response

    def getMVDetail(self, mv_id: str) -> dict:
        """pyncm video.getMVDetail."""
        response = apis.video.getMVDetail(mv_id)
        assert isinstance(response, dict), 'Invalid mv detail response'
        return response

    def getMVResource(self, mv_id: str, res: int = 1080) -> dict:
        """pyncm video.getMVResource."""
        response = apis.video.getMVResource(mv_id, res=res)
        assert isinstance(response, dict), 'Invalid mv resource response'
        return response

    def getMVComments(self, mv_id: str, offset: int = 0, limit: int = 20) -> dict:
        """pyncm video.getMVComments."""
        response = apis.video.getMVComments(mv_id, offset=offset, limit=limit)
        assert isinstance(response, dict), 'Invalid mv comments response'
        return response

    def radioControl(
        self, action: str, song_id: str, like: bool = True, time: str = '0'
    ) -> dict:
        """pyncm miniprograms.radio 交互: skip / like / unlike / trash."""
        if action == 'skip':
            response = apis.miniprograms.radio.setSkipRadioContent(song_id, time=time)
        elif action == 'like':
            response = apis.miniprograms.radio.setLikeRadioContent(
                song_id, like=True, time=time
            )
        elif action == 'unlike':
            response = apis.miniprograms.radio.setLikeRadioContent(
                song_id, like=False, time=time
            )
        elif action == 'trash':
            response = apis.miniprograms.radio.setTrashRadioContent(song_id, time=time)
        else:
            raise ValueError(f'unknown radio action: {action}')
        assert isinstance(response, dict), 'Invalid radio response'
        return response

    def matchTrackByFP(self, audio_fp: str, duration: float) -> dict:
        """pyncm track.getMatchTrackByFP (听歌识曲)."""
        response = apis.track.getMatchTrackByFP(audio_fp, duration)
        assert isinstance(response, dict), 'Invalid fingerprint match response'
        return response

    def getTrackAudioV1(self, track_id: str, level: str = 'standard') -> dict:
        """pyncm track.getTrackAudioV1 (按音质等级取播放地址)."""
        response = apis.track.getTrackAudioV1([str(track_id)], level=level)
        if isinstance(response, bytes):
            response = json.loads(response.decode())
        assert isinstance(response, dict), 'Invalid track audio v1 response'
        return response

    def getTrackDownloadURL(self, track_id: str, bitrate: int = 320000) -> dict:
        """pyncm track.getTrackDownloadURL."""
        response = apis.track.getTrackDownloadURL([str(track_id)], bitrate=bitrate)
        if isinstance(response, bytes):
            try:
                response = json.loads(response.decode())
            except (json.JSONDecodeError, UnicodeDecodeError):
                # 匿名/受限歌曲可能返回非 JSON 原始字节,降级为空结果。
                return {}
        assert isinstance(response, dict), 'Invalid download url response'
        return response

    def likeTrack(self, track_id: str, like: bool = True) -> dict:
        """pyncm track.setLikeTrack (直接红心/取消红心)."""
        response = apis.track.setLikeTrack(track_id, like=like)
        assert isinstance(response, dict), 'Invalid like response'
        return response

    def getTrackComments(self, song_id: str, offset: int = 0, limit: int = 20) -> dict:
        """pyncm track.getTrackComments (网页版歌曲评论)."""
        response = apis.track.getTrackComments(
            str(song_id), offset=offset, limit=limit
        )
        assert isinstance(response, dict), 'Invalid track comments response'
        return response

    def loginTypeSwitch(self) -> dict:
        """pyncm login.loginTypeSwitch (切换登录方式,服务端等同登出)."""
        response = apis.login.loginTypeSwitch()
        assert isinstance(response, dict), 'Invalid login type switch response'
        return response

    def getTrackDownloadURLV1(self, track_id: str, level: str = 'standard') -> dict:
        """pyncm track.getTrackDownloadURLV1 (V1 下载地址)."""
        response = apis.track.getTrackDownloadURLV1([str(track_id)], level=level)
        if isinstance(response, bytes):
            try:
                response = json.loads(response.decode())
            except (json.JSONDecodeError, UnicodeDecodeError):
                return {}
        assert isinstance(response, dict), 'Invalid download url v1 response'
        return response

    def getCloudDriveItemInfo(self, song_id: str) -> dict:
        """pyncm cloud.getCloudDriveItemInfo (云盘单曲详情)."""
        response = apis.cloud.getCloudDriveItemInfo([str(song_id)])
        assert isinstance(response, dict), 'Invalid cloud item response'
        return response

    def rectifyCloudSong(self, old_song_id: str, new_song_id: str) -> dict:
        """pyncm cloud.setRectifySongId (云盘歌曲纠错)."""
        response = apis.cloud.setRectifySongId(old_song_id, new_song_id)
        assert isinstance(response, dict), 'Invalid rectify response'
        return response

    def getMoreRadioContent(self, limit: int = 3) -> dict:
        """pyncm miniprograms.radio.getMoreRadioContent (更多FM内容)."""
        response = apis.miniprograms.radio.getMoreRadioContent(limit=limit)
        assert isinstance(response, dict), 'Invalid radio content response'
        return response

    def getDifmPlayingTracks(self, channel_id: int = 101, limit: int = 10) -> dict:
        """pyncm miniprograms.difm.getCurrentPlayingTrackList (DIFM 播放列表)."""
        response = apis.miniprograms.difm.getCurrentPlayingTrackList(
            channelId=channel_id, limit=limit
        )
        assert isinstance(response, dict), 'Invalid difm playing response'
        return response

    def getDifmChannels(self) -> dict:
        """pyncm miniprograms.difm.getChannelCollection (DIFM 频道)."""
        response = apis.miniprograms.difm.getChannelCollection()
        assert isinstance(response, dict), 'Invalid difm channels response'
        return response

    def getDifmSubscribedChannels(self) -> dict:
        """pyncm miniprograms.difm.getChannelSubscriptionCollection (订阅频道)."""
        response = apis.miniprograms.difm.getChannelSubscriptionCollection()
        assert isinstance(response, dict), 'Invalid difm subs response'
        return response

    def setDifmChannelSubscription(
        self, channel_id: int, subscribe: bool = True
    ) -> dict:
        """pyncm miniprograms.difm.setChannelSubscribiton (订阅/取消频道)."""
        response = apis.miniprograms.difm.setChannelSubscribiton(
            channel_id, set_subsubscribe=subscribe
        )
        assert isinstance(response, dict), 'Invalid difm subscribe response'
        return response

    def getSportsFMRecommendations(self, limit: int = 3, bpm: int = 50) -> dict:
        """pyncm miniprograms.sportsfm.getSportsFMRecommendations (运动FM推荐)."""
        response = apis.miniprograms.sportsfm.getSportsFMRecommendations(
            limit=limit, bpm=bpm
        )
        assert isinstance(response, dict), 'Invalid sports fm response'
        return response

    def getCalculatedSportsFMStatus(
        self,
        distance: int = 0,
        maxbpm: int = 0,
        time: int = 0,
        song_list: list | None = None,
        steps: int = 0,
        bpm: int = 0,
    ) -> dict:
        """pyncm miniprograms.sportsfm.getCalculatedSportsFMStatus."""
        response = apis.miniprograms.sportsfm.getCalculatedSportsFMStatus(
            distance=distance,
            maxbpm=maxbpm,
            time=time,
            songList=song_list or [],
            steps=steps,
            bpm=bpm,
        )
        assert isinstance(response, dict), 'Invalid sports status response'
        return response

    def getZoneFMInfo(self, zone: str = 'CLASSICAL', limit: int = 3) -> dict:
        """pyncm miniprograms.zonefm.getFmZoneInfo (专区FM内容)."""
        response = apis.miniprograms.zonefm.getFmZoneInfo(limit=limit, zone=zone)
        assert isinstance(response, dict), 'Invalid zone fm response'
        return response

    def skipZoneFMTrack(self, song_id: str, zone: str = 'CLASSICAL') -> dict:
        """pyncm miniprograms.zonefm.setSkipFmTrack (跳过专区FM曲目)."""
        response = apis.miniprograms.zonefm.setSkipFmTrack(song_id, zone=zone)
        assert isinstance(response, dict), 'Invalid zone skip response'
        return response


def _tag_texts(value: Any) -> list[str]:
    result: list[str] = []

    def _append(item: Any) -> None:
        if item is None:
            return
        if isinstance(item, str):
            if item:
                result.append(item)
            return
        if isinstance(item, int | float):
            result.append(str(item))
            return
        if isinstance(item, dict):
            for key in ('name', 'tagName', 'title', 'text', 'label', 'value'):
                text = item.get(key)
                if isinstance(text, str) and text:
                    result.append(text)
                    return
            return
        if isinstance(item, list | tuple):
            for child in item:
                _append(child)

    _append(value)
    return list(dict.fromkeys(result))
