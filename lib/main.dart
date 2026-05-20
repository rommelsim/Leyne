// Leyne — entry point.
//
// • Triggers DataStore.bootstrap() (parallel Bus Stops + Bus Services pull,
//   results disk-cached weekly) at startup so the tabs find data when
//   they're tapped.
// • Wires both LyneTheme.light and dark and lets the system pick — no
//   in-app toggle for now (legacy followed the system too).
// • Warns at debug time if LTA_API_KEY is missing.

import 'package:flutter/material.dart';

import 'data/data_store.dart';
import 'data/lta_config.dart';
import 'screens/onboarding_screen.dart';
import 'screens/root_scaffold.dart';
import 'services/ad_consent.dart' show AdConsent, kTestDeviceIdentifiers;
import 'services/deep_link_service.dart';
import 'services/location_service.dart';
import 'state/app_model.dart';
import 'theme.dart';

/// Top-level navigator key so non-widget code (DeepLinkService) can
/// push routes onto the global navigator.
final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LtaConfig.assertConfigured();
  // AppModel reads persisted pins/recents/settings from shared_preferences;
  // await this so Home opens with the user's saved pins on screen, not an
  // empty list that flickers in once load() resolves.
  await AppModel.shared.load();
  // Kick off the 1-second tick now (live ETA countdown + arrival refresh).
  // Tests skip this so they exit without a pending periodic timer.
  AppModel.shared.startTicker();
  // Fire-and-forget — the banner in RootScaffold shows loading/error state
  // while this resolves. Tabs don't await this; data-bound screens read
  // DataStore.referenceState themselves.
  DataStore.shared.bootstrap();
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
    AdConsent.gatherThenStart(
      testDeviceIdentifiers: kTestDeviceIdentifiers,
    );
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
    return MaterialApp(
      title: 'Leyne',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: LyneTheme.light.materialTheme,
      darkTheme: LyneTheme.dark.materialTheme,
      navigatorKey: _navigatorKey,
      home: const _AppRoot(),
    );
  }
}

/// Routes between OnboardingScreen and RootScaffold based on the
/// persisted onboarding flag. Listens to AppModel so the "Show again"
/// entry in Settings can re-enter onboarding mid-session.
class _AppRoot extends StatelessWidget {
  const _AppRoot();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppModel.shared,
      builder: (context, _) {
        if (AppModel.shared.onboardingDone) {
          return const RootScaffold();
        }
        return OnboardingScreen(
          onDone: AppModel.shared.finishOnboarding,
          onRequestLocation: () {
            // Fire-and-forget: the OS dialog races with the step
            // transition, matching the legacy iOS behaviour.
            LocationService.shared.requestAndStart();
          },
          onRequestTracking: () async {
            // UMP → ATT → MobileAds.initialize, then dismiss onboarding
            // so the user lands on Home. AdConsent is idempotent.
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
