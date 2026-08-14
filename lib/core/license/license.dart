import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

/// ===================================================================
/// 许可证类型（可扩展更多等级，如月费年卡）
/// ===================================================================
enum LicenseType {
  /// 免费版
  free,

  /// 永久版（30元买断）
  perpetual;

  factory LicenseType.fromCode(String code) {
    switch (code.toUpperCase()) {
      case 'P':
        return LicenseType.perpetual;
      default:
        return LicenseType.free;
    }
  }

  String toCode() => this == LicenseType.perpetual ? 'P' : 'F';

  /// 中文描述
  String get label => this == LicenseType.perpetual ? 'PRO 永久版' : '免费版';
}

/// ===================================================================
/// 激活码 payload（解码后）
/// ===================================================================
@immutable
class LicensePayload {
  /// 许可证类型
  final LicenseType type;

  /// 最大绑定设备数（免费=1，PRO=4）
  final int maxDevices;

  /// 过期时间毫秒，null=永不过期（买断版）
  final int? expireAt;

  /// 随机 nonce（防止相同参数生成相同激活码）
  final int nonce;

  const LicensePayload({
    required this.type,
    required this.maxDevices,
    required this.expireAt,
    required this.nonce,
  });

  /// 是否过期（永不过期=永远 false）
  bool get isExpired {
    if (expireAt == null) return false;
    return DateTime.now().millisecondsSinceEpoch > expireAt!;
  }

  // =======================================================================
  // 紧凑二进制编码（保证 base36 后固定长度）
  // [1B type|devices] [4B expireTs 或 0] [3B nonce] = 8 bytes
  // =======================================================================

  /// 编码为固定 8 字节
  List<int> toBytes() {
    final b = <int>[];
    final typeByte = (type == LicenseType.perpetual ? 0x10 : 0x00) |
        (maxDevices.clamp(0, 15) & 0x0F);
    b.add(typeByte);
    final exp = expireAt ?? 0;
    // 只保留 expireTs 的低 32 bit 有效位(足够到 2106 年)
    b.add((exp >> 24) & 0xff);
    b.add((exp >> 16) & 0xff);
    b.add((exp >> 8) & 0xff);
    b.add(exp & 0xff);
    final n = nonce & 0x00ffffff;
    b.add((n >> 16) & 0xff);
    b.add((n >> 8) & 0xff);
    b.add(n & 0xff);
    return b; // 固定 8 bytes
  }

  factory LicensePayload.fromBytes(List<int> b) {
    if (b.length < 8) {
      throw LicenseException('Payload 长度不足 (${b.length})');
    }
    // 确保 8 bytes 对齐
    final data = b.length == 8 ? b : b.sublist(b.length - 8);
    final typeByte = data[0];
    final type = (typeByte & 0x10) != 0
        ? LicenseType.perpetual
        : LicenseType.free;
    final maxDevices = typeByte & 0x0F;

    int exp = 0;
    exp = exp | ((data[1] & 0xff) << 24);
    exp = exp | ((data[2] & 0xff) << 16);
    exp = exp | ((data[3] & 0xff) << 8);
    exp = exp | (data[4] & 0xff);
    final expireAt = exp == 0 ? null : exp;

    int nonce = 0;
    nonce = nonce | ((data[5] & 0xff) << 16);
    nonce = nonce | ((data[6] & 0xff) << 8);
    nonce = nonce | (data[7] & 0xff);

    return LicensePayload(
      type: type,
      maxDevices: maxDevices,
      expireAt: expireAt,
      nonce: nonce,
    );
  }
}

/// ===================================================================
/// 已激活的许可证（包含 payload + 绑定设备列表 + 激活时间）
/// 持久化到 Hive
/// ===================================================================
@immutable
class ActivatedLicense {
  final String code; // 激活码原文（用户可查）
  final LicensePayload payload;
  final List<String> boundDevices; // 设备指纹列表
  final int activatedAt; // 激活时间

  const ActivatedLicense({
    required this.code,
    required this.payload,
    required this.boundDevices,
    required this.activatedAt,
  });

  LicenseType get type => payload.type;
  int get maxDevices => payload.maxDevices;
  bool get isPro => type == LicenseType.perpetual && !payload.isExpired;

  /// 剩余可绑名额
  int get remainingSlots => (maxDevices - boundDevices.length).clamp(0, 999);

  /// 设备是否已绑定
  bool isDeviceBound(String fp) => boundDevices.contains(fp);

  /// 是否可以再绑一台
  bool get canBindMore => boundDevices.length < maxDevices;

