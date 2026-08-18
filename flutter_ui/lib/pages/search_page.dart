import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/backend_store.dart';
import '../state/player_state.dart';
import '../theme/app_theme.dart';
import '../widgets/folder_card.dart';
import '../widgets/song_card.dart';

/// 搜索页:类型切换(歌曲/歌单)+ 结果列表。
/// 连接内核时走真实搜索,否则回退 mock 数据。
class SearchPage extends StatefulWidget {
  final PlayerState player;
  final String keyword;
  final BackendStore? store;
  final ValueChanged<Folder> onFolderTap;
  final ValueChanged<int>? onArtistTap;

  const SearchPage({
    super.key,
    required this.player,
    required this.keyword,
    this.store,
    this.onArtistTap,
    required this.onFolderTap,
  });

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String _type = SearchType.songs;
  List<Song> _songs = [];
  List<Folder> _folders = [];
  bool _loading = false;
  bool _backendUnavailable = false;
  Timer? _debounce;

  @override
  void didUpdateWidget(covariant SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keyword != widget.keyword) {
      _scheduleSearch();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _performSearch);
  }

  Future<void> _performSearch() async {
    final keyword = widget.keyword.trim();
    if (keyword.isEmpty) {
      setState(() {
        _songs = [];
        _folders = [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);

    final store = widget.store;
    final connected = store != null && store.client.isConnected;
    if (connected) {
      List<Song>? songs;
      List<Folder>? folders;
      if (_type == SearchType.songs) {
        songs = await store.searchSongs(keyword);
      } else {
        folders = await store.searchFolders(keyword);
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _backendUnavailable = false;
        _songs = songs ?? const [];
        _folders = folders ?? const [];
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _backendUnavailable = true;
      _songs = const [];
      _folders = const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isSongs = _type == SearchType.songs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Row(
            children: [
              _TypeChip(
                label: '歌曲',
                selected: isSongs,
                onTap: () {
                  setState(() => _type = SearchType.songs);
                  _scheduleSearch();
                },
              ),
              const SizedBox(width: 8),
              _TypeChip(
                label: '歌单',
                selected: !isSongs,
                onTap: () {
                  setState(() => _type = SearchType.playlists);
                  _scheduleSearch();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: widget.keyword.trim().isEmpty
              ? Center(
                  child: Text(
                    '输入关键词开始搜索',
                    style: TextStyle(
                      fontSize: 14,
                      color: colors.textTertiary,
                    ),
                  ),
                )
              : _backendUnavailable
                  ? Center(
                      child: Text(
                        '未连接内核,无法搜索',
                        style: TextStyle(
                          fontSize: 14,
                          color: colors.textTertiary,
                        ),
                      ),
                    )
                  : _loading
                      ? const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : isSongs
                          ? _SongResultList(
                              songs: _songs,
                              player: widget.player,
                              onArtistTap: widget.onArtistTap,
                            )
                          : _FolderResultGrid(
                              folders: _folders,
                              onFolderTap: widget.onFolderTap,
                            ),
        ),
      ],
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: selected ? colors.accent : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: selected ? Colors.white : colors.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _SongResultList extends StatelessWidget {
  final List<Song> songs;
  final PlayerState player;
  final ValueChanged<int>? onArtistTap;

  const _SongResultList({
    required this.songs,
    required this.player,
    this.onArtistTap,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const _EmptyResult();
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        return SongCard(
          song: song,
          onPlay: () => player.playSong(song),
          onInsert: () => player.queueSong(song),
          onFavorite: () => player.likeSong(song),
          onArtistTap: (artist) => onArtistTap?.call(artist.id),
        );
      },
      separatorBuilder: (_, _) => const SizedBox(height: 2),
    );
  }
}

class _FolderResultGrid extends StatelessWidget {
  final List<Folder> folders;
  final ValueChanged<Folder> onFolderTap;

  const _FolderResultGrid({
    required this.folders,
    required this.onFolderTap,
  });

  @override
  Widget build(BuildContext context) {
    if (folders.isEmpty) return const _EmptyResult();
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 20,
        crossAxisSpacing: 16,
        childAspectRatio: 0.78,
      ),
      itemCount: folders.length,
      itemBuilder: (context, index) {
        final f = folders[index];
        return FolderCard(
          folder: f,
          width: 200,
          onTap: () => onFolderTap(f),
        );
      },
    );
  }
}

class _EmptyResult extends StatelessWidget {
  const _EmptyResult();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '没有找到相关结果',
        style: TextStyle(
          fontSize: 14,
          color: context.colors.textTertiary,
        ),
      ),
    );
  }
}
