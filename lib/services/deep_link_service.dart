// Universal Links / App Links handler.
//
// Routes incoming URIs to in-app destinations:
//
//   /stop/{code}            → SoftStopScreen(stopCode)
//   /stop/{code}/{busNo}    → SoftStopScreen + SoftBusScreen pushed on top
//   /service/{busNo}        → resolve origin stop, then the same pair
//   /bus/{code}/{busNo}     → same as /stop/{code}/{busNo} (Android widget
//                             taps use this form — see below)
//
// Two URI shapes reach _handle:
//   • https://lyne.sg/stop/83139       — Dart's Uri parser puts the verb at
//     pathSegments[0] ('stop'), so `uri.pathSegments` is switchable as-is.
//   • lyne://stop/83139                — for a custom scheme, Dart's Uri
//     parser treats the segment right after `://` as the AUTHORITY, so it
//     lands in `uri.host` ('stop'), NOT `uri.pathSegments` (which is only
//     ['83139']). Reading pathSegments[0] here would silently miss every
//     lyne:// tap — this is exactly what the Android home-screen widgets use
//     (WidgetDataRepository.deepLinkIntent). normalizeDeepLinkSegments()
//     below splices the host back to the front for the known lyne:// verbs
//     so both shapes funnel through one switch.
//
// Two entry points:
//   • getInitialLink — the URI the app was COLD-LAUNCHED with (deeplink
//     before the app was running).
//   • uriLinkStream — URIs delivered while the app is already running.
//
// Hosting requirements (out-of-repo):
//   • iOS: /.well-known/apple-app-site-association on the same domain,
//     served with Content-Type application/json (no .json extension on
//     the file itself). Plus the `Associated Domains` capability +
//     `applinks:lyne.sg` entitlement in the iOS app.
//   • Android: /.well-known/assetlinks.json on the same domain. Plus
//     android:autoVerify="true" on the intent-filter in
//     AndroidManifest.xml (already wired in Task #11's manifest edit).

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/data_store.dart';
import '../screens/v2/soft_stop_screen.dart';
import 'app_open_ad.dart';

/// Verbs recognised on the `lyne://` custom scheme, where the verb parses as
/// [Uri.host] rather than the first path segment (see file header).
const _kLyneSchemeVerbs = {'stop', 'service', 'bus'};

/// Pure, side-effect-free URI → route-segment normalization. Extracted so it
/// can be unit-tested without a Navigator (see test/deep_link_service_test.dart).
///
/// For `https://lyne.sg/stop/83139` (or any other host/scheme), returns
/// `uri.pathSegments` unchanged: ['stop', '83139'].
///
/// For `lyne://stop/83139`, Dart parses 'stop' as [Uri.host] and ['83139']
/// as [Uri.pathSegments]. When the host is one of [_kLyneSchemeVerbs], this
/// splices it back to the front so the result reads the same either way:
/// ['stop', '83139'].
@visibleForTesting
List<String> normalizeDeepLinkSegments(Uri uri) {
  if (uri.scheme == 'lyne' && _kLyneSchemeVerbs.contains(uri.host)) {
    return [uri.host, ...uri.pathSegments];
  }
  return uri.pathSegments;
}

class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  bool _started = false;

  /// Start listening for incoming links. Idempotent. Pass the
  /// navigatorKey from MaterialApp so we can push routes from outside
  /// the widget tree.
  Future<void> start(GlobalKey<NavigatorState> navigatorKey) async {
    if (_started) return;
    _started = true;

    // Cold-launch deep link.
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handle(initial, navigatorKey);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[deeplink] initial link error: $e');
      }
    }

    // Subsequent in-foreground deliveries.
    _sub = _appLinks.uriLinkStream.listen(
      (uri) => _handle(uri, navigatorKey),
      onError: (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[deeplink] stream error: $e');
        }
      },
    );
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _started = false;
  }

  void _handle(Uri uri, GlobalKey<NavigatorState> navigatorKey) {
    // Accept both https://lyne.sg/... and lyne://... (see normalizeDeepLink
    // Segments doc for why the latter needs host-splicing).
    final segments = normalizeDeepLinkSegments(uri);
    if (segments.isEmpty) return;

    // A deep link is bringing the user to a specific stop/bus — suppress the
    // App Open ad on this foreground so they land on content, not an ad.
    AppOpenAdManager.instance.suppressNext();

    switch (segments[0]) {
      case 'stop':
        if (segments.length >= 2) {
          final stopCode = segments[1];
          final busNo = segments.length >= 3 ? segments[2] : null;
          _pushStopRoute(navigatorKey, stopCode, busNo);
        }
        break;
      case 'bus':
        // lyne://bus/<stop>/<no> — Android widget tap format; same
        // destination as /stop/<stop>/<no>.
        if (segments.length >= 3) {
          final stopCode = segments[1];
          final busNo = segments[2];
          _pushStopRoute(navigatorKey, stopCode, busNo);
        }
        break;
      case 'service':
        if (segments.length >= 2) {
          final busNo = segments[1];
          // Need to resolve the origin stop from the bus routes dataset.
          _openServiceOrigin(navigatorKey, busNo);
        }
        break;
      default:
        if (kDebugMode) {
          // ignore: avoid_print
          print('[deeplink] unhandled URI: $uri');
        }
    }
  }

  Future<void> _openServiceOrigin(
      GlobalKey<NavigatorState> navigatorKey, String busNo) async {
    final origin = await DataStore.shared.originStop(busNo);
    if (origin == null) return;
    _pushStopRoute(navigatorKey, origin.busStopCode, busNo);
  }

  /// Push a SoftStopScreen for the given stop, with [busNo] — when supplied —
  /// already featured in the hero. ONE route, not a Stop + Track Bus stack:
  /// iOS retired the standalone tracking screen, and the Stop hero carries the
  /// route timeline for its featured service.
  void _pushStopRoute(GlobalKey<NavigatorState> navigatorKey, String stopCode,
      String? busNo) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.push(MaterialPageRoute(
      builder: (_) => SoftStopScreen(
        stopCode: stopCode,
        initialService: busNo,
        onBack: () => nav.pop(),
        onSeeAll: () {},
      ),
    ));
  }
}
