import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Standard screen chrome: the "Receipt Workspace" app bar (back button,
/// mono screen title, and a privacy-notice affordance in place of the
/// profile icon the mockups show — this app has no accounts, per FR-1.1,
/// so that corner is repurposed for something actually in scope) plus an
/// optional pinned bottom action bar for the multi-step flows.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.bottomBar,
    this.showBackButton = true,
  });

  final String title;
  final Widget body;
  final Widget? bottomBar;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: showBackButton,
        title: Text(title, style: AppTypography.screenTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            child: GestureDetector(
              onTap: () => _showPrivacySheet(context),
              child: const CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.accentMaroon,
                child: Icon(Icons.shield_outlined, size: 16, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(child: body),
      bottomNavigationBar: bottomBar == null
          ? null
          : Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              decoration: const BoxDecoration(
                color: AppColors.bgApp,
                border: Border(top: BorderSide(color: AppColors.borderSubtle)),
              ),
              child: SafeArea(top: false, child: bottomBar!),
            ),
    );
  }

  static void _showPrivacySheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shield_outlined, color: AppColors.accentViolet),
                const SizedBox(width: AppSpacing.sm),
                Text('100% local & private', style: AppTypography.sectionHeading),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'SplitYuk never saves your bills, contacts, receipt photos, or '
              'payment info anywhere. Everything lives only in memory for this '
              'session, and disappears the moment you close the app.\n\n'
              'No account, no login, no bill history, no server-side database.',
              style: AppTypography.body,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}
