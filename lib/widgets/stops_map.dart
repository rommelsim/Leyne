// Postal-code radius map — OpenStreetMap via flutter_map.
//
// Shows the geocoded postal-code address as a dark "centre" pin and every
// bus stop within the search radius as a green pin. It's a visual preview
// only — taps happen in the list rendered beneath it on the Search screen,
// so the map needs no navigation callbacks.
//
// Marker colours are fixed (not theme-derived): OSM tiles are always
// light regardless of the app's light/dark setting, so the pins are tuned
// to read on a light background.
//
// This widget is Android-only — iOS shipping now ships via the
// SwiftUI app at `ios-native/` which renders the equivalent view with
// MapKit. The Flutter Apple Maps path was removed when Flutter became
// Android-only.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/data_store.dart';
import '../data/models.dart';
import '../theme.dart';

// Near-black centre pin, mid-green stop pins — chosen to contrast on
// the light OSM tiles.
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
        child: FlutterMap(
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
                      // directions_bus_rounded read as a live vehicle, not a
                      // place. Use location_on (drop-pin) — the standard
                      // Material marker for a fixed point of interest.
                      icon: Icons.location_on,
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
        ),
      ),
    );
  }
}

/// Zoom level chosen so the search radius roughly fills the preview.
double _zoomForRadius(int radiusM) {
  if (radiusM <= 300) return 15.4;
  if (radiusM <= 600) return 14.5;
  if (radiusM <= 1200) return 13.6;
  return 12.7;
}

/// A circular icon badge with a white ring + soft shadow.
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
