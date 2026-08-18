import 'dart:async';

import 'package:flutter/material.dart';

import '../services/backend_client.dart';
import '../theme/app_theme.dart';

/// 设置页:配置项读写内核(volume/play_method/language 等),主题本地切换。
class SettingsPage extends StatefulWidget {
  final String themeId;
  final ValueChanged<String> onThemeChanged;
  final Color? customColor;
  final ValueChanged<Color>? onCustomColor;
  final BackendClient? client;
  final bool backendConnected;
  final bool backendProcessMode;
  final int backendPlaylistSize;
  final bool backendWsRunning;
  final Future<void> Function() onReconnect;

  const SettingsPage({
    super.key,
    required this.themeId,
    required this.onThemeChanged,
    this.customColor,
    this.onCustomColor,
    this.client,
    this.backendConnected = false,
    this.backendProcessMode = false,
    this.backendPlaylistSize = 0,
    this.backendWsRunning = false,
    required this.onReconnect,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _advanced = false;
  bool _desktopLyrics = false;
  bool _crossfade = true;
  bool _autoCleanup = true;
  double _volume = 0.8;
  double _targetLufs = -14;
  double _crossfadeDuration = 8;
  String _playMethod = 'Repeat list';
  String _language = 'zh_CN';

  static const _playMethodOptions = {
    '列表循环': 'Repeat list',
    '单曲循环': 'Repeat one',
    '随机播放': 'Shuffle',
    '顺序播放': 'Play in order',
  };
  static const _languageOptions = {
    '简体中文': 'zh_CN',
    'English': 'en_US',
  };

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  /// 从内核拉取配置填充 UI。
  Future<void> _loadConfig() async {
    final c = widget.client;
    if (c == null || !c.isConnected) return;
    try {
      final r = await c.call('get_config');
      final data = (r['result'] as Map<String, dynamic>?) ?? {};
      if (!mounted) return;
      setState(() {
        _volume = (data['volume'] as num?)?.toDouble() ?? _volume;
        _playMethod = (data['play_method'] as String?) ?? _playMethod;
        _language = (data['language'] as String?) ?? _language;
        _advanced =
            (data['show_advanced_settings'] as bool?) ?? _advanced;
        _desktopLyrics =
            (data['enable_desktop_lyrics'] as bool?) ?? _desktopLyrics;
        _autoCleanup =
            (data['data_cleanup_enabled'] as bool?) ?? _autoCleanup;
        _targetLufs = (data['target_lufs'] as num?)?.toDouble() ?? _targetLufs;
      });
    } catch (_) {
      // 内核不可用,保持默认值。
    }
  }

  void _setConfig(String key, Object value) {
    final c = widget.client;
    if (c == null || !c.isConnected) return;
    unawaited(
      c.call('set_config', {'key': key, 'value': value})
          .catchError((Object _) => <String, dynamic>{}),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        _PageTitle(title: '设置'),
        const SizedBox(height: 8),
        _ThemePicker(
          current: widget.themeId,
          onChanged: widget.onThemeChanged,
        ),
        _ColorPalette(
          customColor: widget.customColor,
          onSelected: widget.onCustomColor,
        ),
        _Group(
          title: '内核连接',
          children: [
            _StatusTile(
              label: 'Python 内核',
              ok: widget.backendConnected,
              okText: widget.backendProcessMode
                  ? '已连接(子进程模式)'
                  : '已连接 (127.0.0.1:15490)',
              failText: '未连接',
            ),
            _StatusTile(
              label: '内核播放队列',
              ok: true,
              okText: '${widget.backendPlaylistSize} 首',
            ),
            _StatusTile(
              label: 'WebSocket 桥 (15489)',
              ok: widget.backendWsRunning,
              okText: '运行中',
              failText: '未启动',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Material(
                color: context.colors.accent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: () => widget.onReconnect(),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Text(
                      '重新连接内核',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        SwitchListTile(
          title: const Text('高级设置'),
          subtitle: const Text('显示完整的音频、FFT、LLM、存储参数'),
          value: _advanced,
          onChanged: (v) {
            setState(() => _advanced = v);
            _setConfig('show_advanced_settings', v);
          },
        ),
        _Group(
          title: '应用',
          children: [
            _DropdownTile(
              label: '语言',
              options: _languageOptions.keys.toList(),
              displayValue: _language,
              optionValues: _languageOptions.values.toList(),
              onChanged: (v) {
                setState(() => _language = v);
                _setConfig('language', v);
              },
            ),
          ],
        ),
        _Group(
          title: '播放',
          children: [
            _DropdownTile(
              label: '播放顺序',
              options: _playMethodOptions.keys.toList(),
              displayValue: _playMethod,
              optionValues: _playMethodOptions.values.toList(),
              onChanged: (v) {
                setState(() => _playMethod = v);
                _setConfig('play_method', v);
              },
            ),
            _SliderTile(
              label: '音量',
              value: _volume,
              max: 1,
              onChanged: (v) {
                setState(() => _volume = v);
                _setConfig('volume', v);
              },
            ),
          ],
        ),
        _Group(
          title: '交叉淡化',
          children: [
            _SwitchTile(
              label: '启用智能交叉淡化',
              value: _crossfade,
              onChanged: (v) => setState(() => _crossfade = v),
            ),
            _SliderTile(
              label: '过渡时长(秒)',
              value: _crossfadeDuration,
              max: 20,
              onChanged: (v) => setState(() => _crossfadeDuration = v),
            ),
          ],
        ),
        _Group(
          title: '响度',
          children: [
            _SliderTile(
              label: '目标 LUFS',
              value: _targetLufs,
              min: -24,
              max: -8,
              onChanged: (v) {
                setState(() => _targetLufs = v);
                _setConfig('target_lufs', v.round());
              },
            ),
          ],
        ),
        _Group(
          title: '桌面歌词',
          children: [
            _SwitchTile(
              label: '显示桌面歌词',
              value: _desktopLyrics,
              onChanged: (v) {
                setState(() => _desktopLyrics = v);
                _setConfig('enable_desktop_lyrics', v);
              },
            ),
          ],
        ),
        _Group(
          title: '缓存存储',
          children: [
            _SwitchTile(
              label: '自动清理缓存',
              value: _autoCleanup,
              onChanged: (v) {
                setState(() => _autoCleanup = v);
                _setConfig('data_cleanup_enabled', v);
              },
            ),
          ],
        ),
        if (_advanced) ...[
          _Group(
            title: 'FFT',
            children: const [
              _InfoTile(label: '频谱分析', value: '实时 FFT 由内核输出'),
            ],
          ),
          _Group(
            title: 'LLM',
            children: const [
              _InfoTile(label: '提供商', value: 'OpenAI 兼容'),
              _InfoTile(label: '模型', value: '未配置'),
            ],
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _PageTitle extends StatelessWidget {
  final String title;

  const _PageTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: context.colors.textPrimary,
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Group({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ),
          Material(
            color: colors.card,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(label),
      value: value,
      onChanged: onChanged,
      dense: true,
    );
  }
}

class _SliderTile extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _SliderTile({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: colors.textPrimary),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              activeColor: colors.accent,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              value.toStringAsFixed(value >= 100 ? 0 : 1),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _DropdownTile extends StatelessWidget {
  final String label;
  final String displayValue;
  final List<String> options;
  final List<String> optionValues;
  final ValueChanged<String> onChanged;

  const _DropdownTile({
    required this.label,
    required this.displayValue,
    required this.options,
    required this.optionValues,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final idx = optionValues.indexOf(displayValue);
    final current = idx >= 0 ? options[idx] : displayValue;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: colors.textPrimary),
            ),
          ),
          const Spacer(),
          DropdownButton<String>(
            value: current,
            underline: const SizedBox.shrink(),
            style: TextStyle(
              fontSize: 13,
              color: colors.textPrimary,
            ),
            dropdownColor: colors.card,
            items: options
                .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              final valueIdx = options.indexOf(v);
              if (valueIdx >= 0 && valueIdx < optionValues.length) {
                onChanged(optionValues[valueIdx]);
              }
            },
          ),
        ],
      ),
    );
  }
}

/// 状态行:左侧标签 + 右侧状态点与文字。
class _StatusTile extends StatelessWidget {
  final String label;
  final bool ok;
  final String okText;
  final String? failText;

  const _StatusTile({
    required this.label,
    required this.ok,
    required this.okText,
    this.failText,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 14, color: colors.textPrimary),
          ),
          const Spacer(),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ok ? const Color(0xFF34C759) : colors.textTertiary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            ok ? okText : (failText ?? '未知'),
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 自定义配色取色板:选择基色,自动派生一套明暗色系。
class _ColorPalette extends StatelessWidget {
  final Color? customColor;
  final ValueChanged<Color>? onSelected;

  const _ColorPalette({this.customColor, this.onSelected});

  static const _palette = <Color>[
    Color(0xFFE53935), // 红
    Color(0xFFD81B60), // 玫红
    Color(0xFFEC407A), // 粉
    Color(0xFFFF7043), // 橙红
    Color(0xFFFB8C00), // 橙
    Color(0xFFFFB300), // 琥珀
    Color(0xFFFDD835), // 黄
    Color(0xFF43A047), // 绿
    Color(0xFF00B96A), // 翡翠
    Color(0xFF26A69A), // 青
    Color(0xFF00ACC1), // 湖蓝
    Color(0xFF1E88E5), // 蓝
    Color(0xFF2D7FF9), // 蓝紫(默认)
    Color(0xFF5E5CE6), // 紫
    Color(0xFF8E24AA), // 深紫
    Color(0xFF8D6E63), // 棕
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '自定义主色',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              for (final color in _palette)
                InkWell(
                  onTap: () => onSelected?.call(color),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                      border: Border.all(
                        color: customColor == color
                            ? colors.textPrimary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: customColor == color
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 18,
                          )
                        : null,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 主题选择器:渐变圆点 + 名称,点击切换。
class _ThemePicker extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;

  const _ThemePicker({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final specs = AppThemeRegistry.specs;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '主题配色',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              for (final spec in specs)
                InkWell(
                  onTap: () => onChanged(spec.id),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: spec.id == current
                            ? colors.accent
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [spec.gradientStart, spec.gradientEnd],
                            ),
                          ),
                          child: spec.id == current
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 18,
                                )
                              : null,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          spec.name,
                          style: TextStyle(
                            fontSize: 12,
                            color: spec.id == current
                                ? colors.textPrimary
                                : colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;

  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 14, color: colors.textPrimary),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
