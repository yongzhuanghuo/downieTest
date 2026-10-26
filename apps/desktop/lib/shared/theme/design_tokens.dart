import 'dart:io';

import 'package:flutter/material.dart';

/// Downie 4 风格的桌面端设计 token。
///
/// 颜色是深色优先，浅色主题保留对应值；尺寸按 640×440 主窗口设计。
class AppTokens {
  AppTokens._();

  // 深色
  static const Color window = Color(0xFF1E1E1E);
  static const Color titleBar = Color(0xFF2A2A2A);
  static const Color statusBar = Color(0xFF181818);
  static const Color panel = Color(0xFF242424);
  static const Color panelRaised = Color(0xFF2E2E2E);
  static const Color divider = Color(0xFF3A3A3A);
  static const Color textPrimary = Color(0xFFF5F5F5);
  static const Color textSecondary = Color(0xFFA0A0A0);
  static const Color textTertiary = Color(0xFF6E6E6E);
  static const Color accent = Color(0xFF0A84FF);
  static const Color error = Color(0xFFFF453A);
  static const Color success = Color(0xFF30D158);
  static const Color warning = Color(0xFFFFD60A);
  static const Color overlay = Color(0xB3000000);
  static const Color hover = Color(0x14FFFFFF);
  static const Color pressed = Color(0x24FFFFFF);

  // 浅色
  static const Color windowLight = Color(0xFFF2F2F2);
  static const Color titleBarLight = Color(0xFFE8E8E8);
  static const Color statusBarLight = Color(0xFFE4E4E4);
  static const Color panelLight = Color(0xFFFFFFFF);
  static const Color panelRaisedLight = Color(0xFFF7F7F7);
  static const Color dividerLight = Color(0xFFD6D6D6);
  static const Color textPrimaryLight = Color(0xFF1D1D1F);
  static const Color textSecondaryLight = Color(0xFF6E6E73);
  static const Color textTertiaryLight = Color(0xFF9A9A9E);
  static const Color accentLight = Color(0xFF007AFF);
  static const Color errorLight = Color(0xFFFF3B30);
  static const Color successLight = Color(0xFF34C759);
  static const Color hoverLight = Color(0x0A000000);
  static const Color pressedLight = Color(0x14000000);
}

class AppSpacing {
  AppSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double xxl = 20;
  static const double xxxl = 24;
  static const double huge = 32;
}

class AppRadius {
  AppRadius._();

  static const double control = 4;
  static const double button = 6;
  static const double panel = 8;
  static const double window = 10;
  static const double card = 12;
}

class AppTextStyles {
  AppTextStyles._();

  static const String _macFont = '.SF Pro Text';
  static const String _winFont = 'Segoe UI';
  static const List<String> _fallback = [
    'PingFang SC',
    'Microsoft YaHei UI',
    'Noto Sans CJK SC',
  ];

  static String get fontFamily => Platform.isWindows ? _winFont : _macFont;

  static TextStyle _base(
    double size,
    FontWeight weight, {
    double? height,
    Color? color,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontFamilyFallback: _fallback,
      fontSize: size,
      fontWeight: weight,
      height: height,
      color: color,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle windowTitle(Color color) =>
      _base(13, FontWeight.w600, color: color);

  static TextStyle rowTitle(Color color) =>
      _base(15, FontWeight.w600, color: color);

  static TextStyle rowMeta(Color color) =>
      _base(11, FontWeight.w400, color: color);

  static TextStyle statusBar(Color color) =>
      _base(11, FontWeight.w500, color: color);

  static TextStyle panelTitle(Color color) =>
      _base(20, FontWeight.w600, color: color);

  static TextStyle body(Color color) => _base(13, FontWeight.w400, color: color);
}
