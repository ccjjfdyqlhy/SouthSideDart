import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../services/backend_store.dart';
import '../state/player_state.dart';
import '../theme/app_theme.dart';
import '../widgets/album_mesh_background.dart';
import '../widgets/common.dart';

/// 播放页布局模式。
enum PlayingLayout {
  /// 经典:左封面 + 右歌词滚动列表。
  classic,

  /// 单行歌词:歌词居中仅显示一行,歌曲信息与控制条在底部。
  line,
}

/// 播放详情页(全屏覆盖整个窗口)。
/// 支持两种布局 + 完整播放器控件(分享/下载/红心/音质/播放模式/播放列表)。
class PlayingPage extends StatefulWidget {
  final PlayerState player;

  /// 歌词(优先后端真实歌词)。
  final List<LyricLine> lyrics;
  final BackendStore? store;
  final VoidCallback? onComments;

  /// 打开播放列表抽屉。
  final VoidCallback? onPlaylist;

  /// 点击歌手名打开歌手页。
  final ValueChanged<int>? onArtistTap;
  final VoidCallback onCollapse;

  const PlayingPage({
    super.key,
    required this.player,
    this.lyrics = const [],
    this.store,
    this.onComments,
    this.onPlaylist,
    this.onArtistTap,
    required this.onCollapse,
  });

  @override
  State<PlayingPage> createState() => _PlayingPageState();
}

class _PlayingPageState extends State<PlayingPage> {
  PlayingLayout _layout = PlayingLayout.classic;
  bool _showTranslation = true;
  int _quality = 3200000;
  bool _downloading = false;

  void _toggleTranslation() {
    setState(() => _showTranslation = !_showTranslation);
    _setConfig('show_translation', _showTranslation);
  }

  void _selectQuality(int bitrate) {
    setState(() => _quality = bitrate);
    _setConfig('play_quality', bitrate);
  }

  void _setConfig(String key, Object value) {
    final store = widget.store;
    if (store == null || !store.client.isConnected) return;
    unawaited(
      store.client
          .call('set_config', {'key': key, 'value': value})
          .catchError((Object _) => <String, dynamic>{}),
    );
  }

  String _qualityLabel(int bitrate) {
    switch (bitrate) {
      case 128000:
        return '标准音质';
      case 320000:
        return '高品音质';
      default:
        return '无损音质';
    }
  }

  /// 复制分享链接(网易云歌曲页)。
  Future<void> _shareSong(Song song) async {
    final url = 'https://music.163.com/#/song?id=${song.id}';
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制分享链接:${song.name}')),
    );
  }

  /// 下载歌曲到 ~/Downloads(经内核获取音频 URL)。
  Future<void> _downloadSong(Song song) async {
    if (_downloading || song.id <= 0) return;
    final store = widget.store;
    if (store == null || !store.client.isConnected) return;
    setState(() => _downloading = true);
    try {
      final r = await store.client.call('download_song', {
        'song_id': song.id.toString(),
        'bitrate': _quality,
      });
      final url = ((r['result'] as Map<String, dynamic>?) ?? {})['url'];
      if (url == null) throw StateError('no url');
      final home = Platform.isWindows
          ? (Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.')
          : (Platform.environment['HOME'] ?? '.');
      final dir = Directory('$home/Downloads');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final safe = song.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final file = File('${dir.path}/$safe.mp3');
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url.toString()));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw StateError('http ${response.statusCode}');
      }
      final sink = file.openWrite();
      await response.pipe(sink);
      await sink.close();
      client.close();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已下载到 ${file.path}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败:$e')),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final song = widget.player.currentSong;
    if (song == null) {
      return const SizedBox.shrink();
    }
    final translated = (widget.store?.currentTranslatedLyrics.isNotEmpty ??
            false)
        ? widget.store!.currentTranslatedLyrics
        : const <LyricLine>[];

    return Container(
      color: colors.background,
      child: Stack(
        children: [
          // 封面取色流动网格渐变背景(参考 applemusiclrc MeshGradientRenderer)
          Positioned.fill(
            child: RepaintBoundary(
              child: AlbumMeshBackground(
                coverUrl: song.coverUrl,
                child: const SizedBox.expand(),
              ),
            ),
          ),
          // 右上角:收起 + 单行歌词切换
          Positioned(
            top: 16,
            right: 16,
            child: _TopBarButtons(
              isLine: _layout == PlayingLayout.line,
              onCollapse: widget.onCollapse,
              onToggleLayout: () => setState(() {
                _layout = _layout == PlayingLayout.classic
                    ? PlayingLayout.line
                    : PlayingLayout.classic;
              }),
            ),
          ),
          // 右下角:歌词设置(带文字选项面板)
          Positioned(
            bottom: 16,
            right: 16,
            child: _LyricsSettingsButton(
              showTranslation: _showTranslation,
              onToggleTranslation: _toggleTranslation,
              onComments: widget.onComments,
            ),
          ),
          if (_layout == PlayingLayout.classic)
            _ClassicLayout(
              player: widget.player,
              song: song,
              lyrics: widget.lyrics,
              translatedLyrics: _showTranslation ? translated : const [],
              qualityLabel: _qualityLabel(_quality),
              downloading: _downloading,
              currentQuality: _quality,
              onQualitySelected: _selectQuality,
              onShare: () => _shareSong(song),
              onDownload: () => _downloadSong(song),
              onPlaylist: widget.onPlaylist,
              onArtistTap: widget.onArtistTap,
            )
          else
            _LineLyricsLayout(
              player: widget.player,
              song: song,
              lyrics: widget.lyrics,
              translatedLyrics: _showTranslation ? translated : const [],
              qualityLabel: _qualityLabel(_quality),
              downloading: _downloading,
              currentQuality: _quality,
              onQualitySelected: _selectQuality,
              onShare: () => _shareSong(song),
              onDownload: () => _downloadSong(song),
              onPlaylist: widget.onPlaylist,
              onArtistTap: widget.onArtistTap,
            ),
        ],
      ),
    );
  }
}

