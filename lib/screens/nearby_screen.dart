// Nearby — live nearest stops (device GPS + LTA BusStops dataset),
// sortable by Distance / Arrival / Service, expandable to show live
// arrivals, Pin-to-Home from each row.

import 'package:flutter/material.dart';

import '../data/data_store.dart';
import '../data/models.dart';
import '../services/location_service.dart';
import '../state/app_model.dart';
import '../theme.dart';
import '../widgets/service_row.dart';
import 'detail_screen.dart';

enum _Sort { distance, arrival, service }

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  _Sort _sort = _Sort.distance;
  String? _expandedId;
  // Snapshot of ordered stops, frozen so the 1-second tick doesn't
  // reshuffle the list under the user's finger (matches legacy iOS).
  List<NearbyStop> _ordered = const [];

  @override
  void initState() {
    super.initState();
    // Only start the position stream if permission is already granted
    // (common case after the first prompt). When not yet granted, build()
    // shows the in-app permission prompt and the user explicitly taps
    // "Enable location" — that path goes through requestAndStart() which
    // triggers the OS dialog. This matches legacy iOS LocationManager.
    LocationService.shared.startIfAuthorized();
    DataStore.shared.prefetchNearbyArrivals();
    _recomputeOrder();
  }

  void _recomputeOrder() {
    final list = [...DataStore.shared.nearby];
    switch (_sort) {
      case _Sort.distance:
        list.sort((a, b) => a.distanceM.compareTo(b.distanceM));
        break;
      case _Sort.arrival:
        int eta(NearbyStop s) {
          final svcs = AppModel.shared.liveServices(s.stopCode);
          if (svcs.isEmpty) return 1 << 30;
          return svcs.map((x) => x.etaSec).reduce((a, b) => a < b ? a : b);
        }

        list.sort((a, b) => eta(a).compareTo(eta(b)));
        break;
      case _Sort.service:
        int firstNum(NearbyStop s) {
          final svcs = DataStore.shared.servicesFor(s.stopCode);
          if (svcs.isEmpty) return 9999;
          final nums = svcs
              .map((x) =>
                  int.tryParse(x.no.replaceAll(RegExp(r'[^0-9]'), '')) ?? 9999)
              .toList();
          return nums.reduce((a, b) => a < b ? a : b);
        }

        list.sort((a, b) => firstNum(a).compareTo(firstNum(b)));
        break;
    }
    _ordered = list;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: const Text('Nearby')),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          LocationService.shared,
          DataStore.shared,
          AppModel.shared,
        ]),
        builder: (context, _) {
          // Resort when the nearby list itself or arrivals changed; never
          // on the 1s tick.
          _recomputeOrder();
          return _content(t);
        },
      ),
    );
  }

  Widget _content(LyneTheme t) {
    final loc = LocationService.shared;
    if (!loc.authorized) return _permissionPrompt(t, loc);
    if (DataStore.shared.referenceState.state == LoadState.error) {
      return _errorState(t, DataStore.shared.referenceState.errorMessage ?? '');
    }
    if (_ordered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: t.dim),
            const SizedBox(height: 12),
            Text('Finding stops near you…',
                style: t.sans(13).copyWith(color: t.dim)),
          ],
        ),
      );
    }
    return Column(
      children: [
        _sortRow(t),
        Expanded(
          child: RefreshIndicator(
            color: t.accent,
            onRefresh: () async {
              await LocationService.shared.requestAndStart();
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: _ordered.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _row(t, _ordered[i]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(LyneTheme t, NearbyStop stop) {
    final svcs = AppModel.shared.liveServices(stop.stopCode);
    final anyArriving = svcs.any((s) => s.etaSec <= 60);
    final state = DataStore.shared.arrivals[stop.stopCode];
    final open = _expandedId == stop.id;
    final pinned = AppModel.shared.isPinned(stop.stopCode);

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: anyArriving ? t.live : t.line),
        boxShadow: anyArriving
            ? [
                BoxShadow(
                  color: t.live.withValues(alpha: 0.08),
                  blurRadius: 6,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              final next = open ? null : stop.id;
              setState(() => _expandedId = next);
              if (next != null) {
                DataStore.shared.ensureArrivals(stop.stopCode);
              }
            },
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(16),
              bottom: open ? Radius.zero : const Radius.circular(16),
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Distance / walk minutes column
                  SizedBox(
                    width: 56,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(fmtDistance(stop.distanceM),
                            style: t.mono(14, weight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text('${stop.walkMin} MIN',
                            style: t.mono(9).copyWith(color: t.dim)),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 32, color: t.line),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(stop.stopName,
                            style: t.sans(15, weight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text('STOP ${stop.stopCode}',
                                style: t.mono(10).copyWith(color: t.dim)),
                            if (svcs.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text('·',
                                  style: t.mono(10).copyWith(
                                      color: t.dim.withValues(alpha: 0.5))),
                              const SizedBox(width: 8),
                              Text('${svcs.length} services',
                                  style: t.mono(10).copyWith(color: t.dim)),
                            ],
                            if (anyArriving) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: t.liveBg,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text('ARRIVING',
                                    style: t.mono(8, weight: FontWeight.w700)
                                        .copyWith(
                                            color: t.live,
                                            letterSpacing: 0.5)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more, color: t.dim),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: open
                ? Column(
                    children: [
                      Divider(height: 1, color: t.line),
                      _expanded(t, svcs, state, stop),
                      Divider(height: 1, color: t.line),
                      _actions(t, stop, pinned),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _expanded(LyneTheme t, List<Service> svcs, ArrivalState? state,
      NearbyStop stop) {
    if (svcs.isNotEmpty) {
      return Column(
        children: [
          for (var i = 0; i < svcs.length; i++) ...[
            if (i > 0) Divider(height: 1, color: t.line),
            ServiceRow(
              service: svcs[i],
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DetailScreen(
                    stopCode: stop.stopCode,
                    initialSelectedNo: svcs[i].no,
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    }
    final kind = state?.kind;
    if (kind == ArrivalStateKind.loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
                width: 14,
                height: 14,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: t.dim)),
            const SizedBox(width: 8),
            Text('Loading arrivals…',
                style: t.sans(12).copyWith(color: t.dim)),
          ],
        ),
      );
    }
    if (kind == ArrivalStateKind.error) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(state?.errorMessage ?? 'Couldn’t reach LTA',
            style: t.sans(11).copyWith(color: t.crit)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Text('No buses running here right now',
          style: t.sans(12).copyWith(color: t.dim)),
    );
  }

  Widget _actions(LyneTheme t, NearbyStop stop, bool pinned) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: pinned ? Colors.white : t.fg,
                backgroundColor: pinned ? t.accent : Colors.transparent,
                side: BorderSide(color: pinned ? t.accent : t.line),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: Icon(
                  pinned ? Icons.bookmark : Icons.bookmark_outline,
                  size: 16),
              label: Text(pinned ? 'Pinned to Home' : 'Pin to Home'),
              onPressed: () => AppModel.shared.togglePin(stop.stopCode),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: t.fg,
              side: BorderSide(color: t.line),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.north_east, size: 14),
            label: const Text('Open'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DetailScreen(stopCode: stop.stopCode),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _sortRow(LyneTheme t) {
    Widget chip(_Sort s, String label) {
      final active = _sort == s;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => setState(() => _sort = s),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: active ? t.fg : Colors.transparent,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: active ? t.fg : t.line),
            ),
            child: Text(label,
                style: t.sans(11, weight: FontWeight.w500).copyWith(
                  color: active ? t.bg : t.dim,
                )),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Text('SORT',
              style: t.mono(10, weight: FontWeight.w600)
                  .copyWith(color: t.dim, letterSpacing: 1)),
          const SizedBox(width: 10),
          chip(_Sort.distance, 'Distance'),
          chip(_Sort.arrival, 'Arrival'),
          chip(_Sort.service, 'Service'),
        ],
      ),
    );
  }

  Widget _permissionPrompt(LyneTheme t, LocationService loc) {
    final blocked = loc.auth == LocAuth.deniedForever;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_on_outlined, size: 56, color: t.accent),
            const SizedBox(height: 16),
            Text('See stops near you',
                style: t.sans(17, weight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              'Leyne uses your location only to find bus stops within walking distance. It stays on your device.',
              textAlign: TextAlign.center,
              style: t.sans(13).copyWith(color: t.dim),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: t.accent),
              onPressed: () {
                if (blocked) {
                  loc.openAppSettings();
                } else {
                  loc.requestAndStart();
                }
              },
              child: Text(blocked ? 'Open Settings' : 'Enable location'),
            ),
            if (blocked) ...[
              const SizedBox(height: 8),
              Text(
                'Location is off. Enable it in system settings.',
                textAlign: TextAlign.center,
                style: t.sans(11).copyWith(color: t.dim),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _errorState(LyneTheme t, String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, size: 40, color: t.crit),
            const SizedBox(height: 12),
            Text('Couldn’t load stops',
                style: t.sans(15, weight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(msg,
                style: t.sans(12).copyWith(color: t.dim),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: t.accent),
              onPressed: () => DataStore.shared.bootstrap(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
