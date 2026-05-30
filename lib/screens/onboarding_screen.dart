// Onboarding — 6-step intro. Ports legacy/ios-native/Lyne/OnboardingView.swift.
//
// Flow:
//   • Steps 0–3 are pure marketing (hero, pin stack, narrow checklist,
//     notification mock).
//   • Step 4 primes the iOS location prompt — tapping Continue calls
//     `onRequestLocation` (LocationService.requestAndStart) and advances.
//   • Step 5 primes the ad/ATT prompts — tapping Continue calls
//     `onRequestTracking` (AdConsent.gatherThenStart) which is responsible
//     for closing onboarding when consent + ATT + Mobile Ads init resolve.
//
// There is no Skip: onboarding completes only by advancing through the final
// step, so the location / notification / ads priming always runs.

import 'package:flutter/material.dart';

import '../theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onRequestLocation,
    required this.onRequestNotifications,
    required this.onRequestTracking,
  });

  /// Step 4 (location-prime) Continue. Implementations should call
  /// LocationService.requestAndStart and return — the step advances on its
  /// own; the OS dialog races with the transition, which matches the
  /// legacy iOS behaviour.
  final VoidCallback onRequestLocation;

  /// Step 3 (notifications-prime) Continue. Implementations should call
  /// AppModel.setNotificationsEnabled(true), which fires the Android 13+
  /// POST_NOTIFICATIONS prompt (and SCHEDULE_EXACT_ALARM on 14+) before
  /// scheduling alerts. Same fire-and-forget shape as onRequestLocation.
  final VoidCallback onRequestNotifications;

  /// Step 5 (ads/ATT prime) Continue. Implementations should run UMP →
  /// ATT → MobileAds.initialize, then dismiss onboarding. The button does
  /// NOT advance the step; the caller drives dismissal.
  final VoidCallback onRequestTracking;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnbStep {
  const _OnbStep({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.cta,
  });
  final String eyebrow;
  final String title;
  final String subtitle;
  final String cta;
}

