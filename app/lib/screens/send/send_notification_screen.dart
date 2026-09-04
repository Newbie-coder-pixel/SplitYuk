import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/amount_row.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/dashed_line.dart';
import '../../core/widgets/receipt_card.dart';
import '../../core/widgets/segmented_tabs.dart';
import '../../core/widgets/stamp_badge.dart';
import '../../logic/split_result.dart';
import '../../models/bill.dart';
import '../../models/member.dart';
import '../../services/image_render_service.dart';
import '../../services/notification_service.dart';
import '../../state/session_controller.dart';
import '../status/payment_status_screen.dart';

/// FR-7.1/FR-7.2: send each member their amount owed, with the receipt
/// photo or rendered summary attached. No payment-destination information
/// is ever included here — that was deliberately removed from scope
/// (PRD §6/§9.6); see design.md §8 for why an earlier mockup draft that
/// showed one was not implemented.
class SendNotificationScreen extends StatefulWidget {
  const SendNotificationScreen({super.key});

  @override
  State<SendNotificationScreen> createState() => _SendNotificationScreenState();
}

class _SendNotificationScreenState extends State<SendNotificationScreen> {
  final GlobalKey _previewKey = GlobalKey();
  final ImageRenderService _imageRenderService = ImageRenderService();
  final NotificationService _notificationService = NotificationService(
    relayBaseUrl: const String.fromEnvironment('SPLITYUK_RELAY_URL'),
  );

  NotificationChannel _preferredChannel = NotificationChannel.whatsapp;
  bool _isSending = false;
  Map<String, NotifyOutcome> _outcomes = {};

  NotificationChannel? _effectiveChannelFor(Member member) =>
      NotificationService.resolveChannel(member, _preferredChannel);

  Future<void> _send(SessionController session) async {
    setState(() => _isSending = true);

    String? attachmentPath = session.bill.attachmentImagePath;
    if (attachmentPath == null) {
      try {
        attachmentPath = await _imageRenderService.captureToFile(
          _previewKey,
          'splityuk_summary_${DateTime.now().millisecondsSinceEpoch}',
        );
        session.bill.renderedSummaryImagePath = attachmentPath;
      } catch (_) {
        // Rendering the summary image is best-effort; sending can still
        // proceed with a text-only message if it fails.
      }
    }

    final result = session.computeSplit();
    final outcomes = <String, NotifyOutcome>{};

    for (final member in session.members) {
      final channel = _effectiveChannelFor(member);
      if (channel == null) {
        outcomes[member.id] = NotifyOutcome(
          memberId: member.id,
          success: false,
          error: 'Not reachable automatically — share the summary with them directly.',
        );
        continue;
      }
      final amount = result?.perMember[member.id]?.total ?? 0;
      outcomes[member.id] = await _notificationService.send(
        member: member,
        channel: channel,
        billTitle: session.bill.title.isEmpty ? 'SplitYuk bill' : session.bill.title,
        amountDue: amount,
        attachmentImagePath: attachmentPath,
      );
    }

    if (!mounted) return;
    setState(() {
      _outcomes = outcomes;
      _isSending = false;
    });

    session.markNotificationsSent();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PaymentStatusScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final bill = session.bill;
    final members = session.members;
    final result = session.computeSplit();
    final relayConnected = _notificationService.isConfigured;

    return AppScaffold(
      title: 'Receipt Workspace',
      bottomBar: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PrimaryButton(
            label: _isSending ? 'Sending…' : 'Send to ${members.length} people',
            icon: _isSending ? null : Icons.send_outlined,
            onPressed: (result == null || _isSending) ? null : () => _send(session),
          ),
          const SizedBox(height: 6),
          const Text(
            'Messages open directly to each contact — no new numbers are saved.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySecondary,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (bill.hasUnsentChanges)
            _Banner(
              color: AppColors.bgAmber,
              textColor: AppColors.textAmber,
              icon: Icons.history_toggle_off,
              text: 'This bill changed since it was last sent — sending again will '
                  'update everyone with the corrected amount.',
            ),
          if (!relayConnected)
            _Banner(
              color: AppColors.bgInput,
              textColor: AppColors.textSecondary,
              icon: Icons.cloud_off_outlined,
              text: 'No backend relay is connected yet, so sending will report as '
                  'undelivered. Connect the deployed relay URL to enable real delivery.',
            ),
          const SizedBox(height: AppSpacing.sm),
          const Text('Choose a delivery channel', style: AppTypography.label),
          const SizedBox(height: AppSpacing.sm),
          SegmentedTabs(
            items: const [
              SegmentedTabItem(label: 'WhatsApp', icon: Icons.chat_bubble_outline),
              SegmentedTabItem(label: 'Email', icon: Icons.email_outlined),
            ],
            selectedIndex: _preferredChannel == NotificationChannel.whatsapp ? 0 : 1,
            onSelected: (i) => setState(
              () => _preferredChannel = i == 0 ? NotificationChannel.whatsapp : NotificationChannel.email,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          RepaintBoundary(
            key: _previewKey,
            child: _ReceiptPreview(bill: bill, members: members, result: result),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text('DELIVERY', style: AppTypography.eyebrow),
          const SizedBox(height: AppSpacing.sm),
          ...members.map((m) {
            final channel = _effectiveChannelFor(m);
            final outcome = _outcomes[m.id];
            return _DeliveryRow(member: m, channel: channel, outcome: outcome);
          }),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.textColor, required this.icon, required this.text});
  final Color color;
  final Color textColor;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppRadius.small)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: textColor, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: TextStyle(color: textColor, fontSize: 13))),
        ],
      ),
    );
  }
}

