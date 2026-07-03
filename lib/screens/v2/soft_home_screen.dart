// SoftHomeScreen — Leyne 2.0 Home (Material 3 Android variant).
//
// Layout (content parity with iOS WSHomeView.swift — not a visual clone):
//   header (live date eyebrow + "Nearby" title)
//   → live row (LIVE/LOCATION OFF · Updated h:mm)
//   → MRT strip (nearest stations, always visible when located)
//   → "Closest to you" section (1 highlighted card)
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

class _HeaderItem extends _Item {}

/// Tap-to-search pill — mirrors WSHomeView.swift's `searchBar`: sits directly
/// under the header/title, above everything else (including the MRT strip).
/// Not an inline TextField — the whole pill is a button that pushes the real
/// search screen via `onOpenSearch`, same as iOS's `Button(action: onSearch)`.
class _SearchBarItem extends _Item {}

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

class _EmptyItem extends _Item {}

/// A quiet prompt (shown under the saved-stop fallback) to enable location.
class _LocationNudgeItem extends _Item {}

// ─────────────────────────────────────────────────────────────────────────────

class _SoftHomeScreenState extends State<SoftHomeScreen>
    with WidgetsBindingObserver {
  // ── Walk-minute memoisation cache ─────────────────────────────────────────
  final Map<String, int?> _walkCache = {};

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

  /// Live date eyebrow ("TUESDAY · 2 JUL") — replaces the old time-of-day
  /// greeting. Eyebrow() already uppercases, so casing here doesn't matter.
  /// intl isn't a direct pubspec dependency (only pulled in transitively),
  /// so this formats manually rather than adding a new dependency for one line.
  static const _weekdayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday', //
  ];
  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _dateEyebrow() {
    final now = DateTime.now();
    return '${_weekdayNames[now.weekday - 1]} · ${now.day} ${_monthNames[now.month - 1]}';
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

  List<_Item> _buildItems({required List<NearbyStop> nearby}) {
    final items = <_Item>[];
    // Stops hidden via long-press "Hide from Nearby" are computed once from
    // the RAW DataStore list — see `_hiddenNearbyCount` — so the restore
    // footer can appear in either branch below (including when hiding
    // emptied the visible `nearby` list entirely).
    final hiddenCount = _hiddenNearbyCount();

    // Weather hero sits above the greeting when a snapshot is available.
    if (WeatherStore.shared.snapshot != null) {
      items.add(_WeatherItem());
      items.add(_GapItem(8));
    }
    items.add(_HeaderItem());
    items.add(_GapItem(14));
    items.add(_SearchBarItem());
    items.add(_GapItem(16));
    items.add(_LiveRowItem());

    // MRT — nearby stations strip. Its own small section above the bus stop
    // list, independent of whether there are nearby BUS stops (only needs a
    // location fix and at least one station in range). Mirrors WSHomeView.
    final nearestStations = _nearbyStations();
    if (nearestStations.isNotEmpty) {
      items.add(_GapItem(16));
      items.add(_EyebrowItem('MRT'));
      items.add(_GapItem(10));
      items.add(_MrtStripItem(nearestStations));
    }

    if (nearby.isEmpty) {
      final pins = AppModel.shared.pins;
      if (pins.isNotEmpty) {
        // No nearby stops (location off / denied, or none in range) but the
        // user has saved stops — show those instead of a dead end, so the app
        // still answers "when's my bus?". The first saved stop is the hero
        // ("Your stop"); the rest follow. Mirrors iOS SoftHomeView.
        items.add(_GapItem(16));
        items.add(_EyebrowItem('Your stops'));
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
      } else {
        items.add(_GapItem(8));
        items.add(_EmptyItem());
      }
      if (hiddenCount > 0) {
        items.add(_GapItem(10));
        items.add(_HiddenFooterItem(hiddenCount));
      }
      return items;
    }

    // "Closest to you" — the single nearest stop.
    items.add(_GapItem(16));
    items.add(_EyebrowItem('Closest to you'));
    items.add(_GapItem(10));
    items.add(_NearbyCardItem(nearby.first, highlight: true));

    // "Other nearby stops" — up to 11 more.
    // The native ad card is injected after the 3rd stop (index 2) so it
    // sits naturally mid-list rather than at the top or very bottom.
    // NativeAdCard renders nothing (zero-size) until loaded + consent ready,
    // so there is never a gap or placeholder when fill is pending.
    const nativeAdAfterIndex =
        2; // 0-based index of the stop after which the ad appears
    final others = nearby.skip(1).take(11).toList();
    if (others.isNotEmpty) {
      items.add(_GapItem(16));
      items.add(_EyebrowItem('Other nearby stops'));
      items.add(_GapItem(10));
      for (var i = 0; i < others.length; i++) {
        if (i > 0) items.add(_GapItem(10));
        items.add(_NearbyCardItem(others[i], highlight: false));
        if (i == nativeAdAfterIndex && others.length > nativeAdAfterIndex + 1) {
          // Only inject when there is at least one more stop below — keeps
          // the ad from sitting as the final item in a short list.
          items.add(_GapItem(10));
          items.add(_NativeAdItem());
        }
      }
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
      _HeaderItem() => _header(context),
      _SearchBarItem() => _searchBar(context),
      _LiveRowItem() => _liveRow(context),
      _GapItem(:final height) => SizedBox(height: height),
      _EyebrowItem(:final label) => Eyebrow(label),
      _NearbyCardItem(:final stop, :final highlight, :final badgeText) =>
        RepaintBoundary(
          child: _NearbyCard(
            stop: stop,
            highlight: highlight,
            badgeText: badgeText,
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
        // Live date eyebrow, not a time-of-day greeting — a departure-board
        // detail that's useful rather than decorative. Mirrors
        // WSHomeView.swift's `dateEyebrow`.
        Eyebrow(_dateEyebrow()),
        const SizedBox(height: 2),
        Text(
          'Nearby',
          // 30 → 26: matches WSHomeView.swift's title (ws.sans(26, .heavy)) —
          // Android's was reading noticeably larger than iOS at the same
          // visual hierarchy position.
          style: t.sans(26, weight: FontWeight.w700, color: t.fg),
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

  Widget _liveRow(BuildContext context) {
    final t = context.t;
    final located = LocationService.shared.lastLocation != null;
    final updated = _updatedLabel(_nearbyStops());
    return Row(
      children: [
        Icon(
          located ? Icons.location_on_rounded : Icons.location_off,
          size: 13,
          color: located ? LyneSignal.meBlue : t.dim,
        ),
        const SizedBox(width: 5),
        // Match iOS SoftHomeView.liveRow exactly: blue location glyph, then
        // a green dot + dim "LIVE" when located, or dim "LOCATION OFF" when not.
        // (No redundant "NEAR YOU" string — the section title already says it.)
        if (located) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: t.soon, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          // 10 → 11: legibility floor (owner directive — Android type must
          // never go below 11, even where the size otherwise mirrors the
          // WSLiveBadge word iOS sets at 9.5).
          Text(
            'LIVE',
            style: t
                .mono(11, weight: FontWeight.w700, color: t.dim)
                .copyWith(letterSpacing: 0.8),
          ),
        ] else
          Text(
            'LOCATION OFF',
            style: t
                .mono(11, weight: FontWeight.w700, color: t.dim)
                .copyWith(letterSpacing: 0.8),
          ),
        // Freshness meta — newest of the visible nearby stops' last refresh.
        // Mirrors WSHomeView.swift's `WSFmt.upd(...)` section-header meta
        // (ws.mono(11) — matches Android's floor here exactly).
        if (updated != null) ...[
          const SizedBox(width: 5),
          Text('·', style: t.mono(11, color: t.faint)),
          const SizedBox(width: 5),
          Text(
            'UPDATED $updated',
            style: t
                .mono(11, weight: FontWeight.w500, color: t.faint)
                .copyWith(letterSpacing: 0.8),
          ),
        ],
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

  /// Identity row: pin tile · (name + subtitle + compact meta) · chevron.
  /// Matches iOS SoftNearbyStopCard which shows only the header row — no
  /// per-service arrivals list, no divider, no footer.
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
        // Leading 46×46 rounded pin tile.
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.surfaceHi,
            borderRadius: BorderRadius.circular(LyneRadius.md),
          ),
          child: Icon(Icons.location_on_rounded, size: 20, color: t.fg),
        ),
        const SizedBox(width: 12),
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
        // and stacked the route chips vertically (owner-reported).
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
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
    final services = DataStore.shared.servicesFor(code);
    final sorted = [...services]
      ..sort((a, b) => _liveSec(a, now).compareTo(_liveSec(b, now)));
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
            // Compact word (iOS wsWord parity: Seats/Standing/Limited) in a
            // Flexible so the width-capped column ellipsizes the word rather
            // than overflowing. Safe here: the host ConstrainedBox bounds us.
            Flexible(child: CrowdMeter(load: soonest.load, compact: true)),
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
