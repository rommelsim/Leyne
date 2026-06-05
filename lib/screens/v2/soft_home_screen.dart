// SoftHomeScreen — Leyne 2.0 Home (Material 3 Android variant).
//
// Layout (matches iOS SoftHomeView.swift exactly):
//   header (greeting + title + filter/map buttons)
//   → live row (NEAR YOU · LIVE)
//   → MRT alerts
//   → "Closest to you" section (1 highlighted card)
//   → "Other nearby stops" section (up to 11 cards)
//   → "Live updates" banner
//   → empty state (when no nearby stops)
//
// Pinned stops live on the Saved tab — NOT rendered here.

import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../data/geo.dart';
import '../../data/models.dart';
import '../../services/location_service.dart';
import '../../state/app_model.dart';
import '../../theme.dart';
import '../../widgets/v2/confidence.dart';
import '../../widgets/v2/proximity.dart';
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

sealed class _Item {}

class _HeaderItem extends _Item {}

class _LiveRowItem extends _Item {}

class _GapItem extends _Item {
  _GapItem(this.height);
  final double height;
}

class _EyebrowItem extends _Item {
  _EyebrowItem(this.label);
  final String label;
}

class _NearbyCardItem extends _Item {
  _NearbyCardItem(this.stop, {required this.highlight});
  final NearbyStop stop;
  final bool highlight;
}

class _AlertItem extends _Item {
  _AlertItem(this.alert);
  final TrainAlert alert;
}

class _LiveBannerItem extends _Item {}

class _EmptyItem extends _Item {}

// ─────────────────────────────────────────────────────────────────────────────

class _SoftHomeScreenState extends State<SoftHomeScreen> {
  final Set<String> _dismissedAlerts = {};

  // ── Walk-minute memoisation cache ─────────────────────────────────────────
  final Map<String, int?> _walkCache = {};

  @override
  void initState() {
    super.initState();
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

  // ignore: unused_element
  int? _walkMinutes(String code) {
    if (_walkCache.containsKey(code)) return _walkCache[code];
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

  /// Nearby stops sorted by distance, de-duped against pinned. Capped at 12
  /// total (1 closest + 11 others).
  List<NearbyStop> _nearbyStops(Set<String> pinnedCodes) {
    final base = DataStore.shared.nearby
        .where((s) => !pinnedCodes.contains(s.stopCode))
        .toList()
      ..sort((a, b) => a.distanceM.compareTo(b.distanceM));
    return base.take(12).toList();
  }

  Future<void> _refresh(List<Pin> pins) async {
    await Future.wait(
      pins.map((p) => DataStore.shared.refreshArrivals(p.code)),
    );
    final loc = LocationService.shared.lastLocation;
    if (loc != null) {
      DataStore.shared.updateNearby(loc.lat, loc.lon);
    }
    DataStore.shared.prefetchNearbyArrivals();
  }

  List<_Item> _buildItems({
    required List<NearbyStop> nearby,
    required List<TrainAlert> visibleAlerts,
  }) {
    final items = <_Item>[];

    items.add(_HeaderItem());
    items.add(_GapItem(6));
    items.add(_LiveRowItem());

    // MRT alerts
    if (visibleAlerts.isNotEmpty) {
      items.add(_GapItem(16));
      for (var i = 0; i < visibleAlerts.length; i++) {
        if (i > 0) items.add(_GapItem(10));
        items.add(_AlertItem(visibleAlerts[i]));
      }
    }

    if (nearby.isEmpty) {
      items.add(_GapItem(8));
      items.add(_EmptyItem());
      return items;
    }

    // "Closest to you" — the single nearest stop.
    items.add(_GapItem(16));
    items.add(_EyebrowItem('Closest to you'));
    items.add(_GapItem(10));
    items.add(_NearbyCardItem(nearby.first, highlight: true));

    // "Other nearby stops" — up to 11 more.
    final others = nearby.skip(1).take(11).toList();
    if (others.isNotEmpty) {
      items.add(_GapItem(16));
      items.add(_EyebrowItem('Other nearby stops'));
      items.add(_GapItem(10));
      for (var i = 0; i < others.length; i++) {
        if (i > 0) items.add(_GapItem(10));
        items.add(_NearbyCardItem(others[i], highlight: false));
      }
    }

    // "Live updates" banner
    items.add(_GapItem(16));
    items.add(_LiveBannerItem());

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
              nearby: nearby,
              visibleAlerts: visibleAlerts,
            );

            return RefreshIndicator(
              color: t.accent,
              onRefresh: () => _refresh(pins),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: items.length,
                itemBuilder: (context, index) =>
                    _buildItem(context, items[index], pins: pins),
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
    required List<Pin> pins,
  }) {
    return switch (item) {
      _HeaderItem() => _header(context),
      _LiveRowItem() => _liveRow(context),
      _GapItem(:final height) => SizedBox(height: height),
      _EyebrowItem(:final label) => Eyebrow(label),
      _NearbyCardItem(:final stop, :final highlight) => RepaintBoundary(
          child: _NearbyCard(
            stop: stop,
            highlight: highlight,
            onTap: () => widget.onOpenStop(stop.stopCode),
          ),
        ),
      _AlertItem(:final alert) => _mrtAlertCard(context, alert),
      _LiveBannerItem() => _liveUpdatesBanner(context, pins: pins),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(_greeting()),
        const SizedBox(height: 2),
        Text(
          'Stops near you',
          style: t.sans(30, weight: FontWeight.w700, color: t.fg),
        ),
      ],
    );
  }

