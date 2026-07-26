// Leyne — entry point.
//
// • Triggers DataStore.bootstrap() (parallel Bus Stops + Bus Services pull,
//   results disk-cached weekly) at startup so the tabs find data when
//   they're tapped.
// • Wires both LyneTheme.light and dark and lets the system pick — no
//   in-app toggle for now (legacy followed the system too).
// • Warns at debug time if LTA_API_KEY is missing.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';

import 'data/data_store.dart';
import 'data/lta_config.dart';
import 'data/mrt_geo.dart';
import 'l10n/app_localizations.dart';
import 'screens/v2/soft_root.dart';
import 'screens/v2/soft_stop_screen.dart';
import 'services/ad_consent.dart' show AdConsent, kTestDeviceIdentifiers;
import 'services/alerts_background.dart';
import 'services/analytics_service.dart';
import 'services/app_open_ad.dart';
import 'services/deep_link_service.dart';
import 'services/notifications.dart';
import 'services/review_prompt.dart';
import 'state/app_model.dart';
import 'theme.dart';

/// Top-level navigator key so non-widget code (DeepLinkService) can
/// push routes onto the global navigator.
final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock the whole app to portrait — no auto-rotation. Belt-and-braces with
  // android:screenOrientation="portrait" in AndroidManifest.xml (the manifest
  // is the authoritative OS-level lock; this also pins the Flutter engine).
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);
  LtaConfig.assertConfigured();
  // Initialise Firebase before the first frame so product events log from
  // launch. Guarded: a build without google-services.json (forks / CI /
  // pre-setup) has no default options and initializeApp throws — we swallow
  // it and AnalyticsService stays in its no-op state (markReady never runs).
  // Mirrors iOS, where a missing GoogleService-Info.plist skips configure().
  try {
    await Firebase.initializeApp();
    AnalyticsService.markReady();
  } catch (e) {
    debugPrint('[firebase] init skipped (no config?): $e');
  }
  // AppModel reads persisted pins/recents/settings from shared_preferences;
  // await this so Home opens with the user's saved pins on screen, not an
  // empty list that flickers in once load() resolves.
  await AppModel.shared.load();
  // Notification-tap handler: parses the payload that we set during
  // scheduling (`arrival.<stopCode>.<busNo>` or
  // `alight.<busNo>.<stopName>`) and drills into DetailScreen for that
  // bus. Set BEFORE init() so the initial cold-start launch tap (replayed
  // by the plugin via getNotificationAppLaunchDetails) lands.
  NotificationsService.shared.onNotificationTapped = (payload) {
    // A notification tap is taking the user to a specific stop/bus — suppress
    // the App Open ad on this foreground so they get content, not an ad.
    AppOpenAdManager.instance.suppressNext();
    final parts = payload.split('.');
    // A notification tap is a strong value signal — record it for retention
    // analysis (kind = arrival / track / alight). Mirrors iOS LeyneApp.swift.
    AnalyticsService.notificationTapped(parts.isNotEmpty ? parts.first : '');
    if (parts.length < 3) return;
    final kind = parts[0];
    String? stopCode;
    String? busNo;
    if (kind == 'arrival' || kind == 'track') {
      stopCode = parts[1];
      busNo = parts[2];
    } else if (kind == 'alight') {
      stopCode = AppModel.shared.activeAlight?.stopCode;
      busNo = parts[1];
    }
    if (stopCode == null) return;
    // A useful-notification tap is the strongest "this app delivered value"
    // signal — count it toward the Play Store ratings prompt (fires once, on
    // the 2nd such moment). Fire-and-forget; never blocks navigation.
    unawaited(ReviewPrompt.recordValueMomentAndMaybeAsk());
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    final code = stopCode;
    final no = busNo;
    // ONE push: the Stop screen with the notified service already featured
    // in its hero. It used to push Stop and then stack a SoftBusScreen on top
    // — iOS retired that second screen (WSRoot: "notification taps land on the
    // Stop view with the tapped service pinned as the hero"), and the extra
    // level meant Back from a notification took two taps to reach the app.
    navigator.push(
      MaterialPageRoute(
        builder: (_) => SoftStopScreen(
          stopCode: code,
          initialService: no,
          onBack: () => navigator.pop(),
        ),
      ),
    );
  };
  // Initialize the local-notifications plugin (tz database + Android
  // channel) so AppModel can schedule arrival alerts as soon as a pinned
  // bus's ETA crosses the lead window. Fire-and-forget — the only failure
  // mode is no-notifications, which the toggle already gracefully
  // handles via the auth state.
  NotificationsService.shared.init();

  // Register WorkManager for the background train-alerts poll (Android only).
  // The task runs ~every 15 minutes (WorkManager's OS-enforced minimum)
  // even when the app is closed, so a new MRT/LRT breakdown can notify
  // without the user having the app open. iOS uses BGAppRefreshTask instead
  // (see LeyneApp.swift / BGTaskScheduler registration there).
  if (Platform.isAndroid) {
    await Workmanager().initialize(
      callbackDispatcher,
      // isInDebugMode: true, // uncomment to force immediate execution in debug
    );
    await Workmanager().registerPeriodicTask(
      kAlertsRefreshTask, // unique task name
      kAlertsRefreshTask, // task name passed to callbackDispatcher
      frequency: const Duration(minutes: 15),
      // keepAlive: true so Android 12+ doesn't skip our task on the
      // first few scheduling windows.
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy:
          ExistingPeriodicWorkPolicy.keep, // don't reset the clock
    );
  }

  // Boot-time prompt: if the system has never asked for POST_NOTIFICATIONS
  // and our intent (toggle) is ON, fire the prompt now.
  if (AppModel.shared.notificationsEnabled) {
    () async {
      final status = await NotificationsService.shared.currentStatus();
      if (status == NotifPermStatus.notDetermined) {
        await AppModel.shared.setNotificationsEnabled(true);
      }
    }();
  }
  // Kick off the 1-second tick now (live ETA countdown + arrival refresh).
  // Tests skip this so they exit without a pending periodic timer.
  AppModel.shared.startTicker();
  // Fire-and-forget — the banner in RootScaffold shows loading/error state
  // while this resolves. Tabs don't await this; data-bound screens read
  // DataStore.referenceState themselves.
  DataStore.shared.bootstrap();
  // Fire-and-forget — the MRT tab is not the launch tab, so the dataset
  // will be ready long before the user first taps it.
  unawaited(MrtGeo.load());
  // UMP consent → ATT prompt → MobileAds.initialize. Also fire-and-forget;
  // the AdBanner widget polls AdConsent.started before requesting ads.
  // The test-device list is empty by default — the iOS Simulator and
  // Android Emulator are auto-detected as test devices by the SDK, so
  // dev builds already render "Test Ad" creatives. Populate
  // kTestDeviceIdentifiers in ad_consent.dart with physical-device
  // hashes if you also want those to see test ads.
  //
  // Runs for every launch now that onboarding (which used to own the "Ads"
  // consent step on first run) is gone. AdConsent is idempotent.
  AdConsent.gatherThenStart(testDeviceIdentifiers: kTestDeviceIdentifiers);
  // Subscribe to Universal Links / App Links so an external
  // https://lyne.sg/stop/12345 tap routes into DetailScreen.
  DeepLinkService.instance.start(_navigatorKey);
  runApp(const LyneApp());
}

