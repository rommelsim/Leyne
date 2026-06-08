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
// Saved stops live on the Saved tab but ALSO appear here when they're near
// you — Nearby reflects what's around you, so saving never removes a stop
// from it (iOS parity). Long-press a card for a quick stop-view peek.

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
import 'manage_alerts_screen.dart';

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

  /// Nearby stops sorted by distance, capped at 12 (1 closest + 11 others).
  /// Saved/pinned stops are intentionally kept — Nearby reflects what's around
  /// you, so saving a stop must never make it vanish from here (iOS parity).
  List<NearbyStop> _nearbyStops() {
    final base = [...DataStore.shared.nearby]
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

  /// Long-press peek — a Material take on the iOS context-menu preview: the
  /// stop's live arrivals at a glance, with one tap to open it fully. Replaces
  /// the old long-press, which did nothing useful.
  void _showStopPeek(BuildContext context, NearbyStop stop) {
    final t = context.t;
    DataStore.shared.ensureArrivals(stop.stopCode);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: t.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => _StopPeekSheet(
        stop: stop,
        onOpen: () {
          Navigator.of(sheetCtx).pop();
          widget.onOpenStop(stop.stopCode);
        },
      ),
    );
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
            final nearby = _nearbyStops();
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
            onLongPress: () => _showStopPeek(context, stop),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow(_greeting()),
              const SizedBox(height: 2),
              Text(
                'Stops near you',
                style: t.sans(30, weight: FontWeight.w700, color: t.fg),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _alertButton(context),
      ],
    );
  }

  /// Top-right bell → the central alerts list, with a count badge when the
  /// user has any alerts set. Refreshes the badge on return (an alert may
  /// have been deleted in the list).
  Widget _alertButton(BuildContext context) {
    final t = context.t;
    final count = AppModel.shared.alerts.length;
    return Semantics(
      button: true,
      label: count == 0 ? 'Alerts' : 'Alerts, $count set',
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: () {
          Navigator.of(context)
              .push(MaterialPageRoute(
                builder: (_) => const ManageAlertsScreen(),
              ))
              .then((_) {
            if (mounted) setState(() {});
          });
        },
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.surface,
            shape: BoxShape.circle,
            border: Border.all(color: t.line, width: 1),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(Icons.notifications_rounded, size: 20, color: t.fg),
              if (count > 0)
                Positioned(
                  top: -6,
                  right: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    constraints:
                        const BoxConstraints(minWidth: 18, minHeight: 18),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t.soon,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: t.bg, width: 1.5),
                    ),
                    child: Text(
                      '$count',
                      style: t.sans(11,
                          weight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
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
/// identity (pin tile · name · "Stop {code} · road" · walk + distance) over a
/// 1px divider, then the stop's top-3 services — favourites first, then soonest
/// — each on its own row with its next arrival and a "View all buses" footer.
/// The closest stop is highlighted with a green border + "Closest stop" badge.
class _NearbyCard extends StatelessWidget {
  const _NearbyCard({
    required this.stop,
    required this.highlight,
    required this.onTap,
    this.onLongPress,
  });

  final NearbyStop stop;
  final bool highlight;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

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
          onLongPress: onLongPress,
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
                // Wrap arrivals in per-second tick + favourite changes.
                ListenableBuilder(
                  listenable: AppModel.shared,
                  builder: (context, _) => _arrivalsSection(context, t),
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
      ],
    );
  }

  /// The stop's top-3 services ranked favourite-first → soonest, each on its
  /// own row, plus a "View all buses" footer. Mirrors iOS SoftNearbyStopCard.
  Widget _arrivalsSection(BuildContext context, LyneTheme t) {
    final code = stop.stopCode;
    final now = DateTime.now();
    final feed = Freshness.from(DataStore.shared.lastRefresh(code));
    final ranked = _rankedArrivals(code, now);
    if (ranked.isEmpty) return _quietRow(t);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < ranked.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _arrivalRow(t, ranked[i].service, ranked[i].fav, now, feed),
        ],
        _viewAllRow(t),
      ],
    );
  }

  /// Rank the stop's services: favourites first (saved here OR anywhere), then
  /// earliest within each group, capped at three. The list is sorted by live
  /// ETA before partitioning so each group stays soonest-first.
  List<({Service service, bool fav})> _rankedArrivals(
      String code, DateTime now) {
    final raw = DataStore.shared.servicesFor(code);
    bool isFav(Service s) =>
        AppModel.shared.isFavService(no: s.no, stop: code) ||
        AppModel.shared.isFavService(no: s.no);
    final sorted = [...raw]
      ..sort((a, b) => _liveSec(a, now).compareTo(_liveSec(b, now)));
    final favs = sorted.where(isFav);
    final rest = sorted.where((s) => !isFav(s));
    return [...favs, ...rest]
        .take(3)
        .map((s) => (service: s, fav: isFav(s)))
        .toList();
  }

  /// One ranked service row: number badge (proximity-tinted), a gold star when
  /// favourited, the destination, then its single soonest arrival.
  Widget _arrivalRow(
      LyneTheme t, Service s, bool fav, DateTime now, Freshness feed) {
    final sec = _liveSec(s, now);
    final conf = ArrivalConfidence.of(monitored: s.monitored, feed: feed);
    final badge = serviceBadgeColors(etaSec: sec, confidence: conf, t: t);
    return Row(
      children: [
        Container(
          constraints: const BoxConstraints(minWidth: 46, minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: badge.fill,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(
            s.no,
            style: t.sans(16, weight: FontWeight.w700, color: badge.fg),
          ),
        ),
        const SizedBox(width: 10),
        if (fav) ...[
          const Icon(Icons.star, size: 13, color: Color(0xFFF5B500)),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            _destLabel(s.dest),
            style: t.sans(14, weight: FontWeight.w500, color: t.fg),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        _etaTrailing(t, sec, conf),
      ],
    );
  }

  /// The single soonest arrival, trailing-aligned: proximity-tinted "Arr"
  /// (with a live signal) or "{n} min". A faint "~" precedes an unconfirmed
  /// estimate — the whisper-quiet honesty cue used app-wide.
  Widget _etaTrailing(LyneTheme t, int sec, ArrivalConfidence conf) {
    final eta = fmtEta(sec);
    final arriving = eta.big == 'Arr';
    final isGhost = conf == ArrivalConfidence.unconfirmed;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (isGhost)
          ExcludeSemantics(
            child: Text('~',
                style: t.mono(13, weight: FontWeight.w400, color: t.faint)),
          ),
        Text(
          arriving ? 'Arr' : eta.big,
          style: t.mono(19,
              weight: FontWeight.w600,
              color: etaColor(etaSec: sec, confidence: conf, t: t)),
        ),
        if (arriving) ...[
          if (conf == ArrivalConfidence.live) ...[
            const SizedBox(width: 1),
            ExcludeSemantics(
              child: Transform.translate(
                offset: const Offset(0, -6),
                child: Icon(Icons.sensors, size: 9, color: t.soon),
              ),
            ),
          ],
        ] else ...[
          const SizedBox(width: 3),
          Text(eta.small, style: t.mono(11, color: t.dim)),
        ],
      ],
    );
  }

  /// "View all buses" footer with a leading hairline — the tappable cue that
  /// opens the full stop (the whole card shares the same action).
  Widget _viewAllRow(LyneTheme t) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        children: [
          Divider(height: 1, thickness: 1, color: t.line),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('View all buses',
                  style: t.sans(13, weight: FontWeight.w600, color: t.dim)),
              const Spacer(),
              Icon(Icons.chevron_right, size: 16, color: t.faint),
            ],
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

