import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'data/mock_data.dart';
import 'models/models.dart';
import 'pages/favorites_page.dart';
import 'pages/home_page.dart';
import 'pages/playing_page.dart';
import 'pages/playlist_page.dart';
import 'pages/search_page.dart';
import 'pages/settings_page.dart';
import 'state/player_state.dart';
import 'theme/app_theme.dart';
import 'widgets/player_bar.dart';
import 'widgets/sidebar.dart';
import 'widgets/title_bar.dart';

void main() {
  runApp(const SouthsideMusicApp());
}

class SouthsideMusicApp extends StatefulWidget {
  const SouthsideMusicApp({super.key});

  @override
  State<SouthsideMusicApp> createState() => _SouthsideMusicAppState();
}

class _SouthsideMusicAppState extends State<SouthsideMusicApp> {
  bool _dark = true;
  String _themeId = AppThemeRegistry.specs.first.id;

  ThemeSpec get _spec => AppThemeRegistry.byId(_themeId);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Southside Music',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(_spec),
      darkTheme: AppTheme.dark(_spec),
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      home: HomeShell(
        dark: _dark,
        themeId: _themeId,
        onToggleTheme: () => setState(() => _dark = !_dark),
        onThemeChanged: (id) => setState(() => _themeId = id),
      ),
    );
  }
}

/// 主框架:标题栏 + 侧边栏 + 内容区 + 底部播放栏 + 浮动层。
class HomeShell extends StatefulWidget {
  final bool dark;
  final String themeId;
  final VoidCallback onToggleTheme;
  final ValueChanged<String> onThemeChanged;

  const HomeShell({
    super.key,
    required this.dark,
    required this.themeId,
    required this.onToggleTheme,
    required this.onThemeChanged,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();
  final PlayerState _player = PlayerState();
  final TextEditingController _searchController = TextEditingController();

  SideNavItem _nav = SideNavItem.home;
  Folder? _selectedFolder;
  bool _showSettings = false;
  bool _showPlayingPage = false;

  @override
  void initState() {
    super.initState();
    // 预置一个演示队列。
    _player.setPlaylist(mockRecommendedSongs(), startIndex: 0);
  }

  @override
  void dispose() {
    _player.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _navigate(SideNavItem item) {
    setState(() {
      _nav = item;
      _selectedFolder = null;
      _showSettings = false;
    });
  }

  void _openSettings() {
    setState(() => _showSettings = true);
  }

  void _openFolder(Folder folder) {
    setState(() {
      _nav = SideNavItem.favorites;
      _selectedFolder = folder;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      body: Stack(
        children: [
          Column(
            children: [
              TitleBar(
                title: 'Southside Music',
                searchController: _searchController,
                onSearch: (_) => _navigate(SideNavItem.search),
                onMinimize: () {},
                onMaximize: () {},
                onClose: () => exit(0),
              ),
              Expanded(
                child: Row(
                  children: [
                    Sidebar(
                      current: _showSettings ? SideNavItem.home : _nav,
                      settingsSelected: _showSettings,
                      folders: mockFolders(),
                      selectedFolderId: _selectedFolder?.id,
                      onNavigate: _navigate,
                      onFolderTap: _openFolder,
                      onSettings: _openSettings,
                    ),
                    Expanded(child: _buildContent()),
                  ],
                ),
              ),
              // 预留底部浮动播放栏空间
              const SizedBox(height: 52),
            ],
          ),
          // 底部浮动播放栏(玻璃拟态;播放页全屏时跳过模糊以省 GPU)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRect(
              child: _showPlayingPage
                  ? PlayerBar(
                      player: _player,
                      lyrics: mockLyrics(),
                      onExpand: () =>
                          setState(() => _showPlayingPage = true),
                      onPlaylist: () =>
                          _scaffoldKey.currentState?.openEndDrawer(),
                    )
                  : BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: PlayerBar(
                        player: _player,
                        lyrics: mockLyrics(),
                        onExpand: () =>
                            setState(() => _showPlayingPage = true),
                        onPlaylist: () =>
                            _scaffoldKey.currentState?.openEndDrawer(),
                      ),
                    ),
            ),
          ),
          // 播放详情页:全屏覆盖整个窗口(含侧边栏与播放栏)
          IgnorePointer(
            ignoring: !_showPlayingPage,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              opacity: _showPlayingPage ? 1 : 0,
              child: PlayingPage(
                player: _player,
                onCollapse: () => setState(() => _showPlayingPage = false),
              ),
            ),
          ),
        ],
      ),
      // 播放列表抽屉
      drawerScrimColor: Colors.black54,
      endDrawer: Drawer(
        width: MediaQuery.of(context).size.width * 0.45,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(left: Radius.circular(12)),
        ),
        backgroundColor: context.colors.card,
        child: PlaylistPage(
          player: _player,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_showSettings) {
      return SettingsPage(
        themeId: widget.themeId,
        onThemeChanged: widget.onThemeChanged,
      );
    }
    switch (_nav) {
      case SideNavItem.home:
        return HomePage(player: _player, onFolderTap: _openFolder);
      case SideNavItem.search:
        return SearchPage(
          player: _player,
          keyword: _searchController.text,
          onFolderTap: _openFolder,
        );
      case SideNavItem.favorites:
        return FavoritesPage(
          folder: _selectedFolder,
          player: _player,
          onPlayAll: () {
            if (_selectedFolder == null) return;
            _player
              ..setPlaylist(_selectedFolder!.songs.isNotEmpty
                  ? _selectedFolder!.songs
                  : mockRecommendedSongs().take(6).toList())
              ..isPlaying = true;
          },
        );
      case SideNavItem.library:
        return FavoritesPage(
          folder: _selectedFolder,
          player: _player,
          onPlayAll: () {},
        );
    }
  }
}
