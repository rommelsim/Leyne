// SoftNearbyScreen — the pushed "Nearby" screen (Material 3 Android variant).
//
// Home became minimal 2026-07-07 (owner call): search bar, closest-stop hero,
// one promoted nearest-MRT card, and the "All stops & stations" door card are
// all that remain on SoftHomeScreen. This screen carries what Home lost:
//   • the full nearby bus-stop list (name + code · road · distance + chevron
//     rows, NO arrival info — the hero on Home is the only place arrivals show)
//   • the MRT strip (all 3-4 nearest stations)
//   • the "● LIVE · Updated h:mm" section header that used to sit on Home
//   • the hidden-stops restore footer
//
// A pushed detail-class screen — carries the anchored ad banner via
// SoftDetailBottomBar, same as Stop/Bus/Station screens (not a tab, no
// SoftBottomBar).

import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../data/models.dart';
import '../../data/mrt_geo.dart';
import '../../services/location_service.dart';
import '../../state/app_model.dart';
import '../../theme.dart';
import '../../widgets/v2/soft_components.dart';
import '../../widgets/v2/soft_tab_bar.dart';
import 'soft_home_screen.dart' show MrtStrip, NearbyStopCard;

class SoftNearbyScreen extends StatefulWidget {
  const SoftNearbyScreen({
    super.key,
    required this.onBack,
    required this.onOpenStop,
    required this.onOpenStation,
    this.onTab,
    this.tabSelection,
  });

  final VoidCallback onBack;
  final ValueChanged<String> onOpenStop;
  final void Function(MrtGeoStation station, int distanceM, int walkMin)
  onOpenStation;

  /// Threaded through only so a further pushed screen (e.g. a station opened
  /// from the MRT strip) can carry the tab the user originally came from —
  /// this screen itself never shows a tab bar (see [SoftDetailBottomBar]).
  final ValueChanged<SoftTab>? onTab;
  final SoftTab? tabSelection;

  @override
  State<SoftNearbyScreen> createState() => _SoftNearbyScreenState();
}

class _SoftNearbyScreenState extends State<SoftNearbyScreen> {
  static const _weekdayFmt = _SoftNearbyFmt();

  List<NearbyStop> _nearbyStops() {
    final base = [...DataStore.shared.nearby]
      ..removeWhere((s) => AppModel.shared.isHiddenNearby(s.stopCode))
      ..sort((a, b) => a.distanceM.compareTo(b.distanceM));
    return base.take(12).toList();
  }

  int _hiddenNearbyCount() => DataStore.shared.nearby
      .where((s) => AppModel.shared.isHiddenNearby(s.stopCode))
      .length;

  void _unhideAllNearby() {
    for (final s in DataStore.shared.nearby) {
      if (AppModel.shared.isHiddenNearby(s.stopCode)) {
        AppModel.shared.unhideNearby(s.stopCode);
      }
    }
  }

  List<MrtNearestResult> _nearbyStations() {
    final loc = LocationService.shared.lastLocation;
    if (loc == null) return const [];
    return MrtGeo.nearest(lat: loc.lat, lon: loc.lon, limit: 4);
  }

  String? _updatedLabel(List<NearbyStop> nearby) {
    DateTime? newest;
    for (final s in nearby) {
      final t = DataStore.shared.lastRefresh(s.stopCode);
      if (t != null && (newest == null || t.isAfter(newest))) newest = t;
    }
    if (newest == null) return null;
    return _weekdayFmt.clock(newest, AppModel.shared.use24h);
  }

