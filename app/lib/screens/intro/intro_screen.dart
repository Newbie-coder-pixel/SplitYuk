import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/dashed_line.dart';
import '../../core/widgets/stamp_badge.dart';
import '../../state/session_controller.dart';
import '../create/choose_input_screen.dart';

/// The very first screen — no login, and a repeated, in-context privacy
/// promise rather than a one-time disclaimer (design.md §1).
class IntroScreen extends StatelessWidget {
  const IntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Receipt Workspace', style: AppTypography.screenTitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.bgCardOuter,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: AppColors.bgPaper,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'TEMPORARY SLIP',
                            style: AppTypography.eyebrow,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          const Text('SPLITYUK', style: AppTypography.heroTitle),
                          const SizedBox(height: AppSpacing.xs),
                          const Text(
                            'EVEN SPLIT PROOF // TRANSIENT SESSION',
                            style: AppTypography.eyebrow,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'No. REG-0001 · JAKARTA · STATISTIC-FREE',
                            style: AppTypography.bodySecondary.copyWith(fontFamily: AppTypography.monoFamily),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          const DashedLine(),
                          const SizedBox(height: AppSpacing.lg),
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              Opacity(
                                opacity: 0.35,
                                child: Text(
                                  'This app never saves your bills, contacts, or '
                                  'payment info anywhere. Everything lives only on '
                                  'this screen for right now, disappearing the '
                                  'moment you close it.',
                                  textAlign: TextAlign.center,
                                  style: AppTypography.body,
                                ),
                              ),
                              const StampBadge(text: '100% LOCAL & PRIVATE'),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.shield_outlined, color: AppColors.accentMaroon),
                              SizedBox(width: AppSpacing.sm),
                              Text('Permissions we may ask for', style: AppTypography.label),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          const _PermissionLine(
                            icon: Icons.camera_alt_outlined,
                            title: 'Camera: ',
                            body: 'only to scan a physical receipt, on-device.',
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          const _PermissionLine(
                            icon: Icons.contacts_outlined,
                            title: 'Contacts: ',
                            body: 'to pick who\'s splitting this bill, without typing numbers by hand.',
                          ),
                          const SizedBox(height: AppSpacing.md),
                          const Text(
                            'Both are optional and only asked for when you need them.',
                            style: AppTypography.bodySecondary,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: 'Start splitting a bill',
                icon: Icons.arrow_forward,
                onPressed: () {
                  context.read<SessionController>().resetSession();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ChooseInputScreen()),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'No account. No history stored.',
                textAlign: TextAlign.center,
                style: AppTypography.bodySecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionLine extends StatelessWidget {
  const _PermissionLine({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.accentViolet),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: AppTypography.body,
              children: [
                TextSpan(text: title, style: AppTypography.label),
                TextSpan(text: body),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
