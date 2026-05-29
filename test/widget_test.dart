// Smoke test for the app shell. Verifies:
//   • The four navigation destinations are present and labeled correctly.
//   • Tapping a tab switches the visible screen.
//
// Doesn't drive DataStore.bootstrap (which would hit the real LTA API);
// data layer logic is covered by test/data_layer_test.dart. We avoid
// pumpAndSettle because the bootstrap banner runs a CircularProgressIndicator
// that never settles in tests (DataStore.referenceState stays "loading"
// since bootstrap isn't invoked here).
//
// Onboarding is pre-completed (lyne.onboardingDone=true) so the app routes
// straight to RootScaffold; the onboarding flow itself is exercised by
// test/onboarding_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lyne/main.dart';
import 'package:lyne/state/app_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Root shell shows the four tabs and switches between them',
      (tester) async {
    SharedPreferences.setMockInitialValues({'lyne.onboardingDone': true});
    await AppModel.shared.load();

    await tester.pumpWidget(const LyneApp());
    await tester.pump(); // initial frame

    // All four destinations are present in the bottom navigation. Some
    // labels (Home, Search, Settings) also appear in the active screen's
    // AppBar title, so we look for "at least one".
    expect(find.text('Home'), findsAtLeastNWidgets(1));
    expect(find.text('Nearby'), findsAtLeastNWidgets(1));
    expect(find.text('Search'), findsAtLeastNWidgets(1));
    expect(find.text('Settings'), findsAtLeastNWidgets(1));

    // Home is the initial tab — its empty-state copy is visible.
    expect(find.text('No stops pinned'), findsOneWidget);

    // Switch to Settings; pump one frame for the tap, one for the layout.
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // The Soft settings screen leads with the Appearance section.
    expect(find.text('Appearance'), findsOneWidget);
  });
}
