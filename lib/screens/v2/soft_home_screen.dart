// SoftHomeScreen — Leyne 2.0 Home (Material 3 Android variant).
//
// Layout (matches iOS SoftHomeView.swift exactly):
//   header (greeting + title + filter/map buttons)
//   → live row (NEAR YOU · LIVE)
//   → MRT alerts
//   → "Closest to you" section (1 highlighted card)
//   → "Other nearby stops" section (up to 11 cards)
//   → empty state (when no nearby stops)
//
// Saved stops live on the Saved tab but ALSO appear here when they're near
// you — Nearby reflects what's around you, so saving never removes a stop
// from it (iOS parity). Long-press a card for a quick stop-view peek.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/data_store.dart';
import '../../data/geo.dart';
import '../../data/models.dart';
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

class _AlertItem extends _Item {
  _AlertItem(this.alert);
  final TrainAlert alert;
}

class _NativeAdItem extends _Item {}

class _EmptyItem extends _Item {}

/// A quiet prompt (shown under the saved-stop fallback) to enable location.
class _LocationNudgeItem extends _Item {}

// ─────────────────────────────────────────────────────────────────────────────

class _SoftHomeScreenState extends State<SoftHomeScreen>
    with WidgetsBindingObserver {
  final Set<String> _dismissedAlerts = {};

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

  List<_Item> _buildItems({
    required List<NearbyStop> nearby,
    required List<TrainAlert> visibleAlerts,
  }) {
    final items = <_Item>[];

    // Weather hero sits above the greeting when a snapshot is available.
    if (WeatherStore.shared.snapshot != null) {
      items.add(_WeatherItem());
      items.add(_GapItem(8));
    }
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
            items.add(_NearbyCardItem(_savedStop(rest[i].code), highlight: false));
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
        if (i == nativeAdAfterIndex &&
            others.length > nativeAdAfterIndex + 1) {
          // Only inject when there is at least one more stop below — keeps
          // the ad from sitting as the final item in a short list.
          items.add(_GapItem(10));
          items.add(_NativeAdItem());
        }
      }
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
      _WeatherItem() => const WeatherHeader(),
      _HeaderItem() => _header(context),
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
      _AlertItem(:final alert) => _mrtAlertCard(context, alert),
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
        Eyebrow(_greeting()),
        const SizedBox(height: 2),
        Text(
          'Nearby',
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
          Text(
            'LIVE',
            style: t
                .mono(10, weight: FontWeight.w700, color: t.dim)
                .copyWith(letterSpacing: 0.8),
          ),
        ] else
          Text(
            'LOCATION OFF',
            style: t
                .mono(10, weight: FontWeight.w700, color: t.dim)
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
              Icon(Icons.location_on_rounded, size: 14, color: LyneSignal.meBlue),
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

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    if (h < 22) return 'Good evening';
    return 'Good night';
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
    final subtitle = road.isEmpty ? 'Stop $code' : 'Stop $code · $road';
    final walkMin = stop.walkMin;

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
                style: t.sans(17, weight: FontWeight.w600, color: t.fg),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: t.mono(12.5, color: t.dim),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              _compactMeta(t, code, walkMin),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Icon(Icons.chevron_right_rounded, size: 18, color: t.faint),
      ],
    );
  }

  /// Single merged meta line: walk time + soonest arrival with "~" whisper.
  /// Mirrors iOS SoftNearbyStopCard compactMeta — no per-service list.
  Widget _compactMeta(LyneTheme t, String code, int walkMin) {
    final now = DateTime.now();
    final feed = Freshness.from(DataStore.shared.lastRefresh(code));
    final services = DataStore.shared.servicesFor(code);
    final sorted = [...services]
      ..sort((a, b) => _liveSec(a, now).compareTo(_liveSec(b, now)));
    final soonest = sorted.isEmpty ? null : sorted.first;
    final hasMeta = walkMin > 0 || soonest != null;
    if (!hasMeta) return const SizedBox.shrink();

    ArrivalConfidence? conf;
    String? whenText;
    if (soonest != null) {
      conf = ArrivalConfidence.of(monitored: soonest.monitored, feed: feed);
      final sec = _liveSec(soonest, now);
      final eta = fmtEta(sec);
      whenText = eta.big == 'Arr'
          ? 'next now'
          : 'next in ${eta.big} ${eta.small}';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (walkMin > 0) ...[
          Icon(Icons.directions_walk_rounded, size: 12, color: t.soon),
          const SizedBox(width: 3),
          Text(
            '${walkMin < 1 ? 1 : walkMin} min',
            style: t.mono(12, weight: FontWeight.w500, color: t.soon),
          ),
          if (soonest != null) ...[
            const SizedBox(width: 5),
            Text('·', style: t.mono(12, color: t.faint)),
            const SizedBox(width: 5),
          ],
        ],
        if (soonest != null && whenText != null) ...[
          Icon(Icons.directions_bus_outlined, size: 11, color: t.dim),
          const SizedBox(width: 3),
          if (conf == ArrivalConfidence.unconfirmed)
            ExcludeSemantics(
              child: Text(
                '~',
                style: t.mono(11, weight: FontWeight.w400, color: t.faint),
              ),
            ),
          Text(
            whenText,
            style: t.mono(12, weight: FontWeight.w500, color: t.fg),
          ),
        ],
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
            Text(subtitle, style: t.mono(12.5, color: t.dim)),
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
                    _actionRow(
                      t,
                      icon: pinned
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
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
              style: t.sans(15, weight: FontWeight.w700, color: t.onAccent),
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
