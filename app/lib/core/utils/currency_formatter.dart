import 'package:intl/intl.dart';

/// IDR is the only supported currency (PRD §6 assumption) and has no
/// subunits in everyday use, so amounts are always whole Rupiah.
class CurrencyFormatter {
  CurrencyFormatter._();

  static final NumberFormat _grouping = NumberFormat.decimalPattern('id_ID');

  /// e.g. 129950 -> "Rp 129.950"
  static String format(int amountInRupiah) {
    return 'Rp ${_grouping.format(amountInRupiah)}';
  }

  /// e.g. 129950 -> "129.950" (no currency prefix, for compact contexts).
  static String formatBare(int amountInRupiah) => _grouping.format(amountInRupiah);
}
