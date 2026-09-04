/// How the bill total is divided among members (FR-5.3, PRD §9.5).
enum SplitMode {
  /// Split by item assignment; tax/service distributed per item subtotal.
  itemized,

  /// The full bill total divided into equal shares.
  equal,

  /// Each member assigned a percentage; must sum to 100.
  percentage,

  /// Each member assigned an exact amount; must sum to the bill total.
  customAmount,
}

enum DiscountType { amount, percentage }

/// An optional discount/voucher (FR-3.2). [value] is either a flat Rupiah
/// amount or a percentage of the subtotal, per [type].
class DiscountConfig {
  const DiscountConfig({
    this.type = DiscountType.amount,
    this.value = 0,
  });

  final DiscountType type;
  final num value;

  bool get isZero => value <= 0;

  /// Resolves this discount to a flat Rupiah amount given a subtotal.
  int resolve(int subtotal) {
    if (isZero) return 0;
    final raw = type == DiscountType.amount
        ? value.toDouble()
        : subtotal * (value.toDouble() / 100);
    final clamped = raw.clamp(0, subtotal).toDouble();
    return clamped.round();
  }
}