  Widget _liveRow(BuildContext context) {
    final t = context.t;
    final located = LocationService.shared.lastLocation != null;
    return Row(
      children: [
        Icon(
          located ? Icons.location_on : Icons.location_off,
          size: 13,
          color: located ? LyneSignal.meBlue : t.dim,
        ),
        const SizedBox(width: 5),
        Text(
          located ? 'NEAR YOU' : 'LOCATION OFF',
          style: t
              .mono(10, weight: FontWeight.w700,
                  color: located ? LyneSignal.meBlue : t.dim)
              .copyWith(letterSpacing: 0.8),
        ),
        if (located) ...[
          const SizedBox(width: 6),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: t.soon, shape: BoxShape.circle),
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
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(LyneRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(LyneRadius.md),
        onTap: () => setState(() => _dismissedAlerts.add(alert.id)),
        child: Padding(
          padding: const EdgeInsets.all(14),
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
      ),
    );
  }

  Widget _liveUpdatesBanner(BuildContext context, {required List<Pin> pins}) {
    final t = context.t;
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(LyneRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(LyneRadius.md),
        onTap: () => _refresh(pins),
        child: Semantics(
          label:
              'Live updates. Arrival times update every few seconds. Tap to refresh.',
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.sensors, size: 18, color: t.soon),
                const SizedBox(width: 12),
                Expanded(
                  child: RichText(
                    maxLines: 2,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'Live updates  ',
                          style:
                              t.sans(13, weight: FontWeight.w600, color: t.fg),
                        ),
                        TextSpan(
                          text: 'Arrival times update every few seconds.',
                          style: t.sans(13, color: t.dim),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, size: 16, color: t.faint),
              ],
            ),
          ),
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

// ─── Nearby stop card ────────────────────────────────────────────────────────

/// A nearby-stop card matching iOS SoftNearbyStopCard:
/// identity (pin tile · name · "Stop {code} · road" · walk + distance)
/// over a 1px divider, then the soonest service's next three arrival columns.
/// The closest stop is highlighted with a green border + "Closest stop" badge.
class _NearbyCard extends StatelessWidget {
  const _NearbyCard({
    required this.stop,
    required this.highlight,
    required this.onTap,
  });

  final NearbyStop stop;
  final bool highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final borderColor = highlight ? t.soon : t.line;
    final borderWidth = highlight ? 1.5 : 1.0;

    return Semantics(
      button: true,
      label: 'Open ${stop.stopName.isEmpty ? stop.stopCode : stop.stopName}',
      child: Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: borderColor, width: borderWidth),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (highlight) ...[
                  _closestBadge(t),
                  const SizedBox(height: 12),
                ],
                _identityRow(context, t),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, thickness: 1, color: t.line),
                ),
                // Wrap service row in per-second tick.
                ListenableBuilder(
                  listenable: AppModel.shared,
                  builder: (context, _) => _serviceRow(context, t),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _closestBadge(LyneTheme t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: t.soon,
        borderRadius: BorderRadius.circular(LyneRadius.full),
      ),
      child: Text(
        'Closest stop',
        style: t.sans(11, weight: FontWeight.w700, color: t.contrastFg),
      ),
    );
  }

