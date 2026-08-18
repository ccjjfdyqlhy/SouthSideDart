import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 启动画面:显示内核初始化阶段与进度。
class SplashScreen extends StatelessWidget {
  /// 当前阶段文字(来自内核启动日志或本地流程)。
  final String stage;

  /// 0~1 的进度指示。
  final double progress;

  const SplashScreen({
    super.key,
    required this.stage,
    this.progress = 0,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: const [
                    Color(0xFF2D7FF9),
                    Color(0xFF5E5CE6),
                  ],
                ),
              ),
              child: const Icon(
                Icons.music_note_rounded,
                size: 48,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Southside Music',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 260,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: colors.divider,
                  color: colors.accent,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              stage,
              style: TextStyle(
                fontSize: 13,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
