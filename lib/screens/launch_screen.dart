// Launch screen — WhereSia departure-board splash, shown over the app for a
// beat on cold start. Ports ios-native/Leyne/LaunchScreenView.swift: two
// board rules draw across, the eyebrow + wordmark rise and fade in, the six
// official MRT line colours stagger in one by one (the app's "colour = data"
// signature), a small live dot pulses, then everything fades + scales out to
// reveal the app underneath. Tap anywhere to skip early. Reduce Motion gets
// a still, fully-revealed frame and an earlier dismiss.
//
// Wired in main.dart's `_AppRoot` as a layer over the root Stack (see
// `_launching`), shown on EVERY cold start — first-run installs included —
// mirroring RootView.swift, where LaunchScreenView sits at the top zIndex
// unconditionally and reveals whichever screen is underneath (OnboardingView
// there, OnboardingScreen here) once it finishes. So on a fresh install this
// splash plays FIRST, then OnboardingScreen's own welcome step appears
// (which repeats the same eyebrow/wordmark/line-capsule beat, just without
// the staged reveal) — the same order iOS uses, and the reason onboarding's
// permission primers (steps 2–3) can never fire a system prompt while this
// splash is still covering the screen: nothing behind it is reachable until
// [onDone] fires.
//
// This widget never removes itself from the tree — it calls [onDone] once
// the reveal (or a tap-to-skip) finishes, and the caller stops rendering it.

import 'package:flutter/material.dart';

import '../theme.dart';

class LaunchScreen extends StatefulWidget {
  const LaunchScreen({super.key, required this.onDone});

  /// Fired once, when the staged reveal completes (or the user taps to skip
  /// early). The caller is responsible for no longer building this widget.
  final VoidCallback onDone;

  @override
  State<LaunchScreen> createState() => _LaunchScreenState();
}

class _LaunchScreenState extends State<LaunchScreen>
    with TickerProviderStateMixin {
  // Drives the whole staged reveal (rules → eyebrow → wordmark → line
  // capsules → caption) as fractions of one 0..1 timeline — mirrors the set
  // of individually-delayed `withAnimation` calls in LaunchScreenView.run().
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  );

  // A slow, continuous pulse for the live dot. Only ticks once the caption
  // itself has faded in (it sits behind the same _FadeRise), so starting it
  // immediately is harmless — it's invisible until then.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  // Fade + slight scale-up exit, fired by either the auto-dismiss timer or a
  // tap. `_leaving` mirrors LaunchScreenView's single-shot `leaving` guard so
  // a tap during the exit animation can't restart or double-fire onDone.
  late final AnimationController _leave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  bool _leaving = false;

  /// The six official MRT line colours, NS/EW/NE/CC/DT/TE — same order as
  /// the onboarding welcome step and OnboardingView.swift's `lineOrder`.
  static const List<MRTLine> _lineOrder = [
    MRTLine.ns,
    MRTLine.ew,
    MRTLine.ne,
    MRTLine.cc,
    MRTLine.dt,
    MRTLine.te,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  void _run() {
    if (!mounted) return;
    if (MediaQuery.of(context).disableAnimations) {
      // Still frame: jump both controllers straight to their fully-revealed
      // value (no forward() call, so nothing actually ticks) and dismiss
      // sooner — mirrors LaunchScreenView.run()'s `reduceMotion` branch.
      _enter.value = 1;
      _pulse.value = 1;
      Future.delayed(const Duration(milliseconds: 1000), () {
        _dismiss(const Duration(milliseconds: 300));
      });
      return;
    }
    _pulse.repeat(reverse: true);
    _enter.forward();
    _enter.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _dismiss(const Duration(milliseconds: 450));
      }
    });
  }

  void _dismiss(Duration duration) {
    if (_leaving) return;
    _leaving = true;
    _leave.duration = duration;
    _leave.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _enter.dispose();
    _pulse.dispose();
    _leave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    final content = Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: t.bg)),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 44),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Rule(t: t, controller: _enter, start: 0.05, end: 0.40),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 26),
                  child: Column(
                    children: [
                      _FadeRise(
                        controller: _enter,
                        start: 0.18,
                        end: 0.45,
                        offset: 8,
                        child: Text(
                          'SINGAPORE · BUS & MRT',
                          style: t
                              .mono(11, weight: FontWeight.w600)
                              .copyWith(color: t.dim, letterSpacing: 2.2),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _FadeRise(
                        controller: _enter,
                        start: 0.30,
                        end: 0.60,
                        offset: 14,
                        child: Text(
                          'WhereSia',
                          style: t.sans(38, weight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < _lineOrder.length; i++) ...[
                            if (i > 0) const SizedBox(width: 7),
                            _FadeRise(
                              controller: _enter,
                              start: 0.46 + i * 0.055,
                              end: 0.66 + i * 0.055,
                              offset: 6,
                              child: Container(
                                width: 22,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: _lineOrder[i].color,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                _Rule(t: t, controller: _enter, start: 0.05, end: 0.40),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 56,
          child: Center(
            child: _FadeRise(
              controller: _enter,
              start: 0.68,
              end: 0.90,
              offset: 0,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Opacity(
                        opacity: 0.35 + _pulse.value * 0.65,
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: t.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'LIVE ARRIVALS · SINGAPORE',
                        style: t
                            .mono(10)
                            .copyWith(color: t.dim, letterSpacing: 2),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );

    // Decorative and transient — excluded from the accessibility tree like a
    // native splash screen, rather than having TalkBack read out a wordmark
    // that's about to disappear on its own.
    return ExcludeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _dismiss(const Duration(milliseconds: 350)),
        child: AnimatedBuilder(
          animation: _leave,
          builder: (context, child) {
            final v = _leave.value;
            return Opacity(
              opacity: 1 - v,
              child: Transform.scale(
                scale: reduceMotion ? 1.0 : 1.0 + v * 0.04,
                child: child,
              ),
            );
          },
          child: content,
        ),
      ),
    );
  }
}

/// Fades + rises [child] in over [start]→[end] (fractions of [controller]'s
/// 0..1 timeline). Reduce Motion is handled upstream by [controller] jumping
/// straight to `1.0` without ever ticking, which — through this exact same
/// interval math — renders as a static, fully-revealed frame with no
/// separate code path needed here.
class _FadeRise extends StatelessWidget {
  const _FadeRise({
    required this.controller,
    required this.start,
    required this.end,
    required this.offset,
    required this.child,
  });

  final Animation<double> controller;
  final double start;
  final double end;
  final double offset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, kid) {
        final raw = ((controller.value - start) / (end - start)).clamp(
          0.0,
          1.0,
        );
        final v = Curves.easeOutCubic.transform(raw);
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, (1 - v) * offset),
            child: kid,
          ),
        );
      },
      child: child,
    );
  }
}

/// A board rule that draws from leading to trailing over [start]→[end] —
/// mirrors LaunchScreenView.swift's `rule`.
class _Rule extends StatelessWidget {
  const _Rule({
    required this.t,
    required this.controller,
    required this.start,
    required this.end,
  });

  final LyneTheme t;
  final Animation<double> controller;
  final double start;
  final double end;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final raw = ((controller.value - start) / (end - start)).clamp(
          0.0,
          1.0,
        );
        final v = Curves.easeInOutCubic.transform(raw);
        return Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: v,
            child: Container(height: 1, color: t.line),
          ),
        );
      },
    );
  }
}
