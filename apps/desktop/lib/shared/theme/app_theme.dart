import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Downie 4 风格的桌面主题。
///
/// 深色是主视觉；浅色保留一套对应的 native 色值。
/// 组件层不再使用 Material 默认的卡片/涟漪，具体页面用 token 自绘。
class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final window = isDark ? AppTokens.window : AppTokens.windowLight;
    final panel = isDark ? AppTokens.panel : AppTokens.panelLight;
    final divider = isDark ? AppTokens.divider : AppTokens.dividerLight;
    final textPrimary =
        isDark ? AppTokens.textPrimary : AppTokens.textPrimaryLight;
    final textSecondary =
        isDark ? AppTokens.textSecondary : AppTokens.textSecondaryLight;
    final accent = isDark ? AppTokens.accent : AppTokens.accentLight;
    final error = isDark ? AppTokens.error : AppTokens.errorLight;
    final hover = isDark ? AppTokens.hover : AppTokens.hoverLight;

    final textTheme = _textTheme(isDark);
    final scheme = isDark
        ? const ColorScheme.dark(
            primary: AppTokens.accent,
            onPrimary: Colors.white,
            secondary: AppTokens.accent,
            onSecondary: Colors.white,
            surface: AppTokens.window,
            onSurface: AppTokens.textPrimary,
            onSurfaceVariant: AppTokens.textSecondary,
            error: AppTokens.error,
            onError: Colors.white,
            outline: AppTokens.divider,
            outlineVariant: AppTokens.divider,
            surfaceContainerLow: AppTokens.panel,
            surfaceContainer: AppTokens.panel,
            surfaceContainerHigh: AppTokens.panelRaised,
          )
        : const ColorScheme.light(
            primary: AppTokens.accentLight,
            onPrimary: Colors.white,
            secondary: AppTokens.accentLight,
            onSecondary: Colors.white,
            surface: AppTokens.windowLight,
            onSurface: AppTokens.textPrimaryLight,
            onSurfaceVariant: AppTokens.textSecondaryLight,
            error: AppTokens.errorLight,
            onError: Colors.white,
            outline: AppTokens.dividerLight,
            outlineVariant: AppTokens.dividerLight,
            surfaceContainerLow: AppTokens.panelLight,
            surfaceContainer: AppTokens.panelLight,
            surfaceContainerHigh: AppTokens.panelRaisedLight,
          );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: window,
      fontFamily: AppTextStyles.fontFamily,
      visualDensity: VisualDensity.compact,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: hover,
      dividerColor: divider,
      dividerTheme: DividerThemeData(
        color: divider,
        thickness: 1,
        space: 1,
      ),
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      iconTheme: IconThemeData(color: textSecondary, size: 16),
      appBarTheme: AppBarTheme(
        backgroundColor: window,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.panel),
          side: BorderSide(color: divider),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panel,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        hintStyle: TextStyle(color: textSecondary.withValues(alpha: 0.8)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: BorderSide(color: accent),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          minimumSize: const Size(0, 30),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          minimumSize: const Size(0, 28),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          textStyle: const TextStyle(fontSize: 12),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: textSecondary,
          splashFactory: NoSplash.splashFactory,
          minimumSize: const Size(26, 26),
          padding: EdgeInsets.zero,
          iconSize: 16,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: panel,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: textPrimary, fontSize: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          side: BorderSide(color: divider),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: panel,
        contentTextStyle: TextStyle(color: textPrimary, fontSize: 12),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: divider),
        ),
        textStyle: TextStyle(color: textPrimary, fontSize: 11),
        waitDuration: const Duration(milliseconds: 500),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all<double?>(6.0),
        radius: const Radius.circular(3),
        thumbColor: WidgetStateProperty.all<Color?>(
          textSecondary.withValues(alpha: 0.35),
        ),
        trackColor: WidgetStateProperty.all<Color?>(Colors.transparent),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.window),
          side: BorderSide(color: divider),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: accent.withValues(alpha: 0.3),
        selectionHandleColor: accent,
      ),
    );
  }

  static TextTheme _textTheme(bool isDark) {
    final primary =
        isDark ? AppTokens.textPrimary : AppTokens.textPrimaryLight;
    final secondary =
        isDark ? AppTokens.textSecondary : AppTokens.textSecondaryLight;
    TextStyle style(double size, FontWeight weight, {Color? color}) {
      return TextStyle(
        fontFamily: AppTextStyles.fontFamily,
        fontFamilyFallback: const [
          'PingFang SC',
          'Microsoft YaHei UI',
          'Noto Sans CJK SC',
        ],
        fontSize: size,
        fontWeight: weight,
        color: color ?? primary,
      );
    }

    return TextTheme(
      displayLarge: style(34, FontWeight.w700),
      displayMedium: style(28, FontWeight.w700),
      displaySmall: style(24, FontWeight.w700),
      headlineLarge: style(24, FontWeight.w700),
      headlineMedium: style(22, FontWeight.w600),
      headlineSmall: style(20, FontWeight.w600),
      titleLarge: style(18, FontWeight.w600),
      titleMedium: style(15, FontWeight.w600),
      titleSmall: style(13, FontWeight.w600),
      bodyLarge: style(14, FontWeight.w400),
      bodyMedium: style(13, FontWeight.w400),
      bodySmall: style(11, FontWeight.w400, color: secondary),
      labelLarge: style(13, FontWeight.w500),
      labelMedium: style(11, FontWeight.w500),
      labelSmall: style(10, FontWeight.w500, color: secondary),
    );
  }
}
