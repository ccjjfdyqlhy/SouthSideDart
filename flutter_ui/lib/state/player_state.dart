import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/backend_client.dart';
import '../services/backend_store.dart';

/// 播放状态(内核驱动)。
///
/// 连接 Python 内核后:
/// - 播放队列 / 当前歌曲 / 播放状态 / 进度全部来自内核 ``get_playback``
///   (800ms 轮询 + 事件推送即时刷新);
/// - 播放控制(播放/暂停/切歌/seek)转发内核真实执行;
/// - 本地 100ms 插值仅用于进度条平滑显示,不驱动任何切歌逻辑。
/// 未连接内核时仅展示静态状态,不模拟播放。
class PlayerState extends ChangeNotifier {
  final List<Song> playlist = [];
  int currentIndex = -1;
  bool isPlaying = false;
  double positionMs = 0;
  bool shuffle = false;

  BackendClient? backend;

  int backendPlaylistSize = 0;
  bool backendWsRunning = false;

  Timer? _ticker;
  Timer? _pollTimer;
  bool _syncing = false;

  /// 内核最近一次报告的播放索引(用于检测内核切歌)。
  int _backendIndex = -1;

  /// 是否已完成首次同步(用于启动恢复进度)。
  bool _everSynced = false;

  final Random _random = Random();

  static const _tickMs = 100;
  static const _pollMs = 800;

  Song? get currentSong =>
      currentIndex >= 0 && currentIndex < playlist.length
          ? playlist[currentIndex]
          : null;

  double get durationMs => currentSong?.durationMs.toDouble() ?? 0;

  double get progress =>
      durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0;

  bool get connected => backend != null && backend!.isConnected;

  /// 当前歌词行索引;前奏(第一句开始前)返回 -1 表示无歌词。
  int currentLyricIndex(List<LyricLine> lyrics) {
    if (lyrics.isEmpty) return -1;
    if (positionMs < lyrics.first.timeMs) return -1;
    var idx = 0;
    for (var i = 0; i < lyrics.length; i++) {
      if (positionMs >= lyrics[i].timeMs) idx = i;
    }
    return idx;
  }

  /// 绑定内核:订阅事件推送并开始轮询同步。
  void attachBackend(BackendClient client) {
    backend = client;
    client.onEvent = _onBackendEvent;
    _startPolling();
    _refreshFromBackend();
    loadPlayMethod();
    loadLikedSongs();
  }

  /// 从内核拉取"我喜欢的音乐"歌曲 id,初始化红心状态。
  Future<void> loadLikedSongs() async {
    final client = backend;
    if (client == null || !client.isConnected) return;
    try {
      final r = await client.call('get_liked_songs');
      final data = (r['result'] as Map<String, dynamic>?) ?? {};
      final ids = ((data['ids'] as List?) ?? const []);
      _likedSongs
        ..clear()
        ..addAll(
          ids
              .map((e) => int.tryParse(e.toString()))
              .whereType<int>()
              .toList(),
        );
      notifyListeners();
    } catch (_) {}
  }

  void detachBackend() {
    _stopPolling();
    backend = null;
    playlist.clear();
    currentIndex = -1;
    isPlaying = false;
    positionMs = 0;
    notifyListeners();
  }

  void _onBackendEvent(Map<String, dynamic> message) {
    final event = message['event'];
    if (event == 'SONG_CHANGED' ||
        event == 'PLAY_STATE_CHANGED' ||
        event == 'PLAYLIST_CHANGED') {
      _refreshFromBackend();
    }
  }

