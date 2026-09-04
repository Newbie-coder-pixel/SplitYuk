import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Segmented step progress, e.g. "Step 2 of 4" (design.md §5).
class StepProgressBar extends StatelessWidget {
  const StepProgressBar({super.key, required this.currentStep, required this.totalSteps});

  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(totalSteps, (index) {
        final filled = index < currentStep;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: index == totalSteps - 1 ? 0 : AppSpacing.xs),
            height: 5,
            decoration: BoxDecoration(
              color: filled ? AppColors.accentTerracotta : AppColors.bgInput,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
        );
      }),
    );
  }
}

/// A single thick rounded progress bar for completion/payment status.
class LinearProgress extends StatelessWidget {
  const LinearProgress({
    super.key,
    required this.value,
    this.color = AppColors.accentTerracotta,
  });

  /// 0.0 - 1.0
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: 10,
        backgroundColor: AppColors.bgInput,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}
