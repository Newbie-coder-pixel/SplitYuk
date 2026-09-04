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

  group('ReceiptParser — real-world multi-line receipt layout', () {
    test('associates a two-line item (description, then code+qty+amount) correctly', () {
      const text = 'Paper Bag Red S\n'
          '20154549101003000    1    3000\n'
          'Flower Language Series Succulent\n'
          '20130911110239900    1    39900';
      final result = ReceiptParser.parse(text);

      expect(result.items, hasLength(2));
      expect(result.items[0].name, 'Paper Bag Red S');
      expect(result.items[0].price, 3000);
      expect(result.items[1].name, 'Flower Language Series Succulent');
      expect(result.items[1].price, 39900);
    });

    test('handles a code line with no space before the glued qty digit', () {
      const text = 'Harry Potter Plastic Tumbler wit\n'
          '20184457101091799001    179900';
      final result = ReceiptParser.parse(text);

      expect(result.items, hasLength(1));
      expect(result.items.single.name, 'Harry Potter Plastic Tumbler wit');
      expect(result.items.single.price, 179900);
    });

    test('reads a total printed with a decimal-style ".00" tail', () {
      const text = 'Item A\n1000000    1    50000\nTOTAL                260940.00';
      final result = ReceiptParser.parse(text);

      expect(result.detectedTotal, 260940);
    });

    test('ignores POS metadata (serial/cashier/member/score/date lines)', () {
      const text = 'Serial No.:202608030070\n'
          'POS NO.:IDK5a\n'
          'Cashier:IDK505[IDK505]\n'
          '------------Sales------------\n'
          'Goods code    U/P  Qty  Amt\n'
          'Paper Bag Red S\n'
          '20154549101003000    1    3000\n'
          'Score Get:             13045\n'
          'Current Point         10785.000\n'
          'MemberCode          819*****412\n'
          'Date:2026-08-03 16:58:23';
      final result = ReceiptParser.parse(text);

      expect(result.items, hasLength(1));
      expect(result.items.single.name, 'Paper Bag Red S');
    });

    test('does not misread a masked member code as a price', () {
      const text = 'MemberCode          819*****412';
      final result = ReceiptParser.parse(text);

      expect(result.items, isEmpty);
      expect(result.detectedTotal, isNull);
    });

    test('does not attribute an unlabeled bare number to any item', () {
      const text = 'TAX-Excl                    9\n235081.10\n25858.90';
      final result = ReceiptParser.parse(text);

      expect(result.items, isEmpty);
    });

    test(
      'end-to-end: the exact receipt that previously produced garbage items',
      () {
        const text = '''
Serial No.:202608030070
POS NO.:IDK5a
Cashier:IDK505[IDK505]
------------Sales------------
Goods code    U/P  Qty  Amt
Paper Bag Red S
20154549101003000    1    3000
Flower Language Series Succulent
20130911110239900    1    39900
MIKKO Collection Ankle Socks (1
20162055101052900    1    29900
MIKKO Dress Series Drip Glue Des
20164801101067990   1    79900
Cinnamoroll Lotion Bottle 45ml
20153632101017900   1    17900
Paper Bag Red M
20154550101063600    2    7200
Harry Potter Plastic Tumbler wit
20184457101091799001    179900
Harry Potter Plastic Tumbler wit
20184457111061799001    179900
------------------------------
TAX-Excl                    9
                      235081.10
                       25858.90
Discount Price          276,660
TOTAL                260940.00
Score Get:             13045
Current Point         10785.000
MemberCode          819*****412
------------------------------
BCA Rp                 260,940
Change                       0
Date:2026-08-03 16:58:23
------------------------------
We are looking for global
Cooperation.
Get in touch with us.
''';
        final result = ReceiptParser.parse(text);

        expect(result.detectedTotal, 260940);
        expect(result.items.map((i) => i.price), [
          3000,
          39900,
          29900,
          79900,
          17900,
          7200,
          179900,
          179900,
        ]);
        expect(
          result.items.map((i) => i.name),
          containsAllInOrder([
            'Paper Bag Red S',
            'Flower Language Series Succulent',
            'MIKKO Collection Ankle Socks (1',
            'MIKKO Dress Series Drip Glue Des',
            'Cinnamoroll Lotion Bottle 45ml',
            'Paper Bag Red M',
            'Harry Potter Plastic Tumbler wit',
            'Harry Potter Plastic Tumbler wit',
          ]),
        );
        final itemSum = result.items.fold<int>(0, (sum, i) => sum + i.price);
        // Sanity check independent of the parser: item sum (537600) minus
        // the printed "Discount Price" (276,660) equals the printed TOTAL
        // (260940) exactly — confirms the parsed amounts are the real ones.
        expect(itemSum, 537600);
        expect(itemSum - 276660, result.detectedTotal);
      },
    );
  });
}
