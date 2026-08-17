import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import '../models/models.dart';
import '../state/player_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// 播放页布局模式。
enum PlayingLayout {
  /// 经典:左封面 + 右歌词滚动列表。
  classic,

  /// 单行歌词:歌词居中仅显示一行,歌曲信息与控制条在底部。
  line,
}

/// 播放详情页(全屏覆盖整个窗口)。
/// 支持两种布局:`classic` 与 `line`,左上角按钮切换。
class PlayingPage extends StatefulWidget {
  final PlayerState player;
  final VoidCallback onCollapse;

  const PlayingPage({
    super.key,
    required this.player,
    required this.onCollapse,
  });

  @override
  State<PlayingPage> createState() => _PlayingPageState();
}

class _PlayingPageState extends State<PlayingPage> {
  PlayingLayout _layout = PlayingLayout.classic;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final song = widget.player.currentSong;
    if (song == null) {
      return const SizedBox.shrink();
    }

    return Container(
      color: colors.background,
      child: Stack(
        children: [
          // 主题色氛围光晕(Apple Music 风格)
          Positioned(
            top: -120,
            right: -80,
            child: RepaintBoundary(
              child: Container(
                width: 420,
                height: 420,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      colors.accent.withValues(alpha: 0.22),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 16,
            left: 16,
            child: _FloatingActions(
              layout: _layout,
              onCollapse: widget.onCollapse,
              onToggleLayout: () => setState(() {
                _layout = _layout == PlayingLayout.classic
                    ? PlayingLayout.line
                    : PlayingLayout.classic;
              }),
            ),
          ),
          if (_layout == PlayingLayout.classic)
            _ClassicLayout(player: widget.player, song: song)
          else
            _LineLyricsLayout(player: widget.player, song: song),
        ],
      ),
    );
  }
}

/// 经典布局:左封面 + 右歌词滚动。
class _ClassicLayout extends StatelessWidget {
  final PlayerState player;
  final Song song;

  const _ClassicLayout({required this.player, required this.song});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RepaintBoundary(
                  child: Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 30,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: CoverImage(
                      seed: song.id,
                      size: 280,
                      radius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  song.name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  song.artistNames,
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                _ProgressControls(player: player),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 5,
          child: _LyricsPanel(player: player),
        ),
      ],
    );
  }
}

/// 单行歌词布局:歌词居中仅显示一行,歌曲名与控制条在底部。
class _LineLyricsLayout extends StatelessWidget {
  final PlayerState player;
  final Song song;

  const _LineLyricsLayout({required this.player, required this.song});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lyrics = mockLyrics();

