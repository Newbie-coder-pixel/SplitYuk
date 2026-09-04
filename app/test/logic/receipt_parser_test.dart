import 'package:flutter_test/flutter_test.dart';
import 'package:splityuk_app/logic/receipt_parser.dart';

void main() {
  group('ReceiptParser', () {
    test('extracts line items with grouped thousands amounts', () {
      const text = 'Nasi Goreng Spesial 56.000\nEs Teh Manis 18.000';
      final result = ReceiptParser.parse(text);

      expect(result.items, hasLength(2));
      expect(result.items[0].name, 'Nasi Goreng Spesial');
      expect(result.items[0].price, 56000);
      expect(result.items[1].price, 18000);
    });

    test('captures a total line separately from items', () {
      const text = 'Sate Ayam 35.000\nTotal 35.000';
      final result = ReceiptParser.parse(text);

      expect(result.items, hasLength(1));
      expect(result.detectedTotal, 35000);
    });

    test('skips subtotal/tax/service lines so they are not mistaken for items', () {
      const text = 'Kerupuk 4.000\nSubtotal 4.000\nPPN 10% 400\nService 5% 200\nTotal 4.600';
      final result = ReceiptParser.parse(text);

      expect(result.items, hasLength(1));
      expect(result.items.single.name, 'Kerupuk');
      expect(result.detectedTotal, 4600);
    });

    test('ignores lines with no trailing amount', () {
      const text = 'Warung Sedap Malam\nJl. Sabang No. 14\nNasi Goreng 20.000';
      final result = ReceiptParser.parse(text);

      expect(result.items, hasLength(1));
      expect(result.items.single.name, 'Nasi Goreng');
    });
  });
}
