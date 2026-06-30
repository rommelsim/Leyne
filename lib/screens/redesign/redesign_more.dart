// Lines (MRT/LRT status), Saved, Settings and the Switch (nearby) screen.

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/data_store.dart';
import '../../data/mrt_geo.dart';
import '../../data/mrt_stations.dart';
import '../../services/location_service.dart';
import '../../theme.dart' show MRTLine;
import 'redesign_bridge.dart';
import 'redesign_common.dart';
import 'redesign_controller.dart';
import 'redesign_theme.dart';

// =============================================================== shared bits

class _BackHeader extends StatelessWidget {
  const _BackHeader({required this.title, required this.onBack, this.subtitle});
  final String title;
  final String? subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Row(
        children: [
          RdCircleButton(icon: Symbols.arrow_back, bordered: false, iconSize: 24, onTap: onBack),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: rdText(size: subtitle == null ? 24 : 22, weight: FontWeight.w800, color: t.onSurface, letterSpacing: -0.44)),
              if (subtitle != null)
                Text(subtitle!, style: rdText(size: 12, weight: FontWeight.w500, color: t.onVariant)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.color, this.padding = const EdgeInsets.fromLTRB(4, 0, 4, 9)});
  final String text;
  final Color? color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    return Padding(
      padding: padding,
      child: Text(text, style: rdText(size: 11, weight: FontWeight.w700, color: color ?? t.onVariant, letterSpacing: 0.85)),
    );
  }
}

class RdToggleSwitch extends StatelessWidget {
  const RdToggleSwitch({super.key, required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    return Container(
      width: 48,
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      alignment: on ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(color: on ? t.primary : t.scHighest, borderRadius: BorderRadius.circular(14)),
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(color: on ? t.onPrimary : t.outline, shape: BoxShape.circle),
      ),
    );
  }
}

/// Rounded list card wrapper.
class _Card extends StatelessWidget {
  const _Card({required this.child, this.radius = 22, this.padding});
  final Widget child;
  final double radius;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    return Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: t.scLow,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: t.outlineVariant),
      ),
      child: child,
    );
  }
}

// ============================================================== LINES screen

class RdLinesScreen extends StatefulWidget {
  const RdLinesScreen({super.key, required this.c});
  final RedesignController c;

  @override
  State<RdLinesScreen> createState() => _RdLinesScreenState();
}

