// SoftHomeScreen — Leyne 2.0 Home (Material 3 Android variant).
//
// Layout (content parity with iOS WSHomeView.swift — not a visual clone):
//   header (live date eyebrow + "Nearby" title)
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
import '../../widgets/ad_banner.dart';
import '../../widgets/v2/alert_actions.dart';
import '../../widgets/v2/confidence.dart';
import '../../widgets/v2/proximity.dart';
import '../../widgets/v2/soft_components.dart';
import '../../widgets/v2/soft_departure_board.dart';
import '../../widgets/v2/soft_mrt_home.dart';
import '../../widgets/v2/soft_tab_bar.dart';
import '../../widgets/v2/weather_header.dart';
import 'soft_mrt_station_screen.dart';

class SoftHomeScreen extends StatefulWidget {
  const SoftHomeScreen({
    super.key,
    required this.onTab,
    required this.onOpenStop,
    required this.onOpenBus,
    required this.onOpenSearch,
    required this.onOpenNearby,
  });
  final ValueChanged<SoftTab> onTab;
  final ValueChanged<String> onOpenStop;

  /// Opens a specific service's bus screen directly from a hero-card chip tap
  /// (home-hero-redesign, 2026-07-07). Mirrors the `(stopCode, svc)` hook
  /// already wired through SoftRoot._pushBus for SoftFavouritesScreen.
  final void Function(String stopCode, String svc) onOpenBus;
  final VoidCallback onOpenSearch;

  /// Pushes the new "Nearby" screen (full stop list + MRT strip + LIVE
  /// header + hidden-stops footer) — Home became minimal 2026-07-07 and
  /// handed this content off to its own pushed screen behind the
  /// "All stops & stations" door card.
  final VoidCallback onOpenNearby;

  @override
  State<SoftHomeScreen> createState() => _SoftHomeScreenState();
}

// ── Item types for the flat ListView.builder index ──────────────────────────

sealed class _Item {}

class _WeatherItem extends _Item {}

class _HeaderItem extends _Item {}

