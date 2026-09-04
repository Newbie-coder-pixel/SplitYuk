import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Primary, full-width CTA with the hard offset "stamped" shadow used
/// consistently across every forward-progressing action (design.md §5).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = AppColors.accentTerracotta,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        boxShadow: disabled
            ? null
            : [
                BoxShadow(
                  color: AppColors.textPrimary.withValues(alpha: 0.55),
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Material(
        color: disabled ? AppColors.borderSubtle : color,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md + 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: AppTypography.buttonLabel.copyWith(
                    color: disabled ? AppColors.textSecondary : AppColors.textOnAccent,
                  ),
                ),
                if (icon != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Icon(
                    icon,
                    size: 18,
                    color: disabled ? AppColors.textSecondary : AppColors.textOnAccent,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary, lower-emphasis full-width action.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgInput,
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: AppColors.textPrimary),
                const SizedBox(width: AppSpacing.sm),
              ],
              Text(
                label,
                style: AppTypography.label.copyWith(color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dashed-outline button for "add another" style actions — signals that
/// it expands the form rather than advancing the flow (design.md §5).
class DashedOutlineButton extends StatelessWidget {
  const DashedOutlineButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.add,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        onTap: onPressed,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.medium),
            border: Border.all(
              color: AppColors.textSecondary.withValues(alpha: 0.5),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: AppTypography.label.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
