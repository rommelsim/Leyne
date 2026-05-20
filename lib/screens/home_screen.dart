// Home — pinned cards (drag to reorder, tap label to rename), live ETA
// countdown, pull-to-refresh, empty + error states.
//
// Drops the legacy iOS "tips" carousel + the large-title → sticky-compact
// header pattern; both are polish that don't change behaviour and can be
// added in a follow-up.

import 'package:flutter/material.dart';

import '../data/data_store.dart';
import '../state/app_model.dart';
import '../theme.dart';
import '../widgets/pinned_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    // Listen to BOTH AppModel (pin list + tick) and DataStore (arrivals)
    // so the UI rebuilds when either changes.
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration:
                        BoxDecoration(color: t.live, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text('LIVE',
                      style: t.mono(11, weight: FontWeight.w600)
                          .copyWith(color: t.dim)),
                ],
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: t.accent,
        onRefresh: _refresh,
        child: ListenableBuilder(
          listenable: Listenable.merge([AppModel.shared, DataStore.shared]),
          builder: (context, _) => _body(t),
        ),
      ),
    );
  }

  Widget _body(LyneTheme t) {
    final m = AppModel.shared;
    final ds = DataStore.shared;
    final cards = m.allPinnedCards;

    // Error from the bootstrap call (no stops/services data) takes priority
    // because nothing else will be live without it.
    if (ds.referenceState.state == LoadState.error && cards.isEmpty) {
      return _errorState(t, ds.referenceState.errorMessage ?? 'Couldn’t load LTA data');
    }

    if (cards.isEmpty) return _emptyState(t);

    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: cards.length,
      // onReorderItem auto-adjusts newIndex when moving down — no need
      // for the legacy `if (newIndex > oldIndex) newIndex -= 1` dance.
      onReorderItem: (oldIdx, newIdx) {
        final ids = [for (final c in cards) c.id];
        final moved = ids.removeAt(oldIdx);
        ids.insert(newIdx, moved);
        m.reorderPins(ids);
      },
      proxyDecorator: (child, _, animation) {
        return Material(
          color: Colors.transparent,
          elevation: 4 * animation.value,
          borderRadius: BorderRadius.circular(16),
          child: child,
        );
      },
      itemBuilder: (context, i) {
        final card = cards[i];
        return Padding(
          key: ValueKey(card.id),
          padding: EdgeInsets.only(bottom: i == cards.length - 1 ? 0 : 12),
          child: PinnedCard(
            card: card,
            isNew: card.stopCode == m.recentlyAddedId,
            hiddenServices: m.hiddenSet(
              code: card.stopCode,
              allNos: card.services.map((s) => s.no).toList(),
            ),
            onOpen: (busNo) {
              // Detail screen lands in Task #8 — for now just request
              // arrivals to keep the data warm.
              DataStore.shared.ensureArrivals(card.stopCode, force: true);
            },
            onRename: (newLabel) => m.rename(card.stopCode, newLabel),
          ),
        );
      },
    );
  }

  Future<void> _refresh() async {
    // Force-refresh arrivals for every pinned stop, then yield enough for
    // the spinner to animate. The 1s tick will keep doing this anyway, but
    // a manual pull is the user signalling distrust of staleness.
    final codes = AppModel.shared.pins.map((p) => p.code);
    for (final c in codes) {
      DataStore.shared.ensureArrivals(c, force: true);
    }
    await Future.delayed(const Duration(milliseconds: 500));
  }

  Widget _emptyState(LyneTheme t) {
    return ListView(
      children: [
        const SizedBox(height: 48),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                Icon(Icons.bookmark_outline,
                    size: 48, color: t.dim.withValues(alpha: 0.5)),
                const SizedBox(height: 14),
                Text('No pinned stops yet',
                    style: t.sans(17, weight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(
                  'Pin a stop from Nearby or Search and its live arrivals show up here.',
                  style: t.sans(13).copyWith(color: t.dim),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorState(LyneTheme t, String msg) {
    return ListView(
      children: [
        const SizedBox(height: 48),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                Icon(Icons.wifi_off, size: 40, color: t.crit),
                const SizedBox(height: 12),
                Text('Couldn’t load live data',
                    style: t.sans(15, weight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(msg,
                    style: t.sans(12).copyWith(color: t.dim),
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: t.accent),
                  onPressed: () => DataStore.shared.bootstrap(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
