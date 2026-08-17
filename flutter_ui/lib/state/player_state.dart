import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/models.dart';

/// 播放状态。当前用 mock 时钟模拟进度推进,后续通过协议对接 Python core。
class PlayerState extends ChangeNotifier {
  final List<Song> playlist = [];
  int currentIndex = -1;
  bool isPlaying = false;
  double positionMs = 0;
  bool shuffle = false;

  Timer? _ticker;
  static const _tickMs = 100;

  Song? get currentSong =>
      currentIndex >= 0 && currentIndex < playlist.length
          ? playlist[currentIndex]
          : null;

  double get durationMs =>
      currentSong?.durationMs.toDouble() ?? 0;

  /// 当前播放进度(0~1)。
  double get progress =>
      durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0;

  /// 当前歌词行索引(mock:按时间推进)。
  int currentLyricIndex(List<LyricLine> lyrics) {
    var idx = 0;
    for (var i = 0; i < lyrics.length; i++) {
      if (positionMs >= lyrics[i].timeMs) idx = i;
    }
    return idx;
  }

  void setPlaylist(List<Song> songs, {int startIndex = 0}) {
    playlist
      ..clear()
      ..addAll(songs);
    currentIndex = startIndex;
    positionMs = 0;
    notifyListeners();
  }

  void playSong(Song song) {
    if (playlist.isEmpty || !playlist.contains(song)) {
      setPlaylist([song]);
    } else {
      currentIndex = playlist.indexOf(song);
      positionMs = 0;
    }
    _startTicking();
    notifyListeners();
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
  }

  void next() {
    if (playlist.isEmpty) return;
    final step = shuffle ? 1 : 1;
    currentIndex = (currentIndex + step) % playlist.length;
    positionMs = 0;
    notifyListeners();
  }

  void previous() {
    if (playlist.isEmpty) return;
    if (positionMs > 3000) {
      positionMs = 0;
      notifyListeners();
      return;
    }
    currentIndex =
        (currentIndex - 1 + playlist.length) % playlist.length;
    positionMs = 0;
    notifyListeners();
  }

  void seek(double fraction) {
    positionMs = durationMs * fraction;
    notifyListeners();
  }

  void toggleShuffle() {
    shuffle = !shuffle;
    notifyListeners();
  }

  void _startTicking() {
    _stopTicking();
    _ticker = Timer.periodic(
      const Duration(milliseconds: _tickMs),
      (_) {
        if (!isPlaying) return;
        positionMs += _tickMs;
        if (positionMs >= durationMs && durationMs > 0) {
          next();
          isPlaying = true;
        }
        notifyListeners();
      },
    );
  }

  void _stopTicking() {
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void dispose() {
    _stopTicking();
    super.dispose();
  }
}
