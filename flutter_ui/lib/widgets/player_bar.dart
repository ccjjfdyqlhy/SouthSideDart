import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/player_state.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// 底部播放栏(高 52):封面 + 标题/当前歌词 + 播放控制 + 播放列表按钮。
/// 点击主体展开/收起播放详情页;hover 效果覆盖整条播放栏。
class PlayerBar extends StatefulWidget {
  final PlayerState player;
  final List<LyricLine> lyrics;
  final bool backendConnected;
  final VoidCallback onExpand;
  final VoidCallback onPlaylist;

  const PlayerBar({
    super.key,
    required this.player,
    required this.lyrics,
    this.backendConnected = false,
    required this.onExpand,
    required this.onPlaylist,
  });

  @override
  State<PlayerBar> createState() => _PlayerBarState();
}

class _PlayerBarState extends State<PlayerBar> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.player,
      builder: (context, _) => _buildBar(context),
    );
  }

  Widget _buildBar(BuildContext context) {
    final colors = context.colors;
    final player = widget.player;
    final song = player.currentSong;

    if (song == null) {
      return MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 52,
          color: _hover ? colors.hoverLayer : colors.glass,
          child: Center(
            child: Text(
              '未在播放',
              style: TextStyle(fontSize: 13, color: colors.textTertiary),
            ),
          ),
        ),
      );
    }

    final lyricIndex = player.currentLyricIndex(widget.lyrics);
    final lyricText =
        lyricIndex >= 0 && lyricIndex < widget.lyrics.length
            ? widget.lyrics[lyricIndex].text
            : '';

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 52,
        decoration: BoxDecoration(
          color: _hover ? colors.hoverLayer : colors.glass,
          border: Border(top: BorderSide(color: colors.glassBorder)),
        ),
        child: Stack(
          children: [
            // 顶部细进度条
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SizedBox(
                height: 3,
                child: LinearProgressIndicator(
                  value: player.progress,
                  backgroundColor: Colors.transparent,
                  color: colors.accent,
                ),
              ),
            ),
            Row(
              children: [
                // 左侧信息(点击展开)
                Expanded(
                  child: InkWell(
                    onTap: widget.onExpand,
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        CoverImage(
                          seed: song.id,
                          size: 36,
                          radius: BorderRadius.circular(4),
                          url: song.coverUrl,
                        ),
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
                // 中间控制区(固定宽度,视觉居中)
                SizedBox(
                  width: 280,
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
                // 右侧区域
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconBtn(
                        icon: _playMethodIcon(player.playMethod),
                        size: 18,
                        tooltip: _playMethodLabel(player.playMethod),
                        color: player.playMethod == 'Shuffle'
                            ? colors.accent
                            : colors.textSecondary,
                        onTap: player.cyclePlayMethod,
                      ),
                      IconBtn(
                        icon: Icons.queue_music_rounded,
                        size: 20,
                        tooltip: '播放列表',
                        onTap: widget.onPlaylist,
                      ),
                      const SizedBox(width: 4),
                      // 内核连接指示灯
                      Tooltip(
                        message: widget.backendConnected ? '内核已连接' : '内核未连接',
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.backendConnected
                                ? const Color(0xFF34C759)
                                : colors.textTertiary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

IconData _playMethodIcon(String method) {
  switch (method) {
    case 'Repeat one':
      return Icons.repeat_one_rounded;
    case 'Play in order':
      return Icons.list_alt_rounded;
    case 'Shuffle':
      return Icons.shuffle_rounded;
    case 'Intelligent':
      return Icons.auto_awesome_rounded;
    default:
      return Icons.repeat_rounded;
  }
}

String _playMethodLabel(String method) {
  switch (method) {
    case 'Repeat one':
      return '单曲循环';
    case 'Play in order':
      return '顺序播放';
    case 'Shuffle':
      return '随机播放';
    case 'Intelligent':
      return '智能播放';
    default:
      return '列表循环';
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
