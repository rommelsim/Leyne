// Onboarding flow + AppModel persistence.
//
// Covers:
//   • finishOnboarding flips the lyne.onboardingDone key.
//   • resetOnboarding clears it.
//   • OnboardingScreen advances on Continue, retreats on Back, exits on Skip,
//     and triggers the location/tracking callbacks at the right step.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lyne/screens/onboarding_screen.dart';
import 'package:lyne/state/app_model.dart';
import 'package:lyne/theme.dart';

Widget _host(Widget child) => MaterialApp(
      theme: LyneTheme.light.materialTheme,
      darkTheme: LyneTheme.dark.materialTheme,
      home: child,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppModel.shared.load();
  });

  group('AppModel onboarding persistence', () {
    test('defaults to not done on a fresh install', () {
      expect(AppModel.shared.onboardingDone, isFalse);
    });

    test('finishOnboarding persists across reload', () async {
      AppModel.shared.finishOnboarding();
      expect(AppModel.shared.onboardingDone, isTrue);
      await AppModel.shared.load();
      expect(AppModel.shared.onboardingDone, isTrue);
    });

    test('resetOnboarding clears the flag', () async {
      AppModel.shared.finishOnboarding();
      AppModel.shared.resetOnboarding();
      expect(AppModel.shared.onboardingDone, isFalse);
      await AppModel.shared.load();
      expect(AppModel.shared.onboardingDone, isFalse);
    });
  });

  group('OnboardingScreen', () {
    testWidgets('renders the intro step on first frame', (tester) async {
      await tester.pumpWidget(_host(OnboardingScreen(
        onDone: () {},
        onRequestLocation: () {},
        onRequestTracking: () {},
      )));
      await tester.pump();
      expect(find.text('LEYNE'), findsOneWidget);
      expect(find.text('Right on cue.'), findsOneWidget);
      // Back button hidden on the first step (opacity 0).
      final back = tester.widget<Opacity>(find
          .ancestor(
              of: find.text('Back'), matching: find.byType(Opacity))
          .first);
      expect(back.opacity, 0);
    });

    testWidgets('Skip calls onDone', (tester) async {
      var doneCalls = 0;
      await tester.pumpWidget(_host(OnboardingScreen(
        onDone: () => doneCalls++,
        onRequestLocation: () {},
        onRequestTracking: () {},
      )));
      await tester.pump();
      await tester.tap(find.text('Skip'));
      await tester.pump();
      expect(doneCalls, 1);
    });

    testWidgets('Continue advances through steps and fires priming callbacks',
        (tester) async {
      var locationCalls = 0;
      var trackingCalls = 0;
      var doneCalls = 0;
      await tester.pumpWidget(_host(OnboardingScreen(
        onDone: () => doneCalls++,
        onRequestLocation: () => locationCalls++,
        onRequestTracking: () => trackingCalls++,
      )));
      await tester.pump();

      // Step 0 → 1 → 2 → 3.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Continue'));
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(find.text('STEP 3 · STAY PRESENT'), findsOneWidget);
      expect(locationCalls, 0);
      expect(trackingCalls, 0);

      // Step 3 → 4 (location-prime).
      await tester.tap(find.text('Continue'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('STEP 4 · LOCATION'), findsOneWidget);

      // Step 4 → 5: triggers onRequestLocation AND advances.
      await tester.tap(find.text('Continue'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(locationCalls, 1);
      expect(find.text('STEP 5 · ADS'), findsOneWidget);

      // Step 5: triggers onRequestTracking but does NOT call onDone
      // (the host drives dismissal once consent resolves).
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(trackingCalls, 1);
      expect(doneCalls, 0);
    });

    testWidgets('Back walks the user back one step', (tester) async {
      await tester.pumpWidget(_host(OnboardingScreen(
        onDone: () {},
        onRequestLocation: () {},
        onRequestTracking: () {},
      )));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('STEP 1 · PIN'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('LEYNE'), findsOneWidget);
    });

    testWidgets('rapid double-tap on the location step cannot skip the ATT '
        'step', (tester) async {
      var locationCalls = 0;
      var trackingCalls = 0;
      await tester.pumpWidget(_host(OnboardingScreen(
        onDone: () {},
        onRequestLocation: () => locationCalls++,
        onRequestTracking: () => trackingCalls++,
      )));
      await tester.pump();

      // Advance to the location step (step 4).
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Continue'));
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(find.text('STEP 4 · LOCATION'), findsOneWidget);

      // Two taps in quick succession — the second lands while the
      // multi-tap lock is still engaged and must be ignored, so the ATT
      // step's onRequestTracking never fires off the back of it.
      await tester.tap(find.text('Continue'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Continue'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 500));

      expect(locationCalls, 1);
      expect(trackingCalls, 0);
      expect(find.text('STEP 5 · ADS'), findsOneWidget);
    });
  });
}
