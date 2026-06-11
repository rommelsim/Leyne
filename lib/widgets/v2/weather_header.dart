// WeatherHeader — monochrome weather readout for the Home screen hero area.
//
// Layout:
//   [gradient backdrop covering this widget's area]
//   Row: greeting + time (HH:mm, ticks each minute via _MinuteTicker)
//   Row: {temp}° · {Condition} · {rain hint?}  + monochrome weather icon
//
// Design constraints:
//   • Fully monochrome — greyscale only. No colour except theme tokens.
//   • Uses t.fg / t.dim / t.faint / t.surface throughout.
//   • Backdrop: soft vertical gradient, opacity-only, varies by condition
//     bucket (clear/cloudy/rain/night) — subtle enough that content stays
//     legible above whatever screen background is beneath.
//   • Graceful: when WeatherStore.snapshot is null the widget renders nothing
//     (zero height) — the rest of the Home layout is unaffected.
//
// The widget is stateful only to drive the per-minute clock tick via a Timer.
// Weather data comes from WeatherStore via a ListenableBuilder in the parent
// (SoftHomeScreen already wraps the body in a ListenableBuilder on DataStore +
// LocationService; we add WeatherStore to that merge set).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/nea_models.dart';
import '../../data/weather_store.dart';
import '../../theme.dart';

// ─── Public entry point ───────────────────────────────────────────────────────

class WeatherHeader extends StatefulWidget {
  const WeatherHeader({super.key});

  @override
  State<WeatherHeader> createState() => _WeatherHeaderState();
}

class _WeatherHeaderState extends State<WeatherHeader> {
  Timer? _minuteTimer;

  @override
  void initState() {
    super.initState();
    _scheduleMinuteTick();
  }

  @override
  void dispose() {
    _minuteTimer?.cancel();
    super.dispose();
  }

  /// Schedule a rebuild at the top of the next minute, then every 60 s.
  /// This keeps the displayed time accurate without rebuilding every second.
  void _scheduleMinuteTick() {
    final now = DateTime.now();
    final secondsUntilNextMinute = 60 - now.second;
    _minuteTimer = Timer(Duration(seconds: secondsUntilNextMinute), () {
      if (mounted) setState(() {});
      // After the first alignment, tick every 60 s.
      _minuteTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // ListenableBuilder is in the parent; we read the store directly here.
    final snap = WeatherStore.shared.snapshot;
    if (snap == null) return const SizedBox.shrink();

    final t = context.t;
    final now = DateTime.now();
    final timeStr = _formatTime(now);
    final greeting = _greeting(now.hour);

    return _WeatherBackdrop(
      condition: snap.condition,
      isDark: t.isDark,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Greeting + clock row
            Row(
              children: [
                Expanded(
                  child: Text(
                    greeting,
                    style: t.sans(13, weight: FontWeight.w500, color: t.dim),
                  ),
                ),
                Text(
                  timeStr,
                  style: t.mono(13,
                      weight: FontWeight.w600, color: t.dim),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Weather readout row
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _ConditionLine(snap: snap, t: t),
                ),
                const SizedBox(width: 10),
                _WeatherIcon(condition: snap.condition, t: t),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String _greeting(int hour) {
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    if (hour < 20) return 'Good evening';
    return 'Good night';
  }
}

// ─── Condition text line ──────────────────────────────────────────────────────

class _ConditionLine extends StatelessWidget {
  const _ConditionLine({required this.snap, required this.t});

  final WeatherSnapshot snap;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    final parts = <InlineSpan>[];

    // Temperature
    parts.add(TextSpan(
      text: '${snap.tempRounded}°',
      style: t.mono(22, weight: FontWeight.w700, color: t.fg),
    ));

    // Condition
    parts.add(TextSpan(
      text: '  ${snap.forecastText}',
      style: t.sans(14, weight: FontWeight.w500, color: t.dim),
    ));

    // Optional rain hint
    final hint = snap.rainHint;
    if (hint != null) {
      parts.add(TextSpan(
        text: '  ·  $hint',
        style: t.sans(13, color: t.faint),
      ));
    }

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: parts),
    );
  }
}

// ─── Monochrome weather icon ──────────────────────────────────────────────────

class _WeatherIcon extends StatelessWidget {
  const _WeatherIcon({required this.condition, required this.t});

  final WeatherCondition condition;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return Icon(
      _iconFor(condition),
      size: 24,
      color: t.dim,
    );
  }

  static IconData _iconFor(WeatherCondition c) => switch (c) {
        WeatherCondition.rain => Icons.grain_rounded,
        WeatherCondition.cloudy => Icons.cloud_rounded,
        WeatherCondition.night => Icons.nights_stay_rounded,
        WeatherCondition.clear => Icons.wb_sunny_rounded,
      };
}

// ─── Monochrome gradient backdrop ────────────────────────────────────────────

/// Wraps `child` in a vertically-graduated greyscale backdrop that varies
/// slightly in opacity by weather condition. The gradient is purely
/// opacity-based on the theme surface colour — zero colour introduced.
///
/// Condition opacity ranges (top → bottom), both modes:
///   clear  → 0.00 → 0.06  (barely there — bright day needs the least)
///   cloudy → 0.00 → 0.10  (slightly more depth)
///   rain   → 0.04 → 0.14  (heavier cloud feel)
///   night  → 0.06 → 0.18  (deepest — dark sky)
class _WeatherBackdrop extends StatelessWidget {
  const _WeatherBackdrop({
    required this.condition,
    required this.isDark,
    required this.child,
  });

  final WeatherCondition condition;
  final bool isDark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final (topAlpha, bottomAlpha) = _alphas(condition);

    // In dark mode, the tint is white; in light mode, it's black.
    // Using a fixed hue (white/black) ensures monochrome compliance.
    final tintBase = isDark ? Colors.white : Colors.black;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tintBase.withValues(alpha: topAlpha),
            tintBase.withValues(alpha: bottomAlpha),
          ],
        ),
      ),
      child: child,
    );
  }

  static (double top, double bottom) _alphas(WeatherCondition c) =>
      switch (c) {
        WeatherCondition.clear => (0.00, 0.06),
        WeatherCondition.cloudy => (0.00, 0.10),
        WeatherCondition.rain => (0.04, 0.14),
        WeatherCondition.night => (0.06, 0.18),
      };
}
