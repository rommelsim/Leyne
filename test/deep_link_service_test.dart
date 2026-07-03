// Tests for normalizeDeepLinkSegments — the pure URI → route-segment step
// inside DeepLinkService._handle.
//
// Regression coverage for the lyne:// host-parsing bug: Dart's Uri parser
// treats the segment right after `scheme://` as the AUTHORITY (uri.host),
// not a path segment, for a custom scheme with no "//"-then-slash structure
// recognised as a host+path split. So `lyne://stop/83139` parses to
// host='stop', pathSegments=['83139'] — reading pathSegments[0] as the verb
// (as the original code did) never matches 'stop'/'service', and every
// widget/system deep-link tap silently no-ops.

import 'package:flutter_test/flutter_test.dart';
import 'package:lyne/services/deep_link_service.dart';

void main() {
  group('normalizeDeepLinkSegments — https://lyne.sg (unchanged behaviour)', () {
    test('stop only', () {
      final segs = normalizeDeepLinkSegments(Uri.parse('https://lyne.sg/stop/83139'));
      expect(segs, ['stop', '83139']);
    });

    test('stop + busNo', () {
      final segs =
          normalizeDeepLinkSegments(Uri.parse('https://lyne.sg/stop/83139/12'));
      expect(segs, ['stop', '83139', '12']);
    });

    test('service', () {
      final segs = normalizeDeepLinkSegments(Uri.parse('https://lyne.sg/service/12'));
      expect(segs, ['service', '12']);
    });

    test('unrecognised path falls through untouched', () {
      final segs = normalizeDeepLinkSegments(Uri.parse('https://lyne.sg/about'));
      expect(segs, ['about']);
    });
  });

  group('normalizeDeepLinkSegments — lyne:// (the bug fix)', () {
    test('stop only: host splices to the front', () {
      final segs = normalizeDeepLinkSegments(Uri.parse('lyne://stop/83139'));
      expect(segs, ['stop', '83139']);
    });

    test('stop + busNo', () {
      final segs = normalizeDeepLinkSegments(Uri.parse('lyne://stop/83139/12'));
      expect(segs, ['stop', '83139', '12']);
    });

    test('service', () {
      final segs = normalizeDeepLinkSegments(Uri.parse('lyne://service/12'));
      expect(segs, ['service', '12']);
    });

    test('bus (stop-with-busNo form)', () {
      final segs = normalizeDeepLinkSegments(Uri.parse('lyne://bus/83139/12'));
      expect(segs, ['bus', '83139', '12']);
    });

    test('bare root has no segments', () {
      final segs = normalizeDeepLinkSegments(Uri.parse('lyne://'));
      expect(segs, isEmpty);
    });

    test('unknown host is left as pathSegments (does not get spliced)', () {
      final segs = normalizeDeepLinkSegments(Uri.parse('lyne://unknown/foo'));
      expect(segs, ['foo']);
    });
  });
}
