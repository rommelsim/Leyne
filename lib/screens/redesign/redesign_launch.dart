// Launch splash — animated app mark, wordmark and LTA tagline. Auto-advances
// to onboarding after 2s (driven by the controller).

import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'redesign_common.dart';
import 'redesign_theme.dart';

/// Gradient rounded-square app mark with the bus + train glyph pair. Reused by
/// onboarding's hero.
class RdAppMark extends StatelessWidget {
  const RdAppMark({super.key, this.size = 104, this.glyph = 35, this.radius = 0.34});

  final double size;
  final double glyph;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * radius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2C72E6), Color(0xFF222A38)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2C72E6).withValues(alpha: 0.40),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RdIcon(Symbols.directions_bus, size: glyph, color: const Color(0xFFFFFFFF), fill: 1, weight: 600),
          RdIcon(Symbols.train, size: glyph, color: const Color(0xFFFFFFFF), fill: 1, weight: 600),
        ],
      ),
    );
  }
}

class RdLaunchScreen extends StatefulWidget {
  const RdLaunchScreen({super.key});

  @override
  State<RdLaunchScreen> createState() => _RdLaunchScreenState();
}

class _RdLaunchScreenState extends State<RdLaunchScreen> with TickerProviderStateMixin {
  late final AnimationController _ring =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();
  late final AnimationController _enter =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..forward();

  @override
  void dispose() {
    _ring.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    return Container(
      color: t.surface,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 140,
                  height: 140,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Pulsing ring.
                      AnimatedBuilder(
                        animation: _ring,
                        builder: (_, _) {
                          final v = _ring.value;
                          final scale = 0.5 + v * 1.2; // .5 → 1.7
                          final opacity = v < 0.5 ? 0.0 : (1 - (v - 0.5) / 0.5) * 0.5;
                          return Transform.scale(
                            scale: scale,
                            child: Opacity(
                              opacity: opacity.clamp(0.0, 1.0),
                              child: Container(
                                width: 140,
                                height: 140,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: t.primary, width: 2),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      ScaleTransition(
                        scale: CurvedAnimation(parent: _enter, curve: Curves.easeOutBack),
                        child: const RdAppMark(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                FadeTransition(
                  opacity: _enter,
                  child: Text('SG Transit',
                      style: rdText(size: 26, weight: FontWeight.w900, color: t.onSurface, letterSpacing: -0.26)),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 46,
            child: FadeTransition(
              opacity: _enter,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RdDot(t.bus),
                  const SizedBox(width: 7),
                  Text('Live arrivals · LTA DataMall',
                      style: rdText(size: 12, weight: FontWeight.w600, color: t.onVariant)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
