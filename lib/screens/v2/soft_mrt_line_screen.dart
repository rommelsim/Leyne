// SoftMrtLineScreen — per-line detail screen (Leyne 2.7 Android, Phase 3).
//
// Flutter/Android port of ios-native/Leyne/V2/SoftMrtLineView.swift.
//
// Shows:
//   • SliverAppBar: coloured line-code badge + "{Name} Line" title +
//     running/disrupted subtitle + back button.
//   • Alert card — shown only when the line is disrupted.
//   • "STATION CROWD" section with a Now / {+30 min clock time} segmented
//     toggle in the header row (compact, mirrors iOS Phase 3).
//   • Crowd legend (Low · Moderate · High).
//   • Tappable crowd rows: station name + station code (muted) +
//     people-density glyph (3 person icons, 1/2/3 filled by level) +
//     chevron. Full-bleed dividers between rows. Pressed-row highlight.
//   • Loading / empty / error states.
//
// Navigation:
//   • Tapping a crowd row → pushes SoftMrtStationScreen internally.
//   • System back / AppBar back → Navigator.pop().
//
// DataStore getters used (READ-ONLY):
//   ds.trainAlerts, ds.crowdByLine, ds.forecastByLine
// DataStore mutators used:
//   ds.refreshTrainAlertsIfStale, ds.refreshCrowd, ds.refreshForecast

import 'package:flutter/material.dart';
import '../../data/data_store.dart';
import '../../data/mrt_geo.dart';
import '../../theme.dart';
import '../../widgets/v2/soft_tab_bar.dart';
import 'soft_mrt_station_screen.dart';

class SoftMrtLineScreen extends StatefulWidget {
  const SoftMrtLineScreen({
    super.key,
    required this.line,
    required this.onTab,
    required this.tabSelection,
  });

  final MRTLine line;
  final ValueChanged<SoftTab> onTab;
  final SoftTab tabSelection;

  @override
  State<SoftMrtLineScreen> createState() => _SoftMrtLineScreenState();
}

class _SoftMrtLineScreenState extends State<SoftMrtLineScreen> {
  /// false = Now (PCDRealTime), true = +30 min (PCDForecast).
  bool _showForecast = false;

  @override
  void initState() {
    super.initState();
    DataStore.shared.refreshTrainAlertsIfStale(force: false);
    DataStore.shared.refreshCrowd(widget.line, force: false);
  }

  void _onForecastToggle(bool show) {
    setState(() => _showForecast = show);
    if (show) {
      DataStore.shared.refreshForecast(widget.line, force: false);
    }
  }

