import 'dart:typed_data';

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

/// Which reader produced the result being reviewed. The two are not
/// remotely equal in accuracy, and the user has to be told which one they
/// are looking at — a silent downgrade to the on-device reader looks
/// exactly like the AI having done a terrible job.
enum ReceiptReadSource { ai, onDevice }

/// FR-2.3/FR-2.4: the OCR result must be shown fully editable, with a
/// non-blocking warning if the reviewed total doesn't match the receipt's
/// printed total.
class ReviewScannedScreen extends StatefulWidget {
  const ReviewScannedScreen({
    super.key,
    required this.imagePath,
    required this.imageBytes,
    required this.parsed,
    this.readSource = ReceiptReadSource.ai,
    this.onRetry,
  });

  /// Where the OS left the photo, so the session can delete it later.
  /// Null on the web, which has no file to clean up.
  final String? imagePath;

  /// The photo itself, forwarded as the notification attachment.
  final Uint8List imageBytes;

  final ParsedReceipt parsed;
  final ReceiptReadSource readSource;

  /// Invoked when the user asks to read the photo again — only offered
  /// after an on-device read, where retrying can materially improve it.
  final VoidCallback? onRetry;

  @override
  State<ReviewScannedScreen> createState() => _ReviewScannedScreenState();
}

/// Column widths shared by the header and every item row, so the two stay
/// aligned — a header that doesn't line up with its rows is worse than no
/// header at all when you're checking a list against a paper receipt.
const double _qtyColumnWidth = 28;

/// Wide enough for both icon buttons at [_actionButtonSize] each.
///
/// The size is set explicitly, tap target included: an IconButton's
/// default 48px tap target ignores a smaller icon and silently overflowed
/// this column on a phone-width screen. 40px stays a comfortable target
/// while leaving the item name room to breathe on a dense receipt.
const double _actionButtonSize = 40;
const double _actionsColumnWidth = _actionButtonSize * 2;

