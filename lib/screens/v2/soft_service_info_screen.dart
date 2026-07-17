// SoftServiceInfoScreen — bus service info (Material 3 Android variant).
//
// Flutter/Android port of ios-native/Leyne/WhereSia/WSServiceInfoView.swift.
// Route badge + destination + operating category, a direction segmented
// toggle when the service runs more than one way, then the FULL end-to-end
// stop-by-stop route, "First & last bus" (weekday / Saturday / Sun-P.H.,
// from the BusRoutes dataset), and "How often it runs" (AM peak / midday /
// PM peak / evening, from ServiceFreqStore). There is no fixed minute
// timetable — the disclaimer under the cards says so.
//
// 2026-07-11 restyle: sentence-case copy throughout (iOS card grammar now
// speaks quietly — WSServiceInfoView.swift's `subtitle`), SoftCard/
// SoftRowDivider/SoftEntrance reuse to match soft_home_screen's idiom, and
// this screen now hosts the full route list — Track Bus's "On the way" card
// shows only the live approach segment, its "Full route ›" link opens here
// (WSTrackBusView.swift `routeCard` comment, 2026-07-10 owner call). The
// Android equivalent entry point (SoftBusScreen's ⓘ info button) already
// pushes here with the full ServiceRoute — no separate change needed there.
//
// Opened from SoftBusScreen's top-bar info button.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/data_store.dart';
import '../../data/models.dart' show fmtClock;
import '../../data/mrt_stations.dart';
import '../../data/service_freq_store.dart';
import '../../state/app_model.dart';
import '../../theme.dart';
import '../../widgets/v2/soft_components.dart';
import '../../widgets/v2/soft_departure_board.dart';
import 'soft_stop_screen.dart';

class SoftServiceInfoScreen extends StatefulWidget {
  const SoftServiceInfoScreen({
    super.key,
    required this.serviceNo,
    required this.fromStop,
    required this.onBack,
  });

  final String serviceNo;

  /// The stop this screen was opened from, when any — drives which stop's
  /// first/last times are shown, which stop is highlighted in the full
  /// route list, and which (serviceNo, stop) pair the bookmark toggles.
  /// Null when opened from a bus-search result with no stop context.
  final String? fromStop;
  final VoidCallback onBack;

  @override
  State<SoftServiceInfoScreen> createState() => _SoftServiceInfoScreenState();
}

class _SoftServiceInfoScreenState extends State<SoftServiceInfoScreen> {
  ServiceRoute? _route;
  ServiceFreq? _freq;
  int _dirIndex = 0;
  bool _loading = true;

  /// The stop first/last times are read for: the opened-from stop, else the
  /// origin of the service's initial direction. Resolved once in [_load].
  String? _refStop;

  List<RouteDirection> get _directions => _route?.directions ?? const [];

