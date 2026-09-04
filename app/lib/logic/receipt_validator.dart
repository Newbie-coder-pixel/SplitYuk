import 'receipt_parser.dart';

class ReceiptValidationResult {
  const ReceiptValidationResult({required this.isValid, this.reason});

  final bool isValid;
  final String? reason;
}

/// Guards against feeding a non-receipt photo into the split flow.
///
/// There is no real image classifier here — just OCR text run through a
/// heuristic — so this is a filter, not a guarantee. It exists to catch the
/// common case (a random photo with no price-like content at all), not to
/// perfectly distinguish every receipt from every non-receipt.
class ReceiptValidator {
  ReceiptValidator._();

  static const int _minRawTextLength = 10;

  static final RegExp _receiptKeywords = RegExp(
    r'\b(total|subtotal|tax|pajak|ppn|pb1|service|svc|diskon|discount|cash|'
    r'tunai|kembali|change|qty|nota|struk|invoice|receipt|bayar|jumlah|harga|'
    r'rp|idr)\b',
    caseSensitive: false,
  );

  static ReceiptValidationResult validate(String rawText, ParsedReceipt parsed) {
    final trimmed = rawText.trim();

    if (trimmed.length < _minRawTextLength) {
      return const ReceiptValidationResult(
        isValid: false,
        reason: "We couldn't read enough text from that photo. Make sure the "
            "receipt is in focus, flat, and well-lit, then try again.",
      );
    }

    final hasPriceSignal = parsed.items.isNotEmpty || parsed.detectedTotal != null;
    if (!hasPriceSignal) {
      return const ReceiptValidationResult(
        isValid: false,
        reason: "This doesn't look like a receipt — no item prices or total "
            "were found in that photo.",
      );
    }

    if (!_receiptKeywords.hasMatch(rawText)) {
      return const ReceiptValidationResult(
        isValid: false,
        reason: "This doesn't look like a receipt. Try again with a clearer "
            "photo of your bill.",
      );
    }

    return const ReceiptValidationResult(isValid: true);
  }
}
