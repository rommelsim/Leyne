// SoftTabBar (Material 3) — bottom NavigationBar with pill-indicator
// behind the active icon. Mirrors the iOS tab set exactly:
// Home / Settings / Search. There is NO standalone Nearby tab — iOS folds
// Nearby into the Home page (the "Nearby" section), so a separate tab would
// duplicate it.
//
// SoftBottomBar stacks the AdMob banner above SoftTabBar for the
// tabbed screens (Home / Settings) — this is what those Scaffolds mount
// as bottomNavigationBar.

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../ad_banner.dart';

// 2.4.0: Added `favourites` tab — mirrors iOS SoftRoot 4-tab layout:
// Home · Favourites · Settings · Search
enum SoftTab { home, favourites, settings, search }

class SoftTabBar extends StatelessWidget {
  const SoftTabBar({
    super.key,
    required this.selection,
    required this.onSelect,
  });

  final SoftTab selection;
  final ValueChanged<SoftTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return NavigationBar(
      // Search is a pushed route — not a real tab index. Map visible tabs only.
      selectedIndex: _visibleIndex(selection),
      onDestinationSelected: (i) => onSelect(_visibleTabs[i]),
      backgroundColor: t.bg,
      surfaceTintColor: Colors.transparent,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.near_me_outlined),
          selectedIcon: Icon(Icons.near_me_rounded),
          label: 'Nearby',
        ),
        NavigationDestination(
          icon: Icon(Icons.star_outline_rounded),
          selectedIcon: Icon(Icons.star_rounded),
          label: 'Saved',
        ),
        NavigationDestination(
          icon: Icon(Icons.search_rounded),
          selectedIcon: Icon(Icons.search_rounded),
          label: 'Search',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings_rounded),
          label: 'Settings',
        ),
      ],
    );
  }

  // Search is always pushed as a route, so all 4 tabs map 1:1.
  // Order mirrors iOS: Home · Saved · Search · Settings.
  static const _visibleTabs = [
    SoftTab.home,
    SoftTab.favourites,
    SoftTab.search,
    SoftTab.settings,
  ];

  static int _visibleIndex(SoftTab t) {
    final i = _visibleTabs.indexOf(t);
    return i < 0 ? 0 : i;
  }
}

/// Bottom composite for tabbed views: AdBanner on top, SoftTabBar
/// below. The banner widget self-suppresses (zero-size SizedBox) when
/// ads are disabled or in screenshot mode, so the tab bar sits flush
/// in those builds.
class SoftBottomBar extends StatelessWidget {
  const SoftBottomBar({
    super.key,
    required this.selection,
    required this.onSelect,
  });

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