  Widget _identityRow(BuildContext context, LyneTheme t) {
    final code = stop.stopCode;
    final name = stop.stopName.isEmpty ? code : stop.stopName;
    final road = DataStore.shared.roadName(code);
    final subtitle = road.isEmpty ? 'Stop $code' : 'Stop $code · $road';
    final walkMin = stop.walkMin;
    final dist = fmtDistance(stop.distanceM);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Leading 46×46 rounded tile.
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.surfaceHi,
            borderRadius: BorderRadius.circular(LyneRadius.md),
          ),
          child: Icon(Icons.location_on, size: 20, color: t.fg),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: t.sans(17, weight: FontWeight.w600, color: t.fg),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: t.mono(12.5, color: t.dim),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              // Walk + distance line.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.directions_walk, size: 13, color: t.soon),
                  const SizedBox(width: 3),
                  Text(
                    '${walkMin < 1 ? 1 : walkMin} min walk',
                    style: t.mono(12.5,
                        weight: FontWeight.w500, color: t.soon),
                  ),
                  const SizedBox(width: 5),
                  Text('·',
                      style: t.mono(12.5, color: t.faint)),
                  const SizedBox(width: 5),
                  Text(dist, style: t.mono(12.5, color: t.dim)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Icon(Icons.chevron_right, size: 18, color: t.faint),
      ],
    );
  }

  Widget _serviceRow(BuildContext context, LyneTheme t) {
    final code = stop.stopCode;
    final now = DateTime.now();
    final feed = Freshness.from(DataStore.shared.lastRefresh(code));

    // Re-sort by live etaSec, recomputed from arrivalDate.
    final raw = DataStore.shared.servicesFor(code);
    if (raw.isEmpty) return _quietRow(t);

    // Pick the soonest service (recompute etaSec from arrivalDate for smoothness).
    Service soonest = raw.first;
    int soonestSec = _liveSec(soonest, now);
    for (final s in raw.skip(1)) {
      final sec = _liveSec(s, now);
      if (sec < soonestSec) {
        soonest = s;
        soonestSec = sec;
      }
    }

    final conf =
        ArrivalConfidence.of(monitored: soonest.monitored, feed: feed);
    final badge = serviceBadgeColors(etaSec: soonestSec, confidence: conf, t: t);
    final etas = _arrivalSecs(soonest, now);
    final destLabel = _destLabel(soonest.dest);

    return Row(
      children: [
        // Service-number badge.
        Container(
          constraints: const BoxConstraints(minWidth: 46, minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: badge.fill,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(
            soonest.no,
            style: t.sans(17, weight: FontWeight.w700, color: badge.fg),
          ),
        ),
        const SizedBox(width: 12),
        // Destination label.
        Expanded(
          child: Text(
            destLabel,
            style: t.sans(14, weight: FontWeight.w500, color: t.fg),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        // Up to 3 ETA columns.
        _etaColumns(t, etas, conf),
      ],
    );
  }

  Widget _etaColumns(
      LyneTheme t, List<int> etas, ArrivalConfidence conf) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < etas.length; i++) ...[
          if (i > 0) ...[
            const SizedBox(width: 10),
            Container(width: 1, height: 30, color: t.line),
            const SizedBox(width: 10),
          ],
          _etaColumn(t, etas[i], lead: i == 0, conf: conf),
        ],
      ],
    );
  }

  Widget _etaColumn(LyneTheme t, int sec,
      {required bool lead, required ArrivalConfidence conf}) {
    final eta = fmtEta(sec);
    final arriving = eta.big == 'Arr';
    final color = lead
        ? etaColor(etaSec: sec, confidence: conf, t: t)
        : t.fg;
    final isGhost = conf == ArrivalConfidence.unconfirmed;

    // minWidth (not a fixed width) so "Arr" — wider than a 2-digit ETA —
    // expands instead of overflowing into the adjacent divider/column.
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (lead && isGhost)
                ExcludeSemantics(
                  child: Text(
                    '~',
                    style: t.mono(11,
                        weight: FontWeight.w400, color: t.faint),
                  ),
                ),
              Text(
                arriving ? 'Arr' : eta.big,
                style: t.mono(20, weight: FontWeight.w600, color: color),
              ),
              if (lead && conf == ArrivalConfidence.live) ...[
                const SizedBox(width: 1),
                ExcludeSemantics(
                  child: Transform.translate(
                    offset: const Offset(0, -7),
                    child: Icon(Icons.sensors, size: 9, color: t.soon),
                  ),
                ),
              ],
            ],
          ),
          Text(
            arriving ? 'now' : eta.small,
            style: t.mono(10, color: t.dim),
          ),
        ],
      ),
    );
  }

  Widget _quietRow(LyneTheme t) {
    return Row(
      children: [
        const ConfidenceDot(confidence: ArrivalConfidence.stale, size: 6),
        const SizedBox(width: 7),
        Text(
          'No live arrivals right now',
          style: t.mono(12, color: t.faint),
        ),
      ],
    );
  }

  /// Live seconds for a service — recomputes from arrivalDate for smooth ticking.
  static int _liveSec(Service s, DateTime now) {
    if (s.arrivalDate != null) {
      return s.arrivalDate!.difference(now).inSeconds.clamp(0, 1 << 30);
    }
    return s.etaSec;
  }

  /// Build 1–3 arrival times from a service (in seconds-from-now).
  static List<int> _arrivalSecs(Service s, DateTime now) {
    final first = _liveSec(s, now);
    final result = [first];

    int? second;
    if (s.followingDate != null) {
      second = s.followingDate!.difference(now).inSeconds.clamp(0, 1 << 30);
    } else if (s.followingSec > first) {
      second = s.followingSec;
    }
    if (second != null && second > first) result.add(second);

    if (s.thirdDate != null) {
      final third =
          s.thirdDate!.difference(now).inSeconds.clamp(0, 1 << 30);
      if (third > (result.last)) result.add(third);
    }
    return result;
  }

  static String _destLabel(String dest) {
    if (dest.isEmpty) return 'Next bus';
    if (dest.startsWith('To ')) return dest;
    return 'To $dest';
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
        borderRadius: BorderRadius.circular(LyneRadius.lg),
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
            child: Icon(Icons.location_searching, size: 28, color: t.accent),
          ),
          const SizedBox(height: 12),
          Text(
            'No stops yet',
            style: t.sans(20, weight: FontWeight.w600, color: t.fg),
          ),
          const SizedBox(height: 4),
          Text(
            'Turn on location to see stops near you, or search for one.',
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
                child: const Text('Use location'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: onSearch,
                child: const Text('Search'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
