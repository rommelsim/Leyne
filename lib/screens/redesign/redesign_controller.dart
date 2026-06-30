// Controller for the SG Transit redesign — a faithful port of the prototype's
// `Component` state machine to a [ChangeNotifier]. Holds the phase/screen state,
// navigation stack, theming choices, and the small set of interactions the
// design wires up (sort, expand, save, live-tracking, toast).

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../data/data_store.dart';
import '../../data/models.dart';
import '../../data/mrt_geo.dart';
import '../../services/location_service.dart';
import '../../state/app_model.dart';
import 'redesign_bridge.dart';
import 'redesign_data.dart';

enum RdPhase { launch, onboarding, app }

enum RdPlatform { android, apple }

class RedesignController extends ChangeNotifier {
  RedesignController() {
    // Re-broadcast live-data changes so every redesign screen rebuilds when
    // nearby stops / arrivals / location update (mirrors the iOS model holding
    // DataStore.shared and views observing it).
    DataStore.shared.addListener(_onData);
    LocationService.shared.addListener(_onData);
    // Launch splash auto-advances after 2s. Returning users (who already
    // finished onboarding) skip straight to the app and resume location;
    // first-run users get the permission-priming onboarding.
    _launchTimer = Timer(const Duration(seconds: 2), () {
      if (phase == RdPhase.launch) {
        if (AppModel.shared.onboardingDone) {
          phase = RdPhase.app;
          LocationService.shared.startIfAuthorized();
        } else {
          phase = RdPhase.onboarding;
        }
        notifyListeners();
      }
    });
  }

  Timer? _launchTimer;
  Timer? _toastTimer;
  Timer? _holdTimer;

  final DataStore store = DataStore.shared;
  void _onData() => notifyListeners();

  // ---- theming ----
  bool dark = false;
  String seed = 'blue';
  bool premium = false;

  // ---- flow ----
  RdPhase phase = RdPhase.launch;
  RdPlatform platform = RdPlatform.android;
  int obStep = 0;

  // ---- navigation ----
  String screen = 'map';
  final List<String> stack = [];

  /// Direction of the last screen change, so push/pop animate consistently:
  /// forward slides the incoming screen in from the right, back reverses it so
  /// a "back" visibly slides the screen back out to the right.
  bool navForward = true;

  // ---- home / detail state — active selection points into the live data ----
  int stopIdx = 0;
  String? activeStopCode;
  String? activeService;
  String? activeRouteStop;
  String? activeStationName;
  String sortBy = 'eta'; // 'eta' | 'number'
  bool arrivalsExpanded = false;
  final Set<String> savedStopCodes = {};
  final Set<String> savedRoutes = {};
  RdStation? station;

  // ---- route state ----
  bool routeExpanded = false;
  bool routeDownExpanded = false;

  // ---- overlays ----
  bool searchOpen = false;
  bool tracking = false;
  bool luVisible = false;
  String? toast;

  static const int collapsedCount = 5;

  // ---------------------------------------------------------------- derived

  /// The nearby stop the user is looking at — the selected one, or the closest.
  NearbyStop? get currentNearby {
    final list = store.nearby;
    if (activeStopCode != null) {
      for (final n in list) {
        if (n.stopCode == activeStopCode) return n;
      }
    }
    return list.isNotEmpty ? list.first : null;
  }

  RdStop get currentStop {
    final n = currentNearby;
    if (n == null) {
      return const RdStop(
        name: 'Finding nearby stops…',
        code: '',
        dist: 'Waiting for your location',
        distShort: '',
        badge: '',
        arrivals: [],
      );
    }
    return rdStop(n);
  }

  bool get stopSaved {
    final code = currentNearby?.stopCode;
    return code != null && savedStopCodes.contains(code);
  }

