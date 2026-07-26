// SoftTabBar (Material 3) — bottom NavigationBar with pill-indicator
// behind the active icon. Mirrors the iOS WSTabBar set exactly:
// Nearby · Favourites · Alerts — matching WSRoot.swift's WSTab declaration
// order and its tab TITLES (the enum members stay home/favourites/alerts)
// (no Search destination in the bar — Search is reached via Home's search
// bar → onOpenSearch, and stays a pushed route; no MRT destination either —
// MRT stations are reached from Home's nearby-stations strip and Search,
// matching iOS which has no MRT overview tab).
//
// SoftBottomBar stacks the AdMob banner above SoftTabBar for the
// tabbed screens — this is what those Scaffolds mount as bottomNavigationBar.

import 'package:flutter/material.dart';

import '../../theme/soft_blue.dart';
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
// Android visible order: Nearby · Favourites · Alerts.
enum SoftTab { home, favourites, mrt, alerts, search }

/// Floating white pill bottom bar (SoftBlue §4 rollout note: "bottom nav →
/// floating white pill bar with chipBg-selected pill"). Replaces the
/// Material `NavigationBar` — same three destinations, same order, same
/// semantics, just SoftBlue chrome: a white capsule floating on the tinted
/// ground, the active destination getting a `chipBg`-filled pill behind its
/// icon+label (never a full-width Material indicator wash).
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

  // Labels + glyphs mirror iOS WSRoot's WSTab set exactly (owner parity pass
  // 2026-07-26): the first tab is "Nearby" (what the screen actually answers —
  // "Home" named a place, not a question) with a location pin, and the second
  // is "Favourites" with a star. Every destination keeps its label visible —
  // see _PillDestination.
  static const _destinations = [
    (
      icon: Icons.location_on_outlined,
      selectedIcon: Icons.location_on_rounded,
      label: 'Nearby',
    ),
    (
      icon: Icons.star_outline_rounded,
      selectedIcon: Icons.star_rounded,
      label: 'Favourites',
    ),
    (
      icon: Icons.notifications_outlined,
      selectedIcon: Icons.notifications_rounded,
      label: 'Alerts',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _visibleIndex(selection);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: SoftBlue.card,
          borderRadius: BorderRadius.circular(999),
          boxShadow: SoftBlue.cardShadow,
        ),
        child: Row(
          children: [
            for (var i = 0; i < _destinations.length; i++)
              Expanded(
                child: _PillDestination(
                  icon: _destinations[i].icon,
                  selectedIcon: _destinations[i].selectedIcon,
                  label: _destinations[i].label,
                  selected: i == selectedIndex,
                  badgeCount: i == 2 ? alertBadgeCount : 0,
                  onTap: () => onSelect(_visibleTabs[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Order mirrors iOS WSTabBar: Nearby · Favourites · Alerts. Search and MRT are
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

class _PillDestination extends StatelessWidget {
  const _PillDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final color = selected ? SoftBlue.chipInk : SoftBlue.sub;
    final iconWidget = Icon(
      selected ? selectedIcon : icon,
      size: 22,
      color: color,
    );
    return Semantics(
      button: true,
      selected: selected,
      // No explicit label: every destination now renders its name, so the
      // Text child already names the node. Setting it here as well produced a
      // second, competing node and TalkBack read the tab twice.
      //
      // Center, so the pill HUGS its icon+label instead of being stretched to
      // the full cell. Each destination sits in an Expanded cell (equal thirds,
      // so the three stay evenly spaced whatever the label lengths), and an
      // Expanded cell passes a TIGHT width down — which the AnimatedContainer
      // adopted, painting the selected capsule across the entire third with
      // the text stranded at its left edge. Center loosens that constraint so
      // `mainAxisSize.min` can do its job and centres the result in the cell.
      //
      // Tap target is the pill rather than the whole cell: it is the bar's
      // 64dp height less the 8dp vertical margins = 48dp tall, and the widest
      // is well past 48dp, so it still clears the minimum.
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: AnimatedContainer(
              duration: SoftBlueMotion.standard,
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(vertical: 8),
              // 14 → 9 horizontal: every destination now carries its label (not
              // just the selected one), so three labelled pills have to share
              // the bar's width on a 360dp screen.
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? SoftBlue.chipBg : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  badgeCount > 0
                      ? Badge(
                          label: Text(badgeCount > 9 ? '9+' : '$badgeCount'),
                          backgroundColor: SoftBlue.red,
                          child: iconWidget,
                        )
                      : iconWidget,
                  // The label is ALWAYS shown (iOS parity 2026-07-26 — its tab
                  // bar labels every destination). A bar where only the active
                  // item is named makes the other two a guessing game, and the
                  // pill's width jumping on every switch read as a glitch.
                  // Flexible + ellipsis: three labels share the width, so the
                  // longest ("Favourites") shrinks rather than overflowing.
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      style: SoftBlue.sans(
                        12,
                        weight: FontWeight.w600,
                        color: color,
                      ),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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

/// Bottom composite for tabbed views: the SoftTabBar only. Root tabs are
/// native-ad-only (one NativeAdCard inline in each tab's list) — no banner
/// in the tab gutter. The anchored banner lives on pushed detail screens
/// instead ([SoftDetailBottomBar]), where dwell time makes its 30–60 s
/// refresh earn. Mirrors iOS (WSRoot), owner decision 2026-07-07.
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
        SoftTabBar(
          selection: selection,
          onSelect: onSelect,
          alertBadgeCount: alertBadgeCount,
        ),
      ],
    );
  }
}
