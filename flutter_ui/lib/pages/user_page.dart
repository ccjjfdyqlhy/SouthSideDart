import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/backend_client.dart';
import '../services/backend_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/folder_card.dart';
import '../widgets/network_image.dart';

/// 用户主页(右面板):头像/昵称/签名/用户歌单。
class UserPage extends StatefulWidget {
  final BackendClient client;
  final int userId;
  final VoidCallback onBack;
  final ValueChanged<Folder>? onFolderTap;

  const UserPage({
    super.key,
    required this.client,
    required this.userId,
    required this.onBack,
    this.onFolderTap,
  });

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  Map<String, dynamic>? _user;
  List<Folder> _playlists = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.client.call('get_user', {
        'user_id': widget.userId.toString(),
      });
      final data = (r['result'] as Map<String, dynamic>?) ?? {};
      final playlists = ((data['playlists'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(folderFromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _user = data;
        _playlists = playlists;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载用户信息失败:$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: colors.card,
              border: Border(bottom: BorderSide(color: colors.divider)),
            ),
            child: Row(
              children: [
                IconBtn(
                  icon: Icons.arrow_back_rounded,
                  size: 20,
                  tooltip: '返回',
                  onTap: widget.onBack,
                ),
                const SizedBox(width: 4),
                Text(
                  '用户主页',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Divider(color: colors.divider, height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          style: TextStyle(color: colors.danger),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          Row(
                            children: [
                              NetImage(
                                url: (_user?['avatar_url'] ?? '').toString(),
                                width: 80,
                                height: 80,
                                radius: 40,
                                seed: widget.userId,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (_user?['nickname'] ?? '').toString(),
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        color: colors.textPrimary,
                                      ),
                                    ),
                                    if ((_user?['signature'] ?? '')
                                        .toString()
                                        .isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          (_user?['signature'] ?? '')
                                              .toString(),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colors.textTertiary,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text(
                            '歌单 (${_playlists.length})',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_playlists.isEmpty)
                            Text(
                              '该用户暂无公开歌单',
                              style: TextStyle(
                                fontSize: 13,
                                color: colors.textTertiary,
                              ),
                            )
                          else
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 150,
                                mainAxisSpacing: 16,
                                crossAxisSpacing: 12,
                                childAspectRatio: 0.58,
                              ),
                              itemCount: _playlists.length,
                              itemBuilder: (context, index) {
                                final f = _playlists[index];
                                return FolderCard(
                                  folder: f,
                                  width: 150,
                                  onTap: () => widget.onFolderTap?.call(f),
                                );
                              },
                            ),
                          const SizedBox(height: 16),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}
