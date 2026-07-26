// SoftHomeScreen — Leyne 2.0 Home (Material 3 Android variant).
//
// Layout (content parity with iOS WSHomeView.swift — not a visual clone):
//   header ("Nearby" title + "<area> · updated <when>" caption, spec item 3a)
//   → MRT strip (nearest stations, always visible when located)
//   → "Closest to you" section (1 highlighted card; its eyebrow carries the
//     ● LIVE badge + right-aligned "Updated h:mm", like iOS's BUS STOPS
//     section header — owner flagged the old standalone live row under the
//     search bar as a design mismatch, 2026-07-04)
//   → "Other nearby stops" section (up to 11 cards)
//   → "Other nearby stops" section (up to 11 cards)
//   → hidden-stops restore footer (when any nearby stop is hidden)
//   → empty state (when no nearby stops)
//
// Saved stops live on the Saved tab but ALSO appear here when they're near
// you — Nearby reflects what's around you, so saving never removes a stop
// from it (iOS parity). Long-press a card for a quick stop-view peek.
// Disruptions live on the Alerts tab (with its own unseen badge), not here.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/data_store.dart';
import '../../data/geo.dart';
import '../../data/models.dart';
import '../../data/mrt_geo.dart';
import '../../data/mrt_stations.dart';
import '../../data/weather_store.dart';
import '../../services/location_service.dart';
import '../../state/app_model.dart';
import '../../theme.dart';
import '../../theme/soft_blue.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/v2/alert_actions.dart';
import '../../widgets/v2/confidence.dart';
import '../../widgets/v2/proximity.dart';
import '../../widgets/v2/soft_components.dart';
import '../../widgets/v2/soft_tab_bar.dart';
import '../../widgets/v2/weather_header.dart';
import 'soft_mrt_station_screen.dart';

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

class _WeatherItem extends _Item {}

class _HeaderItem extends _Item {
  _HeaderItem(this.caption);

  /// "`<area> · updated <when>`" (spec item 3a, 2026-07-25) — computed once
  /// in `_buildItems` where `nearby` is in scope.
  final String caption;
}

/// Tap-to-search pill — mirrors WSHomeView.swift's `searchBar`: sits directly
/// under the header/title, above everything else (including the MRT strip).
/// Not an inline TextField — the whole pill is a button that pushes the real
/// search screen via `onOpenSearch`, same as iOS's `Button(action: onSearch)`.
class _SearchBarItem extends _Item {}


class _GapItem extends _Item {
  _GapItem(this.height);
  final double height;
}

/// All/Buses/MRT filter chips (spec item 7) — mirrors WSHomeView.swift's
/// `softChips`. Sits between the hero and the stop list.
class _FilterChipsItem extends _Item {}

/// Anatomy-matched loading skeleton (spec item 6) — shown while nothing has
/// loaded yet and `referenceState` is loading. Mirrors WSHomeView.swift's
/// `skeletonStack`/`WSSkeletonCard`.
class _SkeletonItem extends _Item {
  _SkeletonItem({this.hero = false, this.delay = Duration.zero});
  final bool hero;
  final Duration delay;
}

class _EyebrowItem extends _Item {
  _EyebrowItem(this.label, {this.updated});
  final String label;

  /// Freshness meta ("h:mm"). When set, the eyebrow renders as a full
  /// section-header row: label + ● LIVE badge, "Updated h:mm" right-aligned —
  /// mirroring iOS's BUS STOPS section header (WSSectionHeader).
  final String? updated;
}

class _NearbyCardItem extends _Item {
  _NearbyCardItem(
    this.stop, {
    required this.highlight,
    this.badgeText = 'Closest stop',
  });
  final NearbyStop stop;
  final bool highlight;
  final String badgeText;
}

/// The horizontal "MRT" strip — the 3-4 nearest stations, its own small
/// section above the bus stop list (mirrors WSHomeView.swift's mrtSection).
class _MrtStripItem extends _Item {
  _MrtStripItem(this.stations);
  final List<MrtNearestResult> stations;
}

class _NativeAdItem extends _Item {}

/// Quiet footer offering the way back from the long-press "Hide from
/// Nearby" action — without it a hidden stop is gone for good (there is no
/// standalone "Me" tab). Mirrors WSHomeView.swift's busList footer.
class _HiddenFooterItem extends _Item {
  _HiddenFooterItem(this.count);
  final int count;
}

/// "View all / Show fewer" toggle after the first 3 "Other nearby stops"
/// rows (spec item 7).
class _ViewAllItem extends _Item {
  _ViewAllItem({required this.expanded, required this.total});
  final bool expanded;
  final int total;
}

class _EmptyItem extends _Item {}

/// A quiet prompt (shown under the saved-stop fallback) to enable location.
class _LocationNudgeItem extends _Item {}

// ─────────────────────────────────────────────────────────────────────────────

/// Which sections render — mirrors WSHomeView.swift's `Filter` (spec item 7).
enum _HomeFilter { all, buses, mrt }

