// SoftMrtHome — Home's MRT mode content (Wave 1 port of
// ios-native/Leyne/WhereSia/WSHomeMrt.swift).
//
// Selected by Home's Bus/MRT segmented toggle: nearest station card, live
// platform crowd (now-word + gauge; the multi-point 30-min forecast row is a
// DELIBERATE GAP — see note on SoftMrtHomeContent), the two platform
// directions (derived from line ends), a station-facilities grid, a short
// derived line map (±2 neighbouring stations), and service status. All data
// comes from what's already in DataStore/MrtGeo — no new endpoint, mirroring
// iOS's derive-don't-fetch approach.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/data_store.dart';
import '../../data/models.dart' show fmtDistance;
import '../../data/mrt_geo.dart';
import '../../data/mrt_stations.dart' show lineColorFor;
import '../../state/app_model.dart';
import '../../theme.dart';
import 'soft_departure_board.dart';

// ── Line-sequence helpers (derived from station codes, mirrors WSHomeMrt) ──

/// Splits "EW23" into its line prefix ("EW") and index (23).
({String prefix, int num})? softCodeParts(String code) {
  final letters = RegExp(r'^[A-Za-z]+').firstMatch(code)?.group(0);
  final digitsStr = code.substring(letters?.length ?? 0);
  final n = int.tryParse(digitsStr);
  if (letters == null || letters.isEmpty || n == null) return null;
  return (prefix: letters.toUpperCase(), num: n);
}

/// Every station on a line prefix, ordered by code index.
List<({String code, int num, String name})> softLineSequence(String prefix) {
  final seq = <({String code, int num, String name})>[];
  for (final st in MrtGeo.all) {
    for (final c in st.codes) {
      final parts = softCodeParts(c);
      if (parts != null && parts.prefix == prefix) {
        seq.add((code: c, num: parts.num, name: st.name));
        break;
      }
    }
  }
  seq.sort((a, b) => a.num.compareTo(b.num));
  return seq;
}

/// The neighbouring stations around [station] on its primary line (±radius).
({String prefix, List<({String code, String name, bool current})> items})?
softLineNeighbors(MrtGeoStation station, {int radius = 2}) {
  final code = station.codes.firstWhere(
    (c) => softCodeParts(c) != null,
    orElse: () => '',
  );
  if (code.isEmpty) return null;
  final parts = softCodeParts(code);
  if (parts == null) return null;
  final seq = softLineSequence(parts.prefix);
  final idx = seq.indexWhere((e) => e.num == parts.num);
  if (idx < 0) return null;
  final lo = (idx - radius).clamp(0, seq.length - 1);
  final hi = (idx + radius).clamp(0, seq.length - 1);
  final items = [
    for (final e in seq.sublist(lo, hi + 1))
      (code: e.code, name: e.name, current: e.num == parts.num),
  ];
  return (prefix: parts.prefix, items: items);
}

/// The two platform directions for a station's primary line — derived from
/// the line's first/last station.
({String a, String b})? softPlatformDirections(MrtGeoStation station) {
  final code = station.codes.firstWhere(
    (c) => softCodeParts(c) != null,
    orElse: () => '',
  );
  if (code.isEmpty) return null;
  final parts = softCodeParts(code);
  if (parts == null) return null;
  final seq = softLineSequence(parts.prefix);
  if (seq.length < 2) return null;
  final first = seq.first, last = seq.last;
  if (first.num == last.num) return null;
  return (a: last.name, b: first.name);
}

/// Distinct human line names from a station's codes, e.g.
/// "North South / East West".
String softLineNames(List<String> codes) {
  final names = <String>[];
  for (final c in codes) {
    final prefix = c.length >= 2 ? c.substring(0, 2).toUpperCase() : c;
    String name;
    switch (prefix) {
      case 'NS':
        name = 'North South';
        break;
      case 'EW':
      case 'CG':
        name = 'East West';
        break;
      case 'NE':
        name = 'North East';
        break;
      case 'CC':
      case 'CE':
        name = 'Circle';
        break;
      case 'DT':
        name = 'Downtown';
        break;
      case 'TE':
        name = 'Thomson-East Coast';
        break;
      default:
        name = 'LRT';
    }
    if (!names.contains(name)) names.add(name);
  }
  return names.join(' / ');
}

