// Onboarding flow + AppModel persistence.
//
// Covers:
//   • finishOnboarding flips the lyne.onboardingDone key.
//   • resetOnboarding clears it.
//   • OnboardingScreen renders step 0 on the first frame.
//   • There is no Skip — every user passes through all priming steps.
//   • Continue/Back navigate correctly and fire callbacks at the right steps.
//   • Rapid multi-tap on the location step cannot skip the notifications step.
//
// New flow (5 steps, no ATT):
//   0 welcome → 1 live → 2 location primer → 3 notif primer → 4 done

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lyne/screens/onboarding_screen.dart';
import 'package:lyne/state/app_model.dart';
import 'package:lyne/theme.dart';

Widget _host(Widget child) => MaterialApp(
  theme: LyneTheme.light.materialTheme(),
  darkTheme: LyneTheme.dark.materialTheme(),
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
    testWidgets('renders the welcome step on first frame', (tester) async {
      await tester.pumpWidget(
        _host(
          OnboardingScreen(
            onRequestNotifications: () {},
            onRequestLocation: () {},
            onFinish: () {},
          ),
        ),
      );
      await tester.pump();
      // Step 0 welcome: wordmark text + tagline visible.
      expect(find.text('leyne'), findsOneWidget);
      expect(find.textContaining('Singapore'), findsOneWidget);
      // Back button hidden on step 0 (opacity 0).
      final back = tester.widget<Opacity>(
        find
            .ancestor(of: find.text('Back'), matching: find.byType(Opacity))
            .first,
      );
      expect(back.opacity, 0);
    });

    testWidgets('there is no Skip button', (tester) async {
      await tester.pumpWidget(
        _host(
          OnboardingScreen(
            onRequestNotifications: () {},
            onRequestLocation: () {},
            onFinish: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Skip'), findsNothing);
    });

    testWidgets(
      'Continue advances through all steps and fires callbacks at the right step',
      (tester) async {
        var locationCalls = 0;
        var notificationCalls = 0;
        var finishCalls = 0;

        await tester.pumpWidget(
          _host(
            OnboardingScreen(
              onRequestLocation: () => locationCalls++,
              onRequestNotifications: () => notificationCalls++,
              onFinish: () => finishCalls++,
            ),
          ),
        );
        await tester.pump();

        // Step 0 → 1: welcome "Get started".
        await tester.tap(find.text('Get started'));
        await tester.pump(const Duration(milliseconds: 500));
        // Step 1 shows the live-wedge kicker (rendered uppercase by _Kicker).
        expect(find.textContaining('WHY LEYNE'), findsOneWidget);
        expect(locationCalls, 0);
        expect(notificationCalls, 0);

        // Step 1 → 2: live "Continue".
        await tester.tap(find.text('Continue'));
        await tester.pump(const Duration(milliseconds: 500));
        // Step 2: location primer.
        expect(find.textContaining('Find stops around you'), findsOneWidget);
        expect(locationCalls, 0);
        expect(notificationCalls, 0);

        // Step 2 → 3: location primary is the neutral "Continue" (no skip, per
        // App Store 5.1.1(iv) / iOS parity) — it fires onRequestLocation + advances.
        // `.last`: the live step (step 1) also says "Continue" and lingers one
        // frame in the AnimatedSwitcher; the incoming step's CTA is built last.
        await tester.tap(find.text('Continue').last);
        await tester.pump(const Duration(milliseconds: 500));
        expect(locationCalls, 1);
        expect(notificationCalls, 0);
        // Step 3: notifications primer.
        expect(find.textContaining('Never miss your bus'), findsOneWidget);

        // Step 3 → 4: "Enable notifications" fires onRequestNotifications + advances.
        await tester.tap(find.text('Enable notifications'));
        await tester.pump(const Duration(milliseconds: 500));
        expect(notificationCalls, 1);
        expect(finishCalls, 0);
        // Step 4: done screen.
        expect(find.textContaining('You\'re all set'), findsOneWidget);

        // Step 4: "Enter Leyne" fires onFinish.
        await tester.tap(find.text('Enter Leyne'));
        await tester.pump();
        expect(finishCalls, 1);
      },
    );

    testWidgets(
      'location step has no skip; notification "Maybe later" advances without '
      'firing the notifications callback',
      (tester) async {
        var notificationCalls = 0;

        await tester.pumpWidget(
          _host(
            OnboardingScreen(
              onRequestLocation: () {},
              onRequestNotifications: () => notificationCalls++,
              onFinish: () {},
            ),
          ),
        );
        await tester.pump();

        // Advance to step 2 (location primer).
        await tester.tap(find.text('Get started'));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.text('Continue'));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.textContaining('Find stops around you'), findsOneWidget);

        // Location step must NOT offer any skip/exit before the prompt
        // (App Store 5.1.1(iv) / iOS parity): no "Not now", no "Skip".
        expect(find.text('Not now'), findsNothing);
        expect(find.text('Skip'), findsNothing);

        // The only way forward is the neutral "Continue" primary. `.last`
        // disambiguates from the live step's lingering "Continue" mid-transition.
        await tester.tap(find.text('Continue').last);
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.textContaining('Never miss your bus'), findsOneWidget);

        // Notification step DOES keep a skip — "Maybe later" advances but does
        // NOT call onRequestNotifications.
        await tester.tap(find.text('Maybe later'));
        await tester.pump(const Duration(milliseconds: 500));
        expect(notificationCalls, 0);
        // Should now be on step 4 (done).
        expect(find.textContaining('You\'re all set'), findsOneWidget);
      },
    );

    testWidgets('Back walks the user back one step', (tester) async {
      await tester.pumpWidget(
        _host(
          OnboardingScreen(
            onRequestNotifications: () {},
            onRequestLocation: () {},
            onFinish: () {},
          ),
        ),
      );
      await tester.pump();

      // Advance to step 1.
      await tester.tap(find.text('Get started'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('Always up to the minute'), findsOneWidget);

      // Back returns to step 0.
      await tester.tap(find.text('Back'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('leyne'), findsOneWidget);
    });

    testWidgets(
      'rapid double-tap on the location step cannot skip the notifications step',
      (tester) async {
        var locationCalls = 0;
        var notificationCalls = 0;

        await tester.pumpWidget(
          _host(
            OnboardingScreen(
              onRequestNotifications: () => notificationCalls++,
              onRequestLocation: () => locationCalls++,
              onFinish: () {},
            ),
          ),
        );
        await tester.pump();

        // Advance to step 2 (location primer).
        await tester.tap(find.text('Get started'));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.text('Continue'));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.textContaining('Find stops around you'), findsOneWidget);

        // Two taps in quick succession — the second must be swallowed by the
        // multi-tap lock so onRequestNotifications never fires off the back of it.
        // `.last` targets the location step's "Continue" (the live step's
        // identically-labelled CTA lingers one frame mid-transition).
        await tester.tap(find.text('Continue').last);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.text('Continue').last, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 500));

        expect(locationCalls, 1);
        expect(notificationCalls, 0);
        // Should be on step 3 (notifications primer), not step 4 (done).
        expect(find.textContaining('Never miss your bus'), findsOneWidget);
      },
    );
  });
}