  RouteDirection? get _selected {
    final dirs = _directions;
    if (dirs.isEmpty) return null;
    return _dirIndex < dirs.length ? dirs[_dirIndex] : dirs.first;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final ds = DataStore.shared;
    ds.ensureRoutes();

    // Resolve a reference stop so first/last populates: the opened-from
    // stop, else the origin of the initial direction. Mirrors iOS
    // WSServiceInfoView.load().
    var ref = widget.fromStop;
    if (ref == null) {
      final probe = await ds.serviceRoute(
        serviceNo: widget.serviceNo,
        stopCode: null,
      );
      if (probe != null && probe.directions.isNotEmpty) {
        final dir = probe.initialIndex < probe.directions.length
            ? probe.directions[probe.initialIndex]
            : probe.directions.first;
        ref = dir.stops.isNotEmpty ? dir.stops.first.code : null;
      }
    }

    final route = await ds.serviceRoute(
      serviceNo: widget.serviceNo,
      stopCode: ref,
    );
    final freq = await ServiceFreqStore.shared.freq(widget.serviceNo);

    if (!mounted) return;
    setState(() {
      _route = route;
      _dirIndex = route?.initialIndex ?? 0;
      _refStop = ref;
      _freq = freq;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final reduceMotion = softReduceMotion(context);
    var stagger = 0;
    Duration next() {
      final d = Duration(milliseconds: reduceMotion ? 0 : stagger * 45);
      stagger++;
      return d;
    }

    return Scaffold(
      backgroundColor: t.bg,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(t),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_directions.length > 1) ...[
                  SoftEntrance(delay: next(), child: _directionToggle(t)),
                  const SizedBox(height: 16),
                ],
                SoftEntrance(delay: next(), child: _routeCard(t)),
                const SizedBox(height: 12),
                SoftEntrance(delay: next(), child: _firstLastCard(t)),
                const SizedBox(height: 12),
                SoftEntrance(delay: next(), child: _frequencyCard(t)),
                const SizedBox(height: 14),
                Text(
                  "Buses run at these intervals — there's no fixed minute "
                  'timetable. For exact times, check live arrivals.',
                  style: t.sans(11.5, weight: FontWeight.w500, color: t.dim),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── App bar — badge + destination + category, save action ────────────
  SliverAppBar _buildAppBar(LyneTheme t) {
    return SliverAppBar(
      backgroundColor: t.bg,
      surfaceTintColor: Colors.transparent,
      pinned: false,
      floating: false,
      snap: false,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_rounded, size: 20, color: t.fg),
        onPressed: widget.onBack,
        tooltip: 'Back',
      ),
      actions: [_saveAction(t)],
      titleSpacing: 0,
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ServiceBadge(svc: widget.serviceNo, size: ServiceBadgeSize.lg),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _destTitle,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: t.fg,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                // Sentence case — the card grammar speaks quietly now
                // (WSServiceInfoView.swift `subtitle`, 2026-07-08).
                Text(
                  _subtitle,
                  style: t.sans(13, weight: FontWeight.w500, color: t.dim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _destTitle {
    final d = _selected?.destinationName;
    if (d != null && d.isNotEmpty) return d;
    return 'Bus ${widget.serviceNo}';
  }

  String get _subtitle {
    final cat = (_freq?.category ?? '').trim().toLowerCase();
    if (cat.isEmpty) return 'Bus service';
    return cat[0].toUpperCase() + cat.substring(1);
  }

  /// Trailing bookmark toggle — bookmarks this (serviceNo, fromStop)
  /// favourite. Mirrors iOS's app-bar button exactly: WSServiceInfoView.swift
  /// uses `.bookmark`/`.bookmarkFilled` for this save affordance, not a star
  /// — on iOS a literal star is reserved for long-press context menus (SF
  /// "star"/"star.slash"), not header save controls (icon audit, Section B,
  /// 2026-07-03; this screen previously used star_rounded here, which was
  /// the wrong glyph for this spot).
  Widget _saveAction(LyneTheme t) {
    return ListenableBuilder(
      listenable: AppModel.shared,
      builder: (context, _) {
        final saved = AppModel.shared.isFavService(
          no: widget.serviceNo,
          stop: widget.fromStop,
        );
        return IconButton(
          icon: Icon(
            saved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
            size: 22,
            color: saved ? t.soon : t.fg,
          ),
          tooltip: saved ? 'Remove from saved' : 'Save service',
          onPressed: () {
            if (AppModel.shared.hapticsEnabled) {
              HapticFeedback.selectionClick();
            }
            AppModel.shared.toggleFavService(
              no: widget.serviceNo,
              stop: widget.fromStop,
            );
          },
        );
      },
    );
  }

  // ── Direction toggle ────────────────────────────────────────────────────
  Widget _directionToggle(LyneTheme t) {
    final dirs = _directions;
    return SegmentedButton<int>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        backgroundColor: t.liveBg,
        foregroundColor: t.dim,
        selectedForegroundColor: t.contrastFg,
        selectedBackgroundColor: t.contrast,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LyneRadius.full),
        ),
        textStyle: t.sans(13, weight: FontWeight.w600),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      segments: [
        for (var i = 0; i < dirs.length; i++)
          ButtonSegment<int>(
            value: i,
            label: Text(
              _truncate('To ${dirs[i].destinationName}', 22),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
      ],
      selected: {_dirIndex},
      onSelectionChanged: (selection) {
        final idx = selection.first;
        if (idx == _dirIndex) return;
        setState(() => _dirIndex = idx);
      },
    );
  }

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max - 1)}…';

  // ── Full route (all stops) ──────────────────────────────────────────────
  //
  // This is where the Track Bus "Full route ›" link lands: the complete
  // stop list for the selected direction, the opened-from stop highlighted.
  // Every row opens that stop's own arrivals — mirrors iOS's
  // `routeStopsCard`/`routeStopRow`.
  Widget _routeCard(LyneTheme t) {
    final stops = _selected?.stops ?? const [];
    final title = stops.isEmpty ? 'Route' : 'Route · ${stops.length} stops';
    return SoftCard(
      title: title,
      icon: Icons.route_rounded,
      child: stops.isEmpty
          ? (_loading
                ? Column(
                    children: [
                      for (var i = 0; i < 3; i++) ...[
                        if (i > 0) const SizedBox(height: 14),
                        const SoftSkeletonRow(),
                      ],
                    ],
                  )
                : _emptyRow(t, 'Route unavailable right now.'))
          : Column(
              children: [
                for (var i = 0; i < stops.length; i++)
                  _RouteStopRow(
                    stop: stops[i],
                    isFirst: i == 0,
                    isLast: i == stops.length - 1,
                    isYourStop: stops[i].code == widget.fromStop,
                    onTap: () => _openStop(stops[i].code),
                  ),
              ],
            ),
    );
  }

  void _openStop(String code) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SoftStopScreen(
          stopCode: code,
          onBack: () => Navigator.of(context).pop(),
          onOpenBus: (svc) => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SoftServiceInfoScreen(
                serviceNo: svc,
                fromStop: code,
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          onSeeAll: () {},
        ),
      ),
    );
  }

  // ── First & last bus card ───────────────────────────────────────────────
  Widget _firstLastCard(LyneTheme t) {
    final refStop = _refStop;
    final window = refStop == null
        ? null
        : DataStore.shared.operatingWindow(
            serviceNo: widget.serviceNo,
            stopCode: refStop,
          );
    final use24 = AppModel.shared.use24h;
    final title = widget.fromStop != null
        ? 'First & last bus · this stop'
        : 'First & last bus · from origin';

    return SoftCard(
      title: title,
      icon: Icons.schedule_rounded,
      child: window == null
          ? _emptyRow(
              t,
              _loading
                  ? 'Loading…'
                  : "First/last times weren't published for this stop.",
            )
          : Column(
              children: [
                _kvRow(
                  t,
                  'Weekdays',
                  _firstLastText(window.firstWd, window.lastWd, use24),
                ),
                _kvRow(
                  t,
                  'Saturday',
                  _firstLastText(window.firstSat, window.lastSat, use24),
                ),
                _kvRow(
                  t,
                  'Sun / P.H.',
                  _firstLastText(window.firstSun, window.lastSun, use24),
                  isLast: true,
                ),
              ],
            ),
    );
  }

  String _firstLastText(String? first, String? last, bool use24h) {
    final f = first == null ? '—' : fmtClock(first, use24h: use24h);
    final l = last == null ? '—' : fmtClock(last, use24h: use24h);
    return '$f – $l';
  }

  // ── Frequency card ──────────────────────────────────────────────────────
  Widget _frequencyCard(LyneTheme t) {
    final f = _freq;
    return SoftCard(
      title: 'How often it runs',
      icon: Icons.repeat_rounded,
      child: f == null
          ? _emptyRow(
              t,
              _loading
                  ? 'Loading frequency…'
                  : 'Frequency unavailable right now.',
            )
          : Column(
              children: [
                _kvRow(t, 'AM peak · 0630–0830', ServiceFreq.band(f.amPeak)),
                _kvRow(t, 'Midday · 0831–1659', ServiceFreq.band(f.amOffpeak)),
                _kvRow(t, 'PM peak · 1700–1900', ServiceFreq.band(f.pmPeak)),
                _kvRow(
                  t,
                  'Evening · after 1900',
                  ServiceFreq.band(f.pmOffpeak),
                  isLast: true,
                ),
              ],
            ),
    );
  }

  // ── Shared card chrome ──────────────────────────────────────────────────
  Widget _emptyRow(LyneTheme t, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Text(
      text,
      style: t.sans(13, weight: FontWeight.w500, color: t.dim),
    ),
  );

  Widget _kvRow(
    LyneTheme t,
    String label,
    String value, {
    bool isLast = false,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            children: [
              Text(
                label,
                style: t.sans(13, weight: FontWeight.w600, color: t.dim),
              ),
              const Spacer(),
              Text(
                value,
                style: t.mono(14, weight: FontWeight.w700, color: t.fg),
              ),
            ],
          ),
        ),
        if (!isLast) const SoftRowDivider(),
      ],
    );
  }
}

