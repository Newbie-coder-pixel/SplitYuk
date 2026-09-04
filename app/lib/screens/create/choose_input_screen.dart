import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_scaffold.dart';
import '../scan/scan_receipt_screen.dart';
import 'manual_entry_screen.dart';

/// PRD §8 node B: "Choose Input Method" — scan a receipt or enter it
/// manually.
class ChooseInputScreen extends StatelessWidget {
  const ChooseInputScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Receipt Workspace',
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('How do you want to start?', style: AppTypography.sectionHeading),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Scan a physical receipt and let on-device OCR read it, or enter '
              'items and totals yourself.',
              style: AppTypography.bodySecondary,
            ),
            const SizedBox(height: AppSpacing.xl),
            _InputOptionCard(
              icon: Icons.document_scanner_outlined,
              title: 'Scan a receipt',
              subtitle: 'Camera or gallery photo, read on-device — never uploaded.',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ScanReceiptScreen()),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _InputOptionCard(
              icon: Icons.edit_note_outlined,
              title: 'Enter it manually',
              subtitle: 'Type items line-by-line, or just enter a total.',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ManualEntryScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputOptionCard extends StatelessWidget {
  const _InputOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgSurface,
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.accentTerracotta.withValues(alpha: 0.15),
                child: Icon(icon, color: AppColors.accentTerracottaDark),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTypography.label.copyWith(fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppTypography.bodySecondary),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
