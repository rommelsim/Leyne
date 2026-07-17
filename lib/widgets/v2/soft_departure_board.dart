// SoftDepartureBoard — shared "Nearby transport" primitives (Wave 1 port of
// ios-native/Leyne/WhereSia/WSComponents.swift + WSFormat.swift).
//
// Android stays monochrome: the iOS "Now" plate (solid green + white text +
// green edge tick) becomes a NEUTRAL high-contrast plate (onSurface fill)
// with a neutral edge tick — colour is reserved for the seat/crowd dot only
// (green/amber/red, existing app vocabulary) and MRT line pills elsewhere.
// All entrance/tap/shimmer motion is gated behind
// MediaQuery.disableAnimations (reduce-motion), matching soft_home_screen's
// existing `reduceMotion` convention.

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../theme.dart';

/// True when the platform/user has requested reduced motion. Read once per
/// build via `context` — callers pass this down rather than re-querying.
bool softReduceMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

// ─── Seat/crowd vocabulary (mirrors WSFormat.swift Load extension) ─────────

/// Seat-dot colour — the one deliberate colour exception on an otherwise
/// monochrome row (green seats / amber standing / red limited). Matches the
/// hex values iOS WSFormat.swift uses so the vocabulary is identical cross-
/// platform.
Color softLoadDotColor(Load load) {
  switch (load) {
    case Load.sea:
      return const Color(0xFF1E9245);
    case Load.sda:
      return const Color(0xFFE8890C);
    case Load.lsd:
      return const Color(0xFFE1251B);
  }
}

/// Plain-language seat phrase for a departure row (mirrors wsSeatPhrase).
String softLoadSeatPhrase(Load load) {
  switch (load) {
    case Load.sea:
      return 'Seats available';
    case Load.sda:
      return 'Standing room';
    case Load.lsd:
      return 'Limited standing';
  }
}

// ─── Tap compress (mirrors WSCompressStyle: 98% / 80ms, no ripple/highlight) ─

/// Wraps [child] in a 98%-scale/80ms compress-on-tap, gated behind reduce
/// motion. Use for card-level taps that want the WhereSia "compress" feel
/// instead of a Material ripple (e.g. the departure row itself already gets
/// an InkWell for a11y + ripple; this is for standalone tappable cards that
/// want the quieter WhereSia gesture).
class SoftTapCompress extends StatefulWidget {
  const SoftTapCompress({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;

  @override
  State<SoftTapCompress> createState() => _SoftTapCompressState();
}

class _SoftTapCompressState extends State<SoftTapCompress> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = softReduceMotion(context);
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _pressed && !reduceMotion ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ─── Card (mirrors WSCard: radius 22, strokeless panel, optional eyebrow) ──

/// A strokeless, filled panel with an optional eyebrow title + leading icon.
/// Mirrors WSCard.swift's grammar (uppercase-free sentence-case title here —
/// Android's Eyebrow widget already owns the all-caps convention, so this
/// title is sentence case to avoid a doubled shout).
class SoftCard extends StatelessWidget {
  const SoftCard({super.key, this.title, this.icon, required this.child});

  final String? title;
  final IconData? icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: t.dim),
                  const SizedBox(width: 9),
                ],
                Text(
                  title!,
                  style: t.sans(14, weight: FontWeight.w600, color: t.dim),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }
}

/// Hairline row divider inside a card, matching WSRowDivider.
class SoftRowDivider extends StatelessWidget {
  const SoftRowDivider({super.key});
  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: context.t.line);
}

// ─── Shimmer skeletons (spec: shimmer, never a spinner) ────────────────────

/// A single shimmering placeholder bar — the highlight sweeps left→right
/// every 1.4s; static (no sweep) under reduce-motion.
class SoftShimmerBar extends StatefulWidget {
  const SoftShimmerBar({super.key, this.width, this.height = 14});
  final double? width;
  final double height;

  @override
  State<SoftShimmerBar> createState() => _SoftShimmerBarState();
}

class _SoftShimmerBarState extends State<SoftShimmerBar>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (softReduceMotion(context)) return;
      final c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1400),
      )..repeat();
      setState(() => _c = c);
    });
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final base = Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: t.surfaceHi,
        borderRadius: BorderRadius.circular(widget.height / 2),
      ),
    );
    final c = _c;
    if (c == null) return base;
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.height / 2),
          child: ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (rect) {
              final dx = c.value * 2.6 - 0.8; // sweep left→right
              return LinearGradient(
                colors: [
                  t.surfaceHi,
                  t.line.withValues(alpha: 0.9),
                  t.surfaceHi,
                ],
                stops: const [0.0, 0.5, 1.0],
                begin: Alignment(-1 + dx, 0),
                end: Alignment(0 + dx, 0),
              ).createShader(rect);
            },
            child: base,
          ),
        );
      },
    );
  }
}

