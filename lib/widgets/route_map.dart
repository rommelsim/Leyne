// Split route map — Apple Maps on iOS, OpenStreetMap (via flutter_map)
// on Android.
//
// Both providers render the same three things sourced from `RouteInfo`:
//   1. Your bus stop (filled marker, accent colour)
//   2. The live bus position (live colour) — if LTA reports lat/lon for
//      the next bus
//   3. The route polyline through `journeySegment` (bus → your stop +
//      small approach window). Drawing the whole route would connect
//      40–60 stops with straight lines (LTA has no road geometry) →
//      tangled mess. Same fix as legacy.
//
// Why OSM on Android: avoids the Google Cloud + billing requirement
// for `google_maps_flutter`. OSM's tiles are free, no key, no card on
// file. Singapore has excellent OSM coverage. OSM's tile policy
// requires a real user-agent string + attribution visible to users —
// both wired below.
//
// Provider split lives in one file so the Detail screen has a single
// `RouteMap(...)` to compose with. Data layer never imports either
// map package (GeoPoint is provider-neutral); marker / polyline
// conversions happen here.

import 'dart:io';

import 'package:apple_maps_flutter/apple_maps_flutter.dart' as apple;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/data_store.dart';
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
                  _platformMap(r, t),
                  _legend(t),
                  _liveTag(t, r),
                ],
              ),
      ),
    );
  }

  Widget _platformMap(RouteInfo r, LyneTheme t) {
    return Platform.isIOS
        ? _AppleMap(route: r, busNo: busNo)
        : _OsmMap(route: r, busNo: busNo, t: t);
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

// ─── Apple Maps (iOS) ──────────────────────────────────────────

class _AppleMap extends StatelessWidget {
  const _AppleMap({required this.route, required this.busNo});
  final RouteInfo route;
  final String busNo;

  @override
  Widget build(BuildContext context) {
    final f = _frame(route);
    final you = route.stops[route.youIndex.clamp(0, route.stops.length - 1)];
    final segment = journeySegment(route);

    final annotations = <apple.Annotation>{
      apple.Annotation(
        annotationId: apple.AnnotationId('stop'),
        position: apple.LatLng(you.lat, you.lon),
        infoWindow: apple.InfoWindow(title: 'STOP', snippet: you.name),
      ),
    };
    final bus = route.busCoord;
    if (bus != null) {
      annotations.add(apple.Annotation(
        annotationId: apple.AnnotationId('bus'),
        position: apple.LatLng(bus.lat, bus.lon),
        infoWindow: apple.InfoWindow(title: 'Bus $busNo'),
      ));
    }

    final polylines = <apple.Polyline>{
      if (segment.length >= 2)
        apple.Polyline(
          polylineId: apple.PolylineId('route'),
          points: [for (final s in segment) apple.LatLng(s.lat, s.lon)],
          width: 3,
          color: const Color(0xFF8B5A2B), // LyneTheme.light.accent
        ),
    };

    return apple.AppleMap(
      initialCameraPosition: apple.CameraPosition(
        target: apple.LatLng(f.centerLat, f.centerLon),
        zoom: _zoomFromSpan(f.spanLat),
      ),
      annotations: annotations,
      polylines: polylines,
      myLocationEnabled: true,
      compassEnabled: false,
      mapType: apple.MapType.standard,
    );
  }
}

// ─── OpenStreetMap via flutter_map (Android) ───────────────────

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
    final segment = journeySegment(route);
    final bus = route.busCoord;

    return FlutterMap(
      options: MapOptions(
        initialCenter: LatLng(f.centerLat, f.centerLon),
        initialZoom: _zoomFromSpan(f.spanLat),
        // Allow pan + zoom but disable rotation (matches the Apple Maps
        // side; Singapore transit users don't need rotated maps).
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
          userAgentPackageName: 'com.leyne.lyne',
          maxNativeZoom: 19,
        ),
        if (segment.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [for (final s in segment) LatLng(s.lat, s.lon)],
                strokeWidth: 3,
                color: const Color(0xFF8B5A2B), // LyneTheme.light.accent
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            // Your stop pin.
            Marker(
              point: LatLng(you.lat, you.lon),
              width: 36,
              height: 36,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5A2B),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: const Icon(Icons.directions_bus,
                    size: 18, color: Colors.white),
              ),
            ),
            if (bus != null)
              Marker(
                point: LatLng(bus.lat, bus.lon),
                width: 48,
                height: 28,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3C8A4E), // LyneTheme.light.live
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3C8A4E).withValues(alpha: 0.7),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Text(
                    busNo,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
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
