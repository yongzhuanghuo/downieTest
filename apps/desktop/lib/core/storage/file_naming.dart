import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 播放列表/单视频文件名模板。
///
/// 支持 `{title}`、`{extractor}`、`{id}`（URL 的稳定短哈希）、`{date}`、
/// `{original}`（URL 末段，即服务器端点名）。结果会去掉文件系统非法字符
/// 并限制长度。
String renderFilenameTemplate(
  String template, {
  required String title,
  required String extractor,
  required String url,
  DateTime? now,
}) {
  final date = now ?? DateTime.now();
  final id = shortUrlId(url);
  var name = template
      .replaceAll('{title}', title)
      .replaceAll('{extractor}', extractor)
      .replaceAll('{id}', id)
      .replaceAll('{original}', originalFileName(url))
      .replaceAll('{date}', '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}');
  if (name.trim().isEmpty) name = title;
  name = sanitizePathSegment(name);
  if (name.length > 160) name = sanitizePathSegment(name.substring(0, 160));
  if (name.isEmpty) name = 'video_$id';
  return name;
}

/// 把字符串变成可以安全用作文件/目录名的片段。
String sanitizePathSegment(String value) {
  var result = value
      .replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  // Windows 不允许文件名以点或空格结尾
  result = result.replaceAll(RegExp(r'[. ]+$'), '');
  return result.trim();
}

/// URL 的稳定短哈希（用于同名视频区分/模板占位符）。
String shortUrlId(String url) {
  final digest = md5.convert(utf8.encode(url)).toString();
  return digest.substring(0, 8);
}

/// URL 末段（服务器端点名），去掉文件扩展名；无法解析时返回空串。
String originalFileName(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return '';
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return '';
  var name = segments.last;
  try {
    name = Uri.decodeComponent(name);
  } catch (_) {}
  return name.replaceFirst(RegExp(r'\.[A-Za-z0-9]{1,5}$'), '');
}