class LyneApp extends StatelessWidget {
  const LyneApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuild MaterialApp when the user changes Appearance / Language so the
    // themeMode + locale overrides take effect immediately.
    //
    // Material You (owner decision, 2026-07-02 — supersedes the earlier
    // "stay monochrome" call for Android): DynamicColorBuilder asks the OS
    // for a wallpaper-derived palette on Android 12+ and hands it to
    // LyneTheme.materialTheme() as light/dark ColorSchemes; on older Android
    // (or if the OS has no palette yet) both come back null and
    // materialTheme() falls back to its own seeded palette. Either way,
    // dynamic colour only tints CHROME + ACCENT (NavigationBar/Switch/Chip,
    // LyneTheme.accent/live) — surfaces, MRT line colours, severity colours
    // and crowd colours are unaffected. See theme.dart materialTheme() for
    // the full scope. DynamicColorBuilder sits OUTSIDE the AppModel listener
    // so the platform-channel round trip to fetch the palette (effectively
    // once per process) doesn't re-run every time AppModel notifies.
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return ListenableBuilder(
          listenable: AppModel.shared,
          builder: (context, _) {
            return MaterialApp(
              title: 'Departly',
              debugShowCheckedModeBanner: false,
              themeMode: AppModel.shared.themeMode,
              theme: LyneTheme.light.materialTheme(dynamicScheme: lightDynamic),
              darkTheme: LyneTheme.dark.materialTheme(
                dynamicScheme: darkDynamic,
              ),
              locale: AppModel.shared.locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              navigatorKey: _navigatorKey,
              scaffoldMessengerKey: lyneMessengerKey,
              home: const _AppRoot(),
            );
          },
        );
      },
    );
  }
}

/// The app root. There is no onboarding — the first-run flow (welcome →
/// wedge → permission primers → grant summary) was removed 2026-07-26 (owner
/// call, matching iOS in the same pass), so cold start goes straight to the
/// board after the OS-level launch window and each permission is asked for at
/// the moment it is needed: location on Home, notifications on the first
/// alert (or at boot when the toggle is already on), UMP consent at launch.
///
/// The Flutter-drawn "Departly" splash overlay is likewise GONE (owner
/// 2026-07-25).
class _AppRoot extends StatelessWidget {
  const _AppRoot();

  @override
  Widget build(BuildContext context) => const SoftRoot();
}
