// SoftRoot — Leyne 2.0 Android root composition. Manages a simple stack
// (Home / Favourites / Settings tabs; Search / Stop / Bus / AllArrivals
// pushed) using a Navigator.

import 'package:flutter/material.dart';

import 'soft_bus_screen.dart';
import 'soft_favourites_screen.dart';
import 'soft_home_screen.dart';
import 'soft_search_screen.dart';
import 'soft_settings_screen.dart';
import 'soft_stop_screen.dart';
import '../../widgets/v2/soft_tab_bar.dart';

class SoftRoot extends StatefulWidget {
  const SoftRoot({super.key});

  @override
  State<SoftRoot> createState() => _SoftRootState();
}

class _SoftRootState extends State<SoftRoot> {
  SoftTab _tab = SoftTab.home;
  final _navKey = GlobalKey<NavigatorState>();

  void _handleTab(SoftTab next) {
    if (next == SoftTab.search) {
      _navKey.currentState?.push(MaterialPageRoute(
        builder: (_) => SoftSearchScreen(
          onClose: () => _navKey.currentState?.pop(),
          // Push the result ON TOP of search (don't pop search first) so
          // Back from the stop/bus returns to the search results, then Back
          // again returns Home — instead of jumping straight to Home.
          onOpenStop: (code) => _pushStop(code),
          onOpenBus: (stopCode, svc) =>
              _pushBus(stopCode, svc, fullRoute: true),
          onTab: _handleTab,
        ),
      ));
      return;
    }
    setState(() => _tab = next);
    _navKey.currentState?.popUntil((r) => r.isFirst);
  }

  /// Push the bus route view for [svc] anchored at [stopCode]. [fullRoute]
  /// shows the entire route (used for bus search, which has no boarding stop);
  /// the per-stop arrival flow leaves it false for the narrow approach window.
  void _pushBus(String stopCode, String svc, {bool fullRoute = false}) {
    _navKey.currentState?.push(MaterialPageRoute(
      builder: (_) => SoftBusScreen(
        stopCode: stopCode,
        svc: svc,
        fullRoute: fullRoute,
        onBack: () => _navKey.currentState?.pop(),
        onTab: _handleTab,
        tabSelection: _tab,
      ),
    ));
  }

  void _pushStop(String code) {
    _navKey.currentState?.push(MaterialPageRoute(
      builder: (_) => SoftStopScreen(
        stopCode: code,
        onBack: () => _navKey.currentState?.pop(),
        onOpenBus: (svc) => _pushBus(code, svc),
        onTab: _handleTab,
        tabSelection: _tab,
        onSeeAll: () => _navKey.currentState?.push(MaterialPageRoute(
          builder: (_) => SoftStopScreen(
            stopCode: code,
            showAll: true,
            onBack: () => _navKey.currentState?.pop(),
            onOpenBus: (svc) => _pushBus(code, svc),
            onTab: _handleTab,
            tabSelection: _tab,
            onSeeAll: () {},
          ),
        )),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: _navKey,
      onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => _rootTab()),
    );
  }

  Widget _rootTab() {
    // Material 3 "fade-through" — the standard tab-swap transition.
    // AnimatedSwitcher cross-fades; child keying by _tab ensures the
    // switcher sees a new widget identity on every tab change.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: KeyedSubtree(
        key: ValueKey(_tab),
        child: _tabBody(),
      ),
    );
  }

  Widget _tabBody() {
    switch (_tab) {
      case SoftTab.home:
        return SoftHomeScreen(
          onTab: _handleTab,
          onOpenStop: _pushStop,
          onOpenSearch: () => _handleTab(SoftTab.search),
        );
      case SoftTab.favourites:
        return SoftFavouritesScreen(
          onTab: _handleTab,
          onOpenStop: _pushStop,
          onOpenBus: (stopCode, svc) => _pushBus(stopCode, svc),
          onOpenSearch: () => _handleTab(SoftTab.search),
        );
      case SoftTab.settings:
        return SoftSettingsScreen(onTab: _handleTab);
      case SoftTab.search:
        // Search is always pushed as a route, never the base tab.
        return SoftHomeScreen(
          onTab: _handleTab,
          onOpenStop: _pushStop,
          onOpenSearch: () => _handleTab(SoftTab.search),
        );
    }
  }
}
