// Smoke test for the SG Transit redesign: drives the launch → onboarding flow.
//
// The redesign is now wired to live LTA DataMall data and fires the real
// system permission prompts, so a plugin-free widget test only exercises the
// boot + onboarding chrome (which no longer has the Android/iOS preview
// toggle). The deeper home/stop/route screens require live data + location and
// are covered by on-device verification, not this test.
//
// Uses explicit pump(Duration) (never pumpAndSettle) because the redesign has
// continuously-repeating animations (launch ring, live-bus pulse).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lyne/screens/redesign/redesign_app.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('launch → onboarding welcome (de-prototyped, no platform toggle)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: RedesignRoot()));
    await tester.pump();

    // Launch splash.
    expect(find.text('SG Transit'), findsOneWidget);

    // Auto-advance to onboarding (2s timer); first-run (no persisted flag).
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 400));

    // Welcome — the Android/iOS preview toggle has been removed.
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Android'), findsNothing);
    expect(find.text('iOS'), findsNothing);

    // Plugin-free advance: Get started → notifications → (Not now) → location.
    // The "Allow…" buttons fire real permission prompts, so we stop here.
    await tester.tap(find.text('Get started'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Allow notifications'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Allow while using app'), findsOneWidget);
  });
}
