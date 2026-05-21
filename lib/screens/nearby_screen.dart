// Nearby — live nearest stops sorted by distance / arrival / service number.
//
// Rows are flat (no inline expand): tap a row to drill into DetailScreen.
// "ARRIVING" pill sits next to the stop name when any service is ≤ 60s out;
// service numbers show inline as tiny mono chips so you can see which buses
// stop here at a glance.

import 'package:flutter/material.dart';

import '../data/data_store.dart';
import '../data/models.dart';
import '../services/location_service.dart';
import '../state/app_model.dart';
import '../theme.dart';
import '../widgets/atoms.dart';
import 'detail_screen.dart';

enum _Sort { distance, arrival, service }

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  _Sort _sort = _Sort.distance;
  // Snapshot of ordered stops, frozen so the 1-second tick doesn't reshuffle
  // the list under the user's finger.
  List<NearbyStop> _ordered = const [];

  @override
  void initState() {
    super.initState();
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
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([
            LocationService.shared,
            DataStore.shared,
            AppModel.shared,
          ]),
          builder: (context, _) {
            _recomputeOrder();
            return _content(t);
          },
        ),
      ),
    );
  }

  Widget _content(LyneTheme t) {
    final loc = LocationService.shared;
    if (!loc.authorized) {
      return Column(
        children: [
          _header(t),
          Expanded(child: _permissionPrompt(t, loc)),
        ],
      );
    }
    if (DataStore.shared.referenceState.state == LoadState.error) {
      return Column(
        children: [
          _header(t),
          Expanded(
              child: _errorState(
                  t, DataStore.shared.referenceState.errorMessage ?? '')),
        ],
      );
    }
    if (_ordered.isEmpty) {
      return Column(
        children: [
          _header(t),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: t.dim),
                  const SizedBox(height: 12),
                  Text('Finding stops near you…',
                      style: t.sans(13, color: t.dim)),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Stack(
      children: [
        Column(
          children: [
            _header(t),
            _sortRow(t),
            Expanded(
              child: RefreshIndicator(
                color: t.accent,
                backgroundColor: t.surface,
                onRefresh: () async {
                  await LocationService.shared.requestAndStart();
                },
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 96),
                  itemCount: _ordered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, i) => _row(t, _ordered[i]),
                ),
              ),
            ),
          ],
        ),
        Positioned(
          right: 18,
          bottom: 18,
          child: _mapFab(t),
        ),
      ],
    );
  }

  // ─── Header ─────────────────────────────────────────────────────────

  Widget _header(LyneTheme t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('Nearby',
              style:
                  t.sans(28, weight: FontWeight.w600).copyWith(letterSpacing: -0.4)),
          const Spacer(),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.adjust, size: 14, color: t.dim),
              const SizedBox(width: 6),
              Text('500M',
                  style: t.mono(11, weight: FontWeight.w600, color: t.dim)
                      .copyWith(letterSpacing: 1)),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Sort pills ─────────────────────────────────────────────────────

  Widget _sortRow(LyneTheme t) {
    Widget chip(_Sort s, String label) {
      final active = _sort == s;
      return GestureDetector(
        onTap: () => setState(() => _sort = s),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: active ? t.fg : Colors.transparent,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: active ? t.fg : t.line),
          ),
          child: Text(label,
              style: t.sans(13, weight: FontWeight.w500).copyWith(
                color: active ? t.bg : t.dim,
              )),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: [
          MicroLabel('Sort'),
          const SizedBox(width: 10),
          chip(_Sort.distance, 'Distance'),
          const SizedBox(width: 8),
          chip(_Sort.arrival, 'Arrival'),
          const SizedBox(width: 8),
          chip(_Sort.service, 'Service'),
        ],
      ),
    );
  }

  // ─── Row ────────────────────────────────────────────────────────────

  Widget _row(LyneTheme t, NearbyStop stop) {
    final svcs = AppModel.shared.liveServices(stop.stopCode);
    final svcNos = svcs.isNotEmpty
        ? svcs.map((s) => s.no).toList()
        : DataStore.shared.servicesFor(stop.stopCode).map((s) => s.no).toList();
    final anyArriving = svcs.any((s) => s.etaSec <= 60);

    return Material(
      color: anyArriving
          ? t.accent.withValues(alpha: 0.05)
          : t.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DetailScreen(stopCode: stop.stopCode),
            ),
          );
        },
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: anyArriving
                  ? t.accent.withValues(alpha: 0.35)
                  : t.line,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
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
                        Text(
                          '${stop.distanceM}',
                          style: t.mono(17, weight: FontWeight.w600),
                        ),
                        const SizedBox(width: 1),
                        Text('m',
                            style: t.mono(10, color: t.dim)),
                      ],
                    ),
                    Text('${stop.walkMin} MIN',
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            stop.stopName,
                            style: t.sans(15, weight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (anyArriving) ...[
                          const SizedBox(width: 6),
                          Pill('ARRIVING', color: t.accent),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(stop.stopCode,
                            style: t.mono(10, color: t.faint)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _serviceChipsRow(t, svcNos),
                        ),
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

  Widget _serviceChipsRow(LyneTheme t, List<String> nos) {
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
          Text('+$overflow',
              style: t.mono(10, color: t.faint)),
      ],
    );
  }

  // ─── Map FAB ────────────────────────────────────────────────────────

  Widget _mapFab(LyneTheme t) {
    return Material(
      color: t.contrast,
      shape: const CircleBorder(),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      child: InkWell(
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Map view coming soon',
                  style: t.sans(13, color: t.fg)),
              backgroundColor: t.surfaceHi,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        },
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(Icons.map_outlined, color: t.contrastFg, size: 22),
        ),
      ),
    );
  }

  // ─── States ─────────────────────────────────────────────────────────

  Widget _permissionPrompt(LyneTheme t, LocationService loc) {
    final blocked = loc.auth == LocAuth.deniedForever;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.line),
              ),
              child: Icon(Icons.location_on_outlined,
                  size: 26, color: t.accent),
            ),
            const SizedBox(height: 16),
            Text('See stops near you',
                style: t.sans(17, weight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              'Leyne uses your location only to find bus stops within walking distance. It stays on your device.',
              textAlign: TextAlign.center,
              style: t.sans(13, color: t.dim),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: t.accent,
                foregroundColor: t.contrastFg,
              ),
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
                style: t.sans(11, color: t.dim),
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
                style: t.sans(12, color: t.dim),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: t.accent,
                foregroundColor: t.contrastFg,
              ),
              onPressed: () => DataStore.shared.bootstrap(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
