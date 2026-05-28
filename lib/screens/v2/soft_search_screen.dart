// SoftSearchScreen — Leyne 2.0 Search (Material 3 Android variant).

import 'package:flutter/material.dart';

import '../../data/data_store.dart';
import '../../theme.dart';
import '../../widgets/v2/soft_components.dart';

enum SoftSearchFilter { postal, stopID, busNo, place }

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

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
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
                onSelect: (v) => setState(() => _filter = v),
              ),
              const SizedBox(height: 12),
              if (_ctrl.text.isNotEmpty)
                Text(_detected(),
                    style: t.mono(11, color: t.dim)),
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
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(28),
      child: TextField(
        controller: _ctrl,
        autofocus: true,
        onChanged: (_) => setState(() {}),
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
                  onPressed: () => setState(() => _ctrl.clear()),
                ),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _results(BuildContext context) {
    final t = context.t;
    final q = _ctrl.text.trim();
    if (q.isEmpty) {
      return Center(
          child: Text('Search stops, services, or postal codes',
              style: t.sans(13, color: t.dim)));
    }
    final stops = DataStore.shared.searchStops(q);
    if (stops.isEmpty) {
      return Center(
          child: Text('No results', style: t.sans(13, color: t.dim)));
    }
    return ListView.separated(
      itemCount: stops.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final stop = stops[i];
        return Material(
          color: t.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => widget.onOpenStop(stop.busStopCode),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stop.description,
                          style: t.sans(14,
                              weight: FontWeight.w600, color: t.fg),
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
            ),
          ),
        );
      },
    );
  }

  String _detected() {
    final q = _ctrl.text;
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
