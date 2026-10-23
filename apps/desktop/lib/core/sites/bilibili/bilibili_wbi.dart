import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Bilibili WBI 签名。
///
/// 接口在 `/x/web-interface/nav` 返回 `wbi_img.img_url` / `sub_url`，
/// 取文件名作为 key，经过固定 mixin 表重排后取前 32 位作为 mixin key；
/// 请求参数排序、URL 编码、拼上 `wts` 后 md5(query + mixinKey) 得到 `w_rid`。
class BilibiliWbi {
  BilibiliWbi({required String imgUrl, required String subUrl})
      : imgKey = _keyFromUrl(imgUrl),
        subKey = _keyFromUrl(subUrl);

  final String imgKey;
  final String subKey;

  static const List<int> _mixinKeyEncTab = <int>[
    46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
    27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
    37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
    22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52,
  ];

  late final String _mixinKey = _buildMixinKey();

  String _buildMixinKey() {
    final raw = imgKey + subKey;
    if (raw.length < 64) {
      throw ArgumentError('Bilibili WBI key 长度不足: ${raw.length}');
    }
    final buf = StringBuffer();
    for (final i in _mixinKeyEncTab) {
      buf.write(raw[i]);
    }
    return buf.toString().substring(0, 32);
  }

  /// 返回带 `wts` / `w_rid` 的 query string（不含前导 `?`）。
  ///
  /// [wts] 可注入，方便单测；默认当前秒级时间戳。
  String sign(Map<String, Object?> params, {int? wts}) {
    final clean = <String, String>{};
    params.forEach((key, value) {
      clean[key] = value.toString().replaceAll(RegExp(r"[!'()*]"), '');
    });
    clean['wts'] =
        (wts ?? DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

    final keys = clean.keys.toList()..sort();
    final query = keys
        .map((k) =>
            '${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent(clean[k]!)}')
        .join('&');
    final wRid = md5.convert(utf8.encode('$query$_mixinKey')).toString();
    return '$query&w_rid=$wRid';
  }

  static String _keyFromUrl(String url) {
    final name = url.split('/').last;
    final dot = name.indexOf('.');
    return dot >= 0 ? name.substring(0, dot) : name;
  }
}
