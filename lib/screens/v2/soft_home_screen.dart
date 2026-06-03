// SoftHomeScreen — Leyne 2.0 Home (Material 3 Android variant).
//
// Vertical list of pinned-stop cards followed by a Nearby section (up to 12
// stops, de-duped against pinned). A live-location status row sits under the
// header when location is active. Empty state is gated on BOTH pins AND
// nearby being empty, matching iOS SoftHomeView.
//
// Section order matches iOS SoftHomeView.swift:
//   header → live row → MRT alerts → Pinned → Nearby → empty state

import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../data/geo.dart';
import '../../data/models.dart';
import '../../services/location_service.dart';
import '../../state/app_model.dart';
import '../../theme.dart';
import '../../widgets/v2/confidence.dart';
import '../../widgets/v2/soft_components.dart';
import '../../widgets/v2/soft_tab_bar.dart';

class SoftHomeScreen extends StatefulWidget {
  const SoftHomeScreen({
    super.key,
    required this.onTab,
    required this.onOpenStop,
    required this.onOpenSearch,
  });
  final ValueChanged<SoftTab> onTab;
  final ValueChanged<String> onOpenStop;
  final VoidCallback onOpenSearch;

  @override
  State<SoftHomeScreen> createState() => _SoftHomeScreenState();
}

// ── Item types for the flat ListView.builder index ──────────────────────────

/// Discriminated union for the items rendered by the flat ListView.builder.
sealed class _Item {}

class _HeaderItem extends _Item {}

class _LiveRowItem extends _Item {}

/// Gap / spacer between sections.
class _GapItem extends _Item {
  _GapItem(this.height);
  final double height;
}

class _EyebrowItem extends _Item {
  _EyebrowItem(this.label);
  final String label;
}

class _PinCardItem extends _Item {
  _PinCardItem(this.pin);
  final Pin pin;
}

class _NearbyCardItem extends _Item {
  _NearbyCardItem(this.stop);
  final NearbyStop stop;
}

class _AlertItem extends _Item {
  _AlertItem(this.alert);
  final TrainAlert alert;
}

class _EmptyItem extends _Item {}

// ─────────────────────────────────────────────────────────────────────────────

class _SoftHomeScreenState extends State<SoftHomeScreen> {
  /// Line codes the user has tapped to dismiss this session. Cleared
  /// when the app cold-starts so a new disruption surfaces again.
  final Set<String> _dismissedAlerts = {};

  // ── Walk-minute memoisation cache ─────────────────────────────────────────
  // Keyed by stop code. Recomputed only when LocationService.lastLocation
  // changes (see initState listener). Computing haversine per pin per rebuild
  // was wasteful; pin lists change rarely and location updates are infrequent.
  final Map<String, int?> _walkCache = {};

