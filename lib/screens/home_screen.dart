// Home — hero arrival + compact saved-routes list.
//
// Picks the single most-urgent service across all pinned stops (smallest
// `eta − walk` margin) and promotes it to a full-bleed card. Everything
// else flows below as compact two-line rows.

import 'package:flutter/material.dart';

import '../data/data_store.dart';
import '../data/models.dart';
import '../state/app_model.dart';
import '../theme.dart';
import '../widgets/atoms.dart';
import '../widgets/home_hero.dart';
import '../widgets/pinned_card.dart';
import 'detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: t.accent,
          backgroundColor: t.surface,
          onRefresh: _refresh,
          child: ListenableBuilder(
            listenable: Listenable.merge([AppModel.shared, DataStore.shared]),
            builder: (context, _) => _body(t),
          ),
        ),
      ),
    );
  }

  Widget _body(LyneTheme t) {
    final m = AppModel.shared;
    final ds = DataStore.shared;
    final cards = m.allPinnedCards;
    final visibleCards = _withVisibleServices(cards, m);

    if (ds.referenceState.state == LoadState.error && cards.isEmpty) {
      return _errorState(t, ds.referenceState.errorMessage ?? 'Couldn’t load LTA data');
    }

    if (cards.isEmpty) return _emptyState(t);

    final hero = _selectHero(visibleCards);
    final rest = hero == null
        ? visibleCards
        : visibleCards.where((c) => c.id != hero.card.id).toList();

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          sliver: SliverToBoxAdapter(child: _header(t)),
        ),
        if (hero != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
            sliver: SliverToBoxAdapter(
              child: HomeHero(
                card: hero.card,
                service: hero.service,
                onTap: () => _openDetail(hero.card.stopCode, hero.service.no),
              ),
            ),
          ),
        if (rest.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
            sliver: SliverToBoxAdapter(child: _savedRoutesHeader(t)),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
            sliver: SliverReorderableList(
              itemBuilder: (context, i) {
                final card = rest[i];
                return Padding(
                  key: ValueKey(card.id),
                  padding: EdgeInsets.only(bottom: i == rest.length - 1 ? 0 : 10),
                  child: ReorderableDelayedDragStartListener(
                    index: i,
                    child: PinnedCard(
                      card: card,
                      isNew: card.stopCode == m.recentlyAddedId,
                      hiddenServices: m.hiddenSet(
                        code: card.stopCode,
                        allNos: card.services.map((s) => s.no).toList(),
                      ),
                      onOpen: (busNo) => _openDetail(card.stopCode, busNo),
                      onRename: (label) => m.rename(card.stopCode, label),
                    ),
                  ),
                );
              },
              itemCount: rest.length,
              onReorderItem: (oldIdx, newIdx) {
                // Reorder within the visible "rest" slice and splice the result
                // back into the full pin list at the slots that were occupied
                // by rest cards — hero and hidden cards keep their slots.
                final restCurrent = [for (final c in rest) c.id];
                final restNew = [...restCurrent];
                final moved = restNew.removeAt(oldIdx);
                restNew.insert(newIdx, moved);

                final restSet = restCurrent.toSet();
                final restIter = restNew.iterator;
                final next = <String>[];
                for (final pin in m.pins) {
                  if (restSet.contains(pin.code)) {
                    if (restIter.moveNext()) next.add(restIter.current);
                  } else {
                    next.add(pin.code);
                  }
                }
                m.reorderPins(next);
              },
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  // ─── Header ─────────────────────────────────────────────────────────

  Widget _header(LyneTheme t) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('Home',
            style: t.sans(28, weight: FontWeight.w600).copyWith(letterSpacing: -0.4)),
        const Spacer(),
        _liveIndicator(t),
      ],
    );
  }

  Widget _liveIndicator(LyneTheme t) {
    // The 1-second AppModel tick drives the timestamp refresh.
    final now = DateTime.now();
    final use24 = AppModel.shared.use24h;
    final mm = now.minute.toString().padLeft(2, '0');
    final timeLabel = use24
        ? '${now.hour.toString().padLeft(2, '0')}:$mm'
        : '${((now.hour + 11) % 12) + 1}:$mm ${now.hour < 12 ? 'am' : 'pm'}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7, height: 7,
          decoration: BoxDecoration(
            color: t.accent,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: t.accent.withValues(alpha: 0.55), blurRadius: 8),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text('LIVE · $timeLabel',
            style: t.mono(11, weight: FontWeight.w600, color: t.dim)
                .copyWith(letterSpacing: 1.0)),
      ],
    );
  }

  Widget _savedRoutesHeader(LyneTheme t) {
    return Row(
      children: [
        const MicroLabel('Saved routes'),
        const Spacer(),
        InkWell(
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Long-press a card to rename · drag to reorder',
                  style: t.sans(13, color: t.fg),
                ),
                backgroundColor: t.surfaceHi,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
              ),
            );
          },
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text('Edit', style: t.mono(12, color: t.dim)),
          ),
        ),
      ],
    );
  }

  // ─── Selection ──────────────────────────────────────────────────────

  // Recompute walk/eta-respecting urgency for each pinned card, drop ones
  // that have no visible services after `hiddenSet`, and return what's left
  // in source order. The set used to render the saved-routes list.
  List<CardModel> _withVisibleServices(List<CardModel> cards, AppModel m) {
    final out = <CardModel>[];
    for (final c in cards) {
      final hidden = m.hiddenSet(
        code: c.stopCode,
        allNos: c.services.map((s) => s.no).toList(),
      );
      final visible = c.services.where((s) => !hidden.contains(s.no)).toList();
      if (visible.isEmpty) continue;
      out.add(c);
    }
    return out;
  }

  _HeroPick? _selectHero(List<CardModel> cards) {
    final m = AppModel.shared;
    _HeroPick? best;
    int? bestMargin;
    for (final c in cards) {
      final hidden = m.hiddenSet(
        code: c.stopCode,
        allNos: c.services.map((s) => s.no).toList(),
      );
      for (final s in c.services) {
        if (hidden.contains(s.no)) continue;
        if (s.etaSec >= 3600) continue; // skip stale / no-data entries
        // margin = how soon you need to leave (eta − walk). Negative if late.
        final margin = (s.etaSec ~/ 60) - c.walkMin;
        if (bestMargin == null || margin < bestMargin) {
          bestMargin = margin;
          best = _HeroPick(card: c, service: s);
        }
      }
    }
    return best;
  }

  // ─── Misc ───────────────────────────────────────────────────────────

  void _openDetail(String stopCode, String? busNo) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailScreen(
          stopCode: stopCode,
          initialSelectedNo: busNo,
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    final codes = AppModel.shared.pins.map((p) => p.code);
    for (final c in codes) {
      DataStore.shared.ensureArrivals(c, force: true);
    }
    await Future.delayed(const Duration(milliseconds: 500));
  }

  Widget _emptyState(LyneTheme t) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      children: [
        const SizedBox(height: 36),
        _header(t),
        const SizedBox(height: 80),
        Center(
          child: Column(
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: t.line),
                ),
                child: Icon(Icons.bookmark_outline,
                    size: 26, color: t.dim),
              ),
              const SizedBox(height: 16),
              Text('No pinned stops yet',
                  style: t.sans(17, weight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                'Pin a stop from Nearby or Search and its live arrivals show up here.',
                style: t.sans(13, color: t.dim),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _errorState(LyneTheme t, String msg) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      children: [
        const SizedBox(height: 36),
        _header(t),
        const SizedBox(height: 80),
        Center(
          child: Column(
            children: [
              Icon(Icons.wifi_off, size: 40, color: t.crit),
              const SizedBox(height: 12),
              Text('Couldn’t load live data',
                  style: t.sans(15, weight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(msg,
                  style: t.sans(12, color: t.dim),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: t.accent,
                  foregroundColor: t.contrastFg,
                ),
                onPressed: () => DataStore.shared.bootstrap(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroPick {
  const _HeroPick({required this.card, required this.service});
  final CardModel card;
  final Service service;
}
