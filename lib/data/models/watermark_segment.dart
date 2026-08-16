import 'package:flutter/foundation.dart';

/// 一个水印段：在 [time] 秒时水印出现在该归一化位置，直到下一段（或视频结束）
@immutable
class WatermarkSegment {
  /// 该水印开始出现的秒数
  final double time;

  /// 归一化坐标（0.0~1.0，相对视频宽高）
  final double x;
  final double y;
  final double w;
  final double h;

  const WatermarkSegment({
    required this.time,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  /// 时间点可读文本 "M:SS"
  String get timeLabel {
    final m = time ~/ 60;
    final s = (time % 60).round();
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// 位置可读文本（百分比）
  String get posLabel =>
      '(${(x * 100).round()}%, ${(y * 100).round()}%) ${(w * 100).round()}%×${(h * 100).round()}%';
}
