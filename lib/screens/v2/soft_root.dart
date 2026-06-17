// SoftRoot — Leyne 2.0 Android root composition. Manages a simple stack
// (Bus · MRT · Saved · Search · Alerts tabs; Stop / Bus / Search / Station
// pushed) using a Navigator. Settings is no longer a tab — it opens as a
// modal bottom sheet from the Alerts tab's gear button.

import 'package:flutter/material.dart';

import 'soft_alerts_screen.dart';
import 'soft_bus_screen.dart';
import 'soft_favourites_screen.dart';
import 'soft_home_screen.dart';
import 'soft_mrt_screen.dart';
import 'soft_mrt_station_screen.dart';
import 'soft_search_screen.dart';
import 'soft_stop_screen.dart';
import '../../data/data_store.dart';
import '../../data/mrt_geo.dart';
import '../../services/app_open_ad.dart';
import '../../services/interstitial_ad.dart';
import '../../state/app_model.dart';
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

  /// Returns the ids of every current service-status alert (train + lift).
  /// Used for the badge count and for marking items as seen.
  List<String> _currentAlertIds() {
    final ids = <String>[];
    for (final a in DataStore.shared.trainAlerts) {
      ids.add(a.id);
    }
    for (final lm in DataStore.shared.liftMaintenance) {
      ids.add(lm.id);
    }
    return ids;
  }

  /// Mark all current alerts as seen and dismiss the badge. Called when the
  /// Alerts tab is active (on switch-to and on new data landing).
  void _markAlertsSeen() {
    AppModel.shared.markAllAlertsSeen(_currentAlertIds());
  }

  void _handleTab(SoftTab next) {
    if (next == SoftTab.alerts) {
      setState(() => _tab = next);
      _navKey.currentState?.popUntil((r) => r.isFirst);
      _markAlertsSeen();
      return;
    }
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
    // The Android 3-button BACK key is dispatched to the ROOT navigator
    // (MaterialApp's), which only ever holds this single SoftRoot route — so
    // WidgetsApp.didPopRoute()'s maybePop() finds nothing to pop and the OS
    // finishes the activity, exiting the app even with a Stop / Bus / Search
    // detail pushed on the nested navigator below. (The predictive-back GESTURE
    // already works: a nested Navigator bubbles a NavigationNotification that
    // routes the gesture into the framework's pop logic; the legacy button
    // path does not.) NavigatorPopHandler closes that gap — it installs a
    // PopScope on this root route that, while the nested stack can pop, pops
    // THIS navigator instead, and defers to the OS (exit) once it's back at the
    // first route. Fixes button/gesture parity with no double-pop on gestures.
    return NavigatorPopHandler(
      onPopWithResult: (_) => _navKey.currentState?.maybePop(),
      child: Navigator(
        key: _navKey,
        observers: [_exitObserver],
        onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => _rootTab()),
      ),
    );
  }

  Widget _rootTab() {
    // Badge count is derived from DataStore (alert lists) + AppModel (seen
    // ids). Both are ChangeNotifiers — merge them so the badge stays live.
    return ListenableBuilder(
      listenable: Listenable.merge([DataStore.shared, AppModel.shared]),
      builder: (context, _) {
        final badgeCount =
            AppModel.shared.unseenAlertCount(_currentAlertIds());
        // When the Alerts tab is open and fresh data lands, mark it seen
        // immediately so the badge never increments while the user is there.
        if (_tab == SoftTab.alerts && badgeCount > 0) {
          // Schedule post-frame so we don't mutate state during build.
          WidgetsBinding.instance.addPostFrameCallback((_) => _markAlertsSeen());
        }
        // Material 3 "fade-through" — the standard tab-swap transition.
        // AnimatedSwitcher cross-fades; child keying on _tab + badgeCount
        // ensures the switcher sees a new identity on tab change (not on
        // badge-only updates, which must not reset the active screen).
        //
        // The ColoredBox is essential: mid cross-fade both the outgoing and
        // incoming screens are semi-transparent, so without an opaque backdrop
        // the bare Navigator behind them shows through as a dark/grey flash.
        // Painting the theme background here keeps the fade clean.
        return ColoredBox(
          color: context.t.bg,
          child: AnimatedSwitcher(
            duration: LyneMotion.standard,
            switchInCurve: LyneMotion.enter,
            switchOutCurve: LyneMotion.exit,
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: KeyedSubtree(
              key: ValueKey(_tab),
              child: _tabBody(badgeCount),
            ),
          ),
        );
      },
    );
  }

  Widget _tabBody(int alertBadgeCount) {
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
          onOpenStation: _pushMrtStationFromSearch,
          onOpenSearch: () => _handleTab(SoftTab.search),
        );
      case SoftTab.mrt:
        return SoftMrtScreen(
          onTab: _handleTab,
          onOpenStation: _pushMrtStation,
        );
      case SoftTab.alerts:
        return SoftAlertsScreen(
          onTab: _handleTab,
          alertBadgeCount: alertBadgeCount,
          onAlertsDataChanged: _markAlertsSeen,
        );
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
