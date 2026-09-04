import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/currency_formatter.dart';
import 'dashed_line.dart';

/// A label/value row with a dotted leader filling the gap — the core
/// "printed receipt" pattern (design.md §4), used for every price row.
class AmountRow extends StatelessWidget {
  const AmountRow({
    super.key,
    required this.label,
    required this.amount,
    this.emphasize = false,
    this.labelStyle,
    this.trailing,
  });

  final String label;
  final int amount;
  final bool emphasize;
  final TextStyle? labelStyle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final valueStyle = emphasize
        ? AppTypography.amount.copyWith(fontSize: 17, color: AppColors.accentTerracottaDark)
        : AppTypography.amount;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: labelStyle ??
                (emphasize ? AppTypography.label : AppTypography.bodySecondary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: DashedLine(dashWidth: 2, gapWidth: 3),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(CurrencyFormatter.format(amount), style: valueStyle),
          if (trailing != null) ...[const SizedBox(width: AppSpacing.xs), trailing!],
        ],
      ),
    );
  }
}