class _ReviewScannedScreenState extends State<ReviewScannedScreen> {
  late List<BillItem> _items;
  int? _detectedTotal;
  late int _discount;
  late int _tax;
  late int _serviceCharge;

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.parsed.items);
    _detectedTotal = widget.parsed.detectedTotal;
    _discount = widget.parsed.discount;
    _tax = widget.parsed.tax;
    _serviceCharge = widget.parsed.serviceCharge;
    _includedTax = widget.parsed.includedTax;
  }

  /// Tax the receipt already built into its prices. Shown but never added,
  /// and not editable — it isn't a number the split depends on, it is
  /// there so a reader can see the tax was understood rather than missed.
  late int _includedTax;

  int get _reviewedSubtotal => _items.fold(0, (sum, item) => sum + item.price);

  /// Units bought, not lines printed — "8 lines · 9 items" is the quickest
  /// way to notice a quantity the scan read as 1.
  int get _totalUnits => _items.fold(0, (sum, item) => sum + item.quantity);

  /// What the group actually owes: items, less any discount, plus anything
  /// charged on top. This — not the raw item subtotal — is what has to
  /// match the receipt's printed total.
  int get _reviewedTotal => _reviewedSubtotal - _discount + _tax + _serviceCharge;

  bool get _hasAdjustments => _discount != 0 || _tax != 0 || _serviceCharge != 0;

  /// "2 × Rp 3.600" for a multi-unit line, so the quantity, the unit price
  /// and the line total can all be checked against the paper at a glance.
  ///
  /// Null for a single unit, where it would only repeat the amount. When
  /// the total doesn't divide evenly the unit price is marked approximate
  /// rather than shown as exact — the point of this line is checking the
  /// arithmetic, so a figure that doesn't multiply back must say so.
  String? _unitPriceLabel(BillItem item) {
    if (item.quantity <= 1) return null;
    final unit = CurrencyFormatter.format(item.price ~/ item.quantity);
    final exact = item.price % item.quantity == 0;
    return '${item.quantity} × ${exact ? '' : '≈'}$unit';
  }

  bool get _hasMismatch => _detectedTotal != null && _detectedTotal != _reviewedTotal;

  Future<void> _editAdjustments() async {
    final result = await showModalBottomSheet<_AdjustmentsResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
      ),
      builder: (_) => _AdjustmentsSheet(
        discount: _discount,
        tax: _tax,
        serviceCharge: _serviceCharge,
      ),
    );
    if (result == null) return;
    setState(() {
      _discount = result.discount;
      _tax = result.tax;
      _serviceCharge = result.serviceCharge;
    });
  }

  void _editItem(BillItem item) async {
    final result = await showModalBottomSheet<_ItemEditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
      ),
      builder: (_) => _ItemEditSheet(
        initialName: item.name,
        initialPrice: item.price,
        initialQuantity: item.quantity,
      ),
    );
    if (result == null) return;
    setState(() {
      item.name = result.name;
      item.price = result.price;
      item.quantity = result.quantity;
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
      builder: (_) => const _ItemEditSheet(initialName: '', initialPrice: 0, initialQuantity: 1),
    );
    if (result == null || result.name.trim().isEmpty) return;
    setState(() {
      _items.add(BillItem(
        id: 'reviewed_${DateTime.now().microsecondsSinceEpoch}',
        name: result.name,
        price: result.price,
        quantity: result.quantity,
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
            if (widget.readSource == ReceiptReadSource.onDevice) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.bgAmber,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.offline_bolt_outlined, color: AppColors.textAmber),
                        const SizedBox(width: AppSpacing.sm),
                        const Expanded(
                          child: Text(
                            'Read on this device, not by AI',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textAmber,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'The AI reader could not be reached, so the photo was read on the '
                      'phone instead. That is much less accurate — check every line and '
                      'amount below, or try again.',
                      style: TextStyle(color: AppColors.textAmber),
                    ),
                    if (widget.onRetry != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            widget.onRetry!();
                          },
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Try reading with AI again'),
                          style: TextButton.styleFrom(foregroundColor: AppColors.textAmber),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            ReceiptCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text('LINE ITEMS', style: AppTypography.eyebrow),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          '${_items.length} ${_items.length == 1 ? 'line' : 'lines'}'
                          ' · $_totalUnits ${_totalUnits == 1 ? 'item' : 'items'}',
                          style: AppTypography.bodySecondary,
                          textAlign: TextAlign.end,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const DashedLine(),
                  // A column header in the same order the receipt prints
                  // them, so the list can be read straight down against the
                  // paper it came from.
                  if (_items.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
                      child: Row(
                        children: [
                          SizedBox(
                            width: _qtyColumnWidth,
                            child: Text('QTY', style: AppTypography.eyebrow),
                          ),
                          Expanded(child: Text('ITEM', style: AppTypography.eyebrow)),
                          Text('LINE TOTAL', style: AppTypography.eyebrow),
                          // Keeps the header aligned with the edit/remove
                          // buttons on each row below.
                          SizedBox(width: _actionsColumnWidth),
                        ],
                      ),
                    ),
                    const DashedLine(),
                  ],
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: _qtyColumnWidth,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '${item.quantity}',
                                  style: AppTypography.body.copyWith(
                                    color: AppColors.textSecondary,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2, right: AppSpacing.sm),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.name, style: AppTypography.body),
                                    // Only worth the extra line when there
                                    // is more than one: "2 × Rp 3.600" is
                                    // how you check a line total against
                                    // the receipt, "1 × Rp 3.000" is noise.
                                    if (_unitPriceLabel(item) != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          _unitPriceLabel(item)!,
                                          style: AppTypography.bodySecondary,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                CurrencyFormatter.format(item.price),
                                style: AppTypography.amount,
                              ),
                            ),
                            SizedBox(
                              width: _actionsColumnWidth,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 18),
                                    color: AppColors.textSecondary,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints.tightFor(
                                      width: _actionButtonSize,
                                      height: _actionButtonSize,
                                    ),
                                    style: IconButton.styleFrom(
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () => _editItem(item),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    color: AppColors.textSecondary,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints.tightFor(
                                      width: _actionButtonSize,
                                      height: _actionButtonSize,
                                    ),
                                    style: IconButton.styleFrom(
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () => setState(() => _items.remove(item)),
                                  ),
                                ],
                              ),
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
                  Row(
                    children: [
                      const Text('ADJUSTMENTS', style: AppTypography.eyebrow),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _editAdjustments,
                        icon: const Icon(Icons.tune, size: 16),
                        label: Text(_hasAdjustments ? 'Edit' : 'Add'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.accentViolet,
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _SummaryRow(label: 'Subtotal', amount: _reviewedSubtotal),
                  if (_discount > 0)
                    _SummaryRow(label: 'Discount', amount: -_discount, highlight: true),
                  if (_tax > 0) _SummaryRow(label: 'Tax', amount: _tax),
                  if (_serviceCharge > 0) _SummaryRow(label: 'Service', amount: _serviceCharge),
                  if (_includedTax > 0)
                    _SummaryRow(
                      label: 'Tax (already in the prices)',
                      amount: _includedTax,
                      muted: true,
                    ),
                  if (!_hasAdjustments && _includedTax == 0)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'No discount, tax or service charge was found on this receipt.',
                        style: AppTypography.bodySecondary,
                      ),
                    ),
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
                          CurrencyFormatter.format(_reviewedTotal),
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
                            'the reviewed bill comes to ${CurrencyFormatter.format(_reviewedTotal)}. '
                            'A missed item, or a discount, tax or service charge that was not picked '
                            'up, would explain the difference — check the amounts above, or continue '
                            'if this is expected.',
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
                      session.bill.attachmentBytes = widget.imageBytes;
                      session.setItemsFromOcr(_items);
                      session.setScannedAdjustments(
                        discount: _discount,
                        tax: _tax,
                        serviceCharge: _serviceCharge,
                      );
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

/// One line of the receipt-style money summary. A negative [amount] is
/// rendered with its minus sign, so a deduction reads as a deduction.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.amount,
    this.highlight = false,
    this.muted = false,
  });

  final String label;
  final int amount;
  final bool highlight;

  /// For a figure that is shown for information but does not move the
  /// total — tax already inside the prices. Rendered quieter so it can't
  /// be read as another charge being stacked on.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final formatted = amount < 0
        ? '- ${CurrencyFormatter.format(amount.abs())}'
        : CurrencyFormatter.format(amount);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTypography.bodySecondary)),
          Text(
            formatted,
            style: muted
                ? AppTypography.bodySecondary
                : AppTypography.amount.copyWith(
                    color: highlight ? AppColors.accentViolet : null,
                  ),
          ),
        ],
      ),
    );
  }
}

