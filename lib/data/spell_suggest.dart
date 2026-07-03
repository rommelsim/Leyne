// SpellSuggest — "Did you mean …?" over the transit vocabulary.
//
// Dart port of the iOS WSSpell helper (ios-native WhereSia/WSData.swift):
// vocabulary is every word (≥ 4 letters) from bus-stop descriptions, road
// names and MRT station names; a no-results query is corrected token by
// token via Levenshtein distance with a conservative cap (≤ 2 edits for
// words of 6+ characters, ≤ 1 otherwise) so "Clemeti" suggests "Clementi"
// but garbage never produces a false suggestion.

class SpellSuggest {
  SpellSuggest._();

  static Set<String>? _vocab;

  /// Builds (once) and returns the word vocabulary from [phrases].
  /// An empty build (reference data not loaded yet) is NOT cached, so a
  /// later call retries once stops have arrived.
  static Set<String> _ensureVocab(Iterable<String> Function() phrases) {
    final cached = _vocab;
    if (cached != null) return cached;
    final out = <String>{};
    for (final p in phrases()) {
      for (final w in p.toLowerCase().split(RegExp(r'[^a-z]+'))) {
        if (w.length >= 4) out.add(w);
      }
    }
    if (out.isNotEmpty) _vocab = out;
    return out;
  }

  /// A corrected version of [query] ("Clemeti rd" → "Clementi Rd"), or null
  /// when nothing needed correcting or no candidate was close enough.
  /// [phrases] supplies the corpus lazily (stop names, road names, station
  /// names) — only evaluated on the first call.
  static String? suggest(String query, Iterable<String> Function() phrases) {
    final vocab = _ensureVocab(phrases);
    if (vocab.isEmpty) return null;

    final tokens = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return null;

    var corrected = false;
    final out = <String>[];
    for (final t in tokens) {
      final clean = t.replaceAll(RegExp(r'[^a-z0-9]'), '');
      // Leave short words, numbers (bus/stop codes) and known words alone.
      if (clean.length < 4 ||
          clean.contains(RegExp(r'\d')) ||
          vocab.contains(clean)) {
        out.add(t);
        continue;
      }
      final maxDist = clean.length >= 6 ? 2 : 1;
      String? best;
      var bestD = maxDist + 1;
      for (final w in vocab) {
        if ((w.length - clean.length).abs() > maxDist) continue;
        final d = _editDistance(clean, w, maxDist);
        if (d < bestD) {
          bestD = d;
          best = w;
        }
      }
      if (best != null && bestD <= maxDist) {
        out.add(best);
        corrected = true;
      } else {
        out.add(t);
      }
    }
    if (!corrected) return null;
    return out
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  /// Levenshtein distance with an early-out: returns cap+1 as soon as the
  /// running row minimum exceeds [cap] (we only care about "close enough").
  static int _editDistance(String a, String b, int cap) {
    final m = a.length, n = b.length;
    var prev = List<int>.generate(n + 1, (j) => j);
    for (var i = 1; i <= m; i++) {
      final cur = List<int>.filled(n + 1, 0)..[0] = i;
      var rowMin = i;
      for (var j = 1; j <= n; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var v = prev[j] + 1;
        final ins = cur[j - 1] + 1;
        if (ins < v) v = ins;
        final sub = prev[j - 1] + cost;
        if (sub < v) v = sub;
        cur[j] = v;
        if (v < rowMin) rowMin = v;
      }
      if (rowMin > cap) return cap + 1;
      prev = cur;
    }
    return prev[n];
  }
}
