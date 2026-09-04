import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/member_avatar.dart';
import '../../core/widgets/receipt_card.dart';
import '../../core/widgets/stamp_badge.dart';
import '../../core/widgets/step_progress_bar.dart';
import '../../models/member.dart';
import '../../services/notification_service.dart';
import '../../state/session_controller.dart';
import '../intro/intro_screen.dart';

/// FR-8.1-8.3: mark members paid/unpaid for this session only, resend
/// reminders, and export a record before the session (and everything in
/// it) is discarded for good.
class PaymentStatusScreen extends StatefulWidget {
  const PaymentStatusScreen({super.key});

  @override
  State<PaymentStatusScreen> createState() => _PaymentStatusScreenState();
}

class _PaymentStatusScreenState extends State<PaymentStatusScreen> {
  final NotificationService _notificationService = NotificationService(
    relayBaseUrl: const String.fromEnvironment('SPLITYUK_RELAY_URL'),
  );
  final Set<String> _resending = {};

  Future<void> _resend(SessionController session, Member member) async {
    final channel = NotificationService.resolveChannel(member, NotificationChannel.whatsapp);
    if (channel == null) return;
    setState(() => _resending.add(member.id));
    final result = session.computeSplit();
    final amount = result?.perMember[member.id]?.total ?? 0;
    final outcome = await _notificationService.send(
      member: member,
      channel: channel,
      billTitle: session.bill.title.isEmpty ? 'SplitYuk bill' : session.bill.title,
      amountDue: amount,
      attachmentImagePath: session.bill.attachmentImagePath,
    );
    if (!mounted) return;
    setState(() => _resending.remove(member.id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          outcome.success
              ? 'Reminder resent to ${member.name}.'
              : (outcome.error ?? 'Could not resend to ${member.name}.'),
        ),
      ),
    );
  }

  void _shareSummary(SessionController session) {
    final result = session.computeSplit();
    final bill = session.bill;
    final buffer = StringBuffer()
      ..writeln(bill.title.isEmpty ? 'SplitYuk bill' : bill.title)
      ..writeln('Total: ${CurrencyFormatter.format(bill.total)}')
      ..writeln();
    for (final m in session.members) {
      final amount = result?.perMember[m.id]?.total ?? 0;
      buffer.writeln('${m.name}: ${CurrencyFormatter.format(amount)} ${m.isPaid ? '(paid)' : '(unpaid)'}');
    }

    final attachment = bill.attachmentImagePath;
    if (attachment != null) {
      SharePlus.instance.share(
        ShareParams(text: buffer.toString(), files: [XFile(attachment)]),
      );
    } else {
      SharePlus.instance.share(ShareParams(text: buffer.toString()));
    }
  }

  Future<void> _closeSession(SessionController session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close this bill\'s session?'),
        content: const Text(
          'Everything about this bill — items, members, and amounts — will be '
          'cleared from this device\'s memory. This can\'t be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Close session', style: TextStyle(color: AppColors.accentDanger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await session.closeSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const IntroScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final bill = session.bill;
    final members = session.members;
    final result = session.computeSplit();

    final paidCount = members.where((m) => m.isPaid).length;
    final paidAmount = members
        .where((m) => m.isPaid)
        .fold<int>(0, (sum, m) => sum + (result?.perMember[m.id]?.total ?? 0));
    final progress = members.isEmpty ? 0.0 : paidCount / members.length;

    return AppScaffold(
      title: 'Receipt Workspace',
      showBackButton: false,
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          ReceiptCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.receipt_long_outlined, color: AppColors.accentViolet),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        bill.title.isEmpty ? 'Untitled bill' : bill.title,
                        style: AppTypography.sectionHeading,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                const Text('PAYMENT STATUS', style: AppTypography.eyebrow),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$paidCount of ${members.length} paid',
                      style: AppTypography.label,
                    ),
                    const Spacer(),
                    Text(
                      '${(progress * 100).round()}%',
                      style: AppTypography.amountLarge.copyWith(fontSize: 20),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${CurrencyFormatter.format(paidAmount)} of ${CurrencyFormatter.format(bill.total)} collected',
                  style: AppTypography.bodySecondary,
                ),
                const SizedBox(height: AppSpacing.sm),
                LinearProgress(value: progress, color: AppColors.accentViolet),
                if (progress == 1.0 && members.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  const Center(child: StampBadge(text: 'ALL SETTLED')),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text('MEMBERS', style: AppTypography.eyebrow),
          const SizedBox(height: AppSpacing.sm),
          ...members.asMap().entries.map((entry) {
            final index = entry.key;
            final member = entry.value;
            final amount = result?.perMember[member.id]?.total ?? 0;
            return _MemberStatusRow(
              member: member,
              colorIndex: index,
              amount: amount,
              isResending: _resending.contains(member.id),
              onTogglePaid: () => session.setMemberPaid(member.id, !member.isPaid),
              onResend: () => _resend(session, member),
            );
          }),
          const SizedBox(height: AppSpacing.xl),
          OutlinedButton.icon(
            onPressed: () => _shareSummary(session),
            icon: const Icon(Icons.ios_share_outlined),
            label: const Text('Share summary'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              side: const BorderSide(color: AppColors.borderSubtle),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton(
            onPressed: () => _closeSession(session),
            child: const Text(
              'Close this bill\'s session',
              style: TextStyle(color: AppColors.accentDanger, fontWeight: FontWeight.w600),
            ),
          ),
          const Text(
            'The session will be cleared automatically from this device\'s memory.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySecondary,
          ),
        ],
      ),
    );
  }
}

class _MemberStatusRow extends StatelessWidget {
  const _MemberStatusRow({
    required this.member,
    required this.colorIndex,
    required this.amount,
    required this.isResending,
    required this.onTogglePaid,
    required this.onResend,
  });

  final Member member;
  final int colorIndex;
  final int amount;
  final bool isResending;
  final VoidCallback onTogglePaid;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          MemberAvatar(name: member.name, colorIndex: colorIndex, radius: 18),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.name, style: AppTypography.label),
                Text(CurrencyFormatter.format(amount), style: AppTypography.bodySecondary),
              ],
            ),
          ),
          if (member.isPaid)
            const StampBadge(text: 'PAID', angle: -0.1, color: AppColors.accentSuccess)
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: onTogglePaid,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('Mark as paid', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(height: 2),
                if (isResending)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  GestureDetector(
                    onTap: onResend,
                    child: const Text(
                      'Resend reminder',
                      style: TextStyle(fontSize: 11, color: AppColors.accentTerracottaDark),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
