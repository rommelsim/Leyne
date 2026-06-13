// SoftTabBar (Material 3) — bottom NavigationBar with pill-indicator
// behind the active icon. Mirrors the iOS tab set exactly:
// Bus (Home) · MRT · Saved · Search · Settings — matching SoftRoot.swift
// Tab declaration order.
//
// SoftBottomBar stacks the AdMob banner above SoftTabBar for the
// tabbed screens — this is what those Scaffolds mount as bottomNavigationBar.

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../ad_banner.dart';

// 2.4.0: Added `favourites` tab — mirrors iOS SoftRoot 4-tab layout.
// 2.7.0: Added `mrt` tab — mirrors iOS SoftRoot.
// Phase 1: Reordered to Bus · MRT · Saved · Search · Settings.
// Android visible order: Bus(Home) · MRT · Saved · Search · Settings.
enum SoftTab { home, favourites, mrt, settings, search }

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
      selectedIndex: _visibleIndex(selection),
      onDestinationSelected: (i) => onSelect(_visibleTabs[i]),
      backgroundColor: t.bg,
      surfaceTintColor: Colors.transparent,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.directions_bus_outlined),
          selectedIcon: Icon(Icons.directions_bus_rounded),
          label: 'Bus',
        ),
        NavigationDestination(
          icon: Icon(Icons.train_outlined),
          selectedIcon: Icon(Icons.train_rounded),
          label: 'MRT',
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

  // Order mirrors iOS SoftRoot: Bus · MRT · Saved · Search · Settings.
  static const _visibleTabs = [
    SoftTab.home,
    SoftTab.mrt,
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
