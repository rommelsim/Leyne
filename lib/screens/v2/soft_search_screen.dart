// SoftSearchScreen — Leyne 2.0 Search (Material 3 Android variant).
//
// Input kind is AUTO-DETECTED — no filter chips, no mode selection.
//   • 6-digit all-numeric query → postal geocode flow (OneMap → nearby stops).
//   • All other queries         → Services section + Bus stops section together.
// Mirrors SoftSearchView.swift's layout: large "Search" title, animated
// Cancel button, prominent field (mic visual only), Recent searches vertical
// list, and a 2×2 Browse shortcut grid.

import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../data/lta_models.dart';
import '../../data/models.dart';
import '../../data/search_logic.dart';
import '../../services/geocode_service.dart';
import '../../state/app_model.dart';
import '../../theme.dart';
import '../../widgets/v2/soft_components.dart';
import '../../widgets/v2/soft_tab_bar.dart';

/// Returns true when [q] is a 6-digit all-numeric string — treated as a
/// Singapore postal code. All other non-empty queries go through the combined
/// Services + Bus stops path.
bool detectIsPostal(String q) => RegExp(r'^\d{6}$').hasMatch(q);

// Example values used by the Browse tiles.  Mirrors _examples in the old
// empty state; the kind tag drives Browse tile routing (see _emptyState).
const _exampleStop    = '17179';   // 5-digit stop code
const _exampleBus     = '96';      // bus service number
const _examplePlace   = 'Clementi'; // place name

class SoftSearchScreen extends StatefulWidget {
  const SoftSearchScreen({
    super.key,
    required this.onClose,
    required this.onOpenStop,
    required this.onOpenBus,
    required this.onTab,
  });
  final VoidCallback onClose;
  final ValueChanged<String> onOpenStop;

  /// Open the bus ROUTE view for a service. The first arg is an anchor stop
  /// (the service origin) since the route view is built per (stop, service);
  /// the second is the service number.
  final void Function(String stopCode, String svc) onOpenBus;

  /// Switch to another tab from the bottom bar (pops the search route).
  final ValueChanged<SoftTab> onTab;

  @override
  State<SoftSearchScreen> createState() => _SoftSearchScreenState();
}