class _ReceiptPreview extends StatelessWidget {
  const _ReceiptPreview({required this.bill, required this.members, required this.result});
  final Bill bill;
  final List<Member> members;
  final SplitResult? result;

  @override
  Widget build(BuildContext context) {
    return ReceiptCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Column(
              children: [
                const Text('SPLIT RECEIPT', style: AppTypography.screenTitle),
                const SizedBox(height: 2),
                Text(
                  bill.title.isEmpty ? 'Untitled bill' : bill.title,
                  style: AppTypography.bodySecondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const DashedLine(),
          const SizedBox(height: AppSpacing.md),
          for (final item in bill.items)
            AmountRow(label: item.name, amount: item.price),
          if (bill.items.isEmpty) AmountRow(label: 'Bill total', amount: bill.subtotal),
          const SizedBox(height: AppSpacing.sm),
          const DashedLine(),
          const SizedBox(height: AppSpacing.sm),
          if (bill.taxAmount > 0) AmountRow(label: 'Tax', amount: bill.taxAmount),
          if (bill.serviceAmount > 0) AmountRow(label: 'Service charge', amount: bill.serviceAmount),
          if (bill.discountAmount > 0) AmountRow(label: 'Discount', amount: -bill.discountAmount),
          AmountRow(label: 'TOTAL', amount: bill.total, emphasize: true),
          const SizedBox(height: AppSpacing.md),
          const DashedLine(),
          const SizedBox(height: AppSpacing.md),
          const Text('PER PERSON', style: AppTypography.eyebrow),
          const SizedBox(height: AppSpacing.sm),
          for (final m in members)
            AmountRow(label: m.name, amount: result?.perMember[m.id]?.total ?? 0),
          const SizedBox(height: AppSpacing.md),
          const Center(child: StampBadge(text: 'READY TO SEND // SPLITYUK')),
        ],
      ),
    );
  }
}

class _DeliveryRow extends StatelessWidget {
  const _DeliveryRow({required this.member, required this.channel, required this.outcome});
  final Member member;
  final NotificationChannel? channel;
  final NotifyOutcome? outcome;

  @override
  Widget build(BuildContext context) {
    Widget statusWidget;
    if (outcome == null) {
      statusWidget = Text(
        channel == null
            ? 'Not reachable'
            : channel == NotificationChannel.whatsapp
                ? 'via WhatsApp'
                : 'via Email',
        style: AppTypography.bodySecondary,
      );
    } else if (outcome!.success) {
      statusWidget = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 16, color: AppColors.accentSuccess),
          SizedBox(width: 4),
          Text('Sent', style: TextStyle(color: AppColors.accentSuccess, fontWeight: FontWeight.w600)),
        ],
      );
    } else {
      statusWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 16, color: AppColors.accentDanger),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              outcome!.error ?? 'Failed',
              style: const TextStyle(color: AppColors.accentDanger, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(member.name, style: AppTypography.body)),
          statusWidget,
        ],
      ),
    );
  }
}
