// SoftSearchScreen — Leyne 2.0 Search (Material 3 Android variant).
//
// Input kind is AUTO-DETECTED — no filter chips, no mode selection.
//   • 6-digit all-numeric query → postal geocode flow (OneMap → nearby stops).
//   • All other queries         → Services section + Bus stops section together.
// Mirrors SoftSearchView.swift's resultsContent model exactly, staying
// Material-native throughout (InkWell ripple, FilledButton, InputChip, etc.).

import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../data/lta_models.dart';
import '../../data/models.dart';
import '../../services/geocode_service.dart';
import '../../state/app_model.dart';
import '../../theme.dart';
import '../../widgets/v2/soft_components.dart';

// Example chips shown in the empty state — value fills the field and
// auto-detect handles the rest. Kind tag mirrors iOS pill label
// (SoftSearchView.swift:28-30 / exampleChips).
const _examples = [
  (value: '17179', kind: 'CODE'),
  (value: '120338', kind: 'POSTAL'),
  (value: 'Clementi', kind: 'PLACE'),
  (value: '96', kind: 'BUS'),
];

/// Returns true when [q] is a 6-digit all-numeric string — treated as a
/// Singapore postal code. All other non-empty queries go through the combined
/// Services + Bus stops path.
bool detectIsPostal(String q) => RegExp(r'^\d{6}$').hasMatch(q);

class SoftSearchScreen extends StatefulWidget {
  const SoftSearchScreen({
    super.key,
    required this.onClose,
    required this.onOpenStop,
    required this.onOpenBus,
  });
  final VoidCallback onClose;
  final ValueChanged<String> onOpenStop;

  /// Open the bus ROUTE view for a service. The first arg is an anchor stop
  /// (the service origin) since the route view is built per (stop, service);
  /// the second is the service number.
  final void Function(String stopCode, String svc) onOpenBus;

  @override
  State<SoftSearchScreen> createState() => _SoftSearchScreenState();
}

class _SoftSearchScreenState extends State<SoftSearchScreen> {
  final _ctrl = TextEditingController();

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
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    setState(() {});
    // Trigger geocode whenever the query becomes (or stays) a 6-digit code,
    // regardless of any former filter state.
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

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _searchBar(context),
              const SizedBox(height: 16),
              Expanded(child: _results(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchBar(BuildContext context) {
    final t = context.t;
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(28),
      child: TextField(
        controller: _ctrl,
        autofocus: true,
        // Always text keyboard — postal detection handles numeric-only input;
        // there's no reason to lock users to a number pad for an auto-detect field.
        keyboardType: TextInputType.text,
        autocorrect: false,
        onChanged: (_) => _onQueryChanged(),
        style: t.mono(14, color: t.fg),
        decoration: InputDecoration(
          hintText: 'Search stop, postal code, or bus',
          hintStyle: t.sans(14, color: t.dim),
          prefixIcon: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.onClose,
          ),
          suffixIcon: _ctrl.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _ctrl.clear();
                    _onQueryChanged();
                  },
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
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

  // ─── Empty state: recents + example chips ────────────────────
  Widget _emptyState(BuildContext context) {
    final t = context.t;
    final recents = AppModel.shared.recents;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Recent searches — shown only when the list is non-empty.
          if (recents.isNotEmpty) ...[
            Text(
              'Recent',
              style: t.mono(11, color: t.dim).copyWith(letterSpacing: 0.8),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in recents)
                  InputChip(
                    avatar: Icon(Icons.history, size: 15, color: t.dim),
                    label: Text(
                      r,
                      style: t.sans(12, weight: FontWeight.w500, color: t.fg),
                    ),
                    onPressed: () {
                      setState(() => _ctrl.text = r);
                      _onQueryChanged();
                    },
                    backgroundColor: t.surface,
                    side: BorderSide(color: t.dim.withValues(alpha: 0.2)),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          // Example chips — always shown; tapping fills the field and
          // auto-detect resolves the kind. KIND tag provides iOS-parity
          // context label (SoftSearchView.swift:96-108).
          Text(
            'Examples',
            style: t.mono(11, color: t.dim).copyWith(letterSpacing: 0.8),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final ex in _examples)
                ActionChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ex.value,
                        style: t.mono(12, weight: FontWeight.w600, color: t.fg),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        ex.kind,
                        style: t.mono(9, weight: FontWeight.w600, color: t.dim),
                      ),
                    ],
                  ),
                  backgroundColor: t.surface,
                  side: BorderSide(color: t.dim.withValues(alpha: 0.2)),
                  // Tap fills the field; auto-detect in _results() handles the rest.
                  onPressed: () {
                    setState(() => _ctrl.text = ex.value);
                    _onQueryChanged();
                  },
                ),
            ],
          ),
        ],
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
          // Leading stop-pin tile — mirrors stopTile in SoftSearchView.swift:178-186.
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
  /// button that forces a fresh geocode. Mirrors SearchSheet.swift:238-267.
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
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
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
  /// Mirrors SoftSearchView.swift:300-309 (emptyHint).
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
