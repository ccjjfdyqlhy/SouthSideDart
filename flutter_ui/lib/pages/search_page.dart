import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import '../models/models.dart';
import '../state/player_state.dart';
import '../theme/app_theme.dart';
import '../widgets/folder_card.dart';
import '../widgets/song_card.dart';

/// 搜索页:类型切换(歌曲/歌单)+ 结果列表。
class SearchPage extends StatefulWidget {
  final PlayerState player;
  final String keyword;
  final ValueChanged<Folder> onFolderTap;

  const SearchPage({
    super.key,
    required this.player,
    required this.keyword,
    required this.onFolderTap,
  });

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String _type = SearchType.songs;

  @override
  void didUpdateWidget(covariant SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keyword != widget.keyword) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isSongs = _type == SearchType.songs;
    final songs = isSongs ? mockSearchSongs(widget.keyword) : <Song>[];
    final folders = !isSongs ? mockSearchFolders(widget.keyword) : <Folder>[];

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
                onTap: () => setState(() => _type = SearchType.songs),
              ),
              const SizedBox(width: 8),
              _TypeChip(
                label: '歌单',
                selected: !isSongs,
                onTap: () => setState(() => _type = SearchType.playlists),
              ),
            ],
          ),
        ),
        Expanded(
          child: widget.keyword.isEmpty
              ? Center(
                  child: Text(
                    '输入关键词开始搜索',
                    style: TextStyle(
                      fontSize: 14,
                      color: colors.textTertiary,
                    ),
                  ),
                )
              : isSongs
                  ? _SongResultList(songs: songs, player: widget.player)
                  : _FolderResultGrid(folders: folders, onFolderTap: widget.onFolderTap),
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

  const _SongResultList({required this.songs, required this.player});

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
          onInsert: () {},
          onFavorite: () {},
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
