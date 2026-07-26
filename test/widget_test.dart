// Smoke test for the app shell. Verifies:
//   • The three navigation destinations are present and labeled correctly.
//   • Tapping a tab switches the visible screen.
//
// Doesn't drive DataStore.bootstrap (which would hit the real LTA API);
// data layer logic is covered by test/data_layer_test.dart. We avoid
// pumpAndSettle because the bootstrap banner runs a CircularProgressIndicator
// that never settles in tests (DataStore.referenceState stays "loading"
// since bootstrap isn't invoked here).
//
// Onboarding is pre-completed (lyne.onboardingDone=true) so the app routes
// straight to RootScaffold (past the one-shot LaunchScreen splash — see
// `_skipLaunchScreen` below); the onboarding flow itself is exercised by
// test/onboarding_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lyne/main.dart';
import 'package:lyne/state/app_model.dart';

/// The Flutter-drawn "Departly" launch splash was removed (owner 2026-07-25)
/// — cold start lands straight on the root shell, so tests no longer need a
/// skip step. This helper survives as a single settling pump for the first
/// frame's entrance animations.
Future<void> _skipLaunchScreen(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Root shell shows the three tabs and switches between them', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'lyne.onboardingDone': true});
    await AppModel.shared.load();

    await tester.pumpWidget(const LyneApp());
    await tester.pump(); // initial frame
    await _skipLaunchScreen(tester);

    // All three destinations are present in the bottom navigation (current
    // order: Home · Saved · Alerts, mirroring iOS WSTab). Settings is no
    // longer a tab — it opens as a gear sheet from the Alerts tab. Search is
    // not a bar destination either — it's reached via the Home tab's own
    // search entry point (see the "pops the nested stack" test below) and
    // stays a pushed route (SoftTab.search). MRT lost its destination in the
    // owner walkthrough (2026-07-03): stations open from Home's strip/Search.
    //
    // Soft pill bar (2026-07-25 redesign): only the SELECTED tab renders its
    // text label — resting tabs are icon-only (each still carries its name
    // via Semantics for TalkBack). Home starts selected, so its label is the
    // only one visible; the other two are asserted by icon + semantics.
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Saved'), findsNothing);
    expect(find.text('Alerts'), findsNothing);
    expect(find.byIcon(Icons.bookmark_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    expect(find.bySemanticsLabel('Saved'), findsAtLeastNWidgets(1));
    expect(find.bySemanticsLabel('Alerts'), findsAtLeastNWidgets(1));
    // MRT lost its bottom-bar DESTINATION (2026-07-03) — but "MRT" now
    // legitimately appears as one of Home's All/Buses/MRT filter chips
    // (2026-07-25, parity-audit item 7), so this no longer asserts absence
    // of the text itself; the tab-icon assertions above already cover the
    // bottom bar's actual destinations.

    // The Bus (Home) tab is the initial tab — its header title is visible.
    expect(find.text('Nearby'), findsOneWidget);

    // Switch to Alerts; pump one frame for the tap, one for the layout.
    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // The Alerts screen's status-first summary card (spec item 9,
    // 2026-07-25 — replaced the old static "Service status & your
    // notifications" subtitle) renders "All MRT lines running normally"
    // whenever there are no disruptions, which is always true here since
    // this harness never calls bootstrap(). The bar's visible label follows
    // the selection.
    expect(find.text('All MRT lines running normally'), findsOneWidget);
    expect(find.text('Alerts'), findsAtLeastNWidgets(1));
    expect(find.text('Home'), findsNothing);

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
  testWidgets('System back button pops the nested stack instead of exiting', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'lyne.onboardingDone': true});
    await AppModel.shared.load();

    await tester.pumpWidget(const LyneApp());
    await tester.pump(); // initial frame
    await _skipLaunchScreen(tester);
    expect(find.text('Nearby'), findsOneWidget); // on Home (Bus) tab

    // Open Search — no longer a bottom-bar destination, so this goes through
    // Home's own tap-to-search pill (onOpenSearch), same as a real user
    // reaching it from Home. (Prior to the 2026-07-25 loading-skeleton pass
    // this tapped the empty state's "Search" text button — that button no
    // longer renders while `referenceState` is stuck "loading" in this test
    // harness, which never calls `bootstrap()`; the always-present search
    // pill is the more realistic entry point regardless of load state.)
    // SoftRoot still PUSHES it onto the nested navigator (it is not a
    // state-swap like the other tabs), so the nested stack now has 2 routes.
    await tester.tap(find.text('Stop, bus, MRT or postal code'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // fade-through
    expect(find.text('Find a stop, bus or place'), findsOneWidget);
    expect(find.text('Nearby'), findsNothing); // Home is offstage below

    // Simulate the hardware/3-button BACK key. handlePopRoute returns true only
    // if an in-app observer consumed it (i.e. the back did NOT escape to the OS
    // and finish the activity).
    final handled = await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(handled, isTrue); // consumed in-app, not an app exit
    expect(find.text('Find a stop, bus or place'), findsNothing);
    expect(find.text('Nearby'), findsOneWidget); // back on Home

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
  testWidgets('System back from a non-Home tab returns to Home, not exit', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'lyne.onboardingDone': true});
    await AppModel.shared.load();

    await tester.pumpWidget(const LyneApp());
    await tester.pump(); // initial frame
    await _skipLaunchScreen(tester);
    expect(find.text('Nearby'), findsOneWidget); // on Home (Bus) tab

    // Switch to the Alerts tab (a setState swap — no nested route pushed).
    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('All MRT lines running normally'), findsOneWidget);
    expect(find.text('Nearby'), findsNothing);

    // System BACK from a non-Home tab must be consumed in-app and land on Home.
    final handledFromTab = await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(handledFromTab, isTrue); // NOT an app exit
    expect(find.text('All MRT lines running normally'), findsNothing);
    expect(find.text('Nearby'), findsOneWidget); // back on Home

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
  // PREVIOUS tab — not collapse straight to Home. Path Home → Saved → Alerts:
  // the first BACK must land on Saved (the previous tab), not Home. The earlier
  // "return to Home" fix jumped to Home from any tab "no matter what", losing
  // the middle of the path; SoftRoot._tabHistory now records each tab swap so
  // BACK steps back through them one at a time before exiting from Home.
  // (The middle tab was MRT until the 3-tab walkthrough change; Saved plays
  // the same role now.)
  testWidgets('System back retraces tab history, not straight to Home', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'lyne.onboardingDone': true});
    await AppModel.shared.load();

    await tester.pumpWidget(const LyneApp());
    await tester.pump(); // initial frame
    await _skipLaunchScreen(tester);
    expect(find.text('Nearby'), findsOneWidget); // on Home (Bus) tab

    // Home → Saved (a setState tab swap). The Saved destination becomes
    // selected (filled bookmark).
    await tester.tap(find.byIcon(Icons.bookmark_outline_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // fade-through
    expect(
      find.byIcon(Icons.bookmark_rounded),
      findsAtLeastNWidgets(1),
    ); // Saved
    expect(find.text('Nearby'), findsNothing); // Home not shown

    // Saved → Alerts (another tab swap).
    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('All MRT lines running normally'), findsOneWidget);

    // BACK #1 must retrace to Saved — NOT jump to Home.
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('All MRT lines running normally'), findsNothing);
    expect(
      find.byIcon(Icons.bookmark_rounded),
      findsAtLeastNWidgets(1),
    ); // Saved
    expect(find.text('Nearby'), findsNothing); // crucially NOT Home

    // BACK #2 retraces to Home.
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Nearby'), findsOneWidget); // back on Home

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
  testWidgets('BACK ownership (setFrameworkHandlesBack) tracks navigation depth', (
    tester,
  ) async {
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
    await _skipLaunchScreen(tester);
    expect(find.text('Nearby'), findsOneWidget); // Home (Bus) tab

    // At the Home root with nothing pushed, BACK should exit → the OS owns it,
    // so the framework must have announced it does NOT handle back.
    expect(
      handlesBack,
      isNotEmpty,
      reason: 'SoftRoot must announce BACK ownership to the engine',
    );
    expect(
      handlesBack.last,
      isFalse,
      reason: 'At the Home root the OS owns BACK (app exits)',
    );

    // Switch to a non-Home tab (a setState swap — no nested route pushed). BACK
    // must now be consumed in-app (retrace to Home), so Flutter MUST claim it —
    // otherwise the OnBackInvoked path finishes the activity (the reported bug).
    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('All MRT lines running normally'), findsOneWidget);
    expect(
      handlesBack.last,
      isTrue,
      reason:
          'Off the Home root Flutter must own BACK so Android does not '
          'finish the activity (the 2.8.x exit-on-back regression)',
    );

    // Returning to Home hands BACK ownership back to the OS.
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Nearby'), findsOneWidget); // back on Home
    expect(
      handlesBack.last,
      isFalse,
      reason: 'Back at the Home root the OS owns BACK again',
    );

    // Drain the bounded App-Open-ad preload poll (see note above) so no timer
    // is left pending at teardown.
    await tester.pump(const Duration(seconds: 13));

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });
}
