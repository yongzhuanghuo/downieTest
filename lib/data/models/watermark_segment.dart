import 'package:flutter/foundation.dart';

/// 一个水印段：在 [startTime, endTime] 时间段内，水印出现在该归一化位置。
/// 同一时刻允许存在多个水印段，各段相互独立。
@immutable
class WatermarkSegment {
  /// 该水印开始出现的秒数
  final double startTime;

  /// 该水印结束（消失）的秒数
  final double endTime;

  /// 归一化坐标（0.0~1.0，相对视频宽高）
  final double x;
  final double y;
  final double w;
  final double h;

  const WatermarkSegment({
    required this.startTime,
    required this.endTime,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  /// 是否在 [t] 秒时刻生效
  bool activeAt(double t) => t >= startTime && t <= endTime;

  /// 时间段可读文本 "M:SS - M:SS"
  String get timeLabel => '${_fmt(startTime)} - ${_fmt(endTime)}';

  /// 位置可读文本（百分比）
  String get posLabel =>
      '(${(x * 100).round()}%, ${(y * 100).round()}%) ${(w * 100).round()}%×${(h * 100).round()}%';

  static String _fmt(double t) {
    final m = t ~/ 60;
    final s = (t % 60).round();
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
