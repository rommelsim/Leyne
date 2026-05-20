// Pure query-kind detection (no data). Buses + Stops are resolved live by
// DataStore.searchServices / DataStore.searchStops.
//
// Direct port of legacy/ios-native/Lyne/SearchLogic.swift — same regexes,
// same precedence.

import 'models.dart';

DetectedKind detectQueryKind(String raw) {
  final q = raw.trim();
  if (q.isEmpty) return const DetectedKind('empty', '');

  if (RegExp(r'^\d{6}$').hasMatch(q)) {
    return const DetectedKind('postal', 'Postal code');
  }
  if (RegExp(r'^\d{5}$').hasMatch(q)) {
    return const DetectedKind('stopcode', 'Stop code');
  }
  // Up to 2 leading letters covers real SG services: 88, 410W, NR1, CT8.
  if (RegExp(r'^[A-Za-z]{0,2}\d{1,3}[A-Za-z]?$').hasMatch(q)) {
    return const DetectedKind('bus', 'Bus service');
  }
  if (RegExp(r'^blk\s*\d', caseSensitive: false).hasMatch(q)) {
    return const DetectedKind('block', 'Block + street');
  }
  return const DetectedKind('text', 'Name or place');
}
