// SoftSearchScreen — Leyne 2.0 Search (Material 3 Android variant).
//
// Input kind is AUTO-DETECTED — no mode selection, just typing.
//   • 6-digit all-numeric query → postal geocode flow (OneMap → nearby MRT
//     + bus stops).
//   • All other queries         → combined MRT stations / Services / Bus
//     stops results, narrowable via the All · Bus · MRT · Stops chip row.
// Content parity with WSSearchView.swift (not a visual clone): large
// "Search" title, animated Cancel button, a prominent field (clear-X only,
// no mic action), matched-query bolding in result titles, and a Recent
// searches list. (The Browse example-tile grid was removed — it injected
// hard-coded example queries that read as placeholder/mock data.)

import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../data/lta_models.dart';
import '../../data/models.dart';
import '../../data/mrt_geo.dart';
import '../../data/mrt_stations.dart';
import '../../data/search_logic.dart';
import '../../data/spell_suggest.dart';
import '../../services/analytics_service.dart';
import '../../services/geocode_service.dart';
import '../../state/app_model.dart';
import '../../theme.dart';
import '../../widgets/v2/soft_components.dart';
import '../../widgets/v2/soft_tab_bar.dart';

/// Returns true when [q] is a 6-digit all-numeric string — treated as a
/// Singapore postal code. All other non-empty queries go through the combined
/// Services + Bus stops path.
bool detectIsPostal(String q) => RegExp(r'^\d{6}$').hasMatch(q);

class SoftSearchScreen extends StatefulWidget {
  const SoftSearchScreen({
    super.key,
    required this.onOpenStop,
    required this.onOpenBus,
    required this.onOpenStation,
    required this.onTab,
  });
  final ValueChanged<String> onOpenStop;

  /// Open the bus ROUTE view for a service. The first arg is an anchor stop
  /// (the service origin) since the route view is built per (stop, service);
  /// the second is the service number.
  final void Function(String stopCode, String svc) onOpenBus;

  /// Push the MRT station detail screen for a tapped search result.
  /// Walk/distance are null when opened from Search (no location context).
  final void Function(MrtGeoStation station) onOpenStation;

  /// Switch to another tab from the bottom bar (pops the search route).
  final ValueChanged<SoftTab> onTab;

  @override
  State<SoftSearchScreen> createState() => _SoftSearchScreenState();
}

// ─── Search filter enum ───────────────────────────────────────────────────────

enum _SearchFilter { all, stops, buses, mrt }

// ─── State ────────────────────────────────────────────────────────────────────

