// SoftFavouritesScreen — Leyne "Saved" tab (Material 3 Android).
//
// DESIGN (2026-07-03 parity pass — mirrors WSSavedView.swift exactly in
// structure/content; Material idioms for chrome):
//   • Eyebrow "YOUR PLACES" + big title "Saved", trailing hairline-capsule
//     EDIT/DONE button (no filter tabs — WSSavedView has none; the earlier
//     All/Stops/Buses/MRT segmented control was an Android-only addition
//     that made the screen look structurally different from iOS and has
//     been removed).
//   • ONE continuous "Stops" section — pinned stops followed directly by
//     saved MRT stations, no sub-header between them (mirrors WSSavedView's
//     `list`, where both ForEach blocks sit under a single "Stops" header).
//     Right-aligned section meta is always "Updated h:mm" (or "Updated —"
//     before the first successful fetch) — never omitted, mirrors
//     `WSFmt.upd`.
//   • "Lines" section (saved bus services) — only rendered when non-empty,
//     mirrors WSSavedView's `if !m.favServices.isEmpty`.
//   • No "+ Add stop" row — WSSavedView has none; adding happens via the
//     global search entry point (`onOpenSearch`, pushed from elsewhere),
//     not from this screen.
//   • Stop card: name + "code · ROAD" subline (mono, uppercased road, no
//     "Stop" prefix) + capped service-tile row (3 + "+N" overflow) + a
//     trailing soonest-arrival column (big ETA, and — only for a real
//     live/GPS reading, not a schedule-only estimate — "Bus {no} ·" plus
//     CrowdMeter(compact:true) for the short Seats/Standing/Limited word).
//     No leading icon tile and no walk/distance line — WSSavedView's
//     `savedStopRow` has neither.
//   • Station card: name + line-names subline (e.g. "EAST WEST / DOWNTOWN")
//     + up to 3 coloured line-code chips (Android's own established pill
//     style, kept) + a trailing crowd dot-chip when a live reading exists.
//   • Line (bus) card: ServiceBadge (Android's shared bus-number tile,
//     standing in for iOS's neutral RouteTile) + destination + "at {stop}"/
//     "Anywhere near you" + trailing ETA and CrowdMeter(compact:true).
//   • Swipe gestures (Dismissible) — endToStart only (LEFT swipe = delete),
//     mirroring WSSavedView's `.onDelete`:
//       Pinned stop    → swipe LEFT → unpin via togglePin.
//       Saved station  → swipe LEFT → removeMrtSaved.
//       Saved service  → swipe LEFT → removeFavService.
//     confirmDismiss always returns false — AppModel mutation +
//     ListenableBuilder rebuilds the list; Dismissible never removes the
//     widget itself.
//   • EDIT mode reorders via SliverReorderableList (Android's idiomatic
//     equivalent of WSSavedView's `.onMove`/`EditMode`) — each editable
//     section is a sibling sliver of the page's own CustomScrollView rather
//     than a separately-scrolling ReorderableListView nested inside it, so
//     the drag's auto-scroll has a real Scrollable to work with once the
//     list runs past one screen (see the long comment in build()).
//   • Empty state: centred glyph + "Nothing saved yet" + one line of body
//     copy, no CTA — mirrors WSSavedView's `emptyState` (no button there
//     either).
//   • SoftTab.favourites is used internally (bottom bar label is "Saved"
//     via SoftBottomBar — no change needed here).

import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../data/geo.dart';
import '../../data/models.dart';
import '../../data/mrt_geo.dart';
import '../../data/mrt_stations.dart';
import '../../services/location_service.dart';
import '../../state/app_model.dart';
import '../../theme.dart';
import '../../theme/soft_blue.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/v2/confidence.dart';
import '../../widgets/v2/soft_components.dart';
import '../../widgets/v2/soft_tab_bar.dart';

// ─── Freshness helper ──────────────────────────────────────────────────────

/// "Updated h:mm" from the newest successful arrivals fetch among [pins]'
/// stop codes, or "Updated —" when none have loaded yet. Always rendered —
/// mirrors `WSFmt.upd`'s em-dash fallback rather than omitting the meta.
String _updatedLabel(List<Pin> pins) {
  DateTime? newest;
  for (final pin in pins) {
    final ts = DataStore.shared.lastRefresh(pin.code);
    if (ts != null && (newest == null || ts.isAfter(newest))) newest = ts;
  }
  if (newest == null) return 'Updated —';
  final hhmm =
      '${newest.hour.toString().padLeft(2, '0')}${newest.minute.toString().padLeft(2, '0')}';
  return 'Updated ${fmtClock(hhmm, use24h: AppModel.shared.use24h)}';
}

// ─── Soonest-arrival resolution (mirrors WSData.swift wsSoonest/wsLiveETASec) ─

/// Live seconds-to-arrival, recomputed from the LTA timestamp against now
/// (so the countdown ticks smoothly), falling back to the fetched etaSec.
int _liveEtaSec(Service s, DateTime now) => s.arrivalDate != null
    ? s.arrivalDate!.difference(now).inSeconds.clamp(0, 1 << 30)
    : s.etaSec;


// ─── MRT line-name + crowd helpers ─────────────────────────────────────────
// Passive lookups only — this screen doesn't own its own crowd fetch beyond
// the one-shot warm-up in initState (mirrors `store.wsWarmCrowd` in
// WSSavedView.onAppear), so these read whatever DataStore already has cached.

