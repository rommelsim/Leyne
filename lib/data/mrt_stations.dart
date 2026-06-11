// MRT/LRT station lookup — turns a bus-stop description that sits at a rail
// station ("Clementi Stn", "Farrer Rd Stn Exit A", "Bt Batok Stn") into the
// station's display name + its line code(s) with official line colours, so the
// route timeline can show a colour-coded pill ("[EW23] Clementi") instead of a
// generic "MRT" tag.
//
// There is no bus-stop → station dataset from LTA, so we match on the stop
// DESCRIPTION: SG descriptions tag rail stops with "Stn" and use the station's
// name (often abbreviated — "Rd"→Road, "Bt"→Bukit, "Upp"→Upper). [resolveMrtStation]
// strips the directional prefix + the "Stn" token, expands those abbreviations,
// then looks the name up. Conservative: returns null unless the name resolves to
// a known station, so we never invent a code. Stations data current as of 2026
// (NSL, EWL/CG, NEL, CCL/CE, DTL, TEL operational network).
//
// Kept identical to the iOS side (ios-native/Leyne/V2/MrtStations.swift).

import 'package:flutter/material.dart';

/// Official LTA line brand colours, keyed by the 2-letter code prefix.
const Map<String, Color> _lineColors = {
  'NS': Color(0xFFD42E12), // North South — red
  'EW': Color(0xFF009645), // East West — green
  'CG': Color(0xFF009645), // Changi Airport branch — green
  'NE': Color(0xFF9900AA), // North East — purple
  'CC': Color(0xFFFA9E0D), // Circle — orange
  'CE': Color(0xFFFA9E0D), // Circle extension — orange
  'DT': Color(0xFF005EC4), // Downtown — blue
  'TE': Color(0xFF9D5B25), // Thomson–East Coast — brown
};

/// Fallback colour for any LRT/other code we don't brand individually.
const Color _lrtColor = Color(0xFF748477); // LRT — grey-green

/// Brand colour for a station code like "EW23" / "CC1".
Color lineColorFor(String code) {
  final prefix =
      (code.length >= 2 ? code.substring(0, 2) : code).toUpperCase();
  return _lineColors[prefix] ?? _lrtColor;
}

/// A single station code + its line colour, e.g. EW23 (green).
class MrtCode {
  const MrtCode(this.code, this.color);
  final String code;
  final Color color;
}

/// A resolved rail station: display name + one or more line codes (>1 for
/// interchanges, e.g. Jurong East → EW24, NS1).
class MrtStation {
  const MrtStation(this.name, this.codes);
  final String name;
  final List<MrtCode> codes;
}

