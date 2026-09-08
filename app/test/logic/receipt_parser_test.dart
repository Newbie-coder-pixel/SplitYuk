import 'package:flutter_test/flutter_test.dart';
import 'package:splityuk_app/logic/receipt_parser.dart';

/// The item name/price pairs a parse produced, as a plain map — the shape
/// these format tests actually care about.
Map<String, int> itemsOf(String text) {
  return {for (final item in ReceiptParser.parse(text).items) item.name: item.price};
}

void main() {
  // Every receipt layout below came from a different real-world POS
  // convention. They are the regression net for the thing that makes this
  // parser worth having at all: it must not be tuned to one shop's format.
  group('ReceiptParser — across differing receipt formats', () {
    test('warung: quantity printed in front of the name', () {
      const text = 'Warung Bu Ani\n'
          '2 Nasi Goreng          40.000\n'
          '1 Es Teh Manis          8.000\n'
          'Total                  48.000';

      expect(itemsOf(text), {'Nasi Goreng': 40000, 'Es Teh Manis': 8000});
      expect(ReceiptParser.parse(text).detectedTotal, 48000);
    });

    test('restaurant: unit price x quantity alongside a line total', () {
      const text = 'Nasi Goreng    2 x 25.000    50.000\n'
          'Es Teh         3 x  6.000    18.000';

      expect(itemsOf(text), {'Nasi Goreng': 50000, 'Es Teh': 18000});
    });

    test('restaurant: unit price x quantity with no line total column', () {
      // The line's real cost is the multiplication — reading the unit
      // price as the price would undercharge everyone at the table.
      const text = 'Nasi Goreng    2 x 25.000\nEs Teh         3 x 6.000';

      expect(itemsOf(text), {'Nasi Goreng': 50000, 'Es Teh': 18000});
    });

    test('quantity glued to the multiplier ("2x Nasi Goreng")', () {
      const text = '2x Nasi Goreng          50.000\n1x Es Jeruk              8.000';

      expect(itemsOf(text), {'Nasi Goreng': 50000, 'Es Jeruk': 8000});
    });

    test('unit price glued to the marker ("2 @25.000")', () {
      const text = 'Ayam Geprek     2 @25.000     50.000\nTeh Botol       1 @5.000       5.000';

      expect(itemsOf(text), {'Ayam Geprek': 50000, 'Teh Botol': 5000});
    });

    test('unit price and line total in adjacent columns, no marker', () {
      const text = 'Nasi Goreng      2    25.000    50.000\nEs Teh           3     6.000    18.000';

      expect(itemsOf(text), {'Nasi Goreng': 50000, 'Es Teh': 18000});
    });

    test('minimarket: description above, "qty x unit  total" below', () {
      const text = 'INDOMIE GORENG\n'
          '  3 x 3.500              10.500\n'
          'AQUA 600ML\n'
          '  2 x 4.000               8.000';

      expect(itemsOf(text), {'INDOMIE GORENG': 10500, 'AQUA 600ML': 8000});
    });

    test('cafe: quantity in a left-hand column', () {
      const text = 'QTY ITEM              AMOUNT\n'
          '1   Americano         25.000\n'
          '2   Croissant         36.000';

      expect(itemsOf(text), {'Americano': 25000, 'Croissant': 36000});
    });

    test('amounts marked with Rp, attached or detached', () {
      const text = 'Ayam Bakar        Rp25.000\nNasi Putih        Rp 6.000\nTOTAL             Rp31.000';

      expect(itemsOf(text), {'Ayam Bakar': 25000, 'Nasi Putih': 6000});
      expect(ReceiptParser.parse(text).detectedTotal, 31000);
    });

    test('amounts with the Indonesian ",-" suffix', () {
      const text = 'Kopi Susu         18.000,-\nRoti Bakar        22.000,-\nTotal             40.000,-';

      expect(itemsOf(text), {'Kopi Susu': 18000, 'Roti Bakar': 22000});
      expect(ReceiptParser.parse(text).detectedTotal, 40000);
    });

    test('menu-style dotted leaders between name and price', () {
      const text = 'Mie Ayam .............. 20.000\nPangsit ............... 10.000';

      expect(itemsOf(text), {'Mie Ayam': 20000, 'Pangsit': 10000});
    });

    test('numbered menu lines', () {
      const text = '1. Nasi Goreng          25.000\n2. Ayam Bakar           35.000';

      expect(itemsOf(text), {'Nasi Goreng': 25000, 'Ayam Bakar': 35000});
    });

    test('names containing their own digits are not mistaken for prices', () {
      const text = 'Coca Cola 330ml        15.000\n7UP Kaleng             14.000';

      expect(itemsOf(text), {'Coca Cola 330ml': 15000, '7UP Kaleng': 14000});
    });

    test('prices printed without a thousands separator', () {
      const text = 'Gorengan                 5000\nTeh Anget                3000\nJumlah                   8000';

      expect(itemsOf(text), {'Gorengan': 5000, 'Teh Anget': 3000});
      expect(ReceiptParser.parse(text).detectedTotal, 8000);
    });

    test('English-language invoice with an "Amount Due" total', () {
      const text = 'DESCRIPTION            AMOUNT\n'
          'Grilled Chicken        85.000\n'
          'Caesar Salad           65.000\n'
          'Amount Due            150.000';

      expect(itemsOf(text), {'Grilled Chicken': 85000, 'Caesar Salad': 65000});
      expect(ReceiptParser.parse(text).detectedTotal, 150000);
    });

    test('a per-item discount line is captured as a discount, not an item', () {
      const text = 'Kopi Susu               25.000\n'
          '  Diskon Member         -5.000\n'
          'Roti Bakar              22.000';
      final result = ReceiptParser.parse(text);

      expect(itemsOf(text), {'Kopi Susu': 25000, 'Roti Bakar': 22000});
      expect(result.discount, 5000);
      expect(result.reconciledTotal, 42000);
    });

    test('reads the printed quantity, wherever the layout puts it', () {
      // Left column, right column, glued to the multiplier, or absent —
      // the quantity is what a person scans down to check the list
      // against the paper, so it has to survive all four.
      Map<String, int> quantitiesOf(String text) => {
            for (final item in ReceiptParser.parse(text).items) item.name: item.quantity,
          };

      expect(
        quantitiesOf('2 Nasi Goreng 40.000\n1 Es Teh Manis 8.000'),
        {'Nasi Goreng': 2, 'Es Teh Manis': 1},
      );
      expect(
        quantitiesOf('Paper Bag Red M\n20154550101063600    2    7200'),
        {'Paper Bag Red M': 2},
      );
      expect(
        quantitiesOf('3x Indomie Goreng          10.500'),
        {'Indomie Goreng': 3},
      );
      expect(
        quantitiesOf('Nasi Goreng    2 x 25.000    50.000'),
        {'Nasi Goreng': 2},
      );
      expect(
        quantitiesOf('Kopi Susu 25.000'),
        {'Kopi Susu': 1},
        reason: 'a line with no quantity column means one of it',
      );
    });

    test('a quantity is never mistaken for the price, or the price for a quantity', () {
      final result = ReceiptParser.parse('Paper Bag Red M\n20154550101063600    2    7200');

      expect(result.items.single.price, 7200);
      expect(result.items.single.quantity, 2);
    });

    test('tax and service charged on top are captured as amounts', () {
      const text = 'Nasi Goreng             50.000\n'
          'Subtotal                50.000\n'
          'PPN 11%                  5.500\n'
          'Service 5%               2.500\n'
          'Total                   58.000';
      final result = ReceiptParser.parse(text);

      expect(result.tax, 5500);
      expect(result.serviceCharge, 2500);
      expect(result.reconciledTotal, 58000);
      expect(result.reconciledTotal, result.detectedTotal);
    });

    test('a tax rate with no money on the line is not read as an amount', () {
      // "TAX-Excl  9" is a percentage, and on that receipt the printed
      // prices already include the tax — adding 9 (or 9%) would be wrong.
      const text = 'Nasi Goreng             50.000\nTAX-Excl                     9\nTotal 50.000';
      final result = ReceiptParser.parse(text);

      expect(result.tax, 0);
      expect(result.reconciledTotal, result.detectedTotal);
    });

    test('multiple discount lines accumulate', () {
      const text = 'Kopi Susu               25.000\n'
          'Diskon Member            5.000\n'
          'Voucher                  2.000\n'
          'Total                   18.000';
      final result = ReceiptParser.parse(text);

      expect(result.discount, 7000);
      expect(result.reconciledTotal, 18000);
    });

    test('fast-food bill: tax already inside the prices is not added again', () {
      // A real McDonald's Indonesia bill. Everything below "Eat-In Tot" is
      // the tax breakdown *of that same figure*: Net Sales 59.546 is the
      // pre-tax base and PBJT 5.954 the tax on it, and 59.546 + 5.954 =
      // 65.500, the amount actually paid. Adding PBJT on top would bill
      // the table Rp 71.454 for a Rp 65.500 meal; reading Net Sales as the
      // total would under-bill them by the whole tax.
      const text = 'QTY ITEM                    TOTAL\n'
          '  2 French Fries Medium     48,000\n'
          '  1 McFlurry Matcha OREO    17,500\n'
          'Eat-In Tot(trmasuk PAJAK)   65,500\n'
          'Cashless BCA                65,500\n'
          'Change                           0\n'
          'Net Sales                   59,546\n'
          'DPP PBJT                    59,546\n'
          'PBJT              10%        5,954';
      final result = ReceiptParser.parse(text);

      expect(itemsOf(text), {'French Fries Medium': 48000, 'McFlurry Matcha OREO': 17500});
      expect(result.detectedTotal, 65500, reason: 'the amount paid, not Net Sales');
      expect(result.tax, 0, reason: 'PBJT is inside the price, never added on top');
      expect(result.includedTax, 5954, reason: 'but it is reported, not silently dropped');
      expect(result.reconciledTotal, 65500);
      expect(result.reconciledTotal, result.detectedTotal);
    });

    test('tax genuinely added on top is still added', () {
      // The mirror image: here the items alone do *not* reach the printed
      // total, so the tax is a real addition and must stay one.
      const text = 'Nasi Goreng             50.000\n'
          'PPN 11%                  5.500\n'
          'Total                   55.500';
      final result = ReceiptParser.parse(text);

      expect(result.tax, 5500);
      expect(result.includedTax, 0);
      expect(result.reconciledTotal, 55500);
    });

    test('"Net Sales" is never mistaken for the amount paid', () {
      const text = 'Kopi Susu 25.000\nNet Sales 22.500\nTotal 25.000';

      expect(ReceiptParser.parse(text).detectedTotal, 25000);
    });

    test('a "Total Item" count line is not the total', () {
      const text = 'Kopi Susu 25.000\nTotal Item 1\nTotal Bayar 25.000';

      expect(ReceiptParser.parse(text).detectedTotal, 25000);
    });

    test('total written in caps with a colon', () {
      const text = 'Bakso Urat              30.000\nTOTAL:                  30.000';

      expect(ReceiptParser.parse(text).detectedTotal, 30000);
    });
  });

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

    test('splits items when OCR merges a code row with the next description', () {
      // The layout that broke the old parser: OCR joined each amount row
      // with the following product's name, so no line ended in a price and
      // every item but one was lost.
      const text = 'Paper Bag Red S\n'
          '20154549101003000 1 3000 Flower Language Series Succulent\n'
          '20130911110239900 1 39900 MIKKO Collection Ankle Socks (1\n'
          '20162055101052900 1 29900';
      final result = ReceiptParser.parse(text);

      expect(result.items.map((i) => i.name), [
        'Paper Bag Red S',
        'Flower Language Series Succulent',
        'MIKKO Collection Ankle Socks (1',
      ]);
      expect(result.items.map((i) => i.price), [3000, 39900, 29900]);
    });

    test('handles an item whose code, qty and amount are split across lines', () {
      const text = 'Harry Potter Plastic Tumbler wit\n'
          '20184457101091799001\n'
          '1\n'
          '179900';
      final result = ReceiptParser.parse(text);

      expect(result.items, hasLength(1));
      expect(result.items.single.name, 'Harry Potter Plastic Tumbler wit');
      expect(result.items.single.price, 179900);
    });

    test('never reads a goods code or a quantity as the price', () {
      const text = 'Cinnamoroll Lotion Bottle 45ml\n20153632101017900    1    17900';
      final result = ReceiptParser.parse(text);

      expect(result.items.single.price, 17900);
    });

    test('drops a coded line whose amount column did not survive OCR', () {
      const text = 'Paper Bag Red S\n20154549101003000    1';
      final result = ReceiptParser.parse(text);

      expect(result.items, isEmpty);
    });

    test('keeps a coded, priced line that lost its description', () {
      // Losing the name is recoverable on the review screen; silently
      // dropping the money is not.
      const text = '20154549101003000    1    3000';
      final result = ReceiptParser.parse(text);

      expect(result.items, hasLength(1));
      expect(result.items.single.price, 3000);
    });

    test('takes only the last line of stacked text as an item name', () {
      const text = 'Toko Serba Ada\nJl. Sabang No. 14\nPaper Bag Red S\n'
          '20154549101003000    1    3000';
      final result = ReceiptParser.parse(text);

      expect(result.items.single.name, 'Paper Bag Red S');
    });

    test('reads a total whose amount landed on the next line', () {
      const text = 'Item A\n1000000    1    50000\nTOTAL\n260940.00';
      final result = ReceiptParser.parse(text);

      expect(result.detectedTotal, 260940);
    });

    test('does not treat an item-count line as the total', () {
      const text = 'Kerupuk 4.000\nTotal Item 8\nTotal 4.000';
      final result = ReceiptParser.parse(text);

      expect(result.detectedTotal, 4000);
    });

    test('nothing below the summary section is ever an item', () {
      // From a real scan of a photographed receipt: OCR split "MemberCode"
      // from its value and "Score Get:" from its own, leaving loose
      // label/number pairs below the total. Those became items of
      // Rp 13.045 and Rp 260.940 — money nobody spent, added to everyone's
      // share.
      const text = 'Paper Bag Red S\n'
          '20154549101003000    1    3000\n'
          'TOTAL                     3000\n'
          'Score Get\n'
          '13045\n'
          'Current Point\n'
          '10785\n'
          '819*****412\n'
          '260940';
      final result = ReceiptParser.parse(text);

      expect(itemsOf(text), {'Paper Bag Red S': 3000});
      expect(result.detectedTotal, 3000);
    });

    test('a stray column header is never used as an item name', () {
      // OCR routinely lands "Amt" on its own line, away from the rest of
      // the "Goods code  U/P  Qty  Amt" heading — so the whole-line
      // metadata filter no longer catches it and it named the item below.
      const text = 'Goods code    U/P  Qty\n'
          'Amt\n'
          'Paper Bag Red S\n'
          '20154549101003000    1    3000';

      expect(itemsOf(text), {'Paper Bag Red S': 3000});
    });

    test('a masked loyalty code is never an item, named or unnamed', () {
      const text = 'Kopi Susu 25.000\nMemberCode\n819*****412\n260940';
      final result = ReceiptParser.parse(text);

      expect(result.items.map((i) => i.name), ['Kopi Susu']);
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

        // And the parser must reach that reconciliation on its own: the
        // discount has to be picked up, or every member is billed for the
        // undiscounted 537.600 and the review screen cries mismatch.
        expect(result.discount, 276660);
        expect(result.tax, 0, reason: 'this receipt prints tax-inclusive prices');
        expect(result.serviceCharge, 0);
        expect(result.reconciledTotal, result.detectedTotal);
      },
    );
  });
}
