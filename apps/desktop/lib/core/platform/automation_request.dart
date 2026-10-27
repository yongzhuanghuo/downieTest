import '../../data/models/download_task.dart';

/// Downie 兼容的自动化请求。
///
/// 支持两类输入：
/// - 直接 HTTP(S) 链接（`open -a Downie6 <url>`）
/// - `downie6://XUOpenURL?url=...&postprocessing=...&destination=...`
class AutomationRequest {
  final String url;
  final String title;
  final String destination;
  final PostprocessingMode? postprocessing;
  final bool openInUge;

  const AutomationRequest({
    required this.url,
    this.title = '',
    this.destination = '',
    this.postprocessing,
    this.openInUge = false,
  });
}

AutomationRequest? parseAutomationRequest(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;

  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'http' || scheme == 'https') {
    return AutomationRequest(url: trimmed);
  }
  if (scheme != 'downie6') return null;

  final host = uri.host.toLowerCase();
  if (host != 'xuopenurl' && host != 'open') return null;
  final params = uri.queryParameters;
  final url = (params['url'] ?? '').trim();
  if (!url.startsWith('http://') && !url.startsWith('https://')) return null;

  return AutomationRequest(
    url: url,
    title: (params['title'] ?? '').trim(),
    destination: (params['destination'] ?? '').trim(),
    postprocessing: _mode(params['postprocessing']),
    openInUge: (params['action'] ?? '').toLowerCase() == 'open_in_uge',
  );
}

PostprocessingMode? _mode(String? value) {
  switch (value?.toLowerCase()) {
    case 'mp4':
      return PostprocessingMode.mp4;
    case 'audio':
      return PostprocessingMode.audio;
    default:
      return null;
  }
}
