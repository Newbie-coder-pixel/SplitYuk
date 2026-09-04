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
/// **It deliberately does not assume any fixed number of lines per item.**
/// An earlier version did — it expected either "name and amount on one
/// line" or "name on one line, then goods-code/qty/amount on the next" —
/// and collapsed to a single garbage item on a real receipt, because OCR
/// does not reliably reproduce the printed line breaks: it merges a code
/// row with the next product's description, splits one row in two, or
/// (before `OcrLayout` was introduced) emits the description column and
/// the amount column as separate chunks entirely.
///
/// Instead this reads the receipt as a *stream of tokens* and relies on
/// the one thing every POS layout has in common: descriptions are made of
/// words and prices are made of digits, and they alternate. So the stream
/// is cut into alternating text runs and numeric runs, and each numeric
/// run is paired with the text run immediately before it:
///
/// ```
///   Paper Bag Red S          20154549101003000   1   3000
///   └──── text run ────┘     └────────── numeric run ─────┘
/// ```
///
/// Within a numeric run the *last* plausible amount is the line total (the
/// "Amt" column); anything before it is a goods code and/or a quantity,
/// never a price. This holds whether the run sits on the same OCR line as
/// its description, the next one, or is split across three.
///
/// A text run only ever contributes its **last line's** worth of words as
/// the item name, so header/address/footer lines stacked above an item
/// don't get glued onto it.
class ReceiptParser {
  ReceiptParser._();

  /// A token made only of digits and thousands/decimal separators, and
  /// starting and ending with a digit. Anything else (`45ml`, `(1`,
  /// `819*****412`, `No.`) is a word, not a number — which is what keeps a
  /// masked loyalty code or a size suffix from being read as a price.
  static final RegExp _numericToken = RegExp(r'^\d(?:[\d.,]*\d)?$');

  /// `56.000`, `276,660`, `1.234.567` — grouped thousands, optionally with
  /// a 2-digit decimal tail.
  static final RegExp _groupedAmount = RegExp(r'^\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{2})?$');

  /// `3000`, `179900`, `260940.00` — ungrouped, optionally with a 2-digit
  /// decimal tail that some POS software prints even though IDR has no
  /// subunits.
  static final RegExp _plainAmount = RegExp(r'^\d+(?:[.,]\d{2})?$');

  static final RegExp _decimalTail = RegExp(r'^(.*)[.,](\d{2})$');

  static final RegExp _dividerLine = RegExp(r'^-{2,}.*-{2,}$|^-{3,}$');

  static final RegExp _totalKeywords =
      RegExp(r'^\s*(grand\s+)?(total|jumlah)\b', caseSensitive: false);

  /// Lines that are receipt metadata/noise, never an item — matched
  /// against the whole line so a keyword anywhere on it is enough to
  /// discard it (and to act as a barrier: metadata never continues onto
  /// the next line as part of a product description, and a number below it
  /// never belongs to a product above it).
  static final RegExp _skipLine = RegExp(
    r'\b(subtotal|sub-total|pajak|tax|ppn|pb1|service|svc|discount|diskon|'
    r'change|kembali|cash|tunai|bayar|debit|kredit|credit|visa|mastercard|'
    r'\bbca\b|\bbni\b|\bbri\b|mandiri|cimb|permata|danamon|\bbtn\b|ovo|gopay|'
    r'\bdana\b|shopeepay|linkaja|\bqris\b|\bpembayaran\b|metode\s*bayar|'
    r'serial\s*no|pos\s*no|cashier|member\s*code|score\s*get|current\s*point|'
    r'goods\s*code|u\s*/\s*p|date\s*:|sales\b)',
    caseSensitive: false,
  );

  /// Below this, a number is a quantity, a line counter, or OCR noise —
  /// not a Rupiah price (the smallest coin in circulation is Rp 100).
  static const int _minAmount = 100;

  /// Above 9 digits a "number" is a barcode or goods code, not a price.
  static const int _maxAmountDigits = 9;

  /// A leading numeric token this long is a goods/barcode code. Used only
  /// to decide whether an amount with no readable description is still
  /// worth keeping as an unnamed item.
  static const int _productCodeDigits = 10;

