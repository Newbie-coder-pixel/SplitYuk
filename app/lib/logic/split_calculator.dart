import '../models/bill.dart';
import '../models/member.dart';
import '../models/split_mode.dart';
import 'split_result.dart';
import 'split_validator.dart';

/// Turns a [Bill] + member roster into a per-member [SplitResult].
///
/// Core invariant, true for every mode: the sum of every member's final
/// [MemberShare.total] always equals [Bill.total] exactly — no member ever
/// owes a fractional Rupiah, and no Rupiah is ever lost or invented to
/// rounding. Any rounding remainder is charged entirely to the bill
/// creator (FR-5.5), as a single adjustment, never spread silently across
/// everyone.
///
/// All intermediate math (item-splitting, proportional tax/service) is
/// kept as exact `double` arithmetic and rounded only once, at the very
/// end, per member — rounding at multiple stages would let small errors
/// compound and drift the total away from [Bill.total].
class SplitCalculator {
  SplitCalculator._();

  static SplitResult calculate(Bill bill, List<Member> members) {
    final errors = SplitValidator.validate(bill, members);
    if (errors.isNotEmpty) {
      throw ArgumentError(
        'Cannot calculate a split for an invalid bill: ${errors.join(' ')}',
      );
    }

    final creator = members.firstWhere((m) => m.isCreator);

    switch (bill.splitMode) {
      case SplitMode.itemized:
        return _calculateItemized(bill, members, creator);
      case SplitMode.equal:
        return _calculateEqual(bill, members, creator);
      case SplitMode.percentage:
        return _calculatePercentage(bill, members, creator);
      case SplitMode.customAmount:
        return _calculateCustomAmount(bill, members, creator);
    }
  }

  static SplitResult _calculateItemized(
    Bill bill,
    List<Member> members,
    Member creator,
  ) {
    final subtotal = bill.subtotal;
    final discountAmount = bill.discountAmount;
    final taxAmount = bill.taxAmount;
    final serviceAmount = bill.serviceAmount;
    final total = bill.total;
    final memberCount = members.length;

    final itemSubtotalByMember = <String, double>{
      for (final m in members) m.id: 0,
    };
    for (final item in bill.items) {
      for (final memberId in item.assignedMemberIds) {
        if (!itemSubtotalByMember.containsKey(memberId)) continue;
        itemSubtotalByMember[memberId] =
            itemSubtotalByMember[memberId]! + item.shareFor(memberId);
      }
    }

    final shares = <String, MemberShare>{};
    var sumRounded = 0;

    for (final m in members) {
      final itemSubtotal = itemSubtotalByMember[m.id] ?? 0;

      final double discountShareRaw;
      final double taxShareRaw;
      final double serviceShareRaw;
      if (bill.splitExtrasEqually) {
        discountShareRaw = discountAmount / memberCount;
        taxShareRaw = taxAmount / memberCount;
        serviceShareRaw = serviceAmount / memberCount;
      } else {
        final proportion = subtotal == 0 ? 0.0 : itemSubtotal / subtotal;
        discountShareRaw = discountAmount * proportion;
        taxShareRaw = taxAmount * proportion;
        serviceShareRaw = serviceAmount * proportion;
      }

      final rawTotal =
          itemSubtotal - discountShareRaw + taxShareRaw + serviceShareRaw;
      final roundedTotal = rawTotal.round();
      sumRounded += roundedTotal;

      shares[m.id] = MemberShare(
        memberId: m.id,
        itemSubtotal: itemSubtotal,
        discountShare: discountShareRaw.round(),
        taxShare: taxShareRaw.round(),
        serviceShare: serviceShareRaw.round(),
        total: roundedTotal,
      );
    }

    _reconcileRoundingToCreator(shares, creator.id, total, sumRounded);

    return SplitResult(
      subtotal: subtotal,
      discountAmount: discountAmount,
      taxAmount: taxAmount,
      serviceAmount: serviceAmount,
      total: total,
      perMember: shares,
    );
  }

  static SplitResult _calculateEqual(
    Bill bill,
    List<Member> members,
    Member creator,
  ) {
    final total = bill.total;
    final n = members.length;
    final base = total ~/ n;
    final remainder = total - (base * n);

    final shares = <String, MemberShare>{
      for (final m in members)
        m.id: MemberShare(
          memberId: m.id,
          itemSubtotal: base.toDouble(),
          discountShare: 0,
          taxShare: 0,
          serviceShare: 0,
          total: base,
        ),
    };

    if (remainder != 0) {
      final c = shares[creator.id]!;
      shares[creator.id] = MemberShare(
        memberId: c.memberId,
        itemSubtotal: c.itemSubtotal,
        discountShare: c.discountShare,
        taxShare: c.taxShare,
        serviceShare: c.serviceShare,
        total: c.total + remainder,
      );
    }

    return _wholeBillResult(bill, total, shares);
  }

  static SplitResult _calculatePercentage(
    Bill bill,
    List<Member> members,
    Member creator,
  ) {
    final total = bill.total;
    final shares = <String, MemberShare>{};
    var sumRounded = 0;

    for (final m in members) {
      final pct = bill.percentageShares[m.id] ?? 0;
      final raw = total * (pct / 100);
      final rounded = raw.round();
      sumRounded += rounded;
      shares[m.id] = MemberShare(
        memberId: m.id,
        itemSubtotal: raw,
        discountShare: 0,
        taxShare: 0,
        serviceShare: 0,
        total: rounded,
      );
    }

    _reconcileRoundingToCreator(shares, creator.id, total, sumRounded);

    return _wholeBillResult(bill, total, shares);
  }

  static SplitResult _calculateCustomAmount(
    Bill bill,
    List<Member> members,
    Member creator,
  ) {
    final total = bill.total;
    final shares = <String, MemberShare>{
      for (final m in members)
        m.id: MemberShare(
          memberId: m.id,
          itemSubtotal: (bill.customAmounts[m.id] ?? 0).toDouble(),
          discountShare: 0,
          taxShare: 0,
          serviceShare: 0,
          total: bill.customAmounts[m.id] ?? 0,
        ),
    };

    return _wholeBillResult(bill, total, shares);
  }

  static void _reconcileRoundingToCreator(
    Map<String, MemberShare> shares,
    String creatorId,
    int total,
    int sumRounded,
  ) {
    final diff = total - sumRounded;
    if (diff == 0) return;
    final c = shares[creatorId]!;
    shares[creatorId] = MemberShare(
      memberId: c.memberId,
      itemSubtotal: c.itemSubtotal,
      discountShare: c.discountShare,
      taxShare: c.taxShare,
      serviceShare: c.serviceShare,
      total: c.total + diff,
    );
  }

  static SplitResult _wholeBillResult(
    Bill bill,
    int total,
    Map<String, MemberShare> shares,
  ) {
    return SplitResult(
      subtotal: bill.subtotal,
      discountAmount: bill.discountAmount,
      taxAmount: bill.taxAmount,
      serviceAmount: bill.serviceAmount,
      total: total,
      perMember: shares,
    );
  }
}
