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
import 'screens/root_scaffold.dart';
import 'services/ad_consent.dart';
import 'services/deep_link_service.dart';
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
  AdConsent.gatherThenStart();
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
      home: const RootScaffold(),
    );
  }
}
