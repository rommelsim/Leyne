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
    // Always-dark immersive chrome, regardless of the app's own light/dark
    // theme — routed through the existing inverse-panel tokens instead of
    // raw Colors.black/white/white60. LyneTheme.light's `contrast`/
    // `contrastFg` pair is ALREADY the dark-panel/light-ink combination
    // (see theme.dart: `contrast` is an inverse panel — dark in light mode,
    // light in dark mode) so using the light palette's inverse tokens here
    // — not `context.t`, which would flip to white in dark mode — is what
    // keeps this screen unconditionally dark on both app themes.
    final inv = LyneTheme.light;
    return Scaffold(
      backgroundColor: inv.contrast,
      appBar: AppBar(
        backgroundColor: inv.contrast,
        surfaceTintColor: Colors.transparent,
        foregroundColor: inv.contrastFg,
        title: Text(
          'MRT System Map',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: inv.contrastFg,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: inv.contrastFg),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Close',
        ),
      ),
      body: _MapBody(t: inv),
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
    // `t` is `LyneTheme.light` here (passed down from MrtMapScreen — see the
    // comment there): its `contrastFg` is white ink, so opacity-scaled
    // variants of it stand in for the old Colors.white60 / translucent-white
    // panel literals while staying token-sourced.
    final onDark60 = t.contrastFg.withValues(alpha: 0.6);
    final panel = t.contrastFg.withValues(alpha: 0.08);
    final buttonBg = t.contrastFg.withValues(alpha: 0.15);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.map_rounded,
              size: 36,
              color: onDark60,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'System map not available',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: t.contrastFg,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'The offline map has not been added yet.',
            style: TextStyle(fontSize: 13, color: onDark60),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _openLtaMap,
            style: FilledButton.styleFrom(
              backgroundColor: buttonBg,
              foregroundColor: t.contrastFg,
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('Open LTA system map'),
          ),
        ],
      ),
    );
  }
}
