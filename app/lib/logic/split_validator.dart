import '../models/bill.dart';
import '../models/member.dart';
import '../models/split_mode.dart';

/// Validates a [Bill] + member roster *before* a split is calculated or
/// notifications are sent — this is the enforcement point for FR-5.4 and
/// PRD §11 rule 1. [SplitCalculator] assumes it is only ever called on
/// input that already passed this check.
class SplitValidator {
  SplitValidator._();

  static const double _percentEpsilon = 0.01;

  /// Returns human-readable problems with the current bill/member state.
  /// Empty list means the split is ready to be calculated and sent.
  static List<String> validate(Bill bill, List<Member> members) {
    final errors = <String>[];

    if (members.isEmpty) {
      errors.add('Add at least one member before splitting the bill.');
      return errors;
    }

    final creatorCount = members.where((m) => m.isCreator).length;
    if (creatorCount != 1) {
      errors.add('Exactly one member must be marked as the bill creator.');
    }

    if (bill.total <= 0) {
      errors.add('The bill total must be greater than zero.');
    }

    switch (bill.splitMode) {
      case SplitMode.itemized:
        if (bill.items.isEmpty) {
          errors.add('Add at least one item, or switch to "Total only".');
        } else if (bill.hasUnassignedItems) {
          errors.add('Assign every item to at least one member.');
        }
        break;

      case SplitMode.equal:
        break;

      case SplitMode.percentage:
        final sum = members.fold<double>(
          0,
          (total, m) => total + (bill.percentageShares[m.id] ?? 0),
        );
        if ((sum - 100).abs() > _percentEpsilon) {
          errors.add(
            'Percentages must add up to 100% (currently ${_formatPercent(sum)}%).',
          );
        }
        break;

      case SplitMode.customAmount:
        final sum = members.fold<int>(
          0,
          (total, m) => total + (bill.customAmounts[m.id] ?? 0),
        );
        if (sum != bill.total) {
          errors.add(
            'Custom amounts must add up to the bill total '
            '(currently Rp $sum of Rp ${bill.total}).',
          );
        }
        break;
    }

    return errors;
  }

  static bool isValid(Bill bill, List<Member> members) =>
      validate(bill, members).isEmpty;

  static String _formatPercent(double value) {
    final rounded = (value * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(1);
  }
}
