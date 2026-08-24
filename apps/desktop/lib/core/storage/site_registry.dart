import 'package:flutter/foundation.dart';

/// 一个可登录站点的配置
@immutable
class SiteConfig {
  /// cookie 文件名用（如 'youtube'）
  final String id;

  /// 显示名（如 'YouTube'）
  final String name;

  /// 匹配的域名（host 后缀匹配，如 'youtube.com'）
  final List<String> domains;

  /// 登录页 URL
  final String loginUrl;

  /// 抓 cookie 的域名（如 '.youtube.com'）
  final String cookieDomain;

  const SiteConfig({
    required this.id,
    required this.name,
    required this.domains,
    required this.loginUrl,
    required this.cookieDomain,
  });
}

/// 内置的常见需登录站点列表
const List<SiteConfig> kLoginSites = [
  SiteConfig(
    id: 'youtube',
    name: 'YouTube',
    domains: ['youtube.com', 'youtu.be'],
    loginUrl: 'https://www.youtube.com',
    cookieDomain: '.youtube.com',
  ),
  SiteConfig(
    id: 'douyin',
    name: '抖音',
    domains: ['douyin.com'],
    loginUrl: 'https://www.douyin.com',
    cookieDomain: '.douyin.com',
  ),
  SiteConfig(
    id: 'bilibili',
    name: '哔哩哔哩',
    domains: ['bilibili.com'],
    loginUrl: 'https://www.bilibili.com',
    cookieDomain: '.bilibili.com',
  ),
  SiteConfig(
    id: 'xiaohongshu',
    name: '小红书',
    domains: ['xiaohongshu.com'],
    loginUrl: 'https://www.xiaohongshu.com',
    cookieDomain: '.xiaohongshu.com',
  ),
  SiteConfig(
    id: 'kuaishou',
    name: '快手',
    domains: ['kuaishou.com'],
    loginUrl: 'https://www.kuaishou.com',
    cookieDomain: '.kuaishou.com',
  ),
  SiteConfig(
    id: 'weibo',
    name: '微博',
    domains: ['weibo.com'],
    loginUrl: 'https://weibo.com',
    cookieDomain: '.weibo.com',
  ),
  SiteConfig(
    id: 'twitter',
    name: 'Twitter / X',
    domains: ['x.com', 'twitter.com', 't.co'],
    loginUrl: 'https://x.com',
    cookieDomain: '.x.com',
  ),
  SiteConfig(
    id: 'vimeo',
    name: 'Vimeo',
    domains: ['vimeo.com'],
    loginUrl: 'https://vimeo.com',
    cookieDomain: '.vimeo.com',
  ),
  SiteConfig(
    id: 'twitch',
    name: 'Twitch',
    domains: ['twitch.tv'],
    loginUrl: 'https://www.twitch.tv',
    cookieDomain: '.twitch.tv',
  ),
  SiteConfig(
    id: 'instagram',
    name: 'Instagram',
    domains: ['instagram.com'],
    loginUrl: 'https://www.instagram.com',
    cookieDomain: '.instagram.com',
  ),
  SiteConfig(
    id: 'tiktok',
    name: 'TikTok',
    domains: ['tiktok.com'],
    loginUrl: 'https://www.tiktok.com',
    cookieDomain: '.tiktok.com',
  ),
];

/// 从视频 URL 解析站点配置：命中内置列表则返回，否则按域名自动推导（未知站点也能登录）
SiteConfig resolveSite(String url) {
  final host = _extractHost(url);
  for (final site in kLoginSites) {
    for (final d in site.domains) {
      if (host == d || host.endsWith('.$d')) {
        return site;
      }
    }
  }
  final domain = _eTLD1(host);
  return SiteConfig(
    id: domain.replaceAll('.', '_'),
    name: domain,
    domains: [domain],
    loginUrl: 'https://www.$domain',
    cookieDomain: '.$domain',
  );
}

String _extractHost(String url) {
  try {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.startsWith('www.') ? host.substring(4) : host;
  } catch (_) {
    return '';
  }
}

String _eTLD1(String host) {
  final parts = host.split('.');
  if (parts.length <= 2) return host;
  return '${parts[parts.length - 2]}.${parts[parts.length - 1]}';
}
