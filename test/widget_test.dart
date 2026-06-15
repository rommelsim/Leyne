// Smoke test for the app shell. Verifies:
//   • The five navigation destinations are present and labeled correctly.
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

  testWidgets('Root shell shows the five tabs and switches between them',
      (tester) async {
    SharedPreferences.setMockInitialValues({'lyne.onboardingDone': true});
    await AppModel.shared.load();

    await tester.pumpWidget(const LyneApp());
    await tester.pump(); // initial frame

    // All five destinations are present in the bottom navigation
    // (current order: Bus · MRT · Saved · Search · Alerts). Settings is no
    // longer a tab — it opens as a gear sheet from the Alerts tab.
    expect(find.text('Bus'), findsAtLeastNWidgets(1));
    expect(find.text('MRT'), findsAtLeastNWidgets(1));
    expect(find.text('Saved'), findsAtLeastNWidgets(1));
    expect(find.text('Search'), findsAtLeastNWidgets(1));
    expect(find.text('Alerts'), findsAtLeastNWidgets(1));

    // The Bus (Home) tab is the initial tab — its empty-state copy is visible.
    expect(find.text('No stops yet'), findsOneWidget);

    // Switch to Alerts; pump one frame for the tap, one for the layout.
    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // The Alerts screen header carries its subtitle unconditionally.
    expect(
        find.text('Service status & your notifications'), findsOneWidget);

    // Drain the bounded App-Open-ad preload poll (15 × 800 ms chained timers
    // scheduled from SoftRoot.initState) so no timer is left pending at
    // teardown. Consent never resolves under the test binding, so the poll
    // runs to its attempt cap and then stops scheduling.
    await tester.pump(const Duration(seconds: 13));
  });
}
