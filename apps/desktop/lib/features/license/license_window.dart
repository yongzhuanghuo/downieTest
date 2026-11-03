import 'package:flutter/material.dart';

import 'license_actions.dart';

/// 授权入口（兼容旧调用方）。
///
/// 真正的窗口在 [showLicenseFlow] 里按授权状态分发：
/// 未授权打开试用大窗口，已授权打开「感谢您的注册！」信息窗。
class LicenseWindow {
  LicenseWindow._();

  static Future<void> show(BuildContext context) {
    return showLicenseFlow(context);
  }
}