class _AdjustmentsResult {
  const _AdjustmentsResult(this.discount, this.tax, this.serviceCharge);
  final int discount;
  final int tax;
  final int serviceCharge;
}

/// FR-2.3 applies to more than the item list: a discount or service charge
/// the scan misread has to be correctable too, or the group is split on a
/// number nobody can fix.
class _AdjustmentsSheet extends StatefulWidget {
  const _AdjustmentsSheet({
    required this.discount,
    required this.tax,
    required this.serviceCharge,
  });

  final int discount;
  final int tax;
  final int serviceCharge;

  @override
  State<_AdjustmentsSheet> createState() => _AdjustmentsSheetState();
}

class _AdjustmentsSheetState extends State<_AdjustmentsSheet> {
  late final TextEditingController _discountController = _controllerFor(widget.discount);
  late final TextEditingController _taxController = _controllerFor(widget.tax);
  late final TextEditingController _serviceController = _controllerFor(widget.serviceCharge);

  static TextEditingController _controllerFor(int value) =>
      TextEditingController(text: value == 0 ? '' : value.toString());

  @override
  void dispose() {
    _discountController.dispose();
    _taxController.dispose();
    _serviceController.dispose();
    super.dispose();
  }

  int _valueOf(TextEditingController controller) =>
      int.tryParse(controller.text.trim())?.abs() ?? 0;

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
          const Text('Discount, tax & service', style: AppTypography.sectionHeading),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Enter tax and service only if the receipt adds them on top of the item '
            'prices. Leave them empty when the printed prices already include them.',
            style: AppTypography.bodySecondary,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _discountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Discount (Rp)'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _taxController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Tax (Rp)'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _serviceController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Service charge (Rp)'),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Save',
            onPressed: () => Navigator.of(context).pop(_AdjustmentsResult(
              _valueOf(_discountController),
              _valueOf(_taxController),
              _valueOf(_serviceController),
            )),
          ),
        ],
      ),
    );
  }
}

class _ItemEditResult {
  const _ItemEditResult(this.name, this.price, this.quantity);
  final String name;
  final int price;
  final int quantity;
}

class _ItemEditSheet extends StatefulWidget {
  const _ItemEditSheet({
    required this.initialName,
    required this.initialPrice,
    required this.initialQuantity,
  });
  final String initialName;
  final int initialPrice;
  final int initialQuantity;

  @override
  State<_ItemEditSheet> createState() => _ItemEditSheetState();
}

class _ItemEditSheetState extends State<_ItemEditSheet> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.initialName);
  late final TextEditingController _priceController =
      TextEditingController(text: widget.initialPrice == 0 ? '' : widget.initialPrice.toString());
  late final TextEditingController _quantityController =
      TextEditingController(text: widget.initialQuantity.toString());

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _quantityController.dispose();
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: TextField(
                  controller: _quantityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Qty'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextField(
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Line total (Rp)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Enter what the line costs in total, not the price of one — the quantity '
            'is shown so you can check it against the receipt.',
            style: AppTypography.bodySecondary,
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Save',
            onPressed: () {
              final price = int.tryParse(_priceController.text) ?? 0;
              final quantity = int.tryParse(_quantityController.text.trim()) ?? 1;
              Navigator.of(context).pop(_ItemEditResult(
                _nameController.text.trim(),
                price,
                quantity < 1 ? 1 : quantity,
              ));
            },
          ),
        ],
      ),
    );
  }
}
