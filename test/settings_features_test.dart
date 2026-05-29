// Settings feature tests — the About / Appearance / Language / Notifications
// work added this cycle, plus AppModel preference persistence.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lyne/l10n/app_localizations.dart';
import 'package:lyne/screens/about_screen.dart';
import 'package:lyne/screens/notifications_screen.dart';
import 'package:lyne/screens/settings_screen.dart';
import 'package:lyne/state/app_model.dart';
import 'package:lyne/theme.dart';

Widget _host(Widget child) => MaterialApp(
      theme: LyneTheme.light.materialTheme(),
      darkTheme: LyneTheme.dark.materialTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // permission_handler and flutter_local_notifications reach native code
  // through platform channels that don't exist under flutter test. Stub
  // them so the notification toggle can exercise its grant path: every
  // permission resolves to "granted" (index 1) and the local-notifications
  // plugin accepts every call.
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mockNotificationChannels() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (call) async {
        switch (call.method) {
          case 'checkPermissionStatus':
          case 'checkServiceStatus':
            return 1; // PermissionStatus.granted
          case 'requestPermissions':
            final perms = (call.arguments as List).cast<int>();
            return {for (final p in perms) p: 1};
          case 'shouldShowRequestPermissionRationale':
            return false;
          default:
            return null;
        }
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async {
        switch (call.method) {
          case 'initialize':
          case 'requestNotificationsPermission':
          case 'requestExactAlarmsPermission':
            return true;
          case 'pendingNotificationRequests':
          case 'getActiveNotifications':
            return <Map<String, Object?>>[];
          default:
            return null;
        }
      },
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mockNotificationChannels();
    await AppModel.shared.load();
  });

  group('AppModel preferences', () {
    test('theme mode defaults to system and persists', () async {
      expect(AppModel.shared.themeMode, ThemeMode.system);
      AppModel.shared.setThemeMode(ThemeMode.dark);
      expect(AppModel.shared.themeMode, ThemeMode.dark);
      await AppModel.shared.load();
      expect(AppModel.shared.themeMode, ThemeMode.dark);
    });

    test('locale defaults to null and persists a pick', () async {
      expect(AppModel.shared.locale, isNull);
      AppModel.shared.setLocale(const Locale('zh'));
      expect(AppModel.shared.locale?.languageCode, 'zh');
      await AppModel.shared.load();
      expect(AppModel.shared.locale?.languageCode, 'zh');
    });

    test('notifications toggle defaults off and persists', () async {
      expect(AppModel.shared.notificationsEnabled, isFalse);
      await AppModel.shared.setNotificationsEnabled(true);
      expect(AppModel.shared.notificationsEnabled, isTrue);
      await AppModel.shared.load();
      expect(AppModel.shared.notificationsEnabled, isTrue);
    });

    test('search radius defaults to 500 m and persists a pick', () async {
      expect(AppModel.shared.searchRadiusM, 500);
      AppModel.shared.setSearchRadiusM(1000);
      expect(AppModel.shared.searchRadiusM, 1000);
      await AppModel.shared.load();
      expect(AppModel.shared.searchRadiusM, 1000);
    });
  });

  group('SettingsScreen', () {
    testWidgets('shows the trimmed Personalize rows, no Data section',
        (tester) async {
      await tester.pumpWidget(_host(const SettingsScreen()));
      await tester.pump();
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Search radius'), findsOneWidget);
      expect(find.text('24-hour time'), findsOneWidget);
      // Removed this cycle.
      expect(find.text('Refresh interval'), findsNothing);
      expect(find.text('Data saver'), findsNothing);
    });

    testWidgets('Appearance row opens a picker and applies the choice',
        (tester) async {
      await tester.pumpWidget(_host(const SettingsScreen()));
      await tester.pump();
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      // Picker sheet lists all three modes. ("System" also appears as the
      // row's current-value label, hence findsWidgets.)
      expect(find.text('System'), findsWidgets);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(AppModel.shared.themeMode, ThemeMode.dark);
    });

    testWidgets('Language row opens a picker with the SG languages',
        (tester) async {
      await tester.pumpWidget(_host(const SettingsScreen()));
      await tester.pump();
      await tester.tap(find.text('Language'));
      await tester.pumpAndSettle();
      expect(find.text('中文'), findsOneWidget);
      expect(find.text('Bahasa Melayu'), findsOneWidget);
      await tester.tap(find.text('中文'));
      await tester.pumpAndSettle();
      expect(AppModel.shared.locale?.languageCode, 'zh');
    });

    testWidgets('Search radius row opens a picker and applies the choice',
        (tester) async {
      await tester.pumpWidget(_host(const SettingsScreen()));
      await tester.pump();
      await tester.tap(find.text('Search radius'));
      await tester.pumpAndSettle();
      // Picker lists the radius presets.
      expect(find.text('250 m'), findsOneWidget);
      expect(find.text('1 km'), findsOneWidget);
      await tester.tap(find.text('1 km'));
      await tester.pumpAndSettle();
      expect(AppModel.shared.searchRadiusM, 1000);
    });

    testWidgets('About card navigates to the About screen', (tester) async {
      await tester.pumpWidget(_host(const SettingsScreen()));
      await tester.pump();
      await tester.tap(find.text("What's new"));
      await tester.pumpAndSettle();
      expect(find.byType(AboutScreen), findsOneWidget);
      // MicroLabel renders its label uppercased.
      expect(find.text('THIS BUILD'), findsOneWidget);
      // "Coming soon" sits below the fold — scroll it into view.
      await tester.scrollUntilVisible(find.text('COMING SOON'), 240,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('COMING SOON'), findsOneWidget);
    });

    testWidgets('Notifications row navigates and toggles the preference',
        (tester) async {
      await tester.pumpWidget(_host(const SettingsScreen()));
      await tester.pump();
      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(AppModel.shared.notificationsEnabled, isFalse);
      await tester.tap(find.text('Arrival alerts'));
      await tester.pumpAndSettle();
      expect(AppModel.shared.notificationsEnabled, isTrue);
    });
  });
}
