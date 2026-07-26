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

import 'dart:async';

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
  _HeaderItem(this.caption, {required this.live});

  /// "`<area> · updated <when>`" (spec item 3a, 2026-07-25) — computed once
  /// in `_buildItems` where `nearby` is in scope.
  final String caption;

  /// True once any nearby stop has a real refresh timestamp behind it — the
  /// only condition under which the LIVE chip is allowed to claim liveness
  /// (iOS `hasLiveData`).
  final bool live;
}

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

/// Sentence-case section header (16 bold ink, 4pt inset) with an optional
/// trailing text action on the SAME row — mirrors iOS's `SoftSectionHead`
/// ("Nearby stops · View all"). Replaces the old UPPERCASE mono `Eyebrow`
/// and the separate "View all" row underneath it.
class _SectionHeadItem extends _Item {
  _SectionHeadItem(this.label, {this.action});

  final String label;

  /// "View all" / "Show fewer" — only set when there's something to toggle.
  final String? action;
}

/// The ONE gradient hero — the closest stop (or, in the saved-pins fallback,
/// the first saved stop). Every other stop now lives in [_StopsCardItem].
class _NearbyCardItem extends _Item {
  _NearbyCardItem(this.stop, {this.badgeText = 'Closest stop'});
  final NearbyStop stop;
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

/// The nearby stop rows as ONE white card (radius 20, the one shadow recipe)
/// with hairline dividers between them — iOS renders the whole list as a
/// single surface, not a stack of per-row cards with gaps.
class _StopsCardItem extends _Item {
  _StopsCardItem(this.stops);
  final List<NearbyStop> stops;
}

class _EmptyItem extends _Item {}

/// "Location is off" — the FIRST branch of the screen, taken before any list
/// logic runs (iOS `locationOffState`).
class _LocationOffItem extends _Item {}

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

