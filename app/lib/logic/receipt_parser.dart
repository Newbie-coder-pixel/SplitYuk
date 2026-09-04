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
/// on that assumption rather than trying to be perfect. The AI path
/// (Gemini, via the relay) is what actually generalizes across arbitrary
/// receipt designs; this is the offline/unconfigured fallback, and it is
/// tuned for Indonesian Rupiah receipts specifically.
///
/// **It deliberately does not assume any fixed layout.** An earlier
/// version did — it expected either "name and amount on one line" or
/// "name on one line, then goods-code/qty/amount on the next" — and
/// collapsed to a single garbage item on a real receipt, because OCR does
/// not reliably reproduce the printed line breaks: it merges a code row
/// with the next product's description, splits one row in two, or (before
/// `OcrLayout` was introduced) emits the description column and the amount
/// column as separate chunks entirely.
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
/// never a price. Numbers trailing *after* that amount are not part of
/// this item at all — they're the leading quantity of the next one (the
/// `2 Nasi Goreng 40.000 / 1 Es Teh 8.000` layout), so they are handed
/// back to the next run rather than swallowed.
///
/// The layouts this is known to read, all covered by tests:
///
/// | Layout | Example |
/// |---|---|
/// | name + amount | `Nasi Goreng 56.000` |
/// | name, then code/qty/amount below | `Paper Bag Red S` / `2015… 1 3000` |
/// | leading quantity | `2 Nasi Goreng 40.000` |
/// | unit price × quantity, with a line total | `Nasi Goreng 2 x 25.000 50.000` |
/// | unit price × quantity, no line total | `Nasi Goreng 2 x 25.000` → 50.000 |
/// | currency-marked amounts | `Rp25.000`, `Rp 25.000`, `25.000,-` |
/// | dotted leaders | `Mie Ayam ..... 20.000` |
/// | amount on its own line/column | `Nasi Campur` / `25.000` |
///
/// Known limits, accepted deliberately: amounts are read as Rupiah, so a
/// `.`/`,` before a final 3-digit group is a thousands separator, never a
/// decimal point — `4.50` (a western $4.50) is not understood, because
/// reading it as 4.5 would mean misreading the far more common `3.000` as
/// 3. And a text run only contributes its **last line** as the item name,
/// so a product description that OCR wrapped across two lines keeps only
/// the second — that is the price of not gluing header/address lines onto
/// the first item, and the review screen is where the user fixes it.
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

  /// `Rp`/`RP.`/`IDR` glued to or standing before an amount.
  static final RegExp _currencyPrefix = RegExp(r'^(rp|idr)\.?', caseSensitive: false);

  /// The Indonesian `25.000,-` / `25.000-` price suffix.
  static final RegExp _amountSuffix = RegExp(r'[,.]?-+$');

  /// Neither a letter nor a digit anywhere: a dotted leader, a pipe, a
  /// stray bracket. Carries no meaning, and must not be mistaken for the
  /// start of a product name.
  static final RegExp _hasAlphanumeric = RegExp(r'[0-9a-zA-Z]');

  /// The "times" marker in `2 x 25.000` / `2 @ 25.000`.
  static final RegExp _multiplier = RegExp(r'^[x*@]$', caseSensitive: false);

  /// A quantity with the multiplier glued to it: the `2x` of `2x Nasi
  /// Goreng`. Split rather than read as a word, so it doesn't end up in
  /// the item's name.
  static final RegExp _gluedQuantity = RegExp(r'^(\d{1,3})[x*]$', caseSensitive: false);

  /// A unit price with the marker glued to it: the `@25.000` of `2
  /// @25.000`. Only `@` is split this way — `x` glued to the *front* of a
  /// number is too easily a product name like `X100`.
  static final RegExp _gluedUnitPrice = RegExp(r'^@(.+)$');

  /// The `1.` / `2)` of a numbered menu line — an ordinal, not a name.
  static final RegExp _ordinalPrefix = RegExp(r'^\d{1,3}[.)]$');

  static final RegExp _dividerLine = RegExp(r'^-{2,}.*-{2,}$|^-{3,}$');

  static final RegExp _totalKeywords = RegExp(
    r'^\s*(grand\s+|nett?\s+)?(total|jumlah|amount\s+due)\b',
    caseSensitive: false,
  );

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

  /// Upper bound on a `qty x unit price` multiplication — beyond this the
  /// "quantity" is far more likely to be something misread.
  static const int _maxQuantity = 999;

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

    // The numeric run currently being accumulated, plus the positions in
    // it that were preceded by a "x"/"@" multiplication marker.
    final run = <String>[];
    final multipliedAt = <int>{};

    void flushRun() {
      if (run.isEmpty) return;
      final tokens = List.of(run);
      final markers = Set.of(multipliedAt);
      run.clear();
      multipliedAt.clear();

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

      // Everything after the line amount belongs to the *next* item — most
      // often its leading quantity, in the "2 Nasi Goreng 40.000" layout
      // where OCR gives no line break the parser can rely on. Hand it back
      // instead of letting it swallow this item.
      run.addAll(tokens.sublist(amountIndex + 1));

      // "2 x 25.000" with no separate amount column: the price of the line
      // is quantity times unit price, not the unit price.
      var price = amount;
      if (markers.contains(amountIndex) && amountIndex >= 1) {
        final quantity = _quantityFrom(tokens[amountIndex - 1]);
        if (quantity != null) {
          final multiplied = quantity * amount;
          if (multiplied <= _maxAmount) price = multiplied;
        }
      }

      final name = nameTokens.join(' ').trim();
      if (name.isNotEmpty) {
        items.add(BillItem(id: IdGenerator.next('item'), name: name, price: price));
      } else if (amountIndex > 0 && _digitsOnly(tokens.first).length >= _productCodeDigits) {
        // No readable description, but a goods code and an amount in the
        // right columns is strong evidence of a real purchased line. Keep
        // it as an unnamed item rather than silently dropping money — the
        // review screen (FR-2.3) is where the user names it.
        items.add(BillItem(
          id: IdGenerator.next('item'),
          name: 'Item ${items.length + 1}',
          price: price,
        ));
      }

      nameTokens.clear();
      nameLine = null;
    }

    void barrier() {
      flushRun();
      run.clear();
      multipliedAt.clear();
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

      final lineTokens = line
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty)
          .expand(_splitGluedToken)
          .toList();

      // Checked before _skipLine on purpose: "Total Bayar" would otherwise
      // be discarded as a payment line and the printed total lost.
      if (_totalKeywords.hasMatch(line)) {
        barrier();
        final numerics = lineTokens.map(_asNumeric).whereType<String>().toList();
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
        final numeric = _asNumeric(token);
        if (numeric != null) {
          if (awaitingTotalAmount) {
            final value = _amountFrom(numeric);
            if (value != null) {
              total ??= value;
              awaitingTotalAmount = false;
              continue;
            }
          }
          run.add(numeric);
          continue;
        }

        // A bare currency marker ("Rp") or a dotted leader is punctuation:
        // it neither starts a name nor ends a numeric run.
        if (_isIgnorable(token)) continue;

        // "x"/"@" between numbers is an operator, not the start of a
        // product name — without this, "3 x 3.500  10.500" printed under
        // its description would name the item "x".
        if (run.isNotEmpty && _multiplier.hasMatch(token)) {
          multipliedAt.add(run.length);
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
        // "1." leading a numbered menu line is an ordinal, not the first
        // word of the dish.
        if (nameTokens.isEmpty && _ordinalPrefix.hasMatch(token)) continue;
        nameTokens.add(token);
      }
    }

    flushRun();

    return ParsedReceipt(items: items, detectedTotal: total);
  }

  /// Splits a token that glues a quantity or a marker onto its neighbour
  /// (`2x`, `@25.000`) into its parts, so neither ends up inside an item
  /// name. Every other token is passed through untouched.
  static Iterable<String> _splitGluedToken(String token) {
    final quantity = _gluedQuantity.firstMatch(token);
    if (quantity != null) return [quantity.group(1)!, 'x'];

    final unitPrice = _gluedUnitPrice.firstMatch(token);
    if (unitPrice != null && _asNumeric(unitPrice.group(1)!) != null) {
      return ['@', unitPrice.group(1)!];
    }

    return [token];
  }

  /// The numeric core of [token] if it is a number once currency
  /// decoration is removed (`Rp25.000`, `25.000,-`), else null.
  static String? _asNumeric(String token) {
    var stripped = token.replaceFirst(_currencyPrefix, '');
    stripped = stripped.replaceFirst(_amountSuffix, '');
    return _numericToken.hasMatch(stripped) ? stripped : null;
  }

  static bool _isIgnorable(String token) {
    if (!_hasAlphanumeric.hasMatch(token)) return true;
    final withoutCurrency = token.replaceFirst(_currencyPrefix, '');
    return !_hasAlphanumeric.hasMatch(withoutCurrency);
  }

  static const int _maxAmount = 999999999;

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

  /// [token] read as a quantity: a small plain integer, below the
  /// threshold where a number would instead be a price.
  static int? _quantityFrom(String token) {
    if (!RegExp(r'^\d{1,3}$').hasMatch(token)) return null;
    final value = int.tryParse(token);
    if (value == null || value < 2 || value > _maxQuantity) return null;
    return value;
  }

  static String _digitsOnly(String raw) => raw.replaceAll(RegExp(r'[^0-9]'), '');
}
