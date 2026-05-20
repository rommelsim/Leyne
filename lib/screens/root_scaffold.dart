// Root scaffold — bottom navigation across the 4 tabs.
//
// Legacy parity (RootView.swift):
//   • iOS used a 4-Tab TabView with the Search tab intercepted to open a
//     modal sheet. Flutter port keeps things straightforward: 4 real tabs.
//     Task #9 can refine the Search UX if the modal-sheet pattern is wanted.
//   • Reference data is bootstrapped at app start by main.dart and shows a
//     status banner here while loading or on error. Tabs are usable
//     immediately; data-dependent screens render their own empty states
//     until DataStore is ready.

import 'package:flutter/material.dart';

import '../data/data_store.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'nearby_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class RootScaffold extends StatefulWidget {
  const RootScaffold({super.key});

  @override
  State<RootScaffold> createState() => _RootScaffoldState();
}

class _RootScaffoldState extends State<RootScaffold> {
  int _index = 0;

  static const _screens = <Widget>[
    HomeScreen(),
    NearbyScreen(),
    SearchScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      // IndexedStack preserves each tab's state across switches (a tapped
      // ListView in Nearby keeps its scroll position, etc.). Matches the
      // legacy TabView behavior.
      body: Column(
        children: [
          const _BootstrapBanner(),
          Expanded(child: IndexedStack(index: _index, children: _screens)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.my_location_outlined),
              selectedIcon: Icon(Icons.my_location),
              label: 'Nearby'),
          NavigationDestination(
              icon: Icon(Icons.search),
              selectedIcon: Icon(Icons.search),
              label: 'Search'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings'),
        ],
      ),
    );
  }
}

/// Thin banner above the screens that surfaces DataStore.referenceState.
/// Hidden when ready; shows a spinner row while loading, a retry row on
/// error. Auto-rebuilds via ListenableBuilder when state changes.
class _BootstrapBanner extends StatelessWidget {
  const _BootstrapBanner();

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return ListenableBuilder(
      listenable: DataStore.shared,
      builder: (context, _) {
        final state = DataStore.shared.referenceState;
        switch (state.state) {
          case LoadState.ready:
            return const SizedBox.shrink();
          case LoadState.loading:
            return Container(
              color: t.surface,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: t.dim),
                  ),
                  const SizedBox(width: 12),
                  Text('Loading bus stops…',
                      style: t.sans(13).copyWith(color: t.dim)),
                ],
              ),
            );
          case LoadState.error:
            return Container(
              color: t.crit.withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: t.crit, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.errorMessage ?? 'Couldn’t reach LTA',
                      style: t.sans(13).copyWith(color: t.crit),
                    ),
                  ),
                  TextButton(
                    onPressed: () => DataStore.shared.bootstrap(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
        }
      },
    );
  }
}
