// SoftTabBar (Material 3) — bottom NavigationBar with pill-indicator
// behind the active icon. Mirrors the iOS WSTabBar set exactly:
// Home · Saved · Alerts — matching WSRoot.swift's WSTab declaration order
// (no Search destination in the bar — Search is reached via Home's search
// bar → onOpenSearch, and stays a pushed route; no MRT destination either —
// MRT stations are reached from Home's nearby-stations strip and Search,
// matching iOS which has no MRT overview tab).
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
// Owner walkthrough 2026-07-03: MRT destination removed — iOS WSTab has no
// MRT tab (stations open from Home's strip / Search). SoftTab.mrt is KEPT
// as an enum member: soft_root.dart still mounts SoftMrtScreen for it and
// detail screens still carry it as a `tabSelection` value.
// Android visible order: Home · Saved · Alerts.
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
        // Glyphs mirror iOS WSIcons: house · bookmark · bell.
        const NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Home',
        ),
        const NavigationDestination(
          icon: Icon(Icons.bookmark_outline_rounded),
          selectedIcon: Icon(Icons.bookmark_rounded),
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

  // Order mirrors iOS WSTabBar: Home · Saved · Alerts. Search and MRT are
  // deliberately absent — Search is a pushed route (SoftTab.search) and MRT
  // stations open from Home's strip / Search; see the SoftTab doc comment.
  static const _visibleTabs = [
    SoftTab.home,
    SoftTab.favourites,
    SoftTab.alerts,
  ];

  static int _visibleIndex(SoftTab t) {
    final i = _visibleTabs.indexOf(t);
    return i < 0 ? 0 : i;
  }
}

/// Bottom slot for PUSHED detail screens (Stop / Bus / Station / Line /
/// Settings): the AdBanner only, no tab bar. iOS hides its floating tab bar
/// on pushed routes ("detail screens are focused tasks with their own
/// chrome" — WSRoot.swift), so Android mirrors that; the banner stays
/// because Android's ad inventory is independent of the iOS design (which
/// currently ships no banners at all). SafeArea keeps the banner clear of
/// the gesture-nav home indicator, which NavigationBar used to absorb.
class SoftDetailBottomBar extends StatelessWidget {
  const SoftDetailBottomBar({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(top: false, child: AdBanner());
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
