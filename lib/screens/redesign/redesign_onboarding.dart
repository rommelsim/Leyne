// Onboarding — platform-aware permission primer. Steps: welcome (with an
// Android/iOS preview toggle), notifications, location, ATT (iOS only), done.

import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/ad_consent.dart';
import '../../services/location_service.dart';
import '../../state/app_model.dart';
import 'redesign_common.dart';
import 'redesign_controller.dart';
import 'redesign_launch.dart';
import 'redesign_theme.dart';

class RdOnboarding extends StatelessWidget {
  const RdOnboarding({super.key, required this.c});
  final RedesignController c;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    final body = switch (c.obCurrent) {
      'welcome' => _Welcome(c: c),
      'notif' => _Notif(c: c),
      'location' => _Location(c: c),
      'att' => _Att(c: c),
      _ => _Done(c: c),
    };
    return Container(
      color: t.surface,
      child: SafeArea(
        bottom: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          layoutBuilder: (current, previous) => Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [...previous, ?current],
          ),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(anim),
              child: child,
            ),
          ),
          child: KeyedSubtree(key: ValueKey(c.obCurrent), child: body),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- primitives

class RdFilledButton extends StatelessWidget {
  const RdFilledButton({
    super.key,
    required this.label,
    required this.onTap,
    this.leading,
    this.trailing,
    this.height = 56,
    this.radius = 18,
    this.fontSize = 16,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? leading;
  final IconData? trailing;
  final double height;
  final double radius;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(color: t.primary, borderRadius: BorderRadius.circular(radius)),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[
                RdIcon(leading!, size: fontSize + 4, color: t.onPrimary, fill: 1),
                const SizedBox(width: 8),
              ],
              Text(label, style: rdText(size: fontSize, weight: FontWeight.w700, color: t.onPrimary)),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                RdIcon(trailing!, size: fontSize + 5, color: t.onPrimary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 48,
        child: Center(
          child: Text(label, style: rdText(size: 15, weight: FontWeight.w600, color: t.primary)),
        ),
      ),
    );
  }
}

class _OnbScaffold extends StatelessWidget {
  const _OnbScaffold({required this.content, required this.footer, this.center = false});
  final Widget content;
  final Widget footer;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
      child: Column(
        crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              children: [content],
            ),
          ),
          footer,
        ],
      ),
    );
  }
}

class _HeroBox extends StatelessWidget {
  const _HeroBox({required this.icon, required this.bg, required this.fg});
  final IconData icon;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(26)),
      alignment: Alignment.center,
      child: RdIcon(icon, size: 46, color: fg, fill: 1),
    );
  }
}

// ------------------------------------------------------------------- steps

class _Welcome extends StatelessWidget {
  const _Welcome({required this.c});
  final RedesignController c;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    return _OnbScaffold(
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const RdAppMark(size: 96, glyph: 31, radius: 0.30),
          const SizedBox(height: 26),
          Text('Singapore transit,\nat a glance',
              textAlign: TextAlign.center,
              style: rdText(size: 30, weight: FontWeight.w800, color: t.onSurface, height: 1.12, letterSpacing: -0.6)),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              'Live bus & MRT arrivals, disruption alerts, and the fastest way out the door. Free, fast, no account.',
              textAlign: TextAlign.center,
              style: rdText(size: 15, weight: FontWeight.w400, color: t.onVariant, height: 1.5),
            ),
          ),
        ],
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RdFilledButton(label: 'Get started', trailing: Symbols.arrow_forward, onTap: c.obNext),
          const SizedBox(height: 14),
          Center(
            child: Text('Free · no account',
                style: rdText(size: 12, weight: FontWeight.w500, color: t.onVariant)),
          ),
        ],
      ),
    );
  }
}

