/// What a single member owes, per [SplitResult].
class MemberShare {
  const MemberShare({
    required this.memberId,
    required this.itemSubtotal,
    required this.discountShare,
    required this.taxShare,
    required this.serviceShare,
    required this.total,
  });

  final String memberId;

  /// Pre-rounding, informational only (used for breakdown display).
  final double itemSubtotal;

  final int discountShare;
  final int taxShare;
  final int serviceShare;

  /// The final, rounded amount this member owes. Guaranteed (by
  /// [SplitCalculator]) to sum exactly to [SplitResult.total] across all
  /// members — this is the number that gets sent to them.
  final int total;
}

/// The outcome of running [SplitCalculator.calculate].
class SplitResult {
  const SplitResult({
    required this.subtotal,
    required this.discountAmount,
    required this.taxAmount,
    required this.serviceAmount,
    required this.total,
    required this.perMember,
  });

  final int subtotal;
  final int discountAmount;
  final int taxAmount;
  final int serviceAmount;
  final int total;

  /// Keyed by member id.
  final Map<String, MemberShare> perMember;

  int get sumOfMemberTotals =>
      perMember.values.fold<int>(0, (sum, share) => sum + share.total);

  /// True when every member's share sums exactly to [total]. This should
  /// always be true for any result produced by [SplitCalculator] — exposed
  /// so callers (and tests) can assert it rather than trust it blindly.
  bool get reconciles => sumOfMemberTotals == total;
}
