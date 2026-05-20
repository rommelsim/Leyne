// Search tab — live LTA Buses + Stops, detected-kind hint, persisted
// recent searches.
//
// Conservative variant of legacy SearchSheet.swift (variant A). The
// Ambitious variant was a full-screen modal sheet with oversized type;
// using a normal-sized tab fits the cross-platform NavigationBar shell
// better.

import 'package:flutter/material.dart';

import '../data/data_store.dart';
import '../data/lta_models.dart';
import '../data/search_logic.dart';
import '../state/app_model.dart';
import '../theme.dart';
import 'detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.onSwitchToNearby});

  /// Callback supplied by RootScaffold so the "Stops near me" shortcut
  /// can switch to the Nearby tab. Optional so the widget can be hosted
  /// outside the tab shell (e.g. in tests) without crashing.
  final VoidCallback? onSwitchToNearby;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _ctl = TextEditingController();
  final FocusNode _focus = FocusNode();
  String _q = '';

  @override
  void initState() {
    super.initState();
    _ctl.addListener(() {
      final v = _ctl.text;
      if (v != _q) setState(() => _q = v);
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ─── Picks ────────────────────────────────────────────────

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

  // ─── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: const Text('Search')),
      body: ListenableBuilder(
        listenable: Listenable.merge([DataStore.shared, AppModel.shared]),
        builder: (context, _) => Column(
          children: [
            _searchField(t),
            if (_q.isNotEmpty) _detectedHint(t),
            Expanded(
              child: _q.isEmpty ? _emptyState(t) : _results(t),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchField(LyneTheme t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: _ctl,
        focusNode: _focus,
        autocorrect: false,
        textInputAction: TextInputAction.search,
        style: t.sans(15),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Bus or stop (name / code)',
          hintStyle: TextStyle(color: t.dim),
          prefixIcon: Icon(Icons.search, color: t.dim, size: 18),
          suffixIcon: _q.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close, color: t.dim, size: 16),
                  onPressed: () {
                    _ctl.clear();
                    setState(() => _q = '');
                  },
                ),
          filled: true,
          fillColor: t.surface,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: t.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: t.accent),
          ),
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
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
      child: Row(
        children: [
          Text(
            'DETECTED · ${kind.label.isEmpty ? "ANY" : kind.label.toUpperCase()}'
            '${total > 0 ? " · $total match${total == 1 ? "" : "es"}" : ""}',
            style:
                t.mono(10).copyWith(color: t.dim, letterSpacing: 0.8),
          ),
        ],
      ),
    );
  }

  // ─── Empty state ──────────────────────────────────────────

  Widget _emptyState(LyneTheme t) {
    final recents = AppModel.shared.recents;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // "Stops near me" shortcut → Nearby tab.
        _nearbyShortcut(t),
        const SizedBox(height: 24),
        if (recents.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'RECENT',
              style: t.mono(10, weight: FontWeight.w600)
                  .copyWith(color: t.dim, letterSpacing: 1.2),
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in recents)
                ActionChip(
                  label: Text(r, style: t.sans(12)),
                  backgroundColor: t.surface,
                  side: BorderSide(color: t.line),
                  shape: const StadiumBorder(),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    _ctl.text = r;
                    _ctl.selection =
                        TextSelection.collapsed(offset: r.length);
                    setState(() => _q = r);
                    _focus.requestFocus();
                  },
                ),
            ],
          ),
        ] else
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 8),
            child: Text(
              'Search a bus number or a stop name / 5-digit code.',
              style: t.sans(12).copyWith(color: t.dim),
            ),
          ),
      ],
    );
  }

  Widget _nearbyShortcut(LyneTheme t) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        _focus.unfocus();
        widget.onSwitchToNearby?.call();
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.line),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: t.accent.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.location_on, color: t.accent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Stops near me',
                      style: t.sans(14, weight: FontWeight.w500)),
                  Text('Open the Nearby tab',
                      style: t.sans(11).copyWith(color: t.dim)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward, size: 14, color: t.dim),
          ],
        ),
      ),
    );
  }

  // ─── Results ──────────────────────────────────────────────

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
                  style: t.sans(13).copyWith(color: t.dim)),
              const SizedBox(height: 4),
              Text(
                'Try a bus number or a stop name / 5-digit code.',
                style: t.sans(11).copyWith(color: t.dim),
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
          _sectionHeader(t, 'BUSES', buses.length),
          for (final b in buses.take(20)) _busRow(t, b),
        ],
        if (stops.isNotEmpty) ...[
          _sectionHeader(t, 'STOPS', stops.length),
          for (final s in stops.take(30)) _stopRow(t, s),
        ],
      ],
    );
  }

  Widget _sectionHeader(LyneTheme t, String label, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Row(
        children: [
          Text(label,
              style: t.mono(10, weight: FontWeight.w600)
                  .copyWith(color: t.dim, letterSpacing: 1.2)),
          const Spacer(),
          Text('$count',
              style: t.mono(10).copyWith(color: t.dim)),
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
            Container(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 32),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: t.live,
                borderRadius: BorderRadius.circular(7),
              ),
              alignment: Alignment.center,
              child: Text(b.serviceNo,
                  style: t.mono(13, weight: FontWeight.w700)
                      .copyWith(color: Colors.white)),
            ),
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
                        style: t.mono(11).copyWith(color: t.dim),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1),
                ],
              ),
            ),
            Icon(Icons.arrow_forward, size: 14, color: t.dim),
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
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: t.accent.withValues(alpha: 0.09),
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
                      style: t.mono(11).copyWith(color: t.dim),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1),
                ],
              ),
            ),
            Icon(Icons.arrow_forward, size: 14, color: t.dim),
          ],
        ),
      ),
    );
  }
}
