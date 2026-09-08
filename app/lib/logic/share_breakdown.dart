import '../core/utils/currency_formatter.dart';
import '../models/bill_item.dart';
import 'split_result.dart';

/// Builds the message a member actually receives.
///
/// It used to say only "your share comes to Rp 24.000. (Full breakdown
/// attached.)" — and when the attachment didn't arrive, that left someone
/// being asked for money with no way to see what it was for, and no way to
/// check it. The breakdown belongs in the message itself: the items they
/// were assigned, what was added or taken off, and the arithmetic that
/// reaches their number.
///
/// The money summary is written as a fixed-width block so the amounts line
/// up in a column. WhatsApp renders text between triple backticks in a
/// monospace font, which is what makes that alignment hold; email clients
/// generally don't, so [monospace] turns the fences off and the block is
/// laid out with the same padding either way.
class ShareBreakdown {
  ShareBreakdown._();

  /// Width of the money block. Chosen to fit a WhatsApp bubble on a narrow
  /// phone without wrapping, which would destroy the column alignment.
  static const int _blockWidth = 30;

  /// Longer item names are cut here so the list stays readable. The
  /// receipt itself is the record; this is a reminder of what they owe.
  static const int _maxNameLength = 34;

  static String build({
    required String billTitle,
    required String recipientName,
    required List<BillItem> items,
    required String memberId,
    required MemberShare share,
    required int billTotal,
    required int memberCount,
    bool monospace = true,
  }) {
    final lines = <String>[
      '*${billTitle.trim().isEmpty ? 'SplitYuk bill' : billTitle.trim()}*',
      '',
      'Hi ${recipientName.trim().isEmpty ? 'there' : recipientName.trim()}, '
          'here is your share of this bill.',
    ];

    final assigned = items.where((item) => item.assignedMemberIds.contains(memberId)).toList();
    if (assigned.isNotEmpty) {
      lines
        ..add('')
        ..add('YOUR ITEMS');
      for (final item in assigned) {
        final sharedBy = item.assignedMemberIds.length;
        final yourPart = item.shareFor(memberId).round();
        lines.add('• ${_shorten(item.name)}');
        lines.add(
          sharedBy > 1
              ? '  ${CurrencyFormatter.format(item.price)} shared by $sharedBy'
                  ' → ${CurrencyFormatter.format(yourPart)}'
              : '  ${CurrencyFormatter.format(yourPart)}',
        );
      }
    }

    final summary = <String>[];
    // Only meaningful when there are per-item figures to add up to; the
    // quick split modes hand out a whole-bill share with no breakdown.
    if (assigned.isNotEmpty) {
      summary.add(_row('Items', share.itemSubtotal.round()));
    }
    if (share.discountShare != 0) summary.add(_row('Discount', -share.discountShare));
    if (share.taxShare != 0) summary.add(_row('Tax', share.taxShare, signed: true));
    if (share.serviceShare != 0) summary.add(_row('Service', share.serviceShare, signed: true));
    summary.add('-' * _blockWidth);
    summary.add(_row('YOU PAY', share.total));

    lines.add('');
    if (monospace) lines.add('```');
    lines.addAll(summary);
    if (monospace) lines.add('```');

    lines
      ..add('')
      ..add('Bill total ${CurrencyFormatter.format(billTotal)}, '
          'split between $memberCount ${memberCount == 1 ? 'person' : 'people'}.');

    return lines.join('\n');
  }

  /// A label on the left and a right-aligned amount, padded to
  /// [_blockWidth]. A deduction keeps its minus sign; [signed] marks an
  /// addition with a plus so it reads as one.
  static String _row(String label, int amount, {bool signed = false}) {
    final magnitude = CurrencyFormatter.format(amount.abs());
    final prefix = amount < 0 ? '-' : (signed ? '+' : '');
    final value = '$prefix$magnitude';
    final gap = _blockWidth - label.length - value.length;
    return gap > 0 ? '$label${' ' * gap}$value' : '$label $value';
  }

  static String _shorten(String name) {
    final trimmed = name.trim();
    if (trimmed.length <= _maxNameLength) return trimmed;
    return '${trimmed.substring(0, _maxNameLength - 1)}…';
  }
}
