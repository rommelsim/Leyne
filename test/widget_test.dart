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
import 'package:flutter/services.dart';
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
  // and exit the app. SoftRoot keeps the real back-stack in a nested Navigator,
  // but the button path only reaches the ROOT navigator (one route), so without
  // intervention the OS finishes the activity. SoftRoot's root-route PopScope
  // intercepts it: while the nested stack can pop, it pops that instead.
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

  // Regression (2.8.2): the ACTUAL reported bug. Switching tabs via the bottom
  // bar is a setState swap (AnimatedSwitcher), NOT a navigator push — so the
  // nested stack stays at its first route. The 2.8.1 NavigatorPopHandler fix
  // only bridged BACK to the nested navigator's maybePop(), which found nothing
  // to pop on a non-Home tab, so BACK fell through to the OS and the app exited
  // from any tab. SoftRoot's PopScope now falls back to returning to the Home
  // tab when nothing is pushed; only Home-with-nothing-pushed exits.
  testWidgets('System back from a non-Home tab returns to Home, not exit',
      (tester) async {
    SharedPreferences.setMockInitialValues({'lyne.onboardingDone': true});
    await AppModel.shared.load();

    await tester.pumpWidget(const LyneApp());
    await tester.pump(); // initial frame
    expect(find.text('No stops yet'), findsOneWidget); // on Home (Bus) tab

    // Switch to the Alerts tab (a setState swap — no nested route pushed).
    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Service status & your notifications'), findsOneWidget);
    expect(find.text('No stops yet'), findsNothing);

    // System BACK from a non-Home tab must be consumed in-app and land on Home.
    final handledFromTab = await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(handledFromTab, isTrue); // NOT an app exit
    expect(find.text('Service status & your notifications'), findsNothing);
    expect(find.text('No stops yet'), findsOneWidget); // back on Home

    // System BACK from Home with nothing pushed falls through to the OS (exit) —
    // handlePopRoute returns false, i.e. not consumed in-app.
    final handledFromHome = await tester.binding.handlePopRoute();
    await tester.pump();
    expect(handledFromHome, isFalse); // would finish the activity (app exit)

    // Drain the bounded App-Open-ad preload poll (see note above) so no timer
    // is left pending at teardown.
    await tester.pump(const Duration(seconds: 13));
  });

  // Regression (2.8.2, build 43): BACK must retrace the tab history — return to the
  // PREVIOUS tab — not collapse straight to Home. Path Home → MRT → Alerts:
  // the first BACK must land on MRT (the previous tab), not Home. The earlier
  // "return to Home" fix jumped to Home from any tab "no matter what", losing
  // the middle of the path; SoftRoot._tabHistory now records each tab swap so
  // BACK steps back through them one at a time before exiting from Home.
  testWidgets('System back retraces tab history, not straight to Home',
      (tester) async {
    SharedPreferences.setMockInitialValues({'lyne.onboardingDone': true});
    await AppModel.shared.load();

    await tester.pumpWidget(const LyneApp());
    await tester.pump(); // initial frame
    expect(find.text('No stops yet'), findsOneWidget); // on Home (Bus) tab

    // Home → MRT (a setState tab swap). The MRT destination becomes selected.
    await tester.tap(find.byIcon(Icons.train_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // fade-through
    expect(find.byIcon(Icons.train_rounded), findsAtLeastNWidgets(1)); // on MRT
    expect(find.text('No stops yet'), findsNothing); // Home not shown

    // MRT → Alerts (another tab swap).
    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Service status & your notifications'), findsOneWidget);

    // BACK #1 must retrace to MRT — NOT jump to Home.
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Service status & your notifications'), findsNothing);
    expect(find.byIcon(Icons.train_rounded), findsAtLeastNWidgets(1)); // on MRT
    expect(find.text('No stops yet'), findsNothing); // crucially NOT Home

    // BACK #2 retraces to Home (Bus).
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('No stops yet'), findsOneWidget); // back on Home

    // BACK #3 — history empty, on Home, nothing pushed → falls through to the
    // OS (app exit): handlePopRoute returns false (not consumed in-app).
    expect(await tester.binding.handlePopRoute(), isFalse);
    await tester.pump();

    // Drain the bounded App-Open-ad preload poll (see note above) so no timer
    // is left pending at teardown.
    await tester.pump(const Duration(seconds: 13));
  });

  // Regression (2.8.4, build 45): the REAL bug that builds 41/43/44 all shipped
  // broken. The three tests above drive `handlePopRoute()` — the legacy injected
  // BACK key — which reaches PopScope regardless of engine state, so they passed
  // even while the app exited on a real press. On Android 13+ the real button /
  // gesture uses the OnBackInvokedCallback dispatcher, which only delivers BACK
  // to Flutter while `SystemNavigator.setFrameworkHandlesBack(true)` is in effect.
  // SoftRoot's nested Navigator was flipping that to FALSE on every bare tab root,
  // so Android finished the activity (app exit) without PopScope ever running.
  //
  // This test asserts the SIGNAL itself: Flutter must own BACK off the Home root
  // and relinquish it at the Home root. It fails on the old code (which never
  // forced the flag) and passes once SoftRoot drives it from `canExit`.
  testWidgets('BACK ownership (setFrameworkHandlesBack) tracks navigation depth',
      (tester) async {
    SharedPreferences.setMockInitialValues({'lyne.onboardingDone': true});
    await AppModel.shared.load();

    // Record every SystemNavigator.setFrameworkHandlesBack(bool) pushed to the
    // engine. Returning null for all platform calls keeps the rest inert.
    final handlesBack = <bool>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
          handlesBack.add(call.arguments as bool);
        }
        return null;
      },
    );

    await tester.pumpWidget(const LyneApp());
    await tester.pump(); // initial frame
    expect(find.text('No stops yet'), findsOneWidget); // Home (Bus) tab

    // At the Home root with nothing pushed, BACK should exit → the OS owns it,
    // so the framework must have announced it does NOT handle back.
    expect(handlesBack, isNotEmpty,
        reason: 'SoftRoot must announce BACK ownership to the engine');
    expect(handlesBack.last, isFalse,
        reason: 'At the Home root the OS owns BACK (app exits)');

    // Switch to a non-Home tab (a setState swap — no nested route pushed). BACK
    // must now be consumed in-app (retrace to Home), so Flutter MUST claim it —
    // otherwise the OnBackInvoked path finishes the activity (the reported bug).
    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Service status & your notifications'), findsOneWidget);
    expect(handlesBack.last, isTrue,
        reason: 'Off the Home root Flutter must own BACK so Android does not '
            'finish the activity (the 2.8.x exit-on-back regression)');

    // Returning to Home hands BACK ownership back to the OS.
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('No stops yet'), findsOneWidget); // back on Home
    expect(handlesBack.last, isFalse,
        reason: 'Back at the Home root the OS owns BACK again');

    // Drain the bounded App-Open-ad preload poll (see note above) so no timer
    // is left pending at teardown.
    await tester.pump(const Duration(seconds: 13));

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, null);
  });
}