class _Notif extends StatelessWidget {
  const _Notif({required this.c});
  final RedesignController c;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    return _OnbScaffold(
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeroBox(icon: Symbols.notifications_active, bg: t.mrtContainer, fg: t.mrt),
          const SizedBox(height: 24),
          Text('Never miss your\nbus or a delay',
              style: rdText(size: 28, weight: FontWeight.w800, color: t.onSurface, height: 1.14, letterSpacing: -0.56)),
          const SizedBox(height: 13),
          Text('Get a heads-up when your ride is arriving and a proactive alert when an MRT line you use goes down.',
              style: rdText(size: 15, weight: FontWeight.w400, color: t.onVariant, height: 1.5)),
        ],
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RdFilledButton(
              label: 'Allow notifications',
              onTap: () {
                AppModel.shared.setNotificationsEnabled(true);
                c.obNext();
              },
              height: 54,
              radius: 17,
              fontSize: 15.5),
          const SizedBox(height: 8),
          _GhostButton(label: 'Not now', onTap: c.obNext),
        ],
      ),
    );
  }
}

class _Location extends StatelessWidget {
  const _Location({required this.c});
  final RedesignController c;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    return _OnbScaffold(
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeroBox(icon: Symbols.near_me, bg: t.primaryContainer, fg: t.onPrimaryContainer),
          const SizedBox(height: 24),
          Text('Arrivals around\nyou, instantly',
              style: rdText(size: 28, weight: FontWeight.w800, color: t.onSurface, height: 1.14, letterSpacing: -0.56)),
          const SizedBox(height: 13),
          Text('We use your location to show the nearest stops and stations the moment you open the app — only while you’re using it.',
              style: rdText(size: 15, weight: FontWeight.w400, color: t.onVariant, height: 1.5)),
        ],
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RdFilledButton(
              label: 'Allow while using app',
              leading: Symbols.my_location,
              onTap: () {
                LocationService.shared.requestAndStart();
                c.obNext();
              },
              height: 54,
              radius: 17,
              fontSize: 15.5),
        ],
      ),
    );
  }
}

class _Att extends StatelessWidget {
  const _Att({required this.c});
  final RedesignController c;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    return _OnbScaffold(
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeroBox(icon: Symbols.ads_click, bg: t.scHighest, fg: t.onSurface),
          const SizedBox(height: 24),
          Text('Keep ads relevant?',
              style: rdText(size: 28, weight: FontWeight.w800, color: t.onSurface, height: 1.14, letterSpacing: -0.56)),
          const SizedBox(height: 13),
          Text('Allow SG Transit to use app activity for more relevant ads. Ads stay light and unobtrusive either way — your choice.',
              style: rdText(size: 15, weight: FontWeight.w400, color: t.onVariant, height: 1.5)),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: t.scHigh, borderRadius: BorderRadius.circular(999)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RdIcon(Symbols.phone_iphone, size: 15, color: t.onVariant),
                const SizedBox(width: 6),
                Text('iOS App Tracking Transparency',
                    style: rdText(size: 12, weight: FontWeight.w600, color: t.onVariant)),
              ],
            ),
          ),
        ],
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RdFilledButton(
              label: 'Allow tracking',
              onTap: () {
                AdConsent.gatherThenStart();
                c.obNext();
              },
              height: 54,
              radius: 17,
              fontSize: 15.5),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              AdConsent.gatherThenStart();
              c.obNext();
            },
            child: Container(
              height: 54,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: t.outline),
              ),
              alignment: Alignment.center,
              child: Text('Ask app not to track', style: rdText(size: 15, weight: FontWeight.w700, color: t.onSurface)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.c});
  final RedesignController c;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    return _OnbScaffold(
      center: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(color: t.primaryContainer, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: RdIcon(Symbols.check, size: 54, color: t.primary, fill: 1),
          ),
          const SizedBox(height: 24),
          Text('You’re all set',
              style: rdText(size: 30, weight: FontWeight.w800, color: t.onSurface, letterSpacing: -0.6)),
          const SizedBox(height: 13),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text('Showing what’s arriving around you now. Tap any bus to track it live.',
                textAlign: TextAlign.center,
                style: rdText(size: 15, weight: FontWeight.w400, color: t.onVariant, height: 1.5)),
          ),
        ],
      ),
      footer: RdFilledButton(
          label: 'Enter SG Transit',
          leading: Symbols.map,
          onTap: () {
            AppModel.shared.finishOnboarding();
            LocationService.shared.startIfAuthorized();
            c.obNext();
          }),
    );
  }
}
