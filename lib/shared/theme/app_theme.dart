import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

/// 应用主题配置
/// 使用 FlexColorScheme 提供高质量的亮/暗主题
class AppTheme {
  AppTheme._();

  /// 主题色板 - 选用深蓝色系，专业感
  static const FlexScheme _scheme = FlexScheme.blueM3;

  /// 亮色主题
  static ThemeData get light => FlexThemeData.light(
        scheme: _scheme,
        useMaterial3: true,
        appBarStyle: FlexAppBarStyle.surface,
        subThemesData: const FlexSubThemesData(
          interactionEffects: true,
          tintedDisabledControls: true,
          blendOnColors: true,
          blendTextTheme: true,
          tooltipRadius: 8,
          tooltipSchemeColor: SchemeColor.inverseSurface,
          tooltipOpacity: 0.9,
          drawerIndicatorSchemeColor: SchemeColor.primary,
          bottomNavigationBarMutedUnselectedLabel: false,
          bottomNavigationBarMutedUnselectedIcon: false,
          navigationBarSelectedLabelSchemeColor: SchemeColor.onSurface,
          navigationBarMutedUnselectedLabel: false,
          navigationBarMutedUnselectedIcon: false,
          navigationRailIndicatorSchemeColor: SchemeColor.primaryContainer,
          navigationRailMutedUnselectedLabel: false,
          navigationRailMutedUnselectedIcon: false,
        ),
        visualDensity: FlexColorScheme.comfortablePlatformDensity,
        useMaterial3ErrorColors: true,
      );

  /// 暗色主题
  static ThemeData get dark => FlexThemeData.dark(
        scheme: _scheme,
        useMaterial3: true,
        darkIsTrueBlack: false,
        subThemesData: const FlexSubThemesData(
          interactionEffects: true,
          tintedDisabledControls: true,
          blendOnColors: true,
          blendTextTheme: true,
          tooltipRadius: 8,
          tooltipSchemeColor: SchemeColor.inverseSurface,
          tooltipOpacity: 0.9,
          drawerIndicatorSchemeColor: SchemeColor.primary,
          bottomNavigationBarMutedUnselectedLabel: false,
          bottomNavigationBarMutedUnselectedIcon: false,
          navigationBarSelectedLabelSchemeColor: SchemeColor.onSurface,
          navigationBarMutedUnselectedLabel: false,
          navigationBarMutedUnselectedIcon: false,
          navigationRailIndicatorSchemeColor: SchemeColor.primaryContainer,
          navigationRailMutedUnselectedLabel: false,
          navigationRailMutedUnselectedIcon: false,
        ),
        visualDensity: FlexColorScheme.comfortablePlatformDensity,
        useMaterial3ErrorColors: true,
      );
}
