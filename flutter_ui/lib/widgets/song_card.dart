import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// 横向歌曲卡片:封面(小)在左,曲名/歌手在右侧,高度与播放底栏一致。
class SongCard extends StatefulWidget {
  final Song song;
  final VoidCallback onPlay;
  final VoidCallback onInsert;
  final VoidCallback onFavorite;

  /// 点击歌手名打开歌手页。
  final ValueChanged<Artist>? onArtistTap;

  const SongCard({
    super.key,
    required this.song,
    required this.onPlay,
    required this.onInsert,
    required this.onFavorite,
    this.onArtistTap,
  });

  @override
  State<SongCard> createState() => _SongCardState();
}

class _SongCardState extends State<SongCard> {
  bool _hover = false;

  static const double _height = 56;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final s = widget.song;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: _hover ? colors.hoverLayer : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        height: _height,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            CoverImage(
              seed: s.id,
              size: _height - 12,
              radius: BorderRadius.circular(4),
              url: s.coverUrl,
            ),
            const SizedBox(width: 10),
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
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                      children: [
                        for (var i = 0; i < s.artists.length; i++) ...[
                          if (i > 0) const TextSpan(text: ' / '),
                          if (widget.onArtistTap != null)
                            WidgetSpan(
                              alignment: PlaceholderAlignment.baseline,
                              baseline: TextBaseline.alphabetic,
                              child: GestureDetector(
                                onTap: () => widget.onArtistTap!(s.artists[i]),
                                child: Text(
                                  s.artists[i].name,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.accent,
                                  ),
                                ),
                              ),
                            )
                          else
                            TextSpan(text: s.artists[i].name),
                        ],
                        TextSpan(text: ' · ${s.album}'),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                    size: 24,
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
