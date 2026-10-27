import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 站点覆盖状态。数据由 `tools/generate_site_coverage.py` 生成。
enum SiteCoverageStatus {
  native('原生插件'),
  nativePartial('原生插件（部分）'),
  ytdlp('yt-dlp（待验证）'),
  generic('通用资源检测（未复刻）'),
  drm('DRM（不支持）');

  const SiteCoverageStatus(this.label);

  final String label;

  static SiteCoverageStatus parse(String value) {
    return switch (value) {
      'native' => SiteCoverageStatus.native,
      'native_partial' => SiteCoverageStatus.nativePartial,
      'ytdlp' => SiteCoverageStatus.ytdlp,
      'drm' => SiteCoverageStatus.drm,
      _ => SiteCoverageStatus.generic,
    };
  }
}

class SiteCoverageEntry {
  final String site;
  final String className;
  final List<String> domains;
  final SiteCoverageStatus status;
  final bool verified;
  final String priority;
  final List<String> ytdlpExtractors;
  final String notes;

  const SiteCoverageEntry({
    required this.site,
    required this.className,
    required this.domains,
    required this.status,
    required this.verified,
    required this.priority,
    required this.ytdlpExtractors,
    required this.notes,
  });

  factory SiteCoverageEntry.fromJson(Map<String, dynamic> json) {
    return SiteCoverageEntry(
      site: json['site']?.toString() ?? '',
      className: json['className']?.toString() ?? '',
      domains: (json['domains'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      status: SiteCoverageStatus.parse(json['status']?.toString() ?? ''),
      verified: json['verified'] == true,
      priority: json['priority']?.toString() ?? 'P1',
      ytdlpExtractors: (json['ytdlpExtractors'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      notes: json['notes']?.toString() ?? '',
    );
  }

  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return site.toLowerCase().contains(q) ||
        className.toLowerCase().contains(q) ||
        domains.any((d) => d.toLowerCase().contains(q)) ||
        ytdlpExtractors.any((e) => e.toLowerCase().contains(q));
  }
}

class SiteCoverageData {
  final int total;
  final Map<SiteCoverageStatus, int> counts;
  final List<SiteCoverageEntry> sites;

  const SiteCoverageData({
    required this.total,
    required this.counts,
    required this.sites,
  });

  factory SiteCoverageData.fromJson(Map<String, dynamic> json) {
    final rawCounts = (json['counts'] as Map?) ?? const {};
    String keyFor(SiteCoverageStatus status) =>
        status == SiteCoverageStatus.nativePartial
            ? 'native_partial'
            : status.name;
    final counts = <SiteCoverageStatus, int>{
      for (final status in SiteCoverageStatus.values)
        status: (rawCounts[keyFor(status)] as num?)?.toInt() ?? 0,
    };
    final sites = (json['sites'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => SiteCoverageEntry.fromJson(
              Map<String, dynamic>.from(e),
            ))
        .toList(growable: false);
    return SiteCoverageData(
      total: (json['total'] as num?)?.toInt() ?? sites.length,
      counts: counts,
      sites: sites,
    );
  }
}

/// 站点覆盖数据（应用内「设置 → 支持站点」）。
final siteCoverageProvider = FutureProvider<SiteCoverageData>((ref) async {
  final raw = await rootBundle.loadString('assets/site_coverage.json');
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw const FormatException('site_coverage.json 格式错误');
  }
  return SiteCoverageData.fromJson(Map<String, dynamic>.from(decoded));
});