class _RdLinesScreenState extends State<RdLinesScreen> {
  @override
  void initState() {
    super.initState();
    DataStore.shared.refreshTrainAlertsIfStale();
  }

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    final alerts = DataStore.shared.trainAlerts;
    final disrupted = alerts.map((a) => a.line).whereType<MRTLine>().toSet();
    final normal = MRTLine.values.where((l) => !disrupted.contains(l)).toList();
    return Container(
      color: t.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BackHeader(
            title: 'MRT & LRT',
            subtitle: alerts.isEmpty
                ? 'All lines running normally · live from LTA'
                : '${disrupted.length} line${disrupted.length == 1 ? '' : 's'} affected · live from LTA',
            onBack: widget.c.back,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              children: [
                for (final a in alerts) ...[_MajorLineCard(alert: a), const SizedBox(height: 11)],
                for (final l in normal) ...[_LineRow(line: l), const SizedBox(height: 11)],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LineBadge extends StatelessWidget {
  const _LineBadge({required this.code, required this.bg, this.size = 44});
  final String code;
  final Color bg;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(13)),
      alignment: Alignment.center,
      child: Text(code, style: rdText(size: 14, weight: FontWeight.w900, color: rdMrtBadgeFg(code))),
    );
  }
}

class _MajorLineCard extends StatelessWidget {
  const _MajorLineCard({required this.alert});
  final TrainAlert alert;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    final color = alert.line?.color ?? t.mrt;
    final code = alert.line?.code ??
        (alert.lineCode.length >= 2 ? alert.lineCode.substring(0, 2) : alert.lineCode);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: t.mrt, width: 2),
      ),
      child: Container(
        color: t.mrtContainer,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _LineBadge(code: code, bg: color, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(alert.title, style: rdText(size: 16, weight: FontWeight.w800, color: t.onMrtContainer)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          RdIcon(Symbols.warning, size: 15, color: t.mrt, fill: 1),
                          const SizedBox(width: 4),
                          Text('DISRUPTION', style: rdText(size: 11, weight: FontWeight.w800, color: t.mrt, letterSpacing: 0.22)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 11),
            Text(alert.detail, style: rdText(size: 13, weight: FontWeight.w500, color: t.onMrtContainer, height: 1.45)),
            if (alert.freeBus || alert.freeShuttle) ...[
              const SizedBox(height: 10),
              Row(children: [
                if (alert.freeBus) _freeChip(t, 'Free bus rides'),
                if (alert.freeBus && alert.freeShuttle) const SizedBox(width: 6),
                if (alert.freeShuttle) _freeChip(t, 'Free shuttle'),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _freeChip(RdTokens t, String s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: t.surface.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(999)),
        child: Text(s, style: rdText(size: 10.5, weight: FontWeight.w700, color: t.onMrtContainer)),
      );
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line});
  final MRTLine line;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    return _Card(
      radius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      child: Row(
        children: [
          _LineBadge(code: line.code, bg: line.color),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${line.displayName} Line', style: rdText(size: 15, weight: FontWeight.w700, color: t.onSurface)),
                const SizedBox(height: 2),
                Text('Running normally', style: rdText(size: 12, weight: FontWeight.w500, color: t.onVariant)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: t.busContainer, borderRadius: BorderRadius.circular(9)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RdDot(t.bus, size: 6),
                const SizedBox(width: 5),
                Text('Normal', style: rdText(size: 11.5, weight: FontWeight.w700, color: t.onBusContainer)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================== SAVED screen

class RdSavedScreen extends StatelessWidget {
  const RdSavedScreen({super.key, required this.c});
  final RedesignController c;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    final stops = c.savedStopCodes.toList()..sort();
    final buses = c.savedRoutes.toList()
      ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
    return Container(
      color: t.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BackHeader(title: 'Saved', onBack: c.back),
          Expanded(
            child: (stops.isEmpty && buses.isEmpty)
                ? _empty(t)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    children: [
                      if (buses.isNotEmpty) ...[
                        const _SectionLabel('BUSES'),
                        _Card(
                          radius: 20,
                          child: Column(children: [
                            for (var i = 0; i < buses.length; i++) ...[
                              if (i > 0) Divider(height: 1, thickness: 1, color: t.outlineVariant),
                              _busRow(t, buses[i]),
                            ],
                          ]),
                        ),
                        const SizedBox(height: 22),
                      ],
                      if (stops.isNotEmpty) ...[
                        const _SectionLabel('STOPS'),
                        _Card(
                          radius: 20,
                          child: Column(children: [
                            for (var i = 0; i < stops.length; i++) ...[
                              if (i > 0) Divider(height: 1, thickness: 1, color: t.outlineVariant),
                              GestureDetector(
                                onTap: () => c.openStopCode(stops[i]),
                                behavior: HitTestBehavior.opaque,
                                child: _stopRow(t, stops[i]),
                              ),
                            ],
                          ]),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _empty(RdTokens t) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            RdIcon(Symbols.bookmark, size: 34, color: t.outline),
            const SizedBox(height: 10),
            Text('Nothing saved yet', style: rdText(size: 16, weight: FontWeight.w800, color: t.onSurface)),
            const SizedBox(height: 6),
            Text('Tap the bookmark on a stop or bus to save it here.',
                textAlign: TextAlign.center,
                style: rdText(size: 13, weight: FontWeight.w500, color: t.onVariant)),
          ]),
        ),
      );

  Widget _busRow(RdTokens t, String svc) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        child: Row(children: [
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: t.scHighest, borderRadius: BorderRadius.circular(12)),
            child: Text(svc, style: rdText(size: 15, weight: FontWeight.w800, color: t.onSurface)),
          ),
          const SizedBox(width: 13),
          Text('Saved bus', style: rdText(size: 14, weight: FontWeight.w700, color: t.onSurface)),
        ]),
      );

  Widget _stopRow(RdTokens t, String code) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(DataStore.shared.stopName(code),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: rdText(size: 15, weight: FontWeight.w700, color: t.onSurface)),
                ),
                RdMrtBadgeRow(stopName: DataStore.shared.stopName(code), size: 8),
              ]),
              const SizedBox(height: 4),
              Text('Stop $code', style: rdText(size: 12, weight: FontWeight.w500, color: t.onVariant)),
            ]),
          ),
          RdIcon(Symbols.chevron_right, size: 20, color: t.outline),
        ]),
      );
}

