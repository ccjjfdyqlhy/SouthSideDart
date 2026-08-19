import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'models/models.dart';
import 'pages/album_page.dart';
import 'pages/artist_page.dart';
import 'pages/comments_page.dart';
import 'pages/favorites_page.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'pages/playing_page.dart';
import 'pages/playlist_page.dart';
import 'pages/search_page.dart';
import 'pages/settings_page.dart';
import 'pages/user_page.dart';
import 'services/backend_client.dart';
import 'services/backend_store.dart';
import 'state/player_state.dart';
import 'theme/app_theme.dart';
import 'widgets/player_bar.dart';
import 'widgets/sidebar.dart';
import 'widgets/splash_screen.dart';
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
  Color? _customColor;

  ThemeSpec get _spec {
    final c = _customColor;
    if (c != null) return AppThemeRegistry.custom(c);
    return AppThemeRegistry.byId(_themeId);
  }

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
        customColor: _customColor,
        autoConnect: widget.autoConnect,
        onToggleTheme: () => setState(() => _dark = !_dark),
        onThemeChanged: (id) => setState(() {
          _themeId = id;
          _customColor = null;
        }),
        onCustomColor: (color) => setState(() => _customColor = color),
      ),
    );
  }
}

/// 主框架:标题栏 + 侧边栏 + 内容区 + 底部播放栏 + 浮动层。
class HomeShell extends StatefulWidget {
  final bool dark;
  final String themeId;
  final Color? customColor;
  final bool autoConnect;
  final VoidCallback onToggleTheme;
  final ValueChanged<String> onThemeChanged;
  final ValueChanged<Color>? onCustomColor;

