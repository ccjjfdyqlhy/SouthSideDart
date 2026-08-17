import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import '../models/models.dart';
import '../state/player_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/folder_card.dart';
import '../widgets/song_card.dart';

/// 首页:标题 + 账号问候 + 模式卡 + 推荐歌单 + 推荐歌曲。
class HomePage extends StatelessWidget {
  final PlayerState player;
  final ValueChanged<Folder> onFolderTap;

  const HomePage({
    super.key,
    required this.player,
    required this.onFolderTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final folders = mockFolders();
    final songs = mockRecommendedSongs();

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Text(
                  '首页',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  '欢迎回来,Darkstar',
                  style: TextStyle(fontSize: 15, color: colors.textSecondary),
                ),
                const SizedBox(width: 10),
                const CircleAvatar(radius: 24, backgroundColor: Color(0xFF8E7CC3)),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          sliver: SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Row(
                  children: [
                    for (final card in mockModeCards) ...[
                      Expanded(
                        child: _ModeCard(card: card),
                      ),
                      if (card != mockModeCards.last) const SizedBox(width: 12),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          sliver: SliverToBoxAdapter(
            child: SectionHeader(
              title: '推荐歌单',
              trailing: Text(
                '${folders.length}',
                style: TextStyle(fontSize: 15, color: colors.textTertiary),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.crossAxisExtent;
              final cardW = ((width - 36) / 4).clamp(120.0, 260.0);
              return SliverGrid(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: cardW + 16,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 16,
                  childAspectRatio: cardW / (cardW + 52),
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final f = folders[index];
                    return FolderCard(
                      folder: f,
                      width: cardW,
                      onTap: () => onFolderTap(f),
                    );
                  },
                  childCount: folders.length,
                ),
              );
            },
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          sliver: SliverToBoxAdapter(
            child: SectionHeader(
              title: '推荐歌曲',
              trailing: Text(
                '${songs.length}',
                style: TextStyle(fontSize: 15, color: colors.textTertiary),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          sliver: SliverList.separated(
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              return SongCard(
                song: song,
                onPlay: () => player.playSong(song),
                onInsert: () {},
                onFavorite: () {},
              );
            },
            separatorBuilder: (_, _) => const SizedBox(height: 2),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 20)),
      ],
    );
  }
}

/// 模式卡(心语/私人漫游/私人雷达/相似歌曲):渐变背景 + 白字。
class _ModeCard extends StatefulWidget {
  final ModeCard card;

  const _ModeCard({required this.card});

  @override
  State<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<_ModeCard> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.card;
    return Material(
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: const [
              Color(0xFF3A3A5C),
              Color(0xFF2A2A45),
            ],
          ),
        ),
        child: InkWell(
          onTap: _loading
              ? null
              : () {
                  setState(() => _loading = true);
                  Future.delayed(const Duration(milliseconds: 1800), () {
                    if (mounted) setState(() => _loading = false);
                  });
                },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: SizedBox(
              height: 140,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        c.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        _modeIcon(c.icon),
                        color: Colors.white.withValues(alpha: 0.85),
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Text(
                      c.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    c.hint,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.67),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 2,
                    child: _loading
                        ? const LinearProgressIndicator(
                            backgroundColor: Colors.transparent,
                            color: Colors.white,
                            minHeight: 2,
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _modeIcon(String key) {
    switch (key) {
      case 'heart':
        return Icons.favorite_rounded;
      case 'explore':
        return Icons.explore_rounded;
      case 'radar':
        return Icons.radar_rounded;
      case 'similar':
        return Icons.graphic_eq_rounded;
      default:
        return Icons.music_note_rounded;
    }
  }
}