// ─── Long-press stop peek ────────────────────────────────────────────────────

/// A compact "mini stop view" shown on long-press — the stop's identity and its
/// soonest live arrivals (number · destination · crowd · ETA), with one button
/// to open the full stop. Material counterpart to the iOS context-menu preview.
class _StopPeekSheet extends StatelessWidget {
  const _StopPeekSheet({required this.stop, required this.onOpen});

  final NearbyStop stop;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final code = stop.stopCode;
    final name = stop.stopName.isEmpty ? code : stop.stopName;
    final road = DataStore.shared.roadName(code);
    final subtitle = road.isEmpty ? 'Stop $code' : 'Stop $code · $road';

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: t.sans(20, weight: FontWeight.w700, color: t.fg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(subtitle, style: t.mono(12.5, color: t.dim)),
            const SizedBox(height: 14),
            // Live arrivals — AppModel.shared drives the 1-second ETA tick.
            ListenableBuilder(
              listenable: Listenable.merge([DataStore.shared, AppModel.shared]),
              builder: (context, _) => _arrivals(context, t, code),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onOpen,
                style: FilledButton.styleFrom(
                  backgroundColor: t.accent,
                  foregroundColor: t.onAccent,
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('Open stop'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _arrivals(BuildContext context, LyneTheme t, String code) {
    final now = DateTime.now();
    final feed = Freshness.from(DataStore.shared.lastRefresh(code));
    final raw = [...DataStore.shared.servicesFor(code)]
      ..sort((a, b) => _liveSec(a, now).compareTo(_liveSec(b, now)));
    final shown = raw.take(6).toList();
    if (shown.isEmpty) {
      return Row(
        children: [
          const ConfidenceDot(confidence: ArrivalConfidence.stale, size: 6),
          const SizedBox(width: 7),
          Text('No live arrivals right now',
              style: t.mono(12, color: t.faint)),
        ],
      );
    }
    return Column(
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: t.line),
          _row(t, shown[i], now, feed),
        ],
      ],
    );
  }

  Widget _row(LyneTheme t, Service s, DateTime now, Freshness feed) {
    final sec = _liveSec(s, now);
    final conf = ArrivalConfidence.of(monitored: s.monitored, feed: feed);
    final badge = serviceBadgeColors(etaSec: sec, confidence: conf, t: t);
    final eta = fmtEta(sec);
    final arriving = eta.big == 'Arr';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 32),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badge.fill,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(s.no,
                style: t.sans(15, weight: FontWeight.w700, color: badge.fg)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.dest.isEmpty ? 'Bus ${s.no}' : 'To ${s.dest}',
              style: t.sans(13.5, weight: FontWeight.w500, color: t.fg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _crowdDot(t, s.load),
          const SizedBox(width: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                arriving ? 'Arr' : eta.big,
                style: t.mono(17,
                    weight: FontWeight.w600,
                    color: etaColor(etaSec: sec, confidence: conf, t: t)),
              ),
              if (!arriving) ...[
                const SizedBox(width: 3),
                Text(eta.small, style: t.mono(10, color: t.dim)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Tiny crowd cue — green seats / amber standing / red crowded, matching the
  /// app-wide occupancy semantics.
  Widget _crowdDot(LyneTheme t, Load load) {
    final (Color dotColor, String label) = switch (load) {
      Load.sea => (t.soon, 'Seats'),
      Load.sda => (t.warn, 'Standing'),
      Load.lsd => (t.crit, 'Crowded'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: t.sans(11, color: t.dim)),
      ],
    );
  }

  static int _liveSec(Service s, DateTime now) {
    if (s.arrivalDate != null) {
      return s.arrivalDate!.difference(now).inSeconds.clamp(0, 1 << 30);
    }
    return s.etaSec;
  }
}
