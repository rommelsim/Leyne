// About — app version, what shipped in this build, and what's next.
// Pushed from the Settings "About" card.

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import '../widgets/atoms.dart';

const String _privacyUrl = 'https://rommelsim.github.io/Leyne/privacy.html';
const String _supportUrl = 'https://rommelsim.github.io/Leyne/support.html';

// What shipped in the current build — surfaced so users know what changed.
const List<String> _thisBuild = [
  'Refreshed look — warm dark theme, mint accent, mono numerics throughout.',
  'Home leads with a hero arrival card and leave-now timing.',
  'Compact saved-route rows fit more stops on screen.',
  'Nearby shows service numbers inline and a quick map toggle.',
  'Search opens onto recents and pinned stops instead of a blank page.',
  'Bus detail: live journey timeline with a clear BOARD HERE marker.',
  'Crowding meter now fills as the bus gets fuller — no more guessing.',
  'Bus detail auto-refreshes — the marker moves, no pull needed.',
  'Onboarding no longer skips the tracking prompt on a fast double-tap.',
  'Faster, non-stacking toasts; sharper app icon and tab bar.',
];

// On the roadmap — set expectations for what's intentionally not here yet.
const List<String> _comingSoon = [
  'Refresh interval control — trade battery for freshness.',
  'Data saver — lighter polling and map tiles on cellular.',
  'QR scan — point at a stop pole to jump straight to it.',
  'Nearby map view — see stops on a map, not just a list.',
  'Background arrival alerts — get buzzed even with the app closed.',
  'More languages across every screen.',
];

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _topBar(t, context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                children: [
                  _identity(t),
                  const SizedBox(height: 24),
                  _list(t, 'This build', _thisBuild, Icons.check_rounded,
                      t.accent),
                  const SizedBox(height: 20),
                  _list(t, 'Coming soon', _comingSoon,
                      Icons.arrow_forward_rounded, t.dim),
                  const SizedBox(height: 20),
                  _linksCard(t),
                  const SizedBox(height: 20),
                  Text(
                    'Data from LTA DataMall.\nNot affiliated with any operator.',
                    style: t.mono(11, color: t.faint)
                        .copyWith(height: 1.6, letterSpacing: 0.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(LyneTheme t, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.chevron_left),
            color: t.fg,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          Text('About',
              style: t.sans(20, weight: FontWeight.w600)
                  .copyWith(letterSpacing: -0.2)),
        ],
      ),
    );
  }

  Widget _identity(LyneTheme t) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset('assets/app_icon.png',
              width: 60, height: 60, cacheWidth: 180, fit: BoxFit.cover),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Leyne',
                  style: t.sans(22, weight: FontWeight.w600)
                      .copyWith(letterSpacing: -0.3)),
              const SizedBox(height: 3),
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (_, snap) {
                  final info = snap.data;
                  final v = info == null
                      ? '…'
                      : 'v${info.version} (${info.buildNumber}) · beta';
                  return Text(v,
                      style: t.mono(12, color: t.dim)
                          .copyWith(letterSpacing: 0.4));
                },
              ),
            ],
          ),
        ),
        Text('Made in SG', style: t.sans(12, color: t.dim)),
      ],
    );
  }

  Widget _linksCard(LyneTheme t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: MicroLabel('Legal & support'),
        ),
        Container(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.line),
          ),
          child: Column(
            children: [
              _linkRow(t, 'Privacy Policy', _privacyUrl, isFirst: true),
              Divider(height: 1, color: t.line, indent: 14, endIndent: 14),
              _linkRow(t, 'Support', _supportUrl, isLast: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _linkRow(LyneTheme t, String label, String url,
      {bool isFirst = false, bool isLast = false}) {
    return InkWell(
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      borderRadius: BorderRadius.vertical(
        top: isFirst ? const Radius.circular(14) : Radius.zero,
        bottom: isLast ? const Radius.circular(14) : Radius.zero,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: t.sans(13, color: t.fg).copyWith(height: 1.4)),
            ),
            Icon(Icons.open_in_new_rounded, size: 14, color: t.dim),
          ],
        ),
      ),
    );
  }

  Widget _list(LyneTheme t, String label, List<String> items, IconData icon,
      Color iconColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: MicroLabel(label),
        ),
        Container(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.line),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Icon(icon, size: 15, color: iconColor),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          items[i],
                          style: t.sans(13, color: t.fg)
                              .copyWith(height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
