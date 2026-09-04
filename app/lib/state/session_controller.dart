import 'package:flutter/foundation.dart';

import '../core/utils/id_generator.dart';
import '../core/utils/temp_file_cleaner.dart';
import '../logic/split_calculator.dart';
import '../logic/split_result.dart';
import '../logic/split_validator.dart';
import '../models/bill.dart';
import '../models/bill_item.dart';
import '../models/member.dart';
import '../models/split_mode.dart';

/// The single source of truth for the active bill-splitting session.
///
/// Everything here lives in memory only, for the lifetime of this
/// controller — there is deliberately no persistence layer underneath it
/// (PRD §3). [resetSession] is the only way state is cleared, and it wipes
/// everything rather than archiving it anywhere.
class SessionController extends ChangeNotifier {
  Bill _bill = Bill();
  final List<Member> _members = [];

  Bill get bill => _bill;
  List<Member> get members => List.unmodifiable(_members);

  Member? get creator {
    for (final m in _members) {
      if (m.isCreator) return m;
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Session lifecycle
  // ---------------------------------------------------------------------

  void resetSession() {
    _bill = Bill();
    _members.clear();
    notifyListeners();
  }

  /// Explicit end-of-session cleanup (PRD §17): deletes any temp image
  /// files this session created on disk, then discards all bill/member
  /// state. Call this before [resetSession] whenever a session with a
  /// receipt photo or rendered summary is being closed.
  Future<void> closeSession() async {
    await TempFileCleaner.deleteIfExists(_bill.receiptImagePath);
    await TempFileCleaner.deleteIfExists(_bill.renderedSummaryImagePath);
    resetSession();
  }

  void startManualBill({required bool itemized}) {
    _bill = Bill(
      source: BillSource.manual,
      splitMode: itemized ? SplitMode.itemized : SplitMode.equal,
    );
    notifyListeners();
  }

  void startScannedBill({String? receiptImagePath, int? receiptPrintedTotal}) {
    _bill = Bill(
      source: BillSource.scan,
      splitMode: SplitMode.itemized,
      receiptImagePath: receiptImagePath,
      receiptPrintedTotal: receiptPrintedTotal,
    );
    notifyListeners();
  }

  void setTitle(String title) {
    _bill.title = title;
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Items
  // ---------------------------------------------------------------------

  BillItem addItem({required String name, required int price, int quantity = 1}) {
    final item = BillItem(
      id: IdGenerator.next('item'),
      name: name,
      price: price,
      quantity: quantity,
    );
    _bill.items.add(item);
    _markEditedIfSent();
    notifyListeners();
    return item;
  }

  void setItemsFromOcr(List<BillItem> items) {
    _bill.items
      ..clear()
      ..addAll(items);
    notifyListeners();
  }

  void updateItem(String itemId, {String? name, int? price, int? quantity}) {
    final item = _findItem(itemId);
    if (item == null) return;
    if (name != null) item.name = name;
    if (price != null) item.price = price;
    if (quantity != null) item.quantity = quantity;
    _markEditedIfSent();
    notifyListeners();
  }

  void removeItem(String itemId) {
    _bill.items.removeWhere((i) => i.id == itemId);
    _markEditedIfSent();
    notifyListeners();
  }

  void setItemAssignees(String itemId, Set<String> memberIds) {
    final item = _findItem(itemId);
    if (item == null) return;
    item.assignedMemberIds
      ..clear()
      ..addAll(memberIds);
    _markEditedIfSent();
    notifyListeners();
  }

  void toggleItemAssignee(String itemId, String memberId) {
    final item = _findItem(itemId);
    if (item == null) return;
    if (item.assignedMemberIds.contains(memberId)) {
      item.assignedMemberIds.remove(memberId);
    } else {
      item.assignedMemberIds.add(memberId);
    }
    _markEditedIfSent();
    notifyListeners();
  }

  BillItem? _findItem(String itemId) {
    for (final item in _bill.items) {
      if (item.id == itemId) return item;
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Members
  // ---------------------------------------------------------------------

  Member addMember({
    required String name,
    String? phone,
    String? email,
    bool fromDeviceContact = false,
  }) {
    final member = Member(
      id: IdGenerator.next('member'),
      name: name,
      phone: phone,
      email: email,
      isCreator: _members.isEmpty,
      fromDeviceContact: fromDeviceContact,
    );
    _members.add(member);
    notifyListeners();
    return member;
  }

  /// PRD §11 rule 3: a removed member's assigned items revert to
  /// unassigned rather than silently vanishing.
  void removeMember(String memberId) {
    final removedWasCreator =
        _members.any((m) => m.id == memberId && m.isCreator);
    _members.removeWhere((m) => m.id == memberId);
    _bill.unassignMemberEverywhere(memberId);
    if (removedWasCreator && _members.isNotEmpty) {
      _members.first.isCreator = true;
    }
    notifyListeners();
  }

  /// FR-5.5: the rounding remainder defaults to the creator but can be
  /// manually reassigned to any other member.
  void setCreator(String memberId) {
    for (final m in _members) {
      m.isCreator = m.id == memberId;
    }
    notifyListeners();
  }

  void setMemberPaid(String memberId, bool isPaid) {
    for (final m in _members) {
      if (m.id == memberId) m.isPaid = isPaid;
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Split configuration
  // ---------------------------------------------------------------------

  void setSplitMode(SplitMode mode) {
    _bill.splitMode = mode;
    _markEditedIfSent();
    notifyListeners();
  }

  void setTaxPercent(double value) {
    _bill.taxPercent = value;
    _markEditedIfSent();
    notifyListeners();
  }

  void setServicePercent(double value) {
    _bill.servicePercent = value;
    _markEditedIfSent();
    notifyListeners();
  }

  void setDiscount(DiscountConfig discount) {
    _bill.discount = discount;
    _markEditedIfSent();
    notifyListeners();
  }

  void setSplitExtrasEqually(bool value) {
    _bill.splitExtrasEqually = value;
    _markEditedIfSent();
    notifyListeners();
  }

  void setPercentageShare(String memberId, double percent) {
    _bill.percentageShares[memberId] = percent;
    _markEditedIfSent();
    notifyListeners();
  }

  void setCustomAmount(String memberId, int amount) {
    _bill.customAmounts[memberId] = amount;
    _markEditedIfSent();
    notifyListeners();
  }

  void setManualTotal(int total) {
    _bill.manualTotalOverride = total;
    _markEditedIfSent();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Derived state
  // ---------------------------------------------------------------------

  List<String> get validationErrors => SplitValidator.validate(_bill, _members);

  bool get isReadyToSplit => validationErrors.isEmpty;

  SplitResult? computeSplit() {
    if (!isReadyToSplit) return null;
    return SplitCalculator.calculate(_bill, _members);
  }

  void markNotificationsSent() {
    _bill.notificationsSentAt = DateTime.now();
    _bill.hasUnsentChanges = false;
    notifyListeners();
  }

  /// PRD §11 rule 6: once notifications have gone out, any further edit to
  /// the bill must be surfaced as needing a re-send, not applied silently.
  void _markEditedIfSent() {
    if (_bill.notificationsSentAt != null) {
      _bill.hasUnsentChanges = true;
    }
  }
}
