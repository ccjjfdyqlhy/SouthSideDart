import 'package:flutter/material.dart';

/// 对齐 PySide6/qfluentwidgets 版配色的主题扩展。
///
/// 深色:窗口背景 #111111、卡片 #1d1d1d、边框 #303030、次要文字 #A8A8A8
/// 浅色:窗口背景 #F3F3F3、卡片 #FFFFFF、边框 #DDDDDD、次要文字 #666666
///
/// 多主题基于 Apple Music / Cider 的设计语言扩展:
/// - `sidebar` 侧边栏背景(比主背景更深一档)
/// - `glass` / `glassBorder` 玻璃拟态卡片
/// - 主色为双色渐变(如蓝 #2D7FF9 → 紫 #5E5CE6)
class AppColors extends ThemeExtension<AppColors> {
  final Color background;
  final Color card;
  final Color cardHover;
  final Color sidebar;
  final Color sidebarHover;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color accent;
  final Color accentHover;
  final Color danger;
  final Color hoverLayer;
  final Color glass;
  final Color glassBorder;
  final Color lyricInactive;

  const AppColors({
    required this.background,
    required this.card,
    required this.cardHover,
    required this.sidebar,
    required this.sidebarHover,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentHover,
    required this.danger,
    required this.hoverLayer,
    required this.glass,
    required this.glassBorder,
    required this.lyricInactive,
  });

