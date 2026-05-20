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
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LtaConfig.assertConfigured();
  // Fire-and-forget — the banner in RootScaffold shows loading/error state
  // while this resolves. Tabs don't await this; data-bound screens (Task
  // #7+) read DataStore.referenceState themselves.
  DataStore.shared.bootstrap();
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
      home: const RootScaffold(),
    );
  }
}
