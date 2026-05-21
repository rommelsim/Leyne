// Postal-code radius map — Apple Maps on iOS, OpenStreetMap (flutter_map)
// on Android.
//
// Shows the geocoded postal-code address as a dark "centre" pin and every
// bus stop within the search radius as a green pin. It's a visual preview
// only — taps happen in the list rendered beneath it on the Search screen,
// so the map needs no navigation callbacks.
//
// Marker colours are fixed (not theme-derived): map tiles are always
// light regardless of the app's light/dark setting, so the pins are tuned
// to read on a light background. Mirrors the provider split + custom
// marker approach in route_map.dart.

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
import '../data/models.dart';
import '../theme.dart';

// Near-black centre pin, mid-green stop pins — both chosen to contrast on
// the light OSM / Apple Maps tiles.
const _kAnchorColor = Color(0xFF1A1916);
const _kStopColor = Color(0xFF2BAA67);

class StopsMap extends StatelessWidget {
  const StopsMap({
    super.key,
    required this.center,
    required this.stops,
    required this.radiusM,
  });

  /// Geocoded postal-code location — the search centre.
  final GeoPoint center;

  /// Bus stops within [radiusM] of [center].
  final List<NearbyStop> stops;
  final int radiusM;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 184,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.line),
        ),
        child: Platform.isIOS
            ? _AppleStopsMap(center: center, stops: stops, radiusM: radiusM)
            : _OsmStopsMap(center: center, stops: stops, radiusM: radiusM),
      ),
    );
  }
}

/// Zoom level chosen so the search radius roughly fills the preview. Both
/// providers use the standard web-mercator zoom scale, so one value fits.
double _zoomForRadius(int radiusM) {
  if (radiusM <= 300) return 15.4;
  if (radiusM <= 600) return 14.5;
  if (radiusM <= 1200) return 13.6;
  return 12.7;
}

// ─── Apple Maps (iOS) ──────────────────────────────────────────

class _AppleStopsMap extends StatefulWidget {
  const _AppleStopsMap({
    required this.center,
    required this.stops,
    required this.radiusM,
  });
  final GeoPoint center;
  final List<NearbyStop> stops;
  final int radiusM;

  @override
  State<_AppleStopsMap> createState() => _AppleStopsMapState();
}

class _AppleStopsMapState extends State<_AppleStopsMap> {
  // apple_maps_flutter has no "Flutter widget as marker" — render the
  // glyphs to PNG bytes ourselves and hand them over as BitmapDescriptors.
  //
  // The descriptors are cached *statically*. Rendering them is async, and
  // until they resolve there's no custom icon to show. Without this cache,
  // every time the map scrolled out of the Search list and back its State
  // was recreated, the icons re-rendered from scratch, and the map briefly
  // showed Apple's default red pin before swapping to the custom green bus
  // marker — the reported red→green flash. Caching across State instances
  // lets the second-and-later builds pick the icons up synchronously, so
  // the flash never recurs.
  static apple.BitmapDescriptor? _cachedAnchorIcon;
  static apple.BitmapDescriptor? _cachedStopIcon;

  apple.BitmapDescriptor? _anchorIcon = _cachedAnchorIcon;
  apple.BitmapDescriptor? _stopIcon = _cachedStopIcon;

  @override
  void initState() {
    super.initState();
    if (_anchorIcon == null || _stopIcon == null) _loadMarkers();
  }

  Future<void> _loadMarkers() async {
    final anchor = await _drawPin(
      icon: Icons.home_rounded,
      fillColor: _kAnchorColor,
      size: 84,
    );
    final stop = await _drawPin(
      icon: Icons.directions_bus_rounded,
      fillColor: _kStopColor,
      size: 64,
    );
    _cachedAnchorIcon = apple.BitmapDescriptor.fromBytes(anchor);
    _cachedStopIcon = apple.BitmapDescriptor.fromBytes(stop);
    if (!mounted) return;
    setState(() {
      _anchorIcon = _cachedAnchorIcon;
      _stopIcon = _cachedStopIcon;
    });
  }