class _SoftSearchScreenState extends State<SoftSearchScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

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
    setState(() {});
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
      // Search is a first-class tab (parity with iOS): keep the bottom tab bar
      // visible so it reappears after the keyboard closes. Tapping another tab
      // pops the search route via onTab.
      bottomNavigationBar: SoftBottomBar(
        selection: SoftTab.search,
        onSelect: (tab) {
          if (tab != SoftTab.search) widget.onTab(tab);
        },
      ),
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
              Expanded(
                child: _results(context),
              ),
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
        // Cancel only appears while the field is focused — lets the user
        // dismiss the keyboard and, if they choose, exit via onClose.
        // Uses AnimatedSwitcher so it slides+fades in and out smoothly.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
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
                    _focus.unfocus();
                    widget.onClose();
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
          hintText: 'Search for stops, services or places',
          hintStyle: t.sans(15, color: t.dim),
          // Leading search icon — accent-coloured when text is present.
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 14, right: 10),
            child: Icon(
              Icons.search,
              size: 20,
              color: hasText ? t.accent : t.dim,
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 44,
            minHeight: 44,
          ),
          // Trailing: clear button OR mic icon (visual-only).
          suffixIcon: hasText
              ? IconButton(
                  icon: Icon(Icons.close, size: 18, color: t.dim),
                  onPressed: () {
                    _ctrl.clear();
                    _onQueryChanged();
                  },
                  tooltip: 'Clear',
                )
              : Padding(
                  padding: const EdgeInsets.only(right: 14),
                  // Mic is an inert Icon, not a Button — no dead tap target.
                  // Matches Swift: `Image(systemName: "mic")` with no action.
                  child: Icon(Icons.mic, size: 20, color: t.faint),
                ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 44,
            minHeight: 44,
          ),
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
            borderSide: BorderSide(
              color: t.accent.withValues(alpha: 0.6),
            ),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Recent searches ───────────────────────────────────
          // Shown only when the list is non-empty.
          // Mirrors SoftSearchView.swift recentsSection (lines 188-265).
          if (recents.isNotEmpty) ...[
            _recentsSection(context, t, recents),
            const SizedBox(height: 24),
          ],

          // ── Browse grid ───────────────────────────────────────
          // Always shown. 2×2 shortcut tiles.
          // Mirrors SoftSearchView.swift browseSection (lines 269-320).
          _browseSection(context, t),
        ],
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
      'bus'     => Icons.directions_bus,
      'stopcode' => Icons.location_on,
      'postal' || 'block' || 'text' => Icons.place,
      _         => Icons.history,
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
                  child: Icon(Icons.close, size: 16, color: t.faint),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Browse section ───────────────────────────────────────────
  // 2×2 grid of shortcut tiles. Each tile fills the field and runs the
  // existing search path — no dead buttons.
  //
  // Tile wiring:
  //   Nearby   → onClose() returns to Home's nearby list (no search needed).
  //   Stops    → fills field with _exampleStop ("17179") → stopcode search.
  //   Services → fills field with _exampleBus  ("96")    → bus search.
  //   Places   → fills field with _examplePlace("Clementi") → text search.
  Widget _browseSection(BuildContext context, LyneTheme t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Browse'),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 2.0,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _browseTile(
              context,
              t,
              icon: Icons.near_me,
              label: 'Nearby',
              accent: LyneSignal.meBlue,
              onTap: widget.onClose,
            ),
            _browseTile(
              context,
              t,
              icon: Icons.location_on,
              label: 'Stops',
              accent: t.soon,
              onTap: () {
                setState(() => _ctrl.text = _exampleStop);
                _onQueryChanged();
              },
            ),
            _browseTile(
              context,
              t,
              icon: Icons.directions_bus,
              label: 'Services',
              accent: const Color(0xFFE0683A),
              onTap: () {
                setState(() => _ctrl.text = _exampleBus);
                _onQueryChanged();
              },
            ),
            _browseTile(
              context,
              t,
              icon: Icons.location_city,
              label: 'Places',
              accent: t.dim,
              onTap: () {
                setState(() => _ctrl.text = _examplePlace);
                _onQueryChanged();
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _browseTile(
    BuildContext context,
    LyneTheme t, {
    required IconData icon,
    required String label,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(LyneRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(LyneRadius.md),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: t.line),
            borderRadius: BorderRadius.circular(LyneRadius.md),
          ),
          padding: const EdgeInsets.all(16),
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, size: 22, color: accent),
              Text(
                label,
                style: t.sans(14, weight: FontWeight.w600, color: t.fg),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Combined Services + Bus stops ───────────────────────────
  // Mirrors SoftSearchView.swift:124-141 (resultsContent else branch).
  Widget _combinedResults(BuildContext context, String q) {
    final services = DataStore.shared.searchServices(q);
    final stops = DataStore.shared.searchStops(q);

    if (services.isEmpty && stops.isEmpty) {
      return _emptyHint(
        context,
        'Nothing matches "$q"',
        'Try a stop name, a 5-digit stop code, a 6-digit postal code, or a bus number.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        if (services.isNotEmpty) ...[
          _sectionLabel(context, 'Services'),
          const SizedBox(height: 8),
          for (int i = 0; i < services.length; i++) ...[
            _serviceCard(context, services[i]),
            if (i < services.length - 1) const SizedBox(height: 8),
          ],
        ],
        if (stops.isNotEmpty) ...[
          SizedBox(height: services.isEmpty ? 0 : 16),
          _sectionLabel(context, 'Bus stops'),
          const SizedBox(height: 8),
          for (int i = 0; i < stops.length; i++) ...[
            _stopCard(context, stops[i]),
            if (i < stops.length - 1) const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Text(
        text.toUpperCase(),
        style: t
            .mono(10, weight: FontWeight.w600, color: t.dim)
            .copyWith(letterSpacing: 0.8),
      ),
    );
  }

  Widget _serviceCard(BuildContext context, LtaBusService b) {
    final t = context.t;
    final sub = [
      b.operator_ ?? '',
      if (b.category?.isNotEmpty == true)
        b.category!.substring(0, 1).toUpperCase() + b.category!.substring(1),
    ].where((s) => s.isNotEmpty).join(' · ');
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
                Text(
                  'Service ${b.serviceNo}',
                  style: t.sans(14, weight: FontWeight.w600, color: t.fg),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (sub.isNotEmpty)
                  Text(
                    sub,
                    style: t.mono(11, color: t.dim),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: t.dim),
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
            child: Icon(Icons.location_on, size: 18, color: t.fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stop.description,
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
          Icon(Icons.chevron_right, color: t.dim),
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
    if (stops.isEmpty) {
      // Empty-radius case: append Settings guidance (SoftSearchView.swift:234-236).
      return _emptyHint(
        context,
        'No bus stops within ${_radiusLabel(radius)} of ${geo.label}.',
        'Widen the search radius in Settings.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: stops.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              '${geo.label} · ${stops.length} stop'
              '${stops.length == 1 ? "" : "s"} within ${_radiusLabel(radius)}',
              style: t.mono(11, color: t.dim),
            ),
          );
        }
        return _postalCard(context, stops[i - 1]);
      },
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
              icon: const Icon(Icons.refresh, size: 16),
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
          Icon(Icons.chevron_right, color: t.dim),
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

  /// Two-line empty-results hint with title + subtitle, centred.
  /// Mirrors SoftSearchView.swift:521-530 (emptyHint).
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
