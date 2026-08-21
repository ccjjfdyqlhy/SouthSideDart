import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'backend_client.dart';

/// 从后端 JSON 构造数据模型。
Song songFromJson(Map<String, dynamic> j) => Song(
      id: int.tryParse((j['id'] ?? '').toString()) ?? 0,
      name: (j['name'] ?? '').toString(),
      artists: ((j['artists'] as List?) ?? const [])
          .map((a) => Artist(
                id: int.tryParse((a['id'] ?? '').toString()) ?? 0,
                name: (a['name'] ?? '').toString(),
              ))
          .toList(),
      album: (j['album'] ?? '').toString(),
      durationMs: (j['duration'] as num?)?.toInt() ?? 0,
      coverUrl: (j['cover_url'] ?? '').toString().isEmpty
          ? null
          : (j['cover_url'] ?? '').toString(),
    );

Folder folderFromJson(Map<String, dynamic> j) => Folder(
      id: int.tryParse((j['id'] ?? '').toString()) ?? 0,
      name: (j['name'] ?? '').toString(),
      songCount: (j['song_count'] as num?)?.toInt() ?? 0,
      coverUrl: (j['cover_url'] ?? '').toString().isEmpty
          ? null
          : (j['cover_url'] ?? '').toString(),
      type: (j['type'] ?? 'cloud') == 'local'
          ? FolderType.local
          : FolderType.cloud,
    );

LyricLine lyricLineFromJson(Map<String, dynamic> j) => LyricLine(
      timeMs: ((j['time'] as num?)?.toDouble() ?? 0) * 1000,
      text: (j['content'] ?? '').toString(),
    );

/// 后端数据仓库:管理首页推荐、云端歌单、搜索结果与歌词。
/// 所有加载失败时保持为空列表,由 UI 回退到 mock 数据。
class BackendStore extends ChangeNotifier {
  final BackendClient client;

  BackendStore(this.client);

  bool loadingDaily = false;
  bool loadingFolders = false;
  bool loadingFolderSongs = false;

  List<Folder> dailyFolders = [];
  List<Song> dailySongs = [];
  List<Folder> cloudFolders = [];
  List<Folder> localFolders = [];
  List<Folder> get allFolders => [...localFolders, ...cloudFolders];
  List<Song> folderSongs = [];
  List<LyricLine> currentLyrics = [];
  List<LyricLine> currentTranslatedLyrics = [];

  /// 最近一次加载的歌单 id(供 FavoritesPage 判断当前数据归属)。
  int loadedFolderId = -1;

  /// 每日推荐(首页)。``force`` 用于登录成功后强制刷新。
  Future<void> loadDaily({bool force = false}) async {
    if (!client.isConnected || (loadingDaily && !force)) return;
    loadingDaily = true;
    notifyListeners();
    try {
      final r = await client.call('daily_recommend');
      final data = (r['result'] as Map<String, dynamic>?) ?? {};
      dailyFolders = ((data['folders'] as List?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(folderFromJson)
          .toList();
      dailySongs = ((data['songs'] as List?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(songFromJson)
          .toList();
    } catch (_) {
      // 内核不可用或请求失败,保持 mock 兜底
    } finally {
      loadingDaily = false;
      notifyListeners();
    }
  }

  /// 用户云端歌单 + 本地收藏夹。``force`` 用于登录成功后强制刷新。
  Future<void> loadPlaylists({bool force = false}) async {
    if (!client.isConnected || (loadingFolders && !force)) return;
    loadingFolders = true;
    notifyListeners();
    try {
      final r = await client.call('user_playlists');
      final data = (r['result'] as Map<String, dynamic>?) ?? {};
      cloudFolders = ((data['folders'] as List?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(folderFromJson)
          .toList();
      try {
        final favsRes = await client.call('list_favorites');
        final favsData = (favsRes['result'] as Map<String, dynamic>?) ?? {};
        localFolders = ((favsData['folders'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map((j) => Folder(
                  id: int.tryParse((j['id'] ?? '').toString()) ?? 0,
                  name: (j['name'] ?? '').toString(),
                  songCount: (j['count'] as num?)?.toInt() ?? 0,
                  coverUrl: null,
                  type: FolderType.local,
                ))
            .toList();
      } catch (_) {
        localFolders = const [];
      }
    } catch (_) {
      // 保持空,回退 mock
    } finally {
      loadingFolders = false;
      notifyListeners();
    }
  }

  /// 加载歌单内歌曲(云端按 id,本地按名称)。
  Future<List<Song>> loadFolderSongs(Folder folder) async {
    if (!client.isConnected) return const [];
    loadingFolderSongs = true;
    loadedFolderId = folder.id;
    notifyListeners();
    try {
      final r = await client.call('folder_songs', {
        'folder_id': folder.id.toString(),
        'type': folder.type == FolderType.local ? 'local' : 'cloud',
      });
      final data = (r['result'] as Map<String, dynamic>?) ?? {};
      folderSongs = ((data['songs'] as List?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(songFromJson)
          .toList();
      return List.of(folderSongs);
    } catch (_) {
      return const [];
    } finally {
      loadingFolderSongs = false;
      notifyListeners();
    }
  }

  /// 新建云端歌单,成功后刷新歌单列表。
  Future<bool> createPlaylist(String name) async {
    if (!client.isConnected || name.trim().isEmpty) return false;
    try {
      final r = await client.call('create_playlist', {'name': name.trim()});
      if (r['result'] == null) return false;
      await loadPlaylists(force: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 删除云端歌单,成功后刷新歌单列表。
  Future<bool> removePlaylist(int playlistId) async {
    if (!client.isConnected || playlistId <= 0) return false;
    try {
      final r = await client.call('remove_playlist', {
        'playlist_id': playlistId.toString(),
      });
      if (r['result'] == null) return false;
      await loadPlaylists(force: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 搜索歌曲或歌单。
  Future<List<Song>> searchSongs(String query) async {
    if (!client.isConnected || query.isEmpty) return const [];
    try {
      final r = await client.call('search', {'query': query, 'type': 'songs'});
      final data = (r['result'] as Map<String, dynamic>?) ?? {};
      return ((data['items'] as List?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(songFromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<Folder>> searchFolders(String query) async {
    if (!client.isConnected || query.isEmpty) return const [];
    try {
      final r =
          await client.call('search', {'query': query, 'type': 'playlists'});
      final data = (r['result'] as Map<String, dynamic>?) ?? {};
      return ((data['items'] as List?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(folderFromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 拉取真实歌词(空则保留 mock)。
  Future<void> loadLyrics(int songId) async {
    if (!client.isConnected || songId <= 0) return;
    try {
      final r = await client.call('get_lyrics', {'song_id': songId.toString()});
      final data = (r['result'] as Map<String, dynamic>?) ?? {};
      final lines = ((data['lines'] as List?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(lyricLineFromJson)
          .toList();
      final translated = ((data['translated'] as List?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(lyricLineFromJson)
          .toList();
      if (lines.isNotEmpty) {
        currentLyrics = lines;
        currentTranslatedLyrics = translated;
        notifyListeners();
      }
    } catch (_) {
      // 保持现有歌词
    }
  }
}