// ============================================================ SETTINGS screen

class RdSettingsScreen extends StatelessWidget {
  const RdSettingsScreen({super.key, required this.c});
  final RedesignController c;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    return Container(
      color: t.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BackHeader(title: 'Settings', onBack: c.back),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                _SectionLabel('APPEARANCE', color: t.primary, padding: const EdgeInsets.fromLTRB(6, 0, 6, 9)),
                _Card(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                  child: Column(
                    children: [
                      _SettingRow(
                        icon: Symbols.light_mode,
                        iconFill: 1,
                        title: 'Dark theme',
                        subtitle: 'Switch between light and dark',
                        trailing: RdToggleSwitch(on: c.dark),
                        onTap: c.toggleTheme,
                        iconColor: t.primary,
                        useDarkIcon: c.dark,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _SectionLabel('ONBOARDING & PERMISSIONS', color: t.primary, padding: const EdgeInsets.fromLTRB(6, 0, 6, 9)),
                _Card(
                  child: Column(
                    children: [
                      _SettingRow(
                        icon: Symbols.restart_alt,
                        title: 'Replay onboarding',
                        subtitle: 'See the welcome & permission flow again',
                        trailing: RdIcon(Symbols.chevron_right, size: 20, color: t.outline),
                        onTap: c.replayOnboarding,
                        iconColor: t.onVariant,
                        pad: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      Divider(height: 1, thickness: 1, color: t.outlineVariant),
                      _SettingRow(
                        icon: Symbols.warning,
                        iconFill: 1,
                        title: 'MRT disruption alerts',
                        trailing: const RdToggleSwitch(on: true),
                        onTap: () {},
                        iconColor: t.mrt,
                        pad: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _SectionLabel('ABOUT', color: t.primary, padding: const EdgeInsets.fromLTRB(6, 0, 6, 9)),
                _Card(
                  child: Column(
                    children: [
                      _SettingRow(
                        icon: Symbols.database,
                        title: 'Data source',
                        trailing: Text('LTA · 15s', style: rdText(size: 12, weight: FontWeight.w500, color: t.onVariant)),
                        onTap: () {},
                        iconColor: t.onVariant,
                        pad: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      Divider(height: 1, thickness: 1, color: t.outlineVariant),
                      _SettingRow(
                        icon: Symbols.ads_click,
                        title: 'Remove ads',
                        trailing: Text('\$2.98', style: rdText(size: 12, weight: FontWeight.w600, color: t.onVariant)),
                        onTap: () {},
                        iconColor: t.onVariant,
                        pad: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.trailing,
    required this.onTap,
    required this.iconColor,
    this.subtitle,
    this.iconFill = 0,
    this.pad,
    this.useDarkIcon = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget trailing;
  final VoidCallback onTap;
  final Color iconColor;
  final double iconFill;
  final EdgeInsets? pad;
  final bool useDarkIcon;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: pad ?? EdgeInsets.zero,
        child: Row(
          children: [
            RdIcon(useDarkIcon ? Symbols.dark_mode : icon, size: 22, color: iconColor, fill: iconFill),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: rdText(size: 14.5, weight: FontWeight.w600, color: t.onSurface)),
                  if (subtitle != null)
                    Text(subtitle!, style: rdText(size: 12, weight: FontWeight.w500, color: t.onVariant)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            trailing,
          ],
        ),
      ),
    );
  }
}

// =============================================================== SWITCH screen

class RdSwitchScreen extends StatelessWidget {
  const RdSwitchScreen({super.key, required this.c});
  final RedesignController c;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    final stops = c.otherStops;
    final loc = LocationService.shared.lastLocation;
    return Container(
      color: t.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: Row(
              children: [
                RdCircleButton(icon: Symbols.arrow_back, bordered: false, iconSize: 24, onTap: c.back),
                const SizedBox(width: 6),
                Text('Stops nearby', style: rdText(size: 21, weight: FontWeight.w800, color: t.onSurface, letterSpacing: -0.42)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: GestureDetector(
              onTap: c.openSearch,
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: t.scHigh, borderRadius: BorderRadius.circular(26)),
                child: Row(
                  children: [
                    RdIcon(Symbols.search, size: 22, color: t.onVariant),
                    const SizedBox(width: 11),
                    Text('Search stops, buses, MRT', style: rdText(size: 15, weight: FontWeight.w500, color: t.onVariant)),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 16),
              children: [
                _NearbyLabel(icon: Symbols.directions_bus, text: 'BUS STOPS NEARBY'),
                for (final o in stops)
                  _NearbyTile(
                    iconBg: t.primaryContainer,
                    iconColor: t.onPrimaryContainer,
                    icon: Symbols.directions_bus,
                    title: o.stop.name,
                    subtitle: o.stop.arrivals.isNotEmpty
                        ? '${o.stop.distShort} · next ${o.stop.arrivals.first.route}'
                        : o.stop.distShort,
                    topMin: o.stop.arrivals.isNotEmpty ? o.stop.arrivals.first.min : '—',
                    unit: 'next bus',
                    onTap: () => c.selectStop(o.index),
                  ),
                _NearbyLabel(icon: Symbols.directions_subway, text: 'MRT STATIONS NEARBY'),
                if (loc != null)
                  for (final r in MrtGeo.nearest(lat: loc.lat, lon: loc.lon, limit: 4))
                    _NearbyTile(
                      iconBg: lineColorFor(r.station.codes.isNotEmpty ? r.station.codes.first : ''),
                      iconColor: rdMrtBadgeFg(r.station.codes.isNotEmpty ? r.station.codes.first : ''),
                      icon: Symbols.directions_subway,
                      title: r.station.name,
                      code: r.station.codes.isNotEmpty ? r.station.codes.first : null,
                      codeBg: lineColorFor(r.station.codes.isNotEmpty ? r.station.codes.first : ''),
                      codeFg: rdMrtBadgeFg(r.station.codes.isNotEmpty ? r.station.codes.first : ''),
                      subtitle: r.station.codes.join(' · '),
                      topMin: '${r.walkMin}',
                      unit: 'walk',
                      onTap: () => c.openStationNamed(r.station.name),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NearbyLabel extends StatelessWidget {
  const _NearbyLabel({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
      child: Row(
        children: [
          RdIcon(icon, size: 16, color: t.onVariant),
          const SizedBox(width: 7),
          Text(text, style: rdText(size: 11, weight: FontWeight.w800, color: t.onVariant, letterSpacing: 0.66)),
        ],
      ),
    );
  }
}

class _NearbyTile extends StatelessWidget {
  const _NearbyTile({
    required this.iconBg,
    required this.iconColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.topMin,
    required this.unit,
    required this.onTap,
    this.code,
    this.codeBg,
    this.codeFg,
  });
  final Color iconBg;
  final Color iconColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final String topMin;
  final String unit;
  final VoidCallback onTap;
  final String? code;
  final Color? codeBg;
  final Color? codeFg;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(color: t.scHigh, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: RdIcon(icon, size: 20, color: iconColor, fill: 1),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: rdText(size: 13.5, weight: FontWeight.w700, color: t.onSurface)),
                      ),
                      if (code != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                          decoration: BoxDecoration(color: codeBg, borderRadius: BorderRadius.circular(5)),
                          child: Text(code!, style: rdText(size: 9, weight: FontWeight.w800, color: codeFg)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: rdText(size: 11.5, weight: FontWeight.w500, color: t.onVariant)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text.rich(TextSpan(children: [
                  TextSpan(text: topMin, style: rdText(size: 18, weight: FontWeight.w800, color: t.primary, height: 1)),
                  TextSpan(text: ' min', style: rdText(size: 10, weight: FontWeight.w600, color: t.onVariant)),
                ])),
                const SizedBox(height: 3),
                Text(unit, style: rdText(size: 9.5, weight: FontWeight.w500, color: t.onVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
