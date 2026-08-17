import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// 歌单卡片(首页推荐歌单 / 搜索结果):方形封面 + 名称 + 播放数。
class FolderCard extends StatelessWidget {
  final Folder folder;
  final double width;
  final VoidCallback onTap;

  const FolderCard({
    super.key,
    required this.folder,
    required this.width,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                CoverImage(seed: folder.id, size: width, radius: BorderRadius.circular(10)),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    size: 30,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              folder.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: colors.textPrimary,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${folder.songCount} 首',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
