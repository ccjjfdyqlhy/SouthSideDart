import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/player_state.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// 底部播放栏(高 52):封面 + 标题/当前歌词 + 播放控制 + 播放列表按钮。
/// 点击主体展开/收起播放详情页。
class PlayerBar extends StatelessWidget {
  final PlayerState player;
  final List<LyricLine> lyrics;
  final VoidCallback onExpand;
  final VoidCallback onPlaylist;

  const PlayerBar({
    super.key,
    required this.player,
    required this.lyrics,
    required this.onExpand,
    required this.onPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) => _buildBar(context),
    );
  }

  Widget _buildBar(BuildContext context) {
    final colors = context.colors;
    final song = player.currentSong;
    if (song == null) {
      return Container(
        height: 52,
        color: colors.glass,
        child: Center(
          child: Text(
            '未在播放',
            style: TextStyle(fontSize: 13, color: colors.textTertiary),
          ),
        ),
      );
    }

    final lyricIndex = player.currentLyricIndex(lyrics);
    final lyricText = lyrics.isNotEmpty ? lyrics[lyricIndex].text : '';

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: colors.glass,
        border: Border(top: BorderSide(color: colors.glassBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: InkWell(
              onTap: onExpand,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  CoverImage(seed: song.id, size: 36, radius: BorderRadius.circular(4)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          lyricText.isNotEmpty
                              ? lyricText
                              : song.artistNames,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconBtn(
                  icon: Icons.skip_previous_rounded,
                  size: 22,
                  tooltip: '上一首',
                  onTap: player.previous,
                ),
                const SizedBox(width: 4),
                _PlayPauseButton(player: player),
                const SizedBox(width: 4),
                IconBtn(
                  icon: Icons.skip_next_rounded,
                  size: 22,
                  tooltip: '下一首',
                  onTap: player.next,
                ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconBtn(
                  icon: Icons.shuffle_rounded,
                  size: 18,
                  tooltip: '随机播放',
                  color: player.shuffle ? colors.accent : colors.textSecondary,
                  onTap: player.toggleShuffle,
                ),
                IconBtn(
                  icon: Icons.queue_music_rounded,
                  size: 20,
                  tooltip: '播放列表',
                  onTap: onPlaylist,
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final PlayerState player;

  const _PlayPauseButton({required this.player});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return IconButton(
      onPressed: player.toggle,
      iconSize: 34,
      tooltip: player.isPlaying ? '暂停' : '播放',
      color: colors.textPrimary,
      icon: Icon(
        player.isPlaying
            ? Icons.pause_circle_filled_rounded
            : Icons.play_circle_fill_rounded,
      ),
    );
  }
}
