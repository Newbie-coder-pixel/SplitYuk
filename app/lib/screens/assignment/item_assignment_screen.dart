import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/member_avatar.dart';
import '../../core/widgets/step_progress_bar.dart';
import '../../models/bill_item.dart';
import '../../models/member.dart';
import '../../state/session_controller.dart';
import '../split/split_summary_screen.dart';

/// FR-5.1: assign each item to one or more members. PRD §11 rule 1 blocks
/// proceeding while any item is unassigned.
class ItemAssignmentScreen extends StatefulWidget {
  const ItemAssignmentScreen({super.key});

  @override
  State<ItemAssignmentScreen> createState() => _ItemAssignmentScreenState();
}

class _ItemAssignmentScreenState extends State<ItemAssignmentScreen> {
  String? _activeItemId;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final bill = session.bill;
    final members = session.members;
    final items = bill.items;

    if (items.isEmpty) {
      return const AppScaffold(
        title: 'Receipt Workspace',
        body: Center(
          child: Text('No items to assign.', style: AppTypography.bodySecondary),
        ),
      );
    }

    _activeItemId ??= items.firstWhere(
      (i) => !i.isAssigned,
      orElse: () => items.first,
    ).id;

    final activeItem = items.firstWhere(
      (i) => i.id == _activeItemId,
      orElse: () => items.first,
    );

    final assignedCount = items.where((i) => i.isAssigned).length;
    final allAssigned = assignedCount == items.length && items.isNotEmpty;

    return AppScaffold(
      title: 'Receipt Workspace',
      bottomBar: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('$assignedCount of ${items.length} items assigned', style: AppTypography.bodySecondary),
              const Spacer(),
              Text(
                items.isEmpty ? '' : '${(assignedCount / items.length * 100).round()}%',
                style: AppTypography.label,
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgress(value: items.isEmpty ? 0 : assignedCount / items.length),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            label: allAssigned
                ? 'Continue to split summary'
                : 'Assign all items to continue (${items.length - assignedCount} left)',
            icon: allAssigned ? Icons.arrow_forward : null,
            onPressed: allAssigned
                ? () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SplitSummaryScreen()),
                    )
                : null,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Assign items to friends', style: AppTypography.sectionHeading),
                const SizedBox(height: 4),
                const Text(
                  'Tap an item, then pick who ordered it.',
                  style: AppTypography.bodySecondary,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = items[index];
                final isActive = item.id == _activeItemId;
                return _ItemRowTile(
                  item: item,
                  members: members,
                  isActive: isActive,
                  onTap: () => setState(() => _activeItemId = item.id),
                );
              },
            ),
          ),
          if (items.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: const BoxDecoration(
                color: AppColors.bgSurface,
                border: Border(top: BorderSide(color: AppColors.borderSubtle)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${activeItem.name} · ${CurrencyFormatter.format(activeItem.price)}',
                          style: AppTypography.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        onPressed: () => session.setItemAssignees(
                          activeItem.id,
                          members.map((m) => m.id).toSet(),
                        ),
                        child: const Text('Select all'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.sm,
                    children: members.asMap().entries.map((entry) {
                      final index = entry.key;
                      final member = entry.value;
                      final selected = activeItem.assignedMemberIds.contains(member.id);
                      return GestureDetector(
                        onTap: () => session.toggleItemAssignee(activeItem.id, member.id),
                        child: Column(
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Opacity(
                                  opacity: selected ? 1 : 0.35,
                                  child: MemberAvatar(
                                    name: member.name,
                                    colorIndex: index,
                                    radius: 22,
                                    selected: selected,
                                  ),
                                ),
                                Positioned(
                                  right: -2,
                                  top: -2,
                                  // Always present (rather than added/removed
                                  // from the Stack on toggle) to keep the
                                  // Stack's child list stable across
                                  // rebuilds — conditionally-present
                                  // Positioned children have triggered a
                                  // Flutter framework semantics assertion
                                  // here in testing.
                                  child: Visibility(
                                    visible: selected,
                                    maintainState: true,
                                    maintainAnimation: true,
                                    maintainSize: true,
                                    child: const CircleAvatar(
                                      radius: 8,
                                      backgroundColor: AppColors.accentViolet,
                                      child: Icon(Icons.check, size: 10, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              width: 56,
                              child: Text(
                                member.name.split(' ').first,
                                textAlign: TextAlign.center,
                                style: AppTypography.bodySecondary,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ItemRowTile extends StatelessWidget {
  const _ItemRowTile({
    required this.item,
    required this.members,
    required this.isActive,
    required this.onTap,
  });

  final BillItem item;
  final List<Member> members;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: isActive ? AppColors.bgAmber.withValues(alpha: 0.4) : null,
          borderRadius: BorderRadius.circular(AppRadius.small),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: AppSpacing.sm),
              decoration: BoxDecoration(
                color: item.isAssigned ? AppColors.accentTerracotta : AppColors.textSecondary,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(child: Text(item.name, style: AppTypography.body)),
            if (!item.isAssigned)
              const Padding(
                padding: EdgeInsets.only(right: AppSpacing.sm),
                child: _UnassignedBadge(),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: _AssigneesPreview(item: item, members: members),
              ),
            Text(CurrencyFormatter.format(item.price), style: AppTypography.amount),
          ],
        ),
      ),
    );
  }
}

class _UnassignedBadge extends StatelessWidget {
  const _UnassignedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.bgInput,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: const Text(
        'Unassigned',
        style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _AssigneesPreview extends StatelessWidget {
  const _AssigneesPreview({required this.item, required this.members});

  final BillItem item;
  final List<Member> members;

  @override
  Widget build(BuildContext context) {
    final assigned = members.where((m) => item.assignedMemberIds.contains(m.id)).toList();
    final shown = assigned.length.clamp(0, 3);
    return SizedBox(
      // A Stack of only Positioned children needs a bounded width from its
      // parent, and this sits in a Row that otherwise gives it none.
      width: shown == 0 ? 0 : 24.0 + (shown - 1) * 16.0,
      height: 24,
      child: Stack(
        children: [
          for (var i = 0; i < assigned.length && i < 3; i++)
            Positioned(
              left: i * 16.0,
              child: MemberAvatar(
                name: assigned[i].name,
                colorIndex: members.indexOf(assigned[i]),
                radius: 12,
              ),
            ),
        ],
      ),
    );
  }
}
