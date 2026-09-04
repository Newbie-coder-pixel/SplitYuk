import 'package:flutter_test/flutter_test.dart';

import 'package:splityuk_app/main.dart';

void main() {
  testWidgets('App boots to the intro screen without throwing', (tester) async {
    await tester.pumpWidget(const SplitYukApp());
    await tester.pumpAndSettle();

    expect(find.text('SPLITYUK'), findsOneWidget);
    expect(find.text('Start splitting a bill'), findsOneWidget);
  });

  testWidgets('Start splitting a bill navigates to the input chooser', (tester) async {
    await tester.pumpWidget(const SplitYukApp());
    await tester.pumpAndSettle();

    final button = find.text('Start splitting a bill');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('How do you want to start?'), findsOneWidget);
    expect(find.text('Scan a receipt'), findsOneWidget);
    expect(find.text('Enter it manually'), findsOneWidget);
  });
}