  static ParsedReceipt parse(String rawText) {
    final lines = rawText
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final items = <BillItem>[];
    int? total;
    bool awaitingTotalAmount = false;

    // The description candidate for the next numeric run, plus the index
    // of the line it came from — a new line resets it, so only the last
    // line's words survive as a name.
    final nameTokens = <String>[];
    int? nameLine;

    // The numeric run currently being accumulated.
    final run = <String>[];

    void flushRun() {
      if (run.isEmpty) return;
      final tokens = List.of(run);
      run.clear();

      int? amount;
      var amountIndex = -1;
      for (var i = tokens.length - 1; i >= 0; i--) {
        final value = _amountFrom(tokens[i]);
        if (value != null) {
          amount = value;
          amountIndex = i;
          break;
        }
      }
      if (amount == null) return;

      // The only price-shaped token is the leading goods code — the amount
      // column didn't survive OCR, so there is no price to trust here.
      if (amountIndex == 0 && tokens.length > 1) return;

      final name = nameTokens.join(' ').trim();
      if (name.isNotEmpty) {
        items.add(BillItem(id: IdGenerator.next('item'), name: name, price: amount));
      } else if (amountIndex > 0 && _digitsOnly(tokens.first).length >= _productCodeDigits) {
        // No readable description, but a goods code and an amount in the
        // right columns is strong evidence of a real purchased line. Keep
        // it as an unnamed item rather than silently dropping money — the
        // review screen (FR-2.3) is where the user names it.
        items.add(BillItem(
          id: IdGenerator.next('item'),
          name: 'Item ${items.length + 1}',
          price: amount,
        ));
      }

      nameTokens.clear();
      nameLine = null;
    }

    void barrier() {
      flushRun();
      nameTokens.clear();
      nameLine = null;
      awaitingTotalAmount = false;
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (_dividerLine.hasMatch(line)) {
        barrier();
        continue;
      }

      final lineTokens = line.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

      // Checked before _skipLine on purpose: "Total Bayar" would otherwise
      // be discarded as a payment line and the printed total lost.
      if (_totalKeywords.hasMatch(line)) {
        barrier();
        final numerics = lineTokens.where(_numericToken.hasMatch).toList();
        if (numerics.isEmpty) {
          // A bare "TOTAL" with its amount on the following line/column.
          awaitingTotalAmount = true;
        } else {
          for (var j = numerics.length - 1; j >= 0; j--) {
            final value = _amountFrom(numerics[j]);
            if (value != null) {
              total ??= value;
              break;
            }
          }
        }
        continue;
      }

      if (_skipLine.hasMatch(line)) {
        barrier();
        continue;
      }

      for (final token in lineTokens) {
        if (_numericToken.hasMatch(token)) {
          if (awaitingTotalAmount) {
            final value = _amountFrom(token);
            if (value != null) {
              total ??= value;
              awaitingTotalAmount = false;
              continue;
            }
          }
          run.add(token);
          continue;
        }

        // A word closes any numeric run in progress: the run belonged to
        // whatever was described *before* it, and this word starts the
        // description of whatever comes next.
        awaitingTotalAmount = false;
        flushRun();
        if (nameLine != i) {
          nameTokens.clear();
          nameLine = i;
        }
        nameTokens.add(token);
      }
    }

    flushRun();

    return ParsedReceipt(items: items, detectedTotal: total);
  }

  /// The Rupiah value of [token] if it is plausibly a price, else null.
  static int? _amountFrom(String token) {
    if (!_groupedAmount.hasMatch(token) && !_plainAmount.hasMatch(token)) return null;

    // A trailing exactly-2-digit remainder after the final separator is a
    // decimal/cents tail (e.g. "260940.00") — drop it. A trailing
    // exactly-3-digit group is a thousands separator and gets folded into
    // the number instead (e.g. "276,660" -> 276660).
    final tail = _decimalTail.firstMatch(token);
    final body = tail != null ? tail.group(1)! : token;
    final digits = _digitsOnly(body);
    if (digits.isEmpty || digits.length > _maxAmountDigits) return null;

    final value = int.tryParse(digits);
    if (value == null || value < _minAmount) return null;
    return value;
  }

  static String _digitsOnly(String raw) => raw.replaceAll(RegExp(r'[^0-9]'), '');
}
