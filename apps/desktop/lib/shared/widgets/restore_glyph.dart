import 'package:flutter/material.dart';

/// Windows 风格「还原」图标：两个错开的方框。
///
/// 自绘而不是用 Material 图标，避免 release 构建裁剪图标字体后出现空白。
class RestoreGlyph extends StatelessWidget {
  final Color color;
  final double size;

  const RestoreGlyph({super.key, required this.color, this.size = 11});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _RestoreGlyphPainter(color),
    );
  }
}

class _RestoreGlyphPainter extends CustomPainter {
  final Color color;

  _RestoreGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 11.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 * scale;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0.5 * scale, 0.5 * scale, 7.5 * scale, 7.5 * scale),
        Radius.circular(1.2 * scale),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(3.0 * scale, 3.0 * scale, 7.5 * scale, 7.5 * scale),
        Radius.circular(1.2 * scale),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_RestoreGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}