/// Best-effort MRTLine for a station's code prefix.
MRTLine? softLineFromCode(String code) {
  if (code.length < 2) return null;
  switch (code.substring(0, 2).toUpperCase()) {
    case 'EW':
    case 'CG':
      return MRTLine.ew;
    case 'NS':
      return MRTLine.ns;
    case 'NE':
      return MRTLine.ne;
    case 'CC':
    case 'CE':
      return MRTLine.cc;
    case 'DT':
      return MRTLine.dt;
    case 'TE':
      return MRTLine.te;
    default:
      return null;
  }
}

// ── Station facilities grid ─────────────────────────────────────────────

/// The 3x2 amenity grid — network-standard MRT facilities, greyscale chrome.
/// Shared by Home's MRT mode; future waves can reuse it on the pushed
/// station screen.
class SoftStationFacilitiesGrid extends StatelessWidget {
  const SoftStationFacilitiesGrid({super.key});

  static const _facilities = [
    (icon: Icons.wc_rounded, label: 'Toilets'),
    (icon: Icons.elevator_outlined, label: 'Lift'),
    (icon: Icons.accessible_rounded, label: 'Accessible'),
    (icon: Icons.escalator_rounded, label: 'Escalator'),
    (icon: Icons.credit_card_rounded, label: 'Top-up'),
    (icon: Icons.shopping_bag_outlined, label: 'Retail'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.05,
      children: [
        for (final f in _facilities)
          Container(
            decoration: BoxDecoration(
              color: t.surfaceHi,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(f.icon, size: 20, color: t.fg),
                const SizedBox(height: 8),
                Text(
                  f.label,
                  style: t.sans(11.5, weight: FontWeight.w500, color: t.dim),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ── MRT-mode content ────────────────────────────────────────────────────

/// Home's MRT-mode content stack: station card, platform-crowd-now card,
/// platforms card, facilities card, derived line-map card, service-status
/// card.
///
/// GAP (deliberate): iOS's `crowdCard` also renders a 30-minute, multi-point
/// `ForecastBar` row from `DataStore.stationForecast`. Android's
/// `DataStore.forecastByLine` only exposes the single upcoming interval per
/// station (see data_store.dart's `refreshForecast`), not the raw time
/// series iOS reads via `LTAService.stationForecast` — there's no windowed
/// list to plot several bars against. Rather than invent an API, this card
/// shows only "now" (word + gauge) and omits the forecast row; `SoftForecastBar`
/// itself is still built as a shared primitive for a future wave that adds
/// the missing data.
class SoftMrtHomeContent extends StatefulWidget {
  const SoftMrtHomeContent({
    super.key,
    required this.station,
    required this.distanceM,
    required this.walkMin,
    required this.onOpenStation,
  });

  final MrtGeoStation station;
  final int distanceM;
  final int walkMin;
  final VoidCallback onOpenStation;

  @override
  State<SoftMrtHomeContent> createState() => _SoftMrtHomeContentState();
}

class _SoftMrtHomeContentState extends State<SoftMrtHomeContent> {
  @override
  void initState() {
    super.initState();
    for (final l in _lines) {
      DataStore.shared.refreshForecast(l);
    }
  }

  @override
  void didUpdateWidget(covariant SoftMrtHomeContent old) {
    super.didUpdateWidget(old);
    if (old.station != widget.station) {
      for (final l in _lines) {
        DataStore.shared.refreshForecast(l);
      }
    }
  }

  List<MRTLine> get _lines {
    final out = <MRTLine>[];
    for (final c in widget.station.codes) {
      final l = softLineFromCode(c);
      if (l != null && !out.contains(l)) out.add(l);
    }
    return out;
  }

  StationCrowd? get _crowdNow {
    for (final code in widget.station.codes) {
      final line = softLineFromCode(code);
      final list = line == null ? null : DataStore.shared.crowdByLine[line];
      if (list == null) continue;
      for (final c in list) {
        if (c.code.toUpperCase() == code.toUpperCase()) return c;
      }
    }
    return null;
  }

  bool get _disrupted {
    return widget.station.codes.any(
      (code) => DataStore.shared.trainAlerts.any(
        (a) => softLineFromCode(code) == a.line,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = softReduceMotion(context);
    final children = <Widget>[
      _stationCard(context),
      const SizedBox(height: 14),
      _crowdCard(context),
    ];

    final dirs = softPlatformDirections(widget.station);
    if (dirs != null) {
      children.addAll([
        const SizedBox(height: 14),
        _platformsCard(context, dirs),
      ]);
    }

    children.addAll([
      const SizedBox(height: 14),
      SoftCard(
        title: 'Station facilities',
        icon: Icons.info_outline_rounded,
        child: const SoftStationFacilitiesGrid(),
      ),
    ]);

    final map = softLineNeighbors(widget.station);
    if (map != null && map.items.length > 1) {
      children.addAll([const SizedBox(height: 14), _lineMapCard(context, map)]);
    }

    children.addAll([const SizedBox(height: 14), _statusCard(context)]);

    return ListenableBuilder(
      listenable: DataStore.shared,
      builder: (context, _) {
        final delays = [0, 60, 100, 140, 180, 220];
        var i = 0;
        return Column(
          children: [
            for (final c in children)
              c is SizedBox
                  ? c
                  : SoftEntrance(
                      delay: Duration(
                        milliseconds: reduceMotion
                            ? 0
                            : delays[(i++).clamp(0, delays.length - 1)],
                      ),
                      child: c,
                    ),
          ],
        );
      },
    );
  }

  Widget _stationCard(BuildContext context) {
    final t = context.t;
    final code = widget.station.codes.isNotEmpty
        ? widget.station.codes.first
        : '';
    final saved = AppModel.shared.isMrtSaved(widget.station);
    final walkLine = widget.distanceM > 0
        ? '${widget.walkMin} min walk · ${fmtDistance(widget.distanceM)}'
        : 'Nearby';

    return SoftTapCompress(
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onOpenStation();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (code.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: lineColorFor(code),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  code,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.station.name,
                    style: t.sans(22, weight: FontWeight.w800, color: t.fg),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${softLineNames(widget.station.codes)} Line',
                    style: t.sans(13.5, weight: FontWeight.w600, color: t.dim),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.directions_walk_rounded,
                        size: 13,
                        color: t.dim,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        walkLine,
                        style: t.sans(
                          13.5,
                          weight: FontWeight.w500,
                          color: t.dim,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => AppModel.shared.toggleMrtSaved(widget.station),
              icon: Icon(
                saved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                size: 20,
                color: t.fg,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _crowdCard(BuildContext context) {
    final t = context.t;
    final crowd = _crowdNow;
    final word = crowd == null || crowd.level == CrowdLevel.unknown
        ? '—'
        : _crowdWord(crowd.level);
    final hint = crowd == null || crowd.level == CrowdLevel.unknown
        ? 'Live reading unavailable'
        : _crowdHint(crowd.level);
    return SoftCard(
      title: 'Platform crowd',
      icon: Icons.schedule_rounded,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  word,
                  style: t.sans(17, weight: FontWeight.w800, color: t.fg),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: t.sans(13, weight: FontWeight.w500, color: t.dim),
                ),
              ],
            ),
          ),
          if (crowd != null && crowd.level != CrowdLevel.unknown)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: t.fg,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'LIVE',
                  style: t
                      .mono(9.5, weight: FontWeight.w700, color: t.fg)
                      .copyWith(letterSpacing: 1.1),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _platformsCard(BuildContext context, ({String a, String b}) dirs) {
    final t = context.t;
    return SoftCard(
      title: 'Platforms',
      icon: Icons.train_rounded,
      child: Column(
        children: [
          _platformRow(t, index: 1, dest: dirs.a, letter: 'A'),
          const SoftRowDivider(),
          _platformRow(t, index: 2, dest: dirs.b, letter: 'B'),
        ],
      ),
    );
  }

  Widget _platformRow(
    LyneTheme t, {
    required int index,
    required String dest,
    required String letter,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: t.lineHi, width: 1.5),
            ),
            child: Text(
              '$index',
              style: t.mono(14, weight: FontWeight.w700, color: t.fg),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Towards $dest',
                  style: t.sans(15, weight: FontWeight.w600, color: t.fg),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Platform $letter',
                  style: t.sans(12.5, weight: FontWeight.w500, color: t.dim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineMapCard(
    BuildContext context,
    ({String prefix, List<({String code, String name, bool current})> items})
    map,
  ) {
    final t = context.t;
    final colour = lineColorFor(map.items.first.code);
    return SoftCard(
      title: 'Line map',
      icon: Icons.map_outlined,
      child: Column(
        children: [
          for (var i = 0; i < map.items.length; i++)
            _lineMapRow(
              t,
              colour: colour,
              item: map.items[i],
              isFirst: i == 0,
              isLast: i == map.items.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _lineMapRow(
    LyneTheme t, {
    required Color colour,
    required ({String code, String name, bool current}) item,
    required bool isFirst,
    required bool isLast,
  }) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: item.current ? t.surfaceHi : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: isFirst ? 18 : 0,
                  bottom: isLast ? 18 : 0,
                  child: Container(width: 3, color: colour),
                ),
                Container(
                  width: item.current ? 13 : 10,
                  height: item.current ? 13 : 10,
                  decoration: BoxDecoration(
                    color: item.current ? colour : t.bg,
                    shape: BoxShape.circle,
                    border: Border.all(color: colour, width: 2.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 44,
            child: Text(
              item.code,
              style: t.mono(
                12,
                weight: FontWeight.w700,
                color: item.current ? t.fg : colour,
              ),
            ),
          ),
          Expanded(
            child: Text(
              item.name,
              style: t.sans(
                14.5,
                weight: item.current ? FontWeight.w700 : FontWeight.w500,
                color: item.current ? t.fg : t.dim,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(BuildContext context) {
    final t = context.t;
    final disrupted = _disrupted;
    return SoftCard(
      title: 'Service status',
      icon: Icons.campaign_outlined,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            disrupted ? Icons.notifications_active_outlined : Icons.circle,
            size: disrupted ? 18 : 10,
            color: t.fg,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  disrupted ? 'Service disruption' : 'Normal service',
                  style: t.sans(16, weight: FontWeight.w800, color: t.fg),
                ),
                const SizedBox(height: 3),
                Text(
                  disrupted
                      ? 'Delays reported on this line. Tap Alerts for details.'
                      : 'All train services are running normally.',
                  style: t.sans(13, weight: FontWeight.w500, color: t.dim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _crowdWord(CrowdLevel level) {
  switch (level) {
    case CrowdLevel.low:
      return 'Low';
    case CrowdLevel.moderate:
      return 'Moderate';
    case CrowdLevel.high:
      return 'High';
    case CrowdLevel.unknown:
      return '—';
  }
}

String _crowdHint(CrowdLevel level) {
  switch (level) {
    case CrowdLevel.low:
      return 'Plenty of room';
    case CrowdLevel.moderate:
      return 'Some queues at gantries';
    case CrowdLevel.high:
      return 'Busy — expect a wait';
    case CrowdLevel.unknown:
      return 'No live reading';
  }
}
