// Screen-level widget tests — empty/permission/loaded states across
// Home, Nearby, Search, Settings. Detail is exercised by the smoke
// test in widget_test.dart plus the PinnedCard test which covers its
// drill-in trigger.
//
// All tests use AppModel.forTesting() so the 1-second tick timer
// doesn't fire and leak into other suites.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lyne/screens/home_screen.dart';
import 'package:lyne/screens/nearby_screen.dart';
import 'package:lyne/screens/search_screen.dart';
import 'package:lyne/screens/settings_screen.dart';
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
    // Each test starts with a fresh prefs store.
    SharedPreferences.setMockInitialValues({});
    // Re-load the shared AppModel so the no-pins state is consistent.
    await AppModel.shared.load();
  });

  group('HomeScreen', () {
    testWidgets('empty state when no pins', (tester) async {
      await tester.pumpWidget(_host(const HomeScreen()));
      await tester.pump();
      expect(find.text('No pinned stops yet'), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_outline), findsOneWidget);
      // The LIVE indicator chip is in the AppBar action area.
      expect(find.text('LIVE'), findsOneWidget);
    });

    testWidgets('has "Home" title in AppBar', (tester) async {
      await tester.pumpWidget(_host(const HomeScreen()));
      await tester.pump();
      expect(find.text('Home'), findsOneWidget);
    });
  });

  group('NearbyScreen', () {
    testWidgets('shows location permission prompt when not authorized',
        (tester) async {
      await tester.pumpWidget(_host(const NearbyScreen()));
      // Pump once for initState's status refresh, then a layout pump.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Default permission state in tests is notDetermined → !authorized →
      // permissionPrompt shows.
      expect(find.text('See stops near you'), findsOneWidget);
      expect(find.text('Enable location'), findsOneWidget);
      expect(find.byIcon(Icons.location_on_outlined), findsOneWidget);
    });
  });

  group('SearchScreen', () {
    testWidgets('empty state shows "Stops near me" shortcut + hint',
        (tester) async {
      await tester.pumpWidget(_host(const SearchScreen()));
      await tester.pump();
      expect(find.text('Stops near me'), findsOneWidget);
      // Without any recent searches yet, shows the search-hint copy.
      expect(
          find.text('Search a bus number or a stop name / 5-digit code.'),
          findsOneWidget);
    });

    testWidgets('typing a query shows the DETECTED hint', (tester) async {
      await tester.pumpWidget(_host(const SearchScreen()));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '88');
      await tester.pump();
      // "88" matches the bus-service regex.
      expect(find.textContaining('DETECTED · BUS SERVICE'), findsOneWidget);
    });

    testWidgets('garbage query renders "Nothing matches" state',
        (tester) async {
      await tester.pumpWidget(_host(const SearchScreen()));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'xyzzy nothing matches');
      await tester.pump();
      // DataStore has no data in test mode → no buses, no stops → empty
      // results panel.
      expect(find.textContaining('Nothing matches'), findsOneWidget);
    });

    testWidgets('recent search query renders as a tappable chip',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'lyne.recents': <String>['Bishan', '88'],
      });
      await AppModel.shared.load();
      await tester.pumpWidget(_host(const SearchScreen()));
      await tester.pump();
      expect(find.text('Bishan'), findsOneWidget);
      expect(find.text('88'), findsOneWidget);
      expect(find.text('RECENT'), findsOneWidget);
    });
  });

  group('SettingsScreen', () {
    testWidgets('renders Feedback section with Sound + Haptics toggles',
        (tester) async {
      await tester.pumpWidget(_host(const SettingsScreen()));
      await tester.pump();
      expect(find.text('FEEDBACK'), findsOneWidget);
      expect(find.text('Sound'), findsOneWidget);
      expect(find.text('Haptics'), findsOneWidget);
      // Two switches, one per row.
      expect(find.byType(Switch), findsNWidgets(2));
    });

    testWidgets('toggling Sound persists the new value', (tester) async {
      expect(AppModel.shared.sound, isTrue);
      await tester.pumpWidget(_host(const SettingsScreen()));
      await tester.pump();
      // Tap the first switch (Sound is the first row).
      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      expect(AppModel.shared.sound, isFalse);
    });

    testWidgets('LTA key status row reflects --dart-define state',
        (tester) async {
      await tester.pumpWidget(_host(const SettingsScreen()));
      await tester.pump();
      expect(find.text('LTA DataMall key'), findsOneWidget);
      // In test mode the key is empty (no --dart-define).
      expect(
          find.textContaining('Not set — pass --dart-define'),
          findsOneWidget);
      // Red error icon, not the green check.
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('Theme section documents Follow system', (tester) async {
      await tester.pumpWidget(_host(const SettingsScreen()));
      await tester.pump();
      expect(find.text('Follow system'), findsOneWidget);
      expect(find.text('Light / Dark switches with the OS'), findsOneWidget);
    });
  });
}
