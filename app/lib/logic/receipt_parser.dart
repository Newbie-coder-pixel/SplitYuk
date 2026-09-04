import '../core/utils/id_generator.dart';
import '../models/bill_item.dart';

class ParsedReceipt {
  const ParsedReceipt({required this.items, this.detectedTotal});

  final List<BillItem> items;

  /// The total as printed on the receipt, if a "Total" line was detected —
  /// used for the FR-2.4 mismatch check against the reviewed items.
  final int? detectedTotal;
}

/// Turns raw OCR text into candidate line items. This is a heuristic, not
/// a guarantee — PRD FR-2.3 requires every result to go through an
/// editable review screen before it's trusted, and this parser is built
/// on that assumption rather than trying to be perfect.
class ReceiptParser {
  ReceiptParser._();

  static final RegExp _amountAtEnd = RegExp(r'(\d{1,3}(?:[.,]\d{3})+|\d{4,})\s*$');
  static final RegExp _totalKeywords = RegExp(r'\b(total|jumlah)\b', caseSensitive: false);
  static final RegExp _skipKeywords = RegExp(
    r'\b(subtotal|pajak|tax|ppn|pb1|service|svc|discount|diskon|change|kembali|cash|tunai|bayar)\b',
    caseSensitive: false,
  );

  static ParsedReceipt parse(String rawText) {
    final lines = rawText
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final items = <BillItem>[];
    int? total;

    for (final line in lines) {
      final match = _amountAtEnd.firstMatch(line);
      if (match == null) continue;

      final amount = _parseAmount(match.group(1)!);
      if (amount == null || amount <= 0) continue;

      final namePart = line.substring(0, match.start).trim();

      if (_totalKeywords.hasMatch(line) && namePart.length < 20) {
        // Keep the first (usually only) grand-total line encountered.
        total ??= amount;
        continue;
      }

      if (_skipKeywords.hasMatch(line)) continue;
      if (namePart.isEmpty) continue;

      items.add(BillItem(id: IdGenerator.next('item'), name: namePart, price: amount));
    }

    return ParsedReceipt(items: items, detectedTotal: total);
  }

  static int? _parseAmount(String raw) {
    // IDR has no subunits in everyday use, so any '.' or ',' here is a
    // thousands separator, never a decimal point.
    final digitsOnly = raw.replaceAll(RegExp(r'[.,]'), '');
    return int.tryParse(digitsOnly);
  }
}
