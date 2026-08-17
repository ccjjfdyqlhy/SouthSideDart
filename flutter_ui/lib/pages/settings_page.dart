import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 设置页(精简版):分组展示设置项,结构对齐 Qt 版的设置分组。
class SettingsPage extends StatefulWidget {
  final String themeId;
  final ValueChanged<String> onThemeChanged;

  const SettingsPage({
    super.key,
    required this.themeId,
    required this.onThemeChanged,
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
  String _playMethod = '列表循环';
  String _language = '简体中文';

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
        SwitchListTile(
          title: const Text('高级设置'),
          subtitle: const Text('显示完整的音频、FFT、LLM、存储参数'),
          value: _advanced,
          onChanged: (v) => setState(() => _advanced = v),
        ),
        _Group(
          title: '应用',
          children: [
            _DropdownTile(
              label: '语言',
              value: _language,
              options: const ['简体中文', 'English'],
              onChanged: (v) => setState(() => _language = v),
            ),
          ],
        ),
        _Group(
          title: '播放',
          children: [
            _DropdownTile(
              label: '播放顺序',
              value: _playMethod,
              options: const ['列表循环', '单曲循环', '随机播放'],
              onChanged: (v) => setState(() => _playMethod = v),
            ),
            _SliderTile(
              label: '音量',
              value: _volume,
              max: 1,
              onChanged: (v) => setState(() => _volume = v),
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
              onChanged: (v) => setState(() => _targetLufs = v),
            ),
          ],
        ),
        _Group(
          title: '桌面歌词',
          children: [
            _SwitchTile(
              label: '显示桌面歌词',
              value: _desktopLyrics,
              onChanged: (v) => setState(() => _desktopLyrics = v),
            ),
          ],
        ),
        _Group(
          title: '缓存存储',
          children: [
            _SwitchTile(
              label: '自动清理缓存',
              value: _autoCleanup,
              onChanged: (v) => setState(() => _autoCleanup = v),
            ),
          ],
        ),
        if (_advanced) ...[
          _Group(
            title: 'FFT',
            children: [
              _SliderTile(
                label: '频谱平滑',
                value: 0.5,
                onChanged: (_) {},
              ),
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
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _DropdownTile({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
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
          const Spacer(),
          DropdownButton<String>(
            value: value,
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
              if (v != null) onChanged(v);
            },
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
