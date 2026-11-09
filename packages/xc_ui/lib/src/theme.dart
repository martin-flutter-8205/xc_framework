import 'package:flutter/material.dart';

/// 全局唯一样式来源：主壳 `MaterialApp.theme` 与业务包里的硬编码色都取自这里。
///
/// 「响彻星空」的视觉基调是深空：近黑的底、星云紫蓝的点缀、发光的选中态。
class XcTheme {
  XcTheme._();

  /// 深空底色：几乎黑，但偏蓝，比纯黑有层次。
  static const Color deepSpace = Color(0xFF080C18);

  /// 星云主色：紫蓝，用作 seed。
  static const Color nebula = Color(0xFF7C8CFF);

  /// 深色主题（App 默认）。
  static ThemeData get dark => _build(Brightness.dark);

  /// 浅色主题（留给系统跟随，视觉不作主打）。
  static ThemeData get light => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: nebula,
      brightness: brightness,
    ).copyWith(
      surface: isDark ? const Color(0xFF0D1226) : const Color(0xFFF6F7FF),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? deepSpace : scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.3),
        thickness: 1,
        space: 1,
      ),
    );
  }
}
