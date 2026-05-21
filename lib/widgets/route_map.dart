// Split route map — Apple Maps on iOS, OpenStreetMap (via flutter_map)
// on Android.
//
// Both providers render three points:
//   1. Your bus stop — accent-coloured pin
//   2. The live bus position — green badge with the service number,
//      if LTA reports lat/lon for the next bus
//   3. The user's current location — iOS shows its native blue dot via
//      myLocationEnabled; Android draws a small blue dot using the
//      latest LocationService reading
//
// The route polyline was removed (was visually noisy — LTA has no road
// geometry so straight lines between stops looked like a tangle on
// turns). The three points alone communicate "where the bus is now,
// where your stop is, where you are." Route progress as a list of
// stops lives in the RouteProgress widget below the map.
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
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apple_maps_flutter/apple_maps_flutter.dart' as apple;
import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
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

class _AppleMap extends StatefulWidget {
  const _AppleMap({required this.route, required this.busNo});
  final RouteInfo route;
  final String busNo;

  @override
  State<_AppleMap> createState() => _AppleMapState();
}

class _AppleMapState extends State<_AppleMap> {
  // Custom marker bitmaps — generated once in initState as PNG bytes
  // from the Material icon glyphs, then handed to apple_maps_flutter via
  // BitmapDescriptor.fromBytes. apple_maps_flutter has no built-in
  // "use this Flutter widget as a marker" so we render to PNG ourselves.
  apple.BitmapDescriptor? _stopIcon;
  apple.BitmapDescriptor? _busIcon;

  @override
  void initState() {
    super.initState();
    _loadMarkers();
  }

  Future<void> _loadMarkers() async {
    // Stop pin — accent-coloured circle with the location icon.
    final stopBytes = await _drawIconMarker(
      icon: Icons.location_on,
      fillColor: const Color(0xFF8B5A2B), // LyneTheme.light.accent
    );
    // Bus marker — green circle with the directions_bus icon.
    final busBytes = await _drawIconMarker(
      icon: Icons.directions_bus,
      fillColor: const Color(0xFF3C8A4E), // LyneTheme.light.live
    );
    if (!mounted) return;
    setState(() {
      _stopIcon = apple.BitmapDescriptor.fromBytes(stopBytes);
      _busIcon = apple.BitmapDescriptor.fromBytes(busBytes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = _frame(widget.route);
    final you = widget.route
        .stops[widget.route.youIndex.clamp(0, widget.route.stops.length - 1)];

    final annotations = <apple.Annotation>{
      apple.Annotation(
        annotationId: apple.AnnotationId('stop'),
        position: apple.LatLng(you.lat, you.lon),
        icon: _stopIcon ?? apple.BitmapDescriptor.defaultAnnotation,
        infoWindow: apple.InfoWindow(title: 'STOP', snippet: you.name),
      ),
    };
    final bus = widget.route.busCoord;
    if (bus != null) {
      annotations.add(apple.Annotation(
        annotationId: apple.AnnotationId('bus'),
        position: apple.LatLng(bus.lat, bus.lon),
        icon: _busIcon ?? apple.BitmapDescriptor.defaultAnnotation,
        infoWindow: apple.InfoWindow(title: 'Bus ${widget.busNo}'),
      ));
    }

    return apple.AppleMap(
      initialCameraPosition: apple.CameraPosition(
        target: apple.LatLng(f.centerLat, f.centerLon),
        zoom: _zoomFromSpan(f.spanLat),
      ),
      annotations: annotations,
      myLocationEnabled: true,
      compassEnabled: false,
      mapType: apple.MapType.standard,
      // The map is a UIKit platform view embedded in the Detail screen's
      // scrolling ListView. Without claiming gestures eagerly, the parent
      // scroll view wins the arena and pan/zoom never reach the map.
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
      },
    );
  }
}

/// Render a Material icon onto a coloured circle and return the result
/// as PNG bytes. apple_maps_flutter accepts these via
/// BitmapDescriptor.fromBytes for a fully custom annotation glyph,
/// bypassing Apple's default red-pin look.
///
/// The drawing happens directly on a Canvas (not via a widget tree),
/// which avoids the off-screen-rendering rigmarole. Material icons
/// resolve via the standard 'MaterialIcons' font that Flutter loads at
/// startup, so the glyph just becomes a single character we paint with
/// TextPainter.
Future<Uint8List> _drawIconMarker({
  required IconData icon,
  required Color fillColor,
  Color iconColor = Colors.white,
  Color borderColor = Colors.white,
  double size = 88,
  double borderWidth = 4,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final centre = Offset(size / 2, size / 2);
  final radius = size / 2;

  // Soft drop shadow behind the circle for separation from map tiles.
  final shadow = Paint()
    ..color = Colors.black.withValues(alpha: 0.28)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
  canvas.drawCircle(centre + const Offset(0, 2), radius - 2, shadow);

  // Filled circle.
  canvas.drawCircle(centre, radius - borderWidth, Paint()..color = fillColor);

  // White border.
  canvas.drawCircle(
    centre,
    radius - borderWidth / 2,
    Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth,
  );

  // Icon glyph — Material icons are font characters indexed by codePoint.
  final glyph = TextPainter(textDirection: TextDirection.ltr)
    ..text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: size * 0.55,
        color: iconColor,
      ),
    )
    ..layout();
  glyph.paint(
    canvas,
    Offset((size - glyph.width) / 2, (size - glyph.height) / 2),
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(size.toInt(), size.toInt());
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
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
    final bus = route.busCoord;
    final user = LocationService.shared.lastLocation; // may be null pre-grant

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
            // 3. The user — small blue dot with white ring, iOS-style.
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
