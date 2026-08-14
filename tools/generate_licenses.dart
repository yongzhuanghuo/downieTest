import 'dart:io';
import 'dart:math';

import '../lib/core/license/license.dart';

void main(List<String> args) async {
  // ---------- 解析参数 ----------
  int count = 1;
  String typeStr = 'perpetual';
  int? devices;
  int expireDays = 0;
  String? output;

  for (int i = 0; i < args.length; i++) {
    final a = args[i];
    switch (a) {
      case '-t':
      case '--type':
        typeStr = args[++i];
        break;
      case '-d':
      case '--devices':
        devices = int.parse(args[++i]);
        break;
      case '-e':
      case '--expire':
        expireDays = int.parse(args[++i]);
        break;
      case '-c':
      case '--count':
        count = int.parse(args[++i]);
        break;
      case '-o':
      case '--output':
        output = args[++i];
        break;
      default:
        stderr.writeln('未知参数: $a');
        _printHelp();
        exit(1);
    }
  }

  final type = typeStr == 'free' ? LicenseType.free : LicenseType.perpetual;
  devices ??= type == LicenseType.perpetual ? 4 : 1;
  final expireAt = expireDays <= 0
      ? null
      : DateTime.now()
          .add(Duration(days: expireDays))
          .millisecondsSinceEpoch;

  final codes = <String>[];
  final rand = Random.secure();
  for (int i = 0; i < count; i++) {
    // nonce 用 24-bit 随机
    final nonce = rand.nextInt(1 << 24);
    final payload = LicensePayload(
      type: type,
      maxDevices: devices,
      expireAt: expireAt,
      nonce: nonce,
    );
    final code = LicenseActivation.generate(payload);
    // 自校验
    try {
      LicenseActivation.verify(code);
    } catch (e) {
      stderr.writeln('生成失败: 自校验不通过 $code: $e');
      exit(2);
    }
    codes.add(code);
  }

  final buf = StringBuffer();
  buf.writeln('activation_code,type,max_devices,expire_at_ts,expire_days');
  for (final c in codes) {
    final p = LicenseActivation.verify(c);
    buf.writeln(
      '$c,${p.type.name},${p.maxDevices},${p.expireAt ?? 0},$expireDays',
    );
  }

  if (output == null) {
    stdout.write(buf.toString());
  } else {
    await File(output!).writeAsString(buf.toString());
    print('✅ 已生成 ${codes.length} 个激活码 -> $output');
  }
}

void _printHelp() {
  print('''
用法: dart run tools/generate_licenses.dart [options]

  -t, --type       free | perpetual   (默认 perpetual)
  -d, --devices    最大设备数          (默认 free=1 perpetual=4)
  -e, --expire     过期天数            (默认 0=永不过期)
  -c, --count      生成数量            (默认 1)
  -o, --output     CSV 输出文件        (默认 stdout)

示例:
  dart run tools/generate_licenses.dart -c 5 -t perpetual -o pro.csv
  dart run tools/generate_licenses.dart -c 10 -t free -e 30 -o trial.csv
''');
}
