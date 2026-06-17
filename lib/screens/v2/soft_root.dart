// SoftRoot — Leyne 2.0 Android root composition. Manages a simple stack
// (Bus · MRT · Saved · Search · Alerts tabs; Stop / Bus / Search / Station
// pushed) using a Navigator. Settings is no longer a tab — it opens as a
// modal bottom sheet from the Alerts tab's gear button.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// Reports every push/pop/replace/remove on the nested navigator so the root
/// PopScope can keep `canPop` in sync with whether a detail/Search route is
/// currently pushed (i.e. whether BACK should pop a route vs. change tabs).
class _StackChangeObserver extends NavigatorObserver {
  _StackChangeObserver(this.onChanged);
  final VoidCallback onChanged;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onChanged();
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onChanged();
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onChanged();
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    onChanged();
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

class SoftRoot extends StatefulWidget {
  const SoftRoot({super.key});

  @override
  State<SoftRoot> createState() => _SoftRootState();
}

class _SoftRootState extends State<SoftRoot> {
  SoftTab _tab = SoftTab.home;

  /// Tabs visited before [_tab], oldest first — the OS BACK button retraces
  /// this so back returns to the *previous* view, not always straight to Home.
  /// Only tab swaps are recorded; Search and detail screens are real routes on
  /// the nested navigator, which owns their back-stack. The app starts on Home,
  /// so Home is always the bottom of this stack: when it empties we're back on
  /// Home and the next BACK exits.
  final List<SoftTab> _tabHistory = [];

  final _navKey = GlobalKey<NavigatorState>();
  final _exitObserver = _InterstitialOnExitObserver();
  late final AppLifecycleListener _lifecycle;

  /// True while a Stop / Bus / Station / Search route is pushed on the nested
  /// navigator. One input to the root PopScope's `canPop`: while a route is
  /// pushed, BACK pops it; otherwise BACK retraces [_tabHistory]; only at the
  /// true root (Home, empty history, nothing pushed) does BACK exit the app.
  /// Kept in sync by [_stackObserver].
  bool _nestedHasDetail = false;
  late final _StackChangeObserver _stackObserver =
      _StackChangeObserver(_syncNestedStack);

  /// Last value pushed to [SystemNavigator.setFrameworkHandlesBack], so we only
  /// hit the platform channel when it actually flips. See [build].
  bool? _lastFrameworkHandlesBack;

  /// Recompute [_nestedHasDetail] after any nested navigation. Deferred to a
  /// post-frame callback because navigator observers fire mid-navigation, when
  /// calling setState synchronously would land during build/layout.
  void _syncNestedStack() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final hasDetail = _navKey.currentState?.canPop() ?? false;
      if (hasDetail != _nestedHasDetail) {
        setState(() => _nestedHasDetail = hasDetail);
      }
    });
  }

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
    if (next == SoftTab.search) {
      // Search is a pushed route, not a tab swap — the nested navigator owns
      // its back-stack, so it never participates in the tab history below.
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
    // Record the tab we're leaving so BACK can retrace to it. Only on an actual
    // change — re-tapping the active tab just resets its stack (popUntil below).
    if (next != _tab) {
      _tabHistory.add(_tab);
    }
    setState(() => _tab = next);
    _navKey.currentState?.popUntil((r) => r.isFirst);
    if (next == SoftTab.alerts) {
      _markAlertsSeen();
    }
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
    // The Android BACK key / predictive-back gesture is dispatched to the ROOT
    // navigator (MaterialApp's), which only ever holds this single SoftRoot
    // route. This PopScope is that route's back handler, with explicit priority:
    //
    //   1. A Stop / Bus / Station / Search route is pushed on the nested
    //      navigator → pop it (return to the underlying view).
    //   2. Tab history is non-empty → return to the *previous* tab the user was
    //      on (retrace), rather than jumping straight to Home.
    //   3. History empty but somehow off Home → step back to Home (safety net,
    //      so BACK can never strand the user on, or exit from, a non-Home tab).
    //   4. Home, nothing pushed, empty history → `canPop` is true, so the OS
    //      handles BACK and the app exits (standard Android root behaviour).
    //
    // Why this is hand-rolled: tab switches mutate `_tab` via setState (an
    // AnimatedSwitcher swap — NOT a navigator push), so the nested navigator has
    // no back-stack of tabs to pop. `_tabHistory` IS that missing stack;
    // `_nestedHasDetail` (kept current by `_stackObserver`) tracks whether a
    // real route is pushed so `canPop` only lets the OS exit at the true root.
    final canExit =
        !_nestedHasDetail && _tabHistory.isEmpty && _tab == SoftTab.home;

    // CRITICAL for the Android 13+ predictive-back / OnBackInvokedCallback path
    // (the real BACK button & gesture; NOT the legacy injected key event).
    // The engine only delivers BACK to Flutter while it believes the framework
    // will consume it. That belief is normally derived from a NavigationNotification
    // bubbling to WidgetsApp — but our NESTED navigator emits canHandlePop=false
    // whenever it sits on a bare tab root, which overwrites our root PopScope and
    // makes Flutter UNREGISTER its OnBackInvokedCallback. Android then runs its
    // default handler and finishes the activity — the app exits with onPopInvoked
    // never firing (verified via logcat: setTopOnBackInvokedCallback flips from
    // FlutterActivity$1 back to the default Activity lambda).
    //
    // `canExit` already consolidates nested-detail + tab-history + current tab, so
    // it is the single source of truth. We push it to the engine directly here,
    // and (below) swallow the nested navigator's NavigationNotification so it can
    // no longer override us. Guarded so the platform channel is only hit on flips.
    if (_lastFrameworkHandlesBack != !canExit) {
      _lastFrameworkHandlesBack = !canExit;
      SystemNavigator.setFrameworkHandlesBack(!canExit);
    }

    return PopScope(
      canPop: canExit,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final nav = _navKey.currentState;
        if (nav != null && nav.canPop()) {
          nav.pop(); // 1 — pop a pushed Stop / Bus / Station / Search route
          return;
        }
        if (_tabHistory.isNotEmpty) {
          final prev = _tabHistory.removeLast(); // 2 — retrace to previous tab
          setState(() => _tab = prev);
          if (prev == SoftTab.alerts) _markAlertsSeen();
          return;
        }
        if (_tab != SoftTab.home) {
          setState(() => _tab = SoftTab.home); // 3 — safety net
        }
      },
      // Swallow the nested navigator's NavigationNotification so it can't reach
      // WidgetsApp and flip framework-handles-back to false behind our backs
      // (see the setFrameworkHandlesBack note above). Returning true stops
      // propagation; our explicit call is the authority on BACK handling.
      child: NotificationListener<NavigationNotification>(
        onNotification: (_) => true,
        child: Navigator(
          key: _navKey,
          observers: [_exitObserver, _stackObserver],
          onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => _rootTab()),
        ),
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