class _SoftSearchScreenState extends State<SoftSearchScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  _SearchFilter _filter = _SearchFilter.all;

  // Log one search_performed per search session: fire on the keystroke that
  // first makes the query non-empty, then re-arm once it's cleared. Avoids one
  // analytics event per character while still counting each distinct search.
  // Mirrors iOS SoftSearchView (`loggedSearchSession`).
  bool _loggedSearchSession = false;

  // Postal-code geocoding state — `_geoFor` is the code `_geo` resolved for,
  // so each distinct code geocodes at most once. `_geo` is null while loading
  // or after a failure.
  String? _geoFor;
  GeoPlace? _geo;
  bool _geoLoading = false;
  bool _geoFailed = false;

  @override
  void initState() {
    super.initState();
    // Warm the (large, lazy) BusRoutes dataset as soon as Search opens, while
    // the user is still typing. Tapping a bus result needs it (originStop +
    // the route view's serviceRoute); pre-loading here makes that tap open the
    // bus view immediately instead of blocking on a cold dataset fetch.
    DataStore.shared.ensureRoutes();

    // Rebuild the header whenever field focus changes so the Cancel button
    // animates in/out correctly.
    _focus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onFocusChanged() => setState(() {});

  void _onQueryChanged() {
    // Reset the category filter on every new query so results from a prior
    // search don't leave the user looking at an empty filtered view.
    setState(() => _filter = _SearchFilter.all);
    final hasQuery = _ctrl.text.trim().isNotEmpty;
    if (hasQuery && !_loggedSearchSession) {
      _loggedSearchSession = true;
      AnalyticsService.searchPerformed();
    } else if (!hasQuery) {
      _loggedSearchSession = false;
    }
    _maybeGeocode(_ctrl.text);
  }

  /// Geocode a 6-digit postal code not yet resolved. `force` retries a code
  /// that previously failed. Never throws — GeocodeService collapses any
  /// network/parse error to a null place, surfaced as the "couldn't find" note.
  void _maybeGeocode(String raw, {bool force = false}) {
    final q = raw.trim();
    if (!detectIsPostal(q)) {
      // Not a postal code — reset stale geo state so re-entering a postal
      // code later triggers a fresh lookup.
      if (_geoFor != null) {
        setState(() {
          _geoFor = null;
          _geo = null;
          _geoLoading = false;
          _geoFailed = false;
        });
      }
      return;
    }
    if (!force && q == _geoFor) return;
    setState(() {
      _geoFor = q;
      _geo = null;
      _geoFailed = false;
      _geoLoading = true;
    });
    GeocodeService.shared.postalCode(q).then((place) {
      // Drop a stale result if the query moved on while we waited.
      if (!mounted || _geoFor != q) return;
      setState(() {
        _geoLoading = false;
        _geo = place;
        _geoFailed = place == null;
      });
    });
  }

  // ─── Build ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      // No bottom tab bar: Search is no longer a tab (it's reached from the
      // Home search bar, iOS parity — WSSearchView is a sheet with no tab
      // chrome). The bar also had nothing valid to highlight since the
      // Search destination was removed from SoftTabBar.
      // Dismiss keyboard when tapping outside the field — mirrors iOS
      // `.onTapGesture { focused = false }` on the background view.
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _focus.unfocus(),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _headerRow(context),
                    const SizedBox(height: 14),
                    _fieldRow(context),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
              Expanded(child: _results(context)),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Header: "Search" title + animated Cancel button ─────────
  // Mirrors SoftSearchView.swift headerRow (lines 81-105).
  Widget _headerRow(BuildContext context) {
    final t = context.t;
    final focused = _focus.hasFocus;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Search',
          style: t.sans(28, weight: FontWeight.w700, color: t.fg),
        ),
        const Spacer(),
        // Cancel only appears while the field is focused — it clears the query
        // and dismisses the keyboard, but STAYS on Search (matching iOS, where
        // Cancel does not leave the Search surface). To exit Search the user
        // uses the bottom tab bar or system back — Cancel must not pop the route.
        // Uses AnimatedSwitcher so it slides+fades in and out smoothly.
        AnimatedSwitcher(
          duration: LyneMotion.short,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.3, 0),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: focused
              ? TextButton(
                  key: const ValueKey('cancel'),
                  onPressed: () {
                    _ctrl.clear();
                    _onQueryChanged();
                    _focus.unfocus();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: LyneSignal.meBlue,
                    textStyle: t.sans(14, weight: FontWeight.w500),
                    minimumSize: const Size(48, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  child: const Text('Cancel'),
                )
              : const SizedBox.shrink(key: ValueKey('no-cancel')),
        ),
      ],
    );
  }

  // ─── Search field ─────────────────────────────────────────────
  // Mirrors SoftSearchView.swift fieldRow (lines 109-144).
  // Trailing: clear X when text present, else a mic icon (non-interactive
  // visual only — no speech backend exists).
  Widget _fieldRow(BuildContext context) {
    final t = context.t;
    final hasText = _ctrl.text.isNotEmpty;
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(LyneRadius.md),
      child: TextField(
        controller: _ctrl,
        focusNode: _focus,
        // No autofocus — the keyboard opens only when the user taps the field,
        // not the moment the Search tab opens (user-reported).
        autofocus: false,
        keyboardType: TextInputType.text,
        autocorrect: false,
        onChanged: (_) => _onQueryChanged(),
        style: t.sans(15, weight: FontWeight.w500, color: t.fg),
        decoration: InputDecoration(
          hintText: 'Stop, bus, MRT or postal code',
          hintStyle: t.sans(15, color: t.dim),
          // Leading search icon — accent-coloured when text is present.
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 14, right: 10),
            child: Icon(
              Icons.search_rounded,
              size: 20,
              color: hasText ? t.accent : t.dim,
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 44,
            minHeight: 44,
          ),
          // Trailing: clear button when there's text, nothing otherwise — the
          // old mic glyph was a dead tap target (no speech backend exists).
          suffixIcon: hasText
              ? IconButton(
                  icon: Icon(Icons.close_rounded, size: 18, color: t.dim),
                  onPressed: () {
                    _ctrl.clear();
                    _onQueryChanged();
                  },
                  tooltip: 'Clear',
                )
              : null,
          suffixIconConstraints: hasText
              ? const BoxConstraints(minWidth: 44, minHeight: 44)
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(LyneRadius.md),
            borderSide: BorderSide(color: t.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(LyneRadius.md),
            borderSide: BorderSide(color: t.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(LyneRadius.md),
            borderSide: BorderSide(color: t.accent.withValues(alpha: 0.6)),
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 14,
            horizontal: 14,
          ),
          filled: true,
          fillColor: t.surface,
        ),
      ),
    );
  }

  // ─── Results dispatcher ───────────────────────────────────────
  Widget _results(BuildContext context) {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return _emptyState(context);
    if (detectIsPostal(q)) return _postalResults(context, q);
    return _combinedResults(context, q);
  }

  // ─── Empty state: recent searches + browse grid ───────────────
  // Mirrors SoftSearchView.swift emptyState (lines 176-184).
  // Wraps in ListenableBuilder so removeRecent/clearRecents (which call
  // notifyListeners) automatically rebuild the list without needing the
  // parent TextField setState.
  Widget _emptyState(BuildContext context) {
    return ListenableBuilder(
      listenable: AppModel.shared,
      builder: (context, _) => _emptyStateContent(context),
    );
  }

  Widget _emptyStateContent(BuildContext context) {
    final t = context.t;
    final recents = AppModel.shared.recents;
    // No Browse grid — it injected hard-coded example queries (17179 / 96 /
    // Clementi) that read as placeholder data. With nothing recent, show a
    // quiet prompt; the auto-detecting field does the rest.
    if (recents.isEmpty) return _searchPrompt(context, t);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: _recentsSection(context, t, recents),
    );
  }

  /// Quiet empty-state prompt shown when there are no recent searches.
  Widget _searchPrompt(BuildContext context, LyneTheme t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_rounded, size: 40, color: t.faint),
            const SizedBox(height: 12),
            Text(
              'Find a stop, bus or place',
              style: t.sans(15, weight: FontWeight.w600, color: t.fg),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Search by stop name, 5-digit stop code, bus number, '
              'or 6-digit postal code.',
              style: t.sans(12, color: t.dim),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Recent searches section ──────────────────────────────────
  Widget _recentsSection(
    BuildContext context,
    LyneTheme t,
    List<String> recents,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row: "RECENT SEARCHES" eyebrow + "Clear" button.
        Row(
          children: [
            const Eyebrow('Recent searches'),
            const Spacer(),
            TextButton(
              onPressed: () {
                AppModel.shared.clearRecents();
              },
              style: TextButton.styleFrom(
                foregroundColor: LyneSignal.meBlue,
                textStyle: t.sans(13, weight: FontWeight.w500),
                minimumSize: const Size(48, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              child: const Text('Clear'),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Vertical list of recent rows.
        Column(
          children: [
            for (int i = 0; i < recents.length; i++) ...[
              _recentRow(context, t, recents[i]),
              if (i < recents.length - 1) const SizedBox(height: 6),
            ],
          ],
        ),
      ],
    );
  }

  // A single recent-search row.
  // Mirrors SoftSearchView.swift recentRow (lines 214-265).
  Widget _recentRow(BuildContext context, LyneTheme t, String recent) {
    final kind = detectQueryKind(recent).kind;
    final IconData icon = switch (kind) {
      'bus' => Icons.directions_bus_rounded,
      'stopcode' => Icons.location_on_rounded,
      'postal' || 'block' || 'text' => Icons.place,
      _ => Icons.history,
    };

    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(LyneRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(LyneRadius.md),
        onTap: () {
          setState(() => _ctrl.text = recent);
          _onQueryChanged();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              // Leading icon tile — surfaceHi rounded square.
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: t.surfaceHi,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 14, color: t.dim),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  recent,
                  style: t.sans(14, weight: FontWeight.w500, color: t.fg),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Trailing remove button — distinct tap area, does not trigger
              // the row body's onTap (absorbs its pointer events).
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => AppModel.shared.removeRecent(recent),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, size: 16, color: t.faint),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Combined Services + Bus stops + MRT stations ────────────
  // Mirrors SoftSearchView.swift:124-141 (resultsContent else branch),
  // extended with an "MRT stations" section from MrtGeo.matching().
  // The segmented filter control sits above the list; each section is gated
  // by the active filter. Per-filter empty hints appear when a specific
  // (non-.all) filter yields no matches in that category.
  Widget _combinedResults(BuildContext context, String q) {
    final services = DataStore.shared.searchServices(q);
    final stops = DataStore.shared.searchStops(q);
    final stations = MrtGeo.matching(q);

    // Global empty — offer a "Did you mean …?" correction over the transit
    // vocabulary (stop names, road names, MRT stations) before the catch-all
    // hint. Tapping fills the field, mirroring iOS's WSSpell row.
    if (services.isEmpty && stops.isEmpty && stations.isEmpty) {
      final suggestion = SpellSuggest.suggest(
        q,
        () => [
          ...DataStore.shared.stopByCode.values.expand(
            (s) => [s.description, s.roadName],
          ),
          ...MrtGeo.all.map((s) => s.name),
        ],
      );
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (suggestion != null) ...[
                _didYouMeanRow(context, suggestion),
                const SizedBox(height: 18),
              ],
              Text(
                'Nothing matches "$q"',
                style: context.t.sans(13, weight: FontWeight.w600, color: context.t.fg),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Try a stop name, a 5-digit stop code, a 6-digit postal code, a bus number, or an MRT station.',
                style: context.t.sans(11, color: context.t.dim),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Derive which sections are visible under the active filter.
    final showBuses =
        _filter == _SearchFilter.all || _filter == _SearchFilter.buses;
    final showStops =
        _filter == _SearchFilter.all || _filter == _SearchFilter.stops;
    final showMrt =
        _filter == _SearchFilter.all || _filter == _SearchFilter.mrt;

    // Per-specific-filter empty hints (only when a non-.all filter is active
    // and that category has no matches for this query).
    final busesEmpty =
        _filter == _SearchFilter.buses && services.isEmpty;
    final stopsEmpty =
        _filter == _SearchFilter.stops && stops.isEmpty;
    final mrtEmpty =
        _filter == _SearchFilter.mrt && stations.isEmpty;

    // Track whether any prior section was rendered (for inter-section spacing).
    var sectionRendered = false;

    // Build children list so spacing between sections is correct. Order is
    // MRT stations → Services → Bus stops, matching WSSearchView.swift's
    // `results` view.
    final items = <Widget>[];

    if (showMrt) {
      if (mrtEmpty) {
        items.add(_filterEmptyHint(context, 'No stations match "$q"'));
      } else if (stations.isNotEmpty) {
        items.add(_sectionLabel(context, 'MRT stations'));
        items.add(const SizedBox(height: 8));
        for (int i = 0; i < stations.length; i++) {
          items.add(_stationCard(context, stations[i]));
          if (i < stations.length - 1) items.add(const SizedBox(height: 8));
        }
        sectionRendered = true;
      }
    }

    if (showBuses) {
      if (busesEmpty) {
        if (sectionRendered) items.add(const SizedBox(height: 16));
        items.add(_filterEmptyHint(context, 'No buses match "$q"'));
      } else if (services.isNotEmpty) {
        if (sectionRendered) items.add(const SizedBox(height: 16));
        items.add(_sectionLabel(context, 'Services'));
        items.add(const SizedBox(height: 8));
        for (int i = 0; i < services.length; i++) {
          items.add(_serviceCard(context, services[i]));
          if (i < services.length - 1) items.add(const SizedBox(height: 8));
        }
        sectionRendered = true;
      }
    }

    if (showStops) {
      if (stopsEmpty) {
        if (sectionRendered) items.add(const SizedBox(height: 16));
        items.add(_filterEmptyHint(context, 'No stops match "$q"'));
      } else if (stops.isNotEmpty) {
        if (sectionRendered) items.add(const SizedBox(height: 16));
        items.add(
          _sectionLabel(context, 'Bus stops', meta: '${stops.length}'),
        );
        items.add(const SizedBox(height: 8));
        for (int i = 0; i < stops.length; i++) {
          items.add(_stopCard(context, stops[i]));
          if (i < stops.length - 1) items.add(const SizedBox(height: 8));
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        // Filter control: above results, below the search field.
        _searchFilterControl(context),
        const SizedBox(height: 12),
        ...items,
      ],
    );
  }

  // ─── Search filter segmented control ─────────────────────────────────────
  // Reuses the exact pill/container pattern from SoftFavouritesScreen so
  // both screens look consistent. Shown only when there is an active query
  // with combined results (not postal, not empty state).
  Widget _searchFilterControl(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(LyneRadius.md),
      ),
      child: Row(
        children: [
          _searchFilterPill(context, 'All', _SearchFilter.all, t),
          _searchFilterPill(context, 'Bus', _SearchFilter.buses, t),
          _searchFilterPill(context, 'MRT', _SearchFilter.mrt, t),
          _searchFilterPill(context, 'Stops', _SearchFilter.stops, t),
        ],
      ),
    );
  }

  Widget _searchFilterPill(
    BuildContext context,
    String label,
    _SearchFilter value,
    LyneTheme t,
  ) {
    final active = _filter == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filter = value),
        child: AnimatedContainer(
          duration: LyneMotion.short,
          curve: LyneMotion.standardCurve,
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: active ? t.soon : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: t.sans(
              13,
              weight: FontWeight.w600,
              color: active ? t.contrastFg : t.dim,
            ),
          ),
        ),
      ),
    );
  }

  /// [meta], when given, appends a "· N" count — used on "Bus stops" so a
  /// long result list previews its size before scrolling (WSSearchView.swift
  /// passes the same count as the section header's `meta`).
  Widget _sectionLabel(BuildContext context, String text, {String? meta}) {
    final t = context.t;
    final label = meta == null ? text.toUpperCase() : '${text.toUpperCase()} · $meta';
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Text(
        label,
        style: t
            .mono(10, weight: FontWeight.w600, color: t.dim)
            .copyWith(letterSpacing: 0.8),
      ),
    );
  }

  Widget _serviceCard(BuildContext context, LtaBusService b) {
    final t = context.t;
    // "To {destination}" replaces the old operator·category subline —
    // destination via the same DTO the row already carries. Mirrors
    // WSSearchView.swift's serviceRow (`dest.isEmpty ? "SERVICE" : "SERVICE
    // · TO \(dest)"`, simplified here to match this card's one-line style).
    final destCode = b.destinationCode;
    final dest = (destCode == null || destCode.isEmpty)
        ? ''
        : DataStore.shared.stopName(destCode);
    return _card(
      context,
      onTap: () => _pickBus(b.serviceNo),
      child: Row(
        children: [
          ServiceBadge(svc: b.serviceNo, size: ServiceBadgeSize.sm),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _highlightMatch(
                  'Service ${b.serviceNo}',
                  _ctrl.text.trim(),
                  style: t.sans(14, weight: FontWeight.w600, color: t.fg),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (dest.isNotEmpty)
                  Text(
                    'To $dest',
                    style: t.mono(11, color: t.dim),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: t.dim),
        ],
      ),
    );
  }

  Widget _stopCard(BuildContext context, LtaBusStop stop) {
    final t = context.t;
    return _card(
      context,
      onTap: () => _pickStop(stop.busStopCode),
      child: Row(
        children: [
          // Leading stop-pin tile — mirrors stopTile in SoftSearchView.swift:388-396.
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: t.surfaceHi,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.location_on_rounded, size: 18, color: t.fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _highlightMatch(
                  stop.description,
                  _ctrl.text.trim(),
                  style: t.sans(14, weight: FontWeight.w600, color: t.fg),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Stop ${stop.busStopCode} · ${stop.roadName}',
                  style: t.mono(11, color: t.dim),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: t.dim),
        ],
      ),
    );
  }

  Widget _stationCard(BuildContext context, MrtGeoStation station) {
    final t = context.t;
    return _card(
      context,
      onTap: () => _pickStation(station),
      child: Row(
        children: [
          // Leading tram-icon tile — mirrors stopTile style.
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: t.surfaceHi,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.train_rounded, size: 18, color: t.fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _highlightMatch(
                  station.name,
                  _ctrl.text.trim(),
                  style: t.sans(14, weight: FontWeight.w600, color: t.fg),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                // Coloured line-code pills.
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: station.codes.map((code) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: lineColorFor(code),
                        borderRadius: BorderRadius.circular(LyneRadius.full),
                      ),
                      child: Text(
                        code,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: t.dim),
        ],
      ),
    );
  }

  // ─── Postal ───────────────────────────────────────────────────
  // Mirrors SoftSearchView.swift:221-251 (postalResults).
  Widget _postalResults(BuildContext context, String q) {
    final t = context.t;
    // Reference data must be loaded before stops can be ranked by distance.
    final refState = DataStore.shared.referenceState;
    if (refState.state == LoadState.loading) {
      return _centerNote(context, 'Loading bus stops…', spinner: true);
    }
    if (refState.state == LoadState.error) {
      return _centerNote(
        context,
        refState.errorMessage ?? "Couldn't load bus stops.",
      );
    }
    if (_geoLoading) {
      return _centerNote(context, 'Finding postal code $q…', spinner: true);
    }
    final geo = _geo;
    // Geo failed or not yet resolved — show distinct copy + retry button.
    if (geo == null) {
      return _postalFailState(context, q);
    }
    final radius = AppModel.shared.searchRadiusM;
    final stops = DataStore.shared.stopsWithin(geo.lat, geo.lon, radius);
    // Nearest MRT stations to the postal point (≤ 3, within a ~20-min walk) —
    // parity with iOS's "MRT near {postal}" section.
    final mrtNear = MrtGeo.nearest(lat: geo.lat, lon: geo.lon, limit: 3)
        .where((r) => r.distanceM <= 1600)
        .toList();
    if (stops.isEmpty && mrtNear.isEmpty) {
      // Empty-radius case: append Settings guidance (SoftSearchView.swift:234-236).
      return _emptyHint(
        context,
        'No bus stops within ${_radiusLabel(radius)} of ${geo.label}.',
        'Widen the search radius in Settings.',
      );
    }
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 4),
        child: Text(
          '${geo.label} · ${stops.length} stop'
          '${stops.length == 1 ? "" : "s"} within ${_radiusLabel(radius)}',
          style: t.mono(11, color: t.dim),
        ),
      ),
    ];
    // Two independent sections (not nested) — each shows its own "near {q}"
    // header whenever it has results, regardless of whether the other
    // section is empty. Mirrors WSSearchView.swift's postalResults, which
    // renders "MRT near {trimmed}" and "Bus stops near {trimmed}" as
    // separate `if`s rather than one gating the other.
    if (mrtNear.isNotEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(_sectionLabel(context, 'MRT near $q'));
      children.add(const SizedBox(height: 8));
      for (int i = 0; i < mrtNear.length; i++) {
        children.add(_postalStationCard(context, mrtNear[i]));
        children.add(const SizedBox(height: 8));
      }
    }
    if (stops.isNotEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(_sectionLabel(context, 'Bus stops near $q'));
      children.add(const SizedBox(height: 8));
      for (int i = 0; i < stops.length; i++) {
        children.add(_postalCard(context, stops[i]));
        if (i < stops.length - 1) children.add(const SizedBox(height: 8));
      }
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: children,
    );
  }

  /// A postal-result MRT station card: distance/walk column (matching
  /// _postalCard) + station name + coloured line pills.
  Widget _postalStationCard(BuildContext context, MrtNearestResult r) {
    final t = context.t;
    return _card(
      context,
      onTap: () => _pickStation(r.station),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${r.distanceM} m',
                  style: t.mono(14, weight: FontWeight.w600, color: t.fg),
                ),
                Text('${r.walkMin} min', style: t.mono(10, color: t.dim)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.station.name,
                  style: t.sans(14, weight: FontWeight.w600, color: t.fg),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: r.station.codes.map((code) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: lineColorFor(code),
                        borderRadius: BorderRadius.circular(LyneRadius.full),
                      ),
                      child: Text(
                        code,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: t.dim),
        ],
      ),
    );
  }

  /// Shown when geo == null after loading completes: distinguishes a network
  /// failure (_geoFailed == true) from a genuine not-found. Adds a Retry
  /// button that forces a fresh geocode. Mirrors SoftSearchView.swift:467-473.
  Widget _postalFailState(BuildContext context, String q) {
    final t = context.t;
    final isNetworkError = _geoFailed;
    final title = isNetworkError
        ? "Can't look up postal codes right now."
        : "Couldn't find postal code $q.";
    final sub = isNetworkError
        ? 'Check your connection and try again.'
        : 'Check the 6-digit code and try again.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: t.sans(13, weight: FontWeight.w600, color: t.fg),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              sub,
              style: t.sans(11, color: t.dim),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
              onPressed: () => _maybeGeocode(_ctrl.text, force: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _postalCard(BuildContext context, NearbyStop s) {
    final t = context.t;
    return _card(
      context,
      onTap: () => _pickStop(s.stopCode),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${s.distanceM} m',
                  style: t.mono(14, weight: FontWeight.w600, color: t.fg),
                ),
                Text('${s.walkMin} min', style: t.mono(10, color: t.dim)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.stopName,
                  style: t.sans(14, weight: FontWeight.w600, color: t.fg),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Stop ${s.stopCode}',
                  style: t.mono(11, color: t.dim),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: t.dim),
        ],
      ),
    );
  }

  // ─── Shared helpers ───────────────────────────────────────────
  Widget _card(
    BuildContext context, {
    required VoidCallback onTap,
    required Widget child,
  }) {
    final t = context.t;
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(LyneRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(LyneRadius.md),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(14), child: child),
      ),
    );
  }

  Widget _centerNote(BuildContext context, String msg, {bool spinner = false}) {
    final t = context.t;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spinner) ...[
            CircularProgressIndicator(color: t.dim, strokeWidth: 2),
            const SizedBox(height: 12),
          ],
          Text(
            msg,
            style: t.sans(13, color: t.dim),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Inline single-line hint shown when a specific filter (non-.all) has no
  /// matches in that category. Rendered inside the results list — not centred
  /// full-screen — so it coexists with the filter control and stays at the
  /// top of the list area rather than vertically centred.
  Widget _filterEmptyHint(BuildContext context, String text) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4),
      child: Text(
        text,
        style: t.sans(13, color: t.dim),
      ),
    );
  }

  /// Two-line empty-results hint with title + subtitle, centred.
  /// Mirrors SoftSearchView.swift:521-530 (emptyHint).
  /// Tappable "Did you mean Clementi?" chip — fills the search field with the
  /// corrected query (same pattern as a recent-search tap).
  Widget _didYouMeanRow(BuildContext context, String suggestion) {
    final t = context.t;
    return ActionChip(
      avatar: Icon(Icons.auto_fix_high_rounded, size: 16, color: t.accent),
      label: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: 'Did you mean ', style: t.sans(13, color: t.dim)),
            TextSpan(
              text: suggestion,
              style: t.sans(13, weight: FontWeight.w700, color: t.fg),
            ),
            TextSpan(text: '?', style: t.sans(13, color: t.dim)),
          ],
        ),
      ),
      onPressed: () => setState(() => _ctrl.text = suggestion),
    );
  }

  Widget _emptyHint(BuildContext context, String title, String sub) {
    final t = context.t;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: t.sans(13, weight: FontWeight.w600, color: t.fg),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              sub,
              style: t.sans(11, color: t.dim),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _pickStop(String code) {
    final q = _ctrl.text.trim();
    AppModel.shared.addRecent(q.isEmpty ? DataStore.shared.stopName(code) : q);
    widget.onOpenStop(code);
  }

  void _pickStation(MrtGeoStation station) {
    final q = _ctrl.text.trim();
    AppModel.shared.addRecent(q.isEmpty ? station.name : q);
    widget.onOpenStation(station);
  }

  Future<void> _pickBus(String serviceNo) async {
    // Anchor the route view at the service origin and show the WHOLE route —
    // a bus search means "show me bus N's route", not a single stop's arrivals.
    final origin = await DataStore.shared.originStop(serviceNo);
    if (!mounted || origin == null) return;
    AppModel.shared.addRecent(serviceNo);
    widget.onOpenBus(origin.busStopCode, serviceNo);
  }

  /// '500 m', '1 km', '1.5 km' — for the postal summary line.
  String _radiusLabel(int m) => m < 1000
      ? '$m m'
      : '${(m / 1000).toStringAsFixed(m % 1000 == 0 ? 0 : 1)} km';
}

// ─── Query highlighting (bold the matched substring) ──────────────────────
// Port of WSSearchView.swift's wsHighlightRaw/wsHighlight: finds the first
// case-insensitive occurrence of [query] inside [text] and renders it in a
// heavier weight, leaving the rest of the string at [style]'s own weight.
Widget _highlightMatch(
  String text,
  String query, {
  required TextStyle style,
  int? maxLines,
  TextOverflow? overflow,
}) {
  final q = query.trim();
  final idx = q.isEmpty ? -1 : text.toLowerCase().indexOf(q.toLowerCase());
  if (idx < 0) {
    return Text(text, style: style, maxLines: maxLines, overflow: overflow);
  }
  final pre = text.substring(0, idx);
  final match = text.substring(idx, idx + q.length);
  final post = text.substring(idx + q.length);
  return Text.rich(
    TextSpan(
      style: style,
      children: [
        if (pre.isNotEmpty) TextSpan(text: pre),
        TextSpan(text: match, style: const TextStyle(fontWeight: FontWeight.w800)),
        if (post.isNotEmpty) TextSpan(text: post),
      ],
    ),
    maxLines: maxLines,
    overflow: overflow,
  );
}
