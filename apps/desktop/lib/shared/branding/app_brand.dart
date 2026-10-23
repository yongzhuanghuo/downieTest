/// 应用品牌配置。
///
/// 名称/图标/邮箱集中在这里，避免散落在页面里。
/// 注意：不能使用 Downie 的名称、图标或其它受商标/版权保护的资产。
///
/// 换品牌时这里只影响应用内文字；安装包和系统显示名还要改：
/// `tools/generate_installer_assets.swift`（DMG 背景/说明图）、
/// `macos/Runner/Info.plist`、`windows/runner/Runner.rc`、
/// `windows/installer/setup.iss`、`.github/workflows/build.yml`（DMG 卷名）。
class AppBrand {
  AppBrand._();

  static const String name = '4KDownle 6';
  static const String shortName = '4KDownle';
  static const String tagline = '全能视频下载器';
  static const String supportEmail = 'huoyongzhuang@qq.com';
  static const String logoAsset = 'assets/logo.png';

  static const String privacyNote =
      '$name 的解析和下载在本地完成。只有授权校验、版本检查和主动发送的反馈会联网。'
      '不会上传你下载的视频内容。反馈邮件会发送到 $supportEmail。';
}
