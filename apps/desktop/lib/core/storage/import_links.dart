/// Downie 兼容的结构化导入。
///
/// CSV：表头必须包含 `url` 和 `title`，可选 `path`（保存目录）。
/// XML：根元素 `<downloads>`，每个 `<download>` 包含 `<url>`、`<title>`，
/// 可选 `<path>`。不是这两种格式时返回 null，调用方按普通文本处理。
class ImportedLink {
  final String url;
  final String title;
  final String path;

  const ImportedLink({
    required this.url,
    this.title = '',
    this.path = '',
  });
}

List<ImportedLink>? parseStructuredLinks(String text) {
  final trimmed = text.replaceFirst('﻿', '').trimLeft();
  if (trimmed.isEmpty) return null;

  if (RegExp(r'<downloads\b', caseSensitive: false).hasMatch(trimmed)) {
    return _parseXml(trimmed);
  }

  final rows = _parseCsv(trimmed);
  if (rows.isEmpty) return null;
  final columns = rows.first.map((h) => h.trim().toLowerCase()).toList();
  if (!columns.contains('url') || !columns.contains('title')) return null;
  return _fromRows(rows, columns);
}

List<ImportedLink>? _fromRows(
  List<List<String>> rows,
  List<String> columns,
) {
  final urlIndex = columns.indexOf('url');
  final titleIndex = columns.indexOf('title');
  final pathIndex = columns.indexOf('path');
  final links = <ImportedLink>[];
  for (final row in rows.skip(1)) {
    final url = _cell(row, urlIndex);
    if (!url.startsWith('http://') && !url.startsWith('https://')) continue;
    links.add(ImportedLink(
      url: url,
      title: _cell(row, titleIndex),
      path: _cell(row, pathIndex),
    ));
  }
  return links.isEmpty ? null : links;
}

String _cell(List<String> row, int index) {
  if (index < 0 || index >= row.length) return '';
  return row[index].trim();
}

/// 最小 CSV 解析：支持引号、逗号、双引号转义与字段内换行。
List<List<String>> _parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(ch);
      }
      continue;
    }
    switch (ch) {
      case '"':
        quoted = true;
        break;
      case ',':
        row.add(field.toString());
        field.clear();
        break;
      case '\n':
        row.add(field.toString());
        field.clear();
        rows.add(row);
        row = <String>[];
        break;
      case '\r':
        break;
      default:
        field.write(ch);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}

List<ImportedLink>? _parseXml(String text) {
  final blocks = RegExp(
    r'<download\b[^>]*>([\s\S]*?)</download\s*>',
    caseSensitive: false,
  ).allMatches(text);
  final links = <ImportedLink>[];
  for (final block in blocks) {
    final body = block.group(1) ?? '';
    final url = _xmlTag(body, 'url');
    if (!url.startsWith('http://') && !url.startsWith('https://')) continue;
    links.add(ImportedLink(
      url: url,
      title: _xmlTag(body, 'title'),
      path: _xmlTag(body, 'path'),
    ));
  }
  return links.isEmpty ? null : links;
}

String _xmlTag(String body, String name) {
  final match = RegExp(
    '<$name(?:\\s[^>]*)?>([\\s\\S]*?)</$name\\s*>',
    caseSensitive: false,
  ).firstMatch(body);
  if (match == null) return '';
  var value = (match.group(1) ?? '').trim();
  final cdata = RegExp(r'^<!\[CDATA\[([\s\S]*)\]\]>$').firstMatch(value);
  if (cdata != null) value = (cdata.group(1) ?? '').trim();
  return _decodeXml(value);
}

String _decodeXml(String value) {
  return value
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}
