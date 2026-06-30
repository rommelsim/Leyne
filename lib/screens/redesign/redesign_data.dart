// Mock data for the SG Transit redesign — a faithful port of the constants in
// the design composition (__STOPS, __STATIONS and the MRT line list). The
// redesign is a self-contained design implementation, so it ships with the
// same sample content the prototype used rather than wiring the live LTA feed.

import 'package:flutter/widgets.dart';

/// Crowd / occupancy level, used for both bus loads and station crowding. Maps
/// to the bus (green) / amber / mrt (red) colour roles.
enum RdLoad { seats, standing, packed }

class RdArrival {
  const RdArrival({
    required this.route,
    required this.dest,
    required this.load,
    required this.min,
    this.then,
  });

  final String route;
  final String dest;
  final RdLoad load;
  final String min;
  final String? then;
}

class RdStop {
  const RdStop({
    required this.name,
    required this.code,
    required this.dist,
    required this.distShort,
    required this.badge,
    required this.arrivals,
  });

  final String name;
  final String code;
  final String dist;
  final String distShort;
  final String badge;
  final List<RdArrival> arrivals;
}

class RdStationDir {
  const RdStationDir({
    required this.to,
    required this.via,
    required this.plat,
    required this.min,
    required this.then,
  });

  final String to;
  final String via;
  final String plat; // single letter
  final String min;
  final String then;
}

class RdStation {
  const RdStation({
    required this.key,
    required this.name,
    required this.code,
    required this.lineColor,
    required this.lineFg,
    required this.lineName,
    required this.walk,
    required this.freq,
    required this.crowd,
    required this.crowdLoad,
    required this.firstTrain,
    required this.lastTrain,
    required this.exits,
    required this.facilities,
    required this.dirs,
  });

  final String key;
  final String name;
  final String code;
  final Color lineColor;
  final Color lineFg;
  final String lineName;
  final String walk;
  final String freq;
  final String crowd;
  final RdLoad crowdLoad;
  final String firstTrain;
  final String lastTrain;
  final String exits;
  final String facilities;
  final List<RdStationDir> dirs;
}

class RdMrtLine {
  const RdMrtLine({
    required this.code,
    required this.name,
    required this.badgeBg,
    required this.badgeFg,
    required this.statusText,
    required this.location,
    this.major = false,
    this.detail,
    this.status = RdLineStatus.normal,
  });

  final String code;
  final String name;
  final Color badgeBg;
  final Color badgeFg;
  final String statusText; // chip label for non-major lines
  final String location; // "Bishan · 12 min"
  final bool major;
  final String? detail; // body text for the major-delay card
  final RdLineStatus status;
}

enum RdLineStatus { normal, busy, major }

const _orange = Color(0xFFFA9E0D);
const _onOrange = Color(0xFF3A2500);

/// Bus stops, in priority order (index 0 is the user's current stop).
const List<RdStop> kRdStops = [
  RdStop(
    name: 'Opp Blk 123',
    code: '43091',
    dist: "You're at this stop · Farrer Road",
    distShort: 'You are here',
    badge: "YOU'RE HERE",
    arrivals: [
      RdArrival(route: '165', dest: 'HarbourFront Int', load: RdLoad.seats, min: '2', then: 'then 11'),
      RdArrival(route: '174', dest: 'Clementi Int', load: RdLoad.standing, min: '7', then: 'then 16'),
      RdArrival(route: '186', dest: 'Boon Lay Int', load: RdLoad.packed, min: '12'),
      RdArrival(route: '5', dest: 'Eunos Int', load: RdLoad.seats, min: '4', then: 'then 13'),
      RdArrival(route: '48', dest: 'Marina Centre', load: RdLoad.standing, min: '6', then: 'then 18'),
      RdArrival(route: '93', dest: 'Toa Payoh Int', load: RdLoad.seats, min: '9', then: 'then 21'),
      RdArrival(route: '961', dest: 'Sin Ming Ave', load: RdLoad.packed, min: '13'),
      RdArrival(route: '970', dest: 'Jurong East Int', load: RdLoad.standing, min: '16'),
    ],
  ),
  RdStop(
    name: 'Blk 240',
    code: '43099',
    dist: '1 min walk · 140 m',
    distShort: '140 m',
    badge: '1 MIN WALK',
    arrivals: [
      RdArrival(route: '51', dest: 'Bishan Int', load: RdLoad.seats, min: '5', then: 'then 14'),
      RdArrival(route: '93', dest: 'Toa Payoh', load: RdLoad.standing, min: '8'),
      RdArrival(route: '410', dest: 'Lor 1 Toa Payoh', load: RdLoad.seats, min: '15'),
    ],
  ),
  RdStop(
    name: 'Farrer Rd Exit A',
    code: '43071',
    dist: '2 min walk · 160 m',
    distShort: '160 m',
    badge: '2 MIN WALK',
    arrivals: [
      RdArrival(route: '48', dest: 'Marina Centre', load: RdLoad.standing, min: '4', then: 'then 12'),
      RdArrival(route: '93', dest: 'Toa Payoh', load: RdLoad.packed, min: '9'),
      RdArrival(route: '857', dest: 'Yishun Int', load: RdLoad.seats, min: '17'),
    ],
  ),
];