  @override
  void initState() {
    super.initState();
    // Populate walk cache when location changes (not on every 1s tick).
    LocationService.shared.addListener(_onLocationChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _warm();
      await LocationService.shared.startIfAuthorized();
      final loc = LocationService.shared.lastLocation;
      if (loc != null) {
        DataStore.shared.updateNearby(loc.lat, loc.lon);
        _rebuildWalkCache();
      }
      DataStore.shared.prefetchNearbyArrivals();
    });
  }

  @override
  void dispose() {
    LocationService.shared.removeListener(_onLocationChanged);
    super.dispose();
  }

  void _onLocationChanged() {
    _rebuildWalkCache();
    // LocationService already calls notifyListeners which triggers the outer
    // structural ListenableBuilder — no extra setState needed here.
  }

  void _rebuildWalkCache() {
    final here = LocationService.shared.lastLocation;
    if (here == null) {
      _walkCache.clear();
      return;
    }
    for (final pin in AppModel.shared.pins) {
      _walkCache[pin.code] = _computeWalk(pin.code, here);
    }
  }

  int? _computeWalk(String code, ({double lat, double lon}) here) {
    final stop = DataStore.shared.stopByCode[code];
    if (stop == null) return null;
    final d = haversine(here.lat, here.lon, stop.latitude, stop.longitude);
    return walkMinutesFor(d);
  }

  int? _walkMinutes(String code) {
    if (_walkCache.containsKey(code)) return _walkCache[code];
    // Not yet cached — compute on first access and store.
    final here = LocationService.shared.lastLocation;
    if (here == null) return null;
    final result = _computeWalk(code, here);
    _walkCache[code] = result;
    return result;
  }

  void _warm() {
    for (final pin in AppModel.shared.pins) {
      DataStore.shared.ensureArrivals(pin.code);
    }
  }

  /// Nearby stops with pinned stop codes removed so a stop never appears twice.
  List<NearbyStop> _nearbyStops(Set<String> pinnedCodes) {
    return DataStore.shared.nearby
        .where((s) => !pinnedCodes.contains(s.stopCode))
        .take(12)
        .toList();
  }

  List<Service> _filteredServices(Pin pin) {
    final all = _liveServices(pin.code);
    final tracked = pin.tracked;
    if (tracked != null && tracked.isNotEmpty) {
      return all.where((s) => tracked.contains(s.no)).toList();
    }
    return all;
  }

  List<Service> _liveServices(String code) {
    final a = DataStore.shared.arrivals[code];
    if (a == null || a.kind != ArrivalStateKind.loaded) return const [];
    return a.services;
  }

  /// Build the flat item list for ListView.builder.
  /// Section order: header → live row → MRT alerts → Pinned → Nearby → empty.
  List<_Item> _buildItems({
    required List<Pin> pins,
    required List<NearbyStop> nearby,
    required List<TrainAlert> visibleAlerts,
  }) {
    final items = <_Item>[];

    items.add(_HeaderItem());
    items.add(_GapItem(6));
    items.add(_LiveRowItem());

    // ── MRT alerts (above Pinned — matches iOS order) ──
    if (visibleAlerts.isNotEmpty) {
      items.add(_GapItem(16));
      for (var i = 0; i < visibleAlerts.length; i++) {
        if (i > 0) items.add(_GapItem(10));
        items.add(_AlertItem(visibleAlerts[i]));
      }
    }

    // ── Pinned section ──
    if (pins.isNotEmpty) {
      items.add(_GapItem(16));
      items.add(_EyebrowItem('Pinned'));
      items.add(_GapItem(10));
      for (var i = 0; i < pins.length; i++) {
        if (i > 0) items.add(_GapItem(12));
        items.add(_PinCardItem(pins[i]));
      }
    }

    // ── Nearby section ──
    if (nearby.isNotEmpty) {
      items.add(_GapItem(16));
      items.add(_EyebrowItem('Nearby'));
      items.add(_GapItem(10));
      for (var i = 0; i < nearby.length; i++) {
        if (i > 0) items.add(_GapItem(10));
        items.add(_NearbyCardItem(nearby[i]));
      }
    }

    // ── Empty state (both pins AND nearby empty) ──
    if (pins.isEmpty && nearby.isEmpty) {
      items.add(_GapItem(8));
      items.add(_EmptyItem());
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      bottomNavigationBar: SoftBottomBar(
        selection: SoftTab.home,
        onSelect: widget.onTab,
      ),
      body: SafeArea(
        // Outer builder: structural changes only (pins list, nearby list,
        // alerts membership, location fix/loss). Does NOT rebuild on the 1s
        // AppModel tick — that is isolated to the ETA text inside each card.
        child: ListenableBuilder(
          listenable: Listenable.merge([
            DataStore.shared,
            LocationService.shared,
          ]),
          builder: (context, _) {
            final pins = AppModel.shared.pins;
            final pinnedCodes = pins.map((p) => p.code).toSet();
            final nearby = _nearbyStops(pinnedCodes);
            final visibleAlerts = DataStore.shared.trainAlerts
                .where((a) => !_dismissedAlerts.contains(a.id))
                .toList();

            final items = _buildItems(
              pins: pins,
              nearby: nearby,
              visibleAlerts: visibleAlerts,
            );

            return RefreshIndicator(
              color: t.accent,
              onRefresh: () async {
                await Future.wait(
                  pins.map((p) => DataStore.shared.refreshArrivals(p.code)),
                );
                final loc = LocationService.shared.lastLocation;
                if (loc != null) {
                  DataStore.shared.updateNearby(loc.lat, loc.lon);
                }
                DataStore.shared.prefetchNearbyArrivals();
              },
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: items.length,
                itemBuilder: (context, index) =>
                    _buildItem(context, items[index], nearby: nearby),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    _Item item, {
    required List<NearbyStop> nearby,
  }) {
    return switch (item) {
      _HeaderItem() => _header(context),
      _LiveRowItem() => _liveRow(context),
      _GapItem(:final height) => SizedBox(height: height),
      _EyebrowItem(:final label) => Eyebrow(label),
      _PinCardItem(:final pin) => RepaintBoundary(
        child: _PinCard(
          pin: pin,
          services: _filteredServices(pin),
          walkMinutes: _walkMinutes(pin.code),
          onTap: () => widget.onOpenStop(pin.code),
        ),
      ),
      _NearbyCardItem(:final stop) => RepaintBoundary(
        child: _NearbyCard(
          stop: stop,
          onTap: () => widget.onOpenStop(stop.stopCode),
        ),
      ),
      _AlertItem(:final alert) => _mrtAlertCard(context, alert),
      _EmptyItem() => _EmptyState(
        onNearby: () async {
          await LocationService.shared.requestAndStart();
          final loc = LocationService.shared.lastLocation;
          if (loc != null) {
            DataStore.shared.updateNearby(loc.lat, loc.lon);
            DataStore.shared.prefetchNearbyArrivals();
          }
        },
        onSearch: widget.onOpenSearch,
      ),
    };
  }

  Widget _header(BuildContext context) {
    final t = context.t;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow(_greeting()),
              const SizedBox(height: 2),
              Text(
                'Stops near you',
                style: t.sans(28, weight: FontWeight.w600, color: t.fg),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: widget.onOpenSearch,
          icon: const Icon(Icons.search_rounded),
        ),
      ],
    );
  }

  /// Live-location status row: icon + "NEAR YOU" / "LOCATION OFF" + live dot.
  Widget _liveRow(BuildContext context) {
    final t = context.t;
    final located = LocationService.shared.lastLocation != null;
    return Row(
      children: [
        Icon(
          located ? Icons.location_on : Icons.location_off,
          size: 13,
          color: t.dim,
        ),
        const SizedBox(width: 5),
        Text(
          located ? 'NEAR YOU' : 'LOCATION OFF',
          style: t
              .mono(10, weight: FontWeight.w700, color: t.dim)
              .copyWith(letterSpacing: 0.8),
        ),
        if (located) ...[
          const SizedBox(width: 6),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            'LIVE',
            style: t
                .mono(10, weight: FontWeight.w700, color: t.dim)
                .copyWith(letterSpacing: 0.8),
          ),
        ],
      ],
    );
  }

  Widget _mrtAlertCard(BuildContext context, TrainAlert alert) {
    final t = context.t;
    final color = alert.line?.color ?? t.dim;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => _dismissedAlerts.add(alert.id)),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MRTLineBar(color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alert.title,
                    style: t.sans(13, weight: FontWeight.w600, color: t.fg),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    alert.detail,
                    style: t.sans(12, color: t.dim),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    if (h < 22) return 'Good evening';
    return 'Good night';
  }
}

// ─── Pinned stop card ───────────────────────────────────────────────────────

/// Pinned-stop card matching the Soft 2.0 prototype: pin-chip + stop-name
/// + walk-time header row, up to 3 services sorted by next arrival with
/// right-aligned ETA ("now" in accent, otherwise mono), an overflow
/// "+N more arrivals →" link, and a quiet state when no live arrivals.
///
/// Services are already ETA-sorted by DataStore._fetchArrivals and
/// AppModel.liveServices. No re-sort here — that was waste on every rebuild.
/// The narrow ListenableBuilder(AppModel.shared) makes only the ETA text
/// rebuild each second, not the card's layout/chrome.
class _PinCard extends StatelessWidget {
  const _PinCard({
    required this.pin,
    required this.services,
    required this.walkMinutes,
    required this.onTap,
  });

  static const int _maxVisible = 3;

  final Pin pin;
  final List<Service> services;
  final int? walkMinutes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    // Services are already ETA-sorted upstream (DataStore._fetchArrivals sorts
    // on load; AppModel.liveServices re-sorts after ETA recomputation). No
    // re-sort needed here — it was wasted work on every rebuild.
    final visible = services.take(_maxVisible).toList();
    final overflow = services.length > _maxVisible
        ? services.length - _maxVisible
        : 0;
    final dsName = DataStore.shared.stopName(pin.code);
    final stopName = dsName.isEmpty ? pin.code : dsName;
    final nick = pin.nickname.trim();
    // Empty when there's no real nickname — the card then shows no chip
    // rather than a redundant "PIN" label. Matches iOS SoftPinCard.
    final chip = (nick.isEmpty || nick.toLowerCase() == stopName.toLowerCase())
        ? ''
        : nick.toUpperCase();

    // Compute Freshness once per card, not once per service row.
    final feed = Freshness.from(DataStore.shared.lastRefresh(pin.code));

    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(context, chip: chip, stopName: stopName),
              const SizedBox(height: 12),
              if (visible.isEmpty)
                _quietRow(context)
              else ...[
                for (var i = 0; i < visible.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _serviceRow(context, visible[i], feed: feed),
                ],
                if (overflow > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    '+$overflow more arrivals →',
                    style: t.sans(12, weight: FontWeight.w500, color: t.dim),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context, {
    required String chip,
    required String stopName,
  }) {
    final t = context.t;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (chip.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: t.liveBg,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              chip,
              style: t
                  .mono(10, weight: FontWeight.w600, color: t.accent)
                  .copyWith(letterSpacing: 0.8),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            stopName,
            style: t.sans(17, weight: FontWeight.w600, color: t.fg),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (walkMinutes != null) ...[
          const SizedBox(width: 8),
          _walkChip(context, walkMinutes!),
        ],
      ],
    );
  }

  Widget _walkChip(BuildContext context, int minutes) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: t.liveBg.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_walk, size: 12, color: t.dim),
          const SizedBox(width: 4),
          Text(
            '$minutes m',
            style: t.mono(11, weight: FontWeight.w600, color: t.dim),
          ),
        ],
      ),
    );
  }

  /// Service row with a narrow ListenableBuilder so ONLY the ETA text
  /// rebuilds each second when AppModel ticks — the badge, destination
  /// text, and layout stay untouched.
  Widget _serviceRow(
    BuildContext context,
    Service s, {
    required Freshness feed,
  }) {
    final t = context.t;
    final conf = ArrivalConfidence.of(monitored: s.monitored, feed: feed);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ServiceBadge(svc: s.no, size: ServiceBadgeSize.sm),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '→ ${s.dest}',
            style: t.sans(13, color: t.dim),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        // Narrow rebuild: only this Text re-renders each second.
        ListenableBuilder(
          listenable: AppModel.shared,
          builder: (context, _) {
            // Re-derive etaSec from the live arrivalDate so the countdown
            // is smooth between LTA polls (same logic as AppModel.liveServices).
            final now = DateTime.now();
            final etaSec = s.arrivalDate != null
                ? s.arrivalDate!.difference(now).inSeconds.clamp(0, 1 << 30)
                : s.etaSec;
            return ConfidenceEta(etaSec: etaSec, confidence: conf, size: 13);
          },
        ),
      ],
    );
  }

  Widget _quietRow(BuildContext context) {
    final t = context.t;
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: t.dim.withValues(alpha: 0.6),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text('Quiet · no live arrivals', style: t.sans(13, color: t.dim)),
      ],
    );
  }
}