/// "Next bus" hero card — the soonest live arrival across the stops shown on
/// Home, promoted above the list so the first glance answers "what now?".
class _NextBusItem extends _Item {
  _NextBusItem(this.stop, this.service);
  final NearbyStop stop;
  final Service service;
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

/// Bus/MRT segmented toggle — Wave 1 "Nearby transport" port
/// (ios-native/Leyne/WhereSia/WSHomeView.swift's WSSegmented under the
/// header). Swaps the content below it in place.
class _SegmentedItem extends _Item {}

/// One nearby bus stop rendered as a full departure card (name, walk line,
/// [SoftDepartureRow] list capped at 3 with "Show all N buses" expand) —
/// Bus-mode content, mirrors WSHomeView.swift's private BusStopCard.
class _BusStopCardItem extends _Item {
  _BusStopCardItem(this.stop);
  final NearbyStop stop;
}

/// MRT-mode content: the nearest station's full card stack
/// ([SoftMrtHomeContent]) — mirrors WSHomeView.swift's mrtContent /
/// WSMrtHomeContent.
class _MrtHomeContentItem extends _Item {
  _MrtHomeContentItem(this.entry);
  final MrtNearestResult entry;
}

class _EyebrowItem extends _Item {
  _EyebrowItem(this.label);
  final String label;
}

class _NearbyCardItem extends _Item {
  _NearbyCardItem(this.stop);
  final NearbyStop stop;
}

/// The "door" card to the pushed Nearby screen — full stop list, MRT strip,
/// LIVE/Updated header, hidden-stops footer (2026-07-07 minimal-Home pass).
class _NearbyDoorItem extends _Item {}

class _NativeAdItem extends _Item {}

/// Quiet footer offering the way back from the long-press "Hide from
/// Nearby" action — without it a hidden stop is gone for good (there is no
/// standalone "Me" tab). Mirrors WSHomeView.swift's busList footer.
class _HiddenFooterItem extends _Item {
  _HiddenFooterItem(this.count);
  final int count;
}

class _EmptyItem extends _Item {}

/// A quiet prompt (shown under the saved-stop fallback) to enable location.
class _LocationNudgeItem extends _Item {}

// ─────────────────────────────────────────────────────────────────────────────

class _SoftHomeScreenState extends State<SoftHomeScreen>
    with WidgetsBindingObserver {
  // ── Walk-minute memoisation cache ─────────────────────────────────────────
  final Map<String, int?> _walkCache = {};

  /// Bus (0) / MRT (1) content mode — mirrors WSHomeView.swift's `mode`
  /// state under the segmented toggle.
  int _mode = 0;

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
  /// Stops the user hid (long-press → "Hide from Nearby") are filtered out;
  /// they're restorable from Settings → Hidden stops.
  List<NearbyStop> _nearbyStops() {
    final base = [...DataStore.shared.nearby]
      ..removeWhere((s) => AppModel.shared.isHiddenNearby(s.stopCode))
      ..sort((a, b) => a.distanceM.compareTo(b.distanceM));
    return base.take(12).toList();
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
    DataStore.shared.prefetchNearbyArrivals();
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

  /// Wave 1 "Nearby transport" layout (mirrors WSHomeView.swift): quiet
  /// header + search, a Bus/MRT segmented toggle, then mode-specific
  /// content, one ad card, and (Bus mode only) the hidden-stops footer.
  List<_Item> _buildItems({required List<NearbyStop> nearby}) {
    final items = <_Item>[];
    final hiddenCount = _hiddenNearbyCount();
    final nearestStations = _nearbyStations();

    if (WeatherStore.shared.snapshot != null) {
      items.add(_WeatherItem());
      items.add(_GapItem(8));
    }
    items.add(_HeaderItem());
    items.add(_GapItem(14));
    items.add(_SearchBarItem());
    items.add(_GapItem(14));
    items.add(_SegmentedItem());
    items.add(_GapItem(14));

    if (_mode == 0) {
      _buildBusContent(items, nearby: nearby, hiddenCount: hiddenCount);
    } else {
      _buildMrtContent(items, stations: nearestStations);
    }

    items.add(_GapItem(14));
    items.add(_NativeAdItem());

    if (_mode == 0 && hiddenCount > 0) {
      items.add(_GapItem(10));
      items.add(_HiddenFooterItem(hiddenCount));
    }

    return items;
  }

  /// Bus mode: a [_BusStopCardItem] per nearby stop (soonest walk first,
  /// capped at 6 — mirrors WSHomeView.swift's `busContent`), falling back to
  /// saved stops when there's no location fix, then the "Browse nearby
  /// transport" door card.
  void _buildBusContent(
    List<_Item> items, {
    required List<NearbyStop> nearby,
    required int hiddenCount,
  }) {
    // Stops the list will show (capped at 6). Nearby first; when there's no
    // location fix, fall back to saved stops.
    final List<NearbyStop> display;
    if (nearby.isEmpty) {
      final pins = AppModel.shared.pins;
      display = [
        for (var i = 0; i < pins.length && i < 6; i++) _savedStop(pins[i].code),
      ];
    } else {
      display = nearby.take(6).toList();
    }

    if (display.isEmpty) {
      items.add(_EmptyItem());
      items.add(_GapItem(14));
      items.add(_NearbyDoorItem());
      return;
    }

    // Promote the soonest live arrival to a hero card above the list.
    final hero = _nextBus(display);
    if (hero != null) {
      items.add(hero);
      items.add(_GapItem(14));
    }

    for (var i = 0; i < display.length; i++) {
      if (i > 0) items.add(_GapItem(14));
      items.add(_BusStopCardItem(display[i]));
    }
    if (nearby.isEmpty && LocationService.shared.lastLocation == null) {
      items.add(_GapItem(10));
      items.add(_LocationNudgeItem());
    }
    items.add(_GapItem(14));
    items.add(_NearbyDoorItem());
  }

  /// Soonest arrival across [stops] — the hero card's subject. Null when no
  /// stop has live arrivals yet.
  _NextBusItem? _nextBus(List<NearbyStop> stops) {
    final now = DateTime.now();
    NearbyStop? bestStop;
    Service? best;
    var bestSec = 1 << 30;
    for (final stop in stops) {
      for (final svc in DataStore.shared.servicesFor(stop.stopCode)) {
        final sec = SoftDepartureRow.liveEtaSec(svc, now);
        if (sec < bestSec) {
          bestSec = sec;
          best = svc;
          bestStop = stop;
        }
      }
    }
    if (best == null || bestStop == null) return null;
    return _NextBusItem(bestStop, best);
  }

  /// MRT mode: the nearest station's full card stack, or a quiet prompt when
  /// there's no location fix — mirrors WSHomeView.swift's `mrtContent`.
  void _buildMrtContent(
    List<_Item> items, {
    required List<MrtNearestResult> stations,
  }) {
    if (stations.isNotEmpty) {
      items.add(_MrtHomeContentItem(stations.first));
    } else {
      items.add(_EmptyItem());
    }
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
      _HeaderItem() => _header(context),
      _SearchBarItem() => _searchBar(context),
      _SegmentedItem() => _modeSegmented(context),
      _NextBusItem(:final stop, :final service) => RepaintBoundary(
        child: _NextBusHeroCard(
          stop: stop,
          service: service,
          onOpen: () => widget.onOpenBus(stop.stopCode, service.no),
          onPeek: () => _showStopPeek(context, stop),
        ),
      ),
      _BusStopCardItem(:final stop) => RepaintBoundary(
        child: _BusStopCard(
          stop: stop,
          onOpenStop: () => widget.onOpenStop(stop.stopCode),
          onOpenBus: (svc) => widget.onOpenBus(stop.stopCode, svc),
          onHide: () => AppModel.shared.hideFromNearby(stop.stopCode),
        ),
      ),
      _MrtHomeContentItem(:final entry) => RepaintBoundary(
        child: SoftMrtHomeContent(
          key: ValueKey(entry.station.id),
          station: entry.station,
          distanceM: entry.distanceM,
          walkMin: entry.walkMin,
          onOpenStation: () => _openMrtStation(
            context,
            entry.station,
            distanceM: entry.distanceM,
            walkMin: entry.walkMin,
          ),
        ),
      ),
      _GapItem(:final height) => SizedBox(height: height),
      _EyebrowItem(:final label) => Eyebrow(label),
      _NearbyCardItem(:final stop) => RepaintBoundary(
        child: NearbyStopCard(
          stop: stop,
          onTap: () => widget.onOpenStop(stop.stopCode),
          onLongPress: () => _showStopPeek(context, stop),
        ),
      ),
      _HiddenFooterItem(:final count) => _hiddenFooter(context, count),
      _NearbyDoorItem() => _NearbyDoorCard(onTap: widget.onOpenNearby),
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

  Widget _header(BuildContext context) {
    // "Departures" → live clock headline (owner parity ask, 2026-07-13):
    // iOS's WSGreetingHero shows a time-of-day greeting over a live
    // date/time title ("Sun, 13 Jul · 7:35 PM"); Android now matches.
    return const _ClockHeader();
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
              borderRadius: BorderRadius.circular(LyneRadius.md),
              border: Border.all(color: t.line, width: 1),
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

  /// Bus/MRT segmented toggle — mirrors WSHomeView.swift's WSSegmented
  /// (a sliding pill, monochrome — the pill itself carries no MRT-line hue).
  Widget _modeSegmented(BuildContext context) {
    final t = context.t;
    const labels = ['Bus', 'MRT'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  if (_mode == i) return;
                  HapticFeedback.selectionClick();
                  setState(() => _mode = i);
                },
                child: AnimatedContainer(
                  duration: LyneMotion.standard,
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: _mode == i ? t.contrast : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    labels[i],
                    style: t.sans(
                      12.5,
                      weight: FontWeight.w700,
                      color: _mode == i ? t.contrastFg : t.dim,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
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

// ─── Nearby stop card ────────────────────────────────────────────────────────

/// A compact nearby-stop card matching iOS SoftNearbyStopCard: pin tile ·
/// name · "Stop {code} · road" + a single merged meta line (walk time +
/// soonest arrival with "~" whisper) + trailing chevron. No inline arrivals
/// list, no divider, no footer. Whole card taps to open the full stop view.
/// Home itself now renders `_BusStopCard` per nearby stop (Wave 1 "Nearby
/// transport" port, 2026-07-11); this plain card is still used by
/// `SoftNearbyScreen`'s full stop list.
class NearbyStopCard extends StatelessWidget {
  const NearbyStopCard({
    super.key,
    required this.stop,
    required this.onTap,
    this.onLongPress,
  });

  final NearbyStop stop;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = context.t;

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
              border: Border.all(color: t.line, width: 1.0),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
              // No route-tile row here any more: the hero taught chips to
              // carry times, so timeless tiles below it read as broken. The
              // full inventory is one tap away (calm pass, 2026-07-07).
            ],
          ),
        ),
        const SizedBox(width: 10),
        // No when-column any more — the hero card owns arrival information
        // on this screen; these rows only answer "what else is walkable"
        // (owner decision 2026-07-07: the two-shape column — "Now / Bus A &
        // B" vs "3 min / Bus N · Seats" — read as two kinds of rows).
        Icon(Icons.chevron_right_rounded, size: 18, color: t.faint),
      ],
    );
  }
}

// ─── Bus stop card (Wave 1 "Nearby transport" port) ────────────────────────
//
// The reference card (WSHomeView.swift's BusStopCard): name + code · road,
// walk line, then [SoftDepartureRow]s — capped at 3, "Show all N buses"
// expands in place (no navigation push). A visible bookmark toggles Saved;
// long-press still opens the full quick-action peek sheet.

class _BusStopCard extends StatefulWidget {
  const _BusStopCard({
    required this.stop,
    required this.onOpenStop,
    required this.onOpenBus,
    required this.onHide,
  });

  final NearbyStop stop;
  final VoidCallback onOpenStop;
  final ValueChanged<String> onOpenBus;
  final VoidCallback onHide;

  @override
  State<_BusStopCard> createState() => _BusStopCardState();
}

class _BusStopCardState extends State<_BusStopCard> {
  static const _collapsedCap = 3;
  bool _expanded = false;

  List<Service> _services(DateTime now) {
    final list = [...DataStore.shared.servicesFor(widget.stop.stopCode)];
    list.sort((a, b) {
      final c = SoftDepartureRow.liveEtaSec(
        a,
        now,
      ).compareTo(SoftDepartureRow.liveEtaSec(b, now));
      if (c != 0) return c;
      return a.no.compareTo(b.no);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final stop = widget.stop;
    final name = stop.stopName.isEmpty ? stop.stopCode : stop.stopName;
    final road = DataStore.shared.roadName(stop.stopCode);
    final metaLine = road.isEmpty
        ? stop.stopCode
        : '${stop.stopCode}  ·  $road';
    final walkText = stop.distanceM > 0
        ? '${stop.walkMin} min walk  ·  ${fmtDistance(stop.distanceM)}'
        : 'Nearby';

    return ListenableBuilder(
      listenable: Listenable.merge([DataStore.shared, AppModel.shared]),
      builder: (context, _) {
        final now = DateTime.now();
        final services = _services(now);
        final visible = _expanded
            ? services
            : services.take(_collapsedCap).toList();
        final pinned = AppModel.shared.isPinned(stop.stopCode);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        widget.onOpenStop();
                      },
                      onLongPress: () => _showStopPeekFor(context, stop),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: t.sans(
                              22,
                              weight: FontWeight.w800,
                              color: t.fg,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            metaLine,
                            style: t.sans(
                              13,
                              weight: FontWeight.w500,
                              color: t.dim,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => AppModel.shared.togglePin(stop.stopCode),
                    icon: Icon(
                      pinned
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_outline_rounded,
                      size: 20,
                      color: pinned ? t.fg : t.dim,
                    ),
                  ),
                  // Visible affordance for the quick-actions sheet — the
                  // long-press peek alone was undiscoverable.
                  IconButton(
                    onPressed: () => _showStopPeekFor(context, stop),
                    tooltip: 'Stop options',
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      size: 20,
                      color: t.dim,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.directions_walk_rounded, size: 13, color: t.dim),
                  const SizedBox(width: 8),
                  Text(
                    walkText,
                    style: t.sans(13.5, weight: FontWeight.w500, color: t.dim),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const SoftRowDivider(),
              if (services.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    children: [
                      for (var i = 0; i < 3; i++) ...[
                        if (i > 0) const SizedBox(height: 14),
                        const SoftSkeletonRow(),
                      ],
                    ],
                  ),
                )
              else ...[
                for (var i = 0; i < visible.length; i++) ...[
                  if (i > 0) const SoftRowDivider(),
                  SoftDepartureRow(
                    key: ValueKey(visible[i].no),
                    service: visible[i],
                    onTap: () => widget.onOpenBus(visible[i].no),
                  ),
                ],
                if (services.length > _collapsedCap) ...[
                  const SoftRowDivider(),
                  InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _expanded = !_expanded);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _expanded
                                ? 'Show fewer'
                                : 'Show all ${services.length} buses',
                            style: t.sans(
                              14,
                              weight: FontWeight.w600,
                              color: t.dim,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            _expanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 16,
                            color: t.faint,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  void _showStopPeekFor(BuildContext context, NearbyStop stop) {
    final state = context.findAncestorStateOfType<_SoftHomeScreenState>();
    state?._showStopPeek(context, stop);
  }
}

// ─── MRT — nearby stations strip ────────────────────────────────────────────

/// Horizontal strip of the nearest MRT/LRT stations — its own small section,
/// always visible above the bus stop list when located (no filter to find
/// it). Mirrors WSHomeView.swift's `mrtSection` / `MrtCard`: line-code pills
/// in official colours, live crowd if already cached, name, distance/walk.
class MrtStrip extends StatelessWidget {
  const MrtStrip({super.key, required this.stations, required this.onOpen});

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

/// The single nearest MRT/LRT station, promoted from the horizontal strip to
/// a comfortable full-width card (2026-07-07 minimal-Home pass) — same
/// content as [_MrtStationCard] (line bullets, crowd, name, walk · distance)
/// but sized to the row's full width rather than the strip's fixed 172dp,
/// which read stretched/empty at full width.
class _NearbyDoorCard extends StatelessWidget {
  const _NearbyDoorCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Semantics(
      button: true,
      label: 'Open all stops and stations',
      child: Material(
        color: t.liveBg,
        borderRadius: BorderRadius.circular(LyneRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(LyneRadius.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.map_outlined, size: 20, color: t.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'All stops & stations',
                    style: t.sans(15, weight: FontWeight.w600, color: t.fg),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 18, color: t.faint),
              ],
            ),
          ),
        ),
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
                  // Walk time leads (the human unit), distance follows — the
                  // same order as the hero card's walk line.
                  '${entry.walkMin} min walk · ${fmtDistance(entry.distanceM)}',
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

/// Live crowd for a station, read passively from whatever DataStore already
/// has cached — Home doesn't trigger a fetch of its own (crowd is warmed by
/// the MRT tab / station screen), so this is "if available" only, matching
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
          Text('A retry usually fixes this.', style: t.sans(13, color: t.dim)),
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
                arriving ? 'Now' : eta.big,
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

// ─── Next-bus hero card ──────────────────────────────────────────────────────

/// Promoted "what now" card above the stop list: soonest live arrival across
/// the stops Home shows. Tints `liveBg` when the bus is imminent so the
/// glance-path is hero → list. Tap opens the bus screen; `⋯` opens the same
/// quick-actions sheet as the long-press peek.
class _NextBusHeroCard extends StatelessWidget {
  const _NextBusHeroCard({
    required this.stop,
    required this.service,
    required this.onOpen,
    required this.onPeek,
  });

  final NearbyStop stop;
  final Service service;
  final VoidCallback onOpen;
  final VoidCallback onPeek;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final now = DateTime.now();
    final sec = service.arrivalDate != null
        ? service.arrivalDate!.difference(now).inSeconds.clamp(0, 1 << 30)
        : service.etaSec;
    final arriving = sec < 120;
    final etaBig = sec < 60 ? 'Now' : '${(sec / 60).ceil()}';
    final following = service.followingSec;
    final stopName = stop.stopName.isEmpty ? stop.stopCode : stop.stopName;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: arriving ? t.liveBg : t.surfaceHi,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'NEXT BUS',
                style: t
                    .mono(10, weight: FontWeight.w600, color: t.dim)
                    .copyWith(letterSpacing: 0.8),
              ),
              const Spacer(),
              SizedBox(
                width: 36,
                height: 36,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  onPressed: onPeek,
                  tooltip: 'Stop options',
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    size: 20,
                    color: t.dim,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(LyneRadius.md),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ServiceBadge(svc: service.no, size: ServiceBadgeSize.lg),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          service.dest.isEmpty
                              ? 'Bus ${service.no}'
                              : service.dest,
                          style: t.sans(
                            17,
                            weight: FontWeight.w700,
                            color: t.fg,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        OccupancyLabel(load: service.load),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        etaBig,
                        style: t.mono(
                          44,
                          weight: FontWeight.w600,
                          color: t.fg,
                        ),
                      ),
                      if (sec >= 60)
                        Text('min', style: t.mono(12, color: t.dim)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            [
              if (following > 0) 'then ${(following / 60).ceil()} min',
              'from $stopName',
            ].join('  ·  '),
            style: t.sans(13, color: t.dim),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─── Home header: greeting + live clock (mirrors WSGreetingHero) ────────────

/// Compact one-line header: "Good afternoon · Sun, 13 Jul · 7:35 PM". The
/// old two-line greeting + headline was removed so arrivals own the top of
/// Home. Re-renders on the minute (the line shows minutes only) and honours
/// the app-wide 12/24h setting via [fmtClock]. intl isn't a direct pubspec
/// dependency, so the date part is formatted manually.
class _ClockHeader extends StatefulWidget {
  const _ClockHeader();

  @override
  State<_ClockHeader> createState() => _ClockHeaderState();
}

class _ClockHeaderState extends State<_ClockHeader> {
  Timer? _tick;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _scheduleNextTick();
  }

  /// Fires at each minute boundary so the clock never shows a stale minute,
  /// without a per-second timer.
  void _scheduleNextTick() {
    final now = DateTime.now();
    _tick = Timer(Duration(seconds: 61 - now.second), () {
      if (!mounted) return;
      setState(() {});
      _scheduleNextTick();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static String _greeting(DateTime now) {
    // Same buckets as WSSky.greeting().
    final h = now.hour;
    if (h >= 5 && h < 12) return 'Good morning';
    if (h >= 12 && h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  static String _clockLine(DateTime now) {
    final hhmm =
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}';
    final time = fmtClock(hhmm, use24h: AppModel.shared.use24h);
    return '${_weekdays[now.weekday - 1]}, ${now.day} '
        '${_months[now.month - 1]} · $time';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final now = DateTime.now();
    // Compact one-liner: greeting + date + time in a single dim row. The
    // previous two-line headline pushed the first arrival card ~90px down;
    // arrivals own the top of Home now.
    return Text(
      '${_greeting(now)}  ·  ${_clockLine(now)}',
      style: t.sans(13, weight: FontWeight.w500, color: t.dim),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