/// One row in the full route list — a continuous left rail (quiet outline
/// nodes, a bold accent node at "your stop"), stop name + code, and an
/// MRT-interchange line-pill flag when the stop sits at a rail station.
/// Mirrors iOS `routeStopRow`; tap feedback via [SoftTapCompress] instead of
/// a SwiftUI compress button style.
class _RouteStopRow extends StatelessWidget {
  const _RouteStopRow({
    required this.stop,
    required this.isFirst,
    required this.isLast,
    required this.isYourStop,
    required this.onTap,
  });

  final RouteStopLive stop;
  final bool isFirst;
  final bool isLast;
  final bool isYourStop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final ic = resolveMrtStation(stop.name);
    return SoftTapCompress(
      onTap: () {
        if (AppModel.shared.hapticsEnabled) HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: EdgeInsets.only(top: isFirst ? 2 : 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left rail — the line runs continuously; your stop is a bold
            // accent node, the rest are quiet outlines.
            SizedBox(
              width: 20,
              child: Column(
                children: [
                  Container(
                    width: isYourStop ? 14 : 11,
                    height: isYourStop ? 14 : 11,
                    margin: const EdgeInsets.only(top: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isYourStop ? t.fg : t.bg,
                      border: Border.all(
                        color: isYourStop ? t.fg : t.faint,
                        width: isYourStop ? 3 : 2.5,
                      ),
                    ),
                  ),
                  if (!isLast)
                    Expanded(child: Container(width: 3, color: t.line)),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 8 : 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isYourStop)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          'YOUR STOP',
                          style: t
                              .mono(9, weight: FontWeight.w700, color: t.dim)
                              .copyWith(letterSpacing: 0.4),
                        ),
                      ),
                    Text(
                      stop.name,
                      style: t.sans(
                        14.5,
                        weight: isYourStop ? FontWeight.w800 : FontWeight.w600,
                        color: t.fg,
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(top: ic == null ? 2 : 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            stop.code,
                            style: t.sans(
                              12,
                              weight: FontWeight.w500,
                              color: t.dim,
                            ),
                          ),
                          if (ic != null) ...[
                            const SizedBox(width: 7),
                            Icon(Icons.train_rounded, size: 11, color: t.faint),
                            const SizedBox(width: 4),
                            for (final code in ic.codes.take(3)) ...[
                              _LineBullet(code: code),
                              const SizedBox(width: 4),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 15,
                color: t.faint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small station-code roundel — white code on the line's brand colour.
/// The one deliberate colour exception on this otherwise monochrome row,
/// matching the app-wide "colour = MRT line" convention.
class _LineBullet extends StatelessWidget {
  const _LineBullet({required this.code});
  final MrtCode code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: code.color,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        code.code,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}
