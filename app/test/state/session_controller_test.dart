import 'package:flutter_test/flutter_test.dart';
import 'package:splityuk_app/models/bill_item.dart';
import 'package:splityuk_app/state/session_controller.dart';

void main() {
  group('SessionController — scanned adjustments', () {
    /// The receipt from `receipt_parser_test.dart`'s end-to-end case:
    /// items 537.600, "Discount Price" 276.660, printed TOTAL 260.940.
    test('a scanned discount lands on the bill so the total matches the receipt', () {
      final session = SessionController()..startScannedBill(receiptPrintedTotal: 260940);
      session.setItemsFromOcr([
        BillItem(id: 'i1', name: 'Harry Potter Plastic Tumbler wit', price: 179900),
        BillItem(id: 'i2', name: 'Harry Potter Plastic Tumbler wit', price: 179900),
        BillItem(id: 'i3', name: 'MIKKO Dress Series Drip Glue Des', price: 79900),
        BillItem(id: 'i4', name: 'Flower Language Series Succulent', price: 39900),
        BillItem(id: 'i5', name: 'MIKKO Collection Ankle Socks (1', price: 29900),
        BillItem(id: 'i6', name: 'Cinnamoroll Lotion Bottle 45ml', price: 17900),
        BillItem(id: 'i7', name: 'Paper Bag Red M', price: 7200),
        BillItem(id: 'i8', name: 'Paper Bag Red S', price: 3000),
      ]);

      session.setScannedAdjustments(discount: 276660);

      expect(session.bill.subtotal, 537600);
      expect(session.bill.discountAmount, 276660);
      expect(session.bill.total, 260940);
      expect(session.bill.total, session.bill.receiptPrintedTotal);
    });

    test('tax and service given as amounts survive the conversion to percentages', () {
      final session = SessionController()..startScannedBill();
      session.setItemsFromOcr([
        BillItem(id: 'i1', name: 'Nasi Goreng', price: 50000),
      ]);

      session.setScannedAdjustments(tax: 5500, serviceCharge: 2500);

      expect(session.bill.taxAmount, 5500);
      expect(session.bill.serviceAmount, 2500);
      expect(session.bill.total, 58000);
    });

    test('a discount larger than the subtotal cannot push the bill negative', () {
      final session = SessionController()..startScannedBill();
      session.setItemsFromOcr([
        BillItem(id: 'i1', name: 'Kopi', price: 20000),
      ]);

      session.setScannedAdjustments(discount: 999999);

      expect(session.bill.total, 0);
    });

    test('no adjustments leaves the bill at its item subtotal', () {
      final session = SessionController()..startScannedBill();
      session.setItemsFromOcr([
        BillItem(id: 'i1', name: 'Kopi', price: 20000),
      ]);

      session.setScannedAdjustments();

      expect(session.bill.total, 20000);
      expect(session.bill.taxPercent, 0);
    });
  });

  group('SessionController — members', () {
    test('the first member added becomes creator automatically', () {
      final session = SessionController();
      final a = session.addMember(name: 'Alice');
      session.addMember(name: 'Bob');

      expect(session.creator?.id, a.id);
    });

    test('removing the creator promotes the next member to creator', () {
      final session = SessionController();
      final a = session.addMember(name: 'Alice');
      final b = session.addMember(name: 'Bob');

      session.removeMember(a.id);

      expect(session.members.length, 1);
      expect(session.creator?.id, b.id);
    });

    test('removing a member reverts their assigned items to unassigned', () {
      final session = SessionController()..startScannedBill();
      final a = session.addMember(name: 'Alice');
      final b = session.addMember(name: 'Bob');
      final item = session.addItem(name: 'Nasi Goreng', price: 20000);
      session.setItemAssignees(item.id, {a.id, b.id});

      session.removeMember(a.id);

      final remaining = session.bill.items.first;
      expect(remaining.assignedMemberIds, {b.id});
      expect(remaining.isAssigned, isTrue);
    });

    test('setCreator moves the rounding-remainder role without duplicating it', () {
      final session = SessionController();
      final a = session.addMember(name: 'Alice');
      final b = session.addMember(name: 'Bob');

      session.setCreator(b.id);

      expect(session.members.where((m) => m.isCreator).length, 1);
      expect(session.creator?.id, b.id);
      expect(a.isCreator, isFalse);
    });
  });

  group('SessionController — edit-after-send tracking (PRD §11 rule 6)', () {
    test('editing before any send never flags unsent changes', () {
      final session = SessionController()..startManualBill(itemized: false);
      session.addMember(name: 'Alice');
      session.setManualTotal(50000);

      expect(session.bill.hasUnsentChanges, isFalse);
    });

    test('editing after notifications were sent flags unsent changes', () {
      final session = SessionController()..startManualBill(itemized: false);
      session.addMember(name: 'Alice');
      session.setManualTotal(50000);
      session.markNotificationsSent();

      session.setManualTotal(60000);

      expect(session.bill.hasUnsentChanges, isTrue);
    });

    test('a fresh send clears the unsent-changes flag', () {
      final session = SessionController()..startManualBill(itemized: false);
      session.addMember(name: 'Alice');
      session.setManualTotal(50000);
      session.markNotificationsSent();
      session.setManualTotal(60000);

      session.markNotificationsSent();

      expect(session.bill.hasUnsentChanges, isFalse);
    });
  });

  group('SessionController — validation gate', () {
    test('is not ready to split with no members', () {
      final session = SessionController()..startManualBill(itemized: false);
      session.setManualTotal(10000);

      expect(session.isReadyToSplit, isFalse);
      expect(session.computeSplit(), isNull);
    });

    test('becomes ready once a valid equal split is configured', () {
      final session = SessionController()..startManualBill(itemized: false);
      session.addMember(name: 'Alice');
      session.addMember(name: 'Bob');
      session.setManualTotal(10000);

      expect(session.isReadyToSplit, isTrue);
      expect(session.computeSplit()!.reconciles, isTrue);
    });
  });

  group('SessionController — session reset (PRD §3 no-persistence)', () {
    test('resetSession discards the bill and every member', () {
      final session = SessionController()..startManualBill(itemized: false);
      session.addMember(name: 'Alice');
      session.setManualTotal(10000);

      session.resetSession();

      expect(session.members, isEmpty);
      expect(session.bill.subtotal, 0);
      expect(session.bill.title, '');
    });
  });
}
