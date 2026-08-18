import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// 侧边栏主入口。
enum SideNavItem {
  home('首页', Icons.home_rounded),
  search('搜索', Icons.search_rounded);

  final String label;
  final IconData icon;

  const SideNavItem(this.label, this.icon);
}

class Sidebar extends StatelessWidget {
  final SideNavItem current;
  final bool settingsSelected;

  /// 用户主页面板激活时点亮账号区。
  final bool userPanelActive;
  final List<Folder> folders;
  final int? selectedFolderId;
  final Map<String, dynamic>? account;
  final ValueChanged<SideNavItem> onNavigate;
  final ValueChanged<Folder> onFolderTap;
  final VoidCallback onSettings;
  final VoidCallback? onLogout;
  final VoidCallback? onUserTap;

  const Sidebar({
    super.key,
    required this.current,
    this.settingsSelected = false,
    this.userPanelActive = false,
    required this.folders,
    required this.selectedFolderId,
    this.account,
    required this.onNavigate,
    required this.onFolderTap,
    required this.onSettings,
    this.onLogout,
    this.onUserTap,
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
              selected: !settingsSelected && current == item,
              onTap: () => onNavigate(item),
            ),
          const SizedBox(height: 8),
          _FolderSection(
            folders: folders,
            selectedFolderId: selectedFolderId,
            onFolderTap: onFolderTap,
          ),
          const Spacer(),
          if (account != null) ...[
            _AccountTile(
              account: account!,
              active: userPanelActive,
              onLogout: onLogout,
              onTap: onUserTap,
            ),
            const SizedBox(height: 4),
          ],
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
            if (cloud.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
                child: Text(
                  '暂无歌单',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textTertiary,
                  ),
                ),
              )
            else
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

/// 底部账号信息(头像 + 昵称 + 登出),点击头像/昵称打开用户主页。
class _AccountTile extends StatelessWidget {
  final Map<String, dynamic> account;
  final bool active;
  final VoidCallback? onLogout;
  final VoidCallback? onTap;

  const _AccountTile({
    required this.account,
    this.active = false,
    this.onLogout,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final loggedIn = account['logged_in'] == true;
    final nickname = (account['nickname'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Material(
        color: active ? colors.hoverLayer : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: colors.accent,
                child: Text(
                  nickname.isNotEmpty ? nickname.characters.first : '?',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loggedIn && nickname.isNotEmpty ? nickname : '未登录',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      loggedIn ? '已登录' : '点击右上角登录',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (onLogout != null)
                IconBtn(
                  icon: Icons.logout_rounded,
                  size: 16,
                  tooltip: '退出登录',
                  color: colors.textSecondary,
                  onTap: onLogout,
                ),
            ],
          ),
        ),
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
