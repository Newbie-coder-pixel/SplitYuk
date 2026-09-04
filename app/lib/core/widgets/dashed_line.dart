import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// A horizontal dashed rule — the "receipt perforation" motif used between
/// line items and as section dividers throughout the app (design.md §4).
class DashedLine extends StatelessWidget {
  const DashedLine({
    super.key,
    this.color = AppColors.dividerDashed,
    this.thickness = 1.2,
    this.dashWidth = 5,
    this.gapWidth = 4,
  });

  final Color color;
  final double thickness;
  final double dashWidth;
  final double gapWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: thickness,
      width: double.infinity,
      child: CustomPaint(
        painter: _DashedLinePainter(
          color: color,
          thickness: thickness,
          dashWidth: dashWidth,
          gapWidth: gapWidth,
        ),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter({
    required this.color,
    required this.thickness,
    required this.dashWidth,
    required this.gapWidth,
  });

  final Color color;
  final double thickness;
  final double dashWidth;
  final double gapWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness;
    final step = dashWidth + gapWidth;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset((x + dashWidth).clamp(0, size.width), size.height / 2),
        paint,
      );
      x += step;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.thickness != thickness;
}
