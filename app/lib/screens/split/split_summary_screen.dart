import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/amount_row.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/dashed_line.dart';
import '../../core/widgets/member_avatar.dart';
import '../../core/widgets/receipt_card.dart';
import '../../core/widgets/segmented_tabs.dart';
import '../../core/widgets/stamp_badge.dart';
import '../../logic/split_result.dart';
import '../../models/member.dart';
import '../../models/split_mode.dart';
import '../../state/session_controller.dart';
import '../send/send_notification_screen.dart';

/// FR-5.3/FR-5.4: pick a split mode (item-based bills also let you switch
/// to a quick mode), configure it, and preview each member's exact share
/// before continuing.
class SplitSummaryScreen extends StatefulWidget {
  const SplitSummaryScreen({super.key});

  @override
  State<SplitSummaryScreen> createState() => _SplitSummaryScreenState();
}

class _SplitSummaryScreenState extends State<SplitSummaryScreen> {
  final Map<String, TextEditingController> _percentControllers = {};
  final Map<String, TextEditingController> _amountControllers = {};

  TextEditingController _percentControllerFor(Member m, SessionController session) {
    return _percentControllers.putIfAbsent(m.id, () {
      final existing = session.bill.percentageShares[m.id];
      return TextEditingController(text: existing == null ? '' : existing.toStringAsFixed(0));
    });
  }

  TextEditingController _amountControllerFor(Member m, SessionController session) {
    return _amountControllers.putIfAbsent(m.id, () {
      final existing = session.bill.customAmounts[m.id];
      return TextEditingController(text: existing == null ? '' : existing.toString());
    });
  }

  @override
  void dispose() {
    for (final c in _percentControllers.values) {
      c.dispose();
    }
    for (final c in _amountControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final bill = session.bill;
    final members = session.members;
    final errors = session.validationErrors;
    final result = session.computeSplit();

    final tabs = <SegmentedTabItem>[
      if (bill.isItemized) const SegmentedTabItem(label: 'By item'),
      const SegmentedTabItem(label: 'Equal'),
      const SegmentedTabItem(label: 'Percent'),
      const SegmentedTabItem(label: 'Custom'),
    ];
    final modeOrder = [
      if (bill.isItemized) SplitMode.itemized,
      SplitMode.equal,
      SplitMode.percentage,
      SplitMode.customAmount,
    ];
    final selectedIndex = modeOrder.indexOf(bill.splitMode).clamp(0, modeOrder.length - 1);

    return AppScaffold(
      title: 'Receipt Workspace',
      bottomBar: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (errors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                errors.first,
                style: const TextStyle(color: AppColors.accentDanger, fontSize: 12),
              ),
            ),
          PrimaryButton(
            label: 'Continue to review & send',
            icon: Icons.arrow_forward,
            onPressed: result == null
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SendNotificationScreen()),
                    ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          SegmentedTabs(
            items: tabs,
            selectedIndex: selectedIndex,
            onSelected: (i) => session.setSplitMode(modeOrder[i]),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (bill.splitMode == SplitMode.percentage) _buildPercentageInputs(session, members),
          if (bill.splitMode == SplitMode.customAmount) _buildCustomAmountInputs(session, members),
          if (bill.splitMode == SplitMode.percentage || bill.splitMode == SplitMode.customAmount)
            const SizedBox(height: AppSpacing.lg),
          ReceiptCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('SPLIT SUMMARY', style: AppTypography.eyebrow),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  bill.title.isEmpty ? 'Untitled bill' : bill.title,
                  style: AppTypography.sectionHeading,
                ),
                const SizedBox(height: AppSpacing.md),
                const DashedLine(),
                const SizedBox(height: AppSpacing.md),
                if (result == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: Text(
                      errors.isEmpty ? 'Add members to see the split.' : errors.join(' '),
                      style: AppTypography.bodySecondary,
                    ),
                  )
                else
                  ...members.asMap().entries.map(
                        (entry) => _MemberShareTile(
                          member: entry.value,
                          colorIndex: entry.key,
                          share: result.perMember[entry.value.id],
                        ),
                      ),
                const SizedBox(height: AppSpacing.sm),
                const DashedLine(),
                const SizedBox(height: AppSpacing.sm),
                if (bill.taxAmount > 0)
                  AmountRow(label: 'Tax (${bill.taxPercent.toStringAsFixed(0)}%)', amount: bill.taxAmount),
                if (bill.serviceAmount > 0)
                  AmountRow(
                    label: 'Service (${bill.servicePercent.toStringAsFixed(0)}%)',
                    amount: bill.serviceAmount,
                  ),
                if (bill.discountAmount > 0)
                  AmountRow(label: 'Discount', amount: -bill.discountAmount),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.bgInput,
                    borderRadius: BorderRadius.circular(AppRadius.small),
                  ),
                  child: Row(
                    children: [
                      const Text('FINAL TOTAL', style: AppTypography.label),
                      const Spacer(),
                      Text(
                        CurrencyFormatter.format(bill.total),
                        style: AppTypography.amountLarge.copyWith(fontSize: 22),
                      ),
                      if (result != null && result.reconciles) ...[
                        const SizedBox(width: AppSpacing.sm),
                        const StampBadge(text: 'TALLY OK', angle: -0.12),
                      ],
                    ],
                  ),
                ),
                if (bill.isItemized) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    bill.splitExtrasEqually
                        ? 'Tax & service are split equally across everyone.'
                        : 'Tax & service are split proportionally to what each person ordered.',
                    style: AppTypography.bodySecondary,
                  ),
                ],
                const SizedBox(height: 2),
                const Text(
                  'Any rounding difference is added to the bill creator\'s share, '
                  'so the total always matches exactly.',
                  style: AppTypography.bodySecondary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPercentageInputs(SessionController session, List<Member> members) {
    final sum = members.fold<double>(0, (t, m) => t + (session.bill.percentageShares[m.id] ?? 0));
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final m in members)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(m.name, style: AppTypography.body)),
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: _percentControllerFor(m, session),
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(suffixText: '%', isDense: true),
                      onChanged: (v) => session.setPercentageShare(m.id, double.tryParse(v) ?? 0),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Total: ${sum.toStringAsFixed(1)}% (must equal 100%)',
            style: TextStyle(
              fontSize: 12,
              color: (sum - 100).abs() < 0.01 ? AppColors.accentSuccess : AppColors.textAmber,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomAmountInputs(SessionController session, List<Member> members) {
    final sum = members.fold<int>(0, (t, m) => t + (session.bill.customAmounts[m.id] ?? 0));
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final m in members)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(m.name, style: AppTypography.body)),
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: _amountControllerFor(m, session),
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(prefixText: 'Rp ', isDense: true),
                      onChanged: (v) => session.setCustomAmount(m.id, int.tryParse(v) ?? 0),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Total: ${CurrencyFormatter.format(sum)} of ${CurrencyFormatter.format(session.bill.total)}',
            style: TextStyle(
              fontSize: 12,
              color: sum == session.bill.total ? AppColors.accentSuccess : AppColors.textAmber,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberShareTile extends StatelessWidget {
  const _MemberShareTile({required this.member, required this.colorIndex, required this.share});

  final Member member;
  final int colorIndex;
  final MemberShare? share;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          MemberAvatar(name: member.name, colorIndex: colorIndex, radius: 16),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.isCreator ? '${member.name} · Creator' : member.name,
                  style: AppTypography.label,
                ),
              ],
            ),
          ),
          Text(
            CurrencyFormatter.format(share?.total ?? 0),
            style: AppTypography.amount.copyWith(fontSize: 16),
          ),
        ],
      ),
    );
  }
}
