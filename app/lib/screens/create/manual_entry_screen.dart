import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/dashed_line.dart';
import '../../core/widgets/segmented_tabs.dart';
import '../../models/split_mode.dart';
import '../../state/session_controller.dart';
import '../members/pick_members_screen.dart';

/// FR-3.1/FR-3.2: manual bill entry, either itemized or a single total,
/// plus optional tax/service/discount.
class ManualEntryScreen extends StatefulWidget {
  const ManualEntryScreen({super.key});

  @override
  State<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ItemRow {
  _ItemRow({String name = '', String price = ''})
    : nameController = TextEditingController(text: name),
      priceController = TextEditingController(text: price);
  final TextEditingController nameController;
  final TextEditingController priceController;

  int get price => int.tryParse(priceController.text) ?? 0;

  void dispose() {
    nameController.dispose();
    priceController.dispose();
  }
}

class _ManualEntryScreenState extends State<ManualEntryScreen> {
  bool _isItemized = true;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _totalController = TextEditingController();
  final TextEditingController _taxController = TextEditingController(text: '0');
  final TextEditingController _serviceController = TextEditingController(
    text: '0',
  );
  final TextEditingController _discountController = TextEditingController(
    text: '0',
  );
  DiscountType _discountType = DiscountType.amount;
  bool _splitExtrasEqually = false;

  final List<_ItemRow> _rows = [_ItemRow()];

  @override
  void dispose() {
    _titleController.dispose();
    _totalController.dispose();
    _taxController.dispose();
    _serviceController.dispose();
    _discountController.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  int get _subtotal {
    if (_isItemized) {
      return _rows.fold(0, (sum, row) => sum + row.price);
    }
    return int.tryParse(_totalController.text) ?? 0;
  }

  double get _taxPercent => double.tryParse(_taxController.text) ?? 0;
  double get _servicePercent => double.tryParse(_serviceController.text) ?? 0;
  int get _discountValue => int.tryParse(_discountController.text) ?? 0;

  int get _discountAmount {
    if (_discountValue <= 0) return 0;
    final raw = _discountType == DiscountType.amount
        ? _discountValue
        : (_subtotal * (_discountValue / 100)).round();
    return raw.clamp(0, _subtotal);
  }

  int get _taxableAmount => _subtotal - _discountAmount;
  int get _taxAmount => (_taxableAmount * (_taxPercent / 100)).round();
  int get _serviceAmount => (_taxableAmount * (_servicePercent / 100)).round();
  int get _estimatedTotal => _taxableAmount + _taxAmount + _serviceAmount;

  bool get _canContinue => _isItemized
      ? _rows.any((r) => r.price > 0 && r.nameController.text.trim().isNotEmpty)
      : _subtotal > 0;

  void _continue() {
    final session = context.read<SessionController>();
    session.startManualBill(itemized: _isItemized);
    session.setTitle(_titleController.text.trim());
    session.setTaxPercent(_taxPercent);
    session.setServicePercent(_servicePercent);
    session.setSplitExtrasEqually(_splitExtrasEqually);
    session.setDiscount(
      DiscountConfig(type: _discountType, value: _discountValue),
    );

    if (_isItemized) {
      for (final row in _rows) {
        final name = row.nameController.text.trim();
        if (name.isEmpty || row.price <= 0) continue;
        session.addItem(name: name, price: row.price);
      }
    } else {
      session.setManualTotal(_subtotal);
    }

    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PickMembersScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Receipt Workspace',
      bottomBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryButton(
            label: 'Continue to members',
            icon: Icons.arrow_forward,
            onPressed: _canContinue ? _continue : null,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedTabs(
              items: const [
                SegmentedTabItem(
                  label: 'Itemized',
                  icon: Icons.receipt_long_outlined,
                ),
                SegmentedTabItem(label: 'Total only', icon: Icons.tag_outlined),
              ],
              selectedIndex: _isItemized ? 0 : 1,
              onSelected: (i) => setState(() => _isItemized = i == 0),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Bill title (optional)',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_isItemized)
              ..._buildItemizedSection()
            else
              ..._buildTotalOnlySection(),
            const SizedBox(height: AppSpacing.lg),
            _buildExtraChargesSection(),
            const SizedBox(height: AppSpacing.lg),
            _buildSummary(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildItemizedSection() {
    return [
      const Text('Line items', style: AppTypography.label),
      const SizedBox(height: AppSpacing.sm),
      for (var i = 0; i < _rows.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: Text('${i + 1}', style: AppTypography.bodySecondary),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _rows[i].nameController,
                  decoration: const InputDecoration(
                    hintText: 'Item description',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _rows[i].priceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: 'Amount'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                color: AppColors.textSecondary,
                onPressed: _rows.length == 1
                    ? null
                    : () => setState(() {
                        _rows[i].dispose();
                        _rows.removeAt(i);
                      }),
              ),
            ],
          ),
        ),
      DashedOutlineButton(
        label: 'Add item row',
        onPressed: () => setState(() => _rows.add(_ItemRow())),
      ),
    ];
  }

  List<Widget> _buildTotalOnlySection() {
    return [
      const Text('Bill total', style: AppTypography.label),
      const SizedBox(height: AppSpacing.sm),
      TextField(
        controller: _totalController,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(prefixText: 'Rp ', hintText: '0'),
        onChanged: (_) => setState(() {}),
      ),
    ];
  }

  Widget _buildExtraChargesSection() {
    return Material(
      color: AppColors.bgSurface,
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Tax & extra charges', style: AppTypography.label),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _taxController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Tax',
                      suffixText: '%',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _serviceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Service',
                      suffixText: '%',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _discountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Discount / voucher',
                      prefixText: _discountType == DiscountType.amount
                          ? 'Rp '
                          : null,
                      suffixText: _discountType == DiscountType.percentage
                          ? '%'
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: SegmentedTabs(
                    items: const [
                      SegmentedTabItem(label: 'Rp'),
                      SegmentedTabItem(label: '%'),
                    ],
                    selectedIndex: _discountType == DiscountType.amount ? 0 : 1,
                    onSelected: (i) => setState(
                      () => _discountType = i == 0
                          ? DiscountType.amount
                          : DiscountType.percentage,
                    ),
                  ),
                ),
              ],
            ),
            if (_isItemized) ...[
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _splitExtrasEqually,
                onChanged: (v) => setState(() => _splitExtrasEqually = v),
                title: const Text(
                  'Split tax/service equally',
                  style: AppTypography.body,
                ),
                subtitle: const Text(
                  'Off: proportional to what each person ordered.',
                  style: AppTypography.bodySecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummary() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgInput,
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _summaryLine('Subtotal', _subtotal),
          if (_discountAmount > 0) _summaryLine('Discount', -_discountAmount),
          if (_taxAmount > 0) _summaryLine('Tax', _taxAmount),
          if (_serviceAmount > 0)
            _summaryLine('Service charge', _serviceAmount),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: DashedLine(),
          ),
          Row(
            children: [
              const Text('Estimated total', style: AppTypography.label),
              const Spacer(),
              Text(
                CurrencyFormatter.format(_estimatedTotal),
                style: AppTypography.amountLarge.copyWith(fontSize: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryLine(String label, int amount) {
    final isNegative = amount < 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: AppTypography.bodySecondary),
          const Spacer(),
          Text(
            '${isNegative ? '-' : ''}${CurrencyFormatter.format(amount.abs())}',
            style: AppTypography.amount,
          ),
        ],
      ),
    );
  }
}
