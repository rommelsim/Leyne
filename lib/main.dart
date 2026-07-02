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
import 'package:package_info_plus/package_info_plus.dart';
import 'package:workmanager/workmanager.dart';

import 'data/changelog.dart';
import 'data/data_store.dart';
import 'data/lta_config.dart';
import 'data/mrt_geo.dart';
import 'l10n/app_localizations.dart';
import 'screens/onboarding_screen.dart';
import 'screens/v2/soft_bus_screen.dart';
import 'screens/v2/soft_root.dart';
import 'screens/v2/soft_stop_screen.dart';
import 'screens/whats_new_screen.dart';
import 'services/ad_consent.dart' show AdConsent, kTestDeviceIdentifiers;
import 'services/alerts_background.dart';
import 'services/analytics_service.dart';
import 'services/app_open_ad.dart';
import 'services/deep_link_service.dart';
import 'services/location_service.dart';
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
  // Resolve the running app version before the first frame so the What's
  // New screen's routing decision is stable. Non-fatal if it fails — the
  // screen simply won't show.
  try {
    final info = await PackageInfo.fromPlatform();
    AppModel.shared.setCurrentVersion(info.version);
  } catch (_) {
    /* package_info unavailable — skip What's New */
  }
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
    // Push the Soft stop screen on the root navigator. If the
    // payload identifies a specific bus, follow with a SoftBusScreen
    // push so the user lands directly on the tracking view.
    navigator.push(
      MaterialPageRoute(
        builder: (_) => SoftStopScreen(
          stopCode: code,
          onBack: () => navigator.pop(),
          onOpenBus: (svc) => navigator.push(
            MaterialPageRoute(
              builder: (_) => SoftBusScreen(
                stopCode: code,
                svc: svc,
                onBack: () => navigator.pop(),
              ),
            ),
          ),
          onSeeAll: () {},
        ),
      ),
    );
    if (no != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigator.push(
          MaterialPageRoute(
            builder: (_) => SoftBusScreen(
              stopCode: code,
              svc: no,
              onBack: () => navigator.pop(),
            ),
          ),
        );
      });
    }
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
      kAlertsRefreshTask,          // unique task name
      kAlertsRefreshTask,          // task name passed to callbackDispatcher
      frequency: const Duration(minutes: 15),
      // keepAlive: true so Android 12+ doesn't skip our task on the
      // first few scheduling windows.
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy:
          ExistingPeriodicWorkPolicy.keep, // don't reset the clock
    );
  }

  // Boot-time prompt for existing users past onboarding: if the system
  // has never asked for POST_NOTIFICATIONS and our intent (toggle) is
  // ON, fire the prompt now. Covers the upgrade path from versions
  // before onboarding step 3 became an actual permission ask.
  if (AppModel.shared.onboardingDone && AppModel.shared.notificationsEnabled) {
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
  // First-run users gather consent from the onboarding "Ads" step instead
  // — running it here would race the priming screen and the OS prompts
  // would show before the user sees the explanation. Skippers fall through
  // to here on their next launch (AdConsent is idempotent).
  if (AppModel.shared.onboardingDone) {
    AdConsent.gatherThenStart(testDeviceIdentifiers: kTestDeviceIdentifiers);
  }
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
              title: 'Leyne',
              debugShowCheckedModeBanner: false,
              themeMode: AppModel.shared.themeMode,
              theme: LyneTheme.light.materialTheme(dynamicScheme: lightDynamic),
              darkTheme: LyneTheme.dark.materialTheme(dynamicScheme: darkDynamic),
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

/// Routes between OnboardingScreen, WhatsNewScreen and RootScaffold based on
/// persisted state. Listens to AppModel so the "Show again" entry in
/// Settings can re-enter onboarding mid-session, and so dismissing What's
/// New drops straight through to Home.
class _AppRoot extends StatelessWidget {
  const _AppRoot();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppModel.shared,
      builder: (context, _) {
        if (AppModel.shared.onboardingDone) {
          // A returning user who just updated into a build with release
          // notes sees them once before Home.
          final wn = AppModel.shared.whatsNewVersion;
          if (wn != null) {
            return WhatsNewScreen(
              version: wn,
              entry: kChangelog[wn]!,
              onDismiss: AppModel.shared.markWhatsNewSeen,
            );
          }
          return const SoftRoot();
        }
        return OnboardingScreen(
          onRequestLocation: () {
            // Fire-and-forget: the OS dialog races with the step
            // transition, matching the legacy iOS behaviour.
            LocationService.shared.requestAndStart();
          },
          onRequestNotifications: () {
            // Fire-and-forget like onRequestLocation — the step has
            // already advanced; the OS prompt races with the
            // transition. AppModel handles permission + scheduling.
            AppModel.shared.setNotificationsEnabled(true);
          },
          onFinish: () async {
            // UMP consent (Android only — no ATT), then MobileAds.initialize,
            // then dismiss onboarding. AdConsent.gatherThenStart is a no-op
            // for ATT on Android; the dedicated ATT primer view was removed.
            await AdConsent.gatherThenStart(
              testDeviceIdentifiers: kTestDeviceIdentifiers,
            );
            AppModel.shared.finishOnboarding();
          },
        );
      },
    );
  }
}
