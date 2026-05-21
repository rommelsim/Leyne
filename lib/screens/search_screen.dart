// Search — live search across LTA stops + services. Empty state shows
// recents + pinned stops so the screen is never blank.

import 'package:flutter/material.dart';

import '../data/data_store.dart';
import '../data/lta_models.dart';
import '../data/models.dart';
import '../data/search_logic.dart';
import '../services/geocode_service.dart';
import '../state/app_model.dart';
import '../theme.dart';
import '../widgets/atoms.dart';
import '../widgets/stops_map.dart';
import 'detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.onSwitchToNearby});

  /// Kept for source-compatibility with RootScaffold even though the empty
  /// state no longer surfaces "Stops near me" — the Nearby tab is one tap
  /// away in the bottom bar.
  final VoidCallback? onSwitchToNearby;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _ctl = TextEditingController();
  final FocusNode _focus = FocusNode();
  String _q = '';

  // ─── Postal-code geocoding state ──────────────────────────────
  // `_geoFor` is the postal code `_geo` was resolved for, so each code is
  // geocoded at most once. `_geo` is null while loading or after a failure.
  String? _geoFor;
  GeoPlace? _geo;
  bool _geoLoading = false;
  bool _geoFailed = false;

  @override
  void initState() {
    super.initState();
    // Routes power the per-stop service chips in postal-code results.
    DataStore.shared.ensureRoutes();
    _ctl.addListener(() {
      final v = _ctl.text;
      if (v != _q) {
        setState(() => _q = v);
        _maybeGeocode(v);
      }
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ─── Picks ────────────────────────────────────────────────────

  void _pickStop(String code) {
    final m = AppModel.shared;
    final ds = DataStore.shared;
    m.addRecent(_q.isEmpty ? ds.stopName(code) : _q);
    _openDetail(code);
  }

  Future<void> _pickBus(String serviceNo) async {
    final m = AppModel.shared;
    final origin = await DataStore.shared.originStop(serviceNo);
    if (!mounted || origin == null) return;
    m.addRecent(serviceNo);
    _openDetail(origin.busStopCode);
  }

  void _openDetail(String stopCode) {
    _focus.unfocus();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailScreen(stopCode: stopCode),
      ),
    );
  }

  // ─── Postal-code geocoding ────────────────────────────────────

  /// Geocode `raw` when it's a 6-digit postal code not yet resolved. Pass
  /// `force` to retry a code that previously failed.
  void _maybeGeocode(String raw, {bool force = false}) {
    final q = raw.trim();
    if (detectQueryKind(q).kind != 'postal') return;
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
      body: SafeArea(
        bottom: false,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _focus.unfocus,
          child: ListenableBuilder(
            listenable: Listenable.merge([DataStore.shared, AppModel.shared]),
            builder: (context, _) => Column(
              children: [
                _header(t),
                _searchField(t),
                if (_q.isNotEmpty) _detectedHint(t),
                Expanded(
                  child: _q.isEmpty
                      ? _emptyState(t)
                      : detectQueryKind(_q).kind == 'postal'
                          ? _postalResults(t)
                          : _results(t),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(LyneTheme t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Text('Search',
          style: t.sans(28, weight: FontWeight.w600).copyWith(letterSpacing: -0.4)),
    );
  }

  Widget _searchField(LyneTheme t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: Container(
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: t.line),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Row(
          children: [
            Icon(Icons.search, color: t.dim, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _ctl,
                focusNode: _focus,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                style: t.mono(15),
                cursorColor: t.accent,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Bus, stop or place',
                  hintStyle: t.mono(15, color: t.faint),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            if (_q.isNotEmpty) ...[
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close, color: t.dim, size: 16),
                onPressed: () {
                  _ctl.clear();
                  setState(() => _q = '');
                },
              ),
              Container(width: 1, height: 18, color: t.line),
            ],
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.qr_code_scanner, color: t.fg, size: 18),
              onPressed: () {
                ScaffoldMessenger.of(context)
                  ..removeCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text('QR scan coming soon',
                          style: t.sans(13, color: t.fg)),
                      backgroundColor: t.surfaceHi,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(milliseconds: 1400),
                    ),
                  );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _detectedHint(LyneTheme t) {
    final kind = detectQueryKind(_q);
    final stops = DataStore.shared.searchStops(_q);
    final buses = DataStore.shared.searchServices(_q);
    final total = stops.length + buses.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
      child: Row(
        children: [
          Text(
            'DETECTED · ${kind.label.isEmpty ? "ANY" : kind.label.toUpperCase()}'
            '${total > 0 ? " · $total match${total == 1 ? "" : "es"}" : ""}',
            style: t.mono(10, color: t.dim).copyWith(letterSpacing: 0.8),
          ),
        ],
      ),
    );
  }

  // ─── Empty state ──────────────────────────────────────────────

  Widget _emptyState(LyneTheme t) {
    final recents = AppModel.shared.recents.take(6).toList();
    final pins = AppModel.shared.pins;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
      children: [
        if (recents.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
            child: MicroLabel('Recent'),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in recents) _recentPill(t, r),
            ],
          ),
          const SizedBox(height: 24),
        ],
        if (pins.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
            child: MicroLabel('Pinned'),
          ),
          for (final p in pins) ...[
            _pinnedRow(t, p.code),
            const SizedBox(height: 8),
          ],
        ],
        if (recents.isEmpty && pins.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 16),
            child: Text(
              'Search a bus number, a stop (name / 5-digit code), or a '
              '6-digit postal code to find stops near an address.',
              style: t.sans(13, color: t.dim),
            ),
          ),
      ],
    );
  }

  Widget _recentPill(LyneTheme t, String label) {
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: () {
        _ctl.text = label;
        _ctl.selection = TextSelection.collapsed(offset: label.length);
        setState(() => _q = label);
        _focus.requestFocus();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: t.line),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 12, color: t.faint),
            const SizedBox(width: 6),
            Text(label, style: t.mono(13, color: t.fg)),
          ],
        ),
      ),
    );
  }

  Widget _pinnedRow(LyneTheme t, String stopCode) {
    final name = DataStore.shared.stopName(stopCode);
    final svcs = DataStore.shared.servicesFor(stopCode);
    final firstNo = svcs.isNotEmpty ? svcs.first.no : null;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openDetail(stopCode),
      child: Ink(
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: t.line),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            if (firstNo != null)
              BusChip(no: firstNo, size: ChipSize.sm)
            else
              Container(
                width: 42, height: 28,
                decoration: BoxDecoration(
                  color: t.lineHi,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(Icons.location_on, size: 14, color: t.dim),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name,
                      style: t.sans(14, weight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 1),
                  Text(
                    'STOP $stopCode${svcs.isNotEmpty ? " · ${svcs.length} services" : ""}',
                    style: t.mono(10, color: t.dim)
                        .copyWith(letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
            Icon(Icons.star_rounded, color: t.accent, size: 18),
          ],
        ),
      ),
    );
  }

  // ─── Results ──────────────────────────────────────────────────

  Widget _results(LyneTheme t) {
    final ds = DataStore.shared;
    final buses = ds.searchServices(_q);
    final stops = ds.searchStops(_q);
    final total = buses.length + stops.length;

    if (total == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Nothing matches "$_q"',
                  style: t.sans(13, color: t.dim)),
              const SizedBox(height: 4),
              Text(
                'Try a bus number or a stop name / 5-digit code.',
                style: t.sans(11, color: t.faint),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
      children: [
        if (buses.isNotEmpty) ...[
          _sectionHeader(t, 'Buses', buses.length),
          for (final b in buses.take(20)) _busRow(t, b),
        ],
        if (stops.isNotEmpty) ...[
          _sectionHeader(t, 'Stops', stops.length),
          for (final s in stops.take(30)) _stopRow(t, s),
        ],
      ],
    );
  }

  Widget _sectionHeader(LyneTheme t, String label, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          MicroLabel(label),
          const Spacer(),
          Text('$count', style: t.mono(10, color: t.faint)),
        ],
      ),
    );
  }

  Widget _busRow(LyneTheme t, LtaBusService b) {
    final title = (b.loopDesc?.isNotEmpty == true)
        ? 'Loop · ${b.loopDesc}'
        : 'Service ${b.serviceNo}';
    final sub = [
      b.operator_ ?? '',
      if (b.category?.isNotEmpty == true)
        b.category!.substring(0, 1).toUpperCase() + b.category!.substring(1),
    ].where((s) => s.isNotEmpty).join(' · ');

    return InkWell(
      onTap: () => _pickBus(b.serviceNo),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            BusChip(no: b.serviceNo, size: ChipSize.sm),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: t.sans(14, weight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1),
                  if (sub.isNotEmpty)
                    Text(sub,
                        style: t.mono(11, color: t.dim)
                            .copyWith(letterSpacing: 0.5),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: t.faint),
          ],
        ),
      ),
    );
  }

  Widget _stopRow(LyneTheme t, LtaBusStop s) {
    return InkWell(
      onTap: () => _pickStop(s.busStopCode),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: t.accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.adjust, color: t.accent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s.description,
                      style: t.sans(14, weight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1),
                  Text('STOP ${s.busStopCode} · ${s.roadName}',
                      style: t.mono(11, color: t.dim)
                          .copyWith(letterSpacing: 0.5),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: t.faint),
          ],
        ),
      ),
    );
  }

  // ─── Postal-code results ──────────────────────────────────────

  /// '500 M', '1 KM', '1.5 KM' — upper-cased for the mono summary label.
  String _radiusLabel(int m) => m < 1000
      ? '$m M'
      : '${(m / 1000).toStringAsFixed(m % 1000 == 0 ? 0 : 1)} KM';

  Widget _postalResults(LyneTheme t) {
    // Reference data must be loaded before stops can be ranked by distance.
    final refState = DataStore.shared.referenceState;
    if (refState.state == LoadState.loading) {
      return _centeredNote(t, 'Loading bus stops…', spinner: true);
    }
    if (refState.state == LoadState.error) {
      return _centeredNote(
          t, refState.errorMessage ?? 'Couldn’t load bus stops.');
    }

    if (_geoLoading) {
      return _centeredNote(t, 'Finding postal code $_geoFor…', spinner: true);
    }
    final geo = _geo;
    if (_geoFailed || geo == null) return _postalNotFound(t);

    final radius = AppModel.shared.searchRadiusM;
    final stops = DataStore.shared.stopsWithin(geo.lat, geo.lon, radius);

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      children: [
        _postalSummary(t, geo, stops.length, radius),
        const SizedBox(height: 10),
        StopsMap(
          center: GeoPoint(geo.lat, geo.lon),
          stops: stops,
          radiusM: radius,
        ),
        const SizedBox(height: 14),
        if (stops.isEmpty)
          _postalEmpty(t, radius)
        else
          for (final s in stops) ...[
            _postalStopRow(t, s),
            const SizedBox(height: 6),
          ],
      ],
    );
  }

  Widget _postalSummary(LyneTheme t, GeoPlace geo, int count, int radius) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(geo.label,
              style: t.sans(16, weight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Text(
            'POSTAL ${geo.postalCode} · $count STOP${count == 1 ? "" : "S"} '
            'WITHIN ${_radiusLabel(radius)}',
            style: t.mono(10, color: t.dim).copyWith(letterSpacing: 0.6),
          ),
        ],
      ),
    );
  }

  Widget _postalStopRow(LyneTheme t, NearbyStop s) {
    final svcNos = DataStore.shared.servicesAtStop(s.stopCode);
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => _pickStop(s.stopCode),
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.line),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('${s.distanceM}',
                            style: t.mono(17, weight: FontWeight.w600)),
                        const SizedBox(width: 1),
                        Text('m', style: t.mono(10, color: t.dim)),
                      ],
                    ),
                    Text('${s.walkMin} MIN',
                        style: t.mono(9, color: t.faint)
                            .copyWith(letterSpacing: 0.5)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(width: 1, height: 36, color: t.line),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(s.stopName,
                        style: t.sans(15, weight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(s.stopCode, style: t.mono(10, color: t.faint)),
                        const SizedBox(width: 6),
                        Expanded(child: _serviceChips(t, svcNos)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _serviceChips(LyneTheme t, List<String> nos) {
    if (nos.isEmpty) return const SizedBox.shrink();
    final shown = nos.take(6).toList();
    final overflow = nos.length - shown.length;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final n in shown)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: t.lineHi,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(n,
                style: t.mono(10, weight: FontWeight.w600, color: t.fg)),
          ),
        if (overflow > 0)
          Text('+$overflow', style: t.mono(10, color: t.faint)),
      ],
    );
  }

  Widget _centeredNote(LyneTheme t, String msg, {bool spinner = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (spinner) ...[
              CircularProgressIndicator(color: t.dim, strokeWidth: 2),
              const SizedBox(height: 12),
            ],
            Text(msg,
                style: t.sans(13, color: t.dim),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _postalNotFound(LyneTheme t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wrong_location_outlined, size: 36, color: t.faint),
            const SizedBox(height: 12),
            Text('Couldn’t find postal code $_geoFor',
                style: t.sans(14, weight: FontWeight.w600),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              'Check the 6-digit code, or try again — the address lookup '
              'may be offline.',
              style: t.sans(12, color: t.dim),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: t.accent,
                foregroundColor: t.contrastFg,
              ),
              onPressed: () => _maybeGeocode(_q, force: true),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _postalEmpty(LyneTheme t, int radius) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: Column(
        children: [
          Icon(Icons.near_me_disabled, size: 32, color: t.faint),
          const SizedBox(height: 10),
          Text('No bus stops within ${_radiusLabel(radius).toLowerCase()}',
              style: t.sans(13, weight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Widen the search radius in Settings.',
              style: t.sans(12, color: t.faint),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