  const HomeShell({
    super.key,
    required this.dark,
    required this.themeId,
    this.customColor,
    required this.autoConnect,
    required this.onToggleTheme,
    required this.onThemeChanged,
    this.onCustomColor,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

enum BootPhase { connecting, initializing, loginRequired, ready }

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

  BootPhase _bootPhase = BootPhase.connecting;
  String _bootStage = '正在启动内核…';
  double _bootProgress = 0;
  Map<String, dynamic>? _account;

  // 右面板页(用户主页/歌手页/专辑页),优先于普通导航显示。
  int? _panelUserId;
  int? _panelArtistId;
  int? _panelAlbumId;

  @override
  void initState() {
    super.initState();
    _player.addListener(_onPlayerChanged);
    if (widget.autoConnect) {
      _boot();
    } else {
      setState(() => _bootPhase = BootPhase.ready);
    }
  }

  /// 启动流程:连接内核 → 等待初始化 → 检查登录 → 主界面。
  Future<void> _boot() async {
    _backend.onStartupLog = _onStartupLog;
    final ok = await _startBackendProcess() || await _backend.connectTcp();
    if (!mounted) return;
    setState(() {
      _backendConnected = ok;
      _bootPhase = ok ? BootPhase.initializing : BootPhase.ready;
    });
    if (!ok) return; // 无内核:进入主界面(列表为空态)。

    _player.attachBackend(_backend);
    _store = BackendStore(_backend)..addListener(_onStoreChanged);

    // 等待内核初始化完成。
    await _waitBackendReady();
    if (!mounted) return;

    // 检查登录状态。
    final account = await _fetchAccountInfo();
    if (!mounted) return;
    final loggedIn = (account?['logged_in'] as bool?) ?? false;
    if (loggedIn) {
      _enterMain();
    } else {
      setState(() => _bootPhase = BootPhase.loginRequired);
    }
  }

  /// 登录成功或跳过登录后进入主界面并加载数据。
  void _enterMain() {
    setState(() {
      _bootPhase = BootPhase.ready;
      _bootProgress = 1;
    });
    if (_store != null) {
      // 登录成功后强制刷新(绕过加载中保护),无需重启内核。
      unawaited(_store!.loadDaily(force: true));
      unawaited(_store!.loadPlaylists(force: true));
    }
    _player.syncFromBackend();
    unawaited(_fetchAccountInfo());
  }

  void _onLoginSuccess() => _enterMain();

  void _onSkipLogin() => _enterMain();

  /// 登出:清空账号并回到登录引导。
  Future<void> _logout() async {
    if (_backend.isConnected) {
      try {
        await _backend.call('logout');
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _account = null;
      _bootPhase = BootPhase.loginRequired;
    });
  }

  /// 等待内核 get_account_info 可用(初始化完成)。
  Future<void> _waitBackendReady() async {
    for (var i = 0; i < 30; i++) {
      if (!_backend.isConnected) return;
      try {
        await _backend.call('get_account_info');
        return;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  Future<Map<String, dynamic>?> _fetchAccountInfo() async {
    try {
      final r = await _backend.call('get_account_info');
      final info = (r['result'] as Map<String, dynamic>?) ?? {};
      if (mounted) setState(() => _account = info);
      return info;
    } catch (_) {
      return null;
    }
  }

  /// 解析内核启动日志(stderr)为启动阶段进度。
  void _onStartupLog(String line) {
    final idx = line.indexOf('[backend]');
    if (idx < 0) return;
    final stage = line.substring(idx + 9).trim();
    if (stage.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _bootStage = stage;
      if (stage.contains('Loading config')) {
        _bootProgress = 0.15;
      } else if (stage.contains('Loading favorites')) {
        _bootProgress = 0.3;
      } else if (stage.contains('Logging in')) {
        _bootProgress = 0.45;
      } else if (stage.contains('Phase 2')) {
        _bootProgress = 0.6;
      }
    });
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

  /// 连接 Python 内核:优先子进程直连(stdin/stdout),失败降级 TCP。
  Future<void> _connectBackend() async {
    _backend.disconnect();
    final ok = await _startBackendProcess() || await _backend.connectTcp();
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

  /// 由前端启动内核子进程(stdin/stdout 直连,生命周期随前端)。
  Future<bool> _startBackendProcess() async {
    final root = _findRepoRoot();
    if (root == null) return false;
    final script = '$root/src/backend/standalone.py';
    final candidates = <List<String>>[];
    final envPython = Platform.environment['SOUTHSIDE_BACKEND_PYTHON'];
    if (envPython != null && envPython.isNotEmpty) {
      candidates.add([envPython, script, '--no-tcp']);
    }
    candidates.add(['$root/.venv-backend/bin/python', script, '--no-tcp']);
    candidates.add(['python3', script, '--no-tcp']);
    for (final cmd in candidates) {
      if (await _backend.connectProcess(
        command: cmd,
        workingDirectory: root,
      )) {
        return true;
      }
    }
    return false;
  }

  /// 从当前目录向上查找仓库根(含 src/backend/standalone.py)。
  String? _findRepoRoot() {
    var dir = Directory.current;
    for (var i = 0; i < 6; i++) {
      if (File('${dir.path}/src/backend/standalone.py').existsSync()) {
        return dir.path;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
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
      _selectedFolder = folder;
      _panelUserId = null;
      _panelArtistId = null;
      _panelAlbumId = null;
    });
    // 云端歌单歌曲由内核加载。
    _store?.loadFolderSongs(folder);
  }

  void _closePanel() {
    setState(() {
      _panelUserId = null;
      _panelArtistId = null;
      _panelAlbumId = null;
    });
  }

  /// 新建云端歌单:弹出输入框,调用内核创建后刷新列表。
  Future<void> _createFolder() async {
    final store = _store;
    if (store == null || !store.client.isConnected) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建歌单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入歌单名称'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final ok = await store.createPlaylist(name);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '已创建歌单' : '创建歌单失败'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 打开歌手页(右面板,自动收起全屏播放页)。
  void _openArtist(int artistId) {
    if (artistId <= 0) return;
    setState(() {
      _panelArtistId = artistId;
      _panelUserId = null;
      _panelAlbumId = null;
      _showPlayingPage = false;
    });
  }

  /// 打开用户主页(右面板,自动收起全屏播放页)。
  void _openUser() {
    final uid = (_account?['user_id'] ?? '').toString();
    if (uid.isEmpty) return;
    setState(() {
      _panelUserId = int.tryParse(uid) ?? 0;
      _panelArtistId = null;
      _panelAlbumId = null;
      _showPlayingPage = false;
    });
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
    switch (_bootPhase) {
      case BootPhase.connecting:
      case BootPhase.initializing:
        return SplashScreen(stage: _bootStage, progress: _bootProgress);
      case BootPhase.loginRequired:
        return LoginPage(
          client: _backend,
          onLoginSuccess: _onLoginSuccess,
          onSkip: _onSkipLogin,
        );
      case BootPhase.ready:
        return _buildMain();
    }
  }

  Widget _buildMain() {
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
                      current: _nav,
                      settingsSelected: _showSettings,
                      userPanelActive: _panelUserId != null,
                      folders: store?.cloudFolders ?? const [],
                      selectedFolderId: _selectedFolder?.id,
                      account: _account,
                      onNavigate: _navigate,
                      onFolderTap: _openFolder,
                      onSettings: _openSettings,
                      onLogout: _logout,
                      onUserTap: _openUser,
                      onCreateFolder: _createFolder,
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
                onPlaylist: () =>
                    _scaffoldKey.currentState?.openEndDrawer(),
                onArtistTap: _openArtist,
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
    // 右面板页优先:用户主页 / 歌手页 / 专辑页。
    if (_panelArtistId != null) {
      return ArtistPage(
        client: _backend,
        artistId: _panelArtistId!,
        onBack: _closePanel,
        onSongTap: _player.playSong,
        onAlbumTap: (id) => setState(() {
          _panelAlbumId = id;
          _panelArtistId = null;
        }),
      );
    }
    if (_panelAlbumId != null) {
      return AlbumPage(
        client: _backend,
        albumId: _panelAlbumId!,
        onBack: () => setState(() => _panelAlbumId = null),
        onSongTap: _player.playSong,
      );
    }
    if (_panelUserId != null) {
      return UserPage(
        client: _backend,
        userId: _panelUserId!,
        onBack: _closePanel,
        onFolderTap: _openFolder,
      );
    }
    if (_showSettings) {
      return SettingsPage(
        themeId: widget.themeId,
        customColor: widget.customColor,
        onThemeChanged: widget.onThemeChanged,
        onCustomColor: widget.onCustomColor,
        client: _backend,
        backendConnected: _backendConnected,
        backendProcessMode: _backend.isProcessMode,
        backendPlaylistSize: _player.backendPlaylistSize,
        backendWsRunning: _player.backendWsRunning,
        onReconnect: _connectBackend,
      );
    }
    final store = _store;
    // 选中歌单时优先显示歌单详情。
    if (_selectedFolder != null) {
      return FavoritesPage(
        folder: _selectedFolder,
        player: _player,
        store: store,
        onArtistTap: _openArtist,
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
    switch (_nav) {
      case SideNavItem.home:
        final folders = store?.dailyFolders ?? const <Folder>[];
        final songs = store?.dailySongs ?? const <Song>[];
        return HomePage(
          player: _player,
          folders: folders,
          songs: songs,
          userFolders: store?.cloudFolders ?? const <Folder>[],
          account: _account,
          onModeTap: _playMode,
          onArtistTap: _openArtist,
          onFolderTap: _openFolder,
        );
      case SideNavItem.search:
        return SearchPage(
          player: _player,
          keyword: _searchController.text,
          store: store,
          onArtistTap: _openArtist,
          onFolderTap: _openFolder,
        );
    }
  }
}