  @override
  AppColors copyWith({
    Color? background,
    Color? card,
    Color? cardHover,
    Color? sidebar,
    Color? sidebarHover,
    Color? divider,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? accentHover,
    Color? danger,
    Color? hoverLayer,
    Color? glass,
    Color? glassBorder,
    Color? lyricInactive,
  }) {
    return AppColors(
      background: background ?? this.background,
      card: card ?? this.card,
      cardHover: cardHover ?? this.cardHover,
      sidebar: sidebar ?? this.sidebar,
      sidebarHover: sidebarHover ?? this.sidebarHover,
      divider: divider ?? this.divider,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accent: accent ?? this.accent,
      accentHover: accentHover ?? this.accentHover,
      danger: danger ?? this.danger,
      hoverLayer: hoverLayer ?? this.hoverLayer,
      glass: glass ?? this.glass,
      glassBorder: glassBorder ?? this.glassBorder,
      lyricInactive: lyricInactive ?? this.lyricInactive,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardHover: Color.lerp(cardHover, other.cardHover, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      sidebarHover: Color.lerp(sidebarHover, other.sidebarHover, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentHover: Color.lerp(accentHover, other.accentHover, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      hoverLayer: Color.lerp(hoverLayer, other.hoverLayer, t)!,
      glass: Color.lerp(glass, other.glass, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      lyricInactive: Color.lerp(lyricInactive, other.lyricInactive, t)!,
    );
  }
}

/// 主题规格:名称 + 明暗两套配色 + 主色渐变(Apple Music 双色风格)。
class ThemeSpec {
  final String id;
  final String name;
  final AppColors light;
  final AppColors dark;
  final Color gradientStart;
  final Color gradientEnd;

  const ThemeSpec({
    required this.id,
    required this.name,
    required this.light,
    required this.dark,
    required this.gradientStart,
    required this.gradientEnd,
  });
}

/// 主题注册表:多主题列表,默认(第一个)为蓝紫色系。
class AppThemeRegistry {
  static const specs = <ThemeSpec>[
    // ── 蓝紫色系(默认) ──
    ThemeSpec(
      id: 'blue-purple',
      name: '蓝紫极光',
      gradientStart: Color(0xFF2D7FF9),
      gradientEnd: Color(0xFF5E5CE6),
      light: AppColors(
        background: Color(0xFFF4F4FA),
        card: Color(0xFFFFFFFF),
        cardHover: Color(0xFFF0F0F8),
        sidebar: Color(0xFFE9E9F3),
        sidebarHover: Color(0xFFDCDCF0),
        divider: Color(0xFFE0E0EC),
        textPrimary: Color(0xFF1A1A2E),
        textSecondary: Color(0xFF55556B),
        textTertiary: Color(0xFF8E8EA3),
        accent: Color(0xFF2D7FF9),
        accentHover: Color(0xFF4A94FA),
        danger: Color(0xFFC42B1C),
        hoverLayer: Color(0x0D000000),
        glass: Color(0xCCFFFFFF),
        glassBorder: Color(0x2EFFFFFF),
        lyricInactive: Color(0x99333366),
      ),
      dark: AppColors(
        background: Color(0xFF12111C),
        card: Color(0xFF1D1C2B),
        cardHover: Color(0xFF262537),
        sidebar: Color(0xFF0B0A12),
        sidebarHover: Color(0xFF171625),
        divider: Color(0xFF2B2A3D),
        textPrimary: Color(0xFFF5F5FA),
        textSecondary: Color(0xFFA9A8C0),
        textTertiary: Color(0xFF6F6E86),
        accent: Color(0xFF7AA5FF),
        accentHover: Color(0xFF96B6FF),
        danger: Color(0xFFE5484D),
        hoverLayer: Color(0x14FFFFFF),
        glass: Color(0xB31D1C2B),
        glassBorder: Color(0x2EFFFFFF),
        lyricInactive: Color(0x99B5B5D6),
      ),
    ),
    // ── 经典红粉(Cider) ──
    ThemeSpec(
      id: 'cider',
      name: 'Cider 红粉',
      gradientStart: Color(0xFFFC3C44),
      gradientEnd: Color(0xFFFF2654),
      light: AppColors(
        background: Color(0xFFF5F5F7),
        card: Color(0xFFFFFFFF),
        cardHover: Color(0xFFF0F0F2),
        sidebar: Color(0xFFEBEBEE),
        sidebarHover: Color(0xFFDEDEE2),
        divider: Color(0xFFE1E1E6),
        textPrimary: Color(0xFF1D1D1F),
        textSecondary: Color(0xFF555559),
        textTertiary: Color(0xFF8E8E93),
        accent: Color(0xFFFC3C44),
        accentHover: Color(0xFFFF5A61),
        danger: Color(0xFFC42B1C),
        hoverLayer: Color(0x0D000000),
        glass: Color(0xCCFFFFFF),
        glassBorder: Color(0x2EFFFFFF),
        lyricInactive: Color(0x99333333),
      ),
      dark: AppColors(
        background: Color(0xFF171717),
        card: Color(0xFF242424),
        cardHover: Color(0xFF2D2D2D),
        sidebar: Color(0xFF0D0D0D),
        sidebarHover: Color(0xFF1A1A1A),
        divider: Color(0xFF333333),
        textPrimary: Color(0xFFF5F5F7),
        textSecondary: Color(0xFFA6A6AC),
        textTertiary: Color(0xFF6E6E74),
        accent: Color(0xFFFF5A61),
        accentHover: Color(0xFFFF7A80),
        danger: Color(0xFFE5484D),
        hoverLayer: Color(0x14FFFFFF),
        glass: Color(0xB3242424),
        glassBorder: Color(0x2EFFFFFF),
        lyricInactive: Color(0x99D0D0D6),
      ),
    ),
    // ── 翡翠绿 ──
    ThemeSpec(
      id: 'emerald',
      name: '翡翠森林',
      gradientStart: Color(0xFF00B96A),
      gradientEnd: Color(0xFF00A67E),
      light: AppColors(
        background: Color(0xFFF2F8F5),
        card: Color(0xFFFFFFFF),
        cardHover: Color(0xFFEFF5F1),
        sidebar: Color(0xFFE7F1EB),
        sidebarHover: Color(0xFFD9EAE0),
        divider: Color(0xFFDDEDE4),
        textPrimary: Color(0xFF14241C),
        textSecondary: Color(0xFF4E6056),
        textTertiary: Color(0xFF8AA096),
        accent: Color(0xFF00B96A),
        accentHover: Color(0xFF21C97E),
        danger: Color(0xFFC42B1C),
        hoverLayer: Color(0x0D000000),
        glass: Color(0xCCFFFFFF),
        glassBorder: Color(0x2EFFFFFF),
        lyricInactive: Color(0x99142E22),
      ),
      dark: AppColors(
        background: Color(0xFF0F1B15),
        card: Color(0xFF1B2A22),
        cardHover: Color(0xFF23342B),
        sidebar: Color(0xFF0A120D),
        sidebarHover: Color(0xFF14241C),
        divider: Color(0xFF284033),
        textPrimary: Color(0xFFEFFAF3),
        textSecondary: Color(0xFF9DB8A8),
        textTertiary: Color(0xFF64806F),
        accent: Color(0xFF37D98A),
        accentHover: Color(0xFF5AE39F),
        danger: Color(0xFFE5484D),
        hoverLayer: Color(0x14FFFFFF),
        glass: Color(0xB31B2A22),
        glassBorder: Color(0x2EFFFFFF),
        lyricInactive: Color(0x99C8E0D2),
      ),
    ),
    // ── 暖阳橙 ──
    ThemeSpec(
      id: 'amber',
      name: '暖阳琥珀',
      gradientStart: Color(0xFFFF8A3D),
      gradientEnd: Color(0xFFFF6A00),
      light: AppColors(
        background: Color(0xFFFAF5F0),
        card: Color(0xFFFFFFFF),
        cardHover: Color(0xFFF6F0EA),
        sidebar: Color(0xFFF2E9DF),
        sidebarHover: Color(0xFFEADDD0),
        divider: Color(0xFFEDE2D8),
        textPrimary: Color(0xFF2B1F16),
        textSecondary: Color(0xFF635548),
        textTertiary: Color(0xFF9C8B7B),
        accent: Color(0xFFFF8A3D),
        accentHover: Color(0xFFFF9D5B),
        danger: Color(0xFFC42B1C),
        hoverLayer: Color(0x0D000000),
        glass: Color(0xCCFFFFFF),
        glassBorder: Color(0x2EFFFFFF),
        lyricInactive: Color(0x99332A1F),
      ),
      dark: AppColors(
        background: Color(0xFF1C1510),
        card: Color(0xFF2A211A),
        cardHover: Color(0xFF342A21),
        sidebar: Color(0xFF120D09),
        sidebarHover: Color(0xFF201A14),
        divider: Color(0xFF3B3026),
        textPrimary: Color(0xFFFAF2EA),
        textSecondary: Color(0xFFC0AE9E),
        textTertiary: Color(0xFF7F6F5F),
        accent: Color(0xFFFF9D5B),
        accentHover: Color(0xFFFFB37D),
        danger: Color(0xFFE5484D),
        hoverLayer: Color(0x14FFFFFF),
        glass: Color(0xB32A211A),
        glassBorder: Color(0x2EFFFFFF),
        lyricInactive: Color(0x99E2D3C3),
      ),
    ),
    // ── 深邃青 ──
    ThemeSpec(
      id: 'teal',
      name: '深海青碧',
      gradientStart: Color(0xFF00B8D9),
      gradientEnd: Color(0xFF00A0E9),
      light: AppColors(
        background: Color(0xFFF0F7FA),
        card: Color(0xFFFFFFFF),
        cardHover: Color(0xFFEBF4F7),
        sidebar: Color(0xFFE4F0F5),
        sidebarHover: Color(0xFFD5E9F0),
        divider: Color(0xFFDCEAF0),
        textPrimary: Color(0xFF10242B),
        textSecondary: Color(0xFF4A5F66),
        textTertiary: Color(0xFF88A0A8),
        accent: Color(0xFF00B8D9),
        accentHover: Color(0xFF21C6E4),
        danger: Color(0xFFC42B1C),
        hoverLayer: Color(0x0D000000),
        glass: Color(0xCCFFFFFF),
        glassBorder: Color(0x2EFFFFFF),
        lyricInactive: Color(0x99102E38),
      ),
      dark: AppColors(
        background: Color(0xFF0E1619),
        card: Color(0xFF1A2428),
        cardHover: Color(0xFF222E33),
        sidebar: Color(0xFF090F11),
        sidebarHover: Color(0xFF131D20),
        divider: Color(0xFF27353B),
        textPrimary: Color(0xFFEFF9FB),
        textSecondary: Color(0xFF9DB8C0),
        textTertiary: Color(0xFF607B84),
        accent: Color(0xFF37CDE8),
        accentHover: Color(0xFF5AD7EE),
        danger: Color(0xFFE5484D),
        hoverLayer: Color(0x14FFFFFF),
        glass: Color(0xB31A2428),
        glassBorder: Color(0x2EFFFFFF),
        lyricInactive: Color(0x99C8E2E8),
      ),
    ),
    // ── 樱花粉 ──
    ThemeSpec(
      id: 'rose',
      name: '樱花粉黛',
      gradientStart: Color(0xFFFF5C93),
      gradientEnd: Color(0xFFF472B6),
      light: AppColors(
        background: Color(0xFFFAF3F6),
        card: Color(0xFFFFFFFF),
        cardHover: Color(0xFFF6EFF2),
        sidebar: Color(0xFFF3E8ED),
        sidebarHover: Color(0xFFEBDCE3),
        divider: Color(0xFFEFE0E6),
        textPrimary: Color(0xFF2E1620),
        textSecondary: Color(0xFF6B4A55),
        textTertiary: Color(0xFFA88A94),
        accent: Color(0xFFFF5C93),
        accentHover: Color(0xFFFF7AA6),
        danger: Color(0xFFC42B1C),
        hoverLayer: Color(0x0D000000),
        glass: Color(0xCCFFFFFF),
        glassBorder: Color(0x2EFFFFFF),
        lyricInactive: Color(0x9933242A),
      ),
      dark: AppColors(
        background: Color(0xFF1D1116),
        card: Color(0xFF2B1B22),
        cardHover: Color(0xFF35232C),
        sidebar: Color(0xFF130A0E),
        sidebarHover: Color(0xFF21161B),
        divider: Color(0xFF3B2730),
        textPrimary: Color(0xFFFAEFF3),
        textSecondary: Color(0xFFC2A2AE),
        textTertiary: Color(0xFF82626D),
        accent: Color(0xFFFF7AA6),
        accentHover: Color(0xFFFF96B9),
        danger: Color(0xFFE5484D),
        hoverLayer: Color(0x14FFFFFF),
        glass: Color(0xB32B1B22),
        glassBorder: Color(0x2EFFFFFF),
        lyricInactive: Color(0x99E3CAD2),
      ),
    ),
  ];

  static ThemeSpec byId(String id) =>
      specs.firstWhere((s) => s.id == id, orElse: () => specs.first);

  /// 由用户选定的基色派生一套自定义主题(明暗 + 渐变)。
  static ThemeSpec custom(Color base) {
    return ThemeSpec(
      id: 'custom',
      name: '自定义',
      gradientStart: base,
      gradientEnd: Color.lerp(base, Colors.black, 0.3)!,
      light: AppColors(
        background: const Color(0xFFF5F5F7),
        card: Colors.white,
        cardHover: const Color(0xFFEDEDF2),
        sidebar: const Color(0xFFEBEBEF),
        sidebarHover: const Color(0xFFDEDEE4),
        divider: const Color(0xFFE1E1E8),
        textPrimary: const Color(0xFF1D1D1F),
        textSecondary: const Color(0xFF55555C),
        textTertiary: const Color(0xFF8E8E96),
        accent: base,
        accentHover: Color.lerp(base, Colors.white, 0.25)!,
        danger: const Color(0xFFC42B1C),
        hoverLayer: const Color(0x0D000000),
        glass: const Color(0xCCFFFFFF),
        glassBorder: const Color(0x2EFFFFFF),
        lyricInactive: const Color(0x99333333),
      ),
      dark: AppColors(
        background: const Color(0xFF141416),
        card: const Color(0xFF202024),
        cardHover: const Color(0xFF29292E),
        sidebar: const Color(0xFF0C0C0F),
        sidebarHover: const Color(0xFF18181C),
        divider: const Color(0xFF2E2E34),
        textPrimary: const Color(0xFFF5F5F7),
        textSecondary: const Color(0xFFA6A6AF),
        textTertiary: const Color(0xFF6E6E76),
        accent: Color.lerp(base, Colors.white, 0.25)!,
        accentHover: Color.lerp(base, Colors.white, 0.42)!,
        danger: const Color(0xFFE5484D),
        hoverLayer: const Color(0x14FFFFFF),
        glass: const Color(0xB3202024),
        glassBorder: const Color(0x2EFFFFFF),
        lyricInactive: const Color(0x99D0D0D6),
      ),
    );
  }
}

class AppTheme {
  static const String fontFamily = 'HarmonyOS Sans SC';

  static ThemeData light(ThemeSpec spec) => _build(Brightness.light, spec);

  static ThemeData dark(ThemeSpec spec) => _build(Brightness.dark, spec);

  static ThemeData _build(Brightness brightness, ThemeSpec spec) {
    final isDark = brightness == Brightness.dark;
    final colors = isDark ? spec.dark : spec.light;
    final accent = colors.accent;
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      surface: colors.background,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      extensions: [colors],
      splashFactory: InkSparkle.splashFactory,
      textTheme: Typography.material2021().white.apply(
            fontFamily: fontFamily,
            bodyColor: colors.textPrimary,
            displayColor: colors.textPrimary,
          ),
      iconTheme: IconThemeData(color: colors.textPrimary, size: 20),
      dividerTheme: DividerThemeData(
        color: colors.divider,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        textColor: colors.textPrimary,
        iconColor: colors.textPrimary,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? colors.card : Colors.white,
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(color: Color(0x33000000), blurRadius: 8),
          ],
        ),
        textStyle: TextStyle(
          color: colors.textPrimary,
          fontSize: 12,
          fontFamily: fontFamily,
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          colors.divider.withValues(alpha: 0.8),
        ),
        thickness: WidgetStatePropertyAll(6),
      ),
    );
  }
}

extension BuildContextColors on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

/// 全局滚动行为:桌面鼠标滚轮使用带惯性的平滑滚动,
/// 触摸板/触屏获得弹性回弹(Apple Music 风格)。
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    );
  }
}

/// 统一的非线性曲线常量,供全局动画使用。
class AppMotion {
  /// 缓入缓出立方:进度/歌词/滑入等常规过渡。
  static const Curve curve = Curves.easeInOutCubic;

  /// 弹出回弹:页面/面板出现时轻微过冲,增强"丝滑"感。
  static const Curve pop = Curves.easeOutBack;

  /// 展开/收起(缩放 + 淡入)过渡时长。
  static const Duration medium = Duration(milliseconds: 380);
  static const Duration long = Duration(milliseconds: 560);

  /// 带轻微回弹的过渡曲线(缩放/滑动)。
  static const Curve elastic = Curves.easeOutCubic;
}
