import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import 'netease_image_provider.dart' show NeteaseImageProvider;

/// 网络图片:加载失败/加载中显示占位(利用 Flutter 内置图片内存缓存)。
class NetImage extends StatelessWidget {
  final String url;
  final double width;
  final double height;
  final double radius;

  /// 占位色种子(加载失败/中时的渐变)。
  final int seed;

  const NetImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.radius = 8,
    this.seed = 0,
  });

  @override
  Widget build(BuildContext context) {
    final placeholder = _placeholder(seed);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url.isEmpty
          ? placeholder
          : Image(
              image: NeteaseImageProvider(url),
              width: width,
              height: height,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              frameBuilder: (context, child, frame, wasSync) {
                if (wasSync || frame != null) return child;
                return placeholder;
              },
              errorBuilder: (context, error, stack) => placeholder,
            ),
    );
  }

  Widget _placeholder(int id) {
    return Container(
      width: width,
      height: height,
      color: coverColorFor(id),
      child: Icon(
        Icons.music_note_rounded,
        size: width * 0.3,
        color: Colors.white.withValues(alpha: 0.7),
      ),
    );
  }
}