/// Station display name → all of its line codes. Interchanges list every code.
const Map<String, List<String>> _stationCodes = {
  // North South Line
  'Jurong East': ['EW24', 'NS1'],
  'Bukit Batok': ['NS2'],
  'Bukit Gombak': ['NS3'],
  'Choa Chu Kang': ['NS4'],
  'Yew Tee': ['NS5'],
  'Kranji': ['NS7'],
  'Marsiling': ['NS8'],
  'Woodlands': ['NS9', 'TE2'],
  'Admiralty': ['NS10'],
  'Sembawang': ['NS11'],
  'Canberra': ['NS12'],
  'Yishun': ['NS13'],
  'Khatib': ['NS14'],
  'Yio Chu Kang': ['NS15'],
  'Ang Mo Kio': ['NS16'],
  'Bishan': ['NS17', 'CC15'],
  'Braddell': ['NS18'],
  'Toa Payoh': ['NS19'],
  'Novena': ['NS20'],
  'Newton': ['NS21', 'DT11'],
  'Orchard': ['NS22', 'TE14'],
  'Somerset': ['NS23'],
  'Dhoby Ghaut': ['NS24', 'NE6', 'CC1'],
  'City Hall': ['NS25', 'EW13'],
  'Raffles Place': ['NS26', 'EW14'],
  'Marina Bay': ['NS27', 'CE2', 'TE20'],
  'Marina South Pier': ['NS28'],
  // East West Line + Changi branch
  'Pasir Ris': ['EW1'],
  'Tampines': ['EW2', 'DT32'],
  'Simei': ['EW3'],
  'Tanah Merah': ['EW4'],
  'Bedok': ['EW5'],
  'Kembangan': ['EW6'],
  'Eunos': ['EW7'],
  'Paya Lebar': ['EW8', 'CC9'],
  'Aljunied': ['EW9'],
  'Kallang': ['EW10'],
  'Lavender': ['EW11'],
  'Bugis': ['EW12', 'DT14'],
  'Tanjong Pagar': ['EW15'],
  'Outram Park': ['EW16', 'NE3', 'TE17'],
  'Tiong Bahru': ['EW17'],
  'Redhill': ['EW18'],
  'Queenstown': ['EW19'],
  'Commonwealth': ['EW20'],
  'Buona Vista': ['EW21', 'CC22'],
  'Dover': ['EW22'],
  'Clementi': ['EW23'],
  'Chinese Garden': ['EW25'],
  'Lakeside': ['EW26'],
  'Boon Lay': ['EW27'],
  'Pioneer': ['EW28'],
  'Joo Koon': ['EW29'],
  'Gul Circle': ['EW30'],
  'Tuas Crescent': ['EW31'],
  'Tuas West Road': ['EW32'],
  'Tuas Link': ['EW33'],
  'Expo': ['CG1', 'DT35'],
  'Changi Airport': ['CG2'],
  // North East Line
  'HarbourFront': ['NE1', 'CC29'],
  'Chinatown': ['NE4', 'DT19'],
  'Clarke Quay': ['NE5'],
  'Little India': ['NE7', 'DT12'],
  'Farrer Park': ['NE8'],
  'Boon Keng': ['NE9'],
  'Potong Pasir': ['NE10'],
  'Woodleigh': ['NE11'],
  'Serangoon': ['NE12', 'CC13'],
  'Kovan': ['NE13'],
  'Hougang': ['NE14'],
  'Buangkok': ['NE15'],
  'Sengkang': ['NE16'],
  'Punggol': ['NE17'],
  'Punggol Coast': ['NE18'],
  // Circle Line + extension
  'Bras Basah': ['CC2'],
  'Esplanade': ['CC3'],
  'Promenade': ['CC4', 'DT15'],
  'Nicoll Highway': ['CC5'],
  'Stadium': ['CC6'],
  'Mountbatten': ['CC7'],
  'Dakota': ['CC8'],
  'MacPherson': ['CC10', 'DT26'],
  'Tai Seng': ['CC11'],
  'Bartley': ['CC12'],
  'Lorong Chuan': ['CC14'],
  'Marymount': ['CC16'],
  'Caldecott': ['CC17', 'TE9'],
  'Botanic Gardens': ['CC19', 'DT9'],
  'Farrer Road': ['CC20'],
  'Holland Village': ['CC21'],
  'one-north': ['CC23'],
  'Kent Ridge': ['CC24'],
  'Haw Par Villa': ['CC25'],
  'Pasir Panjang': ['CC26'],
  'Labrador Park': ['CC27'],
  'Telok Blangah': ['CC28'],
  'Bayfront': ['CE1', 'DT16'],
  // Downtown Line
  'Bukit Panjang': ['DT1'],
  'Cashew': ['DT2'],
  'Hillview': ['DT3'],
  'Hume': ['DT4'],
  'Beauty World': ['DT5'],
  'King Albert Park': ['DT6'],
  'Sixth Avenue': ['DT7'],
  'Tan Kah Kee': ['DT8'],
  'Stevens': ['DT10', 'TE11'],
  'Rochor': ['DT13'],
  'Downtown': ['DT17'],
  'Telok Ayer': ['DT18'],
  'Fort Canning': ['DT20'],
  'Bencoolen': ['DT21'],
  'Jalan Besar': ['DT22'],
  'Bendemeer': ['DT23'],
  'Geylang Bahru': ['DT24'],
  'Mattar': ['DT25'],
  'Ubi': ['DT27'],
  'Kaki Bukit': ['DT28'],
  'Bedok North': ['DT29'],
  'Bedok Reservoir': ['DT30'],
  'Tampines West': ['DT31'],
  'Tampines East': ['DT33'],
  'Upper Changi': ['DT34'],
  // Thomson–East Coast Line
  'Woodlands North': ['TE1'],
  'Woodlands South': ['TE3'],
  'Springleaf': ['TE4'],
  'Lentor': ['TE5'],
  'Mayflower': ['TE6'],
  'Bright Hill': ['TE7'],
  'Upper Thomson': ['TE8'],
  'Napier': ['TE12'],
  'Orchard Boulevard': ['TE13'],
  'Great World': ['TE15'],
  'Havelock': ['TE16'],
  'Maxwell': ['TE18'],
  'Shenton Way': ['TE19'],
  'Gardens by the Bay': ['TE22'],
  'Tanjong Rhu': ['TE23'],
  'Katong Park': ['TE24'],
  'Tanjong Katong': ['TE25'],
  'Marine Parade': ['TE26'],
  'Marine Terrace': ['TE27'],
  'Siglap': ['TE28'],
  'Bayshore': ['TE29'],
};

/// Common LTA bus-stop abbreviations → full words (token-wise), so a stop
/// description normalises to the dataset's station names.
const Map<String, String> _abbrev = {
  'rd': 'road',
  'bt': 'bukit',
  'upp': 'upper',
  'pk': 'park',
  'gdns': 'gardens',
  'ctrl': 'central',
  'ctr': 'central',
};

/// Canonical form of a name: lowercased, abbreviations expanded, spaces
/// collapsed. Used to build the lookup index AND to normalise queries so both
/// sides meet ("Farrer Road" and "Farrer Rd Stn" both → "farrer road").
String _canon(String s) {
  final tokens = s
      .toLowerCase()
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => _abbrev[w] ?? w);
  return tokens.join(' ').replaceAll('cck', 'choa chu kang');
}

/// Lazily-built index: canonical station name → display name.
final Map<String, String> _index = {
  for (final name in _stationCodes.keys) _canon(name): name,
};

final RegExp _stationToken = RegExp(r'\b(stn|station|mrt|lrt)\b');
final RegExp _leadingPrefix =
    RegExp(r'^(opp|opposite|bef|before|aft|after)\s+');

/// Resolve a bus-stop description to its rail station, or null when it isn't a
/// (recognised) station stop. e.g. "Farrer Rd Stn Exit A" → Farrer Road [CC20].
MrtStation? resolveMrtStation(String stopName) {
  var s = stopName.toLowerCase().trim();
  // Must read like a station reference, or it isn't one.
  if (!_stationToken.hasMatch(s)) return null;
  // Drop a leading directional prefix ("Opp Clementi Stn" → "clementi stn").
  s = s.replaceFirst(_leadingPrefix, '');
  // Keep only the part before the station token (drops "Stn", "Exit A", …).
  final m = _stationToken.firstMatch(s);
  if (m != null) s = s.substring(0, m.start);
  final display = _index[_canon(s)];
  if (display == null) return null;
  final codes = _stationCodes[display]!
      .map((c) => MrtCode(c, lineColorFor(c)))
      .toList(growable: false);
  return MrtStation(display, codes);
}