    return Column(
      children: [
        const Spacer(flex: 3),
        // 居中单行歌词
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: _LineLyricText(
            player: player,
            lyrics: lyrics,
            colors: colors,
          ),
        ),
        const Spacer(flex: 2),
        // 底部:歌曲信息 + 进度 + 控制
        Padding(
          padding: const EdgeInsets.fromLTRB(48, 0, 48, 24),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  RepaintBoundary(
                    child: CoverImage(
                      seed: song.id,
                      size: 44,
                      radius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song.artistNames,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 20),
                  IconBtn(
                    icon: Icons.favorite_border_rounded,
                    size: 20,
                    tooltip: '收藏',
                    color: colors.danger,
                    onTap: () {},
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _LineProgress(player: player),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconBtn(
                    icon: Icons.skip_previous_rounded,
                    size: 30,
                    onTap: player.previous,
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    onPressed: player.toggle,
                    iconSize: 56,
                    color: colors.textPrimary,
                    icon: Icon(
                      player.isPlaying
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded,
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconBtn(
                    icon: Icons.skip_next_rounded,
                    size: 30,
                    onTap: player.next,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 单行歌词文本:当前行放大显示,切行时淡入淡出。
class _LineLyricText extends StatelessWidget {
  final PlayerState player;
  final List<LyricLine> lyrics;
  final AppColors colors;

  const _LineLyricText({
    required this.player,
    required this.lyrics,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final idx = player.currentLyricIndex(lyrics);
        final text = lyrics.isNotEmpty ? lyrics[idx].text : '';
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          child: Text(
            text,
            key: ValueKey(idx),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
        );
      },
    );
  }
}

/// 底部单行布局的进度条(时间 + 进度)。
class _LineProgress extends StatelessWidget {
  final PlayerState player;

  const _LineProgress({required this.player});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    String fmt(double ms) {
      final total = ms ~/ 1000;
      final m = total ~/ 60;
      final s = total % 60;
      return '$m:${s.toString().padLeft(2, '0')}';
    }

    return SizedBox(
      width: 420,
      child: AnimatedBuilder(
        animation: player,
        builder: (context, _) {
          return Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                ),
                child: Slider(
                  value: player.progress,
                  activeColor: colors.accent,
                  inactiveColor: colors.divider,
                  onChanged: player.seek,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      fmt(player.positionMs),
                      style:
                          TextStyle(fontSize: 12, color: colors.textTertiary),
                    ),
                    Text(
                      fmt(player.durationMs),
                      style:
                          TextStyle(fontSize: 12, color: colors.textTertiary),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FloatingActions extends StatelessWidget {
  final PlayingLayout layout;
  final VoidCallback onCollapse;
  final VoidCallback onToggleLayout;

  const _FloatingActions({
    required this.layout,
    required this.onCollapse,
    required this.onToggleLayout,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isLine = layout == PlayingLayout.line;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.glass,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBtn(
            icon: Icons.keyboard_arrow_down_rounded,
            size: 22,
            tooltip: '收起',
            onTap: onCollapse,
          ),
          const SizedBox(height: 4),
          IconBtn(
            icon: isLine
                ? Icons.view_day_rounded
                : Icons.format_align_center_rounded,
            size: 18,
            tooltip: isLine ? '切换为经典布局' : '切换为单行歌词',
            color: colors.textSecondary,
            onTap: onToggleLayout,
          ),
          const SizedBox(height: 4),
          IconBtn(
            icon: Icons.translate_rounded,
            size: 18,
            tooltip: '翻译',
            onTap: () {},
          ),
          IconBtn(
            icon: Icons.video_settings_rounded,
            size: 18,
            tooltip: '导出歌词视频',
            onTap: () {},
          ),
          IconBtn(
            icon: Icons.edit_rounded,
            size: 18,
            tooltip: '编辑歌词',
            onTap: () {},
          ),
          IconBtn(
            icon: Icons.comment_rounded,
            size: 18,
            tooltip: '查看评论',
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

/// 经典布局进度控制区。
class _ProgressControls extends StatelessWidget {
  final PlayerState player;

  const _ProgressControls({required this.player});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    String fmt(double ms) {
      final total = ms ~/ 1000;
      final m = total ~/ 60;
      final s = total % 60;
      return '$m:${s.toString().padLeft(2, '0')}';
    }

    return SizedBox(
      width: 420,
      child: AnimatedBuilder(
        animation: player,
        builder: (context, _) {
          return Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                ),
                child: Slider(
                  value: player.progress,
                  activeColor: colors.accent,
                  inactiveColor: colors.divider,
                  onChanged: player.seek,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      fmt(player.positionMs),
                      style:
                          TextStyle(fontSize: 12, color: colors.textTertiary),
                    ),
                    Row(
                      children: [
                        IconBtn(
                          icon: Icons.skip_previous_rounded,
                          size: 28,
                          onTap: player.previous,
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          onPressed: player.toggle,
                          iconSize: 52,
                          color: colors.textPrimary,
                          icon: Icon(
                            player.isPlaying
                                ? Icons.pause_circle_filled_rounded
                                : Icons.play_circle_fill_rounded,
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconBtn(
                          icon: Icons.skip_next_rounded,
                          size: 28,
                          onTap: player.next,
                        ),
                      ],
                    ),
                    Text(
                      fmt(player.durationMs),
                      style:
                          TextStyle(fontSize: 12, color: colors.textTertiary),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 歌词面板:内部监听播放进度,仅当当前行变化时才重建,降低帧率开销。
class _LyricsPanel extends StatefulWidget {
  final PlayerState player;

  const _LyricsPanel({required this.player});

  @override
  State<_LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<_LyricsPanel> {
  static final List<LyricLine> _lyrics = mockLyrics();
  int _current = 0;

  @override
  void initState() {
    super.initState();
    widget.player.addListener(_onPlayerChanged);
    _current = widget.player.currentLyricIndex(_lyrics);
  }

  @override
  void didUpdateWidget(covariant _LyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) {
      oldWidget.player.removeListener(_onPlayerChanged);
      widget.player.addListener(_onPlayerChanged);
    }
  }

  @override
  void dispose() {
    widget.player.removeListener(_onPlayerChanged);
    super.dispose();
  }

  void _onPlayerChanged() {
    final idx = widget.player.currentLyricIndex(_lyrics);
    if (idx != _current) {
      setState(() => _current = idx);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 480,
        child: _AutoScrollLyrics(
          lyrics: _lyrics,
          currentIndex: _current,
        ),
      ),
    );
  }
}

/// 自动滚动歌词列表(Apple Music 风格:当前行放大,其他行缩小淡出)。
class _AutoScrollLyrics extends StatefulWidget {
  final List<LyricLine> lyrics;
  final int currentIndex;

  const _AutoScrollLyrics({
    required this.lyrics,
    required this.currentIndex,
  });

  @override
  State<_AutoScrollLyrics> createState() => _AutoScrollLyricsState();
}

class _AutoScrollLyricsState extends State<_AutoScrollLyrics> {
  final ScrollController _controller = ScrollController();

  @override
  void didUpdateWidget(covariant _AutoScrollLyrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      final item = widget.currentIndex.clamp(0, widget.lyrics.length - 1);
      final target = item * 52.0 - 120;
      _controller.animateTo(
        target.clamp(0, _controller.position.maxScrollExtent),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListView.builder(
      controller: _controller,
      padding: const EdgeInsets.symmetric(vertical: 120),
      itemCount: widget.lyrics.length,
      itemBuilder: (context, index) {
        final line = widget.lyrics[index];
        final isCurrent = index == widget.currentIndex;
        final distance = (index - widget.currentIndex).abs();
        return RepaintBoundary(
          child: SizedBox(
            height: 52,
            child: Center(
              child: AnimatedScale(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                scale: isCurrent ? 1.0 : 0.8,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 350),
                  opacity: isCurrent ? 1.0 : (distance <= 2 ? 0.55 : 0.3),
                  child: Text(
                    line.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: isCurrent
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isCurrent
                          ? colors.textPrimary
                          : colors.lyricInactive,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
