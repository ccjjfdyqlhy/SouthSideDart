import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/backend_client.dart';
import '../services/backend_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/network_image.dart';
import '../widgets/song_card.dart';

/// 专辑页(右面板):专辑信息 + 歌曲列表。
class AlbumPage extends StatefulWidget {
  final BackendClient client;
  final int albumId;
  final VoidCallback onBack;
  final ValueChanged<Song>? onSongTap;

  const AlbumPage({
    super.key,
    required this.client,
    required this.albumId,
    required this.onBack,
    this.onSongTap,
  });

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  Map<String, dynamic>? _album;
  List<Song> _songs = [];
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
      final r = await widget.client.call('get_album_tracks', {
        'album_id': widget.albumId.toString(),
      });
      final data = (r['result'] as Map<String, dynamic>?) ?? {};
      final songs = ((data['songs'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(songFromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _album = data;
        _songs = songs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载专辑失败:$e';
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
                    _album?['name']?.toString() ?? '专辑',
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
                                url: (_album?['cover_url'] ?? '').toString(),
                                width: 120,
                                height: 120,
                                seed: widget.albumId,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (_album?['name'] ?? '').toString(),
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        color: colors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      (_album?['artist'] ?? '').toString(),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_songs.length} 首',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colors.textTertiary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          SectionHeader(title: '歌曲列表'),
                          ..._songs.map(
                            (song) => SongCard(
                              song: song,
                              onPlay: () => widget.onSongTap?.call(song),
                              onInsert: () {},
                              onFavorite: () {},
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}
