/// Rebuilds the *visual* reading order of an OCR result from the geometry
/// of the recognized lines.
///
/// Why this exists: ML Kit's `RecognizedText.text` concatenates its
/// **blocks** in block order, and each block's lines within it. On a
/// receipt that is not what you want — ML Kit routinely splits a receipt
/// into several blocks (commonly one for the descriptions/goods codes and
/// another for the qty/amount column, or one block per visual section), so
/// the flat `.text` can emit every product name first and every price
/// later, or interleave them in an order that has nothing to do with how
/// the receipt reads on paper. Any line-based parser fed that string is
/// parsing noise.
///
/// So instead of trusting block order, this ignores blocks entirely,
/// takes every line's bounding box, and regroups the lines into the rows
/// they actually occupy on the paper: lines whose vertical extents overlap
/// belong to the same printed row, and within a row they are ordered
/// left-to-right.
///
/// Rows are chained against the *previously accepted line in the row*
/// rather than against the row's growing bounding box, so a receipt
/// photographed at a slight angle (where the right end of a row sits lower
/// than its left end) still groups correctly instead of splitting apart
/// halfway across.
library;

/// One OCR-recognized line plus where it sits in the image. Deliberately a
/// plain value type with no ML Kit import, so the layout logic can be unit
/// tested on the Dart VM — the ML Kit plugin itself is mobile-only.
class OcrTextLine {
  const OcrTextLine({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get height => (bottom - top).abs();
}

class OcrLayout {
  OcrLayout._();

  /// Two lines are treated as the same printed row when they overlap
  /// vertically by at least this fraction of the shorter line's height.
  /// Loose enough to survive skew and differing glyph heights across a
  /// row, tight enough not to merge two adjacent printed rows.
  static const double _rowOverlapRatio = 0.5;

  /// Regroups [lines] into visual rows and renders them as newline-
  /// separated text, one printed row per line, tokens left-to-right.
  static String toReadingOrder(List<OcrTextLine> lines) {
    final usable = lines.where((line) => line.text.trim().isNotEmpty).toList();
    if (usable.isEmpty) return '';

    usable.sort((a, b) {
      final byTop = a.top.compareTo(b.top);
      return byTop != 0 ? byTop : a.left.compareTo(b.left);
    });

    final rows = <List<OcrTextLine>>[];
    for (final line in usable) {
      final currentRow = rows.isEmpty ? null : rows.last;
      if (currentRow != null && _sameRow(currentRow.last, line)) {
        currentRow.add(line);
      } else {
        rows.add([line]);
      }
    }

    return rows.map((row) {
      final ordered = [...row]..sort((a, b) => a.left.compareTo(b.left));
      return ordered.map((line) => line.text.trim()).join(' ');
    }).join('\n');
  }

  static bool _sameRow(OcrTextLine a, OcrTextLine b) {
    final overlap = (a.bottom < b.bottom ? a.bottom : b.bottom) -
        (a.top > b.top ? a.top : b.top);
    if (overlap <= 0) return false;

    // A degenerate box (zero height) would otherwise swallow every line
    // that follows it into one giant row — treat it as its own row.
    final shorter = a.height < b.height ? a.height : b.height;
    if (shorter <= 0) return false;

    return overlap >= shorter * _rowOverlapRatio;
  }
}
