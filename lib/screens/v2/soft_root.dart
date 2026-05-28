// SoftRoot — Leyne 2.0 Android root composition. Manages a simple stack
// (Home / Nearby / Settings tabs; Search / Stop / Bus / AllArrivals
// pushed) using a Navigator.

import 'package:flutter/material.dart';

import 'soft_bus_screen.dart';
import 'soft_home_screen.dart';
import 'soft_nearby_screen.dart';
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
          onOpenStop: (code) {
            _navKey.currentState?.pop();
            _pushStop(code);
          },
        ),
      ));
      return;
    }
    setState(() => _tab = next);
    _navKey.currentState?.popUntil((r) => r.isFirst);
  }

  void _pushStop(String code) {
    _navKey.currentState?.push(MaterialPageRoute(
      builder: (_) => SoftStopScreen(
        stopCode: code,
        onBack: () => _navKey.currentState?.pop(),
        onOpenBus: (svc) => _navKey.currentState?.push(MaterialPageRoute(
          builder: (_) => SoftBusScreen(
            stopCode: code,
            svc: svc,
            onBack: () => _navKey.currentState?.pop(),
          ),
        )),
        onSeeAll: () => _navKey.currentState?.push(MaterialPageRoute(
          builder: (_) => SoftStopScreen(
            stopCode: code,
            showAll: true,
            onBack: () => _navKey.currentState?.pop(),
            onOpenBus: (svc) => _navKey.currentState?.push(MaterialPageRoute(
              builder: (_) => SoftBusScreen(
                stopCode: code,
                svc: svc,
                onBack: () => _navKey.currentState?.pop(),
              ),
            )),
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
      case SoftTab.nearby:
        return SoftNearbyScreen(onTab: _handleTab, onOpenStop: _pushStop);
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