  /// 从内核拉取完整播放状态并同步到本地(仅在变化时通知)。
  Future<void> _refreshFromBackend() async {
    final client = backend;
    if (client == null || !client.isConnected || _syncing) return;
    _syncing = true;
    try {
      final r = await client.call('get_playback');
      final data = (r['result'] as Map<String, dynamic>?) ?? {};
      final list = ((data['playlist'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(songFromJson)
          .toList();
      final idx = (data['current_index'] as num?)?.toInt() ?? -1;

      backendWsRunning = (data['ws_running'] as bool?) ?? backendWsRunning;
      backendPlaylistSize = list.length;

      // 内核切歌(current_index 变化)才同步歌曲与进度;
      // 播放状态与进度由本地权威,避免无音频环境下被拉回。
      final kernelChanged = idx >= 0 && idx != _backendIndex;
      if (kernelChanged) {
        _backendIndex = idx;
        currentIndex = idx;
        // 首次同步/恢复时采用内核进度(如启动恢复的 last_playing_time)。
        if (!_everSynced) {
          _everSynced = true;
          positionMs =
              ((data['position'] as num?)?.toDouble() ?? 0) * 1000;
        } else {
          positionMs = 0;
        }
        playlist
          ..clear()
          ..addAll(list);
        notifyListeners();
      } else if (list.length != playlist.length) {
        // 队列增删(插入/移除/清空):同步列表,尽量保持当前歌曲。
        final cur = currentSong;
        playlist
          ..clear()
          ..addAll(list);
        if (cur != null && list.isNotEmpty) {
          currentIndex = list.indexWhere((s) => s.id == cur.id);
          if (currentIndex < 0) currentIndex = 0;
        }
        notifyListeners();
      }
    } catch (_) {
      // 内核请求失败时保持当前状态。
    } finally {
      _syncing = false;
    }
  }

  void _startPolling() {
    _stopPolling();
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: _pollMs),
      (_) => _refreshFromBackend(),
    );
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// 直接设置本地队列(UI 展示;播放需经内核)。
  void setPlaylist(List<Song> songs, {int startIndex = 0}) {
    playlist
      ..clear()
      ..addAll(songs);
    currentIndex = startIndex;
    positionMs = 0;
    notifyListeners();
  }

  /// 播放一首歌曲:转发内核真实播放。
  void playSong(Song song) {
    if (song.id <= 0) {
      // 本地歌曲仅本地展示。
      setPlaylist([song]);
      isPlaying = true;
      _startTicking();
      notifyListeners();
      return;
    }
    // 乐观更新本地展示。
    if (playlist.isEmpty || !playlist.contains(song)) {
      setPlaylist([song]);
    } else {
      currentIndex = playlist.indexOf(song);
      positionMs = 0;
      isPlaying = true;
    }
    _startTicking();
    notifyListeners();
    _sync('play_storable', {'song': _songPayload(song)});
  }

  void toggle() {
    if (currentSong == null) return;
    isPlaying = !isPlaying;
    if (isPlaying) {
      _startTicking();
    } else {
      _stopTicking();
    }
    notifyListeners();
    _sync('play_control', {'command': 'toggle'});
  }

  void next() {
    if (playlist.isEmpty) return;
    if (shuffle && playlist.length > 1) {
      currentIndex = _random.nextInt(playlist.length);
    } else {
      currentIndex = (currentIndex + 1) % playlist.length;
    }
    positionMs = 0;
    notifyListeners();
    _sync('play_control', {'command': 'next'});
  }

  void previous() {
    if (playlist.isEmpty) return;
    if (positionMs > 3000) {
      // 播放超过 3 秒:回到本曲开头。
      positionMs = 0;
      notifyListeners();
      return;
    }
    currentIndex = (currentIndex - 1 + playlist.length) % playlist.length;
    positionMs = 0;
    notifyListeners();
    _sync('play_control', {'command': 'previous'});
  }

  void seek(double fraction) {
    positionMs = durationMs * fraction;
    notifyListeners();
    _sync('play_control', {'command': 'seek', 'position': positionMs / 1000});
  }

  /// 当前播放模式(Repeat list / Repeat one / Play in order / Shuffle)。
  String playMethod = 'Repeat list';

  /// 循环切换播放模式(顺序→列表循环→单曲循环→随机→智能)。
  void cyclePlayMethod() {
    const order = [
      'Play in order',
      'Repeat list',
      'Repeat one',
      'Shuffle',
      'Intelligent',
    ];
    final idx = order.indexOf(playMethod);
    playMethod = order[(idx + 1) % order.length];
    shuffle = playMethod == 'Shuffle';
    notifyListeners();
    _sync('set_config', {'key': 'play_method', 'value': playMethod});
  }

  void setPlayMethod(String method) {
    playMethod = method;
    shuffle = method == 'Shuffle';
    notifyListeners();
    _sync('set_config', {'key': 'play_method', 'value': method});
  }

  /// 启动时从内核读取播放模式。
  Future<void> loadPlayMethod() async {
    final client = backend;
    if (client == null || !client.isConnected) return;
    try {
      final r = await client.call('get_config');
      final data = (r['result'] as Map<String, dynamic>?) ?? {};
      final m = data['play_method'];
      if (m is String && m.isNotEmpty) {
        playMethod = m;
        shuffle = m == 'Shuffle';
        notifyListeners();
      }
    } catch (_) {}
  }

  /// 歌曲插入队列(内核在 current_index+2 处插入)。
  void queueSong(Song song) {
    _sync('queue_song', {'song': _songPayload(song)});
  }

  /// 从播放队列移除一首(同步内核)。
  void removePlaylistSong(int index) {
    if (index < 0 || index >= playlist.length) return;
    _sync('remove_playlist_song', {'index': index});
    playlist.removeAt(index);
    if (index < currentIndex) {
      currentIndex -= 1;
    } else if (index == currentIndex) {
      currentIndex = playlist.isEmpty ? -1 : currentIndex.clamp(0, playlist.length - 1);
    }
    notifyListeners();
  }

  /// 清空播放队列(保留当前歌曲,同步内核)。
  void clearPlaylist() {
    _sync('clear_playlist', {});
    final current = currentSong;
    playlist.clear();
    if (current != null) {
      playlist.add(current);
      currentIndex = 0;
    } else {
      currentIndex = -1;
    }
    notifyListeners();
  }

  /// 收藏/取消收藏(内核写入"我喜欢的音乐")。
  void likeSong(Song song) {
    if (song.id <= 0) return;
    _sync('like_song', {'song_id': song.id.toString()});
  }

  final Set<int> _likedSongs = {};

  bool isLiked(int songId) => _likedSongs.contains(songId);

  /// 红心切换:收藏/取消收藏。
  void toggleLike(Song song) {
    if (song.id <= 0) return;
    if (_likedSongs.contains(song.id)) {
      _likedSongs.remove(song.id);
      _sync('unlike_song', {'song_id': song.id.toString()});
    } else {
      _likedSongs.add(song.id);
      _sync('like_song', {'song_id': song.id.toString()});
    }
    notifyListeners();
  }

  void syncFromBackend() {
    _refreshFromBackend();
  }

  void _sync(String method, Map<String, dynamic> params) {
    final client = backend;
    if (client == null || !client.isConnected) return;
    unawaited(
      client
          .call(method, params)
          .catchError((Object _) => <String, dynamic>{}),
    );
  }

  static Map<String, dynamic> _songPayload(Song song) => {
        'id': song.id.toString(),
        'name': song.name,
        'artists': song.artists
            .map((a) => {'id': a.id.toString(), 'name': a.name})
            .toList(),
        'duration': song.durationMs,
      };

  void _startTicking() {
    _stopTicking();
    _ticker = Timer.periodic(const Duration(milliseconds: _tickMs), (_) {
      if (!isPlaying) return;
      positionMs += _tickMs;
      if (durationMs > 0 && positionMs >= durationMs) {
        // 播放结束:自动切下一首(本地权威 + 转发内核)。
        next();
      } else {
        notifyListeners();
      }
    });
  }

  void _stopTicking() {
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void dispose() {
    _stopTicking();
    _stopPolling();
    super.dispose();
  }
}
