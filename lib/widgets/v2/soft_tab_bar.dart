// SoftTabBar (Material 3) — bottom NavigationBar with pill-indicator
// behind the active icon. Mirrors the iOS SoftTabBar's tab order:
// Home / Nearby / Settings / Search.
//
// SoftBottomBar stacks the AdMob banner above SoftTabBar for the
// tabbed screens (Home / Nearby / Settings) — this is what those
// Scaffolds mount as bottomNavigationBar.

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../ad_banner.dart';

enum SoftTab { home, nearby, settings, search }

class SoftTabBar extends StatelessWidget {
  const SoftTabBar({super.key, required this.selection, required this.onSelect});

  final SoftTab selection;
  final ValueChanged<SoftTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return NavigationBar(
      selectedIndex: SoftTab.values.indexOf(selection),
      onDestinationSelected: (i) => onSelect(SoftTab.values[i]),
      backgroundColor: t.bg,
      indicatorColor: t.liveBg,
      surfaceTintColor: Colors.transparent,
      destinations: const [
        NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home'),
        NavigationDestination(
            icon: Icon(Icons.near_me_outlined),
            selectedIcon: Icon(Icons.near_me_rounded),
            label: 'Nearby'),
        NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings'),
        NavigationDestination(
            icon: Icon(Icons.search_rounded),
            label: 'Search'),
      ],
    );
  }
}

/// Bottom composite for tabbed views: AdBanner on top, SoftTabBar
/// below. The banner widget self-suppresses (zero-size SizedBox) when
/// ads are disabled or in screenshot mode, so the tab bar sits flush
/// in those builds.
class SoftBottomBar extends StatelessWidget {
  const SoftBottomBar(
      {super.key, required this.selection, required this.onSelect});

  final SoftTab selection;
  final ValueChanged<SoftTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AdBanner(),
        SoftTabBar(selection: selection, onSelect: onSelect),
      ],
    );
  }
}
