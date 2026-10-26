/// 用户自定义视频提取窗口的地址栏搜索引擎。
///
/// 只影响在提取窗口里输入关键词时的跳转，不参与视频解析。
class SearchEngine {
  final int id;
  final String name;
  final String urlTemplate;

  const SearchEngine({
    required this.id,
    required this.name,
    required this.urlTemplate,
  });

  String build(String query) =>
      urlTemplate.replaceAll('{query}', Uri.encodeQueryComponent(query));
}

const List<SearchEngine> kSearchEngines = [
  SearchEngine(
    id: 0,
    name: 'Google',
    urlTemplate: 'https://www.google.com/search?q={query}',
  ),
  SearchEngine(
    id: 1,
    name: 'Bing',
    urlTemplate: 'https://www.bing.com/search?q={query}',
  ),
  SearchEngine(
    id: 2,
    name: '百度',
    urlTemplate: 'https://www.baidu.com/s?wd={query}',
  ),
  SearchEngine(
    id: 3,
    name: 'DuckDuckGo',
    urlTemplate: 'https://duckduckgo.com/?q={query}',
  ),
];

SearchEngine searchEngineById(int id) => kSearchEngines.firstWhere(
      (engine) => engine.id == id,
      orElse: () => kSearchEngines[1],
    );

/// 把地址栏输入变成可加载的 URL：
/// - 完整 URL 原样返回
/// - 像域名（含点、无空格）的补 https://
/// - 其他当关键词搜索
String resolveAddressInput(String input, {required int engineId}) {
  final value = input.trim();
  if (value.isEmpty) return '';
  final uri = Uri.tryParse(value);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    return value;
  }
  if (RegExp(r'^[\w-]+(\.[\w-]+)+(:\d+)?(/.*)?$').hasMatch(value)) {
    return 'https://$value';
  }
  return searchEngineById(engineId).build(value);
}
