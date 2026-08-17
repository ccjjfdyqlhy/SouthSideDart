import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/backend_client.dart';
import '../theme/app_theme.dart';

class _Comment {
  final String id;
  final String nickname;
  final String avatarUrl;
  final String content;
  final int likedCount;
  final String time;
  final String repliedTo;

  const _Comment({
    required this.id,
    required this.nickname,
    required this.avatarUrl,
    required this.content,
    required this.likedCount,
    required this.time,
    required this.repliedTo,
  });

  factory _Comment.fromJson(Map<String, dynamic> j) {
    final user = (j['user'] as Map<String, dynamic>?) ?? {};
    final beReplied = ((j['be_replied'] as List?) ?? const []);
    final first = beReplied.isNotEmpty
        ? beReplied.first as Map<String, dynamic>
        : null;
    return _Comment(
      id: (j['id'] ?? '').toString(),
      nickname: (user['nickname'] ?? '').toString(),
      avatarUrl: (user['avatar_url'] ?? '').toString(),
      content: (j['content'] ?? '').toString(),
      likedCount: (j['liked_count'] as num?)?.toInt() ?? 0,
      time: (j['time'] ?? '').toString(),
      repliedTo: (first?['content'] ?? '').toString(),
    );
  }
}

/// 评论页:加载真实评论、发表评论。
class CommentsPage extends StatefulWidget {
  final Song song;
  final BackendClient client;

  const CommentsPage({
    super.key,
    required this.song,
    required this.client,
  });

  @override
  State<CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends State<CommentsPage> {
  final TextEditingController _input = TextEditingController();
  List<_Comment> _comments = [];
  bool _loading = true;
  bool _posting = false;
  String? _error;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.client.call('get_comments', {
        'song_id': widget.song.id.toString(),
        'page': _page,
        'limit': 20,
      });
      final data = (r['result'] as Map<String, dynamic>?) ?? {};
      final items = ((data['comments'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_Comment.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _comments = [..._comments, ...items];
        _page += 1;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载评论失败:$e';
      });
    }
  }

  Future<void> _post() async {
    final content = _input.text.trim();
    if (content.isEmpty || _posting) return;
    setState(() => _posting = true);
    try {
      await widget.client.call('add_comment', {
        'song_id': widget.song.id.toString(),
        'content': content,
      });
      if (!mounted) return;
      _input.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('评论已发表')),
      );
      setState(() => _posting = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _posting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发表失败:$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: colors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 520,
        height: 560,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '评论 · ${widget.song.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: '关闭',
                  ),
                ],
              ),
            ),
            Divider(color: colors.divider, height: 1),
            Expanded(
              child: _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        style: TextStyle(color: colors.danger),
                      ),
                    )
                  : _comments.isEmpty && _loading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _comments.length + (_loading ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= _comments.length) {
                              return const Padding(
                                padding: EdgeInsets.all(12),
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              );
                            }
                            return _CommentTile(comment: _comments[index]);
                          },
                        ),
            ),
            Divider(color: colors.divider, height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      maxLength: 140,
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: '友善评论,发布你的想法…',
                        counterText: '',
                        isDense: true,
                        filled: true,
                        fillColor: colors.background,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    color: _posting ? colors.textTertiary : colors.accent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      onTap: _posting ? null : _post,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Text(
                          _posting ? '发布中…' : '发布',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final _Comment comment;

  const _CommentTile({required this.comment});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: colors.cardHover,
            child: Text(
              comment.nickname.isNotEmpty
                  ? comment.nickname.characters.first
                  : '?',
              style: TextStyle(fontSize: 14, color: colors.textSecondary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        comment.nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (comment.time.isNotEmpty)
                      Text(
                        _formatTime(comment.time),
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textTertiary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comment.content,
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.textPrimary,
                    height: 1.4,
                  ),
                ),
                if (comment.repliedTo.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colors.background,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '回复:${comment.repliedTo}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textTertiary,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.thumb_up_alt_outlined,
                      size: 14,
                      color: colors.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${comment.likedCount}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.month}-${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}
