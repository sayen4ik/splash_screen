import 'package:flutter/material.dart';

/// Classic transparency-preview checkerboard, so it's obvious the cloud PNG's
/// alpha channel (not a white background) is being used.
class CheckerboardPainter extends CustomPainter {
  const CheckerboardPainter({this.cellSize = 16});

  final double cellSize;

  static const _light = Color(0xFF3A3A44);
  static const _dark = Color(0xFF2A2A32);

  @override
  void paint(Canvas canvas, Size size) {
    final paintLight = Paint()..color = _light;
    final paintDark = Paint()..color = _dark;
    canvas.drawRect(Offset.zero & size, paintDark);

    final cols = (size.width / cellSize).ceil();
    final rows = (size.height / cellSize).ceil();
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        if ((row + col).isEven) continue;
        canvas.drawRect(
          Rect.fromLTWH(col * cellSize, row * cellSize, cellSize, cellSize),
          paintLight,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CheckerboardPainter oldDelegate) =>
      oldDelegate.cellSize != cellSize;
}
