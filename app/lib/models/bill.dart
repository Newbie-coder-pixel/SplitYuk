import 'bill_item.dart';
import 'split_mode.dart';

enum BillSource { scan, manual }

/// The whole in-memory bill being built this session (PRD §14). This is
/// the single source of truth for money figures — subtotal/tax/total are
/// always derived from [items]/[manualTotalOverride] rather than cached,
/// so they can never drift out of sync with an edit.
class Bill {
  Bill({
    this.title = '',
    this.source = BillSource.manual,
    List<BillItem>? items,
    this.manualTotalOverride,
    this.taxPercent = 0,
    this.servicePercent = 0,
    this.discount = const DiscountConfig(),
    this.splitExtrasEqually = false,
    this.splitMode = SplitMode.itemized,
    Map<String, double>? percentageShares,
    Map<String, int>? customAmounts,
    this.receiptImagePath,
    this.receiptPrintedTotal,
    this.notificationsSentAt,
  })  : items = items ?? <BillItem>[],
        percentageShares = percentageShares ?? <String, double>{},
        customAmounts = customAmounts ?? <String, int>{};

  String title;
  final BillSource source;
  final List<BillItem> items;

  /// Used only for "Total only" manual entry (FR-3.1), where there is no
  /// itemized list to sum. Ignored whenever [items] is non-empty.
  int? manualTotalOverride;

  double taxPercent;
  double servicePercent;
  DiscountConfig discount;

  /// FR-5.2: tax/service split proportional to each member's item subtotal
  /// by default, or equally across members when this is true.
  bool splitExtrasEqually;

  SplitMode splitMode;

  /// memberId -> percentage, used when [splitMode] is [SplitMode.percentage].
  final Map<String, double> percentageShares;

  /// memberId -> exact amount, used when [splitMode] is [SplitMode.customAmount].
  final Map<String, int> customAmounts;

  /// Kept in memory only to attach to the outgoing notification (FR-2.5);
  /// never re-uploaded or persisted beyond the session.
  String? receiptImagePath;

  /// For manual-entry bills (no original photo): an on-device-rendered
  /// summary image (FR-3.3), generated once the split is finalized.
  String? renderedSummaryImagePath;

  /// The total OCR read directly off the receipt, for the mismatch check
  /// in FR-2.4. Null for manual entry.
  int? receiptPrintedTotal;

  /// Set once notifications have gone out, so a later edit can be detected
  /// and trigger a re-send (PRD §11 rule 6) instead of a silent change.
  DateTime? notificationsSentAt;

  /// True when the bill was changed *after* [notificationsSentAt] was set —
  /// the signal the send screen uses to prompt a re-send rather than
  /// silently leaving members with stale amounts (PRD §11 rule 6).
  bool hasUnsentChanges = false;

  bool get isItemized => items.isNotEmpty;

  int get subtotal {
    if (items.isNotEmpty) {
      return items.fold<int>(0, (sum, item) => sum + item.price);
    }
    return manualTotalOverride ?? 0;
  }

  int get discountAmount => discount.resolve(subtotal);

  int get taxableAmount => subtotal - discountAmount;

  int get taxAmount => (taxableAmount * (taxPercent / 100)).round();

  int get serviceAmount => (taxableAmount * (servicePercent / 100)).round();

  int get total => taxableAmount + taxAmount + serviceAmount;

  bool get hasUnassignedItems => items.any((item) => !item.isAssigned);

  /// The image attached to outgoing notifications (FR-7.2): the original
  /// receipt for a scanned bill, or the rendered summary for a manual one.
  String? get attachmentImagePath =>
      source == BillSource.scan ? receiptImagePath : renderedSummaryImagePath;

  void unassignMemberEverywhere(String memberId) {
    for (final item in items) {
      item.unassignMember(memberId);
    }
    percentageShares.remove(memberId);
    customAmounts.remove(memberId);
  }
}