const Map<String, RdStation> kRdStations = {
  'holland': RdStation(
    key: 'holland',
    name: 'Holland Village',
    code: 'CC21',
    lineColor: _orange,
    lineFg: _onOrange,
    lineName: 'Circle Line',
    walk: '4 min walk · 320 m',
    freq: 'every 4–6 min',
    crowd: 'Moderate',
    crowdLoad: RdLoad.standing,
    firstTrain: '5:31 AM',
    lastTrain: '12:18 AM',
    exits: '4 exits · A to D',
    facilities: 'Lift, escalator & toilets',
    dirs: [
      RdStationDir(to: 'HarbourFront', via: 'via one-north · Buona Vista', plat: 'A', min: '3', then: 'then 9 min'),
      RdStationDir(to: 'Dhoby Ghaut', via: 'via Botanic Gardens · Bishan', plat: 'B', min: '5', then: 'then 12 min'),
    ],
  ),
  'botanic': RdStation(
    key: 'botanic',
    name: 'Botanic Gardens',
    code: 'CC19',
    lineColor: _orange,
    lineFg: _onOrange,
    lineName: 'Circle Line · Downtown Line',
    walk: '7 min walk · 560 m',
    freq: 'every 5–7 min',
    crowd: 'Light',
    crowdLoad: RdLoad.seats,
    firstTrain: '5:28 AM',
    lastTrain: '12:09 AM',
    exits: '3 exits · A to C',
    facilities: 'Lift & escalator',
    dirs: [
      RdStationDir(to: 'HarbourFront', via: 'via Farrer Road · Holland V', plat: 'A', min: '6', then: 'then 13 min'),
      RdStationDir(to: 'Marina Bay', via: 'via Bishan · Promenade', plat: 'B', min: '4', then: 'then 11 min'),
    ],
  ),
};

/// Nearby MRT stations shown on the home transfer card and the switch screen,
/// in order. The first entry is the "nearest station".
const List<({String key, String sub, String topMin})> kRdNearbyStations = [
  (key: 'holland', sub: '4 min walk · Circle Line', topMin: '3'),
  (key: 'botanic', sub: '7 min walk · CC · DT', topMin: '6'),
];

/// MRT & LRT line statuses for the Lines screen.
const List<RdMrtLine> kRdMrtLines = [
  RdMrtLine(
    code: 'EWL',
    name: 'East West Line',
    badgeBg: Color(0xFF009645),
    badgeFg: Color(0xFFFFFFFF),
    statusText: 'MAJOR DELAY',
    location: '',
    major: true,
    status: RdLineStatus.major,
    detail: 'Fault between Bugis and Tanah Merah. Add 15 min. Free bus bridging.',
  ),
  RdMrtLine(
    code: 'NSL',
    name: 'North South Line',
    badgeBg: Color(0xFFD42E12),
    badgeFg: Color(0xFFFFFFFF),
    statusText: 'Normal',
    location: 'Bishan · 12 min',
    status: RdLineStatus.normal,
  ),
  RdMrtLine(
    code: 'CCL',
    name: 'Circle Line',
    badgeBg: _orange,
    badgeFg: _onOrange,
    statusText: 'Busy',
    location: 'Farrer Road · 5 min',
    status: RdLineStatus.busy,
  ),
  RdMrtLine(
    code: 'NEL',
    name: 'North East Line',
    badgeBg: Color(0xFF9900AA),
    badgeFg: Color(0xFFFFFFFF),
    statusText: 'Normal',
    location: 'Serangoon · 22 min',
    status: RdLineStatus.normal,
  ),
];