/// 经典布局:左封面 + 右歌词滚动。
class _ClassicLayout extends StatelessWidget {
  final PlayerState player;
  final Song song;
  final List<LyricLine> lyrics;
  final List<LyricLine> translatedLyrics;
  final String qualityLabel;
  final bool downloading;
  final int currentQuality;
  final ValueChanged<int>? onQualitySelected;
  final VoidCallback onShare;
  final VoidCallback onDownload;
  final VoidCallback? onPlaylist;
  final ValueChanged<int>? onArtistTap;

  const _ClassicLayout({
    required this.player,
    required this.song,
    required this.lyrics,
    required this.translatedLyrics,
    required this.qualityLabel,
    required this.downloading,
    required this.currentQuality,
    this.onQualitySelected,
    required this.onShare,
    required this.onDownload,
    this.onPlaylist,
    this.onArtistTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 封面 + 右上分享按钮
                  Stack(
                    clipBehavior: Clip.none,
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
                            url: song.coverUrl,
                          ),
                        ),
                      ),
                      Positioned(
                        top: -8,
                        right: -8,
                        child: IconBtn(
                          icon: Icons.share_rounded,
                          size: 18,
                          tooltip: '复制分享链接',
                          color: colors.textSecondary,
                          onTap: onShare,
                        ),
                      ),
                    ],
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
                  // 歌手名(每个歌手可点击)
                  Text.rich(
                    TextSpan(
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.accent,
                      ),
                      children: [
                        for (var i = 0; i < song.artists.length; i++) ...[
                          if (i > 0) const TextSpan(text: ' / '),
                          if (onArtistTap != null)
                            WidgetSpan(
                              alignment: PlaceholderAlignment.baseline,
                              baseline: TextBaseline.alphabetic,
                              child: GestureDetector(
                                onTap: () =>
                                    onArtistTap?.call(song.artists[i].id),
                                child: Text(
                                  song.artists[i].name,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: colors.accent,
                                    decoration: TextDecoration.underline,
                                    decorationColor: colors.accent
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                              ),
                            )
                          else
                            TextSpan(text: song.artists[i].name),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 红心切换(靠右)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 32),
                      child: AnimatedBuilder(
                        animation: player,
                        builder: (context, _) => IconBtn(
                          icon: player.isLiked(song.id)
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 22,
                          tooltip: player.isLiked(song.id) ? '取消收藏' : '收藏',
                          color: colors.danger,
                          onTap: () => player.toggleLike(song),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 音质显示(进度条上方)
                  Text(
                    qualityLabel,
                    style: TextStyle(fontSize: 12, color: colors.textTertiary),
                  ),
                  const SizedBox(height: 4),
                  _ProgressControls(
                    player: player,
                    downloading: downloading,
                    onDownload: onDownload,
                    onPlaylist: onPlaylist,
                    currentQuality: currentQuality,
                    onQualitySelected: onQualitySelected,
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          flex: 5,
          child: _LyricsPanel(
            player: player,
            lyrics: lyrics,
            translatedLyrics: translatedLyrics,
          ),
        ),
      ],
    );
  }
}

/// 底部控制区:下载/上一曲/播放/下一曲/播放列表/播放模式。
class _ProgressControls extends StatelessWidget {
  final PlayerState player;
  final bool downloading;
  final VoidCallback onDownload;
  final VoidCallback? onPlaylist;
  final int currentQuality;
  final ValueChanged<int>? onQualitySelected;

  const _ProgressControls({
    required this.player,
    required this.downloading,
    required this.onDownload,
    this.onPlaylist,
    this.currentQuality = 3200000,
    this.onQualitySelected,
  });

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
      width: 460,
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
                child: TweenAnimationBuilder<double>(
                  // 进度插值:把 100ms 的轮询跳变平滑为连续滑动。
                  tween: Tween(begin: player.progress, end: player.progress),
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.linear,
                  builder: (context, value, _) => Slider(
                    value: value.clamp(0.0, 1.0),
                    activeColor: colors.accent,
                    inactiveColor: colors.divider,
                    onChanged: player.seek,
                  ),
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
                    // 下载 | 上一曲 | 播放 | 下一曲 | 播放列表 | 播放模式
                    Row(
                      children: [
                        // 音质切换(下载按钮左侧)
                        PopupMenuButton<int>(
                          tooltip: '音质',
                          enabled: onQualitySelected != null,
                          onSelected: onQualitySelected,
                          color: colors.card,
                          icon: Icon(
                            Icons.high_quality_rounded,
                            size: 20,
                            color: colors.textSecondary,
                          ),
                          itemBuilder: (context) => [
                            for (final q in const [
                              (128000, '标准音质'),
                              (320000, '高品音质'),
                              (3200000, '无损音质'),
                            ])
                              PopupMenuItem(
                                value: q.$1,
                                child: Row(
                                  children: [
                                    Icon(
                                      q.$1 == currentQuality
                                          ? Icons.check_rounded
                                          : Icons.circle,
                                      size: 14,
                                      color: q.$1 == currentQuality
                                          ? colors.accent
                                          : Colors.transparent,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(q.$2),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 2),
                        IconBtn(
                          icon: Icons.download_rounded,
                          size: 20,
                          tooltip: '下载歌曲',
                          color: colors.textSecondary,
                          onTap: downloading ? null : onDownload,
                        ),
                        const SizedBox(width: 2),
                        IconBtn(
                          icon: Icons.skip_previous_rounded,
                          size: 28,
                          onTap: player.previous,
                        ),
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
                        IconBtn(
                          icon: Icons.skip_next_rounded,
                          size: 28,
                          onTap: player.next,
                        ),
                        const SizedBox(width: 2),
                        IconBtn(
                          icon: Icons.queue_music_rounded,
                          size: 20,
                          tooltip: '播放列表',
                          color: colors.textSecondary,
                          onTap: onPlaylist,
                        ),
                        const SizedBox(width: 2),
                        IconBtn(
                          icon: _playMethodIcon(player.playMethod),
                          size: 20,
                          tooltip: _playMethodLabel(player.playMethod),
                          color: player.playMethod == 'Shuffle'
                              ? colors.accent
                              : colors.textSecondary,
                          onTap: player.cyclePlayMethod,
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

/// 单行歌词布局:歌词居中仅显示一行,歌曲信息与控制条在底部。
class _LineLyricsLayout extends StatelessWidget {
  final PlayerState player;
  final Song song;
  final List<LyricLine> lyrics;
  final List<LyricLine> translatedLyrics;
  final String qualityLabel;
  final bool downloading;
  final int currentQuality;
  final ValueChanged<int>? onQualitySelected;
  final VoidCallback onShare;
  final VoidCallback onDownload;
  final VoidCallback? onPlaylist;
  final ValueChanged<int>? onArtistTap;

  const _LineLyricsLayout({
    required this.player,
    required this.song,
    required this.lyrics,
    required this.translatedLyrics,
    required this.qualityLabel,
    required this.downloading,
    required this.currentQuality,
    this.onQualitySelected,
    required this.onShare,
    required this.onDownload,
    this.onPlaylist,
    this.onArtistTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        const Spacer(flex: 3),
        // 居中单行歌词
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: _LineLyricText(
            player: player,
            lyrics: lyrics,
            translatedLyrics: translatedLyrics,
            colors: colors,
          ),
        ),
        const Spacer(flex: 2),
        // 底部:歌曲信息 + 控制
        Padding(
          padding: const EdgeInsets.fromLTRB(48, 0, 48, 16),
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
                      url: song.coverUrl,
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
                      Text.rich(
                        TextSpan(
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.accent,
                          ),
                          children: [
                            for (var i = 0; i < song.artists.length; i++) ...[
                              if (i > 0) const TextSpan(text: ' / '),
                              if (onArtistTap != null)
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.baseline,
                                  baseline: TextBaseline.alphabetic,
                                  child: GestureDetector(
                                    onTap: () => onArtistTap
                                        ?.call(song.artists[i].id),
                                    child: Text(
                                      song.artists[i].name,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: colors.accent,
                                        decoration: TextDecoration.underline,
                                        decorationColor: colors.accent
                                            .withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ),
                                )
                              else
                                TextSpan(text: song.artists[i].name),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  IconBtn(
                    icon: Icons.share_rounded,
                    size: 18,
                    tooltip: '复制分享链接',
                    color: colors.textSecondary,
                    onTap: onShare,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                qualityLabel,
                style: TextStyle(fontSize: 12, color: colors.textTertiary),
              ),
              _LineProgress(player: player),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PopupMenuButton<int>(
                    tooltip: '音质',
                    enabled: onQualitySelected != null,
                    onSelected: onQualitySelected,
                    color: colors.card,
                    icon: Icon(
                      Icons.high_quality_rounded,
                      size: 20,
                      color: colors.textSecondary,
                    ),
                    itemBuilder: (context) => [
                      for (final q in const [
                        (128000, '标准音质'),
                        (320000, '高品音质'),
                        (3200000, '无损音质'),
                      ])
                        PopupMenuItem(
                          value: q.$1,
                          child: Row(
                            children: [
                              Icon(
                                q.$1 == currentQuality
                                    ? Icons.check_rounded
                                    : Icons.circle,
                                size: 14,
                                color: q.$1 == currentQuality
                                    ? colors.accent
                                    : Colors.transparent,
                              ),
                              const SizedBox(width: 8),
                              Text(q.$2),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  IconBtn(
                    icon: Icons.download_rounded,
                    size: 20,
                    tooltip: '下载歌曲',
                    color: colors.textSecondary,
                    onTap: downloading ? null : onDownload,
                  ),
                  const SizedBox(width: 14),
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
                  const SizedBox(width: 14),
                  IconBtn(
                    icon: Icons.queue_music_rounded,
                    size: 22,
                    tooltip: '播放列表',
                    color: colors.textSecondary,
                    onTap: onPlaylist,
                  ),
                  const SizedBox(width: 8),
                  IconBtn(
                    icon: _playMethodIcon(player.playMethod),
                    size: 22,
                    tooltip: _playMethodLabel(player.playMethod),
                    color: player.playMethod == 'Shuffle'
                        ? colors.accent
                        : colors.textSecondary,
                    onTap: player.cyclePlayMethod,
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

/// 单行歌词文本:当前行放大显示,切行时淡入淡出,可附翻译。
class _LineLyricText extends StatelessWidget {
  final PlayerState player;
  final List<LyricLine> lyrics;
  final List<LyricLine> translatedLyrics;
  final AppColors colors;

  const _LineLyricText({
    required this.player,
    required this.lyrics,
    required this.translatedLyrics,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final idx = player.currentLyricIndex(lyrics);
        final text =
            idx >= 0 && idx < lyrics.length ? lyrics[idx].text : '';
        final translated = translatedLyrics.isNotEmpty &&
                idx >= 0 &&
                idx < translatedLyrics.length
            ? translatedLyrics[idx].text
            : '';
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          child: Column(
            key: ValueKey(idx),
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              if (translated.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  translated,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ],
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
                child: TweenAnimationBuilder<double>(
                  // 进度插值:把 100ms 的轮询跳变平滑为连续滑动。
                  tween: Tween(begin: player.progress, end: player.progress),
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.linear,
                  builder: (context, value, _) => Slider(
                    value: value.clamp(0.0, 1.0),
                    activeColor: colors.accent,
                    inactiveColor: colors.divider,
                    onChanged: player.seek,
                  ),
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

/// 右上角固定按钮:收起 + 单行歌词切换。
class _TopBarButtons extends StatelessWidget {
  final bool isLine;
  final VoidCallback onCollapse;
  final VoidCallback onToggleLayout;

  const _TopBarButtons({
    required this.isLine,
    required this.onCollapse,
    required this.onToggleLayout,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.glass,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconBtn(
            icon: Icons.keyboard_arrow_down_rounded,
            size: 22,
            tooltip: '收起',
            onTap: onCollapse,
          ),
          const SizedBox(width: 4),
          IconBtn(
            icon: isLine
                ? Icons.view_day_rounded
                : Icons.format_align_center_rounded,
            size: 18,
            tooltip: isLine ? '切换为经典布局' : '切换为单行歌词',
            color: colors.textSecondary,
            onTap: onToggleLayout,
          ),
        ],
      ),
    );
  }
}

/// 右下角"歌词设置"图标:展开带文字的选项面板。
class _LyricsSettingsButton extends StatelessWidget {
  final bool showTranslation;
  final VoidCallback onToggleTranslation;
  final VoidCallback? onComments;

  const _LyricsSettingsButton({
    required this.showTranslation,
    required this.onToggleTranslation,
    this.onComments,
  });

  void _notImplemented(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature 功能将在后续版本接入内核'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.glass,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.glassBorder),
      ),
      child: PopupMenuButton<String>(
        tooltip: '歌词设置',
        color: colors.card,
        icon: Icon(
          Icons.settings_rounded,
          size: 18,
          color: colors.textSecondary,
        ),
        onSelected: (value) {
          switch (value) {
            case 'translation':
              onToggleTranslation();
            case 'export':
              _notImplemented(context, '导出歌词视频');
            case 'edit':
              _notImplemented(context, '歌词编辑');
            case 'comments':
              onComments?.call();
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'translation',
            child: Row(
              children: [
                Icon(
                  showTranslation ? Icons.check_rounded : Icons.circle,
                  size: 14,
                  color: showTranslation
                      ? colors.accent
                      : Colors.transparent,
                ),
                const SizedBox(width: 8),
                const Text('显示翻译'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'export',
            child: Text('导出歌词视频'),
          ),
          const PopupMenuItem(
            value: 'edit',
            child: Text('编辑歌词'),
          ),
          const PopupMenuItem(
            value: 'comments',
            child: Text('查看评论'),
          ),
        ],
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

/// 歌词面板:内部监听播放进度,仅当当前行变化时才重建。
class _LyricsPanel extends StatefulWidget {
  final PlayerState player;
  final List<LyricLine> lyrics;
  final List<LyricLine> translatedLyrics;

  const _LyricsPanel({
    required this.player,
    required this.lyrics,
    required this.translatedLyrics,
  });

  @override
  State<_LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<_LyricsPanel> {
  List<LyricLine> get _lyrics => widget.lyrics;
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
    if (oldWidget.lyrics != widget.lyrics) {
      _current = widget.player.currentLyricIndex(_lyrics);
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
    if (_lyrics.isEmpty) {
      return Center(
        child: Text(
          '暂无歌词',
          style: TextStyle(
            fontSize: 14,
            color: context.colors.textTertiary,
          ),
        ),
      );
    }
    return Center(
      child: SizedBox(
        width: 480,
        child: _AutoScrollLyrics(
          lyrics: _lyrics,
          translatedLyrics: widget.translatedLyrics,
          currentIndex: _current,
        ),
      ),
    );
  }
}

/// 自动滚动歌词列表(Apple Music 风格)。
class _AutoScrollLyrics extends StatefulWidget {
  final List<LyricLine> lyrics;
  final List<LyricLine> translatedLyrics;
  final int currentIndex;

  const _AutoScrollLyrics({
    required this.lyrics,
    required this.translatedLyrics,
    required this.currentIndex,
  });

  @override
  State<_AutoScrollLyrics> createState() => _AutoScrollLyricsState();
}

class _AutoScrollLyricsState extends State<_AutoScrollLyrics> {
  final ScrollController _controller = ScrollController();
  static const _rowHeight = 72.0;

  @override
  void didUpdateWidget(covariant _AutoScrollLyrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      final item = widget.currentIndex.clamp(0, widget.lyrics.length - 1);
      final target = item * _rowHeight - 120;
      _controller.animateTo(
        target.clamp(0, _controller.position.maxScrollExtent),
        duration: AppMotion.long,
        curve: AppMotion.curve,
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
        final translated = widget.translatedLyrics.isNotEmpty &&
                index < widget.translatedLyrics.length
            ? widget.translatedLyrics[index].text
            : '';
        final isCurrent = index == widget.currentIndex;
        final distance = (index - widget.currentIndex).abs();
        return RepaintBoundary(
          child: SizedBox(
            height: _rowHeight,
            child: Center(
              child: AnimatedScale(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                scale: isCurrent ? 1.0 : 0.8,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 350),
                  opacity: isCurrent ? 1.0 : (distance <= 2 ? 0.55 : 0.3),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
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
                      if (translated.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            translated,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                    ],
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
