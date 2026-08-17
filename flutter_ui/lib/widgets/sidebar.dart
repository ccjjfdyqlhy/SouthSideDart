import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

/// 侧边栏主入口。
enum SideNavItem {
  home('首页', Icons.home_rounded),
  library('曲库', Icons.library_music_rounded),
  favorites('收藏', Icons.favorite_rounded),
  search('搜索', Icons.search_rounded);

  final String label;
  final IconData icon;

  const SideNavItem(this.label, this.icon);
}

class Sidebar extends StatelessWidget {
  final SideNavItem current;
  final bool settingsSelected;
  final List<Folder> folders;
  final int? selectedFolderId;
  final ValueChanged<SideNavItem> onNavigate;
  final ValueChanged<Folder> onFolderTap;
  final VoidCallback onSettings;

  const Sidebar({
    super.key,
    required this.current,
    this.settingsSelected = false,
    required this.folders,
    required this.selectedFolderId,
    required this.onNavigate,
    required this.onFolderTap,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: colors.sidebar,
        border: Border(right: BorderSide(color: colors.divider)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          for (final item in SideNavItem.values)
            _NavTile(
              icon: item.icon,
              label: item.label,
              selected: current == item,
              onTap: () => onNavigate(item),
            ),
          const SizedBox(height: 8),
          _FolderSection(
            folders: folders,
            selectedFolderId: selectedFolderId,
            onFolderTap: onFolderTap,
          ),
          const Spacer(),
          _NavTile(
            icon: Icons.settings_rounded,
            label: '设置',
            selected: settingsSelected,
            onTap: onSettings,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bg = selected ? colors.accent : Colors.transparent;
    final fg = selected ? Colors.white : colors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: fg,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderSection extends StatelessWidget {
  final List<Folder> folders;
  final int? selectedFolderId;
  final ValueChanged<Folder> onFolderTap;

  const _FolderSection({
    required this.folders,
    required this.selectedFolderId,
    required this.onFolderTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final local = folders.where((f) => f.type == FolderType.local).toList();
    final cloud = folders.where((f) => f.type == FolderType.cloud).toList();

    return Expanded(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (local.isNotEmpty) ...[
              _SectionLabel('本地', colors),
              for (final f in local) _FolderTile(
                folder: f,
                selected: selectedFolderId == f.id,
                onTap: () => onFolderTap(f),
              ),
            ],
            _SectionLabel('云端', colors),
            for (final f in cloud) _FolderTile(
              folder: f,
              selected: selectedFolderId == f.id,
              onTap: () => onFolderTap(f),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final AppColors colors;

  const _SectionLabel(this.text, this.colors);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: colors.textTertiary,
        ),
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  final Folder folder;
  final bool selected;
  final VoidCallback onTap;

  const _FolderTile({
    required this.folder,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bg = selected ? colors.hoverLayer : Colors.transparent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              children: [
                Icon(
                  folder.type == FolderType.local
                      ? Icons.folder_rounded
                      : Icons.queue_music_rounded,
                  size: 16,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
