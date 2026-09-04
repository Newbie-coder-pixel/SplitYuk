import 'package:flutter_test/flutter_test.dart';
import 'package:splityuk_app/models/bill.dart';
import 'package:splityuk_app/models/bill_item.dart';
import 'package:splityuk_app/models/split_mode.dart';

void main() {
  group('DiscountConfig', () {
    test('resolves a flat amount as-is when within the subtotal', () {
      const discount = DiscountConfig(type: DiscountType.amount, value: 5000);
      expect(discount.resolve(20000), 5000);
    });

    test('resolves a percentage of the subtotal', () {
      const discount = DiscountConfig(type: DiscountType.percentage, value: 10);
      expect(discount.resolve(20000), 2000);
    });

    test('clamps a discount larger than the subtotal instead of going negative', () {
      const discount = DiscountConfig(type: DiscountType.amount, value: 999999);
      expect(discount.resolve(10000), 10000);
    });

    test('never applies to a zero subtotal', () {
      const discount = DiscountConfig(type: DiscountType.percentage, value: 50);
      expect(discount.resolve(0), 0);
    });
  });

  group('Bill derived totals', () {
    test('subtotal sums item prices when items exist', () {
      final bill = Bill(items: [
        BillItem(id: '1', name: 'A', price: 1000),
        BillItem(id: '2', name: 'B', price: 2500),
      ]);
      expect(bill.subtotal, 3500);
    });

    test('falls back to manualTotalOverride when there are no items', () {
      final bill = Bill(manualTotalOverride: 42000);
      expect(bill.subtotal, 42000);
    });

    test('ignores manualTotalOverride once items are present', () {
      final bill = Bill(
        manualTotalOverride: 999,
        items: [BillItem(id: '1', name: 'A', price: 1000)],
      );
      expect(bill.subtotal, 1000);
    });

    test('total = taxable + tax + service, after discount', () {
      final bill = Bill(
        manualTotalOverride: 100000,
        taxPercent: 10,
        servicePercent: 5,
        discount: const DiscountConfig(type: DiscountType.amount, value: 10000),
      );
      // taxable = 90000, tax = 9000, service = 4500, total = 103500.
      expect(bill.taxableAmount, 90000);
      expect(bill.taxAmount, 9000);
      expect(bill.serviceAmount, 4500);
      expect(bill.total, 103500);
    });

    test('hasUnassignedItems reflects any item with an empty assignee set', () {
      final assigned = BillItem(id: '1', name: 'A', price: 1000)
        ..assignedMemberIds.add('m1');
      final unassigned = BillItem(id: '2', name: 'B', price: 500);
      final bill = Bill(items: [assigned, unassigned]);
      expect(bill.hasUnassignedItems, isTrue);

      unassigned.assignedMemberIds.add('m2');
      expect(bill.hasUnassignedItems, isFalse);
    });
  });

  group('BillItem', () {
    test('shareFor splits the price evenly across assignees', () {
      final item = BillItem(id: '1', name: 'A', price: 100)
        ..assignedMemberIds.addAll(['a', 'b', 'c']);
      expect(item.shareFor('a'), closeTo(33.33, 0.01));
    });

    test('shareFor is zero for a member not assigned to the item', () {
      final item = BillItem(id: '1', name: 'A', price: 100)
        ..assignedMemberIds.add('a');
      expect(item.shareFor('someone-else'), 0);
    });

    test('unassignMember reverts the item to unassigned rather than deleting it', () {
      final item = BillItem(id: '1', name: 'A', price: 100)
        ..assignedMemberIds.addAll(['a', 'b']);
      item.unassignMember('a');
      expect(item.assignedMemberIds, {'b'});
      item.unassignMember('b');
      expect(item.isAssigned, isFalse);
    });
  });

  group('Bill.unassignMemberEverywhere', () {
    test('clears a removed member from items, percentages, and custom amounts', () {
      final item = BillItem(id: '1', name: 'A', price: 100)
        ..assignedMemberIds.addAll(['a', 'b']);
      final bill = Bill(
        items: [item],
        splitMode: SplitMode.percentage,
        percentageShares: {'a': 50, 'b': 50},
        customAmounts: {'a': 50, 'b': 50},
      );

      bill.unassignMemberEverywhere('a');

      expect(item.assignedMemberIds, {'b'});
      expect(bill.percentageShares.containsKey('a'), isFalse);
      expect(bill.customAmounts.containsKey('a'), isFalse);
    });
  });
}
