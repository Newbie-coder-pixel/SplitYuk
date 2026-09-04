import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// The rotated rubber-stamp confirmation mark (design.md §4). Always a
/// positive/neutral confirmation ("CHECK OK", "TALLY OK", "LUNAS") — never
/// used for warnings or errors.
class StampBadge extends StatelessWidget {
  const StampBadge({
    super.key,
    required this.text,
    this.angle = -0.18,
    this.color = AppColors.accentViolet,
  });

  final String text;
  final double angle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 1.6),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: AppTypography.stamp.copyWith(color: color),
        ),
      ),
    );
  }
}
