import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// A rounded-full chip used for category filters and status pills
/// (design.md §5).
class PillChip extends StatelessWidget {
  const PillChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
    this.selectedColor = AppColors.accentTerracotta,
    this.backgroundColor,
    this.textColor,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color selectedColor;
  final Color? backgroundColor;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? (selected ? selectedColor : AppColors.bgInput);
    final fg = textColor ??
        (selected ? AppColors.textOnAccent : AppColors.textPrimary);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: AppTypography.label.copyWith(color: fg, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
