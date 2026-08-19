import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'netease_image_provider.dart';

/// 根据歌曲封面提取主色,绘制流动的网格渐变动态背景。
///
/// 参考 applemusiclrc 项目 MeshGradientRenderer 的思路:
/// 封面缩小到 32x32 -> 调整对比度/饱和度/亮度 -> 提取亮度分桶主色 ->
/// 作为多个径向渐变控制点的颜色,控制点随时间做利萨如运动,叠加出流动效果。
class AlbumMeshBackground extends StatefulWidget {
  final String? coverUrl;
  final Widget child;

  const AlbumMeshBackground({super.key, this.coverUrl, required this.child});

  @override
  State<AlbumMeshBackground> createState() => _AlbumMeshBackgroundState();
}

class _AlbumMeshBackgroundState extends State<AlbumMeshBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  List<Color> _palette = const [];
  ui.Image? _thumb;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();
    _loadPalette();
  }

  @override
  void didUpdateWidget(covariant AlbumMeshBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverUrl != widget.coverUrl) {
      _loadPalette();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _thumb?.dispose();
    super.dispose();
  }

  Future<void> _loadPalette() async {
    final url = widget.coverUrl;
    if (url == null || url.isEmpty) {
      setState(() => _palette = const []);
      return;
    }
    try {
      final stream =
          NeteaseImageProvider(url).resolve(ImageConfiguration.empty);
      final completer = Completer<ui.Image>();
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          if (!completer.isCompleted) completer.complete(info.image);
        },
        onError: (e, _) {
          if (!completer.isCompleted) completer.completeError(e);
        },
      );
      stream.addListener(listener);
      final image = await completer.future;
      final thumb = await _shrinkImage(image, 32);
      final palette = await _extractPalette(thumb);
      if (!mounted) return;
      setState(() {
        _thumb?.dispose();
        _thumb = thumb;
        _palette = palette;
      });
    } catch (_) {
      // 取色失败时保留旧调色板(或空),回退为纯色背景。
    }
  }

  Future<ui.Image> _shrinkImage(ui.Image src, int size) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final side = math.min(src.width, src.height).toDouble();
    final sx = (src.width - side) / 2;
    final sy = (src.height - side) / 2;
    canvas.drawImageRect(
      src,
      Rect.fromLTWH(sx, sy, side, side),
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    final img = await picture.toImage(size, size);
    picture.dispose();
    return img;
  }

  /// 亮度分桶取主色:把 32x32 像素按亮度排序均分为 5 桶,取每桶平均色。
  Future<List<Color>> _extractPalette(ui.Image img) async {
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return const [];
    final bytes = data.buffer.asUint8List();
    final n = img.width * img.height;
    final pixels = <({double lum, int r, int g, int b})>[];
    for (var i = 0; i < n; i++) {
      final o = i * 4;
      final r = bytes[o];
      final g = bytes[o + 1];
      final b = bytes[o + 2];
      final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      pixels.add((lum: lum, r: r, g: g, b: b));
    }
    pixels.sort((a, b) => a.lum.compareTo(b.lum));
    const buckets = 5;
    final colors = <Color>[];
    for (var b = 0; b < buckets; b++) {
      final start = n * b ~/ buckets;
      final end = n * (b + 1) ~/ buckets;
      if (end <= start) continue;
      var sr = 0, sg = 0, sb = 0;
      for (var i = start; i < end; i++) {
        sr += pixels[i].r;
        sg += pixels[i].g;
        sb += pixels[i].b;
      }
      final cnt = end - start;
      colors.add(
        Color.fromARGB(255, sr ~/ cnt, sg ~/ cnt, sb ~/ cnt),
      );
    }
    // 温和提升饱和度、轻微压暗,避免背景过亮(参考 applemusiclrc filter 链)。
    return colors.map(_adjustColor).toList();
  }

  Color _adjustColor(Color c) {
    final hsl = HSLColor.fromColor(c);
    final adjusted = hsl
        .withSaturation((hsl.saturation * 1.35).clamp(0.0, 1.0))
        .withLightness((hsl.lightness * 0.82).clamp(0.0, 1.0));
    return adjusted.toColor();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _MeshPainter(
                palette: _palette,
                progress: _controller.value,
                baseColor: _palette.isNotEmpty
                    ? _palette.first
                    : Colors.grey.shade900,
              ),
            ),
            child!,
          ],
        );
      },
      child: widget.child,
    );
  }
}

/// 网格渐变绘制:多个径向渐变光斑随时间做利萨如运动。
class _MeshPainter extends CustomPainter {
  final List<Color> palette;
  final double progress;
  final Color baseColor;

  _MeshPainter({
    required this.palette,
    required this.progress,
    required this.baseColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 底色
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = baseColor,
    );
    if (palette.isEmpty) return;

    final w = size.width;
    final h = size.height;
    final t = progress * 2 * math.pi;
    final count = palette.length;
    final radius = math.max(w, h) * 0.9;

    for (var i = 0; i < count; i++) {
      final phase = i * (2 * math.pi / count);
      // 利萨如运动:每个控制点沿不同频率的椭圆轨迹流动
      final freqX = 0.5 + (i % 2) * 0.35;
      final freqY = 0.4 + ((i + 1) % 2) * 0.45;
      final cx = w * (0.5 + 0.38 * math.cos(t * freqX + phase));
      final cy = h * (0.5 + 0.38 * math.sin(t * freqY + phase * 1.7));
      final c = palette[i % count];
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            c.withValues(alpha: 0.55),
            c.withValues(alpha: 0.18),
            c.withValues(alpha: 0.0),
          ],
        ).createShader(
          Rect.fromCircle(center: Offset(cx, cy), radius: radius),
        )
        ..blendMode = BlendMode.screen;
      canvas.drawCircle(Offset(cx, cy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MeshPainter oldDelegate) {
    return oldDelegate.palette != palette ||
        oldDelegate.progress != progress ||
        oldDelegate.baseColor != baseColor;
  }
}
