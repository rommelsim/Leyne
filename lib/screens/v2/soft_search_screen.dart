// SoftSearchScreen — Leyne 2.0 Search (Material 3 Android variant).
//
// The filter chips are REAL — each routes to a different data path:
//   • Postal     → OneMap geocode (GeocodeService) → stops within searchRadiusM
//   • Bus #      → searchServices → open the service's origin stop
//   • Stop ID    → searchStops (code match)
//   • Place      → searchStops (name match)
// Until 2.3.x every chip silently called searchStops; the postal + bus paths
// already existed in the data layer (and on iOS) but this screen never invoked
// them, so three of the four chips were decorative. Mirrors the V1 SearchScreen
// dispatch (lib/screens/search_screen.dart).

import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../data/lta_models.dart';
import '../../data/models.dart';
import '../../services/geocode_service.dart';
import '../../state/app_model.dart';
import '../../theme.dart';
import '../../widgets/v2/soft_components.dart';

enum SoftSearchFilter { postal, stopID, busNo, place }

// Example chips shown in the empty state — value fills the field, kind
// maps to the matching filter. Mirrors SoftSearchView.swift:28-30.
const _examples = [
  (value: '17179', filter: SoftSearchFilter.stopID),
  (value: '120338', filter: SoftSearchFilter.postal),
  (value: 'Clementi', filter: SoftSearchFilter.place),
  (value: '96', filter: SoftSearchFilter.busNo),
];

class SoftSearchScreen extends StatefulWidget {
  const SoftSearchScreen(
      {super.key, required this.onClose, required this.onOpenStop});
  final VoidCallback onClose;
  final ValueChanged<String> onOpenStop;

  @override
  State<SoftSearchScreen> createState() => _SoftSearchScreenState();
}

class _SoftSearchScreenState extends State<SoftSearchScreen> {
  final _ctrl = TextEditingController();
  SoftSearchFilter _filter = SoftSearchFilter.stopID;