  void _showHideSheet(BuildContext context, NearbyStop stop) {
    final t = context.t;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: t.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stop.stopName.isEmpty ? stop.stopCode : stop.stopName,
                style: t.sans(17, weight: FontWeight.w700, color: t.fg),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () {
                  AppModel.shared.hideFromNearby(stop.stopCode);
                  Navigator.of(sheetCtx).pop();
                },
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.visibility_off_outlined, size: 20, color: t.crit),
                      const SizedBox(width: 14),
                      Text(
                        'Hide from Nearby',
                        style: t.sans(15, weight: FontWeight.w500, color: t.crit),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      bottomNavigationBar: const SoftDetailBottomBar(),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([
            DataStore.shared,
            LocationService.shared,
            AppModel.shared,
          ]),
          builder: (context, _) {
            final nearby = _nearbyStops();
            final hiddenCount = _hiddenNearbyCount();
            final stations = _nearbyStations();
            final updated = _updatedLabel(nearby);

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _topBar(context),
                const SizedBox(height: 16),
                if (stations.isNotEmpty) ...[
                  Eyebrow('MRT'),
                  const SizedBox(height: 10),
                  MrtStrip(
                    stations: stations,
                    onOpen: (entry) => widget.onOpenStation(
                      entry.station,
                      entry.distanceM,
                      entry.walkMin,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                if (nearby.isEmpty)
                  Text(
                    'No stops nearby',
                    style: t.sans(15, weight: FontWeight.w600, color: t.dim),
                  )
                else ...[
                  _sectionHeader(context, 'Bus stops', updated),
                  const SizedBox(height: 10),
                  for (var i = 0; i < nearby.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    NearbyStopCard(
                      stop: nearby[i],
                      onTap: () => widget.onOpenStop(nearby[i].stopCode),
                      onLongPress: () => _showHideSheet(context, nearby[i]),
                    ),
                  ],
                ],
                if (hiddenCount > 0) ...[
                  const SizedBox(height: 10),
                  _hiddenFooter(context, hiddenCount),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    final t = context.t;
    return Row(
      children: [
        Semantics(
          label: 'Back',
          button: true,
          child: Material(
            color: t.surface,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onBack,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: t.line, width: 1),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.arrow_back_rounded, size: 20, color: t.fg),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'Nearby',
          style: t.sans(22, weight: FontWeight.w700, color: t.fg),
        ),
      ],
    );
  }

  /// "● LIVE · Updated h:mm" section header — the row Home used to carry on
  /// its first bus-stop section before the 2026-07-07 minimal-Home pass moved
  /// it here.
  Widget _sectionHeader(BuildContext context, String label, String? updated) {
    final t = context.t;
    if (updated == null) return Eyebrow(label);
    return Row(
      children: [
        Eyebrow(label),
        const SizedBox(width: 8),
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: t.soon, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          'LIVE',
          style: t
              .mono(11, weight: FontWeight.w700, color: t.soon)
              .copyWith(letterSpacing: 0.8),
        ),
        const Spacer(),
        Text(
          'UPDATED $updated',
          style: t
              .mono(11, weight: FontWeight.w500, color: t.faint)
              .copyWith(letterSpacing: 0.8),
        ),
      ],
    );
  }

  Widget _hiddenFooter(BuildContext context, int count) {
    final t = context.t;
    return InkWell(
      borderRadius: BorderRadius.circular(LyneRadius.md),
      onTap: _unhideAllNearby,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Text(
          '$count ${count == 1 ? 'stop' : 'stops'} hidden · Show',
          style: t
              .mono(11, weight: FontWeight.w500, color: t.dim)
              .copyWith(letterSpacing: 0.4),
        ),
      ),
    );
  }
}

/// Tiny 'h:mm' / 'HH:mm' formatter, mirroring SoftHomeScreen's private
/// `_formatClock` (no intl dependency — see that file's comment).
class _SoftNearbyFmt {
  const _SoftNearbyFmt();

  String clock(DateTime dt, bool use24h) {
    final m = dt.minute.toString().padLeft(2, '0');
    if (use24h) return '${dt.hour.toString().padLeft(2, '0')}:$m';
    final h12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    return '$h12:$m ${dt.hour < 12 ? 'am' : 'pm'}';
  }
}
