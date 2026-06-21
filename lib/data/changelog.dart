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
  '2.9.0': WhatsNewEntry(
    headline: 'Leyne, right on your Home Screen.',
    items: [
      WhatsNewItem(
        icon: Icons.widgets_rounded,
        title: 'Home screen widgets',
        body:
            'Add a Nearest Stop or Favourite Service widget to your Home '
            'screen and see the next arrival at a glance — no need to open '
            'the app.',
      ),
      WhatsNewItem(
        icon: Icons.auto_awesome_rounded,
        title: 'Cleaner & tidier',
        body:
            'A more compact route view, a simpler live-crowd readout, and '
            'small refinements across the app.',
      ),
    ],
  ),
  '2.8.5': WhatsNewEntry(
    headline: 'A little more polish.',
    items: [
      WhatsNewItem(
        icon: Icons.tune_rounded,
        title: 'Two small fixes',
        body:
            'The full route card keeps its last stops clear of the navigation '
            'bar, and swipe-to-delete now shows up correctly in dark mode.',
      ),
    ],
  ),
  '2.8.4': WhatsNewEntry(
    headline: 'Back, done right.',
    items: [
      WhatsNewItem(
        icon: Icons.arrow_back_rounded,
        title: 'A more reliable Back button',
        body:
            'The system Back button now reliably returns you to your previous '
            'screen on every Android phone — no more surprise exits.',
      ),
    ],
  ),
  '2.8.1': WhatsNewEntry(
    headline: 'A smoother Back button.',
    items: [
      WhatsNewItem(
        icon: Icons.arrow_back_rounded,
        title: 'Back returns to where you were',
        body:
            'Pressing the system Back button now takes you to the previous '
            'screen instead of closing the app. Tap away — your place is kept.',
      ),
    ],
  ),
  '2.8.0': WhatsNewEntry(
    headline: 'MRT, reimagined — plus alerts in one place.',
    items: [
      WhatsNewItem(
        icon: Icons.train_rounded,
        title: 'A reimagined MRT tab',
        body:
            'Browse the whole network at a glance, with your nearest '
            'station up top. Tap a line for live station crowd and how '
            'busy it\'ll be in 30 minutes; tap a station for its details.',
      ),
      WhatsNewItem(
        icon: Icons.notifications_rounded,
        title: 'A new Alerts tab',
        body:
            'Train disruptions, lift maintenance, and your own bus alerts '
            'now live in one place — with a badge when something new lands. '
            'Settings moved to the gear in the top corner.',
      ),
      WhatsNewItem(
        icon: Icons.warning_amber_rounded,
        title: 'Know the moment a line goes down',
        body:
            'Leyne now notifies you when a new train disruption appears, '
            'even in the background, so you can reroute before you reach '
            'the platform.',
      ),
    ],
  ),
  '2.7.0': WhatsNewEntry(
    headline: 'A live MRT board — free for everyone.',
    items: [
      WhatsNewItem(
        icon: Icons.train_rounded,
        title: 'Live MRT board',
        body:
            'See every line\'s status at a glance, tap a line for live '
            'station crowd levels, and check which lifts are under '
            'maintenance — all free.',
      ),
      WhatsNewItem(
        icon: Icons.star_rounded,
        title: 'Save faster',
        body:
            'Swipe any nearby stop to save it, and drag your saved '
            'stops and buses into the order you want.',
      ),
      WhatsNewItem(
        icon: Icons.notifications_active_rounded,
        title: 'Disruption alerts',
        body:
            'Get notified the moment a line goes down, so you can '
            'reroute before you reach the platform.',
      ),
    ],
  ),
  '2.6.0': WhatsNewEntry(
    headline: 'A calmer look — plus weather and one-swipe alerts.',
    items: [
      WhatsNewItem(
        icon: Icons.circle_outlined,
        title: 'A calmer, monochrome look',
        body:
            'Leyne is now clean black-and-white throughout, so arrival '
            'times and the bus you\'re after stay front and centre. '
            '(Colour returns when trains arrive.)',
      ),
      WhatsNewItem(
        icon: Icons.wb_sunny_rounded,
        title: 'Weather and time on Home',
        body:
            'The Home screen now opens with the time and your local '
            'forecast — temperature, conditions, and a heads-up when '
            'rain\'s on the way.',
      ),
      WhatsNewItem(
        icon: Icons.notifications_active_rounded,
        title: 'Swipe to get notified',
        body:
            'Swipe a bus to set an arrival alert in one tap — you\'ll be '
            'buzzed at 3 minutes and again at 1 minute away. Clearer '
            'notifications with the ETA right on your lock screen.',
      ),
    ],
  ),
  '2.5.0': WhatsNewEntry(
    headline: 'Your bus, all on one screen.',
    items: [
      WhatsNewItem(
        icon: Icons.directions_bus_rounded,
        title: 'Everything at a glance',
        body:
            'The bus view is now one glanceable screen — arrival time, stops '
            'away, how full it is, the route, and the first & last bus — with '
            'no scrolling. Tap the route to open the full route card.',
      ),
      WhatsNewItem(
        icon: Icons.touch_app_rounded,
        title: 'Peek a nearby stop',
        body:
            'Press and hold any stop in Nearby for a quick look at its live '
            'arrivals, then open it in full if it\'s the one you want.',
      ),
      WhatsNewItem(
        icon: Icons.format_list_numbered_rounded,
        title: 'Tidier lists, and fixes',
        body:
            'A stop now lists its buses by number, your saved stops stay '
            'visible in Nearby, and the route folds away the long stretch to '
            'the terminus — plus polish and fixes.',
      ),
    ],
  ),
  '2.4.2': WhatsNewEntry(
    headline: 'Alerts that fit your trip.',
    items: [
      WhatsNewItem(
        icon: Icons.notifications_active_rounded,
        title: 'Tell me before it arrives',
        body:
            'Get a heads-up before your bus reaches your stop — or before '
            'it reaches your destination — with the lead time you choose. '
            'The new bell on the home screen opens every alert in one place.',
      ),
      WhatsNewItem(
        icon: Icons.location_on_rounded,
        title: 'Tracking that lines up',
        body:
            'The bus on the map now matches the stops-away and distance '
            'you read, and route progress follows the line all the way to '
            'its destination.',
      ),
      WhatsNewItem(
        icon: Icons.verified_rounded,
        title: 'Quicker saving and refresh',
        body:
            'Tap the pin to save a stop or the bus to save a bus, pull '
            'down to refresh while tracking a bus, plus polish and fixes.',
      ),
    ],
  ),
  '2.4.0': WhatsNewEntry(
    headline: 'A brighter, clearer Leyne.',
    items: [
      WhatsNewItem(
        icon: Icons.palette_rounded,
        title: 'Arrivals you can read at a glance',
        body:
            'A fresh, colourful look — green means a bus is close, '
            'amber means a little wait — so you can see what\'s coming '
            'without reading a single number.',
      ),
      WhatsNewItem(
        icon: Icons.people_outline_rounded,
        title: 'See how full the bus is',
        body:
            'Every arrival now shows whether there are seats, standing '
            'room, or it\'s filling up — so you can decide whether to '
            'wait for the next one.',
      ),
      WhatsNewItem(
        icon: Icons.star_rounded,
        title: 'Your favourite stops, one tap away',
        body:
            'Pinned stops now live in their own Favourites tab, so the '
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
        body:
            'Pick your drop-off in the route view and Leyne nudges you about '
            'two stops early — so you can look up and still get off in time.',
      ),
      WhatsNewItem(
        icon: Icons.my_location_rounded,
        title: 'Find stops by postal code',
        body:
            'Type any 6-digit postal code in Search to list the bus stops '
            'nearest that address, within your Settings radius.',
      ),
      WhatsNewItem(
        icon: Icons.schedule_rounded,
        title: 'Plan around your next buses',
        body:
            'The bus view now shows your next arrivals and tags each as live '
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
        body:
            'Arrival times without a live GPS fix are now tagged '
            '"~ scheduled", so you know which ones to fully trust.',
      ),
      WhatsNewItem(
        icon: Icons.my_location_rounded,
        title: 'Search by postal code',
        body:
            'Enter any 6-digit postal code to map the bus stops near that '
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