  // Postal-code geocoding state — `_geoFor` is the code `_geo` resolved for, so
  // each code geocodes at most once. `_geo` is null while loading or failed.
  String? _geoFor;
  GeoPlace? _geo;
  bool _geoLoading = false;
  bool _geoFailed = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    setState(() {});
    if (_filter == SoftSearchFilter.postal) _maybeGeocode(_ctrl.text);
  }

  void _onFilterChanged(SoftSearchFilter v) {
    setState(() => _filter = v);
    if (v == SoftSearchFilter.postal) _maybeGeocode(_ctrl.text);
  }

  /// Geocode a 6-digit postal code not yet resolved. `force` retries a code
  /// that previously failed. Never throws — GeocodeService collapses any
  /// network/parse error to a null place, surfaced as the "couldn't find" note.
  void _maybeGeocode(String raw, {bool force = false}) {
    final q = raw.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(q)) {
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
              SortChipRow<SoftSearchFilter>(
                selection: _filter,
                options: const [
                  (value: SoftSearchFilter.postal, label: 'Postal'),
                  (value: SoftSearchFilter.stopID, label: 'Stop ID'),
                  (value: SoftSearchFilter.busNo, label: 'Bus #'),
                  (value: SoftSearchFilter.place, label: 'Place'),
                ],
                onSelect: _onFilterChanged,
              ),
              const SizedBox(height: 12),
              if (_ctrl.text.trim().isNotEmpty)
                Text(_detected(), style: t.mono(11, color: t.dim)),
              const SizedBox(height: 8),
              Expanded(child: _results(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchBar(BuildContext context) {
    final t = context.t;
    final postal = _filter == SoftSearchFilter.postal;
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(28),
      child: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: postal ? TextInputType.number : TextInputType.text,
        onChanged: (_) => _onQueryChanged(),
        style: t.mono(14, color: t.fg),
        decoration: InputDecoration(
          hintText: 'Postal · Stop ID · Bus# · Place',
          hintStyle: t.sans(14, color: t.dim),
          prefixIcon: IconButton(
              icon: const Icon(Icons.arrow_back), onPressed: widget.onClose),
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
              borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _results(BuildContext context) {
    final q = _ctrl.text.trim();
    if (q.isEmpty) {
      return _emptyState(context);
    }
    switch (_filter) {
      case SoftSearchFilter.postal:
        return _postalResults(context, q);
      case SoftSearchFilter.busNo:
        return _busResults(context, q);
      case SoftSearchFilter.stopID:
      case SoftSearchFilter.place:
        return _stopResults(context, q);
    }
  }

  // ─── Empty state: recents + example chips ─────────────────
  Widget _emptyState(BuildContext context) {
    final t = context.t;
    final recents = AppModel.shared.recents;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Recent searches — shown only when the list is non-empty.
          if (recents.isNotEmpty) ...[
            Text('Recent',
                style: t.mono(11, color: t.dim)
                    .copyWith(letterSpacing: 0.8)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in recents)
                  InputChip(
                    avatar: Icon(Icons.history, size: 15, color: t.dim),
                    label: Text(r,
                        style: t.sans(12, weight: FontWeight.w500, color: t.fg)),
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
          // Example chips — always shown in empty state so the field
          // has obvious tap-to-fill affordances. Mirrors
          // SoftSearchView.swift:92-114.
          Text('Examples',
              style: t.mono(11, color: t.dim)
                  .copyWith(letterSpacing: 0.8)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final ex in _examples)
                ActionChip(
                  label: Text(ex.value,
                      style: t.mono(12, weight: FontWeight.w600, color: t.fg)),
                  backgroundColor: t.surface,
                  side: BorderSide(color: t.dim.withValues(alpha: 0.2)),
                  onPressed: () {
                    setState(() {
                      _ctrl.text = ex.value;
                      _filter = ex.filter;
                    });
                    _onQueryChanged();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Stop / Place ─────────────────────────────────────────
  Widget _stopResults(BuildContext context, String q) {
    final stops = DataStore.shared.searchStops(q);
    if (stops.isEmpty) return _centerNote(context, 'No results');
    return ListView.separated(
      itemCount: stops.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _stopCard(context, stops[i]),
    );
  }

  Widget _stopCard(BuildContext context, LtaBusStop stop) {
    final t = context.t;
    return _card(
      context,
      onTap: () => _pickStop(stop.busStopCode),
      child: Row(children: [
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
              Text(stop.description,
                  style: t.sans(14, weight: FontWeight.w600, color: t.fg),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              Text('Stop ${stop.busStopCode} · ${stop.roadName}',
                  style: t.mono(11, color: t.dim),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        Icon(Icons.chevron_right, color: t.dim),
      ]),
    );
  }

  // ─── Bus # ────────────────────────────────────────────────
  Widget _busResults(BuildContext context, String q) {
    final t = context.t;
    final buses = DataStore.shared.searchServices(q);
    if (buses.isEmpty) return _centerNote(context, 'No services match "$q"');
    return ListView.separated(
      itemCount: buses.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final b = buses[i];
        final sub = [
          b.operator_ ?? '',
          if (b.category?.isNotEmpty == true)
            b.category!.substring(0, 1).toUpperCase() + b.category!.substring(1),
        ].where((s) => s.isNotEmpty).join(' · ');
        return _card(
          context,
          onTap: () => _pickBus(b.serviceNo),
          child: Row(children: [
            ServiceBadge(svc: b.serviceNo, size: ServiceBadgeSize.sm),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Service ${b.serviceNo}',
                      style: t.sans(14, weight: FontWeight.w600, color: t.fg),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (sub.isNotEmpty)
                    Text(sub,
                        style: t.mono(11, color: t.dim),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: t.dim),
          ]),
        );
      },
    );
  }

  // ─── Postal ───────────────────────────────────────────────
  Widget _postalResults(BuildContext context, String q) {
    final t = context.t;
    if (!RegExp(r'^\d{6}$').hasMatch(q)) {
      return _centerNote(context, 'Enter a 6-digit postal code');
    }
    // Reference data must be loaded before stops can be ranked by distance.
    final refState = DataStore.shared.referenceState;
    if (refState.state == LoadState.loading) {
      return _centerNote(context, 'Loading bus stops…', spinner: true);
    }
    if (refState.state == LoadState.error) {
      return _centerNote(
          context, refState.errorMessage ?? 'Couldn’t load bus stops.');
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
      return _centerNote(
        context,
        'No bus stops within ${_radiusLabel(radius)} of ${geo.label}.\n'
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
                style: t.mono(11, color: t.dim)),
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
            Text(title,
                style: t.sans(13, weight: FontWeight.w600, color: t.fg),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(sub,
                style: t.sans(11, color: t.dim),
                textAlign: TextAlign.center),
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
      child: Row(children: [
        SizedBox(
          width: 52,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${s.distanceM} m',
                  style: t.mono(14, weight: FontWeight.w600, color: t.fg)),
              Text('${s.walkMin} min', style: t.mono(10, color: t.dim)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.stopName,
                  style: t.sans(14, weight: FontWeight.w600, color: t.fg),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text('Stop ${s.stopCode}',
                  style: t.mono(11, color: t.dim),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        Icon(Icons.chevron_right, color: t.dim),
      ]),
    );
  }

  // ─── Shared ───────────────────────────────────────────────
  Widget _card(BuildContext context,
      {required VoidCallback onTap, required Widget child}) {
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
          Text(msg,
              style: t.sans(13, color: t.dim), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  void _pickStop(String code) {
    final q = _ctrl.text.trim();
    AppModel.shared.addRecent(q.isEmpty ? DataStore.shared.stopName(code) : q);
    widget.onOpenStop(code);
  }

  Future<void> _pickBus(String serviceNo) async {
    final origin = await DataStore.shared.originStop(serviceNo);
    if (!mounted || origin == null) return;
    AppModel.shared.addRecent(serviceNo);
    widget.onOpenStop(origin.busStopCode);
  }

  /// '500 m', '1 km', '1.5 km' — for the postal summary line.
  String _radiusLabel(int m) => m < 1000
      ? '$m m'
      : '${(m / 1000).toStringAsFixed(m % 1000 == 0 ? 0 : 1)} km';

  String _detected() {
    final q = _ctrl.text.trim();
    switch (_filter) {
      case SoftSearchFilter.postal:
        return 'Postal · $q';
      case SoftSearchFilter.stopID:
        return 'Stop · $q';
      case SoftSearchFilter.busNo:
        return 'Bus · $q';
      case SoftSearchFilter.place:
        return 'Place · $q';
    }
  }
}
