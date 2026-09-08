import 'package:flutter_test/flutter_test.dart';
import 'package:splityuk_app/logic/share_breakdown.dart';
import 'package:splityuk_app/logic/split_result.dart';
import 'package:splityuk_app/models/bill_item.dart';

void main() {
  group('ShareBreakdown', () {
    test('itemised share: every number the member is being asked to trust is shown', () {
      final items = [
        BillItem(
          id: 'i1',
          name: 'French Fries Medium',
          price: 48000,
          quantity: 2,
          assignedMemberIds: {'m1', 'm2'},
        ),
        BillItem(id: 'i2', name: 'McFlurry Matcha OREO', price: 17500, assignedMemberIds: {'m2'}),
      ];

      final message = ShareBreakdown.build(
        billTitle: 'McD Jababeka',
        recipientName: 'Adi',
        items: items,
        memberId: 'm1',
        share: const MemberShare(
          memberId: 'm1',
          itemSubtotal: 24000,
          discountShare: 0,
          taxShare: 0,
          serviceShare: 0,
          total: 24000,
        ),
        billTotal: 65500,
        memberCount: 2,
      );

      expect(message, contains('French Fries Medium'));
      // The one thing a bare "you owe Rp 24.000" can never answer: why.
      expect(message, contains('Rp 48.000 shared by 2 → Rp 24.000'));
      expect(message, contains('YOU PAY'));
      expect(message, contains('Rp 24.000'));
      expect(message, contains('Bill total Rp 65.500, split between 2 people.'));

      // Not their item, so not in their message.
      expect(message, isNot(contains('McFlurry')));
    });

    test('shows discount, tax and service with the sign that says which way they go', () {
      final message = ShareBreakdown.build(
        billTitle: 'Dinner',
        recipientName: 'Kartika',
        items: [
          BillItem(id: 'i1', name: 'Nasi Goreng', price: 50000, assignedMemberIds: {'m1'}),
        ],
        memberId: 'm1',
        share: const MemberShare(
          memberId: 'm1',
          itemSubtotal: 50000,
          discountShare: 5000,
          taxShare: 5500,
          serviceShare: 2500,
          total: 53000,
        ),
        billTotal: 53000,
        memberCount: 1,
      );

      expect(message, contains('-Rp 5.000'));
      expect(message, contains('+Rp 5.500'));
      expect(message, contains('+Rp 2.500'));
    });

    test('amounts line up in a column so the arithmetic can be followed', () {
      final message = ShareBreakdown.build(
        billTitle: 'Dinner',
        recipientName: 'Kartika',
        items: [
          BillItem(id: 'i1', name: 'Nasi Goreng', price: 50000, assignedMemberIds: {'m1'}),
        ],
        memberId: 'm1',
        share: const MemberShare(
          memberId: 'm1',
          itemSubtotal: 50000,
          discountShare: 5000,
          taxShare: 5500,
          serviceShare: 0,
          total: 50500,
        ),
        billTotal: 50500,
        memberCount: 1,
      );

      final moneyRows = message
          .split('\n')
          .where((line) => RegExp(r'^(Items|Discount|Tax|YOU PAY)').hasMatch(line))
          .toList();

      expect(moneyRows, hasLength(4));
      // Right-aligned to one width — what makes the column readable in a
      // monospace WhatsApp block.
      expect(moneyRows.map((r) => r.length).toSet(), hasLength(1));
    });

    test('a quick-split share with no assigned items still reads as a complete message', () {
      final message = ShareBreakdown.build(
        billTitle: 'Patungan',
        recipientName: 'Budi',
        items: [
          BillItem(id: 'i1', name: 'Nasi Goreng', price: 50000),
        ],
        memberId: 'm3',
        share: const MemberShare(
          memberId: 'm3',
          itemSubtotal: 25000,
          discountShare: 0,
          taxShare: 0,
          serviceShare: 0,
          total: 25000,
        ),
        billTotal: 50000,
        memberCount: 2,
      );

      expect(message, isNot(contains('YOUR ITEMS')));
      expect(message, contains('YOU PAY'));
      expect(message, contains('Rp 25.000'));
    });

    test('monospace fences are WhatsApp-only', () {
      const share = MemberShare(
        memberId: 'm1',
        itemSubtotal: 10000,
        discountShare: 0,
        taxShare: 0,
        serviceShare: 0,
        total: 10000,
      );
      final items = [
        BillItem(id: 'i1', name: 'Kopi', price: 10000, assignedMemberIds: {'m1'}),
      ];

      final whatsapp = ShareBreakdown.build(
        billTitle: 'B',
        recipientName: 'A',
        items: items,
        memberId: 'm1',
        share: share,
        billTotal: 10000,
        memberCount: 1,
      );
      final email = ShareBreakdown.build(
        billTitle: 'B',
        recipientName: 'A',
        items: items,
        memberId: 'm1',
        share: share,
        billTotal: 10000,
        memberCount: 1,
        monospace: false,
      );

      expect(whatsapp, contains('```'));
      expect(email, isNot(contains('```')));
    });

    test('a very long item name is shortened rather than wrapped', () {
      final message = ShareBreakdown.build(
        billTitle: 'B',
        recipientName: 'A',
        items: [
          BillItem(
            id: 'i1',
            name: 'Harry Potter Plastic Tumbler with Lid and Straw Limited Edition',
            price: 179900,
            assignedMemberIds: {'m1'},
          ),
        ],
        memberId: 'm1',
        share: const MemberShare(
          memberId: 'm1',
          itemSubtotal: 179900,
          discountShare: 0,
          taxShare: 0,
          serviceShare: 0,
          total: 179900,
        ),
        billTotal: 179900,
        memberCount: 1,
      );

      final nameLine = message.split('\n').firstWhere((l) => l.startsWith('• '));
      expect(nameLine.length, lessThanOrEqualTo(38));
      expect(nameLine, endsWith('…'));
    });
  });
}
