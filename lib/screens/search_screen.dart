// Search — live search across LTA stops + services. Empty state shows
// recents + pinned stops so the screen is never blank.

import 'package:flutter/material.dart';

import '../data/data_store.dart';
import '../data/lta_models.dart';
import '../data/search_logic.dart';
import '../state/app_model.dart';
import '../theme.dart';
import '../widgets/atoms.dart';
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
                  child: _q.isEmpty ? _emptyState(t) : _results(t),
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
              'Search a bus number or stop (name / 5-digit code).',
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
}