  @override
  Widget build(BuildContext context) {
    final anchorIcon = _anchorIcon;
    final stopIcon = _stopIcon;
    // Only place annotations once the custom icons exist — never fall back
    // to BitmapDescriptor.defaultAnnotation, whose red pin was the wrong
    // marker the user saw flash in. A pinless half-second on the very first
    // render is preferable to showing the wrong icon.
    final annotations = <apple.Annotation>{
      if (anchorIcon != null)
        apple.Annotation(
          annotationId: apple.AnnotationId('center'),
          position: apple.LatLng(widget.center.lat, widget.center.lon),
          icon: anchorIcon,
          infoWindow: const apple.InfoWindow(title: 'Search centre'),
        ),
      if (stopIcon != null)
        for (final s in widget.stops)
          apple.Annotation(
            annotationId: apple.AnnotationId(s.stopCode),
            position: apple.LatLng(s.lat, s.lon),
            icon: stopIcon,
            infoWindow: apple.InfoWindow(
              title: s.stopName,
              snippet: 'Stop ${s.stopCode} · ${s.distanceM} m away',
            ),
          ),
    };

    return apple.AppleMap(
      initialCameraPosition: apple.CameraPosition(
        target: apple.LatLng(widget.center.lat, widget.center.lon),
        zoom: _zoomForRadius(widget.radiusM),
      ),
      annotations: annotations,
      myLocationEnabled: false,
      compassEnabled: false,
      mapType: apple.MapType.standard,
      // Embedded UIKit platform view — claim gestures eagerly so pan/zoom
      // reach the map rather than an enclosing scrollable.
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
      },
    );
  }
}

/// Render a Material icon onto a coloured circle and return PNG bytes for
/// apple_maps_flutter's BitmapDescriptor.fromBytes. Drawing straight onto a
/// Canvas avoids off-screen widget rendering; Material icons are font
/// glyphs, so the icon is just one painted character.
Future<Uint8List> _drawPin({
  required IconData icon,
  required Color fillColor,
  Color iconColor = Colors.white,
  double size = 80,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final centre = Offset(size / 2, size / 2);
  final radius = size / 2;
  const border = 4.0;

  final shadow = Paint()
    ..color = Colors.black.withValues(alpha: 0.3)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
  canvas.drawCircle(centre + const Offset(0, 2), radius - 2, shadow);

  canvas.drawCircle(centre, radius - border, Paint()..color = fillColor);
  canvas.drawCircle(
    centre,
    radius - border / 2,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = border,
  );

  final glyph = TextPainter(textDirection: TextDirection.ltr)
    ..text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: size * 0.52,
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

class _OsmStopsMap extends StatelessWidget {
  const _OsmStopsMap({
    required this.center,
    required this.stops,
    required this.radiusM,
  });
  final GeoPoint center;
  final List<NearbyStop> stops;
  final int radiusM;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(
        initialCenter: LatLng(center.lat, center.lon),
        initialZoom: _zoomForRadius(radiusM),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.pinchZoom |
              InteractiveFlag.drag |
              InteractiveFlag.doubleTapZoom |
              InteractiveFlag.flingAnimation,
        ),
      ),
      children: [
        // OSM tile layer — the user-agent header is required by OSM's tile
        // usage policy (https://operations.osmfoundation.org/policies/tiles/).
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.leyne.leyne',
          maxNativeZoom: 19,
        ),
        MarkerLayer(
          markers: [
            // Stops first, centre last — the centre badge draws on top.
            for (final s in stops)
              Marker(
                point: LatLng(s.lat, s.lon),
                width: 26,
                height: 26,
                child: const _CircleBadge(
                  icon: Icons.directions_bus_rounded,
                  fill: _kStopColor,
                  size: 26,
                ),
              ),
            Marker(
              point: LatLng(center.lat, center.lon),
              width: 36,
              height: 36,
              child: const _CircleBadge(
                icon: Icons.home_rounded,
                fill: _kAnchorColor,
                size: 36,
              ),
            ),
          ],
        ),
        // OSM licence attribution — required by the tile policy.
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

/// A circular icon badge with a white ring + soft shadow — the OSM-side
/// marker, shaped to match the iOS BitmapDescriptor pins.
class _CircleBadge extends StatelessWidget {
  const _CircleBadge({
    required this.icon,
    required this.fill,
    required this.size,
  });
  final IconData icon;
  final Color fill;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Icon(icon, size: size * 0.5, color: Colors.white),
    );
  }
}
