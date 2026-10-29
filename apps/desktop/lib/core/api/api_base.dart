/// 后端 API 基础地址。
///
/// 默认本机调试；发布/CI 用 `--dart-define=API_BASE=...` 覆盖。
/// 授权、版本检查、联系支持共用同一地址。
const String kApiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://127.0.0.1:3000',
);