// ─── Nearby stop card ───────────────────────────────────────────────────────

/// Compact card for stops in the Nearby section. Shows stop name, road name,
/// distance chip, and up to 2 live service previews with confidence treatment.
/// Tapping opens the stop detail screen.
///
/// The narrow ListenableBuilder(AppModel.shared) makes only the ETA text
/// rebuild each second, not the card's layout/chrome.
class _NearbyCard extends StatelessWidget {
  const _NearbyCard({required this.stop, required this.onTap});

  static const int _maxServices = 2;

  final NearbyStop stop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final arrival = DataStore.shared.arrivals[stop.stopCode];
    final services =
        (arrival != null && arrival.kind == ArrivalStateKind.loaded)
        ? arrival.services
        : const <Service>[];
    final road = DataStore.shared.roadName(stop.stopCode);
    final visible = services.take(_maxServices).toList();

    // Compute Freshness once per card, not once per service row.
    final feed = Freshness.from(DataStore.shared.lastRefresh(stop.stopCode));

    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Distance tile
              _distanceTile(context),
              const SizedBox(width: 12),
              // Stop info + service rows
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stop.stopName,
                      style: t.sans(15, weight: FontWeight.w600, color: t.fg),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (road.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        road,
                        style: t.sans(12, color: t.dim),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (visible.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      for (var i = 0; i < visible.length; i++) ...[
                        if (i > 0) const SizedBox(height: 6),
                        _serviceRow(context, visible[i], feed: feed),
                      ],
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: t.dim),
            ],
          ),
        ),
      ),
    );
  }

  Widget _distanceTile(BuildContext context) {
    final t = context.t;
    return Container(
      width: 52,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: t.liveBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            fmtDistance(stop.distanceM),
            style: t.mono(11, weight: FontWeight.w700, color: t.accent),
          ),
          Text('away', style: t.mono(9, color: t.dim)),
        ],
      ),
    );
  }

  Widget _serviceRow(
    BuildContext context,
    Service s, {
    required Freshness feed,
  }) {
    final t = context.t;
    final conf = ArrivalConfidence.of(monitored: s.monitored, feed: feed);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ServiceBadge(svc: s.no, size: ServiceBadgeSize.sm),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '→ ${s.dest}',
            style: t.sans(12, color: t.dim),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 6),
        // Narrow rebuild: only this ETA widget re-renders each second.
        ListenableBuilder(
          listenable: AppModel.shared,
          builder: (context, _) {
            final now = DateTime.now();
            final etaSec = s.arrivalDate != null
                ? s.arrivalDate!.difference(now).inSeconds.clamp(0, 1 << 30)
                : s.etaSec;
            return ConfidenceEta(etaSec: etaSec, confidence: conf, size: 12);
          },
        ),
      ],
    );
  }
}

// ─── Empty state ────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onNearby, required this.onSearch});
  final VoidCallback onNearby;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.liveBg,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.push_pin_outlined, size: 28, color: t.accent),
          ),
          const SizedBox(height: 12),
          Text(
            'No stops pinned',
            style: t.sans(20, weight: FontWeight.w600, color: t.fg),
          ),
          const SizedBox(height: 4),
          Text(
            'Pin a bus stop to see live arrivals at a glance.',
            style: t.sans(13, color: t.dim),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              FilledButton(
                onPressed: onNearby,
                style: FilledButton.styleFrom(
                  backgroundColor: t.accent,
                  foregroundColor: t.onAccent,
                ),
                child: const Text('Nearby'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: onSearch, child: const Text('Search')),
            ],
          ),
        ],
      ),
    );
  }
}
