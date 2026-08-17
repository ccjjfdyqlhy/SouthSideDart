import 'dart:async';

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

  /// 当前歌词行索引。
  int currentLyricIndex(List<LyricLine> lyrics) {
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
      final playing = (data['playing'] as bool?) ?? false;
      final position = ((data['position'] as num?)?.toDouble() ?? 0) * 1000;

      final changed = list.length != playlist.length ||
          idx != currentIndex ||
          playing != isPlaying ||
          (position - positionMs).abs() > 400;
      if (changed) {
        playlist
          ..clear()
          ..addAll(list);
        currentIndex = idx;
        isPlaying = playing;
        positionMs = position;
        backendPlaylistSize = list.length;
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
    _sync('play_control', {'command': 'next'});
  }

  void previous() {
    _sync('play_control', {'command': 'previous'});
  }

  void seek(double fraction) {
    positionMs = durationMs * fraction;
    notifyListeners();
    _sync('play_control', {'command': 'seek', 'position': positionMs / 1000});
  }

  void toggleShuffle() {
    shuffle = !shuffle;
    notifyListeners();
    // 随机/列表循环写入内核配置。
    _sync('set_config', {
      'key': 'play_method',
      'value': shuffle ? 'Shuffle' : 'Repeat list',
    });
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
      notifyListeners();
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
