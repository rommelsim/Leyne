// Universal Links / App Links handler.
//
// Routes incoming https://lyne.sg/* URIs to in-app destinations:
//
//   /stop/{code}            → DetailScreen(stopCode)
//   /stop/{code}/{busNo}    → DetailScreen(stopCode, initialSelectedNo)
//   /service/{busNo}        → resolve origin stop, then DetailScreen
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
import '../screens/detail_screen.dart';

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
    // Accept both https://lyne.sg/... and any other host (devs running
    // local custom schemes). We only care about the path.
    final segments = uri.pathSegments;
    if (segments.isEmpty) return;

    switch (segments[0]) {
      case 'stop':
        if (segments.length >= 2) {
          final stopCode = segments[1];
          final busNo = segments.length >= 3 ? segments[2] : null;
          _push(navigatorKey,
              DetailScreen(stopCode: stopCode, initialSelectedNo: busNo));
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
    _push(navigatorKey,
        DetailScreen(stopCode: origin.busStopCode, initialSelectedNo: busNo));
  }

  void _push(GlobalKey<NavigatorState> navigatorKey, Widget screen) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.push(MaterialPageRoute(builder: (_) => screen));
  }
}