  /// Arrivals for the current stop sorted by the active sort key.
  List<RdArrival> get sortedArrivals {
    final list = [...currentStop.arrivals];
    const big = 1 << 30;
    list.sort((a, b) {
      if (sortBy == 'number') {
        return (int.tryParse(a.route) ?? big).compareTo(int.tryParse(b.route) ?? big);
      }
      return (int.tryParse(a.min) ?? big).compareTo(int.tryParse(b.min) ?? big);
    });
    return list;
  }

  List<RdArrival> get visibleArrivals =>
      arrivalsExpanded ? sortedArrivals : sortedArrivals.take(collapsedCount).toList();

  bool get canExpandArrivals => sortedArrivals.length > collapsedCount;

  /// Nearest MRT/LRT station to the user — drives the Home transfer card.
  MrtNearestResult? get nearestMrt {
    final loc = LocationService.shared.lastLocation;
    if (loc == null) return null;
    final near = MrtGeo.nearest(lat: loc.lat, lon: loc.lon, limit: 1);
    return near.isEmpty ? null : near.first;
  }

  /// Other nearby stops (not the current one) for the switch screen.
  List<({RdStop stop, int index})> get otherStops {
    final cur = currentNearby?.stopCode;
    final out = <({RdStop stop, int index})>[];
    final list = store.nearby;
    for (var i = 0; i < list.length; i++) {
      if (list[i].stopCode != cur) out.add((stop: rdStop(list[i]), index: i));
    }
    return out;
  }

  RdStation get activeStation => station ?? kRdStations['holland']!;

  bool get routeSaved => activeService != null && savedRoutes.contains(activeService);

  List<String> get obSteps => platform == RdPlatform.apple
      ? const ['welcome', 'notif', 'location', 'att', 'done']
      : const ['welcome', 'notif', 'location', 'done'];

  String get obCurrent => obSteps[obStep.clamp(0, obSteps.length - 1)];

  /// The bottom Nearby/Saved nav only shows on the top-level screens.
  bool get showNav =>
      (screen == 'map' || screen == 'lines' || screen == 'saved') && !searchOpen;

  // ----------------------------------------------------------------- actions

  void go(String s) {
    navForward = true;
    stack.add(screen);
    screen = s;
    searchOpen = false;
    notifyListeners();
  }

  void back() {
    navForward = false;
    screen = stack.isNotEmpty ? stack.removeLast() : 'map';
    notifyListeners();
  }

  void toMap() {
    navForward = false;
    screen = 'map';
    stack.clear();
    searchOpen = false;
    notifyListeners();
  }

  void toLines() {
    navForward = true;
    screen = 'lines';
    stack
      ..clear()
      ..add('map');
    searchOpen = false;
    notifyListeners();
  }

  void openStop() => go('stop');

  void openRoute() => go('route');

  /// Open a specific stop's detail (from search / nearby / saved).
  void openStopCode(String code) {
    activeStopCode = code;
    go('stop');
  }

  /// Open a bus route, anchored to the stop the user is watching it from.
  void openBus(String service, String? stopCode) {
    activeService = service;
    activeRouteStop = stopCode;
    go('route');
  }

  void selectStop(int i) {
    navForward = false;
    final list = store.nearby;
    if (i >= 0 && i < list.length) activeStopCode = list[i].stopCode;
    screen = 'map';
    stack.clear();
    notifyListeners();
  }

  void openStation(String key) {
    navForward = true;
    stack.add(screen);
    station = kRdStations[key];
    screen = 'station';
    searchOpen = false;
    notifyListeners();
  }

  /// Open a real MRT/LRT station by display name (from the live transfer card).
  void openStationNamed(String name) {
    navForward = true;
    stack.add(screen);
    activeStationName = name;
    station = null;
    screen = 'station';
    searchOpen = false;
    notifyListeners();
  }

  void toggleSaveStop() {
    final n = currentNearby;
    if (n == null) return;
    final on = !savedStopCodes.contains(n.stopCode);
    if (on) {
      savedStopCodes.add(n.stopCode);
    } else {
      savedStopCodes.remove(n.stopCode);
    }
    notify(on ? 'Saved ${n.stopName}' : 'Removed ${n.stopName} from saved');
  }

