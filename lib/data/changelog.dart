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
  '2.4.0': WhatsNewEntry(
    headline: 'A brighter, clearer Leyne.',
    items: [
      WhatsNewItem(
        icon: Icons.palette_outlined,
        title: 'Arrivals you can read at a glance',
        body: 'A fresh, colourful look — green means a bus is close, '
            'amber means a little wait — so you can see what\'s coming '
            'without reading a single number.',
      ),
      WhatsNewItem(
        icon: Icons.people_outline_rounded,
        title: 'See how full the bus is',
        body: 'Every arrival now shows whether there are seats, standing '
            'room, or it\'s filling up — so you can decide whether to '
            'wait for the next one.',
      ),
      WhatsNewItem(
        icon: Icons.star_rounded,
        title: 'Your favourite stops, one tap away',
        body: 'Pinned stops now live in their own Favourites tab, so the '
            'places you ride from most are always right there.',
      ),
    ],
  ),
  '2.3.0': WhatsNewEntry(
    headline: 'Smarter alerts, quicker taps.',
    items: [
      WhatsNewItem(
        icon: Icons.notifications_active_rounded,
        title: 'Get a heads-up before your stop',
        body: 'Pick your drop-off in the route view and Leyne nudges you about '
            'two stops early — so you can look up and still get off in time.',
      ),
      WhatsNewItem(
        icon: Icons.my_location_rounded,
        title: 'Find stops by postal code',
        body: 'Type any 6-digit postal code in Search to list the bus stops '
            'nearest that address, within your Settings radius.',
      ),
      WhatsNewItem(
        icon: Icons.schedule_rounded,
        title: 'Plan around your next buses',
        body: 'The bus view now shows your next arrivals and tags each as live '
            'GPS or a schedule estimate, so you know which to trust.',
      ),
    ],
  ),
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
