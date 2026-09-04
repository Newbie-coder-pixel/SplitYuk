import 'package:flutter_test/flutter_test.dart';
import 'package:splityuk_app/logic/split_calculator.dart';
import 'package:splityuk_app/models/bill.dart';
import 'package:splityuk_app/models/bill_item.dart';
import 'package:splityuk_app/models/member.dart';
import 'package:splityuk_app/models/split_mode.dart';

Member _member(String id, {bool isCreator = false}) =>
    Member(id: id, name: id, isCreator: isCreator);

void main() {
  group('SplitCalculator — equal mode', () {
    test('divides evenly when total is divisible by member count', () {
      final bill = Bill(
        splitMode: SplitMode.equal,
        manualTotalOverride: 300,
      );
      final members = [_member('a', isCreator: true), _member('b'), _member('c')];

      final result = SplitCalculator.calculate(bill, members);

      expect(result.total, 300);
      expect(result.perMember['a']!.total, 100);
      expect(result.perMember['b']!.total, 100);
      expect(result.perMember['c']!.total, 100);
      expect(result.reconciles, isTrue);
    });

    test('charges the indivisible remainder entirely to the creator', () {
      final bill = Bill(splitMode: SplitMode.equal, manualTotalOverride: 100);
      // 100 / 3 = 33.33..., base=33, remainder=1
      final members = [_member('a'), _member('b', isCreator: true), _member('c')];

      final result = SplitCalculator.calculate(bill, members);

      expect(result.perMember['a']!.total, 33);
      expect(result.perMember['c']!.total, 33);
      expect(result.perMember['b']!.total, 34); // creator absorbs the +1
      expect(result.sumOfMemberTotals, 100);
      expect(result.reconciles, isTrue);
    });

    test('reconciles for a large, awkward member count', () {
      final bill = Bill(splitMode: SplitMode.equal, manualTotalOverride: 100000);
      final members = List.generate(7, (i) => _member('m$i', isCreator: i == 0));

      final result = SplitCalculator.calculate(bill, members);

      expect(result.reconciles, isTrue);
      expect(result.sumOfMemberTotals, 100000);
    });
  });

  group('SplitCalculator — percentage mode', () {
    test('splits by percentage and reconciles despite rounding', () {
      final bill = Bill(
        splitMode: SplitMode.percentage,
        manualTotalOverride: 100,
        percentageShares: {
          'a': 100 / 3,
          'b': 100 / 3,
          'c': 100 / 3 + (100 - 3 * (100 / 3)), // ensure exact 100 sum
        },
      );
      final members = [_member('a', isCreator: true), _member('b'), _member('c')];

      final result = SplitCalculator.calculate(bill, members);

      expect(result.reconciles, isTrue);
      expect(result.sumOfMemberTotals, 100);
    });

    test('rejects percentages that do not sum to 100', () {
      final bill = Bill(
        splitMode: SplitMode.percentage,
        manualTotalOverride: 100,
        percentageShares: {'a': 50, 'b': 40},
      );
      final members = [_member('a', isCreator: true), _member('b')];

      expect(
        () => SplitCalculator.calculate(bill, members),
        throwsArgumentError,
      );
    });
  });

  group('SplitCalculator — custom amount mode', () {
    test('uses the exact amounts given when they sum to the total', () {
      final bill = Bill(
        splitMode: SplitMode.customAmount,
        manualTotalOverride: 150,
        customAmounts: {'a': 100, 'b': 50},
      );
      final members = [_member('a', isCreator: true), _member('b')];

      final result = SplitCalculator.calculate(bill, members);

      expect(result.perMember['a']!.total, 100);
      expect(result.perMember['b']!.total, 50);
      expect(result.reconciles, isTrue);
    });

    test('rejects custom amounts that do not sum to the total', () {
      final bill = Bill(
        splitMode: SplitMode.customAmount,
        manualTotalOverride: 150,
        customAmounts: {'a': 100, 'b': 40},
      );
      final members = [_member('a', isCreator: true), _member('b')];

      expect(
        () => SplitCalculator.calculate(bill, members),
        throwsArgumentError,
      );
    });
  });

  group('SplitCalculator — itemized mode', () {
    test('splits an item evenly across its assignees', () {
      final item = BillItem(id: 'i1', name: 'Nasi Goreng x2', price: 56000)
        ..assignedMemberIds.addAll(['a', 'b']);
      final bill = Bill(splitMode: SplitMode.itemized, items: [item]);
      final members = [_member('a', isCreator: true), _member('b')];

      final result = SplitCalculator.calculate(bill, members);

      expect(result.total, 56000);
      expect(result.perMember['a']!.total, 28000);
      expect(result.perMember['b']!.total, 28000);
      expect(result.reconciles, isTrue);
    });

    test(
      'reconciles a 3-way split of an item that does not divide evenly, '
      'matching the design-mockup example (35000 / 3)',
      () {
        final item = BillItem(id: 'i1', name: 'Sate Ayam', price: 35000)
          ..assignedMemberIds.addAll(['a', 'b', 'c']);
        final bill = Bill(splitMode: SplitMode.itemized, items: [item]);
        final members = [
          _member('a', isCreator: true),
          _member('b'),
          _member('c'),
        ];

        final result = SplitCalculator.calculate(bill, members);

        expect(result.total, 35000);
        expect(result.reconciles, isTrue);
        // 35000/3 = 11666.67 -> two members round to 11667, one absorbs
        // the residual via the creator-rounding rule.
        final totals = members.map((m) => result.perMember[m.id]!.total).toList()
          ..sort();
        expect(totals, [11666, 11667, 11667]);
      },
    );

    test('distributes tax and service proportionally to item subtotal', () {
      final itemA = BillItem(id: 'i1', name: 'A', price: 60000)
        ..assignedMemberIds.add('a');
      final itemB = BillItem(id: 'i2', name: 'B', price: 40000)
        ..assignedMemberIds.add('b');
      final bill = Bill(
        splitMode: SplitMode.itemized,
        items: [itemA, itemB],
        taxPercent: 10,
        servicePercent: 5,
      );
      final members = [_member('a', isCreator: true), _member('b')];

      final result = SplitCalculator.calculate(bill, members);

      // subtotal 100000, tax 10000, service 5000, total 115000.
      // a = 60% of extras, b = 40% of extras.
      expect(result.subtotal, 100000);
      expect(result.taxAmount, 10000);
      expect(result.serviceAmount, 5000);
      expect(result.total, 115000);
      expect(result.perMember['a']!.total, 69000); // 60000 + 6000 + 3000
      expect(result.perMember['b']!.total, 46000); // 40000 + 4000 + 2000
      expect(result.reconciles, isTrue);
    });

    test('splits tax and service equally when splitExtrasEqually is set', () {
      final itemA = BillItem(id: 'i1', name: 'A', price: 90000)
        ..assignedMemberIds.add('a');
      final itemB = BillItem(id: 'i2', name: 'B', price: 10000)
        ..assignedMemberIds.add('b');
      final bill = Bill(
        splitMode: SplitMode.itemized,
        items: [itemA, itemB],
        taxPercent: 10,
        splitExtrasEqually: true,
      );
      final members = [_member('a', isCreator: true), _member('b')];

      final result = SplitCalculator.calculate(bill, members);

      // subtotal 100000, tax 10000 split 5000/5000 regardless of item split.
      expect(result.perMember['a']!.total, 95000);
      expect(result.perMember['b']!.total, 15000);
      expect(result.reconciles, isTrue);
    });

    test('applies a flat discount before tax/service', () {
      final item = BillItem(id: 'i1', name: 'A', price: 100000)
        ..assignedMemberIds.add('a');
      final bill = Bill(
        splitMode: SplitMode.itemized,
        items: [item],
        taxPercent: 10,
        discount: const DiscountConfig(type: DiscountType.amount, value: 20000),
      );
      final members = [_member('a', isCreator: true)];

      final result = SplitCalculator.calculate(bill, members);

      // taxable = 100000 - 20000 = 80000, tax = 8000, total = 88000.
      expect(result.discountAmount, 20000);
      expect(result.taxAmount, 8000);
      expect(result.total, 88000);
      expect(result.perMember['a']!.total, 88000);
    });

    test('rejects an itemized bill with an unassigned item', () {
      final assigned = BillItem(id: 'i1', name: 'A', price: 10000)
        ..assignedMemberIds.add('a');
      final unassigned = BillItem(id: 'i2', name: 'B', price: 5000);
      final bill = Bill(
        splitMode: SplitMode.itemized,
        items: [assigned, unassigned],
      );
      final members = [_member('a', isCreator: true)];

      expect(
        () => SplitCalculator.calculate(bill, members),
        throwsArgumentError,
      );
    });

    test('a member assigned nothing owes an equal-extras share but zero items', () {
      final item = BillItem(id: 'i1', name: 'A', price: 50000)
        ..assignedMemberIds.add('a');
      final bill = Bill(
        splitMode: SplitMode.itemized,
        items: [item],
        taxPercent: 10,
        splitExtrasEqually: true,
      );
      final members = [_member('a', isCreator: true), _member('b')];

      final result = SplitCalculator.calculate(bill, members);

      // total = 55000, tax split equally = 2500 each.
      expect(result.perMember['b']!.itemSubtotal, 0);
      expect(result.perMember['b']!.total, 2500);
      expect(result.reconciles, isTrue);
    });
  });

  group('SplitCalculator — guard rails', () {
    test('throws when there are no members', () {
      final bill = Bill(splitMode: SplitMode.equal, manualTotalOverride: 100);
      expect(() => SplitCalculator.calculate(bill, []), throwsArgumentError);
    });

    test('throws when no member (or more than one) is marked creator', () {
      final bill = Bill(splitMode: SplitMode.equal, manualTotalOverride: 100);
      final noCreator = [_member('a'), _member('b')];
      final twoCreators = [
        _member('a', isCreator: true),
        _member('b', isCreator: true),
      ];

      expect(() => SplitCalculator.calculate(bill, noCreator), throwsArgumentError);
      expect(() => SplitCalculator.calculate(bill, twoCreators), throwsArgumentError);
    });

    test('throws when the bill total is zero', () {
      final bill = Bill(splitMode: SplitMode.equal, manualTotalOverride: 0);
      final members = [_member('a', isCreator: true)];
      expect(() => SplitCalculator.calculate(bill, members), throwsArgumentError);
    });

    test('throws when a discount fully wipes the bill (nothing to split)', () {
      final item = BillItem(id: 'i1', name: 'A', price: 10000)
        ..assignedMemberIds.add('a');
      final bill = Bill(
        splitMode: SplitMode.itemized,
        items: [item],
        discount: const DiscountConfig(type: DiscountType.amount, value: 999999),
      );
      final members = [_member('a', isCreator: true)];

      expect(() => SplitCalculator.calculate(bill, members), throwsArgumentError);
    });
  });
}
