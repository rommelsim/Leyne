// EtaPill — renders the headline "3 min" / "Arr now" pill with the
// correct text and live/non-live treatment.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lyne/widgets/eta_pill.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('EtaPill text', () {
    testWidgets('3 minutes shows "3" + "min"', (tester) async {
      await tester.pumpWidget(_wrap(const EtaPill(etaSec: 180)));
      expect(find.text('3'), findsOneWidget);
      expect(find.text('min'), findsOneWidget);
    });

    testWidgets('1 minute boundary shows "1" + "min" (live)', (tester) async {
      await tester.pumpWidget(_wrap(const EtaPill(etaSec: 60)));
      expect(find.text('1'), findsOneWidget);
      expect(find.text('min'), findsOneWidget);
    });

    testWidgets('<1 minute renders "Arr" + "now"', (tester) async {
      await tester.pumpWidget(_wrap(const EtaPill(etaSec: 30)));
      expect(find.text('Arr'), findsOneWidget);
      expect(find.text('now'), findsOneWidget);
    });

    testWidgets('0 / negative renders "Arr" + "now"', (tester) async {
      await tester.pumpWidget(_wrap(const EtaPill(etaSec: 0)));
      expect(find.text('Arr'), findsOneWidget);
      await tester.pumpWidget(_wrap(const EtaPill(etaSec: -5)));
      expect(find.text('Arr'), findsOneWidget);
    });
  });
}
