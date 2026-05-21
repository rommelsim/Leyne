// Release notes shown by the What's New screen.
//
// `kChangelog` is keyed by the marketing version (PackageInfo.version, e.g.
// "2.0.0" — no build number). When a returning user opens a build whose
// version has an entry here for the first time, WhatsNewScreen is shown
// once. Builds with no entry show nothing — so a silent bugfix release
// doesn't interrupt anyone. Add an entry whenever a release has news worth
// surfacing; drop old entries freely (only the running version is read).

import 'package:flutter/material.dart';

class WhatsNewEntry {
  const WhatsNewEntry({required this.headline, required this.items});

  /// One-line summary shown large at the top of the screen.
  final String headline;
  final List<WhatsNewItem> items;
}

class WhatsNewItem {
  const WhatsNewItem({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

const Map<String, WhatsNewEntry> kChangelog = {
  '2.0.0': WhatsNewEntry(
    headline: 'A clearer, more honest commute.',
    items: [
      WhatsNewItem(
        icon: Icons.gps_off_rounded,
        title: 'Know when a time is a guess',
        body: 'Arrival times without a live GPS fix are now tagged '
            '"~ scheduled", so you know which ones to fully trust.',
      ),
      WhatsNewItem(
        icon: Icons.schedule_rounded,
        title: 'First & last bus',
        body: 'Each service now shows its first and last bus for the day — '
            'with a heads-up when the last one has already left.',
      ),
      WhatsNewItem(
        icon: Icons.my_location_rounded,
        title: 'Search by postal code',
        body: 'Enter any 6-digit postal code to map the bus stops near that '
            'address. Set the search radius in Settings.',
      ),
      WhatsNewItem(
        icon: Icons.directions_bus_rounded,
        title: 'Arriving buses stand out',
        body: 'In Nearby, the number of a bus arriving now lights up green.',
      ),
    ],
  ),
};
