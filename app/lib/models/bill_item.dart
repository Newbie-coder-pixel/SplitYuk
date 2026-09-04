/// A single line item on the bill.
///
/// [price] is the item's line total in whole Rupiah (i.e. quantity already
/// multiplied in), matching how both the OCR output and manual-entry rows
/// present a line: "Nasi goreng spesial x2 — Rp 56.000", not a unit price.
class BillItem {
  BillItem({
    required this.id,
    required this.name,
    required this.price,
    int? quantity,
    Set<String>? assignedMemberIds,
  })  : quantity = quantity ?? 1,
        assignedMemberIds = assignedMemberIds ?? <String>{};

  final String id;
  String name;
  int price;
  int quantity;

  /// Members sharing this item. Empty means "unassigned" — PRD §11 rule 1
  /// blocks proceeding to notifications while any item is unassigned.
  final Set<String> assignedMemberIds;

  bool get isAssigned => assignedMemberIds.isNotEmpty;

  /// This member's exact (unrounded) share of this item's price, split
  /// evenly across everyone assigned to it. Rounding only happens once,
  /// at the final per-member total — see SplitCalculator.
  double shareFor(String memberId) {
    if (!assignedMemberIds.contains(memberId)) return 0;
    return price / assignedMemberIds.length;
  }

  /// Called when a member is removed from the session (PRD §11 rule 3):
  /// their assigned items must revert to unassigned, never disappear.
  void unassignMember(String memberId) {
    assignedMemberIds.remove(memberId);
  }

  BillItem copyWith({String? name, int? price, int? quantity}) {
    return BillItem(
      id: id,
      name: name ?? this.name,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
      assignedMemberIds: Set.of(assignedMemberIds),
    );
  }
}
