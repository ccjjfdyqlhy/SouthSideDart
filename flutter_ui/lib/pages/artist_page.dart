import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/backend_client.dart';
import '../services/backend_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/network_image.dart';
import '../widgets/song_card.dart';

/// 歌手页(右面板):头像/简介/热门歌曲/专辑。
class ArtistPage extends StatefulWidget {
  final BackendClient client;
  final int artistId;
  final VoidCallback onBack;

  /// 播放热门歌曲。
  final ValueChanged<Song>? onSongTap;

  /// 打开专辑(返回专辑 id)。
  final ValueChanged<int>? onAlbumTap;

  const ArtistPage({
    super.key,
    required this.client,
    required this.artistId,
    required this.onBack,
    this.onSongTap,
    this.onAlbumTap,
  });

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  Map<String, dynamic>? _artist;
  List<Song> _hotSongs = [];
  List<Map<String, dynamic>> _albums = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.client.call('get_artist', {
        'artist_id': widget.artistId.toString(),
      });
      final data = (r['result'] as Map<String, dynamic>?) ?? {};
      final hotSongs = ((data['hot_songs'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(songFromJson)
          .toList();
      final albums = ((data['albums'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      if (!mounted) return;
      setState(() {
        _artist = data;
        _hotSongs = hotSongs;
        _albums = albums;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载歌手信息失败:$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: colors.card,
              border: Border(bottom: BorderSide(color: colors.divider)),
            ),
            child: Row(
              children: [
                IconBtn(
                  icon: Icons.arrow_back_rounded,
                  size: 20,
                  tooltip: '返回',
                  onTap: widget.onBack,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _artist?['name']?.toString() ?? '歌手',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(color: colors.divider, height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          style: TextStyle(color: colors.danger),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          Row(
                            children: [
                              NetImage(
                                url: (_artist?['avatar_url'] ?? '').toString(),
                                width: 96,
                                height: 96,
                                radius: 48,
                                seed: widget.artistId,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (_artist?['name'] ?? '').toString(),
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        color: colors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '歌曲 ${_artist?['music_count'] ?? 0} · '
                                      '专辑 ${_artist?['album_count'] ?? 0}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                    if ((_artist?['brief'] ?? '')
                                        .toString()
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        (_artist?['brief'] ?? '').toString(),
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colors.textTertiary,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          SectionHeader(title: '热门歌曲'),
                          ..._hotSongs.map(
                            (song) => SongCard(
                              song: song,
                              onPlay: () => widget.onSongTap?.call(song),
                              onInsert: () {},
                              onFavorite: () {},
                            ),
                          ),
                          if (_albums.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            SectionHeader(title: '专辑'),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 14,
                              runSpacing: 14,
                              children: [
                                for (final album in _albums)
                                  _AlbumTile(
                                    album: album,
                                    onTap: () => widget.onAlbumTap?.call(
                                      int.tryParse(album['id'].toString()) ?? 0,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 16),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class _AlbumTile extends StatelessWidget {
  final Map<String, dynamic> album;
  final VoidCallback onTap;

  const _AlbumTile({required this.album, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 110,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NetImage(
              url: (album['cover_url'] ?? '').toString(),
              width: 110,
              height: 110,
              seed: int.tryParse(album['id'].toString()) ?? 0,
            ),
            const SizedBox(height: 6),
            Text(
              (album['name'] ?? '').toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