class _SoftHomeScreenState extends State<SoftHomeScreen>
    with WidgetsBindingObserver {
  // ── Walk-minute memoisation cache ─────────────────────────────────────────
  final Map<String, int?> _walkCache = {};

  /// All/Buses/MRT filter (spec item 7) — chips between the hero and the
  /// stop list.
  _HomeFilter _filter = _HomeFilter.all;

  /// "View all / Show fewer" toggle for "Other nearby stops" past the first
  /// 3 rows (spec item 7).
  bool _stopsExpanded = false;

  /// Frozen display order for the nearby bus-stop list (spec item 5, ported
  /// from WSHomeView.swift's `frozenOrder`/`frozenAt`): GPS wobble re-sorts
  /// `DataStore.nearby` every few seconds, which made the whole list "jump
  /// around" (owner field test 2026-07-24). The list keeps its first-paint
  /// order; a re-sort happens only on pull-to-refresh or a genuine move
  /// (>350 m). Distances/ETAs inside the rows stay live regardless.
  List<String> _frozenOrder = [];
  ({double lat, double lon})? _frozenAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LocationService.shared.addListener(_onLocationChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _warm();
      await LocationService.shared.startIfAuthorized();
      final loc = LocationService.shared.lastLocation;
      if (loc != null) {
        DataStore.shared.updateNearby(loc.lat, loc.lon);
        _rebuildWalkCache();
        // Warm the weather store on first render; this is a no-op if the
        // snapshot is already fresh (e.g. app is still in the same session).
        WeatherStore.shared.refreshIfStale(lat: loc.lat, lon: loc.lon);
      }
      DataStore.shared.prefetchNearbyArrivals();
      _warmMrtCrowd();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LocationService.shared.removeListener(_onLocationChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Force-refresh weather when the user brings the app to the foreground,
      // matching how other apps update stale data after a background gap.
      final loc = LocationService.shared.lastLocation;
      WeatherStore.shared.refreshIfStale(
        force: true,
        lat: loc?.lat,
        lon: loc?.lon,
      );
      // Also refresh nearby arrivals so the list isn't showing stale ETAs
      // from before the background gap (iOS SoftHomeView/WSHomeView refresh
      // the same way on scenePhase → .active / onAppear).
      DataStore.shared.prefetchNearbyArrivals();
      // A launch-time bootstrap failure (LTA flake) shouldn't outlive a trip
      // to the background — retry quietly on return (iOS parity).
      if (DataStore.shared.referenceState.state == LoadState.error) {
        DataStore.shared.bootstrap();
      }
    }
  }

  void _onLocationChanged() {
    _rebuildWalkCache();
    _warmMrtCrowd();
    // LocationService already calls notifyListeners which triggers the outer
    // structural ListenableBuilder — no extra setState needed here.
  }

  /// Actively warms crowd data for the MRT strip's stations (spec item 7) —
  /// previously the strip only showed crowd "if available" from whatever the
  /// MRT tab/station screen happened to have already fetched. Mirrors
  /// WSHomeView.swift's `store.wsWarmCrowd(for: nearbyStations.map(\.station))`.
  void _warmMrtCrowd() {
    final lines = <MRTLine>{};
    for (final entry in _nearbyStations()) {
      for (final code in entry.station.codes) {
        final line = _lineFromCode(code);
        if (line != null) lines.add(line);
      }
    }
    for (final line in lines) {
      DataStore.shared.refreshCrowd(line);
    }
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
  /// Stops the user hid (long-press → "Hide from Nearby") are filtered out;
  /// they're restorable from Settings → Hidden stops.
  List<NearbyStop> _nearbyStops() {
    final live = [...DataStore.shared.nearby]
      ..removeWhere((s) => AppModel.shared.isHiddenNearby(s.stopCode))
      ..sort((a, b) => a.distanceM.compareTo(b.distanceM));
    _syncFrozenOrder(live);
    final ordered = _applyFrozenOrder(live);
    return ordered.take(12).toList();
  }

  /// (Re)freezes the display order to the current distance sort — spec
  /// item 5. Called on first data, and again only after a genuine move.
  void _refreezeOrder(List<NearbyStop> live) {
    _frozenOrder = live.map((s) => s.stopCode).toList();
    _frozenAt = LocationService.shared.lastLocation;
  }

  /// Freezes on first data; re-freezes only once the user has moved more
  /// than ~350 m from where the order was last frozen. Mirrors
  /// WSHomeView.swift's `syncFrozenOrder`.
  void _syncFrozenOrder(List<NearbyStop> live) {
    if (_frozenOrder.isEmpty) {
      if (live.isNotEmpty) _refreezeOrder(live);
      return;
    }
    final here = LocationService.shared.lastLocation;
    final anchor = _frozenAt;
    if (here != null &&
        anchor != null &&
        haversine(here.lat, here.lon, anchor.lat, anchor.lon) > 350) {
      _refreezeOrder(live);
    }
  }

  /// Orders [live] by the frozen index; newly-appearing stops (not yet in
  /// the frozen order) append at the end rather than shuffling in.
  List<NearbyStop> _applyFrozenOrder(List<NearbyStop> live) {
    if (_frozenOrder.isEmpty) return live;
    final idx = {
      for (var i = 0; i < _frozenOrder.length; i++) _frozenOrder[i]: i,
    };
    final ordered = [...live]..sort((a, b) {
      final ia = idx[a.stopCode] ?? 1 << 30;
      final ib = idx[b.stopCode] ?? 1 << 30;
      return ia.compareTo(ib);
    });
    return ordered;
  }

  /// Count of stops in range that are hidden from Nearby — computed from the
  /// RAW (unfiltered) DataStore list, not `_nearbyStops()`, so the restore
  /// footer still appears even if every in-range stop happens to be hidden.
  /// Mirrors WSHomeView.swift's `hiddenHere`.
  int _hiddenNearbyCount() => DataStore.shared.nearby
      .where((s) => AppModel.shared.isHiddenNearby(s.stopCode))
      .length;

  /// Restores every currently-hidden nearby stop. AppModel only exposes a
  /// per-code `unhideNearby`, so this loops rather than adding a bulk method
  /// to a file another agent owns.
  void _unhideAllNearby() {
    for (final s in DataStore.shared.nearby) {
      if (AppModel.shared.isHiddenNearby(s.stopCode)) {
        AppModel.shared.unhideNearby(s.stopCode);
      }
    }
  }


  /// 'h:mm' / 'HH:mm' render of a refresh timestamp, honouring the app-wide
  /// 24h clock preference. No intl — see `_dateEyebrow`.
  String _formatClock(DateTime dt, bool use24h) {
    final m = dt.minute.toString().padLeft(2, '0');
    if (use24h) return '${dt.hour.toString().padLeft(2, '0')}:$m';
    final h12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    return '$h12:$m ${dt.hour < 12 ? 'am' : 'pm'}';
  }

  /// Newest `lastRefresh` among the currently-visible nearby stop codes, for
  /// the "Updated h:mm" freshness meta next to the live row. Computed inline
  /// here (not a DataStore helper) per the owning agent's file boundary.
  String? _updatedLabel(List<NearbyStop> nearby) {
    DateTime? newest;
    for (final s in nearby) {
      final t = DataStore.shared.lastRefresh(s.stopCode);
      if (t != null && (newest == null || t.isAfter(newest))) newest = t;
    }
    if (newest == null) return null;
    return _formatClock(newest, AppModel.shared.use24h);
  }

  /// Relative freshness for the header caption (spec item 3a): "just now"
  /// (<5s), "Ns ago" (<60s), else "Nm ago" — distinct from `_updatedLabel`'s
  /// clock-format string used by the "Closest to you" section header.
  String? _relativeUpdated(List<NearbyStop> nearby) {
    DateTime? newest;
    for (final s in nearby) {
      final t = DataStore.shared.lastRefresh(s.stopCode);
      if (t != null && (newest == null || t.isAfter(newest))) newest = t;
    }
    if (newest == null) return null;
    final diff = DateTime.now().difference(newest);
    if (diff.inSeconds < 5) return 'just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    return '${diff.inMinutes}m ago';
  }

  /// "`<area> · updated <when>`" header caption (spec item 3a). Area = road
  /// name of the first (closest) nearby stop; falls back to a neutral
  /// prompt when there's neither an area nor a refresh timestamp yet (no
  /// location fix / nothing loaded).
  String _headerCaption(List<NearbyStop> nearby) {
    final area = nearby.isEmpty ? '' : DataStore.shared.roadName(nearby.first.stopCode);
    final when = _relativeUpdated(nearby);
    if (area.isEmpty) return 'Stops and stations around you';
    return when == null ? area : '$area · updated $when';
  }

  /// The 3-4 nearest MRT/LRT stations to the current location fix, for the
  /// "MRT" strip. Mirrors WSHomeView.swift's `nearbyStations`: empty (so the
  /// section hides) when there's no location fix or the geo dataset hasn't
  /// loaded/found anything nearby yet.
  List<MrtNearestResult> _nearbyStations() {
    final loc = LocationService.shared.lastLocation;
    if (loc == null) return const [];
    return MrtGeo.nearest(lat: loc.lat, lon: loc.lon, limit: 4);
  }

  /// Opens the station detail screen, mirroring SoftMrtScreen._openStation
  /// (same push pattern, `tabSelection: SoftTab.home` since we're pushing
  /// from Home rather than the MRT tab).
  void _openMrtStation(
    BuildContext context,
    MrtGeoStation station, {
    int? distanceM,
    int? walkMin,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SoftMrtStationScreen(
          station: station,
          onBack: () => Navigator.of(context).pop(),
          onTab: widget.onTab,
          tabSelection: SoftTab.home,
          distanceM: distanceM,
          walkMin: walkMin,
          // Without this, the station's "Bus stops at this station" rows
          // render inert (no chevron, no tap) when the station is entered
          // from Home — every other call site forwards it.
          onOpenStop: widget.onOpenStop,
        ),
      ),
    );
  }

  /// Builds a NearbyStop for a saved pin (no GPS). Distance/walk are 0 so the
  /// card hides the walk chip; arrivals are read live from servicesFor(code).
  NearbyStop _savedStop(String code) {
    final s = DataStore.shared.stopByCode[code];
    return NearbyStop(
      id: code,
      stopName: DataStore.shared.stopName(code),
      stopCode: code,
      lat: s?.latitude ?? 0,
      lon: s?.longitude ?? 0,
      distanceM: 0,
      walkMin: 0,
      services: const [],
    );
  }

  Future<void> _refresh(List<Pin> pins) async {
    await Future.wait(
      pins.map((p) => DataStore.shared.refreshArrivals(p.code)),
    );
    final loc = LocationService.shared.lastLocation;
    if (loc != null) {
      DataStore.shared.updateNearby(loc.lat, loc.lon);
    }
    // The one sanctioned re-sort (spec item 5): pull-to-refresh re-freezes
    // the nearby list to the current distance order. Clearing here lets the
    // next `_nearbyStops()` call (during the rebuild this triggers) re-freeze
    // from the just-updated `DataStore.nearby`.
    _frozenOrder = [];
    DataStore.shared.prefetchNearbyArrivals();
    _warmMrtCrowd();
  }

  /// Long-press peek — a Material take on the iOS context-menu preview: the
  /// stop's live arrivals at a glance plus the quick actions from the iOS
  /// context menu (pin, arrival alerts, open on map, copy code, hide), with
  /// one tap to open the stop fully.
  void _showStopPeek(BuildContext context, NearbyStop stop) {
    final t = context.t;
    DataStore.shared.ensureArrivals(stop.stopCode);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: t.surface,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => _StopPeekSheet(
        stop: stop,
        onOpen: () {
          Navigator.of(sheetCtx).pop();
          widget.onOpenStop(stop.stopCode);
        },
        onArrivalAlerts: () {
          Navigator.of(sheetCtx).pop();
          _quickArrivalAlerts(stop);
        },
        onOpenMaps: () {
          Navigator.of(sheetCtx).pop();
          _openOnMaps(stop);
        },
        onCopyCode: () {
          Navigator.of(sheetCtx).pop();
          _copyCode(stop.stopCode);
        },
        onHide: () {
          Navigator.of(sheetCtx).pop();
          AppModel.shared.hideFromNearby(stop.stopCode);
        },
      ),
    );
  }

  /// Quick arrival alert from the long-press menu — targets the stop's soonest
  /// service (mirrors the iOS "Arrival Alerts" action, which targets the
  /// soonest bus). Falls back to opening the stop when nothing is live yet so
  /// the user can still pick a bus. Reuses the Stop screen's alert flow.
  Future<void> _quickArrivalAlerts(NearbyStop stop) async {
    final code = stop.stopCode;
    DataStore.shared.ensureArrivals(code);
    final now = DateTime.now();
    int liveSec(Service s) => s.arrivalDate != null
        ? s.arrivalDate!.difference(now).inSeconds.clamp(0, 1 << 30)
        : s.etaSec;
    final services = [...DataStore.shared.servicesFor(code)]
      ..sort((a, b) => liveSec(a).compareTo(liveSec(b)));
    if (services.isEmpty) {
      widget.onOpenStop(code); // nothing live yet — let them pick in the stop
      return;
    }
    final bus = services.first;
    final stopName = DataStore.shared.stopName(code);
    // One tap arms the alert (3 & 1 min) with an Undo snackbar — no sheet.
    await toggleArrivalAlert(
      busNo: bus.no,
      stopCode: code,
      stopName: stopName,
      dest: bus.dest,
    );
  }

  /// Open the stop's location in the device's default maps app. Mirrors the
  /// iOS "Open on Map" action. Uses a geo: URI (label = stop name), falling
  /// back to a Google Maps web search if no maps app handles geo:.
  Future<void> _openOnMaps(NearbyStop stop) async {
    final s = DataStore.shared.stopByCode[stop.stopCode];
    final name = stop.stopName.isEmpty ? stop.stopCode : stop.stopName;
    if (s != null) {
      final geo = Uri.parse(
        'geo:${s.latitude},${s.longitude}'
        '?q=${s.latitude},${s.longitude}(${Uri.encodeComponent(name)})',
      );
      if (await launchUrl(geo, mode: LaunchMode.externalApplication)) return;
    }
    final web = Uri.parse(
      'https://www.google.com/maps/search/?api=1'
      '&query=${Uri.encodeComponent(name)}',
    );
    await launchUrl(web, mode: LaunchMode.externalApplication);
  }

  /// Copy the stop code to the clipboard (iOS "Copy Stop Code").
  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    const duration = Duration(seconds: 2);
    final controller = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Stop code $code copied'),
        duration: duration,
        behavior: SnackBarBehavior.floating,
      ),
    );
    // Fallback dismiss for devices with animations disabled (Flutter's built-in
    // SnackBar auto-hide timer doesn't fire then).
    Future.delayed(duration, controller.close);
  }

  List<_Item> _buildItems({required List<NearbyStop> nearby}) {
    final items = <_Item>[];
    // Stops hidden via long-press "Hide from Nearby" are computed once from
    // the RAW DataStore list — see `_hiddenNearbyCount` — so the restore
    // footer can appear in either branch below (including when hiding
    // emptied the visible `nearby` list entirely).
    final hiddenCount = _hiddenNearbyCount();
    final nearestStations = _nearbyStations();

    // Weather hero sits above the greeting when a snapshot is available.
    if (WeatherStore.shared.snapshot != null) {
      items.add(_WeatherItem());
      items.add(_GapItem(8));
    }
    items.add(_HeaderItem(_headerCaption(nearby)));
    items.add(_GapItem(14));
    items.add(_SearchBarItem());

    // Anatomy-matched loading skeletons (spec item 6) — nothing loaded yet
    // (no nearby stops, no nearby stations, no saved stops to fall back to)
    // and the reference dataset is still loading. Never shown once ANY real
    // content is available, so a slow secondary feed can't re-trigger it.
    final loading =
        DataStore.shared.referenceState.state == LoadState.loading;
    if (loading &&
        nearby.isEmpty &&
        nearestStations.isEmpty &&
        AppModel.shared.pins.isEmpty) {
      items.add(_GapItem(16));
      items.add(_FilterChipsItem());
      items.add(_GapItem(10));
      items.add(_SkeletonItem(hero: true));
      for (var i = 1; i <= 3; i++) {
        items.add(_GapItem(10));
        // Mirrors WSHomeView.swift's `WSSkeletonCard(delaySeconds: i * 0.15)`.
        items.add(_SkeletonItem(delay: Duration(milliseconds: i * 150)));
      }
      return items;
    }

    items.add(_GapItem(16));
    items.add(_FilterChipsItem());

    if (nearby.isEmpty) {
      final pins = AppModel.shared.pins;
      if (pins.isNotEmpty) {
        // No nearby stops (location off / denied, or none in range) but the
        // user has saved stops — show those instead of a dead end, so the app
        // still answers "when's my bus?". The first saved stop is the hero
        // ("Your stop"); the rest follow. Mirrors iOS SoftHomeView.
        if (_filter != _HomeFilter.mrt) {
          items.add(_GapItem(16));
          items.add(
            _EyebrowItem(
              'Your stops',
              updated: _updatedLabel(
                [for (final p in pins) _savedStop(p.code)],
              ),
            ),
          );
          items.add(_GapItem(10));
          items.add(
            _NearbyCardItem(
              _savedStop(pins.first.code),
              highlight: true,
              badgeText: 'Your stop',
            ),
          );
          final rest = pins.skip(1).toList();
          if (rest.isNotEmpty) {
            items.add(_GapItem(16));
            items.add(_EyebrowItem('More saved'));
            items.add(_GapItem(10));
            for (var i = 0; i < rest.length; i++) {
              if (i > 0) items.add(_GapItem(10));
              items.add(
                _NearbyCardItem(_savedStop(rest[i].code), highlight: false),
              );
              if (i == 2 && rest.length > 3) {
                items.add(_GapItem(10));
                items.add(_NativeAdItem());
              }
            }
          }
          if (LocationService.shared.lastLocation == null) {
            items.add(_GapItem(10));
            items.add(_LocationNudgeItem());
          }
        }
      } else if (_filter != _HomeFilter.mrt) {
        items.add(_GapItem(8));
        items.add(_EmptyItem());
      }
      // MRT strip moves BELOW the bus-stop list (spec item 7, iOS order:
      // hero → stops → MRT) — including in this no-nearby-bus-stops branch.
      if (_filter != _HomeFilter.buses && nearestStations.isNotEmpty) {
        items.add(_GapItem(16));
        items.add(_EyebrowItem('MRT'));
        items.add(_GapItem(10));
        items.add(_MrtStripItem(nearestStations));
      }
      if (hiddenCount > 0) {
        items.add(_GapItem(10));
        items.add(_HiddenFooterItem(hiddenCount));
      }
      return items;
    }

    if (_filter != _HomeFilter.mrt) {
      // "Closest to you" — the single nearest stop. Carries the LIVE badge +
      // freshness meta (the first bus-stop section is where iOS puts them).
      items.add(_GapItem(16));
      items.add(
        _EyebrowItem('Closest to you', updated: _updatedLabel(nearby)),
      );
      items.add(_GapItem(10));
      items.add(_NearbyCardItem(nearby.first, highlight: true));

      // "Other nearby stops" — up to 11 more, with a "View all / Show
      // fewer" toggle past the first 3 (spec item 7).
      // The native ad card is injected after the 3rd VISIBLE stop so it
      // sits naturally mid-list rather than at the top or very bottom.
      // NativeAdCard renders nothing (zero-size) until loaded + consent
      // ready, so there is never a gap or placeholder when fill is pending.
      const nativeAdAfterIndex = 2;
      const collapsedCount = 3;
      final others = nearby.skip(1).take(11).toList();
      if (others.isNotEmpty) {
        items.add(_GapItem(16));
        items.add(_EyebrowItem('Other nearby stops'));
        items.add(_GapItem(10));
        final shown = (_stopsExpanded || others.length <= collapsedCount)
            ? others
            : others.take(collapsedCount).toList();
        for (var i = 0; i < shown.length; i++) {
          if (i > 0) items.add(_GapItem(10));
          items.add(_NearbyCardItem(shown[i], highlight: false));
          if (i == nativeAdAfterIndex &&
              shown.length > nativeAdAfterIndex + 1) {
            items.add(_GapItem(10));
            items.add(_NativeAdItem());
          }
        }
        if (others.length > collapsedCount) {
          items.add(_GapItem(10));
          items.add(
            _ViewAllItem(expanded: _stopsExpanded, total: others.length),
          );
        }
      }
    }

    // MRT — nearby stations strip. Moved below the bus-stop section (spec
    // item 7, iOS order: hero → stops → MRT); previously sat directly under
    // the search bar. Independent of whether there are nearby BUS stops
    // (only needs a location fix and at least one station in range).
    if (_filter != _HomeFilter.buses && nearestStations.isNotEmpty) {
      items.add(_GapItem(16));
      items.add(_EyebrowItem('MRT'));
      items.add(_GapItem(10));
      items.add(_MrtStripItem(nearestStations));
    }

    if (hiddenCount > 0) {
      items.add(_GapItem(10));
      items.add(_HiddenFooterItem(hiddenCount));
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
        child: ListenableBuilder(
          listenable: Listenable.merge([
            DataStore.shared,
            LocationService.shared,
            WeatherStore.shared,
          ]),
          builder: (context, _) {
            final pins = AppModel.shared.pins;
            final nearby = _nearbyStops();

            final items = _buildItems(nearby: nearby);

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
      _WeatherItem() => const WeatherHeader(),
      _HeaderItem(:final caption) => _header(context, caption),
      _SearchBarItem() => _searchBar(context),
      _GapItem(:final height) => SizedBox(height: height),
      _EyebrowItem(:final label, :final updated) =>
        updated == null ? Eyebrow(label) : _sectionHeaderRow(context, label, updated),
      _FilterChipsItem() => _filterChips(context),
      _SkeletonItem(:final hero, :final delay) =>
        _HomeSkeletonCard(hero: hero, delay: delay),
      _ViewAllItem(:final expanded, :final total) => _viewAllRow(
        context,
        expanded: expanded,
        total: total,
      ),
      _NearbyCardItem(:final stop, :final highlight, :final badgeText) =>
        RepaintBoundary(
          child: highlight
              ? _NearbyHero(
                  stop: stop,
                  badgeText: badgeText,
                  onTap: () => widget.onOpenStop(stop.stopCode),
                  onLongPress: () => _showStopPeek(context, stop),
                )
              // Quiet row (spec item 7, mirrors WSHomeView.swift's
              // SoftStopRow): bus glyph tile · name · code·distance · ONE
              // segmented soonest pill · chevron — replaces the old
              // route-chips + crowd "when" column for every non-hero row.
              : _QuietStopRow(
                  stop: stop,
                  onTap: () => widget.onOpenStop(stop.stopCode),
                  onLongPress: () => _showStopPeek(context, stop),
                ),
        ),
      _HiddenFooterItem(:final count) => _hiddenFooter(context, count),
      _MrtStripItem(:final stations) => _MrtStrip(
        stations: stations,
        onOpen: (entry) => _openMrtStation(
          context,
          entry.station,
          distanceM: entry.distanceM,
          walkMin: entry.walkMin,
        ),
      ),
      _NativeAdItem() => const NativeAdCard(),
      _LocationNudgeItem() => _locationNudge(context),
      // When the stop directory itself failed to load (LTA flake at launch),
      // "No stops yet · turn on location" is the wrong story — location is
      // fine, the data isn't. Show the honest card with a retry instead
      // (mirrors WSHomeView's referenceState-error empty state).
      _EmptyItem()
          when DataStore.shared.referenceState.state == LoadState.error =>
        _ReferenceRetryCard(onRetry: () => DataStore.shared.bootstrap()),
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

  /// Header (spec item 3a, 2026-07-25): NO greeting line and NO "Buses near
  /// `<road>`" title — just the big heavy "Nearby" title and one caption
  /// line underneath ("`<area> · updated <when>`"). Supersedes the previous
  /// date-eyebrow-above-title layout. Android has no map, so — unlike iOS's
  /// header row, which also carries a map icon button — there's nothing to
  /// add here; the search entry point stays the separate pill below (spec:
  /// "do not touch anything below the header").
  Widget _header(BuildContext context, String caption) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Nearby',
          style: SoftBlue.sans(23, weight: FontWeight.w800, color: SoftBlue.ink),
        ),
        const SizedBox(height: 3),
        Text(
          caption,
          style: SoftBlue.sans(12.5, weight: FontWeight.w500, color: SoftBlue.sub),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  /// Tap-to-search pill — Material take on WSHomeView.swift's `searchBar`:
  /// same copy, same placement directly under the title (before the MRT
  /// strip / bus list), same hairline-bordered pill shape. Whole row taps
  /// through to the real search screen; no inline TextField here, matching
  /// iOS's plain `Button`.
  Widget _searchBar(BuildContext context) {
    final t = context.t;
    return Semantics(
      button: true,
      label: 'Search for a stop, bus, MRT station or postal code',
      child: Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(LyneRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(LyneRadius.md),
          onTap: widget.onOpenSearch,
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 15),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(LyneRadius.md),
              boxShadow: SoftBlue.cardShadow,
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 19, color: t.dim),
                const SizedBox(width: 11),
                Text(
                  'Stop, bus, MRT or postal code',
                  style: t.sans(15, weight: FontWeight.w600, color: t.dim),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// All/Buses/MRT filter chips (spec item 7) — sits between the hero and
  /// the stop list, gating which sections below render. Mirrors
  /// WSHomeView.swift's `softChips`/`SortChipRow` idiom already used
  /// elsewhere in this design language.
  Widget _filterChips(BuildContext context) {
    return SortChipRow<_HomeFilter>(
      selection: _filter,
      options: const [
        (value: _HomeFilter.all, label: 'All'),
        (value: _HomeFilter.buses, label: 'Buses'),
        (value: _HomeFilter.mrt, label: 'MRT'),
      ],
      onSelect: (f) => setState(() => _filter = f),
    );
  }

  /// "View all N / Show fewer" toggle at the foot of "Other nearby stops"
  /// past the first 3 rows (spec item 7).
  Widget _viewAllRow(BuildContext context, {required bool expanded, required int total}) {
    final t = context.t;
    return Semantics(
      button: true,
      label: expanded ? 'Show fewer stops' : 'View all $total stops',
      child: InkWell(
        borderRadius: BorderRadius.circular(LyneRadius.md),
        onTap: () => setState(() => _stopsExpanded = !_stopsExpanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              Text(
                expanded ? 'Show fewer' : 'View all',
                style: t.sans(13, weight: FontWeight.w600, color: t.accent),
              ),
              const SizedBox(width: 4),
              Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: t.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Section-header row for the first bus-stop section: eyebrow label +
  /// ● LIVE badge, freshness meta right-aligned. This is where iOS keeps the
  /// live/updated info (WSSectionHeader on "Bus stops") — the old standalone
  /// live row under the search bar read as a floating orphan next to it
  /// (owner-flagged mismatch). Badge follows this platform's established
  /// convention (soft_mrt_station_screen.dart): dot + mono "LIVE", both t.soon.
  Widget _sectionHeaderRow(BuildContext context, String label, String updated) {
    final t = context.t;
    return Row(
      children: [
        Eyebrow(label),
        const SizedBox(width: 8),
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: t.soon, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        // 11 not 9.5: legibility floor (owner directive — Android type must
        // never go below 11, even where iOS's WSLiveBadge word is smaller).
        Text(
          'LIVE',
          style: t
              .mono(11, weight: FontWeight.w700, color: t.soon)
              .copyWith(letterSpacing: 0.8),
        ),
        const Spacer(),
        // Newest of the visible stops' last refresh — mirrors iOS's
        // right-aligned `WSFmt.upd(...)` section-header meta.
        Text(
          'UPDATED $updated',
          style: t
              .mono(11, weight: FontWeight.w500, color: t.faint)
              .copyWith(letterSpacing: 0.8),
        ),
      ],
    );
  }

  /// A quiet prompt under the saved list to turn on location for nearby stops.
  Widget _locationNudge(BuildContext context) {
    final t = context.t;
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(LyneRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(LyneRadius.md),
        onTap: () async {
          await LocationService.shared.requestAndStart();
          final loc = LocationService.shared.lastLocation;
          if (loc != null) {
            DataStore.shared.updateNearby(loc.lat, loc.lon);
            DataStore.shared.prefetchNearbyArrivals();
          }
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LyneRadius.md),
            border: Border.all(color: t.line, width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.location_on_rounded,
                size: 14,
                color: LyneSignal.meBlue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Turn on location for stops near you',
                  style: t.sans(
                    13,
                    weight: FontWeight.w500,
                    color: LyneSignal.meBlue,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Quiet restore row for stops hidden via long-press "Hide from Nearby" —
  /// without this, a hidden stop is gone for good (there is no standalone
  /// "Me" tab). Mirrors WSHomeView.swift's busList footer.
  Widget _hiddenFooter(BuildContext context, int count) {
    final t = context.t;
    return InkWell(
      borderRadius: BorderRadius.circular(LyneRadius.md),
      onTap: _unhideAllNearby,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Text(
          '$count ${count == 1 ? 'stop' : 'stops'} hidden · Show',
          style: t
              .mono(11, weight: FontWeight.w500, color: t.dim)
              .copyWith(letterSpacing: 0.4),
        ),
      ),
    );
  }
}

// ─── Loading skeletons (spec item 6) ────────────────────────────────────────

/// Anatomy-matched loading skeleton — a hero-shaped card (mirrors
/// [SoftHeroCard]'s eyebrow/title/ring layout) or a row-shaped card (the
/// shared [SoftSkeletonCard] primitive), shown while nothing has loaded yet.
/// Mirrors WSHomeView.swift's `WSSkeletonCard`: same dimensions as the real
/// content so the swap doesn't shift anything below it.
class _HomeSkeletonCard extends StatefulWidget {
  const _HomeSkeletonCard({this.hero = false, this.delay = Duration.zero});
  final bool hero;

  /// Stagger offset before this card starts breathing (spec item 6: "hero-
  /// shaped + 3 row-shaped, staggered breathing").
  final Duration delay;

  @override
  State<_HomeSkeletonCard> createState() => _HomeSkeletonCardState();
}

class _HomeSkeletonCardState extends State<_HomeSkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: SoftBlueMotion.pulse,
  );

  /// Gates this card's entrance until its stagger [widget.delay] elapses —
  /// the "staggered" half of spec item 6's "hero-shaped + 3 row-shaped,
  /// staggered breathing" (each card's own pulse starts once it's visible).
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (!mounted) return;
      setState(() => _visible = true);
      _c.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.hero) {
      // Row skeletons use the shared white-card primitive as-is (its own
      // internal pulse); the stagger comes from this card's own entrance
      // fading in only once its delay has elapsed.
      return AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: SoftBlueMotion.standard,
        curve: Curves.easeOut,
        child: const SoftSkeletonCard(),
      );
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final dimA = 0.18 + 0.06 * _c.value;
        final baseA = 0.24 + 0.08 * _c.value;
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: SoftBlue.heroGradient,
            borderRadius: BorderRadius.circular(SoftBlue.heroRadius),
            boxShadow: SoftBlue.heroShadow,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _bar(170, 12, baseA),
                    const SizedBox(height: 8),
                    _bar(120, 10, dimA),
                    const SizedBox(height: 14),
                    _bar(150, 18, baseA),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: dimA),
                    width: 7,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// A hero-tinted skeleton bar — white@dim% on the gradient rather than
  /// [SoftSkeletonBar]'s ink@% (that primitive is tuned for white cards).
  Widget _bar(double w, double h, double alpha) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: alpha),
        borderRadius: BorderRadius.circular(h / 2),
      ),
    );
  }
}

// ─── Quiet stop row (spec item 7) ───────────────────────────────────────────

/// White-card stop row: bus glyph tile · name · "code · distance" · ONE
/// segmented soonest pill (fixed widths so the number/time boundary aligns
/// down the list) · chevron. Mirrors WSHomeView.swift's `SoftStopRow`
/// exactly — replaces the old route-chips + crowd "when" column for every
/// non-hero row in "Other nearby stops" (the closest/hero row keeps its own
/// gradient [SoftHeroCard] treatment, unchanged).
class _QuietStopRow extends StatelessWidget {
  const _QuietStopRow({
    required this.stop,
    required this.onTap,
    this.onLongPress,
  });

  final NearbyStop stop;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final name = stop.stopName.isEmpty ? stop.stopCode : stop.stopName;
    return Semantics(
      button: true,
      label: 'Open $name',
      child: Material(
        color: SoftBlue.card,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: ListenableBuilder(
            listenable: AppModel.shared,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: SoftBlue.chipBg,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      Icons.directions_bus_rounded,
                      size: 17,
                      color: SoftBlue.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          style: SoftBlue.sans(
                            14.5,
                            weight: FontWeight.w600,
                            color: SoftBlue.ink,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          stop.distanceM > 0
                              ? '${stop.stopCode} · ${fmtDistance(stop.distanceM)}'
                              : stop.stopCode,
                          style: SoftBlue.mono(11.5, color: SoftBlue.sub),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _soonestPill(),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: SoftBlue.sub,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _soonestPill() {
    final now = DateTime.now();
    final sorted = _NearbyCard._sortedServices(stop.stopCode, now);
    if (sorted.isEmpty) return const SizedBox.shrink();
    final soonest = sorted.first;
    final etaBig = fmtEta(_NearbyCard._liveSec(soonest, now)).big;
    return SoftBusTimePill(no: soonest.no, etaBig: etaBig, noWidth: 44, timeWidth: 52);
  }
}

// ─── Nearby stop card ────────────────────────────────────────────────────────

/// A compact nearby-stop card matching iOS SoftNearbyStopCard:
/// "Closest stop" badge (closest only) + pin tile · name · "Stop {code} · road"
/// + a single merged meta line (walk time + soonest arrival with "~" whisper)
/// + trailing chevron. No inline arrivals list, no divider, no footer. Whole
/// card taps to open the full stop view.
/// The closest stop is highlighted with a green border + "Closest stop" badge.
class _NearbyCard extends StatelessWidget {
  const _NearbyCard({
    required this.stop,
    required this.highlight,
    required this.onTap,
    this.onLongPress,
    this.badgeText = 'Closest stop',
  });

  final NearbyStop stop;
  final bool highlight;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String badgeText;

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
                // Wrap identity in per-second tick so the soonest-arrival
                // meta line updates without rebuilding the whole list.
                ListenableBuilder(
                  listenable: AppModel.shared,
                  builder: (context, _) => _identityRow(context, t),
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
        badgeText,
        style: t.sans(11, weight: FontWeight.w700, color: t.contrastFg),
      ),
    );
  }

  /// Identity row: (name + subtitle + compact meta) · chevron. No leading
  /// icon tile — matches iOS SoftNearbyStopCard/StopRow, which shows only
  /// the header row (no per-service arrivals list, no divider, no footer,
  /// no pin glyph).
  Widget _identityRow(BuildContext context, LyneTheme t) {
    final code = stop.stopCode;
    final name = stop.stopName.isEmpty ? code : stop.stopName;
    final road = DataStore.shared.roadName(code);
    // "Stop {code} · {road} · {distance}" — distance appended when known
    // (nearby fixes only; a saved-stop fallback card has distanceM == 0).
    // Mirrors WSHomeView.swift's StopRow.subline.
    final subtitle = [
      'Stop $code',
      if (road.isNotEmpty) road,
      if (stop.distanceM > 0) fmtDistance(stop.distanceM),
    ].join(' · ');

    // Route-number chips — DataStore.servicesAtStop first (route-table
    // derived, stable even before live arrivals load), falling back to the
    // service numbers already carried by `stop`. Mirrors WSHomeView.swift's
    // StopRow.tiles.
    final routesAtStop = DataStore.shared.servicesAtStop(code);
    final tiles = routesAtStop.isNotEmpty
        ? routesAtStop
        : DataStore.shared.servicesFor(code).map((s) => s.no).toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // No leading pin tile (iOS parity — WSHomeView.swift's StopRow has
        // none). It was decorative (same glyph on every card, zero
        // information) and, at 46+12dp, the single biggest width thief
        // pushing stop names into ellipsis (owner-reported 2026-07-03:
        // "Farrer Rd St…", "Empress Rd…").
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                // 17/w600 → 15.5/w700: matches WSHomeView.swift's StopRow
                // title (ws.sans(15.5, .bold)) — was reading larger than iOS.
                style: t.sans(15.5, weight: FontWeight.w700, color: t.fg),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                // 12.5 → 11.5/w500: matches WSHomeView.swift's StopRow
                // subline (ws.mono(11.5, .medium)).
                style: t.mono(11.5, weight: FontWeight.w500, color: t.dim),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (tiles.isNotEmpty) ...[
                const SizedBox(height: 8),
                _RouteChipsRow(services: tiles),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        // Trailing when-column (iOS parity): soonest arrival BIG, the bus +
        // crowd quiet underneath — replaces the old bottom meta line.
        // Width-capped so the quiet line can never crush the title column —
        // uncapped, "Bus 93 · Seats available" squeezed titles to ~6 chars
        // and stacked the route chips vertically (owner-reported). Lowered
        // 150→130 2026-07-03 alongside dropping CrowdMeter's glyphs here
        // (see _whenColumn): word-only quiet lines only need ~85–125dp, so
        // 130 is now a tight backstop for pathological input (a 4-char
        // service number + "Standing") rather than the effective width —
        // this guarantees the title Expanded below always keeps its share.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 130),
          child: _whenColumn(t, code),
        ),
        const SizedBox(width: 6),
        Icon(Icons.chevron_right_rounded, size: 18, color: t.faint),
      ],
    );
  }

  /// Trailing "when" column — mirrors WSHomeView.swift's `whenColumn`: the
  /// soonest arrival BIG on top, the bus number + crowd (or the multi-
  /// arriving names) quiet underneath. Walk time isn't repeated here — the
  /// subline already carries the distance (iOS parity).
  Widget _whenColumn(LyneTheme t, String code) {
    final now = DateTime.now();
    final sorted = _sortedServices(code, now);
    final soonest = sorted.isEmpty ? null : sorted.first;
    if (soonest == null) {
      return Text(
        '—',
        style: t.mono(19, weight: FontWeight.w700, color: t.dim),
      );
    }

    // Everything inside the "Arr" window (< 60s live), soonest first — since
    // `sorted` is already ascending by live ETA, these are its leading run.
    final arriving = sorted.where((s) => _liveSec(s, now) < 60).toList();
    if (arriving.length >= 2) {
      // Several buses at once: name them all instead of silently showing one.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'Arr',
            style: t.mono(19, weight: FontWeight.w700, color: t.fg),
          ),
          const SizedBox(height: 3),
          Text(
            _arrivingLabel(arriving),
            // 10 → 11: legibility floor (iOS's own value here is 10).
            style: t.mono(11, color: t.dim),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }

    final eta = fmtEta(_liveSec(soonest, now));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: eta.big,
                style: t.mono(19, weight: FontWeight.w700, color: t.fg),
              ),
              if (eta.big != 'Arr')
                TextSpan(
                  text: ' min',
                  style: t.mono(11, weight: FontWeight.w600, color: t.dim),
                ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 10 → 11: legibility floor (iOS's own value here is 10).
            Text('Bus ${soonest.no} ·', style: t.mono(11, color: t.dim)),
            const SizedBox(width: 5),
            // Compact word (iOS wsWord parity: Seats/Standing/Limited), no
            // glyphs — the three person icons alone cost ~42dp and, inside
            // this already width-capped column, were the biggest single
            // contributor to crushing the stop-name title down to ~105dp
            // (owner-reported 2026-07-03). The word carries the crowd level
            // on its own in this compact context. Flexible so the
            // width-capped column ellipsizes the word rather than
            // overflowing. Safe here: the host ConstrainedBox bounds us.
            Flexible(
              child: CrowdMeter(
                load: soonest.load,
                compact: true,
                showGlyphs: false,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// "Bus 174 & 165" (+N when more than two are arriving together) — sits
  /// under the big "Arr", so no "arriving" suffix needed (iOS parity).
  static String _arrivingLabel(List<Service> arriving) {
    final nos = arriving.map((s) => s.no).toList();
    final shown = nos.take(2).join(' & ');
    final extra = nos.length - 2;
    return extra > 0 ? 'Bus $shown +$extra' : 'Bus $shown';
  }

  /// Live seconds for a service — recomputes from arrivalDate for smooth ticking.
  static int _liveSec(Service s, DateTime now) {
    if (s.arrivalDate != null) {
      return s.arrivalDate!.difference(now).inSeconds.clamp(0, 1 << 30);
    }
    return s.etaSec;
  }

  /// Services at [code] sorted ascending by live ETA — the single source of
  /// "soonest"/"next" truth shared by `_whenColumn` (the non-hero card) and
  /// `_NearbyHero` (the gradient hero), so the two never drift apart.
  static List<Service> _sortedServices(String code, DateTime now) {
    final services = DataStore.shared.servicesFor(code);
    return [...services]
      ..sort((a, b) => _liveSec(a, now).compareTo(_liveSec(b, now)));
  }
}

/// The ONE gradient hero for Home (spec §4: Nearby's hero IS "closest stop +
/// soonest bus + countdown ring"). Renders a `SoftHeroCard` for the
/// highlighted "Closest to you" / "Your stop" slot whenever the stop has a
/// live soonest service; falls back to the plain bordered `_NearbyCard` when
/// nothing is live yet — never fabricate a hero to fill the slot (spec §4).
class _NearbyHero extends StatelessWidget {
  const _NearbyHero({
    required this.stop,
    required this.onTap,
    this.onLongPress,
    this.badgeText = 'Closest stop',
  });

  final NearbyStop stop;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String badgeText;

  @override
  Widget build(BuildContext context) {
    // Per-second tick (AppModel drives the app-wide ETA clock) so the hero's
    // countdown ring/numeral update without rebuilding the whole list —
    // mirrors `_NearbyCard`'s identity-row ListenableBuilder.
    return ListenableBuilder(
      listenable: AppModel.shared,
      builder: (context, _) {
        final code = stop.stopCode;
        final now = DateTime.now();
        final sorted = _NearbyCard._sortedServices(code, now);

        if (sorted.isEmpty) {
          // Nothing live yet at the closest stop — keep the old bordered
          // card rather than fabricating a hero (spec §4).
          return _NearbyCard(
            stop: stop,
            highlight: true,
            badgeText: badgeText,
            onTap: onTap,
            onLongPress: onLongPress,
          );
        }

        final soonest = sorted.first;
        final name = stop.stopName.isEmpty ? code : stop.stopName;
        final eyebrow = badgeText == 'Your stop'
            ? 'YOUR STOP · $name'
            : 'CLOSEST · $name';
        final title = soonest.dest.isEmpty
            ? 'Bus ${soonest.no}'
            : 'Bus ${soonest.no} → ${soonest.dest}';
        final etaSeconds = _NearbyCard._liveSec(soonest, now);

        // Later buses as segmented pills (spec item 2) — number and minutes
        // stay visually distinct instead of the old run-on string.
        final thenServices = <({String no, String etaBig})>[
          for (final next in sorted.skip(1).take(2))
            (
              no: next.no,
              etaBig: () {
                final sec = _NearbyCard._liveSec(next, now);
                if (sec <= 60) return 'Arr';
                return '${(sec / 60).ceil().clamp(0, 999)}';
              }(),
            ),
        ];

        final hero = SoftHeroCard(
          eyebrow: eyebrow,
          title: title,
          etaSeconds: etaSeconds,
          thenServices: thenServices,
          ctaLabel: 'Open stop',
          onCta: onTap,
          onTap: onTap,
          // Spec item 3c-v: walk time (minutes, not metres) under "Arr".
          walkMin: stop.walkMin,
        );

        return Semantics(
          button: true,
          label: 'Open $name',
          child: onLongPress == null
              ? hero
              : GestureDetector(onLongPress: onLongPress, child: hero),
        );
      },
    );
  }
}

/// Compact route-number chip row under a nearby card's subtitle — up to 3
/// service numbers plus a "+N" overflow chip. Mirrors WSHomeView.swift's
/// TileRow/RouteTile/OverflowTile (neutral tiles, not accent-filled — the
/// card can list several services without turning into a wall of colour).
class _RouteChipsRow extends StatelessWidget {
  const _RouteChipsRow({required this.services});

  final List<String> services;
  static const int _cap = 3;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final shown = services.take(_cap).toList();
    final extra = services.length - shown.length;
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (final svc in shown) _tile(t, svc),
        if (extra > 0) _overflowTile(t, extra),
      ],
    );
  }

  // NOTE: no `alignment:` on these Containers — a Container with alignment
  // set and no explicit width EXPANDS to the incoming max width, which made
  // every chip fill the card and stack vertically (owner-reported). Wrapping
  // in IntrinsicWidth keeps the pill hugging its label while minWidth still
  // centres short codes.
  Widget _tile(LyneTheme t, String text) => IntrinsicWidth(
    child: Container(
      constraints: const BoxConstraints(minWidth: 26, minHeight: 21),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.surfaceHi,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.line, width: 1),
      ),
      child: Text(
        text,
        style: t.mono(11, weight: FontWeight.w700, color: t.fg),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );

  Widget _overflowTile(LyneTheme t, int count) => IntrinsicWidth(
    child: Container(
      constraints: const BoxConstraints(minWidth: 26, minHeight: 21),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.faint, width: 1),
      ),
      child: Text(
        // 10 → 11: matches WSHomeView.swift's OverflowTile (ws.mono(11, .bold))
        // and clears the 11pt legibility floor.
        '+$count',
        style: t.mono(11, weight: FontWeight.w700, color: t.dim),
        maxLines: 1,
      ),
    ),
  );
}

// ─── MRT — nearby stations strip ────────────────────────────────────────────

/// Horizontal strip of the nearest MRT/LRT stations — its own small section,
/// always visible above the bus stop list when located (no filter to find
/// it). Mirrors WSHomeView.swift's `mrtSection` / `MrtCard`: line-code pills
/// in official colours, live crowd if already cached, name, distance/walk.
class _MrtStrip extends StatelessWidget {
  const _MrtStrip({required this.stations, required this.onOpen});

  final List<MrtNearestResult> stations;
  final ValueChanged<MrtNearestResult> onOpen;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < stations.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            _MrtStationCard(
              entry: stations[i],
              onTap: () => onOpen(stations[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _MrtStationCard extends StatelessWidget {
  const _MrtStationCard({required this.entry, required this.onTap});

  final MrtNearestResult entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final station = entry.station;
    final crowd = _crowdFor(station);

    return Semantics(
      button: true,
      label:
          'Open ${station.name} MRT station, ${entry.walkMin} min walk'
          '${crowd == null ? '' : ', crowd ${_crowdWord(crowd.level)}'}',
      child: Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(LyneRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(LyneRadius.md),
          onTap: onTap,
          onLongPress: () => _showMrtStationMenu(context, station),
          child: Container(
            width: 172,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(LyneRadius.md),
              border: Border.all(color: t.line, width: 1),
            ),
            // Fixed 3-row layout — crowd lives INLINE on the chip row (like
            // iOS MrtCard) so a card with a reading is the same height as
            // one without; a conditional fourth row made strip cards uneven
            // (owner-reported).
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    ...station.codes.take(2).map((code) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: lineColorFor(code),
                            borderRadius: BorderRadius.circular(
                              LyneRadius.full,
                            ),
                          ),
                          child: Text(
                            code,
                            // 9.5 → 11: legibility floor (also closer to
                            // WSHomeView.swift's LineBullet at ws.mono(12)).
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                    }),
                    const Spacer(),
                    if (crowd != null) ...[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _crowdColor(crowd.level, t),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _crowdWord(crowd.level),
                          // 10 → 11: legibility floor.
                          style: t.sans(
                            11,
                            weight: FontWeight.w500,
                            color: t.dim,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  station.name,
                  // 14 → 15: matches WSHomeView.swift's MrtCard name
                  // (ws.sans(15, .bold)).
                  style: t.sans(15, weight: FontWeight.w700, color: t.fg),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${fmtDistance(entry.distanceM)} · ${entry.walkMin} min walk',
                  // 10.5 → 11: legibility floor (iOS's own value here is
                  // 10.5 — ws.mono(10.5)).
                  style: t.mono(11, color: t.dim),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Long-press quick action on an MRT station card — a single "Save
/// station" / "Remove from Saved" row, toggling AppModel's saved-MRT list.
/// Mirrors WSHomeView.swift's MrtCard context menu (Android's equivalent of
/// the long-press "Hide from Nearby" sheet on bus stops).
void _showMrtStationMenu(BuildContext context, MrtGeoStation station) {
  final t = context.t;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: t.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetCtx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              station.name,
              style: t.sans(17, weight: FontWeight.w700, color: t.fg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            ListenableBuilder(
              listenable: AppModel.shared,
              builder: (context, _) {
                final saved = AppModel.shared.isMrtSaved(station);
                return InkWell(
                  onTap: () {
                    AppModel.shared.toggleMrtSaved(station);
                    Navigator.of(sheetCtx).pop();
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        // Icon convention audit: this is a STATION SAVE
                        // affordance, not a "favourite" toggle — iOS uses
                        // bookmark/bookmark.slash for save even inside a
                        // context menu (WSHomeView.swift MrtCard), reserving
                        // literal stars for the separate "favourite bus
                        // service" action (WSBusStopView.swift). Was
                        // Icons.star_rounded/star_outline_rounded (wrong
                        // glyph family); now matches the bookmark pair
                        // soft_mrt_station_screen.dart already uses for the
                        // same action.
                        Icon(
                          saved
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_outline_rounded,
                          size: 20,
                          color: t.fg,
                        ),
                        const SizedBox(width: 14),
                        Text(
                          saved ? 'Remove from Saved' : 'Save station',
                          style: t.sans(
                            15,
                            weight: FontWeight.w500,
                            color: t.fg,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// Best-effort MRTLine for a station's code prefix ("EW23" → ew). Mirrors
/// SoftMrtStationScreen._lineFromCode: CG→EW, CE→CC, LRT prefixes → null
/// (crowd isn't reported per-LRT-station).
MRTLine? _lineFromCode(String code) {
  if (code.length < 2) return null;
  switch (code.substring(0, 2).toUpperCase()) {
    case 'EW':
    case 'CG':
      return MRTLine.ew;
    case 'NS':
      return MRTLine.ns;
    case 'NE':
      return MRTLine.ne;
    case 'CC':
    case 'CE':
      return MRTLine.cc;
    case 'DT':
      return MRTLine.dt;
    case 'TE':
      return MRTLine.te;
    default:
      return null;
  }
}

/// Live crowd for a station, read from whatever DataStore has cached.
/// `_SoftHomeScreenState._warmMrtCrowd` actively kicks off a fetch for the
/// strip's stations on appear/location change (spec item 7, 2026-07-25 —
/// previously this strip only showed crowd "if available" from whatever the
/// MRT tab/station screen happened to already have fetched); this stays a
/// passive read so a slow feed never blocks the strip's own render, matching
/// the "timely, never a loud loading state" rule for a secondary strip.
StationCrowd? _crowdFor(MrtGeoStation station) {
  for (final code in station.codes) {
    final line = _lineFromCode(code);
    final list = line == null ? null : DataStore.shared.crowdByLine[line];
    if (list == null) continue;
    for (final c in list) {
      if (c.code.toUpperCase() == code.toUpperCase()) return c;
    }
  }
  return null;
}

/// Crowd dot colour — NEUTRAL ink (owner decision 2026-07-03, iOS WhereSia
/// rule: crowd is never colour-coded; the word carries the level).
Color _crowdColor(CrowdLevel level, LyneTheme t) {
  return level == CrowdLevel.unknown ? t.faint : t.fg;
}

String _crowdWord(CrowdLevel level) {
  switch (level) {
    case CrowdLevel.low:
      return 'Low';
    case CrowdLevel.moderate:
      return 'Moderate';
    case CrowdLevel.high:
      return 'High';
    case CrowdLevel.unknown:
      return 'Unknown';
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
              OutlinedButton(onPressed: onSearch, child: const Text('Search')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shown instead of [_EmptyState] when the LTA stop directory failed to load
/// — location is on and working, so "turn on location" would mislead. Quiet
/// copy per the timely-over-loud rule; resume also auto-retries.
class _ReferenceRetryCard extends StatelessWidget {
  const _ReferenceRetryCard({required this.onRetry});
  final VoidCallback onRetry;

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
            child: Icon(Icons.refresh_rounded, size: 28, color: t.accent),
          ),
          const SizedBox(height: 12),
          Text(
            'Stops aren’t loading right now',
            style: t.sans(20, weight: FontWeight.w600, color: t.fg),
          ),
          const SizedBox(height: 4),
          Text(
            'A retry usually fixes this.',
            style: t.sans(13, color: t.dim),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: t.accent,
              foregroundColor: t.onAccent,
            ),
            child: const Text('Retry'),
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
  const _StopPeekSheet({
    required this.stop,
    required this.onOpen,
    required this.onArrivalAlerts,
    required this.onOpenMaps,
    required this.onCopyCode,
    required this.onHide,
  });

  final NearbyStop stop;
  final VoidCallback onOpen;
  final VoidCallback onArrivalAlerts;
  final VoidCallback onOpenMaps;
  final VoidCallback onCopyCode;
  final VoidCallback onHide;

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
            // maxLines+ellipsis: a long road name shouldn't clip the sheet
            // layout mid-render (audit pass — this Text had neither before).
            Text(
              subtitle,
              style: t.mono(12.5, color: t.dim),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 14),
            // Live arrivals — AppModel.shared drives the 1-second ETA tick.
            ListenableBuilder(
              listenable: Listenable.merge([DataStore.shared, AppModel.shared]),
              builder: (context, _) => _arrivals(context, t, code),
            ),
            const SizedBox(height: 14),
            Divider(height: 1, thickness: 1, color: t.line),
            const SizedBox(height: 6),
            // Quick actions — the iOS context-menu set. Pin reflects live state,
            // so it lives inside a ListenableBuilder on AppModel.
            ListenableBuilder(
              listenable: AppModel.shared,
              builder: (context, _) {
                final pinned = AppModel.shared.isPinned(code);
                return Column(
                  children: [
                    // Icon convention audit: STOP SAVE affordance (not a
                    // "favourite" toggle) — iOS uses bookmark/bookmark.slash
                    // here too, even inside its context menu
                    // (WSHomeView.swift StopRow); stars are reserved for the
                    // separate "favourite bus service" action elsewhere. Was
                    // Icons.star_rounded/star_outline_rounded; now matches
                    // soft_stop_screen.dart's pin-toggle icon pair.
                    _actionRow(
                      t,
                      icon: pinned
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_outline_rounded,
                      label: pinned ? 'Remove from Saved' : 'Add to Saved',
                      onTap: () => AppModel.shared.togglePin(code),
                    ),
                    _actionRow(
                      t,
                      icon: Icons.visibility_outlined,
                      label: 'Arrival alerts',
                      onTap: onArrivalAlerts,
                    ),
                    _actionRow(
                      t,
                      icon: Icons.map_outlined,
                      label: 'Open on Maps',
                      onTap: onOpenMaps,
                    ),
                    _actionRow(
                      t,
                      icon: Icons.copy_rounded,
                      label: 'Copy stop code',
                      onTap: onCopyCode,
                    ),
                    _actionRow(
                      t,
                      icon: Icons.visibility_off_outlined,
                      label: 'Hide from Nearby',
                      onTap: onHide,
                      destructive: true,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
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

  /// One quick-action row: leading icon + label, full-width tap target.
  /// Destructive actions (Hide) read in the critical colour.
  Widget _actionRow(
    LyneTheme t, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final color = destructive ? t.crit : t.fg;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 14),
            Text(
              label,
              style: t.sans(15, weight: FontWeight.w500, color: color),
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
          Text('No live arrivals right now', style: t.mono(12, color: t.faint)),
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
    final eta = fmtEta(sec);
    final arriving = eta.big == 'Arr';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          // Badge keeps its standard look — proximity is not colour-coded.
          Container(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 32),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.accent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              s.no,
              // Bus service number is a NUMERAL set in the sans face — give
              // it tabular figures (theme.dart's new `sans(tabularFigures:)`
              // param) so stacked badges in this list don't jitter/misalign
              // digit widths against each other.
              style: t.sans(
                15,
                weight: FontWeight.w700,
                color: t.onAccent,
                tabularFigures: true,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
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
                style: t.mono(
                  17,
                  weight: FontWeight.w600,
                  color: etaColor(etaSec: sec, confidence: conf, t: t),
                ),
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
