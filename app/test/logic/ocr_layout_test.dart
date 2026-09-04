import 'package:flutter_test/flutter_test.dart';
import 'package:splityuk_app/logic/ocr_layout.dart';

OcrTextLine line(String text, double left, double top, {double width = 200, double height = 20}) {
  return OcrTextLine(
    text: text,
    left: left,
    top: top,
    right: left + width,
    bottom: top + height,
  );
}

void main() {
  group('OcrLayout.toReadingOrder', () {
    test('rejoins a receipt that ML Kit split into a name column and an amount column', () {
      // This is the failure that made a real scan yield one garbage item:
      // ML Kit returned the descriptions/codes as one block and the
      // qty/amount column as another, so `RecognizedText.text` listed every
      // description first and every amount afterwards.
      final lines = [
        // Block 1 — left column, top to bottom.
        line('Paper Bag Red S', 40, 100),
        line('20154549101003000', 40, 130),
        line('Flower Language Series Succulent', 40, 160),
        line('20130911110239900', 40, 190),
        // Block 2 — right column, top to bottom.
        line('1    3000', 400, 131, width: 90),
        line('1    39900', 400, 191, width: 90),
      ];

      expect(
        OcrLayout.toReadingOrder(lines),
        'Paper Bag Red S\n'
        '20154549101003000 1    3000\n'
        'Flower Language Series Succulent\n'
        '20130911110239900 1    39900',
      );
    });

    test('orders fragments within a row left-to-right, not by block order', () {
      final lines = [
        line('179900', 400, 50, width: 80),
        line('1', 340, 50, width: 20),
        line('20184457101091799', 40, 50, width: 280),
      ];

      expect(OcrLayout.toReadingOrder(lines), '20184457101091799 1 179900');
    });

    test('keeps rows apart when they do not overlap vertically', () {
      final lines = [
        line('Cinnamoroll Lotion Bottle 45ml', 40, 100),
        line('20153632101017900 1 17900', 40, 128),
      ];

      expect(
        OcrLayout.toReadingOrder(lines),
        'Cinnamoroll Lotion Bottle 45ml\n20153632101017900 1 17900',
      );
    });

    test('groups a skewed row whose right end sits lower than its left end', () {
      // Photographing a receipt by hand always tilts it a little; the
      // amount at the right of a row can sit most of a line-height below
      // the description at its left. Chaining each fragment against its
      // left neighbour keeps them on one row anyway.
      final lines = [
        line('Paper Bag Red M', 40, 100, width: 150),
        line('2', 300, 108, width: 20),
        line('7200', 380, 115, width: 70),
      ];

      expect(OcrLayout.toReadingOrder(lines), 'Paper Bag Red M 2 7200');
    });

    test('does not let a zero-height box swallow the rest of the receipt', () {
      final lines = [
        OcrTextLine(text: 'glitch', left: 40, top: 100, right: 100, bottom: 100),
        line('Real Item', 40, 130),
        line('20154549101003000 1 3000', 40, 160),
      ];

      expect(
        OcrLayout.toReadingOrder(lines),
        'glitch\nReal Item\n20154549101003000 1 3000',
      );
    });

    test('ignores blank lines and returns empty for no input', () {
      expect(OcrLayout.toReadingOrder(const []), '');
      expect(OcrLayout.toReadingOrder([line('   ', 0, 0)]), '');
    });
  });
}
