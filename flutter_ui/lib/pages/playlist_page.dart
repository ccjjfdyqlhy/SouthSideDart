import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/player_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// 播放列表抽屉(右侧滑入):当前播放队列 + 播放/排序/清空。
class PlaylistPage extends StatelessWidget {
  final PlayerState player;
  final VoidCallback onClose;

  const PlaylistPage({
    super.key,
    required this.player,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.card,
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              children: [
                Text(
                  '播放列表',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const Spacer(),
                IconBtn(
                  icon: Icons.clear_all_rounded,
                  size: 18,
                  tooltip: '清空',
                  onTap: () {
                    player
                      ..setPlaylist([])
                      ..isPlaying = false;
                  },
                ),
                IconBtn(
                  icon: Icons.close_rounded,
                  size: 18,
                  tooltip: '关闭',
                  onTap: onClose,
                ),
              ],
            ),
          ),
          Divider(color: colors.divider),
          Expanded(
            child: player.playlist.isEmpty
                ? Center(
                    child: Text(
                      '队列为空',
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.textTertiary,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: player.playlist.length,
                    itemBuilder: (context, index) {
                      final song = player.playlist[index];
                      final isCurrent = index == player.currentIndex;
                      return _QueueTile(
                        song: song,
                        index: index,
                        isCurrent: isCurrent,
                        onPlay: () => player.playSong(song),
                        onRemove: () {
                          final list = List<Song>.from(player.playlist)
                            ..removeAt(index);
                          final newIndex = index < player.currentIndex
                              ? player.currentIndex - 1
                              : player.currentIndex;
                          player
                            ..setPlaylist(list)
                            ..currentIndex = newIndex;
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  final Song song;
  final int index;
  final bool isCurrent;
  final VoidCallback onPlay;
  final VoidCallback onRemove;

  const _QueueTile({
    required this.song,
    required this.index,
    required this.isCurrent,
    required this.onPlay,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListTile(
      onTap: onPlay,
      leading: CoverImage(seed: song.id, size: 40, radius: BorderRadius.circular(4)),
      title: Text(
        song.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          color: isCurrent ? colors.accent : colors.textPrimary,
          fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      subtitle: Text(
        song.artistNames,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: colors.textSecondary),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCurrent)
            Icon(Icons.volume_up_rounded, size: 16, color: colors.accent)
          else
            IconBtn(
              icon: Icons.remove_circle_outline_rounded,
              size: 18,
              tooltip: '移除',
              onTap: onRemove,
            ),
        ],
      ),
    );
  }
}
