/// Downie 兼容的 `downie-license://` 授权自动化。
///
/// 示例：
///   downie-license://activate?email=me@example.com&license=XXXXX-...
///   downie-license://deactivate?email=me@example.com&license=XXXXX-...
///
/// 也接受 `downie6-license://`，避免与已安装的 Downie 4 抢占 scheme。
class LicenseAutomationRequest {
  final bool activate;
  final String email;
  final String code;
  final bool hide;

  const LicenseAutomationRequest({
    required this.activate,
    required this.email,
    required this.code,
    this.hide = false,
  });
}

LicenseAutomationRequest? parseLicenseAutomation(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'downie-license' && scheme != 'downie6-license') return null;
  final action = uri.host.toLowerCase();
  if (action != 'activate' && action != 'deactivate') return null;
  final email = (uri.queryParameters['email'] ?? '').trim();
  final license = (uri.queryParameters['license'] ?? '').trim();
  if (email.isEmpty || license.isEmpty) return null;
  return LicenseAutomationRequest(
    activate: action == 'activate',
    email: email,
    code: license,
    hide: (uri.queryParameters['hide'] ?? '').toLowerCase() == 'true',
  );
}