  /// Keeps the Nearby board from going stale while the user just sits there
  /// (iOS re-runs `prefetchNearbyArrivals()` on every 1-second tick). Without
  /// it the board only refetched on init / resume / location change / pull, so
  /// standing still froze every ETA on screen. `ensureArrivals`'
  /// [LtaConfig.arrivalRefresh] freshness window absorbs the extra calls, so
  /// this ticks at 5s and turns into a real fetch roughly every 25s — the
  /// same cadence iOS lands on. A Timer rather than a second listener on
  /// AppModel's per-second tick: the screen already rebuilds on that tick for
  /// the countdowns, and firing a 12-stop prefetch loop every second just to
  /// have it no-op is work for nothing.
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LocationService.shared.addListener(_onLocationChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _warm();
      await LocationService.shared.startIfAuthorized();
      // Onboarding (and its location primer) was removed 2026-07-26, so this
      // is now the app's only first-run location request: Nearby is the screen
      // that needs the permission, and it asks the first time it appears.
      // Mirrors the iOS WSHomeView change made in the same pass.
      //
      // Gated on OUR OWN "have we asked" flag, not on `LocAuth`: Android's
      // Geolocator reports a never-asked permission as `denied`, identical to
      // a refusal, so there is no platform state to test here. Prompting on
      // `denied` instead would re-raise the dialog on every single Home mount
      // for anyone who said no. See AppModel.locationAsked.
      if (!AppModel.shared.locationAsked && !LocationService.shared.authorized) {
        AppModel.shared.markLocationAsked();
        await _requestLocation();
      }
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
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => DataStore.shared.prefetchNearbyArrivals(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
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


  /// Relative freshness for the header caption (spec item 3a): "just now"
  /// (<5s), "Ns ago" (<60s), else "Nm ago". This is now the screen's ONLY
  /// freshness tell — the "Closest to you" section header that used to repeat
  /// it as a LIVE badge + clock time is gone (iOS parity, owner 2026-07-25).
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
    // The freshness caption is the first list item now — the title and the
    // search action moved into the app bar (iOS deleted the in-content search
    // pill entirely, 2026-07-26).
    items.add(
      _HeaderItem(
        _headerCaption(nearby),
        live: _relativeUpdated(nearby) != null,
      ),
    );

    // NO LOCATION FIX — the first branch, before any list logic (iOS
    // `locationOffState`). Nothing below can answer "what's near me" without
    // a fix, so offering a filtered, skeleton-ed or empty list first would be
    // answering a question the app can't hear yet. The saved-pins fallback
    // below is an Android extra and keeps precedence: a user with saved stops
    // still gets live departures rather than a permission prompt.
    if (LocationService.shared.lastLocation == null &&
        AppModel.shared.pins.isEmpty) {
      items.add(_GapItem(16));
      items.add(_LocationOffItem());
      return items;
    }

    // Anatomy-matched loading skeletons (spec item 6) — nothing loaded yet
    // (no nearby stops, no nearby stations, no saved stops to fall back to)
    // and the reference dataset is still loading. Never shown once ANY real
    // content is available, so a slow secondary feed can't re-trigger it.
    // No filter chips while the skeletons are up: they'd be a live control
    // over content that doesn't exist yet.
    final loading =
        DataStore.shared.referenceState.state == LoadState.loading;
    if (loading &&
        nearby.isEmpty &&
        nearestStations.isEmpty &&
        AppModel.shared.pins.isEmpty) {
      items.add(_GapItem(16));
      items.add(_SkeletonItem(hero: true));
      for (var i = 1; i <= 3; i++) {
        items.add(_GapItem(10));
        // Mirrors WSHomeView.swift's `WSSkeletonCard(delaySeconds: i * 0.15)`.
        items.add(_SkeletonItem(delay: Duration(milliseconds: i * 150)));
      }
      return items;
    }

    // Section order mirrors iOS WSHomeView.softBody: caption → HERO → chips →
    // stops → MRT → hidden footer. The chips used to sit above the hero, which
    // put a control before the answer it filters; iOS moved them below so the
    // screen leads with the departure board (owner 2026-07-25).
    //
    // `_chips` is emitted OUTSIDE every `_filter` gate: with the MRT filter
    // active the bus sections don't render, and chips inside that gate would
    // disappear with them, stranding the user on a filter they can't undo.
    void addChips() {
      items.add(_GapItem(16));
      items.add(_FilterChipsItem());
    }

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
            _NearbyCardItem(
              _savedStop(pins.first.code),
              badgeText: 'Your stop',
            ),
          );
        }
        addChips();
        if (_filter != _HomeFilter.mrt) {
          final rest = pins.skip(1).toList();
          if (rest.isNotEmpty) {
            items.add(_GapItem(16));
            items.add(_SectionHeadItem('More saved'));
            items.add(_GapItem(10));
            // One card for the whole list, hairline-separated rows inside —
            // same surface treatment as the nearby list below.
            items.add(
              _StopsCardItem([
                for (final p in rest) _savedStop(p.code),
              ]),
            );
            if (rest.length > 3) {
              items.add(_GapItem(10));
              items.add(_NativeAdItem());
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
        items.add(_SectionHeadItem('MRT stations'));
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
      // The hero: the single nearest stop. NO eyebrow above it — the header
      // caption already carries "<area> · updated <when>", and a second
      // freshness badge right under it read as a floating duplicate (iOS
      // dropped both the label and the badge here, owner 2026-07-25).
      items.add(_GapItem(16));
      items.add(_NearbyCardItem(nearby.first));
    }

    addChips();

    if (_filter != _HomeFilter.mrt) {
      // "Nearby stops" — up to 11 more in ONE card, with the "View all /
      // Show fewer" toggle riding the section header rather than sitting as
      // its own row underneath (iOS `softStopsSection`).
      // The native ad card follows the card; NativeAdCard renders nothing
      // (zero-size) until loaded + consent ready, so there is never a gap or
      // placeholder when fill is pending.
      const collapsedCount = 3;
      final others = nearby.skip(1).take(11).toList();
      if (others.isNotEmpty) {
        items.add(_GapItem(16));
        items.add(
          _SectionHeadItem(
            'Nearby stops',
            action: others.length > collapsedCount
                ? (_stopsExpanded ? 'Show fewer' : 'View all')
                : null,
          ),
        );
        items.add(_GapItem(10));
        final shown = (_stopsExpanded || others.length <= collapsedCount)
            ? others
            : others.take(collapsedCount).toList();
        items.add(_StopsCardItem(shown));
        if (shown.length > collapsedCount - 1) {
          items.add(_GapItem(10));
          items.add(_NativeAdItem());
        }
      }
    }

    // MRT — nearby stations strip. Moved below the bus-stop section (spec
    // item 7, iOS order: hero → stops → MRT); previously sat directly under
    // the search bar. Independent of whether there are nearby BUS stops
    // (only needs a location fix and at least one station in range).
    if (_filter != _HomeFilter.buses && nearestStations.isNotEmpty) {
      items.add(_GapItem(16));
      items.add(_SectionHeadItem('MRT stations'));
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
      // Title + search live in a real app bar (iOS parity 2026-07-26: the
      // in-content search pill is gone and the title moved to the nav bar
      // with a trailing search action). A platform app bar gets Material's
      // own sizing, ripple and scroll behaviour, which a hand-built header
      // row and a fake pill never did.
      appBar: AppBar(
        backgroundColor: t.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 20,
        title: Text(
          'Nearby',
          style: SoftBlue.sans(20, weight: FontWeight.w800, color: SoftBlue.ink),
        ),
        actions: [
          IconButton(
            onPressed: widget.onOpenSearch,
            icon: const Icon(Icons.search_rounded),
            color: SoftBlue.ink,
            tooltip: 'Search stops, buses, stations',
          ),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: SoftBottomBar(
        selection: SoftTab.home,
        onSelect: widget.onTab,
      ),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([
            DataStore.shared,
            LocationService.shared,
            WeatherStore.shared,
            // The freshness caption counts UP ("updated 12s ago"), so it has
            // to rebuild every second — AppModel's 1-second tick is the
            // app-wide clock that drives it (and the row ETAs with it).
            AppModel.shared,
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
      _HeaderItem(:final caption, :final live) => _header(
        context,
        caption,
        live: live,
      ),
      _GapItem(:final height) => SizedBox(height: height),
      _SectionHeadItem(:final label, :final action) => SoftSectionHead(
        title: label,
        action: action,
        onAction: action == null
            ? null
            : () => setState(() => _stopsExpanded = !_stopsExpanded),
      ),
      _FilterChipsItem() => _filterChips(context),
      _SkeletonItem(:final hero, :final delay) =>
        _HomeSkeletonCard(hero: hero, delay: delay),
      _NearbyCardItem(:final stop, :final badgeText) =>
        RepaintBoundary(
          child: _NearbyHero(
            stop: stop,
            badgeText: badgeText,
            onTap: () => widget.onOpenStop(stop.stopCode),
            onLongPress: () => _showStopPeek(context, stop),
          ),
        ),
      // ONE white card for the whole run of rows, hairline-separated (iOS
      // `softStopsSection`) — not a stack of per-row cards with 10dp gaps.
      _StopsCardItem(:final stops) => RepaintBoundary(
        child: _stopsCard(context, stops),
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
      // Located, but nothing in range — a different fact from "location is
      // off", so it doesn't borrow that copy.
      _EmptyItem() => _EmptyState(
        locationOff: false,
        onNearby: _requestLocation,
        onSearch: widget.onOpenSearch,
      ),
      _LocationOffItem() => _EmptyState(
        locationOff: true,
        onNearby: _requestLocation,
        onSearch: widget.onOpenSearch,
      ),
    };
  }

  /// Asks for the location permission and, once granted, kicks the nearby
  /// list off immediately rather than waiting for the next fix callback.
  Future<void> _requestLocation() async {
    await LocationService.shared.requestAndStart();
    final loc = LocationService.shared.lastLocation;
    if (loc != null) {
      DataStore.shared.updateNearby(loc.lat, loc.lon);
      DataStore.shared.prefetchNearbyArrivals();
    }
  }

  /// The freshness line — all that's left of the old header now that the
  /// title and the search action live in the app bar (iOS `softCaptionRow`).
  ///
  /// The LIVE chip earns its place rather than decorating: with minute-
  /// resolution ETAs a stop can sit visually unchanged for a full minute, and
  /// the screen then reads as a printed sheet. The breathing dot is the only
  /// thing on Nearby that moves between refreshes, so it is what says the app
  /// is still working — and it is shown ONLY when there's a real refresh
  /// timestamp behind it, since claiming "LIVE" over absent data would be
  /// exactly the loud dishonesty this design avoids.
  Widget _header(BuildContext context, String caption, {required bool live}) {
    return Row(
      children: [
        if (live) ...[const _LiveChip(), const SizedBox(width: 8)],
        Flexible(
          child: Text(
            caption,
            style: SoftBlue.sans(12.5, weight: FontWeight.w500, color: SoftBlue.sub),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// The nearby stop rows as ONE white card — radius 20, the one shadow
  /// recipe, 1px hairline dividers inset 64 on the leading edge so they start
  /// where the row text does (iOS `softStopsSection`). Each row is a plain
  /// [_QuietStopRow]; the card owns the surface, so a row never draws its own.
  Widget _stopsCard(BuildContext context, List<NearbyStop> stops) {
    return Container(
      decoration: BoxDecoration(
        color: SoftBlue.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: SoftBlue.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < stops.length; i++) ...[
                if (i > 0)
                  Container(
                    height: 1,
                    margin: const EdgeInsets.only(left: 64),
                    color: SoftBlue.hairline,
                  ),
                _QuietStopRow(
                  stop: stops[i],
                  onTap: () => widget.onOpenStop(stops[i].stopCode),
                  onLongPress: () => _showStopPeek(context, stops[i]),
                ),
              ],
            ],
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
          // "SHOW" uppercase — it's the action word in an otherwise flat mono
          // line, and iOS sets it the same way (`hiddenFooter`).
          '$count ${count == 1 ? 'stop' : 'stops'} hidden · SHOW',
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
          // Anatomy of the CURRENT hero: title, metadata line, then a
          // three-row departure board. The old skeleton still drew a 64pt
          // countdown ring the hero hasn't had since the board replaced it,
          // so the placeholder promised a shape the real card never took.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _bar(170, 12, baseA),
              const SizedBox(height: 8),
              _bar(120, 10, dimA),
              const SizedBox(height: 16),
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _bar(double.infinity, i == 0 ? 16 : 12, i == 0 ? baseA : dimA),
              ],
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

/// Stop row: bus glyph tile · name · "code · distance" · ONE segmented
/// soonest pill (fixed widths so the number/time boundary aligns down the
/// list). Mirrors WSHomeView.swift's `SoftStopRow` exactly.
///
/// The row draws NO surface of its own — the enclosing card
/// (`_SoftHomeScreenState._stopsCard`) owns the white fill, radius and
/// shadow, and hairlines separate the rows inside it. There is no trailing
/// chevron either: the ETA pill is the row's answer, and a chevron next to it
/// only says "this is tappable", which every row on the screen already is.
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
        color: Colors.transparent,
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
                        // Same metadata format as the hero (ui-checklist §2) —
                        // never a bare 5-digit number, which is ambiguous next
                        // to bus numbers and MRT line codes. The row is
                        // narrower than the hero, so "away" is dropped; the
                        // field order already says what the metres are.
                        SoftStopCode(
                          stop.stopCode,
                          suffix: stop.distanceM > 0
                              ? '${stop.walkMin < 1 ? 1 : stop.walkMin} min walk · '
                                    '${fmtDistance(stop.distanceM)}'
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _soonestPill(),
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
    final sorted = _Arrivals.sorted(stop.stopCode, now);
    if (sorted.isEmpty) return const SizedBox.shrink();
    final soonest = sorted.first;
    final etaBig = fmtEta(_Arrivals.liveSec(soonest, now)).big;
    // 44/52 → 46/56: the pill lost its chevron, so it can take the width back
    // — and "Now"/"12 min" stop crowding their segments.
    return SoftBusTimePill(no: soonest.no, etaBig: etaBig, noWidth: 46, timeWidth: 56);
  }
}

// ─── Shared arrival helpers ──────────────────────────────────────────────────

/// The single source of "soonest"/"next" truth on this screen — shared by the
/// stop rows and the gradient hero so the two can never drift apart.
abstract final class _Arrivals {
  /// Live seconds for a service — recomputed from `arrivalDate` so the
  /// countdown ticks smoothly between feed refreshes.
  static int liveSec(Service s, DateTime now) {
    if (s.arrivalDate != null) {
      return s.arrivalDate!.difference(now).inSeconds.clamp(0, 1 << 30);
    }
    return s.etaSec;
  }

  /// Services at [code] sorted ascending by live ETA.
  static List<Service> sorted(String code, DateTime now) {
    final services = DataStore.shared.servicesFor(code);
    return [...services]
      ..sort((a, b) => liveSec(a, now).compareTo(liveSec(b, now)));
  }
}

/// The ONE gradient hero for Home: the closest stop named as the title, its
/// next three departures as a board underneath.
///
/// The hero NEVER changes shape (iOS parity 2026-07-26). With no live
/// arrivals Android used to swap in a completely different bordered card, so
/// the top of the screen redrew itself as a different object every time the
/// feed dipped — the loudest possible way to say "nothing right now".
/// [SoftBoardHeroCard] prints its `emptyLabel` inside the same gradient card
/// instead: same shape, honest sentence, no fabricated departures.
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
    // board counts down without rebuilding the whole list.
    return ListenableBuilder(
      listenable: AppModel.shared,
      builder: (context, _) {
        final code = stop.stopCode;
        final now = DateTime.now();
        final sorted = _Arrivals.sorted(code, now);
        final name = stop.stopName.isEmpty ? code : stop.stopName;

        // The board: next three DISTINCT services by live ETA. One service can
        // appear twice in the feed (this bus and the following one); the board
        // answers "which buses can I take", so the second sighting is noise
        // here. Mirrors iOS SoftHeroCard.board.
        final seen = <String>{};
        final board = <({String no, String dest, String etaBig})>[
          for (final s in sorted)
            if (seen.add(s.no))
              (
                no: s.no,
                dest: s.dest,
                etaBig: fmtEta(_Arrivals.liveSec(s, now)).big,
              ),
        ].take(3).toList();

        // Shared metadata format (ui-checklist §2): STOP CODE · MIN WALK ·
        // METRES AWAY. The code is what you match against the pole you're
        // standing at; the walk time is the decision; the metres are how you
        // pick between two stops the same walk time apart.
        final meta = stopCodeLabel(
          code,
          suffix: stop.distanceM > 0
              ? '${stop.walkMin < 1 ? 1 : stop.walkMin} min walk · '
                    '${fmtDistance(stop.distanceM)} away'
              : null,
        );

        return Semantics(
          button: true,
          label: 'Open $name',
          child: SoftBoardHeroCard(
            title: name,
            meta: meta,
            board: board,
            // On Nearby the first card is self-evidently the closest, so it
            // carries no label (iOS drops it too). The saved-stop fallback
            // branch is NOT the closest stop, so that one says so.
            decision: badgeText == 'Your stop' ? 'Saved stop' : null,
            ctaLabel: 'Open stop',
            // Same card, same shape, one honest sentence where the board
            // would be — never a different card (iOS `SoftHeroCard`).
            emptyLabel: 'No live arrivals right now',
            onTap: onTap,
            onLongPress: onLongPress,
          ),
        );
      },
    );
  }
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
    // 2-up GRID, not a horizontal carousel (iOS parity — WSHomeView's
    // `softMrtSection` is a 2-column LazyVGrid of 4 tiles). The carousel put
    // the 3rd and 4th stations off-screen behind a sideways swipe nobody
    // performs; users scan top-to-bottom, so all four now read at once.
    final shown = stations.take(4).toList();
    return Column(
      children: [
        for (var row = 0; row < (shown.length + 1) ~/ 2; row++) ...[
          if (row > 0) const SizedBox(height: 10),
          // IntrinsicHeight is what makes `stretch` legal here. The strip
          // sits in a Column inside the Home SliverList, so the Row's own
          // height arrives UNBOUNDED — and `stretch` hands its incoming
          // maxHeight to the tiles as a tight constraint, i.e. h=Infinity,
          // which asserts in performLayout. IntrinsicHeight measures the
          // taller tile first and bounds the Row to that, so both tiles in
          // a row still end up the same height (the point of `stretch`:
          // a 1-line and a 2-line station name must not stagger the grid).
          // Cheap at this size — two children, four tiles total.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var col = 0; col < 2; col++) ...[
                  if (col > 0) const SizedBox(width: 10),
                  Expanded(
                    child: row * 2 + col < shown.length
                        ? _MrtStationCard(
                            entry: shown[row * 2 + col],
                            onTap: () => onOpen(shown[row * 2 + col]),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MrtStationCard extends StatelessWidget {
  const _MrtStationCard({required this.entry, required this.onTap});

  final MrtNearestResult entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final station = entry.station;
    // "<distance> · <crowd word>" (iOS `SoftMrtTile.meta`). The walk minutes
    // are gone — on a 2-up tile the distance already answers "how far", and
    // the crowd word only appears when there IS a reading, so the tile never
    // prints the literal "Unknown" as if it were a measurement.
    final crowd = _crowdFor(station);
    final meta = [
      fmtDistance(entry.distanceM),
      if (crowd != null && crowd.level != CrowdLevel.unknown)
        _crowdWord(crowd.level),
    ].join(' · ');

    return Semantics(
      button: true,
      label: 'Open ${station.name} MRT station, $meta',
      child: Container(
        decoration: BoxDecoration(
          color: SoftBlue.card,
          borderRadius: BorderRadius.circular(18),
          boxShadow: SoftBlue.cardShadow,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: () => _showMrtStationMenu(context, station),
            child: Padding(
              // No fixed width — the tile fills its grid column (see
              // _MrtStrip). No border either: in the soft-blue language a
              // surface is a white fill + the one shadow, never an outline.
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      // Rounded-SQUARE line badges (iOS LineBullet), capped at
                      // two: a stadium pill reads as a chip you can tap, while
                      // the square badge is the map's own line-code mark.
                      for (final code in station.codes.take(2))
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Container(
                            constraints: const BoxConstraints(
                              minWidth: 26,
                              minHeight: 21,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: lineColorFor(code),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              code,
                              style: SoftBlue.mono(
                                12,
                                weight: FontWeight.w700,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    station.name,
                    style: SoftBlue.sans(
                      13.5,
                      weight: FontWeight.w700,
                      color: SoftBlue.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: SoftBlue.mono(11, color: SoftBlue.sub),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
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

String _crowdWord(CrowdLevel level) {
  switch (level) {
    case CrowdLevel.low:
      return 'Low';
    case CrowdLevel.moderate:
      return 'Moderate';
    case CrowdLevel.high:
      return 'High';
    case CrowdLevel.unknown:
      // Never the word "Unknown" — an em dash says "no reading" without
      // dressing an absence up as a measurement (iOS `wsWord`).
      return '—';
  }
}

// ─── Empty state ────────────────────────────────────────────────────────────

/// The "we can't answer yet" state — centred glyph, one fact, one primary
/// action, one way out. Mirrors iOS `locationOffState`: no card, no border,
/// nothing pretending to be content.
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.locationOff,
    required this.onNearby,
    required this.onSearch,
  });

  /// True when there's no location fix at all (the iOS copy); false when
  /// location works and simply nothing is in range — a different fact, so it
  /// doesn't borrow the "turn it on" wording.
  final bool locationOff;
  final VoidCallback onNearby;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 40, 30, 12),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: SoftBlue.chipBg,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_on_outlined,
              size: 22,
              color: SoftBlue.chipInk,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            locationOff ? 'Location is off' : 'No stops nearby',
            style: SoftBlue.sans(15, weight: FontWeight.w700, color: SoftBlue.ink),
          ),
          const SizedBox(height: 5),
          Text(
            locationOff
                ? 'Turn on location to see the stops and stations closest to you.'
                : 'Nothing is in range right now — search for a stop instead.',
            style: SoftBlue.sans(12.5, color: SoftBlue.sub),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          if (locationOff)
            FilledButton(
              onPressed: onNearby,
              style: FilledButton.styleFrom(
                backgroundColor: SoftBlue.blue,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 11,
                ),
              ),
              child: Text(
                'Turn on Location',
                style: SoftBlue.sans(
                  13.5,
                  weight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          TextButton(
            onPressed: onSearch,
            child: Text(
              'Search instead',
              style: SoftBlue.sans(
                12.5,
                weight: FontWeight.w600,
                color: SoftBlue.blue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "LIVE" — a breathing dot + the word, next to the freshness caption.
///
/// Local to this screen by design: the shared soft-blue token file is another
/// agent's territory this session, and this is the only screen that carries
/// the chip. Shown ONLY when there's a real refresh timestamp behind it (see
/// `_HeaderItem.live`) — the dot is the one thing on Nearby that moves
/// between refreshes, so it has to be telling the truth.
class _LiveChip extends StatefulWidget {
  const _LiveChip();

  @override
  State<_LiveChip> createState() => _LiveChipState();
}

class _LiveChipState extends State<_LiveChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reduce Motion keeps the dot, drops the breath (the word carries the
    // message on its own, so nothing is lost).
    final animate = !MediaQuery.disableAnimationsOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: SoftBlue.chipBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, child) => Opacity(
              opacity: animate ? 1 - 0.6 * _c.value : 1,
              child: child,
            ),
            child: Container(
              width: 5.5,
              height: 5.5,
              decoration: const BoxDecoration(
                color: SoftBlue.blue,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'LIVE',
            style: SoftBlue.sans(
              9.5,
              weight: FontWeight.w800,
              color: SoftBlue.chipInk,
            ).copyWith(letterSpacing: 0.6),
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

  /// Tiny crowd cue. NEUTRAL ink, never a traffic light: crowding isn't a
  /// disruption, and red/amber here spends the alarm colours the app reserves
  /// for real service problems. The word carries the level (iOS `wsWord`
  /// wording: "Seats available" / "Standing only" / "Almost full").
  Widget _crowdDot(LyneTheme t, Load load) {
    final label = switch (load) {
      Load.sea => 'Seats available',
      Load.sda => 'Standing only',
      Load.lsd => 'Almost full',
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: t.dim, shape: BoxShape.circle),
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
