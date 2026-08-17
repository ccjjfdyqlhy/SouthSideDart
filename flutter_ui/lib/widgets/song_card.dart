import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// 歌曲卡片:封面 + 歌名/歌手 + 时长 + 悬停操作(插入/播放/收藏)。
class SongCard extends StatefulWidget {
  final Song song;
  final bool showCover;
  final VoidCallback onPlay;
  final VoidCallback onInsert;
  final VoidCallback onFavorite;

  const SongCard({
    super.key,
    required this.song,
    this.showCover = true,
    required this.onPlay,
    required this.onInsert,
    required this.onFavorite,
  });

  @override
  State<SongCard> createState() => _SongCardState();
}

class _SongCardState extends State<SongCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final s = widget.song;
    final cardHeight = widget.showCover ? 150.0 : 56.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: _hover ? colors.hoverLayer : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        height: cardHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (widget.showCover) ...[
              CoverImage(seed: s.id, size: cardHeight - 16),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${s.artistNames} · ${s.album}',
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
            const SizedBox(width: 12),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: _hover ? 1 : 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconBtn(
                    icon: Icons.playlist_add_rounded,
                    size: 18,
                    tooltip: '插入到播放之后',
                    color: colors.textSecondary,
                    onTap: widget.onInsert,
                  ),
                  IconBtn(
                    icon: Icons.favorite_border_rounded,
                    size: 18,
                    tooltip: '收藏',
                    color: colors.danger,
                    onTap: widget.onFavorite,
                  ),
                  IconBtn(
                    icon: Icons.play_circle_fill_rounded,
                    size: 26,
                    tooltip: '播放',
                    color: colors.accent,
                    onTap: widget.onPlay,
                  ),
                ],
              ),
            ),
            Text(
              s.durationText,
              style: TextStyle(fontSize: 12, color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
