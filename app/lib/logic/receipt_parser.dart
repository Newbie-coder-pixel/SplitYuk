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
///
/// Real POS receipts commonly print each line item across *two* lines —
/// the description on one line, then a barcode/product-code followed by
/// qty and the line amount on the next (e.g. a retail receipt printing
/// "Paper Bag Red S" then "20154549101003000   1   3000" underneath it).
/// This parser tracks a short buffer of "name-looking" lines and attaches
/// them to the next code/qty/amount line it finds, rather than assuming
/// every item is a single self-contained line.
class ReceiptParser {
  ReceiptParser._();

  /// A trailing amount, anchored so it must start at a word boundary
  /// (start-of-line or after whitespace) — this stops something like a
  /// masked member/loyalty code ("819*****412") from being read as a
  /// price, since it's glued to the previous character, not space-separated.
  /// The final group may be a 3-digit thousands separator (","/".") or,
  /// for POS systems that print prices with a decimal tail even though IDR
  /// has no subunits (e.g. "260940.00"), a 2-digit decimal remainder.
  static final RegExp _amountAtEnd = RegExp(
    r'(?:^|\s)(\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{2})?|\d{4,}(?:[.,]\d{2})?)\s*$',
  );

  /// A barcode/product-code line: a long numeric code, optionally a
  /// separate qty, then the line amount — with no dependence on the
  /// description, which lives on a separate line entirely.
  static final RegExp _codeQtyAmountLine = RegExp(
    r'^(\d{6,})\D*?(?:(\d{1,4})\s+)?([\d.,]{3,})\s*$',
  );

  static final RegExp _dividerLine = RegExp(r'^-{2,}.*-{2,}$|^-{3,}$');

  static final RegExp _totalKeywords = RegExp(r'^\s*(total|jumlah)\b', caseSensitive: false);

  /// Lines that are receipt metadata/noise, never an item — matched
  /// against the whole line so a keyword anywhere on it is enough to
  /// discard it (and reset any buffered item name, since metadata never
  /// continues onto the next line as part of a product description).
  static final RegExp _skipLine = RegExp(
    r'\b(subtotal|sub-total|pajak|tax|ppn|pb1|service|svc|discount|diskon|'
    r'change|kembali|cash|tunai|bayar|debit|kredit|credit|visa|mastercard|'
    r'\bbca\b|\bbni\b|\bbri\b|mandiri|cimb|permata|danamon|\bbtn\b|ovo|gopay|'
    r'\bdana\b|shopeepay|linkaja|\bqris\b|\bpembayaran\b|metode\s*bayar|'
    r'serial\s*no|pos\s*no|cashier|member\s*code|score\s*get|current\s*point|'
    r'goods\s*code|u\s*/\s*p|date\s*:|sales\b)',
    caseSensitive: false,
  );

  static const int _maxBufferedNameLines = 3;

  static ParsedReceipt parse(String rawText) {
    final lines = rawText
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => !_dividerLine.hasMatch(line))
        .toList();

    final items = <BillItem>[];
    int? total;
    final nameBuffer = <String>[];

    for (final line in lines) {
      if (_skipLine.hasMatch(line)) {
        nameBuffer.clear();
        continue;
      }

      final codeMatch = _codeQtyAmountLine.firstMatch(line);
      if (codeMatch != null) {
        final amount = _parseAmount(codeMatch.group(3)!);
        if (amount != null && amount > 0 && nameBuffer.isNotEmpty) {
          items.add(BillItem(
            id: IdGenerator.next('item'),
            name: nameBuffer.join(' ').trim(),
            price: amount,
          ));
        }
        nameBuffer.clear();
        continue;
      }

      final inlineMatch = _amountAtEnd.firstMatch(line);
      if (inlineMatch != null) {
        final amount = _parseAmount(inlineMatch.group(1)!);
        if (amount != null && amount > 0) {
          final namePart = line.substring(0, inlineMatch.start).trim();

          if (_totalKeywords.hasMatch(line) && namePart.length < 20) {
            total ??= amount;
          } else if (namePart.isNotEmpty) {
            items.add(BillItem(id: IdGenerator.next('item'), name: namePart, price: amount));
          }
          // A bare, unlabeled number (no name on the same line, not a
          // total) can't be confidently attributed to anything — skip it
          // rather than guessing.
          nameBuffer.clear();
          continue;
        }
      }

      // No amount on this line at all — it's a candidate item description
      // that might be completed by a code/amount line right after it.
      nameBuffer.add(line);
      if (nameBuffer.length > _maxBufferedNameLines) {
        nameBuffer.removeAt(0);
      }
    }

    return ParsedReceipt(items: items, detectedTotal: total);
  }

  static int? _parseAmount(String raw) {
    // A trailing exactly-2-digit remainder after the final separator is a
    // decimal/cents tail some POS software prints even though IDR has no
    // subunits (e.g. "260940.00") — drop it. A trailing exactly-3-digit
    // group is a thousands separator and gets folded into the number
    // instead (e.g. "276,660" -> 276660).
    final decimalTail = RegExp(r'^(.*)[.,](\d{2})$').firstMatch(raw);
    final withoutCents = decimalTail != null ? decimalTail.group(1)! : raw;
    final digitsOnly = withoutCents.replaceAll(RegExp(r'[.,]'), '');
    return int.tryParse(digitsOnly);
  }
}
