import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'models/models.dart';
import 'pages/comments_page.dart';
import 'pages/favorites_page.dart';
import 'pages/home_page.dart';
import 'pages/playing_page.dart';
import 'pages/playlist_page.dart';
import 'pages/search_page.dart';
import 'pages/settings_page.dart';
import 'services/backend_client.dart';
import 'services/backend_store.dart';
import 'state/player_state.dart';
import 'theme/app_theme.dart';
import 'widgets/player_bar.dart';
import 'widgets/sidebar.dart';
import 'widgets/title_bar.dart';

void main() {
  runApp(const SouthsideMusicApp());
}

class SouthsideMusicApp extends StatefulWidget {
  /// 启动时自动连接 Python 内核;widget 测试中关闭。
  final bool autoConnect;

  const SouthsideMusicApp({super.key, this.autoConnect = true});

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
        autoConnect: widget.autoConnect,
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
  final bool autoConnect;
  final VoidCallback onToggleTheme;
  final ValueChanged<String> onThemeChanged;

  const HomeShell({
    super.key,
    required this.dark,
    required this.themeId,
    required this.autoConnect,
    required this.onToggleTheme,
    required this.onThemeChanged,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();
  final PlayerState _player = PlayerState();
  final BackendClient _backend = BackendClient();
  final TextEditingController _searchController = TextEditingController();

  BackendStore? _store;
  SideNavItem _nav = SideNavItem.home;
  Folder? _selectedFolder;
  bool _showSettings = false;
  bool _showPlayingPage = false;
  bool _backendConnected = false;

  @override
  void initState() {
    super.initState();
    _player.addListener(_onPlayerChanged);
    if (widget.autoConnect) {
      _connectBackend();
    }
  }

  /// 播放歌曲变化时,向后端拉取真实歌词。
  void _onPlayerChanged() {
    final song = _player.currentSong;
    if (song != null && song.id > 0 && _store != null) {
      _store!.loadLyrics(song.id);
    }
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  /// 当前歌词:来自内核真实歌词(空则显示"暂无歌词")。
  List<LyricLine> _effectiveLyrics() {
    final store = _store;
    if (store != null && store.currentLyrics.isNotEmpty) {
      return store.currentLyrics;
    }
    return const [];
  }

  /// 连接 Python 内核(standalone.py 的 TCP RPC 服务)。
  Future<void> _connectBackend() async {
    _backend.disconnect();
    final ok = await _backend.connect();
    if (!mounted) return;
    setState(() => _backendConnected = ok);
    if (ok) {
      _player.attachBackend(_backend);
      _store = BackendStore(_backend)..addListener(_onStoreChanged);
      // 后台加载推荐与歌单(数据为空时 UI 显示空态)。
      unawaited(_store!.loadDaily());
      unawaited(_store!.loadPlaylists());
      _player.syncFromBackend();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayerChanged);
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
    // 云端歌单歌曲由内核加载。
    _store?.loadFolderSongs(folder);
  }

  /// 打开当前歌曲的评论页(真实加载/发表)。
  void _openComments() {
    final song = _player.currentSong;
    if (song == null || song.id <= 0) return;
    showDialog<void>(
      context: context,
      builder: (_) => CommentsPage(song: song, client: _backend),
    );
  }

  /// 模式卡点击:向内核启动对应播放模式。
  void _playMode(String icon) {
    final store = _store;
    if (store == null || !store.client.isConnected) return;
    final mode = switch (icon) {
      'heart' => 'heart',
      'explore' => 'fm',
      'radar' => 'radar',
      'similar' => 'similar',
      _ => 'heart',
    };
    unawaited(
      store.client
          .call('play_mode', {'mode': mode})
          .catchError((Object _) => <String, dynamic>{}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
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
                      folders: store?.cloudFolders ?? const [],
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
                      lyrics: _effectiveLyrics(),
                      backendConnected: _backendConnected,
                      onExpand: () =>
                          setState(() => _showPlayingPage = true),
                      onPlaylist: () =>
                          _scaffoldKey.currentState?.openEndDrawer(),
                    )
                  : BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: PlayerBar(
                        player: _player,
                        lyrics: _effectiveLyrics(),
                        backendConnected: _backendConnected,
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
                lyrics: _effectiveLyrics(),
                store: _store,
                onComments: _openComments,
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
        client: _backend,
        backendConnected: _backendConnected,
        backendPlaylistSize: _player.backendPlaylistSize,
        backendWsRunning: _player.backendWsRunning,
        onReconnect: _connectBackend,
      );
    }
    final store = _store;
    switch (_nav) {
      case SideNavItem.home:
        final folders = store?.dailyFolders ?? const <Folder>[];
        final songs = store?.dailySongs ?? const <Song>[];
        return HomePage(
          player: _player,
          folders: folders,
          songs: songs,
          onModeTap: _playMode,
          onFolderTap: _openFolder,
        );
      case SideNavItem.search:
        return SearchPage(
          player: _player,
          keyword: _searchController.text,
          store: store,
          onFolderTap: _openFolder,
        );
      case SideNavItem.favorites:
      case SideNavItem.library:
        return FavoritesPage(
          folder: _selectedFolder,
          player: _player,
          store: store,
          onPlayAll: () {
            final folder = _selectedFolder;
            if (folder == null) return;
            // 真实播放:内核加载歌单并从头播放。
            if (store != null && store.client.isConnected) {
              unawaited(
                store.client
                    .call('play_playlist', {
                      'folder_id': folder.id.toString(),
                      'type': folder.type == FolderType.local
                          ? 'local'
                          : 'cloud',
                    })
                    .catchError((Object _) => <String, dynamic>{}),
              );
            }
          },
        );
    }
  }
}