  void _openStation(MrtGeoStation station) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SoftMrtStationScreen(
          station: station,
          onBack: () => Navigator.of(context).pop(),
          onTab: widget.onTab,
          tabSelection: widget.tabSelection,
        ),
      ),
    );
  }

  TrainAlert? get _alert =>
      DataStore.shared.trainAlerts
          .where((a) => a.line == widget.line)
          .firstOrNull;

  /// Wall-clock time 30 minutes from now formatted as the toggle label,
  /// e.g. "10:30 AM" (12-h) or "22:30" (24-h). Matches iOS forecastTimeLabel.
  /// Uses TimeOfDay for formatting so we don't need the intl package.
  String get _forecastTimeLabel {
    final now = DateTime.now();
    final target = now.add(const Duration(minutes: 30));
    final tod = TimeOfDay(hour: target.hour, minute: target.minute);
    final use24h = MediaQuery.of(context).alwaysUse24HourFormat;
    if (use24h) {
      // Zero-pad both fields for HH:mm format.
      final h = tod.hour.toString().padLeft(2, '0');
      final m = tod.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } else {
      // MaterialLocalizations gives us the locale-aware 12-h format for free.
      return tod.format(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      bottomNavigationBar: SoftBottomBar(
        selection: widget.tabSelection,
        onSelect: widget.onTab,
      ),
      body: ListenableBuilder(
        listenable: DataStore.shared,
        builder: (context, _) {
          final ds = DataStore.shared;
          final alert = _alert;
          final crowdData = ds.crowdByLine[widget.line];
          final forecastData = ds.forecastByLine[widget.line];
          final activeData = _showForecast ? forecastData : crowdData;

          return RefreshIndicator(
            onRefresh: () async {
              DataStore.shared.refreshTrainAlertsIfStale(force: true);
              DataStore.shared.refreshCrowd(widget.line, force: true);
              if (_showForecast) {
                DataStore.shared.refreshForecast(widget.line, force: true);
              }
            },
            color: t.fg,
            backgroundColor: t.surface,
            child: CustomScrollView(
              slivers: [
                _buildAppBar(t, alert),
                // Full-bleed divider under the header.
                SliverToBoxAdapter(
                  child: Divider(color: t.line, height: 1, thickness: 1),
                ),
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Alert card — only when disrupted.
                      if (alert != null) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                          child: _AlertCard(alert: alert, t: t),
                        ),
                      ],
                      // Crowd section header: eyebrow + toggle.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: Row(
                          children: [
                            Text(
                              'STATION CROWD',
                              style: t
                                  .mono(10, weight: FontWeight.w600, color: t.dim)
                                  .copyWith(letterSpacing: 0.8),
                            ),
                            const Spacer(),
                            _CrowdToggle(
                              showForecast: _showForecast,
                              forecastLabel: _forecastTimeLabel,
                              onToggle: _onForecastToggle,
                              t: t,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
                // Crowd list content.
                if (activeData == null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: t.dim,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _showForecast
                                ? 'Loading forecast…'
                                : 'Loading live crowd…',
                            style: TextStyle(fontSize: 13, color: t.dim),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (activeData.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      child: Text(
                        _showForecast
                            ? 'Forecast unavailable right now.'
                            : 'Crowd data unavailable right now.',
                        style: TextStyle(fontSize: 13, color: t.faint),
                      ),
                    ),
                  )
                else ...[
                  // Legend above the rows.
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: _CrowdLegend(t: t),
                    ),
                  ),
                  // Full-bleed crowd rows with dividers.
                  _CrowdRowList(
                    items: _sortedCrowd(activeData),
                    onTapStation: _openStation,
                    t: t,
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  SliverAppBar _buildAppBar(LyneTheme t, TrainAlert? alert) {
    final disrupted = alert != null;
    return SliverAppBar(
      backgroundColor: t.bg,
      surfaceTintColor: Colors.transparent,
      pinned: false,
      floating: false,
      snap: false,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_rounded, size: 20, color: t.fg),
        onPressed: () => Navigator.of(context).pop(),
        tooltip: 'Back',
      ),
      titleSpacing: 0,
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Coloured line-code badge.
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: widget.line.color,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              widget.line.code,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${widget.line.displayName} Line',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: t.fg,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(right: 5),
                    decoration: BoxDecoration(
                      color: disrupted
                          ? LyneSeverity.warning.color
                          : LyneSeverity.normal.color.withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Text(
                    disrupted ? 'Disrupted' : 'Operating normally',
                    style: TextStyle(
                      fontSize: 12,
                      color: disrupted ? LyneSeverity.warning.color : t.dim,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Sort crowd entries by the numeric suffix of the station code (EW13 → 13).
  /// Mirrors SoftMrtLineView.swift sortedCrowd / codeNum.
  static List<StationCrowd> _sortedCrowd(List<StationCrowd> items) {
    int codeNum(String code) {
      final match = RegExp(r'\d+').firstMatch(code);
      return match == null ? 0 : int.tryParse(match.group(0)!) ?? 0;
    }

    final sorted = List<StationCrowd>.from(items);
    sorted.sort((a, b) => codeNum(a.code).compareTo(codeNum(b.code)));
    return sorted;
  }
}

// ─── Alert card ───────────────────────────────────────────────────────────────

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert, required this.t});

  final TrainAlert alert;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LyneSeverity.warning.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 14,
                color: LyneSeverity.warning.color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  alert.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.fg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            alert.detail,
            style: TextStyle(fontSize: 13, color: t.dim),
          ),
          if (alert.freeBus || alert.freeShuttle) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (alert.freeBus)
                  _FreeServiceChip(
                    label: 'Free bus rides',
                    icon: Icons.directions_bus_rounded,
                    t: t,
                  ),
                if (alert.freeShuttle)
                  _FreeServiceChip(
                    label: 'Free MRT shuttle',
                    icon: Icons.train_rounded,
                    t: t,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FreeServiceChip extends StatelessWidget {
  const _FreeServiceChip({
    required this.label,
    required this.icon,
    required this.t,
  });

  final String label;
  final IconData icon;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: t.surfaceHi,
        borderRadius: BorderRadius.circular(LyneRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: t.dim),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: t.dim),
          ),
        ],
      ),
    );
  }
}

// ─── Compact Now / +30min segmented toggle ────────────────────────────────────
// Sits in the crowd-section header row (right-aligned). The forecast label
// shows the actual wall-clock time (e.g. "10:30 AM") instead of "+30 min".
// Mirrors SoftMrtLineView.swift Phase 3 Picker in the section header.

class _CrowdToggle extends StatelessWidget {
  const _CrowdToggle({
    required this.showForecast,
    required this.forecastLabel,
    required this.onToggle,
    required this.t,
  });

  final bool showForecast;
  final String forecastLabel;
  final ValueChanged<bool> onToggle;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: t.surfaceHi,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Segment(
            label: 'Now',
            selected: !showForecast,
            onTap: () => onToggle(false),
            t: t,
          ),
          _Segment(
            label: forecastLabel,
            selected: showForecast,
            onTap: () => onToggle(true),
            t: t,
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.t,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: LyneMotion.fast,
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? t.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? t.fg : t.dim,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

// ─── Crowd legend ─────────────────────────────────────────────────────────────

class _CrowdLegend extends StatelessWidget {
  const _CrowdLegend({required this.t});

  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    const levels = [CrowdLevel.low, CrowdLevel.moderate, CrowdLevel.high];
    return Row(
      children: levels.map((level) {
        return Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: _crowdColor(level),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                _crowdLabel(level),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: t.dim,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─── Full-bleed crowd row list ────────────────────────────────────────────────
// Rendered as a SliverList so it scrolls within the outer CustomScrollView.
// Dividers are full-bleed (edge-to-edge), matching iOS SoftMrtLineView.swift.

class _CrowdRowList extends StatelessWidget {
  const _CrowdRowList({
    required this.items,
    required this.onTapStation,
    required this.t,
  });

  final List<StationCrowd> items;
  final ValueChanged<MrtGeoStation> onTapStation;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          // Each logical item is the row + optional divider below it.
          final rowIndex = index ~/ 2;
          final isDivider = index.isOdd;

          if (isDivider) {
            // Full-bleed divider — no horizontal padding.
            return Divider(color: t.line, height: 1, thickness: 1);
          }

          final stop = items[rowIndex];
          final station = MrtGeo.stationForCode(stop.code);

          return _CrowdRow(
            stop: stop,
            station: station,
            onTap: station != null ? () => onTapStation(station) : null,
            t: t,
          );
        },
        // For N items: N rows + (N-1) dividers = 2N-1 children.
        childCount: items.isEmpty ? 0 : items.length * 2 - 1,
      ),
    );
  }
}

// ─── Single crowd row ─────────────────────────────────────────────────────────
// Station name + station code (muted, below) + people-density glyph +
// optional trailing chevron. Pressed-row background highlight.
// Mirrors SoftMrtLineView.swift crowdRow.

class _CrowdRow extends StatefulWidget {
  const _CrowdRow({
    required this.stop,
    required this.station,
    required this.onTap,
    required this.t,
  });

  final StationCrowd stop;
  final MrtGeoStation? station;
  final VoidCallback? onTap;
  final LyneTheme t;

  @override
  State<_CrowdRow> createState() => _CrowdRowState();
}

class _CrowdRowState extends State<_CrowdRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final stop = widget.stop;
    final unknown = stop.level == CrowdLevel.unknown;

    return GestureDetector(
      onTapDown: widget.onTap != null ? (_) => setState(() => _pressed = true) : null,
      onTapUp: widget.onTap != null
          ? (_) {
              setState(() => _pressed = false);
              widget.onTap!();
            }
          : null,
      onTapCancel:
          widget.onTap != null ? () => setState(() => _pressed = false) : null,
      child: AnimatedContainer(
        duration: LyneMotion.fast,
        color: _pressed ? t.surfaceHi : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            // Station name + code.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stop.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: unknown ? t.dim : t.fg,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  // Station code — muted, smaller, tabular.
                  Text(
                    stop.code,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: t.faint,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // People-density glyph (3 person icons, 1–3 filled by level).
            _PeopleDensityGlyph(level: stop.level, t: t),
            // Trailing chevron — only when the row is tappable.
            if (widget.onTap != null) ...[
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, size: 14, color: t.faint),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── People-density glyph ─────────────────────────────────────────────────────
// Three person silhouettes filled (coloured) by level: Low=1, Moderate=2,
// High=3. Unfilled icons render in t.line (hairline). No text label.
// Mirrors SoftMrtLineView.swift crowdGlyph.

class _PeopleDensityGlyph extends StatelessWidget {
  const _PeopleDensityGlyph({required this.level, required this.t});

  final CrowdLevel level;
  final LyneTheme t;

  @override
  Widget build(BuildContext context) {
    final filled = switch (level) {
      CrowdLevel.low => 1,
      CrowdLevel.moderate => 2,
      CrowdLevel.high => 3,
      CrowdLevel.unknown => 0,
    };
    final activeColor = _crowdColor(level);

    return Semantics(
      label: _crowdLabel(level),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Icon(
              Icons.person_rounded,
              size: 13,
              color: i < filled ? activeColor : t.line,
            ),
          );
        }),
      ),
    );
  }
}

// ─── Crowd helpers ─────────────────────────────────────────────────────────────

Color _crowdColor(CrowdLevel level) {
  switch (level) {
    case CrowdLevel.low:
      return LyneSeverity.normal.color;
    case CrowdLevel.moderate:
      return LyneSeverity.warning.color;
    case CrowdLevel.high:
      return LyneSeverity.critical.color;
    case CrowdLevel.unknown:
      return LyneSeverity.unknown.color;
  }
}

String _crowdLabel(CrowdLevel level) {
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
