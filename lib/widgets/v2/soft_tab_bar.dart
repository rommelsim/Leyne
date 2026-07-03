// SoftTabBar (Material 3) — bottom NavigationBar with pill-indicator
// behind the active icon. Mirrors the iOS WSTabBar set exactly:
// Bus (Home) · MRT · Saved · Alerts — matching WSRoot.swift's WSTab
// declaration order (no Search destination in the bar — Search is reached
// via Home's search bar → onOpenSearch, and stays a pushed route).
//
// SoftBottomBar stacks the AdMob banner above SoftTabBar for the
// tabbed screens — this is what those Scaffolds mount as bottomNavigationBar.

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../ad_banner.dart';

// 2.4.0: Added `favourites` tab — mirrors iOS SoftRoot 4-tab layout.
// 2.7.0: Added `mrt` tab — mirrors iOS SoftRoot.
// Phase 1: Reordered to Bus · MRT · Saved · Search · Settings.
// Phase 2: Replaced `settings` tab with `alerts` — Settings is now a gear-
//          button sheet accessed from the Alerts tab. Mirrors iOS SoftRoot.
// WhereSia redesign: Search removed as a bar destination — mirrors WSRoot's
// 3-tab WSTab enum (home/saved/alerts). SoftTab.search is KEPT as an enum
// member: soft_root.dart still uses it as a pushed-route marker (Search is
// always a pushed screen, never a tab body — see SoftRoot._handleTab), and
// SoftBusScreen/SoftStopScreen/SoftSearchScreen still pass it around as a
// `tabSelection` value for screens reached via search.
// Android visible order: Bus(Home) · MRT · Saved · Alerts.
enum SoftTab { home, favourites, mrt, alerts, search }

class SoftTabBar extends StatelessWidget {
  const SoftTabBar({
    super.key,
    required this.selection,
    required this.onSelect,
    this.alertBadgeCount = 0,
  });

  final SoftTab selection;
  final ValueChanged<SoftTab> onSelect;

  /// Number of unseen alerts. When > 0, the Alerts tab shows a badge dot.
  final int alertBadgeCount;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return NavigationBar(
      selectedIndex: _visibleIndex(selection),
      onDestinationSelected: (i) => onSelect(_visibleTabs[i]),
      backgroundColor: t.bg,
      surfaceTintColor: Colors.transparent,
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.directions_bus_outlined),
          selectedIcon: Icon(Icons.directions_bus_rounded),
          label: 'Bus',
        ),
        const NavigationDestination(
          icon: Icon(Icons.train_outlined),
          selectedIcon: Icon(Icons.train_rounded),
          label: 'MRT',
        ),
        const NavigationDestination(
          icon: Icon(Icons.star_outline_rounded),
          selectedIcon: Icon(Icons.star_rounded),
          label: 'Saved',
        ),
        NavigationDestination(
          icon: Badge(
            isLabelVisible: alertBadgeCount > 0,
            label: alertBadgeCount > 9
                ? const Text('9+')
                : Text('$alertBadgeCount'),
            child: const Icon(Icons.notifications_outlined),
          ),
          selectedIcon: Badge(
            isLabelVisible: alertBadgeCount > 0,
            label: alertBadgeCount > 9
                ? const Text('9+')
                : Text('$alertBadgeCount'),
            child: const Icon(Icons.notifications_rounded),
          ),
          label: 'Alerts',
        ),
      ],
    );
  }

  // Order mirrors iOS WSTabBar: Bus · MRT · Saved · Alerts. Search is
  // deliberately absent — it's a pushed route (SoftTab.search), never a bar
  // destination; see the SoftTab doc comment above.
  static const _visibleTabs = [
    SoftTab.home,
    SoftTab.mrt,
    SoftTab.favourites,
    SoftTab.alerts,
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
    this.alertBadgeCount = 0,
  });

  final SoftTab selection;
  final ValueChanged<SoftTab> onSelect;

  /// Forwarded to [SoftTabBar] to badge the Alerts destination.
  final int alertBadgeCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AdBanner(),
        SoftTabBar(
          selection: selection,
          onSelect: onSelect,
          alertBadgeCount: alertBadgeCount,
        ),
      ],
    );
  }
}
