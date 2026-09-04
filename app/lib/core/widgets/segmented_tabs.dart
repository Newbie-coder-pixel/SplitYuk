import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

class SegmentedTabItem {
  const SegmentedTabItem({required this.label, this.icon});
  final String label;
  final IconData? icon;
}

/// A full-width row of equal segments with one active tab (design.md §5),
/// used for split-mode selectors and the notification channel picker.
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<SegmentedTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.bgInput,
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: Row(
        children: List.generate(items.length, (index) {
          final active = index == selectedIndex;
          final item = items[index];
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelected(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: active ? AppColors.accentTerracotta : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (item.icon != null) ...[
                      Icon(
                        item.icon,
                        size: 15,
                        color: active ? AppColors.textOnAccent : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      item.label,
                      style: AppTypography.label.copyWith(
                        fontSize: 13,
                        color: active ? AppColors.textOnAccent : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