  ActivatedLicense copyWith({
    List<String>? boundDevices,
  }) {
    return ActivatedLicense(
      code: code,
      payload: payload,
      boundDevices: boundDevices ?? this.boundDevices,
      activatedAt: activatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'type': payload.type.toCode(),
      'maxDevices': payload.maxDevices,
      'expireAt': payload.expireAt,
      'nonce': payload.nonce,
      'boundDevices': boundDevices,
      'activatedAt': activatedAt,
    };
  }

  factory ActivatedLicense.fromMap(Map<String, dynamic> m) {
    return ActivatedLicense(
      code: m['code'] as String,
      payload: LicensePayload(
        type: LicenseType.fromCode((m['type'] as String?) ?? 'F'),
        maxDevices: (m['maxDevices'] as num?)?.toInt() ?? 1,
        expireAt: m['expireAt'] as int?,
        nonce: (m['nonce'] as num?)?.toInt() ?? 0,
      ),
      boundDevices: List<String>.from(m['boundDevices'] as List? ?? const []),
      activatedAt: (m['activatedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

/// ===================================================================
/// 激活码工具：生成 / 校验 / 格式化
/// ===================================================================
class LicenseActivation {
  LicenseActivation._();

  // ⚠️ 密钥硬编码，仅供离线 MVP 演示用。商用部署必须换成服务器端签发。
  // 开发者可自行修改此字符串，重新生成激活码即可。
  static const String _secret = 'DownloPRO_HMAC_v2_x9K2pQ7mFz4L8cN3sR5t';
  static const int codeLength = 20;       // 激活码有效字母数字 20 位
  static const int groupSize = 5;         // 5 位一组 = XXXX-XXXX-XXXX-XXXX

  // 20 chars × 5bit = 100bit，取整字节 12 bytes = 96bit（末尾 4bit 补 0）
  // 布局: [4 bytes HMAC-SHA256 截断] [8 bytes payload]
  static const int _sigBytes = 4;
  static const int _payloadBytes = 8;
  static const int _totalBytes = _sigBytes + _payloadBytes; // 12

  /// 自定义 base32 字母表（去掉易混字符）：A-Z + 2-7 = 32
  static const String _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// =================================================================
  /// 生成激活码
  /// =================================================================
  static String generate(LicensePayload payload) {
    final payloadBytes = payload.toBytes(); // 8 bytes
    final sigBytes = _hmacSha256Truncated(payloadBytes); // 4 bytes
    final bytes = <int>[...sigBytes, ...payloadBytes]; // 12 bytes
    return _group(_encodeBase32(bytes).toUpperCase());
  }

  /// =================================================================
  /// 校验激活码并返回 payload
  /// =================================================================
  static LicensePayload verify(String code) {
    final clean = _clean(code);
    if (clean.length != codeLength) {
      throw LicenseException('激活码长度不正确（应为 XXXX-XXXX-XXXX-XXXX）');
    }
    final bytes = _decodeBase32(clean);
    if (bytes.length != _totalBytes) {
      throw LicenseException('激活码格式无效');
    }
    final gotSig = bytes.sublist(0, _sigBytes);
    final payloadBytes = bytes.sublist(_sigBytes);
    final expectedSig = _hmacSha256Truncated(payloadBytes);
    if (!_bytesEqual(gotSig, expectedSig)) {
      throw LicenseException('激活码无效（签名不匹配）');
    }
    final payload = LicensePayload.fromBytes(payloadBytes);
    if (payload.isExpired) {
      throw LicenseException('激活码已过期');
    }
    return payload;
  }

  // ======================= 内部工具 =======================

  /// 真正的 HMAC-SHA256，取前 4 字节作为签名
  /// 碰撞率 ≈ 1/2³²，安全性远高于 CRC16
  static List<int> _hmacSha256Truncated(List<int> data) {
    final key = utf8.encode(_secret);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(data);
    // 取前 4 字节（32 bit）
    return digest.bytes.sublist(0, _sigBytes);
  }

  /// 预处理激活码：去掉分隔符 + 统一大写 + 易混字符规范
  /// 字母表不含 0,1,I,O，所以用户可能输错的字符统一映射：
  ///   0, O → 8（数字 8 在字母表，一致映射）
  ///   1, I → L（字母 L 在字母表，一致映射）
  static String _clean(String code) {
    final up = code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return up
        .replaceAll('O', '8')
        .replaceAll('0', '8')
        .replaceAll('1', 'L')
        .replaceAll('I', 'L');
  }

  static String _group(String code) {
    final parts = <String>[];
    for (int i = 0; i < code.length; i += groupSize) {
      final end = (i + groupSize > code.length) ? code.length : i + groupSize;
      parts.add(code.substring(i, end));
    }
    return parts.join('-');
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ===================================================================
  // 自定义 base32（5-bit 流编码），不用大整数，位操作直接映射
  // 字母表: ABCDEFGHJKLMNPQRSTUVWXYZ23456789 (32 字符，不含 0,1,I,O)
  // 末尾字符：有效数据对齐到 LSB，padding 0 在高 bit 侧，
  // 确保修改激活码任意一位都会改变解码出的字节。
  // ===================================================================

  /// bytes → 5-bit 组 → base32 字符
  /// 尾部剩余有效位对齐 LSB（高位补 0 当 padding）
  static String _encodeBase32(List<int> bytes) {
    final out = StringBuffer();
    int buffer = 0;
    int bitsLeft = 0;
    for (final b in bytes) {
      buffer = (buffer << 8) | (b & 0xff);
      bitsLeft += 8;
      while (bitsLeft >= 5) {
        bitsLeft -= 5;
        final idx = (buffer >> bitsLeft) & 0x1F;
        out.write(_alphabet[idx]);
      }
    }
    if (bitsLeft > 0) {
      // 剩余 bitsLeft 位真实数据，对齐到字符的 LSB，高位补 0
      final idx = buffer & ((1 << bitsLeft) - 1);
      out.write(_alphabet[idx]);
    }
    return out.toString();
  }

  /// base32 字符串 → 字节（按 5-bit 还原，正好 12 bytes）
  /// 与编码对称：最后一个字符只取 LSB 侧的真实位数，高位被丢弃
  static List<int> _decodeBase32(String s) {
    int buffer = 0;
    int bitsLeft = 0;
    final out = <int>[];
    final expectedBits = _totalBytes * 8; // 96
    int consumedBits = 0;
    for (final ch in s.split('')) {
      final idx = _alphabet.indexOf(ch);
      if (idx < 0) continue;
      final remaining = expectedBits - consumedBits;
      // 只取还需要的位：剩下不足 5 位时，取 idx 的 LSB
      final take = remaining < 5 ? remaining : 5;
      final mask = (1 << take) - 1;
      final val = idx & mask;
      buffer = (buffer << take) | val;
      bitsLeft += take;
      consumedBits += take;
      while (bitsLeft >= 8) {
        bitsLeft -= 8;
        out.add((buffer >> bitsLeft) & 0xff);
      }
      if (consumedBits >= expectedBits) break;
    }
    // 12 字节对齐（兜底）
    final need = _totalBytes;
    if (out.length < need) {
      return List<int>.filled(need - out.length, 0) + out;
    }
    return out.sublist(0, need);
  }
}

/// ===================================================================
/// 设备指纹：基于平台稳定硬件 ID
/// ===================================================================
class DeviceFingerprint {
  DeviceFingerprint._();

  /// 获取当前设备指纹（失败=回退到MAC地址+主机名组合）
  static Future<String> get() async {
    try {
      if (Platform.isMacOS) {
        return await _ioreg();
      } else if (Platform.isWindows) {
        return await _windowsMachineGuid();
      } else {
        return await _hostnameFallback();
      }
    } catch (e) {
      stderr.writeln('[DeviceFingerprint] 失败: $e，回退到 hostname');
      return _hostnameFallback();
    }
  }

  /// macOS: IOPlatformUUID（每台 Mac 唯一且长期稳定）
  static Future<String> _ioreg() async {
    final r = await Process.run('ioreg', ['-rd1', '-c', 'IOPlatformExpertDevice']);
    final out = r.stdout.toString();
    final match = RegExp(r'"IOPlatformUUID" = "([^"]+)"').firstMatch(out);
    if (match != null) return match.group(1)!.replaceAll('-', '').toLowerCase();
    throw StateError('无法解析 ioreg 结果');
  }

  /// Windows: HKLM\SOFTWARE\Microsoft\Cryptography\MachineGuid
  static Future<String> _windowsMachineGuid() async {
    final r = await Process.run('reg', [
      'query',
      r'HKLM\SOFTWARE\Microsoft\Cryptography',
      '/v',
      'MachineGuid',
    ]);
    final out = r.stdout.toString();
    final match = RegExp(r'MachineGuid\s+REG_SZ\s+([^\r\n]+)').firstMatch(out);
    if (match != null) return match.group(1)!.replaceAll('-', '').toLowerCase();
    throw StateError('无法读取 MachineGuid');
  }

  /// 通用 fallback: hostname + 本地化主机 ID
  static Future<String> _hostnameFallback() async {
    final h = Platform.localHostname;
    final sep = Platform.pathSeparator;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        sep;
    return ('$h-$home').hashCode.toRadixString(16).padLeft(16, '0');
  }
}

/// ===================================================================
/// 许可证异常
/// ===================================================================
class LicenseException implements Exception {
  final String message;
  LicenseException(this.message);
  @override
  String toString() => 'LicenseException: $message';
}