const List<_OnbStep> _steps = [
  _OnbStep(
    eyebrow: 'LEYNE',
    title: 'Right on cue.',
    subtitle:
        'A small card on your home screen tells you when your bus is close — so you can stop reaching for your phone.',
    cta: 'Continue',
  ),
  _OnbStep(
    eyebrow: 'STEP 1 · PIN',
    title: 'Your bus stops, always on top.',
    subtitle:
        'Pin the stops you actually use. Rename them. Reorder them. Live arrivals update in the background.',
    cta: 'Continue',
  ),
  _OnbStep(
    eyebrow: 'STEP 2 · NARROW',
    title: 'Pick the buses you ride.',
    subtitle:
        'A stop can serve a dozen routes. Track only the ones you actually take — the rest stay out of your way.',
    cta: 'Continue',
  ),
  _OnbStep(
    eyebrow: 'STEP 3 · STAY PRESENT',
    title: 'We’ll buzz when it’s close.',
    subtitle:
        'Set notify-at-2-min on any stop. Put the phone away. You’ll know in time to walk over.',
    cta: 'Continue',
  ),
  _OnbStep(
    eyebrow: 'STEP 4 · LOCATION',
    title: 'See stops near you.',
    subtitle:
        'We use your location only to find bus stops within walking distance. It stays on your device, is never sold, and you can change this anytime in Settings.',
    cta: 'Continue',
  ),
  _OnbStep(
    eyebrow: 'STEP 5 · ADS',
    title: 'Free, thanks to ads.',
    subtitle:
        'Leyne is free because it shows ads. With your permission they can be more relevant to you; decline and you’ll still get ads and every feature — entirely your choice.',
    cta: 'Continue',
  ),
];

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  // +1 = forward (slide in from right), -1 = back (slide in from left).
  // Drives the AnimatedSwitcher transition so Back doesn't look like Next.
  int _direction = 1;
  // Locks Back / Continue against rapid multi-taps. Without it, a fast
  // double-tap on the location step advances to the ATT step and fires
  // onRequestTracking() while the iOS location prompt is still on screen —
  // iOS then silently drops the ATT prompt (it won't stack two permission
  // dialogs). It also stops a double-tap on the ATT step from running
  // onRequestTracking() twice and dismissing onboarding before ATT resolves.
  bool _busy = false;
  static const _anim = Duration(milliseconds: 280);
  static const _curve = Curves.easeOutCubic;

  // Re-enable the nav buttons once the slide transition has settled.
  void _unlockAfterTransition() {
    Future.delayed(_anim + const Duration(milliseconds: 140), () {
      if (mounted) setState(() => _busy = false);
    });
  }

  void _next() {
    if (_busy) return;
    final last = _steps.length - 1;
    if (_step == 3) {
      // Notifications prime: advance + kick the POST_NOTIFICATIONS
      // prompt. Same shape as the location prime — the OS dialog races
      // with the transition, which is fine for one-off permissions.
      setState(() {
        _busy = true;
        _direction = 1;
        _step += 1;
      });
      widget.onRequestNotifications();
      _unlockAfterTransition();
    } else if (_step == last - 1) {
      // Location prime: advance + kick the OS prompt. Stay locked through
      // the transition so a second tap can't jump to the ATT step and
      // race its prompt against the location one.
      setState(() {
        _busy = true;
        _direction = 1;
        _step += 1;
      });
      widget.onRequestLocation();
      _unlockAfterTransition();
    } else if (_step == last) {
      // ATT/Ads prime: lock the button for good — the caller dismisses
      // onboarding once consent + ATT + Mobile Ads init resolve.
      setState(() => _busy = true);
      widget.onRequestTracking();
    } else {
      setState(() {
        _busy = true;
        _direction = 1;
        _step += 1;
      });
      _unlockAfterTransition();
    }
  }

  void _back() {
    if (_step == 0) return;
    // On every step except the final, _busy guards rapid taps during the
    // slide transition. The final (ATT) step intentionally leaves _busy
    // set after Continue is tapped — the caller dismisses onboarding when
    // consent resolves. But Back must still work there, otherwise a
    // stalled consent flow would trap the user (there is no Skip).
    // Matches iOS, which only disables Continue (not Back) on the final.
    final isFinal = _step == _steps.length - 1;
    if (_busy && !isFinal) return;
    setState(() {
      _busy = true;
      _direction = -1;
      _step -= 1;
    });
    _unlockAfterTransition();
  }

  Widget _visualFor(int i, LyneTheme t) {
    switch (i) {
      case 0:
        return _OnbVisualHero(t: t);
      case 1:
        return const _OnbVisualStack();
      case 2:
        return const _OnbVisualNarrow();
      case 3:
        return _OnbVisualNotification(t: t);
      case 4:
        return _OnbVisualLocation(t: t);
      default:
        return _OnbVisualTracking(t: t);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final s = _steps[_step];

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              // Top bar: Back only. Skip was removed so every user passes
              // through the location + notification + ads/ATT priming steps;
              // onboarding completes only by reaching the final step.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Row(
                  children: [
                    Opacity(
                      opacity: _step > 0 ? 1 : 0,
                      child: TextButton.icon(
                        onPressed: (_step > 0 && !_busy) ? _back : null,
                        icon: Icon(Icons.chevron_left,
                            size: 18, color: t.accent),
                        label: Text('Back',
                            style: t.sans(15).copyWith(color: t.accent)),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),

              // Visual.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: _anim,
                      switchInCurve: _curve,
                      switchOutCurve: _curve,
                      transitionBuilder: (child, anim) {
                        final dir = _direction.toDouble();
                        // Incoming slides in from `dir` side; outgoing
                        // exits to the opposite side, so Back actually
                        // looks like Back.
                        final isOutgoing =
                            anim.status == AnimationStatus.reverse;
                        final slide = Tween<Offset>(
                          begin: Offset(
                              isOutgoing ? -dir * 0.15 : dir * 0.15, 0),
                          end: Offset.zero,
                        ).animate(anim);
                        return FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: slide,
                            child: child,
                          ),
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey(_step),
                        // FittedBox scales the mock down on small screens
                        // (and the constrained test viewport) so the
                        // intrinsic size of the card stack never overflows.
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: _visualFor(_step, t),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Copy.
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.eyebrow,
                      style: t
                          .mono(11)
                          .copyWith(color: t.dim, letterSpacing: 1.4),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      s.title,
                      style: t.sans(30, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      s.subtitle,
                      style: t.sans(15).copyWith(color: t.dim, height: 1.35),
                    ),
                  ],
                ),
              ),

              // Dots + CTA.
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _steps.length; i++)
                          AnimatedContainer(
                            duration: _anim,
                            margin:
                                const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _step ? 20 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: i == _step ? t.accent : t.line,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy ? null : _next,
                        style: FilledButton.styleFrom(
                          backgroundColor: t.accent,
                          foregroundColor: Colors.white,
                          // Keep the button visually identical while the
                          // multi-tap lock is engaged — the guard should be
                          // invisible, not a grey flicker between steps.
                          disabledBackgroundColor: t.accent,
                          disabledForegroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          s.cta,
                          style: t
                              .sans(16, weight: FontWeight.w600)
                              .copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Visual mocks ───────────────────────────────────────────

class _OnbVisualCard extends StatelessWidget {
  const _OnbVisualCard({
    required this.label,
    required this.stop,
    required this.no,
    required this.dest,
    required this.eta,
    this.arriving = false,
  });

  final String label;
  final String stop;
  final String no;
  final String dest;
  final String eta;
  final bool arriving;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: arriving ? t.live : t.line),
          boxShadow: [
            BoxShadow(
              color: arriving
                  ? t.live.withValues(alpha: 0.19)
                  : Colors.black.withValues(alpha: 0.05),
              blurRadius: arriving ? 15 : 7,
              offset: Offset(0, arriving ? 8 : 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '✎ ${label.toUpperCase()} · STOP $stop',
                      style: t
                          .mono(10)
                          .copyWith(color: t.dim, letterSpacing: 0.8),
                    ),
                  ),
                  if (arriving) _PulseDot(color: t.live),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(dest,
                  style: t.sans(16, weight: FontWeight.w600)),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: arriving ? t.liveBg : Colors.transparent,
                border: Border(top: BorderSide(color: t.line)),
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(18)),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Text(no,
                        style: t.mono(20, weight: FontWeight.w700)),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text(dest,
                            style: t.sans(12).copyWith(color: t.dim)),
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          eta,
                          style: t.mono(24, weight: FontWeight.w500).copyWith(
                              color: arriving ? t.live : t.fg),
                        ),
                        const SizedBox(width: 3),
                        Text('min',
                            style: t.sans(11).copyWith(color: t.dim)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnbVisualHero extends StatelessWidget {
  const _OnbVisualHero({required this.t});
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    final dark = t.isDark;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.2,
            colors: dark
                ? const [
                    Color(0xFF2A2725),
                    Color(0xFF14110F),
                    Color(0xFF08070A),
                  ]
                : const [
                    Color(0xFFF8EEDB),
                    Color(0xFFE9D8B8),
                    Color(0xFFC9B696),
                  ],
          ),
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.45 : 0.18),
              blurRadius: 25,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 32, 0, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Monday, 18 May',
                  style: t
                      .sans(11)
                      .copyWith(color: (dark ? Colors.white : const Color(0xFF111111))
                          .withValues(alpha: 0.78))),
              const SizedBox(height: 2),
              Text(
                '9:41',
                style: TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w200,
                  letterSpacing: -2.2,
                  color: dark ? Colors.white : const Color(0xFF111111),
                ),
              ),
              const SizedBox(height: 20),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: _OnbVisualCard(
                  label: 'Morning',
                  stop: '53061',
                  no: '88',
                  dest: 'Bef Bishan Stn',
                  eta: '2',
                  arriving: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnbVisualStack extends StatelessWidget {
  const _OnbVisualStack();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          _OnbVisualCard(
            label: 'Morning',
            stop: '53061',
            no: '88',
            dest: 'Bef Bishan Stn',
            eta: '2',
            arriving: true,
          ),
          SizedBox(height: 10),
          _OnbVisualCard(
            label: 'Evening',
            stop: '53241',
            no: '174',
            dest: 'Opp Blk 211',
            eta: '9',
          ),
          SizedBox(height: 10),
          _OnbVisualCard(
            label: 'NUS days',
            stop: '01113',
            no: '14',
            dest: 'Bugis Stn',
            eta: '6',
          ),
        ],
      ),
    );
  }
}

