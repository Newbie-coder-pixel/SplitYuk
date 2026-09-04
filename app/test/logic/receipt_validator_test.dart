import 'package:flutter_test/flutter_test.dart';
import 'package:splityuk_app/logic/receipt_parser.dart';
import 'package:splityuk_app/logic/receipt_validator.dart';

void main() {
  group('ReceiptValidator', () {
    test('accepts a genuine receipt', () {
      const text = 'WARUNG SEDAP MALAM\nNasi Goreng Spesial 56.000\n'
          'Es Teh Manis 18.000\nSubtotal 74.000\nPPN 10% 7.400\nTotal 81.400';
      final parsed = ReceiptParser.parse(text);

      final result = ReceiptValidator.validate(text, parsed);

      expect(result.isValid, isTrue);
      expect(result.reason, isNull);
    });

    test('rejects a photo with almost no recognizable text', () {
      const text = '  \n  ';
      final parsed = ReceiptParser.parse(text);

      final result = ReceiptValidator.validate(text, parsed);

      expect(result.isValid, isFalse);
      expect(result.reason, contains("couldn't read enough text"));
    });

    test('rejects a photo with plenty of text but no prices', () {
      const text = 'A beautiful sunset over the beach in Bali, taken with my '
          'new camera during our trip last December with the whole family.';
      final parsed = ReceiptParser.parse(text);

      final result = ReceiptValidator.validate(text, parsed);

      expect(result.isValid, isFalse);
      expect(result.reason, contains("doesn't look like a receipt"));
    });

    test('rejects a photo with numbers but no receipt keywords', () {
      // e.g. a photo of a scoreboard, a phone number, an address plaque.
      const text = 'Jalan Merdeka No. 17\nBlok C-45, RT 003 RW 012\n'
          'Kode Pos 12345\nTelp: 021-5551234';
      final parsed = ReceiptParser.parse(text);

      final result = ReceiptValidator.validate(text, parsed);

      expect(result.isValid, isFalse);
    });

    test('accepts a sparse receipt as long as a total and keyword are present', () {
      const text = 'Kopi Kenangan\nTotal Rp 25.000';
      final parsed = ReceiptParser.parse(text);

      final result = ReceiptValidator.validate(text, parsed);

      expect(result.isValid, isTrue);
    });
  });
}
