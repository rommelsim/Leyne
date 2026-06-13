// MrtMapScreen — full-screen zoomable MRT system map.
//
// Flutter/Android port of ios-native/Leyne/V2/MrtMapView.swift.
//
// Wraps the bundled `assets/mrt_system_map.png` (when present) in an
// InteractiveViewer so the user can pinch-zoom and pan the full system map.
//
// The PNG asset is NOT registered in pubspec.yaml yet — the file doesn't
// exist on disk, so adding it would break the build. When the user drops the
// PNG into `assets/` and adds it to pubspec.yaml, the InteractiveViewer will
// light up automatically. Until then, Image.asset's errorBuilder renders a
// clean fallback: an icon + label + a button to open the LTA online map.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme.dart';

class MrtMapScreen extends StatelessWidget {
  const MrtMapScreen({super.key});

  static const _ltaMapUrl =
      'https://www.lta.gov.sg/content/ltagov/en/map/train.html';

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text(
          'MRT System Map',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Close',
        ),
      ),
      body: _MapBody(t: t),
    );
  }
}

class _MapBody extends StatelessWidget {
  const _MapBody({required this.t});

  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 1.0,
      maxScale: 5.0,
      clipBehavior: Clip.none,
      child: Center(
        child: Image.asset(
          'assets/mrt_system_map.png',
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => _MapFallback(t: t),
        ),
      ),
    );
  }
}

// ─── Fallback (asset not yet bundled) ────────────────────────────────────────

class _MapFallback extends StatelessWidget {
  const _MapFallback({required this.t});

  final LyneTheme t;

  Future<void> _openLtaMap() async {
    final uri = Uri.parse(MrtMapScreen._ltaMapUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color.fromRGBO(255, 255, 255, 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.map_rounded,
              size: 36,
              color: Colors.white60,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'System map not available',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'The offline map has not been added yet.',
            style: TextStyle(fontSize: 13, color: Colors.white60),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _openLtaMap,
            style: FilledButton.styleFrom(
              backgroundColor: const Color.fromRGBO(255, 255, 255, 0.15),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('Open LTA system map'),
          ),
        ],
      ),
    );
  }
}
