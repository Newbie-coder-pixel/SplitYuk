import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:splityuk_app/core/theme/app_theme.dart';
import 'package:splityuk_app/logic/receipt_parser.dart';
import 'package:splityuk_app/models/bill_item.dart';
import 'package:splityuk_app/models/split_mode.dart';
import 'package:splityuk_app/screens/assignment/item_assignment_screen.dart';
import 'package:splityuk_app/screens/create/choose_input_screen.dart';
import 'package:splityuk_app/screens/create/manual_entry_screen.dart';
import 'package:splityuk_app/screens/members/pick_members_screen.dart';
import 'package:splityuk_app/screens/scan/review_scanned_screen.dart';
import 'package:splityuk_app/screens/scan/scan_receipt_screen.dart';
import 'package:splityuk_app/screens/send/send_notification_screen.dart';
import 'package:splityuk_app/screens/split/split_summary_screen.dart';
import 'package:splityuk_app/screens/status/payment_status_screen.dart';
import 'package:splityuk_app/state/session_controller.dart';

/// These pump every screen directly (bypassing navigation) with a
/// realistic populated session, so a build/layout crash on any screen —
/// a null lookup, a RenderFlex overflow, a bad Provider wire-up — fails
/// here instead of only showing up on a real device.
Future<void> _pump(
  WidgetTester tester,
  SessionController session,
  Widget screen, {
  Size surfaceSize = const Size(1080, 4000),
}) async {
  // A tall surface so every screen's content renders without needing to
  // scroll a lazy sliver list into view first — this test is about
  // catching build/layout crashes, not scroll behavior. Pass a narrower
  // [surfaceSize] to check a screen at a real phone's width, where a row
  // of fixed-width columns is far likelier to overflow.
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: session,
      child: MaterialApp(theme: AppTheme.light(), home: screen),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

SessionController _itemizedSessionWithAssignments() {
  final session = SessionController()..startScannedBill();
  final alice = session.addMember(name: 'Alice', phone: '0812000001');
  final bob = session.addMember(name: 'Bob', phone: '0812000002');
  final item1 = session.addItem(name: 'Nasi Goreng Spesial', price: 56000);
  final item2 = session.addItem(name: 'Es Teh Manis', price: 18000);
  session.setItemAssignees(item1.id, {alice.id, bob.id});
  session.setItemAssignees(item2.id, {bob.id});
  session.setTaxPercent(10);
  session.setServicePercent(5);
  return session;
}

SessionController _itemizedSessionPartiallyAssigned() {
  final session = SessionController()..startScannedBill();
  final alice = session.addMember(name: 'Alice', phone: '0812000001');
  session.addMember(name: 'Bob', phone: '0812000002');
  final item1 = session.addItem(name: 'Nasi Goreng Spesial', price: 56000);
  session.addItem(name: 'Es Teh Manis', price: 18000);
  session.setItemAssignees(item1.id, {alice.id});
  return session;
}

void main() {
  testWidgets('ChooseInputScreen builds', (tester) async {
    await _pump(tester, SessionController(), const ChooseInputScreen());
    expect(find.text('Scan a receipt'), findsOneWidget);
  });

  testWidgets('ScanReceiptScreen builds', (tester) async {
    await _pump(tester, SessionController(), const ScanReceiptScreen());
    expect(find.text('Take a photo'), findsOneWidget);
  });

  testWidgets('ReviewScannedScreen renders a full receipt with quantities and a discount',
      (tester) async {
    // The real scanned receipt from receipt_parser_test.dart: eight lines,
    // a 276.660 discount, and a printed total of 260.940. Rendering it at
    // a phone's width is the check that matters — the qty/name/amount
    // columns and the per-row buttons all have to fit next to a long
    // product name without a RenderFlex overflow.
    final parsed = ParsedReceipt(
      items: [
        BillItem(id: 'i1', name: 'Paper Bag Red S', price: 3000),
        BillItem(id: 'i2', name: 'Flower Language Series Succulent', price: 39900),
        BillItem(id: 'i3', name: 'MIKKO Collection Ankle Socks (1', price: 29900),
        BillItem(id: 'i4', name: 'MIKKO Dress Series Drip Glue Des', price: 79900),
        BillItem(id: 'i5', name: 'Cinnamoroll Lotion Bottle 45ml', price: 17900),
        BillItem(id: 'i6', name: 'Paper Bag Red M', price: 7200, quantity: 2),
        BillItem(id: 'i7', name: 'Harry Potter Plastic Tumbler wit', price: 179900),
        BillItem(id: 'i8', name: 'Harry Potter Plastic Tumbler wit', price: 179900),
      ],
      detectedTotal: 260940,
      discount: 276660,
    );

    await _pump(
      tester,
      SessionController(),
      ReviewScannedScreen(imagePath: '/tmp/receipt.jpg', parsed: parsed),
      surfaceSize: const Size(390, 3000),
    );

    expect(find.text('QTY'), findsOneWidget);
    expect(find.text('ITEM'), findsOneWidget);
    expect(find.text('AMOUNT'), findsOneWidget);
    expect(find.text('8 lines · 9 items'), findsOneWidget);

    // The discount is shown as a deduction, and the total is the amount
    // actually owed — so it matches the receipt and no mismatch warning
    // fires.
    expect(find.text('Discount'), findsOneWidget);
    expect(find.text('- Rp 276.660'), findsOneWidget);
    expect(find.text('Rp 260.940'), findsOneWidget);
    expect(find.text('Total mismatch detected'), findsNothing);
  });

  testWidgets('ReviewScannedScreen warns when the items do not reach the printed total',
      (tester) async {
    final parsed = ParsedReceipt(
      items: [BillItem(id: 'i1', name: 'Kopi Susu', price: 25000)],
      detectedTotal: 90000,
    );

    await _pump(
      tester,
      SessionController(),
      ReviewScannedScreen(imagePath: '/tmp/receipt.jpg', parsed: parsed),
      surfaceSize: const Size(390, 3000),
    );

    expect(find.text('Total mismatch detected'), findsOneWidget);
  });

  testWidgets('ManualEntryScreen builds in both itemized and total-only modes', (tester) async {
    await _pump(tester, SessionController(), const ManualEntryScreen());
    expect(find.text('Line items'), findsOneWidget);

    await tester.tap(find.text('Total only'));
    await tester.pumpAndSettle();
    expect(find.text('Bill total'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PickMembersScreen builds with existing members', (tester) async {
    final session = SessionController()..startManualBill(itemized: false);
    session.addMember(name: 'Alice', phone: '0812000001');
    session.addMember(name: 'Bob', phone: '0812000002');
    await _pump(tester, session, const PickMembersScreen());
    expect(find.text('Alice · You'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
  });

  testWidgets('ItemAssignmentScreen builds mid-assignment', (tester) async {
    final session = _itemizedSessionPartiallyAssigned();
    await _pump(tester, session, const ItemAssignmentScreen());
    expect(find.textContaining('items assigned'), findsOneWidget);
  });

  testWidgets('SplitSummaryScreen builds for every split mode', (tester) async {
    final session = _itemizedSessionWithAssignments();
    await _pump(tester, session, const SplitSummaryScreen());
    expect(find.text('FINAL TOTAL'), findsOneWidget);

    for (final mode in SplitMode.values) {
      session.setSplitMode(mode);
      if (mode == SplitMode.percentage) {
        for (final m in session.members) {
          session.setPercentageShare(m.id, 100 / session.members.length);
        }
      }
      if (mode == SplitMode.customAmount) {
        final each = session.bill.total ~/ session.members.length;
        for (final m in session.members) {
          session.setCustomAmount(m.id, each);
        }
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'mode: $mode');
    }
  });

  testWidgets('SplitSummaryScreen builds for a non-itemized (total-only) bill', (tester) async {
    final session = SessionController()..startManualBill(itemized: false);
    session.addMember(name: 'Alice');
    session.addMember(name: 'Bob');
    session.setManualTotal(50000);
    await _pump(tester, session, const SplitSummaryScreen());
    expect(find.text('By item'), findsNothing);
  });

  testWidgets('SendNotificationScreen builds and renders the receipt preview', (tester) async {
    final session = _itemizedSessionWithAssignments();
    await _pump(tester, session, const SendNotificationScreen());
    expect(find.text('SPLIT RECEIPT'), findsOneWidget);
    expect(find.text('Alice'), findsWidgets);
  });

  testWidgets('PaymentStatusScreen builds with a mix of paid/unpaid members', (tester) async {
    final session = _itemizedSessionWithAssignments();
    session.markNotificationsSent();
    session.setMemberPaid(session.members.first.id, true);
    await _pump(tester, session, const PaymentStatusScreen());
    expect(find.text('PAYMENT STATUS'), findsOneWidget);
    expect(find.text('Share summary'), findsOneWidget);
  });
}