/// Skeleton for one departure row: plate + two text bars + an ETA bar.
class SoftSkeletonRow extends StatelessWidget {
  const SoftSkeletonRow({super.key});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SoftShimmerBar(width: 62, height: 46),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: const [
              SoftShimmerBar(width: 130, height: 13),
              SizedBox(height: 7),
              SoftShimmerBar(width: 88, height: 10),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const SoftShimmerBar(width: 46, height: 16),
      ],
    );
  }
}

/// Whole-card skeleton shown before the first nearby stop resolves.
class SoftSkeletonCard extends StatelessWidget {
  const SoftSkeletonCard({super.key});
  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Finding transport near you',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: context.t.surface,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SoftShimmerBar(width: 84, height: 12),
            const SizedBox(height: 14),
            const SoftShimmerBar(width: 190, height: 22),
            const SizedBox(height: 14),
            const SoftShimmerBar(width: 120, height: 11),
            const SizedBox(height: 14),
            const SoftRowDivider(),
            const SizedBox(height: 14),
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              const SoftSkeletonRow(),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Departure row (mirrors WSDepartureRow) ─────────────────────────────────

/// One departure: monochrome plate (neutral edge tick while arriving —
/// deliberately NOT green, per the Android monochrome-plate constraint) +
/// destination + coloured seat dot + seat phrase (+ optional vehicle icons)
/// + stacked next-two ETAs + chevron. Reused by Home's BusStopCard and
/// (future waves) the Stop/Bus detail screens.
class SoftDepartureRow extends StatelessWidget {
  const SoftDepartureRow({
    super.key,
    required this.service,
    required this.onTap,
    this.showsVehicleIcons = false,
  });

  final Service service;
  final VoidCallback onTap;
  final bool showsVehicleIcons;

  /// Live seconds until arrival, recomputed from arrivalDate when present so
  /// the row ticks smoothly with the app-wide 1-second clock.
  static int liveEtaSec(Service s, DateTime now) {
    if (s.arrivalDate != null) {
      return s.arrivalDate!.difference(now).inSeconds.clamp(0, 1 << 30);
    }
    return s.etaSec;
  }

