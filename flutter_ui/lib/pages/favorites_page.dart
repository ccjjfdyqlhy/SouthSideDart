import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/backend_store.dart';
import '../state/player_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/song_card.dart';

/// 收藏/歌单页:显示选中的本地或云端歌单及其歌曲。
class FavoritesPage extends StatelessWidget {
  final Folder? folder;
  final PlayerState player;
  final BackendStore? store;
  final VoidCallback onPlayAll;
  final ValueChanged<int>? onArtistTap;

  const FavoritesPage({
    super.key,
    required this.folder,
    required this.player,
    this.store,
    this.onArtistTap,
    required this.onPlayAll,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (folder == null) {
      return Center(
        child: Text(
          '从左侧选择一个收藏夹',
          style: TextStyle(fontSize: 14, color: colors.textTertiary),
        ),
      );
    }

    final backendSongs = (store != null &&
            store!.loadedFolderId == folder!.id &&
            store!.folderSongs.isNotEmpty)
        ? store!.folderSongs
        : null;
    final songs = folder!.songs.isNotEmpty
        ? folder!.songs
        : (backendSongs ?? const []);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Row(
              children: [
                CoverImage(
                  seed: folder!.id,
                  size: 120,
                  radius: BorderRadius.circular(12),
                  url: folder!.coverUrl,
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        folder!.name,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${folder!.songCount} 首歌曲',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _PrimaryBtn(
                            icon: Icons.play_arrow_rounded,
                            label: '播放全部',
                            onTap: onPlayAll,
                          ),
                          const SizedBox(width: 8),
                          _GhostBtn(
                            icon: Icons.playlist_add_rounded,
                            label: '添加到队列',
                            onTap: () {
                              for (final s in songs) {
                                player.queueSong(s);
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      Text('已添加 ${songs.length} 首到播放队列'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (songs.isEmpty && (store?.loadingFolderSongs ?? false))
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (songs.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  '歌单暂无歌曲',
                  style: TextStyle(fontSize: 13, color: Color(0xFF6F6E86)),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            sliver: SliverList.separated(
              itemCount: songs.length,
              itemBuilder: (context, index) {
                final song = songs[index];
                return SongCard(
                  song: song,
                  onPlay: () => player.playSong(song),
                  onInsert: () => player.queueSong(song),
                  onFavorite: () => player.likeSong(song),
                  onArtistTap: (artist) => onArtistTap?.call(artist.id),
                );
              },
              separatorBuilder: (_, _) => const SizedBox(height: 2),
            ),
          ),
      ],
    );
  }
}

class _PrimaryBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PrimaryBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.accent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GhostBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _GhostBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.divider),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: colors.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
