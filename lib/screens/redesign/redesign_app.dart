// Root of the SG Transit redesign. Owns the controller, resolves the design
// tokens for the current theme/seed/premium choice, routes between the launch /
// onboarding / app phases, lays the overlays above the app content, and wires
// hardware-back to the in-app navigation stack.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'redesign_controller.dart';
import 'redesign_detail.dart';
import 'redesign_home.dart';
import 'redesign_launch.dart';
import 'redesign_more.dart';
import 'redesign_onboarding.dart';
import 'redesign_overlays.dart';
import 'redesign_theme.dart';

class RedesignRoot extends StatefulWidget {
  const RedesignRoot({super.key});

  @override
  State<RedesignRoot> createState() => _RedesignRootState();
}

class _RedesignRootState extends State<RedesignRoot> {
  final RedesignController _c = RedesignController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final tokens = RdTokens.resolve(dark: _c.dark, seed: _c.seed, premium: _c.premium);
        final inApp = _c.phase == RdPhase.app;
        return RdTheme(
          tokens: tokens,
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: tokens.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
            child: PopScope(
              canPop: !(inApp && _c.canHandleBack),
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) _c.handleBack();
              },
              child: DefaultTextStyle(
                style: rdText(size: 15, color: tokens.onSurface),
                child: Container(
                  color: tokens.surface,
                  child: _buildPhase(tokens),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPhase(RdTokens tokens) {
    switch (_c.phase) {
      case RdPhase.launch:
        return const RdLaunchScreen();
      case RdPhase.onboarding:
        return RdOnboarding(c: _c);
      case RdPhase.app:
        return _AppShell(c: _c);
    }
  }
}

class _AppShell extends StatelessWidget {
  const _AppShell({required this.c});
  final RedesignController c;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: SafeArea(
                top: true,
                bottom: false,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (current, previous) => Stack(
                    fit: StackFit.expand,
                    alignment: Alignment.center,
                    children: [...previous, ?current],
                  ),
                  transitionBuilder: (child, anim) {
                    // Directional push/pop: the incoming screen slides in from
                    // the right on a forward nav and from the left on back; the
                    // outgoing screen slides the opposite way, so a "back"
                    // visibly reverses the push.
                    final incoming = child.key == ValueKey(c.screen);
                    final f = c.navForward;
                    final beginX = incoming ? (f ? 1.0 : -1.0) : (f ? -1.0 : 1.0);
                    return SlideTransition(
                      position: Tween(begin: Offset(beginX, 0), end: Offset.zero).animate(anim),
                      child: child,
                    );
                  },
                  child: KeyedSubtree(key: ValueKey(c.screen), child: _screen(c.screen)),
                ),
              ),
            ),
            if (c.showNav) RdBottomNav(c: c),
          ],
        ),
        if (c.searchOpen) RdSearchOverlay(c: c),
        if (c.luVisible) RdLiveUpdate(c: c),
        if (c.toast != null) RdToast(c: c),
      ],
    );
  }

  Widget _screen(String screen) {
    switch (screen) {
      case 'stop':
        return RdStopScreen(c: c);
      case 'station':
        return RdStationScreen(c: c);
      case 'route':
        return RdRouteScreen(c: c);
      case 'lines':
        return RdLinesScreen(c: c);
      case 'saved':
        return RdSavedScreen(c: c);
      case 'settings':
        return RdSettingsScreen(c: c);
      case 'switch':
        return RdSwitchScreen(c: c);
      case 'map':
      default:
        return RdHomeScreen(c: c);
    }
  }
}
