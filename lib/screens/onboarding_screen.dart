// Onboarding — 5-step first-run flow mirroring ios-native/Leyne/OnboardingView.swift.
//
// Flow:
//   step 0  welcome         — eyebrow, "WhereSia" wordmark, line-colour
//                             capsules, tagline, "Get started"
//   step 1  live wedge      — "WHY WHERESIA / Always up to the minute" + a
//                             mini departure-board preview
//   step 2  location primer — "Permission 1 of 2", primes OS location prompt
//   step 3  notif primer    — "Permission 2 of 2", primes POST_NOTIFICATIONS
//   step 4  done            — LIVE grant summary + "Enter WhereSia" → onFinish
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
// There is no Skip: onboarding completes only via the "Enter WhereSia" button
// on the done step, ensuring every user passes through the priming steps.

import 'package:flutter/material.dart';

import '../data/models.dart' show Load;
import '../services/location_service.dart';
import '../services/notifications.dart' show NotifPermStatus;
import '../state/app_model.dart';
import '../theme.dart';
import '../widgets/v2/confidence.dart';
import '../widgets/v2/soft_components.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onRequestLocation,
    required this.onRequestNotifications,
    required this.onFinish,
  });

  /// Location-primer "Allow location" tap. Implementations should call
  /// LocationService.requestAndStart(); the returned future must settle when
  /// the OS dialog does. The step only advances AFTER that — on Android the
  /// permission dialog pauses the activity, so a transition started in the
  /// same frame froze half-rendered behind the dialog (owner-reported: step
  /// objects "not rendering" until the dialog was dismissed).
  final Future<void> Function() onRequestLocation;

  /// Notifications-primer "Enable notifications" tap. Implementations should
  /// call AppModel.setNotificationsEnabled(true), which fires the Android 13+
  /// POST_NOTIFICATIONS prompt before scheduling alerts. Same await-then-
  /// advance shape as onRequestLocation.
  final Future<void> Function() onRequestNotifications;

  /// Done step "Enter WhereSia" tap. Implementations should run UMP consent
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
  // and by the done step's "Enter WhereSia").
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

  // Primary action on permission primers: fires the callback, AWAITS the OS
  // dialog, then advances. Advancing in the same frame as the dialog froze
  // the transition mid-flight (Android pauses the activity, halting frames)
  // — the next step sat near-invisible behind the dialog and snapped in on
  // resume. Holding the current step until the dialog settles keeps every
  // transition fully rendered. _busy guards re-taps while the dialog is up.
  Future<void> _primePrimary(
    Future<void> Function() permissionCallback,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await permissionCallback();
    } catch (_) {/* a failed prompt still advances — primer shown once */}
    if (!mounted) return;
    setState(() {
      _direction = 1;
      _step += 1;
    });
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
                        // Quiet grey, not accent — mirrors iOS's ws.dim Back.
                        icon: Icon(
                          Icons.chevron_left,
                          size: 18,
                          color: t.dim,
                        ),
                        label: Text(
                          'Back',
                          style: t.sans(15).copyWith(color: t.dim),
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

              // ── Page dots — permission progress only (2 dots), top-centre
              // directly under the Back row: iOS parity (OnboardingView's
              // stepScaffold `dots`; owner-flagged mismatch 2026-07-04 — they
              // used to sit at the bottom counting ALL steps). Outside the
              // switcher so they morph in place; invisible but
              // space-preserving on non-permission steps, like iOS's
              // opacity-0 dots.
              AnimatedOpacity(
                duration: _anim,
                opacity: (_step == 2 || _step == 3) ? 1 : 0,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < 2; i++)
                        AnimatedContainer(
                          duration: _anim,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _step - 2 ? 18 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == _step - 2 ? t.accent : t.line,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                    ],
                  ),
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
                        final exiting = anim.status == AnimationStatus.reverse;
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

  /// Fires the OS permission callback, awaits it, then advances. Used by
  /// primer primaries.
  final void Function(Future<void> Function() permissionCallback)
  onPrimePrimary;

  /// Advances silently without a permission prompt. Used by primer secondaries.
  final VoidCallback onPrimeSecondary;
  final Future<void> Function() onRequestLocation;
  final Future<void> Function() onRequestNotifications;
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
        // Outline glyphs, not filled — iOS's primer tiles use thin outlined
        // icons (navigation arrow / bell) in quiet ink.
        icon: Icons.near_me_outlined,
        kicker: 'Permission 1 of 2',
        title: 'Find stops around you',
        body:
            'Departly uses your location to surface the nearest stops and place your bus, you and your stop on the map.',
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
        icon: Icons.notifications_none_rounded,
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

  /// The app's official MRT line palette, in the same NS/EW/NE/CC/DT/TE
  /// order as the launch screen and OnboardingView.swift's `lineOrder`.
  static const _lineOrder = [
    MRTLine.ns,
    MRTLine.ew,
    MRTLine.ne,
    MRTLine.cc,
    MRTLine.dt,
    MRTLine.te,
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
      child: Column(
        children: [
          const Spacer(),
          // Eyebrow + "WhereSia" wordmark + line-colour capsules — quotes the
          // launch screen (LaunchScreenView.swift) and OnboardingView.swift's
          // welcome() block, replacing the old "leyne"+dot wordmark.
          Text(
            'SINGAPORE · BUS & MRT',
            textAlign: TextAlign.center,
            style: t
                .sans(11, weight: FontWeight.w800)
                .copyWith(color: t.dim, letterSpacing: 2.2),
          ),
          const SizedBox(height: 10),
          Text(
            'Departly',
            textAlign: TextAlign.center,
            style: t.sans(40, weight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final line in _lineOrder) ...[
                if (line != _lineOrder.first) const SizedBox(width: 6),
                Container(
                  width: 22,
                  height: 5,
                  decoration: BoxDecoration(
                    color: line.color,
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 28),
          Text(
            'Every bus and train,\nin real time.',
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
                  _Kicker(label: 'Why Departly', t: t),
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
                  _BoardPreview(t: t),
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
            // Center: the icon/copy block sits vertically centred between
            // the dots and the CTA (iOS stepScaffold parity — content used
            // to hug the top, owner-flagged mismatch 2026-07-04). The scroll
            // view still takes over when the block outgrows the viewport.
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon card — matches iOS's surface-backed ZStack icon:
                    // quiet ink glyph, not accent-tinted.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: t.surface,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: t.line),
                      ),
                      child: SizedBox(
                        width: 76,
                        height: 76,
                        child: Icon(icon, size: 34, color: t.fg),
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
                style: t
                    .sans(14, weight: FontWeight.w600)
                    .copyWith(color: t.dim),
              ),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ─── Step 4: Done ────────────────────────────────────────────────────────────

/// The actual grant outcome of a primed permission, mirroring
/// OnboardingView.swift's `Grant` enum (`on` / `off` / `skipped`).
enum _Grant { on, off, skipped }

class _DoneStep extends StatelessWidget {
  const _DoneStep({required this.t, required this.busy, required this.onNext});

  final LyneTheme t;
  final bool busy;
  final VoidCallback onNext;

  /// Reads the real, current OS grant — never assumed. [LocationService] and
  /// [AppModel] are updated in place by `onRequestLocation`/
  /// `onRequestNotifications` (see main.dart) once the system dialog they
  /// primed resolves, so listening to both here (rather than snapshotting
  /// once) means a dialog that's still in flight when this step first
  /// appears flips the row live the moment it settles.
  _Grant get _locationGrant => switch (LocationService.shared.auth) {
    LocAuth.authorized => _Grant.on,
    LocAuth.denied || LocAuth.deniedForever => _Grant.off,
    LocAuth.notDetermined => _Grant.skipped,
  };

  _Grant get _notifGrant => switch (AppModel.shared.notificationAuth) {
    NotifPermStatus.granted => _Grant.on,
    NotifPermStatus.denied || NotifPermStatus.permanentlyDenied => _Grant.off,
    NotifPermStatus.notDetermined => _Grant.skipped,
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([LocationService.shared, AppModel.shared]),
      builder: (context, _) {
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
              Text(
                'You\'re all set',
                style: t.sans(27, weight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                'Departly is ready. Your nearest stops are already loading.',
                textAlign: TextAlign.center,
                style: t.sans(14).copyWith(color: t.dim, height: 1.5),
              ),
              const SizedBox(height: 24),
              // Live grant summary — Location + Notifications only (no ATT
              // on Android). Each row reflects the actual system permission
              // state, not an assumption that the primer's primary button
              // means "granted".
              _GrantRow(label: 'Location', state: _locationGrant, t: t),
              const SizedBox(height: 8),
              _GrantRow(label: 'Notifications', state: _notifGrant, t: t),
              const Spacer(),
              _PrimaryButton(
                label: 'Enter Departly',
                t: t,
                busy: busy,
                onTap: onNext,
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
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
    // Dim grey, not accent — mirrors iOS's ws.dim kicker.
    return Text(
      label.toUpperCase(),
      style: t
          .mono(11, weight: FontWeight.w700)
          .copyWith(color: t.dim, letterSpacing: 1.2),
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
  const _GrantRow({required this.label, required this.state, required this.t});
  final String label;
  final _Grant state;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    // Mirrors iOS OnboardingView.grantRow: label, state word (ON/OFF/
    // SKIPPED), and a filled check only when actually granted — an empty
    // ring otherwise, so "skipped" and "denied" both read honestly instead
    // of a blanket checkmark.
    final granted = state == _Grant.on;
    final text = switch (state) {
      _Grant.on => 'ON',
      _Grant.off => 'OFF',
      _Grant.skipped => 'SKIPPED',
    };
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
            Text(
              text,
              style: t
                  .mono(11, weight: FontWeight.w600)
                  .copyWith(color: granted ? t.fg : t.dim, letterSpacing: 0.6),
            ),
            const SizedBox(width: 8),
            Icon(
              granted ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 16,
              color: granted ? t.accent : t.faint,
            ),
          ],
        ),
      ),
    );
  }
}

/// Primary action button — shared by all steps.
///
/// Ink pill (`t.fg` background, `t.bg` text): mirrors iOS onboarding's ink
/// CTA. Was `t.accent`, but at runtime that resolves to the Material You
/// dynamic colour, which made the CTA read wallpaper-tinted while iOS's is
/// black — owner-flagged mismatch 2026-07-04. Ink flips correctly in dark
/// mode (near-white pill, dark text), same as iOS.
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
          backgroundColor: t.fg,
          foregroundColor: t.bg,
          // Keep the button visually identical while the multi-tap guard is
          // engaged — a grey flicker between steps would be noticeable.
          disabledBackgroundColor: t.fg,
          disabledForegroundColor: t.bg,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          style: t
              .sans(16, weight: FontWeight.w600)
              .copyWith(color: t.bg),
        ),
      ),
    );
  }
}

// ─── Board preview: mini departure board (step 1) ────────────────────────────
//
// Mirrors iOS OnboardingView.boardPreview: the actual app idiom (route
// badge, LIVE status, big mono ETA, crowd meter) instead of an abstract
// feature list — reuses the same atoms the real Home/Stop screens render
// (ServiceBadge, ConfidenceStatusPill, CrowdMeter) so onboarding previews
// exactly what the user is about to see, not a mockup of it.

class _BoardPreview extends StatelessWidget {
  const _BoardPreview({required this.t});
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Preview of live arrivals',
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(LyneRadius.md),
          border: Border.all(color: t.line),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Eyebrow('Nearby'),
                  const SizedBox(width: 10),
                  const ConfidenceStatusPill(
                    confidence: ArrivalConfidence.live,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Container(height: 1, color: t.line)),
                ],
              ),
              const SizedBox(height: 14),
              _BoardRow(
                no: '174',
                dest: 'Towards Clementi',
                etaMin: 3,
                load: Load.sea,
                t: t,
              ),
              Container(
                height: 1,
                color: t.line,
                margin: const EdgeInsets.symmetric(vertical: 11),
              ),
              _BoardRow(
                no: '961M',
                dest: 'Towards Marina Ctr',
                etaMin: 7,
                load: Load.sda,
                t: t,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoardRow extends StatelessWidget {
  const _BoardRow({
    required this.no,
    required this.dest,
    required this.etaMin,
    required this.load,
    required this.t,
  });

  final String no;
  final String dest;
  final int etaMin;
  final Load load;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ServiceBadge(svc: no, size: ServiceBadgeSize.sm),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            dest,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.sans(14, weight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('$etaMin', style: t.mono(17, weight: FontWeight.w700)),
            const SizedBox(width: 2),
            Text(
              ' min',
              style: t.mono(10, weight: FontWeight.w600, color: t.dim),
            ),
          ],
        ),
        const SizedBox(width: 10),
        CrowdMeter(load: load, showLabel: false),
      ],
    );
  }
}
