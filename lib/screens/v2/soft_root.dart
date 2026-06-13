// SoftRoot — Leyne 2.0 Android root composition. Manages a simple stack
// (Home / Favourites / Settings tabs; Search / Stop / Bus / AllArrivals
// pushed) using a Navigator.

import 'package:flutter/material.dart';

import 'soft_bus_screen.dart';
import 'soft_favourites_screen.dart';
import 'soft_home_screen.dart';
import 'soft_mrt_screen.dart';
import 'soft_mrt_station_screen.dart';
import 'soft_search_screen.dart';
import 'soft_settings_screen.dart';
import 'soft_stop_screen.dart';
import '../../data/mrt_geo.dart';
import '../../services/app_open_ad.dart';
import '../../services/interstitial_ad.dart';
import '../../theme.dart';
import '../../widgets/v2/soft_tab_bar.dart';

/// Route name tagged on Stop / Bus detail routes so the navigator observer can
/// recognise a detail-view exit (and ignore other pops, e.g. the search route).
const String _kDetailRouteName = 'detail';

/// Fires an interstitial attempt whenever a Stop / Bus detail route is popped.
/// Hooking the navigator (not just each onBack button) means the back button,
/// the Android system back, and the predictive-back gesture all trigger it —
/// they all route through Navigator.pop → didPop. The manager's own guards
/// decide whether an ad actually shows, so a stray pop is harmless.
class _InterstitialOnExitObserver extends NavigatorObserver {
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == _kDetailRouteName) {
      InterstitialAdManager.instance.maybeShowOnExit();
    }
    super.didPop(route, previousRoute);
  }
}

class SoftRoot extends StatefulWidget {
  const SoftRoot({super.key});

  @override
  State<SoftRoot> createState() => _SoftRootState();
}

class _SoftRootState extends State<SoftRoot> {
  SoftTab _tab = SoftTab.home;
  final _navKey = GlobalKey<NavigatorState>();
  final _exitObserver = _InterstitialOnExitObserver();
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // App Open ad. SoftRoot only exists past onboarding, so mounting the
    // listener here is the first-run gate. Preload once consent resolves, then
    // show on every WARM foreground — this listener is created AFTER the
    // initial cold-launch resume, so the very first launch never shows one.
    // All other guards (frequency cap, notification/deep-link suppression,
    // master switches) live in the manager.
    AppOpenAdManager.instance.preloadWhenReady();
    // Cold-launch App Open is currently DISABLED in the manager
    // (AppOpenAdManager._coldLaunchEnabled = false) so opening the app never
    // greets the user with an ad — tester feedback that launch ads were too
    // aggressive. The call is kept (it no-ops) so re-enabling is a one-flag
    // change. Warm returns are handled by the onResume listener below.
    AppOpenAdManager.instance.showOnColdLaunch();
    // Interstitial ad — preload so one is ready when the user backs out of a
    // Stop / Bus detail (the navigator observer fires the show attempt).
    InterstitialAdManager.instance.preloadWhenReady();
    _lifecycle = AppLifecycleListener(
      onResume: () => AppOpenAdManager.instance.showIfAvailable(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _handleTab(SoftTab next) {
    if (next == SoftTab.search) {
      _navKey.currentState?.push(
        // Fade-through instead of MaterialPageRoute's slide so that opening
        // Search feels identical to switching any other tab. Back-stack
        // semantics are preserved — this is still a pushed route, so Back from
        // a stop/bus result returns to search results first, then to Home.
        PageRouteBuilder<void>(
          transitionDuration: LyneMotion.standard,
          reverseTransitionDuration: LyneMotion.standard,
          pageBuilder: (_, _, _) => SoftSearchScreen(
            onClose: () => _navKey.currentState?.pop(),
            // Push the result ON TOP of search (don't pop search first) so
            // Back from the stop/bus/station returns to the search results,
            // then Back again returns Home — instead of jumping straight to Home.
            onOpenStop: (code) => _pushStop(code),
            onOpenBus: (stopCode, svc) =>
                _pushBus(stopCode, svc, fullRoute: true),
            onOpenStation: _pushMrtStationFromSearch,
            onTab: _handleTab,
          ),
          transitionsBuilder: (_, anim, _, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
      return;
    }
    setState(() => _tab = next);
    _navKey.currentState?.popUntil((r) => r.isFirst);
  }

  /// Push the bus route view for [svc] anchored at [stopCode]. [fullRoute]
  /// shows the entire route (used for bus search, which has no boarding stop);
  /// the per-stop arrival flow leaves it false for the narrow approach window.
  void _pushBus(String stopCode, String svc, {bool fullRoute = false}) {
    _navKey.currentState?.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: _kDetailRouteName),
        builder: (_) => SoftBusScreen(
          stopCode: stopCode,
          svc: svc,
          fullRoute: fullRoute,
          onBack: () => _navKey.currentState?.pop(),
          onTab: _handleTab,
          tabSelection: _tab,
        ),
      ),
    );
  }

  /// Push station detail with walk/distance context (from nearest-stations tap).
  void _pushMrtStation(MrtGeoStation station, int distanceM, int walkMin) {
    _pushMrtStationDetail(station, distanceM: distanceM, walkMin: walkMin);
  }

  /// Push station detail without walk/distance context (from Search tap).
  void _pushMrtStationFromSearch(MrtGeoStation station) {
    _pushMrtStationDetail(station);
  }

  void _pushMrtStationDetail(
    MrtGeoStation station, {
    int? distanceM,
    int? walkMin,
  }) {
    _navKey.currentState?.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: _kDetailRouteName),
        builder: (_) => SoftMrtStationScreen(
          station: station,
          distanceM: distanceM,
          walkMin: walkMin,
          onBack: () => _navKey.currentState?.pop(),
          onTab: _handleTab,
          tabSelection: _tab,
        ),
      ),
    );
  }

  void _pushStop(String code) {
    _navKey.currentState?.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: _kDetailRouteName),
        builder: (_) => SoftStopScreen(
          stopCode: code,
          onBack: () => _navKey.currentState?.pop(),
          onOpenBus: (svc) => _pushBus(code, svc),
          onTab: _handleTab,
          tabSelection: _tab,
          onSeeAll: () => _navKey.currentState?.push(
            MaterialPageRoute(
              settings: const RouteSettings(name: _kDetailRouteName),
              builder: (_) => SoftStopScreen(
                stopCode: code,
                showAll: true,
                onBack: () => _navKey.currentState?.pop(),
                onOpenBus: (svc) => _pushBus(code, svc),
                onTab: _handleTab,
                tabSelection: _tab,
                onSeeAll: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: _navKey,
      observers: [_exitObserver],
      onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => _rootTab()),
    );
  }

  Widget _rootTab() {
    // Material 3 "fade-through" — the standard tab-swap transition.
    // AnimatedSwitcher cross-fades; child keying by _tab ensures the
    // switcher sees a new widget identity on every tab change.
    return AnimatedSwitcher(
      duration: LyneMotion.standard,
      switchInCurve: LyneMotion.enter,
      switchOutCurve: LyneMotion.exit,
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: KeyedSubtree(key: ValueKey(_tab), child: _tabBody()),
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
      case SoftTab.mrt:
        return SoftMrtScreen(onTab: _handleTab, onOpenStation: _pushMrtStation);
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
