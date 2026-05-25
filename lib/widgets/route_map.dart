// Route map — OpenStreetMap via flutter_map.
//
// Renders three points:
//   1. Your bus stop — accent-coloured pin
//   2. The live bus position — green badge with the service number,
//      if LTA reports lat/lon for the next bus
//   3. The user's current location — a small blue dot using the latest
//      LocationService reading
//
// The route polyline was removed (was visually noisy — LTA has no road
// geometry so straight lines between stops looked like a tangle on
// turns). The three points alone communicate "where the bus is now,
// where your stop is, where you are." Route progress as a list of
// stops lives in the RouteProgress widget below the map.
//
// Why OSM: avoids the Google Cloud + billing requirement for
// `google_maps_flutter`. OSM's tiles are free, no key, no card on file.
// Singapore has excellent OSM coverage. OSM's tile policy requires a
// real user-agent string + attribution visible to users — both wired
// below.
//
// This widget is Android-only — iOS shipping now ships via the SwiftUI
// app at `ios-native/` which renders the equivalent view with MapKit.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/data_store.dart';
import '../services/location_service.dart';
import '../theme.dart';

class RouteMap extends StatelessWidget {
  const RouteMap({
    super.key,
    required this.route,
    required this.busNo,
    required this.loading,
  });

  final RouteInfo? route;
  final String busNo;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final r = route;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 240,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: t.line),
        ),
        child: r == null || r.stops.isEmpty
            ? _placeholder(t, loading)
            : Stack(
                children: [
                  _OsmMap(route: r, busNo: busNo, t: t),
                  _legend(t),
                  _liveTag(t, r),
                ],
              ),
      ),
    );
  }

  Widget _placeholder(LyneTheme t, bool loading) {
    return Container(
      color: t.isDark ? const Color(0xFF0F0F0D) : const Color(0xFFEEEBE4),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading) CircularProgressIndicator(color: t.dim, strokeWidth: 2),
          if (loading) const SizedBox(height: 8),
          Text(
            loading ? 'Loading route…' : 'Route unavailable',
            style: t.sans(12).copyWith(color: t.dim),
          ),
        ],
      ),
    );
  }

  Widget _legend(LyneTheme t) {
    return Positioned(
      top: 8,
      left: 8,
      child: Row(
        children: [
          _chip(t, t.live, 'BUS $busNo'),
          const SizedBox(width: 4),
          _chip(t, t.accent, 'STOP'),
        ],
      ),
    );
  }

  Widget _liveTag(LyneTheme t, RouteInfo r) {
    return Positioned(
      bottom: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          r.busCoord == null ? 'LIVE · LTA · NO BUS GPS' : 'LIVE · LTA',
          style: t.mono(9, weight: FontWeight.w600)
              .copyWith(color: Colors.white, letterSpacing: 0.6),
        ),
      ),
    );
  }

  Widget _chip(LyneTheme t, Color dot, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: t.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(label, style: t.mono(9).copyWith(color: t.dim)),
        ],
      ),
    );
  }
}

// ─── Shared helpers ────────────────────────────────────────────

({double centerLat, double centerLon, double spanLat, double spanLon})
    _frame(RouteInfo r) {
  final you = r.stops[r.youIndex.clamp(0, r.stops.length - 1)];
  final lats = <double>[you.lat];
  final lons = <double>[you.lon];
  final b = r.busCoord;
  if (b != null) {
    lats.add(b.lat);
    lons.add(b.lon);
  }
  final minLat = lats.reduce((a, b) => a < b ? a : b);
  final maxLat = lats.reduce((a, b) => a > b ? a : b);
  final minLon = lons.reduce((a, b) => a < b ? a : b);
  final maxLon = lons.reduce((a, b) => a > b ? a : b);
  return (
    centerLat: (minLat + maxLat) / 2,
    centerLon: (minLon + maxLon) / 2,
    spanLat: ((maxLat - minLat) * 1.6).clamp(0.004, 0.5),
    spanLon: ((maxLon - minLon) * 1.6).clamp(0.004, 0.5),
  );
}

/// Rough conversion from a latitude span to a zoom level (1=world,
/// 21=street). 0.005 deg ≈ ~550m at the equator → zoom 16; bigger
/// spans = smaller zoom.
double _zoomFromSpan(double spanLat) {
  if (spanLat < 0.005) return 16;
  if (spanLat < 0.01) return 15;
  if (spanLat < 0.02) return 14;
  if (spanLat < 0.05) return 13;
  if (spanLat < 0.1) return 12;
  return 11;
}

class _OsmMap extends StatelessWidget {
  const _OsmMap({
    required this.route,
    required this.busNo,
    required this.t,
  });
  final RouteInfo route;
  final String busNo;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    final f = _frame(route);
    final you = route.stops[route.youIndex.clamp(0, route.stops.length - 1)];
    final bus = route.busCoord;
    final user = LocationService.shared.lastLocation; // may be null pre-grant

    return FlutterMap(
      options: MapOptions(
        initialCenter: LatLng(f.centerLat, f.centerLon),
        initialZoom: _zoomFromSpan(f.spanLat),
        // Allow pan + zoom but disable rotation — Singapore transit users
        // don't need rotated maps.
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.pinchZoom |
              InteractiveFlag.drag |
              InteractiveFlag.doubleTapZoom |
              InteractiveFlag.flingAnimation,
        ),
      ),
      children: [
        // OSM tile layer. The user-agent header is required by OSM's
        // tile usage policy — see https://operations.osmfoundation.org/policies/tiles/
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.leyne.leyne',
          maxNativeZoom: 19,
        ),
        MarkerLayer(
          markers: [
            // 1. Your bus stop — accent-coloured pin (Material location
            //    icon, drop-pin shape via icon choice). Distinct from
            //    the bus marker so it reads at a glance.
            Marker(
              point: LatLng(you.lat, you.lon),
              width: 40,
              height: 48,
              alignment: Alignment.topCenter,
              child: _PinShadow(
                color: const Color(0xFF8B5A2B), // accent
                child: const Icon(Icons.location_on,
                    size: 44, color: Color(0xFF8B5A2B)),
              ),
            ),
            // 2. Live bus position — green pill with the service number.
            //    Pill shape + bus icon makes it instantly distinct from
            //    the stop pin.
            if (bus != null)
              Marker(
                point: LatLng(bus.lat, bus.lon),
                width: 64,
                height: 32,
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3C8A4E), // live
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3C8A4E).withValues(alpha: 0.7),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.directions_bus,
                          size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        busNo,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // 3. The user — small blue dot with white ring.
            //    Only drawn once LocationService has produced a reading.
            if (user != null)
              Marker(
                point: LatLng(user.lat, user.lon),
                width: 20,
                height: 20,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E7BFF),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1E7BFF).withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        // OSM license attribution — required by the OSM tile policy.
        // Positioned bottom-left so it doesn't fight the LIVE tag in
        // the bottom-right.
        const RichAttributionWidget(
          alignment: AttributionAlignment.bottomLeft,
          attributions: [
            TextSourceAttribution('OpenStreetMap contributors'),
          ],
        ),
      ],
    );
  }
}

/// Drop-shadow wrapper for a single icon-style marker. The pin icon
/// already encodes the shape; this just adds a soft shadow beneath so
/// it doesn't disappear into the map tiles.
class _PinShadow extends StatelessWidget {
  const _PinShadow({required this.color, required this.child});
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}
