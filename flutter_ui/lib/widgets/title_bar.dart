import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 顶部标题栏(高 48):左侧标题,中间搜索框,右侧窗口控制。
class TitleBar extends StatelessWidget {
  final String title;
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;
  final VoidCallback onMinimize;
  final VoidCallback onMaximize;
  final VoidCallback onClose;

  const TitleBar({
    super.key,
    required this.title,
    required this.searchController,
    required this.onSearch,
    required this.onMinimize,
    required this.onMaximize,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 48,
      padding: const EdgeInsets.only(left: 20, right: 8),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 260,
            height: 30,
            child: TextField(
              controller: searchController,
              onSubmitted: onSearch,
              style: TextStyle(fontSize: 13, color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: '搜索音乐、歌手、专辑',
                hintStyle: TextStyle(fontSize: 13, color: colors.textTertiary),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: colors.textSecondary,
                ),
                filled: true,
                fillColor: colors.background,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _WindowButton(
            icon: Icons.remove_rounded,
            tooltip: '最小化',
            onTap: onMinimize,
          ),
          _WindowButton(
            icon: Icons.crop_square_rounded,
            tooltip: '最大化',
            onTap: onMaximize,
          ),
          _WindowButton(
            icon: Icons.close_rounded,
            tooltip: '关闭',
            danger: true,
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool danger;
  final VoidCallback onTap;

  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        hoverColor: danger ? colors.danger : colors.hoverLayer,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            size: 16,
            color: danger
                ? colors.textSecondary
                : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