class _OnbVisualNarrow extends StatelessWidget {
  const _OnbVisualNarrow();

  static const _rows = <_NarrowRow>[
    _NarrowRow(no: '88', dest: 'Bukit Panjang', eta: '2', on: true, live: true),
    _NarrowRow(no: '156', dest: 'Clementi', eta: '9', on: false, live: false),
    _NarrowRow(no: '410', dest: 'Loop', eta: '4', on: false, live: false),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: t.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Text(
                '✎ MORNING · STOP 53061',
                style: t.mono(10).copyWith(color: t.dim, letterSpacing: 0.8),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text('Bef Bishan Stn',
                  style: t.sans(16, weight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: t.accent.withValues(alpha: 0.25)),
                ),
                child: Text(
                  'Tracking 1 of 3',
                  style: t.mono(10).copyWith(color: t.accent),
                ),
              ),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < _rows.length; i++) ...[
              if (i > 0) Divider(height: 1, color: t.line),
              _buildRow(t, _rows[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRow(LyneTheme t, _NarrowRow r) {
    return Opacity(
      opacity: r.on ? 1 : 0.4,
      child: Container(
        color: r.live ? t.liveBg : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: r.on ? t.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: r.on ? t.accent : t.line, width: 1.5),
              ),
              child: r.on
                  ? const Icon(Icons.check,
                      size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 42,
              child: Text(r.no,
                  style: t.mono(17, weight: FontWeight.w700)),
            ),
            Expanded(
              child: Text('→ ${r.dest}', style: t.sans(13)),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  r.eta,
                  style: t
                      .mono(18, weight: FontWeight.w500)
                      .copyWith(color: r.live ? t.live : t.fg),
                ),
                const SizedBox(width: 2),
                Text('m', style: t.sans(10).copyWith(color: t.dim)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NarrowRow {
  const _NarrowRow({
    required this.no,
    required this.dest,
    required this.eta,
    required this.on,
    required this.live,
  });
  final String no;
  final String dest;
  final String eta;
  final bool on;
  final bool live;
}

class _OnbVisualNotification extends StatelessWidget {
  const _OnbVisualNotification({required this.t});
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    final dark = t.isDark;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Notification banner mock.
          DecoratedBox(
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF2A2925) : const Color(0xFF1A1916),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: t.live),
              boxShadow: [
                BoxShadow(
                  color: t.live.withValues(alpha: 0.2),
                  blurRadius: 18,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t.live,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '88',
                      style: t
                          .mono(15, weight: FontWeight.w700)
                          .copyWith(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'LEYNE · NOW',
                          style: t.mono(10).copyWith(
                                color: const Color(0xFFF2EFE8)
                                    .withValues(alpha: 0.55),
                                letterSpacing: 0.6,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Bus 88 in 2 min',
                          style: t
                              .sans(14, weight: FontWeight.w500)
                              .copyWith(color: const Color(0xFFF2EFE8)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Bef Bishan Stn · time to head down',
                          style: t.sans(11).copyWith(
                                color: const Color(0xFFF2EFE8)
                                    .withValues(alpha: 0.6),
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'INSTEAD OF',
            style:
                t.mono(11).copyWith(color: t.dim, letterSpacing: 1),
          ),
          const SizedBox(height: 14),
          Opacity(
            opacity: 0.55,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: t.line),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.smartphone, size: 18, color: t.fg),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Checking your phone every 30 seconds',
                        style: t.sans(13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnbVisualLocation extends StatelessWidget {
  const _OnbVisualLocation({required this.t});
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return _SystemAlertMock(
      t: t,
      icon: Icons.location_on,
      title: 'Allow “Leyne” to use your location?',
      body:
          'Leyne needs your location to show bus stops within walking distance. You can change this anytime in Settings.',
      buttons: const [
        _AlertButton(label: 'Allow Once', emphasized: true),
        _AlertButton(label: 'Allow While Using App', emphasized: true),
        _AlertButton(label: 'Don’t Allow', emphasized: false),
      ],
    );
  }
}

class _OnbVisualTracking extends StatelessWidget {
  const _OnbVisualTracking({required this.t});
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return _SystemAlertMock(
      t: t,
      icon: Icons.do_not_touch_outlined,
      title:
          'Allow “Leyne” to track your activity across other companies’ apps and websites?',
      body:
          'Leyne uses your device identifier to show ads relevant to you and to keep the app free.',
      buttons: const [
        _AlertButton(label: 'Allow Tracking', emphasized: true),
        _AlertButton(label: 'Ask App Not to Track', emphasized: true),
      ],
    );
  }
}

class _AlertButton {
  const _AlertButton({required this.label, required this.emphasized});
  final String label;
  final bool emphasized;
}

class _SystemAlertMock extends StatelessWidget {
  const _SystemAlertMock({
    required this.t,
    required this.icon,
    required this.title,
    required this.body,
    required this.buttons,
  });

  final LyneTheme t;
  final IconData icon;
  final String title;
  final String body;
  final List<_AlertButton> buttons;

  @override
  Widget build(BuildContext context) {
    final dark = t.isDark;
    return SizedBox(
      width: 270,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF32302A) : const Color(0xFFFCFAF3),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t.accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: Colors.white, size: 18),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: t.sans(15, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style:
                        t.sans(12).copyWith(color: t.dim, height: 1.3),
                  ),
                ],
              ),
            ),
            for (final b in buttons) ...[
              Divider(height: 1, color: t.line),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Text(
                  b.label,
                  style: t.sans(14,
                      weight: b.emphasized
                          ? FontWeight.w500
                          : FontWeight.w400).copyWith(
                    color: b.emphasized ? t.accent : t.fg,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pulsing live-dot used in the hero card mock — soft halo around a solid
/// core. Loops indefinitely while the widget is mounted.
class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color});
  final Color color;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final v = _c.value;
        final haloSize = 8 + 10 * v;
        final haloOpacity = (1 - v) * 0.5;
        return SizedBox(
          width: 18,
          height: 18,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: haloSize,
                height: haloSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: haloOpacity),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
