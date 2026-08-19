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
  List<Map<String, dynamic>> _subs = [];
  bool _loading = true;
  bool _signingIn = false;
  bool _subsLoaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 每日签到(pyncm user.setSignin)。
  Future<void> _dailySignin() async {
    if (_signingIn || !widget.client.isConnected) return;
    setState(() => _signingIn = true);
    try {
      final r = await widget.client.call('daily_signin', {'dtype': 'mobile'});
      final code = ((r['result'] as Map<String, dynamic>?) ?? {})['code'];
      if (!mounted) return;
      final ok = code == 200;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? '签到成功(+4 经验)' : '签到失败(可能已签到)'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('签到失败:$e'), duration: const Duration(seconds: 2)),
      );
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  /// 加载我的订阅(艺人/专辑,pyncm user.getUserArtistSubs / getUserAlbumSubs)。
  Future<void> _loadSubs() async {
    if (_subsLoaded || !widget.client.isConnected) return;
    try {
      final r = await widget.client.call('user_subs', {'type': 'artist'});
      final data = (r['result'] as Map<String, dynamic>?) ?? {};
      final items = ((data['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      if (!mounted) return;
      setState(() {
        _subs = items;
        _subsLoaded = true;
      });
    } catch (_) {
      // 匿名或未登录时静默失败。
    }
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
                          const SizedBox(height: 14),
                          // 用户统计信息:等级/关注/粉丝/歌单/动态/会员等。
                          _UserStatsBar(
                            level: ((_user?['level'] as num?) ?? 0).toInt(),
                            follows:
                                ((_user?['follows'] as num?) ?? 0).toInt(),
                            followeds:
                                ((_user?['followeds'] as num?) ?? 0).toInt(),
                            playlistCount: ((_user?['playlist_count'] as num?) ??
                                    0)
                                .toInt(),
                            eventCount:
                                ((_user?['event_count'] as num?) ?? 0).toInt(),
                            vipType: ((_user?['vip_type'] as num?) ?? 0).toInt(),
                            gender: ((_user?['gender'] as num?) ?? 0).toInt(),
                            province: ((_user?['province'] as num?) ?? 0).toInt(),
                            city: ((_user?['city'] as num?) ?? 0).toInt(),
                            createTime:
                                ((_user?['create_time'] as num?) ?? 0).toInt(),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _signingIn ? null : _dailySignin,
                            icon: Icon(
                              Icons.task_alt_rounded,
                              size: 16,
                              color: _signingIn
                                  ? colors.textTertiary
                                  : colors.accent,
                            ),
                            label: Text(_signingIn ? '签到中…' : '每日签到'),
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
                          const SizedBox(height: 24),
                          Text(
                            '我的订阅 (${_subs.length})',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (!_subsLoaded)
                            TextButton(
                              onPressed: _loadSubs,
                              child: Text(
                                '加载我订阅的艺人',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colors.accent,
                                ),
                              ),
                            )
                          else if (_subs.isEmpty)
                            Text(
                              '暂无订阅',
                              style: TextStyle(
                                fontSize: 13,
                                color: colors.textTertiary,
                              ),
                            )
                          else
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                for (final sub in _subs)
                                  _SubChip(
                                    name: (sub['name'] ?? '').toString(),
                                    coverUrl: (sub['cover_url'] ?? '').toString(),
                                    seed: widget.userId,
                                  ),
                              ],
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

/// 用户统计信息条:等级 / 关注 / 粉丝 / 歌单 / 动态等。
class _UserStatsBar extends StatelessWidget {
  final int level;
  final int follows;
  final int followeds;
  final int playlistCount;
  final int eventCount;
  final int vipType;
  final int gender;
  final int province;
  final int city;
  final int createTime;

  const _UserStatsBar({
    required this.level,
    required this.follows,
    required this.followeds,
    required this.playlistCount,
    required this.eventCount,
    required this.vipType,
    required this.gender,
    required this.province,
    required this.city,
    required this.createTime,
  });

  String _formatCount(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    return '$n';
  }

  String _formatDate(int ms) {
    if (ms <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _genderLabel(int g) {
    switch (g) {
      case 1:
        return '男';
      case 2:
        return '女';
      default:
        return '保密';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final chips = <Widget>[];
    if (level > 0) chips.add(_InfoChip(icon: Icons.local_fire_department_rounded, text: 'Lv.$level', colors: colors));
    chips.add(_InfoChip(icon: Icons.favorite_border_rounded, text: '关注 ${_formatCount(follows)}', colors: colors));
    chips.add(_InfoChip(icon: Icons.people_alt_outlined, text: '粉丝 ${_formatCount(followeds)}', colors: colors));
    if (playlistCount > 0) chips.add(_InfoChip(icon: Icons.queue_music_rounded, text: '歌单 $playlistCount', colors: colors));
    if (eventCount > 0) chips.add(_InfoChip(icon: Icons.dynamic_feed_rounded, text: '动态 $eventCount', colors: colors));
    if (vipType > 0) chips.add(_InfoChip(icon: Icons.workspace_premium_rounded, text: '会员', colors: colors));
    chips.add(_InfoChip(icon: Icons.wc_rounded, text: _genderLabel(gender), colors: colors));
    if (province > 0) chips.add(_InfoChip(icon: Icons.location_on_outlined, text: '地区 $province', colors: colors));
    final createDate = _formatDate(createTime);
    if (createDate.isNotEmpty) chips.add(_InfoChip(icon: Icons.cake_outlined, text: '加入于 $createDate', colors: colors));

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips,
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final AppColors colors;

  const _InfoChip({
    required this.icon,
    required this.text,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.textSecondary),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 订阅条目:圆形封面 + 名称。
class _SubChip extends StatelessWidget {
  final String name;
  final String coverUrl;
  final int seed;

  const _SubChip({
    required this.name,
    required this.coverUrl,
    required this.seed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 96,
      child: Column(
        children: [
          NetImage(url: coverUrl, width: 72, height: 72, radius: 36, seed: seed),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
