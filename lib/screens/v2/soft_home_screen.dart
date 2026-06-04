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
      _PinCardItem(:final pin) =>
        RepaintBoundary(child: _pinStopCard(pin)),
      _NearbyCardItem(:final stop) =>
        RepaintBoundary(child: _nearbyStopCard(stop)),
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

  /// Pinned-stop card — the unified SoftStopCard. When the pin has a custom
  /// nickname it becomes the card title (the name the user gave it), with the
  /// real stop name kept in the subline so context isn't lost. Without a
  /// nickname the title is the stop's own name + "code · road" subline.
  Widget _pinStopCard(Pin pin) {
    final dsName = DataStore.shared.stopName(pin.code);
    final stopName = dsName.isEmpty ? pin.code : dsName;
    final nick = pin.nickname.trim();
    final hasNick = nick.isNotEmpty && nick.toLowerCase() != stopName.toLowerCase();
    final walk = _walkMinutes(pin.code);
    return _SoftStopCard(
      name: hasNick ? nick : stopName,
      code: pin.code,
      // Nicknamed → show the real stop name in the subline; otherwise the road.
      desc: hasNick ? stopName : DataStore.shared.roadName(pin.code),
      trailing: walk != null ? '$walk min' : null,
      services: _filteredServices(pin),
      feed: Freshness.from(DataStore.shared.lastRefresh(pin.code)),
      onTap: () => widget.onOpenStop(pin.code),
    );
  }

  /// Nearby-stop card — same unified card, trailing shows distance.
  Widget _nearbyStopCard(NearbyStop stop) {
    return _SoftStopCard(
      name: stop.stopName,
      code: stop.stopCode,
      desc: DataStore.shared.roadName(stop.stopCode),
      trailing: fmtDistance(stop.distanceM),
      services: DataStore.shared.servicesFor(stop.stopCode),
      feed: Freshness.from(DataStore.shared.lastRefresh(stop.stopCode)),
      onTap: () => widget.onOpenStop(stop.stopCode),
    );
  }

  Widget _header(BuildContext context) {
    final t = context.t;
    // Greeting + title only — no search icon here. Search is reached via the
    // bottom-bar Search tab (matching iOS, whose home header has no search
    // button either); a second header button was redundant.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(_greeting()),
        const SizedBox(height: 2),
        Text(
          'Stops near you',
          style: t.sans(28, weight: FontWeight.w600, color: t.fg),
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

// ─── Unified stop card (mirrors iOS SoftStopCard) ───────────────────────────

/// Natural service-number order ('7' < '91' < '107M' < '191') so a stop's
/// chips read like its panel — leading integer first, then lexical.
int _compareServiceNo(Service a, Service b) {
  int lead(String s) =>
      int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1 << 30;
  final c = lead(a.no).compareTo(lead(b.no));
  return c != 0 ? c : a.no.compareTo(b.no);
}

/// The Leyne 3.0 Home card — a stop's identity (pin tile · name · code · road)
/// + a trailing distance/walk, then a wrapping row of mini bus-number chips.
/// Used for BOTH the Pinned and Nearby sections so the page reads as one
/// language — a direct port of iOS `SoftStopCard`. Material-native (Material
/// surface + InkWell ripple). The chip row's ETAs refresh each second via a
/// narrow ListenableBuilder(AppModel) so only the chips — not the card chrome —
/// rebuild on the tick.
class _SoftStopCard extends StatelessWidget {
  const _SoftStopCard({
    required this.name,
    required this.code,
    required this.desc,
    required this.trailing,
    required this.services,
    required this.feed,
    required this.onTap,
  });

  static const int _maxChips = 4;

  final String name;
  final String code;
  final String desc; // road name / "opp Blk 445"; may be empty
  final String? trailing; // distance ("80m") or walk ("3 min"); may be null
  final List<Service> services;
  final Freshness feed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    // Chips order by bus number (matching iOS), capped at 4 + "+N".
    final sorted = [...services]..sort(_compareServiceNo);

    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(LyneRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headerRow(context),
              const SizedBox(height: 11),
              if (sorted.isEmpty)
                _quietRow(context)
              else
                _chipRow(context, sorted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerRow(BuildContext context) {
    final t = context.t;
    return Row(
      children: [
        // Leading map-pin tile — distinguishes a stop card at a glance.
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.surfaceHi,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(Icons.location_on, size: 18, color: t.fg),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: t.sans(16, weight: FontWeight.w600, color: t.fg),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                desc.isEmpty ? code : '$code · $desc',
                style: t.mono(11.5, color: t.dim),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Text(
            trailing!,
            style: t.mono(12, weight: FontWeight.w600, color: t.dim),
          ),
        ],
        const SizedBox(width: 6),
        Icon(Icons.chevron_right, size: 18, color: t.faint),
      ],
    );
  }

  /// Wrapping mini-chip row. Wrapped in a narrow AppModel listener so only the
  /// chips re-render each second (the header/tile stay put).
  Widget _chipRow(BuildContext context, List<Service> sorted) {
    final t = context.t;
    return ListenableBuilder(
      listenable: AppModel.shared,
      builder: (context, _) {
        final now = DateTime.now();
        final visible = sorted.take(_maxChips).toList();
        final overflow = sorted.length > _maxChips
            ? sorted.length - _maxChips
            : 0;
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final s in visible)
              _MiniBusChip(
                svc: s.no,
                // Re-derive ETA from the live arrivalDate for a smooth
                // countdown between LTA polls (as AppModel.liveServices does).
                etaSec: s.arrivalDate != null
                    ? s.arrivalDate!.difference(now).inSeconds.clamp(0, 1 << 30)
                    : s.etaSec,
                confidence: ArrivalConfidence.of(
                  monitored: s.monitored,
                  feed: feed,
                ),
              ),
            if (overflow > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  '+$overflow',
                  style: t.mono(12, weight: FontWeight.w600, color: t.faint),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _quietRow(BuildContext context) {
    final t = context.t;
    return Row(
      children: [
        const ConfidenceDot(confidence: ArrivalConfidence.stale, size: 6),
        const SizedBox(width: 7),
        Text('No live arrivals right now', style: t.mono(11, color: t.faint)),
      ],
    );
  }
}

/// Compact next-bus chip: a service micro-pill + confidence-treated ETA, in a
/// rounded capsule. Port of iOS `MiniBusChip`. Whisper-quiet: the ETA reads as
/// a confident arrival; the only estimate tell is a faint trailing "~".
class _MiniBusChip extends StatelessWidget {
  const _MiniBusChip({
    required this.svc,
    required this.etaSec,
    required this.confidence,
  });

  final String svc;
  final int etaSec;
  final ArrivalConfidence confidence;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final eta = fmtEta(etaSec);
    final arriving = eta.big == 'Arr';
    final whisper = confidence == ArrivalConfidence.stale ||
        confidence == ArrivalConfidence.unconfirmed;
    final label = arriving ? 'now' : '${eta.big} ${eta.small}';

    return Container(
      height: 27,
      padding: const EdgeInsets.only(left: 4, right: 9),
      decoration: BoxDecoration(
        color: t.surfaceHi,
        borderRadius: BorderRadius.circular(LyneRadius.full),
        border: Border.all(color: t.line, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Inner service micro-pill.
          Container(
            constraints: const BoxConstraints(minWidth: 22),
            height: 18,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: t.line, width: 0.5),
            ),
            child: Text(
              svc,
              style: t.mono(12, weight: FontWeight.w700, color: t.fg),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: t.mono(
              12,
              weight: FontWeight.w600,
              color: etaColor(etaSec: etaSec, confidence: confidence, t: t),
            ),
          ),
          if (whisper) ...[
            const SizedBox(width: 1),
            ExcludeSemantics(
              child: Opacity(
                opacity: 0.7,
                child: Text(
                  '~',
                  style: t.mono(9, weight: FontWeight.w400, color: t.faint),
                ),
              ),
            ),
          ],
        ],
      ),
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
