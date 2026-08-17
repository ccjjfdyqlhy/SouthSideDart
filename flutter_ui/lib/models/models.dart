/// 对齐 Python core/models.py 的数据模型(Flutter 侧先做 UI 演示,后续经协议对接)。
library;

class Artist {
  final int id;
  final String name;

  const Artist({required this.id, required this.name});
}

class Song {
  final int id;
  final String name;
  final List<Artist> artists;
  final String album;
  final int durationMs;
  final String? coverUrl;

  const Song({
    required this.id,
    required this.name,
    required this.artists,
    required this.album,
    required this.durationMs,
    this.coverUrl,
  });

  String get artistNames =>
      artists.map((a) => a.name).join(' / ');

  String get durationText {
    final total = durationMs ~/ 1000;
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

enum FolderType { local, cloud }

class Folder {
  final int id;
  final String name;
  final int songCount;
  final String? coverUrl;
  final FolderType type;
  final List<Song> songs;

  const Folder({
    required this.id,
    required this.name,
    required this.songCount,
    this.coverUrl,
    this.type = FolderType.cloud,
    this.songs = const [],
  });
}

class LyricLine {
  final double timeMs;
  final String text;

  const LyricLine({required this.timeMs, required this.text});
}

class SearchType {
  static const songs = 'Songs';
  static const playlists = 'Playlists';
}

class ModeCard {
  final String title;
  final String subtitle;
  final String hint;
  final String icon;

  const ModeCard({
    required this.title,
    required this.subtitle,
    required this.hint,
    required this.icon,
  });
}
