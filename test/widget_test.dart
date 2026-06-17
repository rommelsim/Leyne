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

  // Regression: the Android 3-button BACK key (the WidgetsBinding.handlePopRoute
  // → didPopRoute path) must pop a route pushed on SoftRoot's NESTED navigator
  // and return to the previous view — NOT fall through to the root navigator
  // and exit the app. Before the NavigatorPopHandler wrap, handlePopRoute()
  // returned false here (root navigator has one route) and called
  // SystemNavigator.pop() → the app exited even with a detail screen open.
  // The predictive-back gesture was unaffected and already worked; this guards
  // the button path that did not.
  testWidgets('System back button pops the nested stack instead of exiting',
      (tester) async {
    SharedPreferences.setMockInitialValues({'lyne.onboardingDone': true});
    await AppModel.shared.load();

    await tester.pumpWidget(const LyneApp());
    await tester.pump(); // initial frame
    expect(find.text('No stops yet'), findsOneWidget); // on Home (Bus) tab

    // Open Search — SoftRoot PUSHES this onto the nested navigator (it is not a
    // state-swap like the other tabs), so the nested stack now has 2 routes.
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // fade-through
    expect(find.text('Find a stop, bus or place'), findsOneWidget);
    expect(find.text('No stops yet'), findsNothing); // Home is offstage below

    // Simulate the hardware/3-button BACK key. handlePopRoute returns true only
    // if an in-app observer consumed it (i.e. the back did NOT escape to the OS
    // and finish the activity).
    final handled = await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(handled, isTrue); // consumed in-app, not an app exit
    expect(find.text('Find a stop, bus or place'), findsNothing);
    expect(find.text('No stops yet'), findsOneWidget); // back on Home

    // Drain the bounded App-Open-ad preload poll (see note above) so no timer
    // is left pending at teardown.
    await tester.pump(const Duration(seconds: 13));
  });
}