const Map<String, String> _mrtLineNames = {
  'NS': 'North South',
  'EW': 'East West',
  'CG': 'East West',
  'NE': 'North East',
  'CC': 'Circle',
  'CE': 'Circle',
  'DT': 'Downtown',
  'TE': 'Thomson–East Coast',
};

/// Distinct human line names from a station's codes, e.g. "North South /
/// Circle". Mirrors WSHomeView.swift's `wsLineNames`.
String _lineNames(List<String> codes) {
  final names = <String>[];
  for (final c in codes) {
    final prefix = (c.length >= 2 ? c.substring(0, 2) : c).toUpperCase();
    final name = _mrtLineNames[prefix] ?? 'LRT';
    if (!names.contains(name)) names.add(name);
  }
  return names.join(' / ');
}

/// Best-effort MRTLine for a station's code prefix ("EW23" → ew). LRT
/// prefixes (PE/PW/SW/SE/BP) return null — crowd isn't reported per LRT
/// station.
MRTLine? _lineFromCode(String code) {
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

/// This station's cached crowd reading, if any line's feed has already
/// loaded one for it.
StationCrowd? _crowdFor(MrtGeoStation station) {
  for (final code in station.codes) {
    final line = _lineFromCode(code);
    final list = line == null ? null : DataStore.shared.crowdByLine[line];
    if (list == null) continue;
    for (final c in list) {
      if (c.code.toUpperCase() == code.toUpperCase()) return c;
    }
  }
  return null;
}

/// Crowd dot colour. Superseded 2026-07-25 (soft-blue spec item 5): "High"
/// crowd is amber — the one semantic colour exception to the earlier
/// 2026-07-03 "crowd is never colour-coded" rule, which stands for
/// low/moderate (still neutral ink; only the word carries the level there).
Color _crowdColor(CrowdLevel level, LyneTheme t) {
  if (level == CrowdLevel.unknown) return t.faint;
  if (level == CrowdLevel.high) return SoftBlue.amber;
  return t.fg;
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
      return 'Unknown';
  }
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class SoftFavouritesScreen extends StatefulWidget {
  const SoftFavouritesScreen({
    super.key,
    required this.onTab,
    required this.onOpenStop,
    required this.onOpenBus,
    required this.onOpenStation,
    required this.onOpenSearch,
  });

  final ValueChanged<SoftTab> onTab;
  final ValueChanged<String> onOpenStop;
  final void Function(String stopCode, String svc) onOpenBus;
  final void Function(MrtGeoStation station) onOpenStation;

  /// Kept for signature parity with soft_root.dart's uniform call site
  /// across Home/Saved/etc. WSSavedView has no "add" affordance of its own
  /// (adding happens via the global search entry point elsewhere), so this
  /// screen doesn't currently wire it to anything — see the file header.
  final VoidCallback onOpenSearch;

  @override
  State<SoftFavouritesScreen> createState() => _SoftFavouritesScreenState();
}

class _SoftFavouritesScreenState extends State<SoftFavouritesScreen> {
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _warmArrivals();
      DataStore.shared.ensureRoutes();
      _warmCrowd();
    });
  }

  void _warmArrivals() {
    for (final pin in AppModel.shared.pins) {
      DataStore.shared.ensureArrivals(pin.code);
    }
    for (final fav in AppModel.shared.favServices) {
      if (fav.stop != null) {
        DataStore.shared.ensureArrivals(fav.stop!);
      }
    }
  }

  /// One-shot crowd warm-up for every line touched by a saved station, so
  /// the trailing crowd chip has data without requiring a visit to the MRT
  /// tab first. Mirrors WSSavedView.onAppear's `store.wsWarmCrowd(...)`.
  void _warmCrowd() {
    final lines = <MRTLine>{};
    for (final st in AppModel.shared.savedMrtStations) {
      for (final code in st.codes) {
        final line = _lineFromCode(code);
        if (line != null) lines.add(line);
      }
    }
    for (final line in lines) {
      DataStore.shared.refreshCrowd(line);
    }
  }

  Future<void> _refreshAll() async {
    final futures = <Future<void>>[];
    for (final pin in AppModel.shared.pins) {
      futures.add(DataStore.shared.refreshArrivals(pin.code));
    }
    for (final fav in AppModel.shared.favServices) {
      if (fav.stop != null) {
        futures.add(DataStore.shared.refreshArrivals(fav.stop!));
      }
    }
    await Future.wait(futures);
  }

  bool get _isEmpty =>
      AppModel.shared.pins.isEmpty &&
      AppModel.shared.favServices.isEmpty &&
      AppModel.shared.savedMrtStations.isEmpty;

  // ── "Up next" hero (spec item 5, 2026-07-25 soft-blue redesign —
  // supersedes the earlier "most urgent across all saved" rule) ───────────
  //
  // Pick = the nearest SAVED STOP by GPS distance (falls back to the first
  // pinned/saved stop when location is unavailable), showing that stop's
  // own soonest bus. When the picked stop has no live service right now,
  // the hero STILL renders — "No live arrivals right now" (spec item 8,
  // 2026-07-25: previously suppressed entirely, matching an earlier version
  // of the iOS spec; WSSavedView's `savedHero` always shows the hero once
  // there's a pinned stop, with that fallback text and no ring). Only
  // returns null when there are no pinned stops at all — saved lines/MRT
  // stations never contribute a candidate here (spec scope is "nearest
  // saved stop").
  _UrgentPick? _upNext(BuildContext context) {
    final pins = AppModel.shared.pins;
    if (pins.isEmpty) return null;

    final loc = LocationService.shared.lastLocation;
    Pin? nearestPin;
    double? nearestDistanceM;
    if (loc != null) {
      for (final pin in pins) {
        final latLon = DataStore.shared.stopLatLon(pin.code);
        if (latLon == null) continue;
        final d = haversine(loc.lat, loc.lon, latLon.lat, latLon.lon);
        if (nearestDistanceM == null || d < nearestDistanceM) {
          nearestDistanceM = d;
          nearestPin = pin;
        }
      }
    }
    // Fallback: first pinned/saved stop (spec item 5) when GPS is off or no
    // pinned stop resolves a geo position.
    final pin = nearestPin ?? pins.first;

    final code = pin.code;
    final allSvcs = DataStore.shared.servicesFor(code);
    final tracked = pin.tracked;
    final services = (tracked != null && tracked.isNotEmpty)
        ? allSvcs.where((s) => tracked.contains(s.no)).toList()
        : allSvcs;
    final stopName = DataStore.shared.stopName(code);
    // The user's own nickname wins over the LTA description (iOS parity).
    final name = pin.nickname.isNotEmpty
        ? pin.nickname
        : (stopName.isEmpty ? code : stopName);

    // Shared metadata format (ui-checklist §2): STOP · MIN WALK · AWAY. Walk
    // time and distance both need a location fix; without one the line
    // degrades to the labelled code rather than guessing.
    final walkMin = nearestDistanceM == null
        ? null
        : walkMinutesFor(nearestDistanceM);
    final meta = stopCodeLabel(
      code,
      suffix: (walkMin != null && nearestDistanceM != null)
          ? '$walkMin min walk · ${fmtDistance(nearestDistanceM.round())} away'
          : null,
    );

    final now = DateTime.now();
    final sorted = [...services]
      ..sort((a, b) => _liveEtaSec(a, now).compareTo(_liveEtaSec(b, now)));

    // Next three DISTINCT services — a feed repeat of the same bus is noise
    // when the question is "which bus can I take" (§2).
    final seen = <String>{};
    final board = <({String no, String dest, String etaBig})>[
      for (final s in sorted)
        if (seen.add(s.no))
          (no: s.no, dest: s.dest, etaBig: fmtEta(_liveEtaSec(s, now)).big),
    ].take(3).toList();

    // "Leave in X min": X = ETA − walk time, walk at 5 km/h (`walkMinutesFor`,
    // the same formula Nearby uses). Slack ≤ 0 → "Leave now". The walk minutes
    // this used to repeat now live in the shared meta line above.
    String? decision;
    if (walkMin != null && board.isNotEmpty) {
      final slack = (_liveEtaSec(sorted.first, now) / 60).ceil() - walkMin;
      decision = slack <= 0 ? 'Leave now' : 'Leave in $slack min';
    }

    return _UrgentPick(
      name: name,
      meta: meta,
      board: board,
      decision: decision,
      onOpen: () => widget.onOpenStop(code),
    );
  }

  Widget _upNextHero(_UrgentPick pick) {
    return Semantics(
      button: true,
      label: pick.board.isEmpty
          ? 'Open ${pick.name}, no live arrivals right now'
          : 'Open ${pick.name}',
      child: SoftBoardHeroCard(
        title: pick.name,
        meta: pick.meta,
        board: pick.board,
        decision: pick.decision,
        ctaLabel: 'Open stop',
        onTap: pick.onOpen,
      ),
    );
  }


  // ── Arrival resolution for the Lines section ────────────────────────────

  _Resolved? _atStopArrival(FavService fav) {
    final code = fav.stop!;
    final svc = DataStore.shared
        .servicesFor(code)
        .cast<Service?>()
        .firstWhere((s) => s!.no == fav.no, orElse: () => null);
    if (svc == null) return null;
    return _Resolved(
      svc: svc,
      stopName: DataStore.shared.stopName(code),
      stopCode: code,
    );
  }

  _Resolved? _resolve(FavService fav) =>
      fav.isAnywhere ? null : _atStopArrival(fav);

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      bottomNavigationBar: SoftBottomBar(
        selection: SoftTab.favourites,
        onSelect: widget.onTab,
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([AppModel.shared, DataStore.shared]),
          builder: (context, _) {
            // Auto-exit edit mode when the list becomes empty.
            if (_editing && _isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => setState(() => _editing = false),
              );
            }
            return RefreshIndicator(
              color: t.accent,
              // Disable pull-to-refresh while editing — drag gestures conflict.
              onRefresh: _editing ? () async {} : _refreshAll,
              // CustomScrollView + SliverReorderableList, NOT a plain ListView
              // wrapping a shrinkWrap/NeverScrollableScrollPhysics
              // ReorderableListView. That older nesting (still used for the
              // static, non-editing render below, which is harmless) is a
              // known Flutter footgun for the EDITING path specifically:
              // SliverReorderableList drives its drag auto-scroll off
              // `Scrollable.of(context)`, which — nested one level down as
              // it was — resolved to its OWN never-scrollable, already
              // fully-laid-out inner Scrollable instead of this page's, so
              // auto-scroll during a drag was a no-op. Any list longer than
              // one screen (a realistic case for pinned stops) could only be
              // reordered within whatever was already on-screen; dragging to
              // an off-screen position silently failed to move further,
              // which read as "reorder doesn't stick." Making every editable
              // section a sibling SLIVER of ONE shared CustomScrollView gives
              // SliverReorderableList the real, scrollable ancestor it needs.
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    sliver: SliverMainAxisGroup(
                      slivers: [
                        SliverToBoxAdapter(child: _header(context)),
                        const SliverToBoxAdapter(child: SizedBox(height: 20)),
                        if (_isEmpty)
                          SliverToBoxAdapter(child: _emptyState(context))
                        else ...[
                          if (_upNext(context) case final pick?) ...[
                            SliverToBoxAdapter(child: _upNextHero(pick)),
                            const SliverToBoxAdapter(child: SizedBox(height: 20)),
                          ],
                          ..._stopsSectionSlivers(context),
                          // One native ad per screen, between the stops and
                          // Lines sections (iOS parity: WSSavedView). Zero-size
                          // until a creative loads — padding applies only then.
                          const SliverToBoxAdapter(
                            child: NativeAdCard(
                              padding: EdgeInsets.only(top: 20),
                            ),
                          ),
                          if (AppModel.shared.favServices.isNotEmpty) ...[
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 20),
                            ),
                            ..._linesSectionSlivers(context),
                          ],
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────────

  Widget _header(BuildContext context) {
    final t = context.t;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'YOUR PLACES',
                style: t
                    .sans(11, weight: FontWeight.w800, color: t.dim)
                    .copyWith(letterSpacing: 1.4),
              ),
              const SizedBox(height: 3),
              Text(
                'Saved',
                style: t.sans(26, weight: FontWeight.w800, color: t.fg),
              ),
            ],
          ),
        ),
        if (!_isEmpty) _editButton(context),
      ],
    );
  }

  Widget _editButton(BuildContext context) {
    final t = context.t;
    // Filled + shadow, no stroke (spec anti-rule #5) — was a bare
    // hairline-bordered capsule with no fill.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _editing = !_editing),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(LyneRadius.full),
          boxShadow: SoftBlue.chipShadow,
        ),
        child: AnimatedSwitcher(
          duration: LyneMotion.short,
          child: Text(
            _editing ? 'DONE' : 'EDIT',
            key: ValueKey(_editing),
            style: t
                .mono(11, weight: FontWeight.w700, color: t.fg)
                .copyWith(letterSpacing: 0.8),
          ),
        ),
      ),
    );
  }

  // ─── Shared section header (label · hairline rule · optional meta) ────────
  // Mirrors WSSectionHeader: uppercase label, a hairline rule that stretches
  // to fill the remaining row width, and an optional right-aligned meta.

  Widget _sectionHeader(
    BuildContext context, {
    required String label,
    String? meta,
  }) {
    final t = context.t;
    return Row(
      children: [
        Text(
          label.toUpperCase(),
          style: t
              .sans(11, weight: FontWeight.w800, color: t.dim)
              .copyWith(letterSpacing: 1.4),
        ),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: t.line)),
        if (meta != null) ...[
          const SizedBox(width: 10),
          Text(
            meta,
            style: t.mono(11, color: t.dim).copyWith(letterSpacing: 0.5),
          ),
        ],
      ],
    );
  }

  // ─── Stops section (pins + saved MRT stations, one continuous section) ────
  // Mirrors WSSavedView.list: both ForEach blocks sit directly under a
  // single "Stops" header with no sub-header between them.
  //
  // Returns a flat list of SLIVERS (not one Column) so the editing path can
  // hand its ReorderableListView-equivalent (SliverReorderableList) straight
  // to the page's single CustomScrollView — see the long comment in build()
  // on why the editable lists need to be real siblings of the page's own
  // Scrollable rather than nested inside a second, shrink-wrapped one.

  List<Widget> _stopsSectionSlivers(BuildContext context) {
    final pins = AppModel.shared.pins;
    final stations = AppModel.shared.savedMrtStations;
    // Split into two headed groups (spec item 8, 2026-07-25 — was one
    // continuous "Stops" section with no sub-header between pins and
    // stations, which read as "too much going on" per the owner). Mirrors
    // WSSavedView.swift's `list`: separate "Bus stops" / "MRT stations"
    // `sectionHead`s, each only rendered when its group is non-empty.
    return [
      if (pins.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: _sectionHeader(
            context,
            label: 'Bus stops',
            meta: _updatedLabel(pins),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 10)),
        _editing
            ? _reorderablePinsSliver(context, pins)
            : SliverToBoxAdapter(child: _staticPins(context, pins)),
      ],
      if (stations.isNotEmpty) ...[
        if (pins.isNotEmpty)
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        SliverToBoxAdapter(
          child: _sectionHeader(context, label: 'MRT stations'),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 10)),
        _editing
            ? _reorderableStationsSliver(context, stations)
            : SliverToBoxAdapter(child: _staticStations(context, stations)),
      ],
    ];
  }

  Widget _staticPins(BuildContext context, List<Pin> pins) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < pins.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _pinRow(context, pins[i]),
        ],
      ],
    );
  }

  Widget _reorderablePinsSliver(BuildContext context, List<Pin> pins) {
    return SliverReorderableList(
      itemCount: pins.length,
      // Remove the default drag elevation / Material shadow.
      proxyDecorator: (child, index, animation) =>
          Material(elevation: 0, color: Colors.transparent, child: child),
      onReorderItem: (oldIndex, newIndex) {
        final reordered = [...pins];
        final item = reordered.removeAt(oldIndex);
        reordered.insert(newIndex, item);
        AppModel.shared.reorderPins(reordered.map((p) => p.code).toList());
      },
      itemBuilder: (context, index) {
        final pin = pins[index];
        return Padding(
          key: ValueKey('reorder-pin-${pin.code}'),
          padding: EdgeInsets.only(bottom: index == pins.length - 1 ? 0 : 10),
          child: Row(
            children: [
              Expanded(
                child: _StopCard(
                  pin: pin,
                  onTap: () => widget.onOpenStop(pin.code),
                  onLongPress: () => _showRenameDialog(context, pin),
                ),
              ),
              const SizedBox(width: 8),
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.drag_handle_rounded,
                    size: 22,
                    color: context.t.dim,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pinRow(BuildContext context, Pin pin) {
    final t = context.t;
    final code = pin.code;
    return Dismissible(
      key: ValueKey('fav-$code'),
      direction: DismissDirection.endToStart,
      background: const SizedBox.shrink(),
      secondaryBackground: _dismissBackground(
        context: context,
        color: t.crit,
        icon: Icons.delete_rounded,
        label: 'Delete',
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
      ),
      confirmDismiss: (_) async {
        AppModel.shared.togglePin(code);
        // Always return false — AppModel mutation + ListenableBuilder rebuilds
        // the list; we never let Dismissible remove the widget itself.
        return false;
      },
      child: _StopCard(
        pin: pin,
        onTap: () => widget.onOpenStop(code),
        onLongPress: () => _showRenameDialog(context, pin),
      ),
    );
  }

  /// Long-press rename for a pinned stop (spec item 8) — mirrors iOS
  /// WSSavedView's `.alert("Rename stop", ...)` context-menu action, as a
  /// Material text-input dialog. Saves via `AppModel.rename`, which persists
  /// the nickname and drives the same `LabelPill` the card already renders.
  Future<void> _showRenameDialog(BuildContext context, Pin pin) async {
    final controller = TextEditingController(text: pin.nickname);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final t = dialogContext.t;
        return AlertDialog(
          title: const Text('Rename stop'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Nickname'),
            onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text),
              child: Text('Save', style: TextStyle(color: t.accent)),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (result != null) {
      AppModel.shared.rename(pin.code, result);
    }
  }

  Widget _staticStations(BuildContext context, List<MrtGeoStation> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _stationRow(context, items[i]),
        ],
      ],
    );
  }

  Widget _reorderableStationsSliver(
    BuildContext context,
    List<MrtGeoStation> items,
  ) {
    return SliverReorderableList(
      itemCount: items.length,
      proxyDecorator: (child, index, animation) =>
          Material(elevation: 0, color: Colors.transparent, child: child),
      onReorderItem: (oldIndex, newIndex) {
        final reordered = [...items];
        final item = reordered.removeAt(oldIndex);
        reordered.insert(newIndex, item);
        AppModel.shared.reorderSavedMrt(reordered.map((s) => s.id).toList());
      },
      itemBuilder: (context, index) {
        final station = items[index];
        return Padding(
          key: ValueKey('reorder-mrt-${station.id}'),
          padding: EdgeInsets.only(bottom: index == items.length - 1 ? 0 : 10),
          child: Row(
            children: [
              Expanded(
                child: _StationCard(
                  station: station,
                  onTap: () => widget.onOpenStation(station),
                ),
              ),
              const SizedBox(width: 8),
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.drag_handle_rounded,
                    size: 22,
                    color: context.t.dim,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _stationRow(BuildContext context, MrtGeoStation station) {
    final t = context.t;
    return Dismissible(
      key: ValueKey('fav-mrt-${station.id}'),
      direction: DismissDirection.endToStart,
      background: const SizedBox.shrink(),
      secondaryBackground: _dismissBackground(
        context: context,
        color: t.crit,
        icon: Icons.delete_rounded,
        label: 'Delete',
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
      ),
      confirmDismiss: (_) async {
        AppModel.shared.removeMrtSaved(station);
        return false;
      },
      child: _StationCard(
        station: station,
        onTap: () => widget.onOpenStation(station),
      ),
    );
  }

  // ─── Lines section (saved bus services) ────────────────────────────────
  // Only rendered when non-empty — mirrors `if !m.favServices.isEmpty`.

  List<Widget> _linesSectionSlivers(BuildContext context) {
    final items = AppModel.shared.favServices;
    return [
      SliverToBoxAdapter(child: _sectionHeader(context, label: 'Lines')),
      const SliverToBoxAdapter(child: SizedBox(height: 10)),
      _editing
          ? _reorderableLinesSliver(context, items)
          : SliverToBoxAdapter(child: _staticLines(context, items)),
    ];
  }

  Widget _staticLines(BuildContext context, List<FavService> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _lineRow(context, items[i]),
        ],
      ],
    );
  }

  Widget _reorderableLinesSliver(BuildContext context, List<FavService> items) {
    return SliverReorderableList(
      itemCount: items.length,
      proxyDecorator: (child, index, animation) =>
          Material(elevation: 0, color: Colors.transparent, child: child),
      onReorderItem: (oldIndex, newIndex) {
        final reordered = [...items];
        final item = reordered.removeAt(oldIndex);
        reordered.insert(newIndex, item);
        AppModel.shared.reorderFavServices(reordered.map((f) => f.id).toList());
      },
      itemBuilder: (context, index) {
        final fav = items[index];
        return Padding(
          key: ValueKey('reorder-svc-${fav.id}'),
          padding: EdgeInsets.only(bottom: index == items.length - 1 ? 0 : 10),
          child: Row(
            children: [
              Expanded(child: _lineCard(context, fav)),
              const SizedBox(width: 8),
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.drag_handle_rounded,
                    size: 22,
                    color: context.t.dim,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _lineRow(BuildContext context, FavService fav) {
    final t = context.t;
    return Dismissible(
      key: ValueKey('fav-${fav.id}'),
      direction: DismissDirection.endToStart,
      background: const SizedBox.shrink(),
      secondaryBackground: _dismissBackground(
        context: context,
        color: t.crit,
        icon: Icons.delete_rounded,
        label: 'Delete',
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
      ),
      confirmDismiss: (_) async {
        AppModel.shared.removeFavService(fav);
        return false;
      },
      child: _lineCard(context, fav),
    );
  }

  Widget _lineCard(BuildContext context, FavService fav) {
    final resolved = _resolve(fav);
    final stopCode = resolved?.stopCode ?? fav.stop;
    return _LineCard(
      fav: fav,
      resolved: resolved,
      onTap: stopCode != null ? () => widget.onOpenBus(stopCode, fav.no) : null,
    );
  }

  // ─── Dismiss background helper ────────────────────────────────────────────

  Widget _dismissBackground({
    required BuildContext context,
    required Color color,
    required IconData icon,
    required String label,
    required Alignment alignment,
    required EdgeInsets padding,
  }) {
    // Ink must contrast the `color` fill (always t.crit). In Leyne's MONOCHROME
    // palette t.crit is #111 ink in light mode but **white** in dark mode, so a
    // hardcoded Colors.white icon/label rendered white-on-white in dark mode —
    // the Delete affordance vanished. t.contrastFg is the ink paired with
    // t.crit/t.contrast and flips correctly per mode (dark→#0F0F0F, light→white).
    final t = context.t;
    final ink = t.contrastFg;
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(LyneRadius.lg),
      ),
      alignment: alignment,
      padding: padding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: ink, size: 20),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: ink,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Empty state ──────────────────────────────────────────────────────────
  // Mirrors WSSavedView.emptyState: centred glyph + title + one line of body
  // copy, no CTA button — WSSavedView doesn't have one either.

  /// Spec item 5: a teaching card ("Stops you save appear here with live
  /// timings") plus up to 3 nearest stops, each with a one-tap Save capsule
  /// — replaces the old plain "Nothing saved yet" text-only empty state.
  /// The nearest-stops list is whatever `DataStore.shared.nearby` already
  /// has ranked (silently empty until location is on — Home already owns
  /// the "turn on location" prompt, this screen doesn't duplicate it).
  Widget _emptyState(BuildContext context) {
    final nearby = DataStore.shared.nearby.take(3).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: SoftBlue.card,
              borderRadius: BorderRadius.circular(SoftBlue.cardRadius),
              boxShadow: SoftBlue.cardShadow,
            ),
            child: Column(
              children: [
                Icon(
                  Icons.bookmark_outline_rounded,
                  size: 28,
                  color: SoftBlue.sub,
                ),
                const SizedBox(height: 10),
                Text(
                  'Stops you save appear here with live timings',
                  textAlign: TextAlign.center,
                  style: SoftBlue.sans(
                    14.5,
                    weight: FontWeight.w600,
                    color: SoftBlue.ink,
                  ),
                ),
              ],
            ),
          ),
          if (nearby.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final stop in nearby) ...[
              _nearestSaveRow(context, stop),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }

  Widget _nearestSaveRow(BuildContext context, NearbyStop stop) {
    final name = stop.stopName.isEmpty ? stop.stopCode : stop.stopName;
    return ListenableBuilder(
      listenable: AppModel.shared,
      builder: (context, _) {
        final saved = AppModel.shared.pinForCode(stop.stopCode) != null;
        return SoftCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SoftBlue.sans(
                        14,
                        weight: FontWeight.w600,
                        color: SoftBlue.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    SoftStopCode(stop.stopCode, color: SoftBlue.sub),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => AppModel.shared.togglePin(stop.stopCode),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: saved ? SoftBlue.chipBg : SoftBlue.ink,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    saved ? 'Saved' : 'Save',
                    style: SoftBlue.sans(
                      12.5,
                      weight: FontWeight.w700,
                      color: saved ? SoftBlue.chipInk : Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Resolved arrival ────────────────────────────────────────────────────────

class _Resolved {
  const _Resolved({
    required this.svc,
    required this.stopName,
    required this.stopCode,
  });
  final Service svc;
  final String stopName;
  final String stopCode;
}

// ─── Most-urgent hero candidate ─────────────────────────────────────────────

/// The "Up next" hero candidate — the nearest saved stop and its own mini
/// departure board (spec item 5). See `_SoftFavouritesScreenState._upNext`.
///
/// Restructured 2026-07-25 to match iOS `WSSavedView.savedHero`: the saved
/// STOP names the card and the buses follow it as a board. The countdown ring
/// came out for the same reason it did on Nearby — it spent a third of the
/// card on one bus's number while the other departures at that stop had
/// nowhere to go.
class _UrgentPick {
  const _UrgentPick({
    required this.name,
    required this.meta,
    required this.board,
    required this.decision,
    required this.onOpen,
  });

  /// The stop's nickname if the user set one, else its name — this is the
  /// card's TITLE. Place first, then departures (ui-checklist §2).
  final String name;

  /// `Stop 11119 · 1 min walk · 68m away`, built by `stopCodeLabel`.
  final String meta;

  /// Up to three DISTINCT services at that stop, soonest first. Empty when
  /// the feed has nothing running — the hero still renders (never suppressed)
  /// with "No live arrivals right now".
  final List<({String no, String dest, String etaBig})> board;

  /// The one line on this card that's a decision rather than data:
  /// "Leave now" / "Leave in 4 min". Null without a location fix — the hero
  /// never states a walk time it can't back up.
  final String? decision;

  final VoidCallback onOpen;
}

// ─── Crowd dot chip (saved MRT station rows) ───────────────────────────────

/// Small trailing "● Low"-style chip for a saved station's live crowd
/// reading. Mirrors WSSavedView.swift's WSChip(gauge:text:) at 185-187.
class _CrowdDotChip extends StatelessWidget {
  const _CrowdDotChip({required this.level, required this.t});

  final CrowdLevel level;
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
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _crowdColor(level, t),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            _crowdWord(level),
            style: t.mono(10.5, weight: FontWeight.w600, color: t.dim),
          ),
        ],
      ),
    );
  }
}

/// A single coloured MRT line-code chip (established Android idiom, used
/// consistently across search/home/mrt screens — kept as-is rather than
/// switched to iOS's neutral hard-corner LineBullet).
Widget _lineCodeChip(String code) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: lineColorFor(code),
      borderRadius: BorderRadius.circular(LyneRadius.full),
    ),
    child: Text(
      code,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    ),
  );
}

// ─── Saved stop card ─────────────────────────────────────────────────────────

/// Mirrors WSSavedView.swift's `savedStopRow`: name · "code · ROAD" subline ·
/// capped service-tile row · a trailing soonest-arrival column. No leading
/// icon tile and no walk/distance line — iOS shows neither here. A nickname
/// (HOME/WORK/etc.) renders as a small label above the name via the shared
/// `LabelPill`, matching iOS's small-caps label rather than swapping title
/// and subtitle.
class _StopCard extends StatelessWidget {
  const _StopCard({required this.pin, required this.onTap, this.onLongPress});

  final Pin pin;
  final VoidCallback onTap;

  /// Long-press → rename dialog (spec item 8). Null in read-only contexts.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final code = pin.code;
    final stopName = DataStore.shared.stopName(code);
    final road = DataStore.shared.roadName(code);
    // Distance appended when GPS + this stop's geo position are both known
    // (spec item 5: "distance shown in the meta line") — omitted rather than
    // faked when either is unavailable.
    // Shared metadata format (ui-checklist §2): MIN WALK · METRES, after the
    // labelled code. With no location fix there's neither, so the road name
    // stands in as the "where" rather than leaving the line blank — matching
    // iOS WSSavedView.savedStopCard's `meta`.
    String? metaSuffix;
    final loc = LocationService.shared.lastLocation;
    final latLon = DataStore.shared.stopLatLon(code);
    if (loc != null && latLon != null) {
      final d = haversine(loc.lat, loc.lon, latLon.lat, latLon.lon);
      metaSuffix = '${walkMinutesFor(d)} min walk · ${fmtDistance(d.round())}';
    } else if (road.isNotEmpty) {
      metaSuffix = road.toUpperCase();
    }
    final subtitle = stopCodeLabel(code, suffix: metaSuffix);

    // Service list — respects a pin's tracked subset when set (Android-only
    // per-pin bus selection; iOS's Saved view always shows every service at
    // the stop, but narrowing to what the user actually pinned buses for is
    // a deliberate existing Android feature, not a parity bug — kept as-is).
    final allSvcs = DataStore.shared.servicesFor(code);
    final tracked = pin.tracked;
    final services = (tracked != null && tracked.isNotEmpty)
        ? allSvcs.where((s) => tracked.contains(s.no)).toList()
        : allSvcs;

    final nickname = pin.nickname.trim();

    return Semantics(
      button: true,
      label: 'Open $stopName',
      child: Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(LyneRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (nickname.isNotEmpty) ...[
                        LabelPill(
                          text: nickname,
                          variant: LabelPillVariant.tinted,
                        ),
                        const SizedBox(height: 6),
                      ],
                      // The star chip states "this is saved" on the card
                      // itself. Without it the Saved list was visually
                      // identical to the Nearby list and the state was implied
                      // only by which tab you were on (iOS parity, 2026-07-25).
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              stopName,
                              style: t.sans(
                                17,
                                weight: FontWeight.w600,
                                color: t.fg,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const SoftSavedMark(),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: t.mono(12.5, color: t.dim),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // No route-tile chip row (spec item 8, 2026-07-25:
                      // owner — "too much going on"; deleted along with
                      // `_ServiceChipRow`, which had no other call sites).
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Width-capped (iOS parity note): an unconstrained trailing
                // column takes its full natural width regardless of how
                // little space is left (Flutter always gives a Row's
                // non-flex children unbounded width) — that starved the
                // leading Expanded column down to a sliver, collapsing its
                // service-tile Wrap into a single vertical stack (owner-
                // reported "ETAs render vertically"). Same bug/fix as Home's
                // when-column (see soft_home_screen.dart `_identityRow`).
                // Lowered 150→130 2026-07-03 alongside dropping CrowdMeter's
                // glyphs in _SoonestColumn below — same width-crush finding
                // as Home's `_whenColumn`: the word-only quiet line only
                // needs ~85-125dp, so 130 is a tight backstop rather than
                // the effective width, guaranteeing the stop-name column
                // keeps its share.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 148),
                  child: ListenableBuilder(
                    listenable: AppModel.shared,
                    builder: (context, _) => _SoonestColumn(services: services),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Mini departure board for a saved stop card: up to TWO segmented
/// [SoftBusTimePill]s (spec item 5), soonest first, fixed segment widths so
/// the number/time boundary lines up between the two rows. Replaces the
/// former single-big-ETA + CrowdMeter-word column.
class _SoonestColumn extends StatelessWidget {
  const _SoonestColumn({required this.services});

  final List<Service> services;

  static const double _noWidth = 40;
  static const double _timeWidth = 54;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final sorted = [...services]
      ..sort((a, b) => _liveEtaSec(a, now).compareTo(_liveEtaSec(b, now)));
    final top = sorted.take(2).toList();
    if (top.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < top.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          SoftBusTimePill(
            no: top[i].no,
            etaBig: fmtEta(_liveEtaSec(top[i], now)).big,
            noWidth: _noWidth,
            timeWidth: _timeWidth,
          ),
        ],
      ],
    );
  }
}

// ─── Saved MRT station card ──────────────────────────────────────────────────

/// Mirrors WSSavedView.swift's `savedStationRow`: name · line-names subline
/// (uppercased) · up to 3 coloured line-code chips · a trailing crowd chip
/// when a live reading exists. No leading icon tile, matching iOS.
class _StationCard extends StatelessWidget {
  const _StationCard({required this.station, required this.onTap});

  final MrtGeoStation station;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final crowd = _crowdFor(station);
    final showCrowd = crowd != null && crowd.level != CrowdLevel.unknown;
    final codes = station.codes.take(3).toList();

    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(LyneRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            station.name,
                            style: t.sans(
                              17,
                              weight: FontWeight.w600,
                              color: t.fg,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const SoftSavedMark(),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _lineNames(station.codes).toUpperCase(),
                      style: t.mono(12.5, color: t.dim),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: codes.map(_lineCodeChip).toList(),
                    ),
                  ],
                ),
              ),
              if (showCrowd) ...[
                const SizedBox(width: 8),
                _CrowdDotChip(level: crowd.level, t: t),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Saved line (bus) card ───────────────────────────────────────────────────

/// Mirrors WSSavedView.swift's `lineRow`: a bus-number tile (Android's
/// shared `ServiceBadge`, standing in for iOS's neutral RouteTile) ·
/// destination · "at {stop}" / "Anywhere near you" · a trailing ETA +
/// CrowdMeter(compact:true) column.
class _LineCard extends StatelessWidget {
  const _LineCard({required this.fav, required this.resolved, this.onTap});

  final FavService fav;
  final _Resolved? resolved;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final svc = resolved?.svc;
    final destText = svc?.dest ?? 'Bus ${fav.no}';
    final whereText = fav.stop != null
        ? 'at ${resolved?.stopName ?? DataStore.shared.stopName(fav.stop!)}'
        : 'Anywhere near you';

    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(LyneRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              ServiceBadge(svc: fav.no),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            destText,
                            style: t.sans(
                              15,
                              weight: FontWeight.w700,
                              color: t.fg,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const SoftSavedMark(),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      whereText,
                      style: t.mono(11, color: t.dim),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ListenableBuilder(
                listenable: AppModel.shared,
                builder: (context, _) => _LineEtaColumn(svc: svc),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineEtaColumn extends StatelessWidget {
  const _LineEtaColumn({required this.svc});

  final Service? svc;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final svc = this.svc;
    if (svc == null) {
      return Text(
        '—',
        style: t.mono(16, weight: FontWeight.w600, color: t.faint),
      );
    }
    final eta = fmtEta(_liveEtaSec(svc, DateTime.now()));
    final arriving = eta.big == 'Arr';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        // iOS parity fix — same "Arr" headline bug as _SoonestColumn above:
        // `eta.big` is always the headline, never `eta.small` ("now"/"min").
        // Mirrors WSSavedView.swift's lineRow:
        // `Text(eta.big) + Text(eta.big == "Arr" ? "" : "m")` — note the
        // bare "m" suffix here (not " min") matches iOS's more compact
        // Lines-section readout.
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: eta.big,
                style: t.mono(17, weight: FontWeight.w700, color: t.fg),
              ),
              if (!arriving)
                // 10 → 11: legibility floor (iOS's own value here is 10pt).
                TextSpan(
                  text: 'm',
                  style: t.mono(11, color: t.dim),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        CrowdMeter(load: svc.load, compact: true),
      ],
    );
  }
}
