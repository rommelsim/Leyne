// Smoke test for the app shell. Verifies:
//   • The four navigation destinations are present and labeled correctly.
//   • Tapping a tab switches the visible screen.
//
// Doesn't drive DataStore.bootstrap (which would hit the real LTA API);
// data layer logic is covered by test/data_layer_test.dart. We avoid
// pumpAndSettle because the bootstrap banner runs a CircularProgressIndicator
// that never settles in tests (DataStore.referenceState stays "loading"
// since bootstrap isn't invoked here).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lyne/main.dart';

void main() {
  testWidgets('Root shell shows the four tabs and switches between them',
      (tester) async {
    await tester.pumpWidget(const LyneApp());
    await tester.pump(); // initial frame

    // All four destinations are present in the bottom navigation.
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Nearby'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    // Home is the initial tab — its empty-state copy is visible.
    expect(find.text('No pinned stops yet'), findsOneWidget);

    // Switch to Settings; pump one frame for the tap, one for the layout.
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('LTA DataMall key'), findsOneWidget);
  });
}
