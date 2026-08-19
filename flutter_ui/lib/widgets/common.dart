import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import '../theme/app_theme.dart';
import 'netease_image_provider.dart' show NeteaseImageProvider;

/// 封面图:有真实 URL 显示网络图(带占位兜底),否则渐变 + 音符占位。
class CoverImage extends StatelessWidget {
  final int seed;
  final double size;
  final BorderRadius? radius;
  final String? url;

  const CoverImage({
    super.key,
    required this.seed,
    required this.size,
    this.radius,
    this.url,
  });

  @override
  Widget build(BuildContext context) {
    final placeholder = _placeholder(seed, size);
    if (url == null || url!.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: radius ?? BorderRadius.circular(size * 0.08),
      child: SizedBox(
        width: size,
        height: size,
        child: Image(
          image: NeteaseImageProvider(url!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, wasSync) {
            if (wasSync || frame != null) return child;
            return placeholder;
          },
          errorBuilder: (context, error, stack) => placeholder,
        ),
      ),
    );
  }

  Widget _placeholder(int seed, double size) {
    final base = coverColorFor(seed);
    return ClipRRect(
      borderRadius: radius ?? BorderRadius.circular(size * 0.08),
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [base, Color.lerp(base, Colors.black, 0.35)!],
            ),
          ),
          child: Icon(
            Icons.music_note_rounded,
            size: size * 0.42,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }
}

/// 图标按钮:圆角悬停反馈。
class IconBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color? color;
  final String? tooltip;
  final VoidCallback? onTap;

  const IconBtn({
    super.key,
    required this.icon,
    this.size = 20,
    this.color,
    this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        hoverColor: colors.hoverLayer,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: size, color: color ?? colors.textPrimary),
        ),
      ),
    );
  }
}

/// 通用节标题(小标题 + 可选右侧数字滚动器占位)。
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// 通用圆角卡片容器。
class RoundedCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final VoidCallback? onTap;

  const RoundedCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: color ?? colors.card,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: child,
        ),
      ),
    );
  }
}
