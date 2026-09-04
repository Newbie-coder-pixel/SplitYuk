import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/dashed_line.dart';
import '../../core/widgets/receipt_card.dart';
import '../../logic/receipt_parser.dart';
import '../../models/bill_item.dart';
import '../../state/session_controller.dart';
import '../members/pick_members_screen.dart';

/// FR-2.3/FR-2.4: the OCR result must be shown fully editable, with a
/// non-blocking warning if the reviewed total doesn't match the receipt's
/// printed total.
class ReviewScannedScreen extends StatefulWidget {
  const ReviewScannedScreen({super.key, required this.imagePath, required this.parsed});

  final String imagePath;
  final ParsedReceipt parsed;

  @override
  State<ReviewScannedScreen> createState() => _ReviewScannedScreenState();
}

class _ReviewScannedScreenState extends State<ReviewScannedScreen> {
  late List<BillItem> _items;
  int? _detectedTotal;

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.parsed.items);
    _detectedTotal = widget.parsed.detectedTotal;
  }

  int get _reviewedSubtotal => _items.fold(0, (sum, item) => sum + item.price);

  bool get _hasMismatch =>
      _detectedTotal != null && _detectedTotal != _reviewedSubtotal;

  void _editItem(BillItem item) async {
    final result = await showModalBottomSheet<_ItemEditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
      ),
      builder: (_) => _ItemEditSheet(initialName: item.name, initialPrice: item.price),
    );
    if (result == null) return;
    setState(() {
      item.name = result.name;
      item.price = result.price;
    });
  }

  void _addMissedItem() async {
    final result = await showModalBottomSheet<_ItemEditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
      ),
      builder: (_) => const _ItemEditSheet(initialName: '', initialPrice: 0),
    );
    if (result == null || result.name.trim().isEmpty) return;
    setState(() {
      _items.add(BillItem(
        id: 'reviewed_${DateTime.now().microsecondsSinceEpoch}',
        name: result.name,
        price: result.price,
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Receipt Workspace',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_outlined, color: AppColors.accentViolet),
                const SizedBox(width: AppSpacing.sm),
                const Expanded(
                  child: Text('Review scanned receipt', style: AppTypography.sectionHeading),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            ReceiptCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('LINE ITEMS', style: AppTypography.eyebrow),
                  const SizedBox(height: AppSpacing.sm),
                  const DashedLine(),
                  const SizedBox(height: AppSpacing.sm),
                  if (_items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                      child: Text(
                        'No items were detected automatically. Add them below.',
                        style: AppTypography.bodySecondary,
                      ),
                    )
                  else
                    ..._items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(child: Text(item.name, style: AppTypography.body)),
                            Text(
                              CurrencyFormatter.format(item.price),
                              style: AppTypography.amount,
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              color: AppColors.textSecondary,
                              onPressed: () => _editItem(item),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              color: AppColors.textSecondary,
                              onPressed: () => setState(() => _items.remove(item)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  DashedOutlineButton(label: 'Add missed item', onPressed: _addMissedItem),
                  const SizedBox(height: AppSpacing.md),
                  const DashedLine(),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.bgInput,
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                    child: Row(
                      children: [
                        const Text('TOTAL', style: AppTypography.label),
                        const Spacer(),
                        Text(
                          CurrencyFormatter.format(_reviewedSubtotal),
                          style: AppTypography.amountLarge.copyWith(fontSize: 20),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_hasMismatch) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.bgAmber,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppColors.textAmber),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Total mismatch detected',
                            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textAmber),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'The receipt printed ${CurrencyFormatter.format(_detectedTotal!)}, but '
                            'the reviewed items add up to ${CurrencyFormatter.format(_reviewedSubtotal)}. '
                            'Check the amounts above, or continue if this is expected (e.g. tax/service '
                            'not itemized separately).',
                            style: const TextStyle(color: AppColors.textAmber),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'Looks right, continue',
              icon: Icons.arrow_forward,
              onPressed: _items.isEmpty
                  ? null
                  : () {
                      final session = context.read<SessionController>();
                      session.startScannedBill(
                        receiptImagePath: widget.imagePath,
                        receiptPrintedTotal: _detectedTotal,
                      );
                      session.setItemsFromOcr(_items);
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const PickMembersScreen()),
                      );
                    },
            ),
            const SizedBox(height: AppSpacing.sm),
            SecondaryButton(
              label: 'Retake photo',
              icon: Icons.camera_alt_outlined,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemEditResult {
  const _ItemEditResult(this.name, this.price);
  final String name;
  final int price;
}

class _ItemEditSheet extends StatefulWidget {
  const _ItemEditSheet({required this.initialName, required this.initialPrice});
  final String initialName;
  final int initialPrice;

  @override
  State<_ItemEditSheet> createState() => _ItemEditSheetState();
}

class _ItemEditSheetState extends State<_ItemEditSheet> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.initialName);
  late final TextEditingController _priceController =
      TextEditingController(text: widget.initialPrice == 0 ? '' : widget.initialPrice.toString());

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Item details', style: AppTypography.sectionHeading),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Item name'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _priceController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Amount (Rp)'),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Save',
            onPressed: () {
              final price = int.tryParse(_priceController.text) ?? 0;
              Navigator.of(context).pop(_ItemEditResult(_nameController.text.trim(), price));
            },
          ),
        ],
      ),
    );
  }
}