  static int? _liveMin(DateTime? date, int fallbackSec) {
    int sec;
    if (date != null) {
      sec = date.difference(DateTime.now()).inSeconds.clamp(0, 1 << 30);
    } else if (fallbackSec > 0) {
      sec = fallbackSec;
    } else {
      return null;
    }
    return (sec / 60).ceil().clamp(1, 1 << 30);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final now = DateTime.now();
    final sec = liveEtaSec(service, now);
    final isNow = sec < 60;
    final arriving = sec < 120 && service.monitored;
    final minutes = (sec / 60).ceil().clamp(1, 1 << 30);
    final followMin = _liveMin(service.followingDate, service.followingSec);
    final thirdMin = _liveMin(service.thirdDate, 0);
    final sched = !service.monitored;
    final reduceMotion = softReduceMotion(context);

    final noDigits = service.no.length > 3;
    final dest = service.dest.isEmpty ? 'Bus ${service.no}' : service.dest;

    String etaLabel;
    if (isNow) {
      etaLabel = 'Now';
    } else if (arriving) {
      etaLabel = 'Arriving';
    } else {
      etaLabel = '${sched ? '~' : ''}$minutes min';
    }
    String? followLabel;
    if (followMin != null) {
      followLabel = thirdMin != null
          ? '$followMin · $thirdMin min'
          : '$followMin min';
    }

    return Semantics(
      button: true,
      label: _a11y(service, isNow, minutes, followMin, sched),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (isNow)
                  Positioned(
                    left: -12,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 3,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color: t.fg,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Monochrome plate — NOT green even when arriving; a
                    // neutral high-contrast fill + edge tick carries the
                    // "now" state instead (Android monochrome constraint).
                    AnimatedContainer(
                      duration: reduceMotion
                          ? Duration.zero
                          : LyneMotion.standard,
                      curve: Curves.easeOutCubic,
                      width: 62,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isNow ? t.contrast : t.surfaceHi,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        service.no,
                        style: t.mono(
                          noDigits ? 15 : 18,
                          weight: FontWeight.w700,
                          color: isNow ? t.contrastFg : t.fg,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            dest,
                            style: t.sans(
                              15,
                              weight: FontWeight.w600,
                              color: t.fg,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 5),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedContainer(
                                duration: reduceMotion
                                    ? Duration.zero
                                    : LyneMotion.short,
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: softLoadDotColor(service.load),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  softLoadSeatPhrase(service.load),
                                  style: t.sans(
                                    12.5,
                                    weight: FontWeight.w500,
                                    color: t.dim,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (showsVehicleIcons) ...[
                                if (service.deck == Deck.dd) ...[
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.airport_shuttle_rounded,
                                    size: 13,
                                    color: t.faint,
                                  ),
                                ] else if (service.deck == Deck.bd) ...[
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.directions_bus_filled_rounded,
                                    size: 13,
                                    color: t.faint,
                                  ),
                                ],
                                if (service.wab) ...[
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.accessible_rounded,
                                    size: 13,
                                    color: t.faint,
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSwitcher(
                          duration: reduceMotion
                              ? Duration.zero
                              : LyneMotion.short,
                          transitionBuilder: (child, anim) =>
                              FadeTransition(opacity: anim, child: child),
                          child: Text(
                            etaLabel,
                            key: ValueKey(etaLabel),
                            style:
                                (isNow
                                        ? t.sans(19, weight: FontWeight.w800)
                                        : arriving
                                        ? t.sans(16, weight: FontWeight.w800)
                                        : t.sans(19, weight: FontWeight.w800))
                                    .copyWith(color: t.fg),
                          ),
                        ),
                        if (followLabel != null)
                          Text(
                            followLabel,
                            style: t.sans(
                              12.5,
                              weight: FontWeight.w500,
                              color: t.dim,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, size: 16, color: t.faint),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _a11y(Service s, bool isNow, int minutes, int? followMin, bool sched) {
    final parts = <String>[
      isNow
          ? 'Bus ${s.no}, arriving now'
          : 'Bus ${s.no}, ${sched ? 'around ' : ''}$minutes minutes',
    ];
    if (s.dest.isNotEmpty) parts.add('to ${s.dest}');
    parts.add(softLoadSeatPhrase(s.load));
    if (s.wab) parts.add('wheelchair accessible');
    if (followMin != null) parts.add('then $followMin minutes');
    return parts.join(', ');
  }
}

// ─── Forecast bar (mirrors ForecastBar — grows on appear) ──────────────────

/// A single crowd-forecast bar: track height enlarges + label brightens for
/// the current period; the fill grows from the bottom on first build (static
/// under reduce-motion).
class SoftForecastBar extends StatefulWidget {
  const SoftForecastBar({
    super.key,
    required this.fraction,
    required this.time,
    this.isNow = false,
  });

  final double fraction;
  final String time;
  final bool isNow;

  @override
  State<SoftForecastBar> createState() => _SoftForecastBarState();
}

class _SoftForecastBarState extends State<SoftForecastBar> {
  double _grown = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _grown = 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final trackH = widget.isNow ? 58.0 : 44.0;
    final reduceMotion = softReduceMotion(context);
    final grown = reduceMotion ? 1.0 : _grown;
    return Expanded(
      child: Column(
        children: [
          Container(
            height: trackH,
            decoration: BoxDecoration(
              color: t.line,
              borderRadius: BorderRadius.circular(7),
            ),
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
              duration: reduceMotion ? Duration.zero : LyneMotion.emphasis,
              curve: Curves.easeOut,
              height: trackH * widget.fraction.clamp(0, 1) * grown,
              width: double.infinity,
              decoration: BoxDecoration(
                color: t.fg,
                borderRadius: BorderRadius.circular(7),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            widget.time,
            style: t.mono(
              10,
              weight: widget.isNow ? FontWeight.w700 : FontWeight.w400,
              color: widget.isNow ? t.fg : t.dim,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Entrance (fade + rise on first build, mirrors .wsEntrance) ────────────

/// The single staggered-entrance idiom: fades + rises a few px when it first
/// builds, delayed by [delay] so siblings stagger. Gated behind reduce
/// motion (renders fully shown immediately).
class SoftEntrance extends StatefulWidget {
  const SoftEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.rise = 12,
  });

  final Widget child;
  final Duration delay;
  final double rise;

  @override
  State<SoftEntrance> createState() => _SoftEntranceState();
}

class _SoftEntranceState extends State<SoftEntrance> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    final reduceMotion = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    if (reduceMotion) {
      _shown = true;
      return;
    }
    Future.delayed(widget.delay, () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = softReduceMotion(context);
    if (reduceMotion) return widget.child;
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: _shown ? Offset.zero : Offset(0, widget.rise / 100),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
