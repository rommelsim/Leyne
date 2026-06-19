// Onboarding — 5-step first-run flow mirroring ios-native/Leyne/OnboardingView.swift.
//
// Flow:
//   step 0  welcome         — wordmark, tagline, "Get started"
//   step 1  live wedge      — "WHY LEYNE / Always up to the minute" + 3-row card
//   step 2  location primer — "Permission 1 of 2", primes OS location prompt
//   step 3  notif primer    — "Permission 2 of 2", primes POST_NOTIFICATIONS
//   step 4  done            — grant summary + "Enter Leyne" → onFinish
//
// Android differences from iOS:
//   • No ATT / App Tracking Transparency step (Android has none).
//   • Permission counters are "of 2" not "of 3".
//   • Done summary shows Location + Notifications only (no Ad tracking row).
//   • onFinish (not onRequestTracking) drives completion — the caller runs
//     AdConsent.gatherThenStart (UMP only, no ATT) and finishOnboarding().
//
// Transition: the ENTIRE per-step content — visual/copy/buttons — lives inside
// a single AnimatedSwitcher keyed by step index so text, cards, and CTAs all
// slide as one unit. Persistent chrome (back row, dots) stays outside it.
//
// There is no Skip: onboarding completes only via the "Enter Leyne" button on
// the done step, ensuring every user passes through the priming steps.

import 'package:flutter/material.dart';

import '../theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onRequestLocation,
    required this.onRequestNotifications,
    required this.onFinish,
  });

  /// Location-primer "Allow location" tap. Implementations should call
  /// LocationService.requestAndStart() and return — the step advances on its
  /// own; the OS dialog races with the transition, matching iOS behaviour.
  final VoidCallback onRequestLocation;

  /// Notifications-primer "Enable notifications" tap. Implementations should
  /// call AppModel.setNotificationsEnabled(true), which fires the Android 13+
  /// POST_NOTIFICATIONS prompt before scheduling alerts. Same fire-and-forget
  /// shape as onRequestLocation.
  final VoidCallback onRequestNotifications;

  /// Done step "Enter Leyne" tap. Implementations should run UMP consent
  /// (AdConsent.gatherThenStart — a no-op on Android for ATT) then call
  /// AppModel.shared.finishOnboarding(). There is no ATT view on Android;
  /// this callback is the sole completion path.
  final VoidCallback onFinish;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