  void notify(String msg) {
    _toastTimer?.cancel();
    toast = msg;
    notifyListeners();
    _toastTimer = Timer(const Duration(milliseconds: 3600), () {
      toast = null;
      notifyListeners();
    });
  }

  void dismissToast() {
    _toastTimer?.cancel();
    toast = null;
    notifyListeners();
  }

  // ---- save-button press/hold on the home header ----
  bool _held = false;

  void saveDown() {
    _held = false;
    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(milliseconds: 480), () {
      _held = true;
      notify('Opening saved stops');
      go('saved');
    });
  }

  void saveUp() {
    _holdTimer?.cancel();
    if (!_held) toggleSaveStop();
  }

  // ---- sort / expand ----
  void setSort(String s) {
    sortBy = s;
    notifyListeners();
  }

  void toggleArrivals() {
    arrivalsExpanded = !arrivalsExpanded;
    notifyListeners();
  }

  void toggleRoute() {
    routeExpanded = !routeExpanded;
    notifyListeners();
  }

  void toggleRouteDown() {
    routeDownExpanded = !routeDownExpanded;
    notifyListeners();
  }

  void saveRoute() {
    final svc = activeService;
    if (svc == null) return;
    final on = !savedRoutes.contains(svc);
    if (on) {
      savedRoutes.add(svc);
    } else {
      savedRoutes.remove(svc);
    }
    notify(on ? 'Bus $svc saved' : 'Removed Bus $svc from saved');
  }

  // ---- theming ----
  void toggleTheme() {
    dark = !dark;
    notifyListeners();
  }

  void togglePremium() {
    premium = !premium;
    notifyListeners();
  }

  void setSeed(String k) {
    seed = k;
    notifyListeners();
  }

  // ---- onboarding ----
  void setPlatform(RdPlatform p) {
    platform = p;
    obStep = 0;
    notifyListeners();
  }

  void obNext() {
    if (obStep >= obSteps.length - 1) {
      phase = RdPhase.app;
      screen = 'map';
      stack.clear();
    } else {
      obStep++;
    }
    notifyListeners();
  }

  void replayOnboarding() {
    phase = RdPhase.onboarding;
    obStep = 0;
    stack.clear();
    screen = 'map';
    notifyListeners();
  }

  // ---- live tracking ----
  String get _trackMsg =>
      'Live Update on · we’ll alert you when ${activeService ?? 'your bus'} is 1 stop away';

  void startTrack() {
    notify(_trackMsg);
    tracking = true;
    luVisible = true;
    navForward = true;
    stack.add(screen);
    screen = 'route';
    notifyListeners();
  }

  void trackFromRoute() {
    notify(_trackMsg);
    tracking = true;
    luVisible = true;
    notifyListeners();
  }

  void stopTrack() {
    tracking = false;
    luVisible = false;
    notifyListeners();
  }

  void dismissLU() {
    luVisible = false;
    notifyListeners();
  }

  void luView() {
    luVisible = false;
    if (screen != 'route') {
      navForward = true;
      stack.add(screen);
      screen = 'route';
    }
    notifyListeners();
  }

  // ---- search ----
  void openSearch() {
    searchOpen = true;
    notifyListeners();
  }

  void closeSearch() {
    searchOpen = false;
    notifyListeners();
  }

  /// Whether an in-app back action is available (so [PopScope] should not pop).
  bool get canHandleBack => searchOpen || stack.isNotEmpty || screen != 'map';

  /// Hardware-back handling for the app phase. Returns true if handled.
  bool handleBack() {
    if (searchOpen) {
      searchOpen = false;
      notifyListeners();
      return true;
    }
    if (stack.isNotEmpty) {
      back();
      return true;
    }
    if (screen != 'map') {
      toMap();
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    DataStore.shared.removeListener(_onData);
    LocationService.shared.removeListener(_onData);
    _launchTimer?.cancel();
    _toastTimer?.cancel();
    _holdTimer?.cancel();
    super.dispose();
  }
}