// Total steps for the page-dot count (welcome + live + location + notif + done).
const int _kStepCount = 5;

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  // +1 = forward (new slides in from right, old exits left).
  // -1 = back (new slides in from left, old exits right).
  int _direction = 1;
  // Guards rapid multi-taps through permission-step transitions. Without this
  // a fast double-tap on the location step would advance twice — firing
  // onRequestLocation and then immediately calling the next step's handler
  // before the OS dialog settles.
  bool _busy = false;

  // Mirror LyneMotion timing used elsewhere in the app.
  static const _anim = Duration(milliseconds: 320);
  static const _curve = Curves.easeOutCubic;

  void _unlockAfterTransition() {
    Future.delayed(_anim + const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _busy = false);
    });
  }

  // Advances the step forward (used by primary CTAs on non-permission steps
  // and by the done step's "Enter Leyne").
  void _next() {
    if (_busy) return;
    if (_step == 4) {
      // Done: lock for the async onFinish — onboarding dismisses externally.
      setState(() => _busy = true);
      widget.onFinish();
    } else {
      setState(() {
        _busy = true;
        _direction = 1;
        _step += 1;
      });
      _unlockAfterTransition();
    }
  }

  // Primary action on permission primers: fires the callback THEN advances.
  // The callback is fire-and-forget; the OS dialog races with the transition.
  void _primePrimary(VoidCallback permissionCallback) {
    if (_busy) return;
    setState(() {
      _busy = true;
      _direction = 1;
      _step += 1;
    });
    permissionCallback();
    _unlockAfterTransition();
  }

  // Secondary "Not now / Maybe later" on permission primers: just advances,
  // no permission callback fired.
  void _primeSecondary() {
    if (_busy) return;
    setState(() {
      _busy = true;
      _direction = 1;
      _step += 1;
    });
    _unlockAfterTransition();
  }

  void _back() {
    if (_step == 0) return;
    // The done step (4) locks _busy via onFinish. Back must still work there
    // so a stalled onFinish doesn't trap the user — there is no Skip.
    final isDone = _step == _kStepCount - 1;
    if (_busy && !isDone) return;
    setState(() {
      _busy = true;
      _direction = -1;
      _step -= 1;
    });
    _unlockAfterTransition();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              // ── Top bar: Back only (no Skip) ─────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Row(
                  children: [
                    Opacity(
                      // Hide on step 0 and on the done step (mirrors iOS:
                      // `step > 0 && step != 5`).
                      opacity: (_step > 0 && _step < _kStepCount - 1) ? 1 : 0,
                      child: TextButton.icon(
                        onPressed:
                            (_step > 0 && _step < _kStepCount - 1 && !_busy)
                            ? _back
                            : null,
                        icon: Icon(
                          Icons.chevron_left,
                          size: 18,
                          color: t.accent,
                        ),
                        label: Text(
                          'Back',
                          style: t.sans(15).copyWith(color: t.accent),
                        ),
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

              // ── Per-step content: ALL inside one AnimatedSwitcher ─────
              // The key is ValueKey(_step) so the ENTIRE subtree (visual +
              // kicker/title/body + buttons) is treated as one new widget and
              // animates in together. This is the fix for the transition jank
              // where copy was snapping while the visual slid.
              Expanded(
                child: AnimatedSwitcher(
                  duration: _anim,
                  switchInCurve: _curve,
                  switchOutCurve: _curve,
                  transitionBuilder: (child, anim) {
                    final dir = _direction.toDouble();
                    // Read anim.status PER FRAME (inside the builder), not once
                    // when this transition widget is first built. AnimatedSwitcher
                    // builds the outgoing child's transition while its controller
                    // is still `completed` and only calls reverse() afterwards — so
                    // a build-time status check sees `forward`/`completed` for BOTH
                    // children and slid the outgoing page the wrong way, making it
                    // cross the incoming page instead of pushing with it. By the
                    // time frames paint, the outgoing controller is reversing, so a
                    // per-frame check reliably tells incoming from outgoing.
                    return AnimatedBuilder(
                      animation: anim,
                      child: child,
                      builder: (context, child) {
                        final exiting =
                            anim.status == AnimationStatus.reverse;
                        // Incoming slides from the dir-side to centre; outgoing
                        // exits to the opposite side. Both move the same way, so
                        // it reads as one push (Next ←, Back →).
                        final sign = exiting ? -dir : dir;
                        final v = anim.value;
                        return Opacity(
                          opacity: v.clamp(0.0, 1.0),
                          child: FractionalTranslation(
                            translation: Offset((1 - v) * sign * 0.14, 0),
                            child: child,
                          ),
                        );
                      },
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: _StepBody(
                      step: _step,
                      busy: _busy,
                      onNext: _next,
                      onPrimePrimary: _primePrimary,
                      onPrimeSecondary: _primeSecondary,
                      onRequestLocation: widget.onRequestLocation,
                      onRequestNotifications: widget.onRequestNotifications,
                      t: t,
                    ),
                  ),
                ),
              ),

              // ── Page dots ─────────────────────────────────────────────
              // Outside the switcher so they don't animate — they update
              // in place via AnimatedContainer, matching iOS behaviour.
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _kStepCount; i++)
                      AnimatedContainer(
                        duration: _anim,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _step ? 20 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == _step ? t.accent : t.line,
                          borderRadius: BorderRadius.circular(3),
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

// ─── Per-step content widget ──────────────────────────────────────────────────
//
// A separate StatelessWidget so the AnimatedSwitcher can cleanly replace the
// whole subtree. It receives _busy so the primary button can be visually stable
// during multi-tap lock.

class _StepBody extends StatelessWidget {
  const _StepBody({
    required this.step,
    required this.busy,
    required this.onNext,
    required this.onPrimePrimary,
    required this.onPrimeSecondary,
    required this.onRequestLocation,
    required this.onRequestNotifications,
    required this.t,
  });

  final int step;
  final bool busy;
  final VoidCallback onNext;

  /// Fires the OS permission callback then advances. Used by primer primaries.
  final void Function(VoidCallback permissionCallback) onPrimePrimary;

  /// Advances silently without a permission prompt. Used by primer secondaries.
  final VoidCallback onPrimeSecondary;
  final VoidCallback onRequestLocation;
  final VoidCallback onRequestNotifications;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return switch (step) {
      0 => _WelcomeStep(t: t, busy: busy, onNext: onNext),
      1 => _LiveStep(t: t, busy: busy, onNext: onNext),
      // Location step: neutral "Continue" and NO skip/secondary. App Store
      // Guideline 5.1.1(iv) forbids an exit/delay before the location prompt;
      // we mirror the iOS onboarding here so the flow is identical. (The
      // notification step below keeps its "Maybe later" — a skip is permitted
      // there.)
      2 => _PrimerStep(
        t: t,
        busy: busy,
        onPrimaryTap: () => onPrimePrimary(onRequestLocation),
        icon: Icons.location_on_rounded,
        kicker: 'Permission 1 of 2',
        title: 'Find stops around you',
        body:
            'Leyne uses your location to surface the nearest stops and place your bus, you and your stop on the map.',
        points: const [
          (Icons.my_location_rounded, 'Nearest stops, sorted by distance'),
          (Icons.map_outlined, 'See exactly where your stop is'),
        ],
        primaryLabel: 'Continue',
      ),
      3 => _PrimerStep(
        t: t,
        busy: busy,
        onPrimaryTap: () => onPrimePrimary(onRequestNotifications),
        onSecondaryTap: onPrimeSecondary,
        icon: Icons.notifications_rounded,
        kicker: 'Permission 2 of 2',
        title: 'Never miss your bus',
        body:
            'Get a heads-up when it\'s time to leave, and a nudge the moment your bus is pulling in.',
        points: const [
          (Icons.schedule_rounded, 'Leave-now alerts for your trip'),
          (Icons.lock_rounded, 'Live countdown on your lock screen'),
        ],
        primaryLabel: 'Enable notifications',
        secondaryLabel: 'Maybe later',
      ),
      _ => _DoneStep(t: t, busy: busy, onNext: onNext),
    };
  }
}

// ─── Step 0: Welcome ─────────────────────────────────────────────────────────

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({
    required this.t,
    required this.busy,
    required this.onNext,
  });

  final LyneTheme t;
  final bool busy;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
      child: Column(
        children: [
          const Spacer(),
          // Wordmark: "leyne" + accent dot, mirroring iOS wordmark().
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('leyne', style: t.sans(44, weight: FontWeight.w700)),
              Padding(
                padding: const EdgeInsets.only(bottom: 9, left: 5),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: t.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Singapore\'s buses & MRT,\nin real time.',
            textAlign: TextAlign.center,
            style: t.sans(20, weight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Text(
            'Live arrivals the moment they change — your bus on the map, and a nudge before it pulls in.',
            textAlign: TextAlign.center,
            style: t.sans(14).copyWith(color: t.dim, height: 1.5),
          ),
          const Spacer(),
          _PrimaryButton(label: 'Get started', t: t, busy: busy, onTap: onNext),
          const SizedBox(height: 14),
          Text(
            'NO ACCOUNT NEEDED',
            style: t.mono(12, weight: FontWeight.w500).copyWith(color: t.faint),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─── Step 1: Live wedge ──────────────────────────────────────────────────────

class _LiveStep extends StatelessWidget {
  const _LiveStep({required this.t, required this.busy, required this.onNext});

  final LyneTheme t;
  final bool busy;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  _Kicker(label: 'Why Leyne', t: t),
                  const SizedBox(height: 8),
                  Text(
                    'Always up to the minute.',
                    style: t.sans(27, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Real-time arrivals, refreshed continuously — so you always know when to leave and exactly where your bus is.',
                    style: t.sans(15).copyWith(color: t.dim, height: 1.5),
                  ),
                  const SizedBox(height: 22),
                  _OnbVisualLive(t: t),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _PrimaryButton(label: 'Continue', t: t, busy: busy, onTap: onNext),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─── Steps 2–3: Permission primer ────────────────────────────────────────────

class _PrimerStep extends StatelessWidget {
  const _PrimerStep({
    required this.t,
    required this.busy,
    required this.onPrimaryTap,
    this.onSecondaryTap,
    required this.icon,
    required this.kicker,
    required this.title,
    required this.body,
    required this.points,
    required this.primaryLabel,
    this.secondaryLabel,
  });

  final LyneTheme t;
  final bool busy;

  /// Primary: fires the OS permission prompt then advances the step.
  final VoidCallback onPrimaryTap;

  /// Secondary: advances the step without firing a permission prompt. When
  /// null (with [secondaryLabel] also null) the secondary button is omitted —
  /// required for the location step, where App Store Guideline 5.1.1(iv)
  /// forbids any skip/exit before the permission request (iOS parity).
  final VoidCallback? onSecondaryTap;
  final IconData icon;
  final String kicker;
  final String title;
  final String body;
  final List<(IconData, String)> points;
  final String primaryLabel;
  final String? secondaryLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  // Icon card — matches iOS's surface-backed ZStack icon.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: t.line),
                    ),
                    child: SizedBox(
                      width: 76,
                      height: 76,
                      child: Icon(icon, size: 34, color: t.accent),
                    ),
                  ),
                  const SizedBox(height: 26),
                  _Kicker(label: kicker, t: t),
                  const SizedBox(height: 8),
                  Text(title, style: t.sans(27, weight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Text(
                    body,
                    style: t.sans(15).copyWith(color: t.dim, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  // Bullet points.
                  for (final (ico, label) in points) ...[
                    _PointRow(icon: ico, label: label, t: t),
                    const SizedBox(height: 11),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _PrimaryButton(
            label: primaryLabel,
            t: t,
            busy: busy,
            onTap: onPrimaryTap,
          ),
          // Secondary: just advances, no permission prompt. Omitted entirely
          // when no label/handler is supplied (the location step has none).
          if (secondaryLabel != null && onSecondaryTap != null)
            TextButton(
              onPressed: busy ? null : onSecondaryTap,
              style: TextButton.styleFrom(
                foregroundColor: t.dim,
                minimumSize: const Size(double.infinity, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                secondaryLabel!,
                style: t.sans(
                  14,
                  weight: FontWeight.w600,
                ).copyWith(color: t.dim),
              ),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ─── Step 4: Done ────────────────────────────────────────────────────────────

class _DoneStep extends StatelessWidget {
  const _DoneStep({required this.t, required this.busy, required this.onNext});

  final LyneTheme t;
  final bool busy;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
      child: Column(
        children: [
          const Spacer(),
          // Checkmark in an accent rounded rect — mirrors iOS done screen.
          DecoratedBox(
            decoration: BoxDecoration(
              color: t.accent,
              borderRadius: BorderRadius.circular(26),
            ),
            child: SizedBox(
              width: 84,
              height: 84,
              child: Icon(Icons.check_rounded, size: 42, color: t.onAccent),
            ),
          ),
          const SizedBox(height: 26),
          Text('You\'re all set', style: t.sans(27, weight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(
            'Leyne is ready. Your nearest stops are already loading.',
            textAlign: TextAlign.center,
            style: t.sans(14).copyWith(color: t.dim, height: 1.5),
          ),
          const SizedBox(height: 24),
          // Grant summary — Location + Notifications only (no ATT on Android).
          _GrantRow(label: 'Location', t: t),
          const SizedBox(height: 8),
          _GrantRow(label: 'Notifications', t: t),
          const Spacer(),
          _PrimaryButton(label: 'Enter Leyne', t: t, busy: busy, onTap: onNext),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─── Building blocks ─────────────────────────────────────────────────────────

class _Kicker extends StatelessWidget {
  const _Kicker({required this.label, required this.t});
  final String label;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: t
          .mono(11, weight: FontWeight.w700)
          .copyWith(color: t.accent, letterSpacing: 1.2),
    );
  }
}

class _PointRow extends StatelessWidget {
  const _PointRow({required this.icon, required this.label, required this.t});
  final IconData icon;
  final String label;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: t.surfaceHi,
            borderRadius: BorderRadius.circular(7),
          ),
          child: SizedBox(
            width: 28,
            height: 28,
            child: Icon(icon, size: 14, color: t.fg),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(label, style: t.sans(13.5, weight: FontWeight.w500)),
          ),
        ),
      ],
    );
  }
}

class _GrantRow extends StatelessWidget {
  const _GrantRow({required this.label, required this.t});
  final String label;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.line),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        child: Row(
          children: [
            Text(label, style: t.sans(14, weight: FontWeight.w600)),
            const Spacer(),
            // Static — the user saw the permission dialogs; the row is just
            // a summary confirming those steps ran. Matches iOS "Skipped"
            // neutral state: a circle icon at faint opacity.
            Icon(Icons.check_circle_rounded, size: 16, color: t.accent),
          ],
        ),
      ),
    );
  }
}

/// Primary action button — shared by all steps.
///
/// Uses `t.accent` background and `t.onAccent` foreground so dark-mode
/// (accent = white) renders correctly: white background, dark text.
/// The previous `Colors.white` foreground caused white-on-white in dark mode.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.t,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final LyneTheme t;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: busy ? null : onTap,
        style: FilledButton.styleFrom(
          backgroundColor: t.accent,
          foregroundColor: t.onAccent,
          // Keep the button visually identical while the multi-tap guard is
          // engaged — a grey flicker between steps would be noticeable.
          disabledBackgroundColor: t.accent,
          disabledForegroundColor: t.onAccent,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          style: t
              .sans(16, weight: FontWeight.w600)
              .copyWith(color: t.onAccent),
        ),
      ),
    );
  }
}

// ─── OnbVisualLive: 3-row feature card (step 1) ──────────────────────────────
//
// Mirrors iOS OnbVisualLive — three rows in surface cards: icon + title + desc.
// Monochrome: icon foreground is t.accent (white/black), background is t.liveBg.

class _OnbVisualLive extends StatelessWidget {
  const _OnbVisualLive({required this.t});
  final LyneTheme t;

  static const _rows = [
    (Icons.wifi_tethering_rounded, 'Live arrivals', 'refreshed continuously'),
    (Icons.map_rounded, 'On the map', 'your bus, you and your stop'),
    (Icons.notifications_rounded, 'Smart alerts', 'a nudge before it pulls in'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (ico, title, desc) in _rows) ...[
          DecoratedBox(
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.line),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: t.liveBg,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(ico, size: 18, color: t.accent),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: t.sans(14, weight: FontWeight.w600)),
                        const SizedBox(height: 1),
                        Text(desc, style: t.mono(11).copyWith(color: t.dim)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}
