# Changelog

Reverse-chronological log of every shipped build. Source of truth for
what landed in each AAB / Archive. Update this file whenever a new
version is built (see [BUILDING.md](BUILDING.md)).

Format: one section per version, tagged with the platform and build
artifact path. User-facing iOS releases should also have a matching
entry in `kChangelog` inside `ios-native/Leyne/AppModel.swift`.

## Leyne 2.4.3 · iOS (21) · 2026-06-08

**2026-06-08 — iOS Archive (2.4.3, build 21):** iOS-only release continuing the
2.4.x redesign — reworks the Bus view into a single glanceable dashboard and
refines Nearby. No Android changes this round.

- **Bus view → one-screen dashboard:** ETA, stops-away, deck type, crowd, the
  next two arrivals, a compact route strip (origin → bus → your stop →
  destination), a live map, and first/last bus are all visible without
  scrolling (laid out in a `GeometryReader` so the map flexes to fit). The ETA
  hero was reorganised — ETA + stops-away headline, crowd top-right, deck +
  next-two in a quiet footer. (`SoftBusView.swift`)
- **Route & map as glass cards:** tapping the route strip raises a Liquid-Glass
  card (`.regularMaterial`) with the full route timeline + live "BUS HERE NOW"
  position; it folds the long tail so it opens on bus → your stop, and the
  expand/collapse toggles both ways. Tapping the map opens a half-height map
  card. (`SoftBusView.swift`, `RouteTimeline.swift`)
- **Alerts moved to the top bar:** a bell toggles the boarding alert (+ lock-
  screen tracking) and a save (bus) toggle, each with a confirmation toast so
  the buttons explain themselves. The alight reminder is removed for now.
  (`SoftBusView.swift`)
- **Stop list sorts by bus number** (natural order: 2 · 10 · 53 · 53M · 98A),
  with Arrival / Distance still available in the Sort menu. (`SoftStopView.swift`)
- **Nearby keeps saved stops:** saving a stop no longer removes it from Nearby —
  Nearby now hides only stops you explicitly hid. (`SoftHomeView.swift`)
- **Long-press a nearby stop → peek:** a mini Stop view (name + live arrivals,
  service · crowd · ETA) plus an Open Stop action. (`SoftHomeView.swift`)
- **Map fixes:** the inline preview auto-frames its markers (no edge clipping);
  the recenter button locates the bus's *current* position; a separate button
  recentres on you (shown only when a fix exists). (`SoftBusView.swift`)
- **Tests:** added `NearbyActionTests` covering Add to Saved / Hide From Nearby /
  Open Stop / Copy and the service-number ordering, with a regression that
  saving a stop never hides it from Nearby.
- Build + tests verified.

## Leyne 2.4.2 · Android (33) · 2026-06-06

**2026-06-06 — Android Play Store AAB (2.4.2, build 33):**
`build/app/outputs/bundle/release/app-release.aab`. First Android build of the
2.4.x line since 2.4.0 (closed alpha), so it carries the full notifications
redesign plus this round's refinements.

- **Notifications redesign — two configurable alert types:** notify me before
  the bus reaches MY STOP (set from the Stop view) and before it reaches MY
  DESTINATION (set from the Bus view), each with a lead-time picker (default
  5 / 10 min) and a "You'll be notified!" confirmation. A central **Manage
  alerts** screen (Active / Other, Edit → delete) collects them all. Replaces
  the old fixed 60 s lead with a per-alert user choice; one persisted alert
  list is the single scheduling source of truth. (`alert_timing.dart`,
  `bus_alert.dart`, `notify_when_sheet.dart`, `notify_confirm.dart`,
  `manage_alerts_screen.dart`, `app_model.dart`, `notifications.dart`)
- **Alerts a tap away on Home:** a bell button at the top-right of Nearby opens
  Manage alerts, with a badge showing how many you've set. (`soft_home_screen.dart`)
- **Simpler Settings:** removed the Language picker (the app is English-only),
  the redundant notifications on/off toggle (permission is requested once at
  onboarding), and the My Favourites shortcut (Saved is already a tab).
  (`soft_settings_screen.dart`)
- **Bus-tracking accuracy fixes:** the bus on the map, the stops-away / distance
  text, and route progress now agree — the bus index is grounded in the GPS fix,
  distance measures to YOUR stop, and progress runs to the line's terminus.
  (`bus_progress.dart`, `soft_bus_screen.dart`, `route_timeline.dart`)
- **Simpler save model:** one-tap pin saves a stop, one-tap bus glyph saves a
  bus, with distinct glyphs per type. (`soft_stop_screen.dart`,
  `soft_bus_screen.dart`)
- **"Home" → "Nearby":** the first tab is renamed Nearby with a location glyph.
  (`soft_tab_bar.dart`)
- **Ads on Stop & Bus pages; tab bar stays put:** the bottom bar (with the
  banner) now rides along on the Stop and Bus detail screens instead of
  vanishing. (`soft_stop_screen.dart`, `soft_bus_screen.dart`, `soft_root.dart`)
- **Notify sheet & route polish:** collapsible full route on the Bus view, a
  combined "arrival alert + live tracking" button, fixed truncated destination
  strings, a LIVE badge in the sheet header (replacing a dead chevron), and
  removal of the test-notification button and the redundant "manage in Settings"
  footer. (`route_timeline.dart`, `notify_when_sheet.dart`)
- **Build:** `flutter build appbundle --release`. pubspec `2.4.2+33`.

## Leyne 2.4.2 · iOS (20) · 2026-06-06

**2026-06-06 — iOS App Store / TestFlight Archive (2.4.2, build 20):** headline
feature is the notifications redesign; also bus-tracking accuracy fixes, a
simpler save model, and pull-to-refresh on the bus view.

- **Notifications redesign — two configurable alert types (NEW):**
  - *Notify me when my bus reaches MY STOP* (arrival) — set from the Stop view:
    tap a bus's bell → "Notify me when" sheet → choose how early (When arriving /
    2 / 5 / 10 / 15 min; default 5) → "You'll be notified!" confirmation. Fires
    that many minutes before the live ETA. Copy: "Bus 153 arriving soon /
    <stop> / 5 min to arrival."
  - *Notify me when my bus reaches MY DESTINATION* (alight) — set from the Bus
    view: destination defaults to the route terminus and any stop is selectable
    via the route timeline; lead adds a 30-min option (default 10). Fires that
    many minutes before the estimated destination arrival (~90 s/stop estimate,
    shown with the quiet "~" cue). Copy: "Your stop is next / <dest> / Arriving
    in 10 min."
  - A central **Manage alerts** screen (Active / Other sections, Edit → delete),
    reachable from the confirmation and from Settings.
  - Replaces the old hardcoded lead (60 s / 300 s) with a per-alert user choice.
  - Architecture: pure tested `AlertTiming` (lead options + fire-time math +
    copy), a `BusAlert` model + single persisted alert list (`leyne.alerts`) as
    the one scheduling source of truth, with one-time migration of legacy
    `tracked`/`activeAlight`. Notification alerts are now fully independent of
    pinned-card visibility (`Pin.tracked`). New files: `AlertTiming.swift`,
    `BusAlert.swift`, `V2/NotifyWhenSheet.swift`, `V2/NotifyConfirmView.swift`,
    `V2/ManageAlertsView.swift`; tests `AlertTimingTests.swift`,
    `BusAlertTests.swift`. (`AppModel.swift`, `SoftStopView.swift`,
    `SoftBusView.swift`, `SoftSettingsView.swift`)
- **Bus-tracking accuracy fixes:** the map pin used the real GPS fix while the
  "stops away" / callout / approaching card used a pure ETA estimate, so they
  disagreed (a pin ~1.3 km away while the text said "arriving now / 0 stops").
  The bus's route index is now grounded in the GPS fix (nearest stop, clamped to
  your stop), with the ETA estimate only as a fallback; the approaching-card
  distance now measures to YOUR stop. Route progress now runs to the line's
  terminus (was cut off just past your stop), and the green progress line ends
  exactly at the bus (the boarding stop no longer paints an isolated green
  segment). Logic extracted to a pure, tested `BusProgress` helper.
  (`SoftBusView.swift`, `V2/RouteTimeline.swift`, `BusProgress.swift`,
  `BusProgressTests.swift`)
- **Simpler save model:** the star menu is gone — the Stop view's save is a
  one-tap **pin** toggle (saves the stop) and the Bus view's is a one-tap **bus**
  toggle (saves the bus), each filling when saved. Distinct glyphs differentiate
  the two. (`SoftStopView.swift`, `SoftBusView.swift`)
- **Pull-to-refresh on the bus view:** tracking a bus now supports pull-to-
  refresh (matches Home / Stop / Saved). (`SoftBusView.swift`)
- **"Add bus" in Saved:** on the Buses segment, the add row now reads "Add bus"
  instead of "Add stop". (`SoftFavouritesView.swift`)
- **CI:** the `ios-native` job now runs the Swift unit test suite
  (`xcodebuild test`), not just a build. (`.github/workflows/ci.yml`)

## Leyne 2.4.2 · Android (32) · 2026-06-06

**2026-06-06 — Android parity with iOS 2.4.2:** the same notifications redesign,
bus-tracking fixes, save toggles, pull-to-refresh, and "Add bus" label, ported
to Flutter so both platforms match. Bump to `2.4.2+32`. Build artifact (when
archived): `build/app/outputs/bundle/release/app-release.aab`.

- **Notifications redesign:** `AlertKind`/`AlertTiming` (`lib/data/alert_timing.dart`),
  `BusAlert` (`lib/state/bus_alert.dart`), alert CRUD + persistence (`lyne.alerts`)
  + legacy migration in `app_model.dart`, scheduling via `scheduleAlerts` /
  `scheduleDestinationAlert` in `notifications.dart`, and the
  `notify_when_sheet.dart` / `notify_confirm.dart` / `manage_alerts_screen.dart`
  UI, wired into the Stop and Bus screens + Settings.
- **Bus-tracking fixes:** GPS-grounded bus index, distance-to-your-stop,
  route-to-terminus timeline, and the green-line fix — via the shared
  `lib/data/bus_progress.dart` helper and `widgets/v2/route_timeline.dart`.
- **Save toggles, pull-to-refresh, "Add bus" label** mirrored from iOS.
- Tests: `test/alert_timing_test.dart`, `test/bus_alert_test.dart`,
  `test/bus_progress_test.dart`. CI runs `flutter analyze` + `flutter test`.

## Leyne 2.4.1 · iOS (19) · 2026-06-06

**2026-06-06 — iOS App Store / TestFlight Archive (2.4.1, build 19):** patch
over 2.4.0 (that train is closed for new submissions, so the marketing version
moves to 2.4.1). Carries the ad-banner fix from on-device testing.

- **Banner ad fix:** the bottom banner went permanently blank after leaving a
  tab and returning (e.g. Home → Saved → Home). Cause: a single shared
  `BannerHostView` (UIKit singleton) was mounted by all four tab gutters, and a
  `UIView` can only live in one place — whichever tab was visited last "stole"
  it. Each tab gutter now owns its own banner host via
  `BannerAdView.Coordinator`, so banners persist per tab. The `window != nil`
  load gate keeps only the visible tab requesting ads (AdMob-policy clean).
  (`ios-native/Leyne/AdBanner.swift`)
- **Home card — Top-3 arrivals:** each nearby-stop card now lists up to three
  services ranked favourite-first → soonest, each with its next arrival and a
  gold star on favourites, plus a "View all buses" footer — replacing the old
  one-service / three-times layout. Ranking is a stable partition of the
  eta-sorted services (`rankedArrivals` in `SoftHomeView.swift`); a bus counts
  as favourite when saved at the stop or anywhere.
- **Bus view — route-progress first:** the bus screen now leads with a compact
  "approaching" card (stops away · arriving-in · distance · slim journey bar)
  and the route-progress timeline; the live map moved to a full-screen sheet
  behind a "View on map" button. (`ios-native/Leyne/V2/SoftBusView.swift`)
- **Stop detail — grouped list + next-three times:** "All arriving buses" is now
  a single grouped card; each service row shows its next three arrival times in
  columns (lead column proximity-tinted with a live signal) instead of one ETA
  pill, with a "Show more" expander past six services. LIVE moved up beside the
  walk/distance line. (`ios-native/Leyne/V2/SoftStopView.swift`)
- **Live Activity ↔ app data mismatch (critical):** the Dynamic Island / Lock
  Screen showed a different "stops away" and minute count than the bus screen
  (e.g. 8 stops / 8 min vs the app's 5 stops / 7 min). Two causes, both fixed in
  `AppModel.startLivePolling` / `liveState`: stops-away used a GPS-nearest-stop
  search while the app derives it from the ETA (~90 s/stop) — now both use the
  ETA method; and the minute count used `ceil` vs the app's `fmtETA` floor — now
  both floor. (`ios-native/Leyne/AppModel.swift`)
- **Quick pin/save/alert menu:** the star on Stop and Bus views now opens a menu
  to pin/unpin (Saved), save a bus (here / anywhere) and set/cancel an arrival
  alert — no sheet, no leaving the page. The star fills green when saved.
  (`SoftStopView.swift`, `SoftBusView.swift`)
- **Bus view — Live updates card + stop count:** added a "Live updates — Service
  running smoothly" status card below the map button, and the route expander now
  shows the stop count ("View all N stops").

## Leyne 2.4.1 · Android (31) · 2026-06-06

**2026-06-06 — Android parity with iOS 2.4.1:** ports the three arrival-view
redesigns from the iOS build to Flutter so both platforms match. Bump to
`2.4.1+31`. Build artifact (when archived):
`build/app/outputs/bundle/release/app-release.aab`.

- **Home card — Top-3 arrivals:** each nearby-stop card now lists up to three
  services ranked favourite-first → soonest (gold star on favourites), each with
  its next arrival, plus a "View all buses" footer — replacing the old
  one-service / three-times layout. (`lib/screens/v2/soft_home_screen.dart`)
- **Stop detail — grouped list + next-three times:** "All arriving buses" is a
  single grouped card; each row shows its next three arrival times in columns
  (lead column proximity-tinted with a live signal). The old per-card list +
  "Show all buses" navigation became an inline "Show more" expander past six
  services. LIVE moved up beside the walk/distance line.
  (`lib/screens/v2/soft_stop_screen.dart`)
- **Bus view — route-progress first:** leads with a compact "approaching" card
  (stops away · arriving-in · distance · slim journey bar) and the route-progress
  timeline; the live map moved to a full-screen page behind a "View on map"
  button. (`lib/screens/v2/soft_bus_screen.dart`)
- **Ongoing-notification minute fix:** the live-tracking notification used `ceil`
  while the bus screen uses `fmtEta` floor, so it read one minute higher; now both
  floor (`lib/services/notifications.dart`). (Android has no Live Activity, so the
  iOS stops-away mismatch doesn't apply here.)
- **Quick pin/save/alert menu:** the star on Stop and Bus views now opens a popup
  menu — pin/unpin (Saved), save a bus (here / anywhere), set/cancel arrival alert
  — instead of a bottom sheet; the star fills when saved.
- **Bus view — Live updates card:** added a "Service running smoothly" status card
  below "View on map".

## Leyne 2.4.0 · Android (30) · 2026-06-05

**2026-06-05 — Android closed-alpha AAB (2.4.0, build 30):** the 9-screen
Material redesign brought to parity with iOS, plus bug fixes from on-device
testing. Build artifact: `build/app/outputs/bundle/release/app-release.aab`.

- **9-screen redesign (Material):** Home ("Stops near you" — Closest/Other
  sections, new nearby card with 3-ETA columns, live-updates banner), Stop
  Detail, Bus tracking (contained map card + live-position callout + route
  progress; next-buses moved to Stop Detail), Saved tab, Search (recents list
  + Browse grid), Settings (grouped rows). Tab bar is now Home · Saved ·
  Search · Settings.
- **Search:** tokenised + synonym matching (mrt/station→stn, interchange→int)
  so "yio chu kang mrt" resolves; recents list with per-row remove + Clear.
- **Saved:** shows only saved stops + saved bus services (no nearby bleed-in);
  All / Stops / Buses segments; swipe-left to delete.
- **Fixes:** Home filter/map header buttons removed; nearby-card "Arr" wrap
  fixed; Search keeps the bottom tab bar visible after the keyboard closes.
- **Ads:** re-enabled for closed testing via **Google test ad units**
  (`kLyneAdsTest` defaults `true`) to protect the AdMob account from invalid
  traffic. ⚠️ Flip to production ads (`--dart-define=LYNE_ADS_TEST=false` or
  reset the default) before the public Play Store release.

## Leyne 2.4.0 · iOS (18) · 2026-06-04

**2026-06-04 — iOS UI overhaul (2.4.0, build 18):** the redesign from the June
mockups, built on branch `ui-overhaul-2.4.0` (worktree) so 2.3.3 stayed
shippable. Tracking doc: `docs/UI_OVERHAUL_2.4.0.md`.

- **Semantic colour returns** (`Theme.swift` `soon`/`mid` tokens, both light &
  dark): green = arriving soon / seats, amber = mid-wait / standing, neutral =
  far / scheduled. `V2/Proximity.swift` adds `ETATier`, `etaColor`,
  `serviceBadgeColors`, `occupancyColor`, `OccupancyLabel`. Confidence stays
  shape/opacity + the whisper "~" — colour is proximity + crowding only; a
  scheduled/ghost arrival is never painted a confident green.
- **Home** (`SoftStopCard`/`SoftHomeView`): card-style ETA-ordered chips, lead
  chip green "Arriving soon"; distance on its own row; "NEAR YOU" blue + green
  LIVE dot; "Nearby stops" header. Pinned section moved to Favourites.
- **Tab bar** (`SoftRoot`/`SoftTabBar`): four inline labelled tabs — Home ·
  Favourites · Settings · Search (Search is no longer the detached `.search`
  circle); selection tint = location blue. New `SoftFavouritesView` (pinned
  stops). Ad banner re-anchors above the bar via the existing gutter inset.
- **Stop view** (`SoftStopView`): proximity-coloured service badges,
  destination + occupancy, big coloured ETA + dot, "Arriving soon" lead row,
  "Updated N ago" line, ETA/Bus no./Distance sort, LTA-estimates footer.
- **Bus view** (`SoftBusView`/`RouteTimeline`/`CrowdMeter`): green hero when
  imminent, coloured occupancy bars + fuller labels, green route progress
  (checked past · green bus-here · green your-stop ring), green map stop pin.
- **Bus view route bottom** (`RouteProgressBar` + `RouteTimeline`): compact
  horizontal **ROUTE PROGRESS** summary with "N stops remaining"; **FULL ROUTE**
  list with per-stop times + "View all stops" toggle. The bus's position on the
  route (`estimatedBusIndex`) is derived from the ETA the same way the map pin
  is — upcoming stops show "ETA H:MM", the bus's stop shows the plain clock, and
  passed stops show a check but **no fabricated past time** (`etaClock` /
  `fmtClock`, honours the 24-hour setting).

- **Favourites** (`SoftFavouritesView`): rebuilt to the FavouriteView mockup —
  header (+ / gear), **Favourite stops** (enriched cards: gold star, distance +
  walk, chips, "Updated N ago" + crowd footer) and **Favourite services**
  (derived from pins' `tracked` buses: badge + "To {dest}" + anchor stop + ETA),
  per-section Edit/remove. No new model — favourite stop = pin without
  `tracked`, favourite service = pin with `tracked`.

- **Pin flow + favourite services** (`FavService` model, `SaveSheet`): new
  persisted `FavService { no, stop? }` (`leyne.favServices`) — `stop == nil` =
  "anywhere" (next arrival on the route near you), set = "at this stop". Stop
  view gains a pin button → "Save this stop" sheet; Bus view's stop-pin pill is
  replaced by a favourite button → "Save this service" sheet (anywhere / at this
  stop). Favourites gains All/Stops/Services/Bus+Stop filter chips. Favourite
  stops = `m.pins`; favourite services = `m.favServices` (independent of
  `Pin.tracked`, which stays alerts-only).

**Known remaining (Phase E/F polish):** green map route **polyline** not drawn
(markers are green, the connecting line isn't). Dark-mode colour is on by
default (revert = `Theme.dark` `soon`/`mid` tokens). On-device visual QA still
needed (no simulator was run during the build).

## Leyne 2.3.3 · iOS (17) · 2026-06-04

**2026-06-04 — iOS version bump 2.3.2 → 2.3.3 (build 17):** 2.3.2 (build 16) was
already uploaded/approved and is live on TestFlight, so the ad-banner fix ships
as a new version. Bumped `MARKETING_VERSION` 2.3.2 → 2.3.3 and
`CURRENT_PROJECT_VERSION` 16 → 17 across all configs in
`ios-native/Leyne.xcodeproj/project.pbxproj`. Added a `kChangelog["2.3.3"]`
What's New entry. Re-Archive in Xcode to upload.

**AdBanner.swift — banner blank-after-a-while fix:** the bottom-accessory banner
loaded exactly once per session then went blank and never recovered. Root causes:
(1) the `rootViewController` was captured once and went stale when
`tabViewBottomAccessory` re-parented the banner; (2) `didLoad`/`fired` latches
meant no reload or retry ever happened. Fix: `didMoveToWindow()` now refreshes
`rootViewController` on every window re-entry and re-attempts a load (45s debounce
via `kAdRefreshDebounce`); load failures retry with exponential backoff
(`kAdRetryDelays` = 5 → 10 → 30s), reset on a successful `didReceiveAd`. Release
ad config unchanged (prod unit `ca-app-pub-5864511655536507/9782205994`). Builds
clean in Release.

## Leyne 2.3.2 · iOS (16) · 2026-06-03

**2026-06-03 — iOS version bump 2.3.1 → 2.3.2 (build 16):** the 2.3.1 train was
already approved/closed on App Store Connect (upload rejected: codes 90186 /
90062 — `CFBundleShortVersionString` must exceed the approved 2.3.1). Bumped
`MARKETING_VERSION` 2.3.1 → 2.3.2 and `CURRENT_PROJECT_VERSION` 15 → 16 across
all configs in `ios-native/Leyne.xcodeproj/project.pbxproj`. Ships this session's
iOS work (two-direction routes, search→route + keyboard dismiss, long-route
collapse, monochrome dark mode). Added a `kChangelog["2.3.2"]` What's New entry.
Re-Archive in Xcode to upload.

## Leyne 2.3.1 · iOS (15) · Android (28) · 2026-06-03

**2026-06-03 — Closed-alpha build 28 (Android):** rebuilt the closed-testing AAB
(`build-android-closed-test.sh`, `LYNE_ADS_TEST=true` → Google test ad unit) at
versionCode 28, folding in every fix below. Supersedes the never-finalised build
27. `flutter analyze` clean · 127 tests pass.

**2026-06-03 — Android performance + design/parity review pass:**

> Full-team review of the Android build after reports of frame drops while
> navigating and design drift from iOS. Findings fixed across performance,
> Material consistency, iOS parity, and test coverage. Shipped in build 28.
>
> **Performance (the FPS drops):**
> - **Bus view** (`soft_bus_screen.dart`): the bus-pin glide drove `setState` on
>   the whole screen every animation frame, rebuilding the full map `Stack`
>   (tiles + all markers + sheet) at 60fps for 1.5s per move. Now scoped to a
>   `ValueNotifier` + `AnimatedBuilder` that rebuilds only the marker layer; the
>   draggable sheet drag likewise moved to a `ValueListenable` (no per-pointer
>   `setState`); `_timelineStops()` computed once per build instead of 4×.
> - **Home + Nearby** (`soft_home_screen.dart`, `soft_nearby_screen.dart`): the
>   whole list rebuilt every 1s tick. Split into a structural outer listener with
>   the per-second ETA wrapped in its own narrow `ListenableBuilder`; converted to
>   `ListView.builder` + `RepaintBoundary`; memoised walk-distance per location
>   fix; compute confidence once per card; dropped a redundant per-rebuild sort.
> - **DataStore** (`data_store.dart`): earlier per-poll full re-sort of ~5000
>   stops was already removed; now `notifyListeners()` also fires only when an
>   arrival state actually changes (value-equality guard), killing redundant
>   rebuild storms from the 12 nearby prefetches + 1s pin ticker.
>
> **Material design consistency:** shared `LyneRadius` (md/lg/full) + `kSectionGap`
> tokens replace ad-hoc radii; `SoftToggle`→Material `Switch` and `SortChipRow`→
> `ChoiceChip` (48dp targets, ripple, TalkBack); fixed the invisible light-mode
> nav-bar indicator; fixed InkWell ripple overflowing rounded card/section corners
> (Stop, Settings, MRT alerts); unified all-caps label tracking; map controls →
> Material ripple with 48dp tap targets.
>
> **iOS parity:** added the missing Pin/Unpin button to the Bus view; moved MRT
> disruption alerts above the stop list (was buried below Nearby); added the
> imminent-bus accent stroke+glow on Stop detail; aligned Stop detail to iOS
> uniform cards; "recent" bus tier promoted to a first-class state with its own
> a11y label; route-timeline emoji→icon, "THIS STOP" label, suppressed the
> misleading "N stops away" badge, added stop-code subline; title → "Stops near
> you". (Decision: Home pinned cards keep Android's ETA-row layout rather than
> porting the iOS bus-number chip-grid — for a favourite stop, "when" beats
> "which", so the rows that show next-arrival ETAs are the stronger call. The
> greeting carries no user name on either platform, by design.)
>
> **Tests:** +36 (now 127 total) covering `Freshness.from` boundaries, the
> `ArrivalConfidence.of` matrix, `_refreshNearbyServices` semantics, the notify
> guard, and both cold-start prefetch orderings.
>
> **Follow-ups (same day):**
> - **Bus-sheet physics** (`soft_bus_screen.dart`): the draggable sheet snapped
>   to its peek/expanded position instantly on release. Replaced the zero-anim
>   snap with a velocity-aware `SpringSimulation` (unbounded `AnimationController`)
>   so a flick flings it open/closed and a slow release eases with momentum —
>   still scoped to the `Transform.translate` only, so no perf regression.
> - **Bus search opened the wrong screen** (`soft_search_screen.dart`,
>   `soft_bus_screen.dart`, `soft_root.dart`): tapping a bus result (e.g. "156")
>   resolved the service origin and opened that *bus stop's* arrivals instead of
>   the bus's route. Now it opens the bus **route view** anchored at the origin
>   with a new `fullRoute` flag so the whole route is listed (the long-route
>   collapse keeps it scannable). iOS `SoftSearchView` has the same gap — mirror
>   pending.
> - **Long route timelines** (`route_timeline.dart` + iOS `RouteTimeline.swift`):
>   routes longer than 8 stops now fold the lead-in (everything >2 stops before
>   the boarding/bus focal stop) into an expandable "Show N earlier stops" node,
>   keeping the actionable boarding + upcoming area visible. Implemented
>   identically on both platforms (shared `maxVisible = 8`, same focal/keepFrom
>   logic, collapse node drawn as part of the connector line).
> - **Two-direction routes (both platforms):** the Bus view now shows BOTH
>   directions of a service (origin→terminus and back) with a "To {destination}"
>   segmented toggle. New `serviceRoute()` data API (`data_store.dart` +
>   iOS `DataStore.swift`) returns all directions with the anchor-stop direction
>   preselected; `SoftBusScreen`/`SoftBusView` gained a `fullRoute` flag and the
>   toggle. The non-anchor direction shows its full route and never mis-labels a
>   "THIS STOP" boarding badge.
> - **Android search rebuilt to the iOS auto-detect model** (`soft_search_screen.dart`):
>   dropped the explicit Postal/Stop ID/Bus #/Place filter chips; input kind is
>   now auto-detected (6-digit → postal geocode; otherwise combined **Services**
>   + **Bus stops** result sections), mirroring `SoftSearchView`. Kept the
>   Android-only Recent chips and example chips. Search routing verified on both
>   platforms: **Bus # → bus route view**; **Stop ID / Place / Postal → stop
>   detail**.
> - **iOS search keyboard couldn't be dismissed** (`SoftSearchView.swift`): a
>   plain `TextField` has no Done bar, so once focused the keyboard was stuck.
>   Added `.scrollDismissesKeyboard(.interactively)` (drag results down to hide)
>   and tap-empty-space-to-dismiss. (Android already dismisses via the back
>   button.)
> - **Dark mode → monochrome black-and-white (both platforms)** (`theme.dart` +
>   iOS `Theme.swift`): removed the brand-green dark palette (warm-green bg/surface,
>   mint accent, green liveBg). Dark is now neutral — `#0F0F0F` bg, white `fg`,
>   white accent (LIVE/arriving/pin), neutral grey surfaces — mirroring the light
>   mode's black-ink monochrome. Amber/red disruption colours and the real MRT
>   line hues are kept.
> - **Home cards rebuilt to mirror iOS** (`soft_home_screen.dart`): replaced the
>   two bespoke Android cards (Pinned = ETA rows; Nearby = distance-tile + rows)
>   with a single unified `_SoftStopCard` + `_MiniBusChip`, a direct port of iOS
>   `SoftStopCard` — map-pin tile · name · "code · road" · trailing distance/walk
>   · chevron, then a wrapping grid of bus-number chips (sorted by number, 4 +
>   "+N", whisper-`~` confidence tell). Used for BOTH Pinned and Nearby so the
>   page reads as one language, matching iOS. Material-native (Material surface +
>   InkWell ripple) and keeps the per-second ETA refresh scoped to the chip row.
> - **Removed the Android Nearby tab** (`soft_tab_bar.dart`, `soft_root.dart`,
>   deleted `soft_nearby_screen.dart`): iOS has no standalone Nearby tab — it
>   folds Nearby into the Home page — so the Android 4th tab duplicated the Home
>   "Nearby" section. Bottom bar is now Home / Settings / Search, matching iOS.
> - **Two search buttons on Android home** (`soft_home_screen.dart`): the home
>   header had a search IconButton *and* the bottom bar has a Search tab. iOS's
>   home header has no search button (search lives in the tab bar), so the
>   redundant header button was removed — search is now reached via the
>   bottom-bar Search tab (and the empty-state Search button), matching iOS.
> - **Slow open of the bus view from search** (`soft_search_screen.dart` +
>   `SoftSearchView.swift`): tapping a bus result blocked on a cold load of the
>   large BusRoutes dataset (needed by `originStop` + the route view). Now the
>   dataset is warmed via `ensureRoutes()` when Search opens, so the tap opens
>   the route view immediately.
> - **Inconsistent "Show N earlier stops" on the route** (`soft_bus_screen.dart`
>   + `SoftBusView.swift`): in full-route (bus-search) mode the anchored origin
>   often reappears late on the *return* direction and got badged as the boarding
>   stop, pushing the collapse focal point to ~index 53 → "Show 51 earlier stops"
>   on one direction but not the other. Fixed by not marking any "THIS STOP" in
>   full-route mode (there's no boarding stop when browsing a route), so both
>   directions render the whole route cleanly with no spurious collapse.
> - **Back from a search result jumped to Home** (`soft_root.dart` + iOS
>   `SoftRoot.swift` legacy route): the search screen was popped *before* pushing
>   the tapped stop/bus, so the stack lost search and Back landed on Home. Now
>   the result is pushed on top of search → Back returns to the results, Back
>   again returns Home. (The first-class iOS search tab already behaved correctly.)

**2026-06-03 — Android parity pass + closed-alpha build 27 (Android):**

> Brought the Android (Flutter) app up to design + feature parity with the iOS
> 3.0 rewrite, staying Material-native (no cross-platform idiom bleed). Android
> had drifted behind — it lacked the data-confidence system entirely and still
> used the old binary `monitored` treatment with a loud "~ scheduled" label and
> a colour-dot crowd indicator. Build 26 → 27 for the first closed-alpha upload.

- **Confidence/freshness system** ported to Flutter (`lib/widgets/v2/confidence.dart`):
  four-state `ArrivalConfidence` (live / stale / unconfirmed / none) + `Freshness`
  derived from a new `DataStore.lastRefresh`, with `ConfidenceEta` (whisper-quiet
  trailing "~"), `ConfidenceDot` (filled / hollow / dashed via `CustomPainter`),
  `ConfidenceStatusPill`, and a bar `CrowdMeter`. Wired into Home, Stop and Bus —
  nothing fabricated, honoring the "timely but quietly honest" rule.
- **Light theme → monochrome** black ink accent on `#F2F2F2`, matching iOS
  (was the green mint). Dark mode already matched.
- **Home**: added the Nearby section (Pinned + Nearby, de-duped) and a
  live-location status row; empty state gated on both being empty.
- **Stop**: added a Distance sort — `Service.busLat/busLon` are now plumbed
  through from LTA's NextBus feed (previously parsed but dropped in the mapper) —
  plus a header walk-distance chip.
- **Search**: recents now surface as tappable chips, example/suggestion chips,
  and postal retry + "widen the radius in Settings" guidance.
- **Bus**: rebuilt as an immersive full-bleed map + draggable bottom sheet with
  a three-tier bus pin (live GPS → recent/dimmed → estimated-from-route-geometry),
  gliding between positions.
- **Map now uses free CartoDB tiles** (Positron in light / Dark Matter in dark,
  theme-aware) via `flutter_map` — a modern basemap with no API key and no
  billing, replacing the dated default OSM raster. (Native Google Maps was
  trialled then reverted to avoid Maps SDK billing.)
- `ServiceBadge` sizes aligned to the iOS spec.
- **Closed-alpha AAB** built via `build-android-closed-test.sh`
  (`LYNE_ADS_TEST=true`), so it serves Google's reserved test unit, not the real
  `/6513878972` banner. Promote with `build-android-prod.sh` for production.

**2026-06-02 — AdMob account migration + version bump (iOS):**

> The `leyne0000@gmail.com` Google account was approved/verified, so ads were
> moved off the personal `rommelsim` stopgap publisher and back onto the project
> publisher `ca-app-pub-5864511655536507`. Marketing version bumped 2.3.0 → 2.3.1
> (build 15) because App Store Connect closed the 2.3.0 train for new submissions
> once 2.3.0 was approved and released. Also surfaces the 3.0 visual overhaul in
> What's New — it shipped in 2.3.0 but was never called out to users there.

- **What's New (user-facing):** added a `kChangelog["2.3.1"]` entry announcing
  the redesign — the calmer Soft-mint look, at-a-glance live/estimated/scheduled
  confidence (freshness dot + status pill), and the immersive full-screen bus
  map with draggable sheet. (The design itself shipped in 2.3.0; this is the
  first build to announce it.)
- AdMob publisher swapped to `leyne0000`'s `ca-app-pub-5864511655536507` across
  both platforms: iOS app ID `~6330743279` + banner `/9782205994`
  (`LeyneInfo.plist`, `AdBanner.swift`); Android app ID `~5685985257` + banner
  `/6513878972` (`AndroidManifest.xml`, `ad_banner.dart`). Test units (DEBUG /
  `LYNE_ADS_TEST`) unchanged — still Google's sample units.
- The personal `rommelsim` publisher `ca-app-pub-6816620800052795` is retired
  from ads; AdMob + Play Console now both live under `leyne0000@gmail.com`.
- **The Android closed-testing AAB (now build 27, see above)** is built via
  `build-android-closed-test.sh` (`LYNE_ADS_TEST=true`), so it serves Google's
  reserved test unit `…/6300978111`, not the real `/6513878972`. Promote to
  production by rebuilding with `build-android-prod.sh` before the public release.
- **Action still required:** publish a GDPR + IDFA consent message for the new
  iOS app `~6330743279` in AdMob → Privacy & messaging, or UMP consent will
  error in the EEA/UK.

## Leyne 2.3.0 · iOS (14) · Android (25) · 2026-05-31 · released

**2026-05-31 — Leyne 3.0 design alignment: the data-confidence system (iOS):**

> Implemented the "honest about uncertainty" design (Claude Design handoff) on
> iOS, keeping the Soft mint palette. Per the spec, confidence is expressed
> hue-free — opacity, dot shape and freshness microcopy — so it never competes
> with the accent. No version bump / archive yet; `kChangelog` gets its
> user-facing entry when this is cut into a build.

- New four-state per-arrival confidence (`V2/Confidence.swift`): live / stale /
  unconfirmed (ghost bus) / no-service, derived honestly from LTA's `Monitored`
  flag + feed freshness — nothing fabricated. Ships reusable treatments:
  confidence-aware ETA numerals, a freshness dot (filled / hollow / dashed),
  a LIVE/ESTIMATED/SCHEDULED status pill, and a crowd meter glyph.
- Stop view (`SoftStopView`): every arrival now carries the confidence
  treatment; a crowd glyph (person + fill-bars) replaces the dot + word; a
  footer explains the aging / scheduled-only rows. Distance sort was
  intentionally **not** added — LTA shares no live bus position, so a
  bus-distance sort would be fabricated (contradicting the design's own thesis).
- Bus view (`SoftBusView`) rebuilt as an immersive full-bleed map + draggable
  bottom sheet: the peek answers "when's my bus" (confidence hero ETA + status
  pill + which stop + crowd); pulling the sheet up reveals alerts and the full
  route timeline inline. All prior wiring (alerts, Live Activity, alight
  scheduling, pin) preserved.
- Onboarding gained an upfront honesty value-prop screen showing the
  live / estimated / scheduled mini-states. The three iOS permission prompts
  (Location, Notifications, ATT) were already primed in-context.
- Home-screen widget + Live Activity now distinguish live vs scheduled arrivals
  (the "~" + dimmed treatment), and the Live Activity reflects honest
  live → scheduled transitions mid-trip — `Monitored` threaded end-to-end
  (LTA → snapshot → `ContentState` → lock screen / Dynamic Island).
- App + widget extension build clean (`xcodebuild`, iOS Simulator).

**2026-05-31 — Whisper-quiet confidence rolled out app-wide (positioning: timely updates):**

> Product decision: the selling point is **timely updates**, so the UI must not
> advertise data gaps. The loud "honesty" cues from the Leyne 3.0 confidence
> system are demoted *everywhere* to a single near-invisible "~"; numbers and
> map pins always read confidently. Data-layer + accessibility honesty is
> untouched. See memory `feedback_timely_over_honest.md`.

- **Stop view**: `ConfidenceETA` now renders full-ink — no dimming, no "~"
  prefix — with only a faint trailing "~" for estimated/aged arrivals; the
  "aging & scheduled-only arrivals shown honestly" footer was removed.
- **Home cards** (`MiniBusChip`): confident chips — dropped the dim, the dashed
  outline and the "~" prefix; faint trailing "~" only.
- **Widget + Live Activity**: dropped the dimmed colour and the "sched" unit
  (now always "min"); the lone tell is the small "~". `AppModel.liveState` no
  longer emits "Scheduled · N min" (status reads "Arrives in N min").
- **Onboarding**: the "Honest about your wait" confidence screen is replaced by
  **"Always up to the minute"** (`OnbVisualLive`: live arrivals · on the map ·
  smart alerts); welcome copy now leads with real-time, not "admits when unsure".
- `monitored` still flows end-to-end (it powers the "~" and the accessibility
  labels); the demotion is visual only. App + widget build clean (`xcodebuild`).

**2026-05-31 — Bus view: always-on map position (live → last-known → estimated) + new layout (iOS):**

> The map used to drop the bus marker the instant LTA stopped sharing a GPS
> coordinate (scheduled "ghost" buses, or a monitored bus that dropped its fix
> mid-poll), so the bus often "couldn't be tracked". Confirmed there's no better
> feed — LTA DataMall's `BusArrivalv3` is the single source every SG app reads,
> and it only carries a position for `Monitored == 1` arrivals. So instead of a
> richer feed, the Bus view now **always plots the bus**, in one of three honesty
> tiers, never disguised as more certain than it is.

- Three-tier bus position (`SoftBusView`): **live** (real GPS fix) → **recent**
  (had a fix, dropped this poll → last-known) → **estimated** (no fix / ghost
  bus → position derived from route geometry + ETA). The bus is **always**
  plotted so the map never goes blank.
- **Whisper-quiet confidence (positioning: "timely updates"):** the map pin is
  *always a confident solid pin* and the hero ETA is *always a full-ink number* —
  the app never advertises a data gap. The only tell that a position is
  estimated/aged is a near-invisible "~" beside the ETA; the status pill reads
  LIVE whenever a bus is present. The loud cues from the first pass (dashed/"≈"
  pins, dimmed numerals, the "Ghost bus / not transmitting GPS" banner, the map
  tier caption) were **removed**. Accessibility label still states the true tier
  for screen-reader honesty. See memory `feedback_timely_over_honest.md`.
- The estimated position walks back up the route from your stop by ETA-worth of
  travel (≈90s/stop) and interpolates between bracketing stops; it decrements the
  ETA by time since the last refresh so the pin **creeps** toward the stop, and
  glides between fixes. Uses `RouteInfo` we already fetch — no new network calls.
- Camera auto-frames to fit both the bus and the stop on first plot (the user's
  recenter button opts out of further auto-framing).
- Sheet relaid out to the latest design: bigger "Towards …" title, hero eyebrow
  now names the stop ("ARRIVING AT …"), next-two arrivals inline ("then 18 · 24
  min"), "Stop <code> · <dist> away" + crowd-with-label, a black (`contrast`)
  "Notify me before it arrives" button, a clock-glyph Live Activity row, and a
  "Tap a stop to set an arrival alert." route hint. A tier-aware honesty caption
  states whether the pin is live / last-known / estimated.
- Recent QoL polish rolled in: Home chip sort by bus number + wrap-no-truncate,
  Search/Home field de-dup, Stop ETA size 30→22, sheet drag physics
  (`.global` space + flick momentum), status-bar-safe recenter button, and the
  blue user / green stop / dark bus marker icon language.
- App + widget extension build clean (`xcodebuild`, iOS Simulator).

**2026-05-31 — Leyne 3.0 flow-prototype overhaul (iOS): Home · Search · tabs · onboarding:**

> Second pass after an honest gap review — the first pass shipped only the Bus
> view + confidence engine; this brings the *rest* of the navigable flow (per
> `Flow Prototype.html`) into the Leyne 3.0 language. The Disruption / Mid-trip /
> Fare artboards are deliberately out of scope — they live on a separate
> wireframe canvas, not the prototype, and assume a journey planner / fare
> engine the app doesn't have.

- New `SoftStopCard` (+ `MiniBusChip`): the design's stop card — pin tile, name,
  code·road, distance, and a row of confidence-treated next-bus chips.
- **Home** rebuilt: greeting + search bar + live-location row, then **Pinned**
  and **Nearby** sections of StopCards. The standalone Nearby tab folds into
  Home, so the bar is now **Home / Search / Settings**.
- **Search** rebuilt as the design's "Find" surface: tall field, tap-to-fill
  example chips (code/postal/place/bus), auto-detected input, and results split
  into Services + Bus stops with slim pin-tile rows. Real postal/geocode logic
  preserved.
- **Onboarding** restructured to the prototype's 6 steps: Welcome → "Honest
  about your wait" (live/estimated/scheduled) → Location → Notifications → ATT →
  "You're all set" grant summary (reflects the real granted states). Real system
  prompts preserved; consent-gather split from finish (`RootView`).
- **Stop** rebuilt to the minimal prototype layout: a clean header (back · name ·
  code·road · distance), an **ETA / Distance / Bus no.** sort, and arrival cards
  reduced to a neutral service badge + a big confidence-treated ETA. Destination,
  crowd, route and per-bus alerts now live on the Bus view (matching the
  prototype). The **Distance sort is honest** — it uses the live bus GPS position
  (`NextBus` lat/lon → `Service.busLat/busLon`) vs the stop; ghost / no-signal
  buses have no real distance and sort last.
- Fixed Home StopCard chips truncating ("1… 4 m…") — they now **wrap** via a
  `FlowLayout` at intrinsic width, so each service number + ETA reads in full.
- App + widget extension build clean (`xcodebuild`, iOS Simulator).

**2026-05-31 — UX review, cross-platform parity & ads verification (build 14 / 25):**

> Android versionCode bumped 24 → 25: code 24 was already consumed on Play
> Console, so the closed-test upload re-builds under 25 (same 2.3.0 content).

iOS — bus arrival screen UX review (`SoftBusView`):
- Fixed the clipped arrival headline: "Arr" could truncate at large Dynamic
  Type sizes. Arriving now reads "ARRIVING · Now"; real minute counts keep the
  big numeral. Guarded with `lineLimit(1)` + `minimumScaleFactor`.
- Map stop marker + legend now use a location pin (`mappin.fill`). The old bus
  glyph implied a live bus position that the on-screen caption explicitly says
  isn't shared — a direct contradiction.
- Renamed "Following" → "Then"; grouped the notify + Live Activity actions
  under one "Alerts" header so they no longer read as duplicate buttons; pinned
  the Back/Pin bar so it doesn't scroll away on long routes; "Pinned" button
  now reads "Unpin"; removed a "Tap to cancel" VoiceOver instruction.
- Added a notifications-off warning banner on the stop screen, and the next
  arrival now shows inline on Nearby rows (parity with Android).

Android — cross-platform parity + correctness:
- Fixed a wrong-bus bug: when the tracked service had departed, the screen
  silently showed a different bus's ETA under the original number. It now
  shows an honest "no live data" state.
- Bus screen gained the "Live · GPS" / "~ Scheduled" provenance chip, a third
  upcoming arrival, the "Then" label, an "Alerts" group header, and the
  ongoing-tracker card now stays visible (with an Enable prompt) when
  notifications are off.
- Settings gained Sound & Haptics toggles. Search-preview map markers use a
  location pin instead of a bus icon.

Ads — verified production-ready on both platforms (no code changes): real
AdMob app + unit IDs, Google test units gated behind `#if DEBUG` /
`kLyneAdsTest`, UMP → ATT → SDK-init consent ordering enforced, SKAdNetwork
items present. Action item before promoting Android to production: confirm the
Play Data Safety form discloses Advertising ID (the `AD_ID` permission is
declared in the manifest).

App Store **Guideline 2.2** resubmission fixes (prior build 2.2.1/2.2.3 was
rejected as a "pre-release/trial with a limited feature set"):

- **Removed every "beta" label.** The live V2 Settings footer no longer says
  "· beta" (`SoftSettingsView`); the string is also stripped from the dead V1
  `HomeView`/`SettingsView` and the Flutter `soft_settings_screen` /
  `about_screen` / `settings_screen` so it's gone from the binary entirely.
  The explicit "BETA" badge was the most likely rejection trigger.
- **Alight alert is now a real feature, not a stub.** `SoftBusView`'s route-
  timeline alight picker called a `UserDefaults`-only stub with a fake 15-min
  timer; it now arms the actual alert via `AppModel.setActiveAlight(...)`
  (fireAt = 90 s × (stopsToAlight − 2), mirroring V1 `DetailView`) and clears
  it on untap. No partially-implemented feature for a reviewer to find.
- **What's New no longer over-promises.** Removed the "First & last bus" item
  (not surfaced in the V2 screens) from `kChangelog` and Flutter `changelog`.
- **Search filter chips are now real, not decorative (iOS).** `SoftSearchView`
  previously routed all four chips (Postal / Stop ID / Bus # / Place) through
  the same stop-name search — a Guideline 2.2 partial-feature risk. Now:
  **Postal** OneMap-geocodes the 6-digit code and lists bus stops within the
  Settings radius, nearest first (e.g. `120338` → nearby stops); **Bus #**
  searches services and opens the chosen service's origin stop; **Stop ID /
  Place** search stops. Ports the proven V1 `SearchSheet` postal flow
  (`GeocodeService` + `haversine`). This makes the "Search by postal code"
  What's New claim truthful.
- **Live Activity + widget taps now deep-link (iOS).** The Live Activity (lock
  screen / Dynamic Island) set no `widgetURL`, and the app had no `onOpenURL`
  receiver at all — so tapping a live bus (e.g. 184) under the notch just
  foregrounded the app instead of opening that bus, and the Home Screen widget's
  `lyne://stop/<code>` link was silently dropped too. Added a
  `lyne://bus/<stopCode>/<busNo>` URL to the Live Activity (lock screen + all
  Dynamic Island presentations) and an `onOpenURL` handler in `RootView` that
  routes both `bus` and `stop` links through the same `AppModel.open(...)` path a
  notification tap uses (`SoftRoot` then pushes Stop or Bus). The `lyne` scheme
  was already registered in `LeyneInfo.plist`; only the receiver was missing.
- **Live Activity no longer lingers as a stale ghost after arrival (iOS).** On
  arrival the activity ended with `dismissalPolicy: .default`, which keeps an
  *ended* Live Activity on the Lock Screen for up to ~4 h while iOS drops it from
  the Dynamic Island immediately — so an arrived bus showed a stale Lock-Screen
  card (still the previous bus) that was absent from the Dynamic Island. Changed
  to `.immediate` (`AppModel.startLivePolling`) so both surfaces clear together
  after the brief "Bus is here" state.
- **Version bumped** to iOS `2.3.0 (13)` and Flutter `2.3.0+22` (stores reject
  a duplicate of the rejected `(12)` build; also a clean marketing version for
  the 2.0 "Soft" release).

Android quality pass (full-team Android review, 2026-05-30) — brings the
Flutter/Android side to parity with the iOS fixes above:

- **Search filter chips are now real on Android too.** `soft_search_screen.dart`
  routed all four chips (Postal / Stop ID / Bus # / Place) through the same
  `searchStops` call — the identical decorative-chip Guideline 2.2 / Google Play
  "deceptive behavior" risk just fixed on iOS. Now **Postal** OneMap-geocodes the
  6-digit code and lists stops within the Settings radius, **Bus #** searches
  services and opens the chosen service's origin stop, **Stop ID / Place** search
  stops. Mirrors the V1 `SearchScreen` dispatch.
- **Alight alert now fires on Android.** `SoftBusScreen` held the picked stop in
  widget-local `_alightId` and never scheduled anything — the 🔔 chip lit up but
  no notification armed. Now wired to `AppModel.setActiveAlight(...)` via
  `_onAlightChanged` (fireAt = 90 s × (stopsToAlight − 2)), mirroring
  `DetailScreen`; tapping the armed stop again disarms the ride.
- **Route timeline no longer fabricates per-stop ETAs.** Downstream stops showed
  invented clock times (`liveETA + 2 min × stopsAway`); LTA only publishes an ETA
  for the queried stop, so those are gone — the timeline shows position only.
- **Android build/release hardening.** CI now builds the release AAB (was a debug
  APK, which skips the AOT/release code path); Flutter is pinned to `3.44.0`;
  Gradle heap `8G → 4G` (the 8G request risked OOM on ~7G CI runners); and the
  upload keystore moved to a repo-local, gitignored path resolved via
  `rootProject.file()` (was an absolute `/Users/...` path that broke on any other
  machine).
- **Build artifact (Android).** `flutter build appbundle --release` (Flutter
  3.44.0) → `build/app/outputs/bundle/release/app-release.aab` (62 MB),
  versionCode **23** / versionName **2.3.0**, signed with the `upload` key
  (self-signed `CN=Rommel`, SHA-256 `CD:61:…:3B:95`, valid to 2053) — ready for
  Play Console upload. iOS build (13) Archive was submitted to App Store Connect.

Post-review quick-wins (full-team standup, 2026-05-30) — small, verified fixes
landed after the 2.3.0 build above; fold into the next Archive/AAB:

- **What's New now displays on iOS 2.3.0.** `kChangelog` in `AppModel.swift` only
  had a `2.0.0` entry, so the What's New gate silently no-op'd for everyone
  updating to 2.3.0 (`whatsNewVersion` returns nil when `kChangelog[current]` is
  absent). Added an honest `2.3.0` entry (alight heads-up, Live Activity / widget
  deep-link, postal-code search) — all three are features that actually shipped.
- **iOS now honours Dynamic Type.** `Theme.swift` `sans()`/`mono()` used a fixed
  `Font.system(size:)` and ignored the user's text-size setting app-wide. Now
  scaled through `UIFontMetrics.default.scaledValue(for:)` in the single font
  factory, cascading to every call site; the hardcoded 56 pt ETA numeral in
  `SoftBusView.arrivalCard` was bypassing the factory and now routes through
  `t.mono(56)`. (Still verify layout at the largest accessibility sizes.)
- **iOS test host fixed.** `LeyneTests` `TEST_HOST` still pointed at the pre-rename
  `Lyne.app/Lyne`; the app builds as `Leyne.app/Leyne`, so the host app could not
  be injected. Corrected in both Debug and Release test configs (`project.pbxproj`).
- **Android onboarding icon.** The notification-priming step rendered the
  iOS-specific `Icons.phone_iphone`; swapped to the platform-neutral
  `Icons.smartphone` (`onboarding_screen.dart`).

Verified: `xcodebuild … -scheme Leyne` **BUILD SUCCEEDED**; `flutter analyze lib/`
clean. NOT done (and why): the "dead V1" `HomeView.swift` / `SettingsView.swift`
were **not** deleted — they still define live V2 types (`WhatsNewView`,
`NotificationsView`, `StickyCompactBar`, `TitleOffsetKey`), so deletion breaks the
build; dropping the dead `HomeView`/`SettingsView` structs needs a type-extraction
refactor first. The `AdBanner` `#warning` was **not** un-commented — it is paired
to `forceTestUnitForRelease` (currently `false` / App-Store-safe), so un-commenting
would fire a false "ads are ON" alarm; the real guard is a `check-ad-toggle.sh`
pre-Archive grep (still open).

## Unreleased — Leyne 2.0 "Soft" redesign · 2026-05-29

First execution pass of the Leyne 2.0 redesign from the Claude Design
handoff bundle (`~/Downloads/leyne-2-0/`, Soft direction). Both
platforms now carry the new palette and the V2 "Soft" UI is the
default (and only) path on iOS and Android — the original
`leyne.softUI` gate has been retired.

- **New Soft palette.** `ios-native/Leyne/Theme.swift` and
  `lib/theme.dart` updated in place with the warm dark (`#15201C`) /
  warm light (`#F4EFE7`) bg + mint accent
  (`#8EE6C0` dark / `#2D7A5A` light). Property names preserved so
  existing call sites compile against the new values.
- **iOS V2 screens behind `leyne.softUI` flag.** New
  `ios-native/Leyne/V2/` directory containing nine shared primitives
  (ServiceBadge, LabelPill, SortChipRow, IOSGlassPill, SoftTabBar,
  RouteTimeline, MapHandoffToast, SoftPrimitives) and six screens
  (Home / Nearby / Stop / Bus / Search / Settings) wired to real
  `DataStore` arrivals + `LocationManager` + LTA routes. Toggle with
  `defaults write com.leyne.Leyne leyne.softUI -bool true`.
- **MRT line palette.** New `MRTLine` enum + `LyneSignal` namespace
  (Flutter) / cross-mode `mrtNE` + `meBlue` colours (iOS) for transit
  overlays that don't change between dark and light.
- **Pull-to-refresh across the V2 stack (iOS).** New async
  `DataStore.refreshArrivals(stop:)` (always hits the network and is
  awaitable) wired to `.refreshable` on `SoftHomeView`, `SoftStopView`,
  and `SoftBusView`. Stop/Bus also reload route geometry on pull.
- **Onboarding parity + no Skip.** Flutter onboarding drops the `onDone`
  callback and the Skip button to match iOS — every user passes through
  the notification / location / ads priming steps; onboarding completes
  only by reaching the final step (`lib/main.dart`,
  `lib/screens/onboarding_screen.dart`, `OnboardingView.swift`).
- **Notifications default OFF (Flutter bugfix).** `AppModel.load()` was
  reading `lyne.notifications ?? true`, so a fresh install showed the
  toggle ON before `POST_NOTIFICATIONS` was ever granted — a lying
  toggle that fired no alerts. Now defaults to `false` (opt-in), the
  honest "persisted result of the permission flow".
- **UX honesty fixes (iOS).** Home cards suppress the empty "PIN" chip;
  the stop-header `figure.walk` icon (walk minutes were never populated)
  becomes `mappin.and.ellipse`; the master pill reads "Alert all / All
  alerts / N alerts" instead of the misleading "Track all".
- **Audio session fix (iOS).** `Feedback` no longer forces
  `setActive(true)`, which was interrupting background music on launch.
- **Live Activity entry point in V2 (iOS).** `SoftBusView` now shows a
  Start/Stop Live Activity row wired to the existing
  `AppModel.toggleLiveActivity(...)` engine (15 s LTA polling, stops-away,
  auto-end on arrival, relaunch restore — already used by V1
  `DetailView`). The previous comment claiming "ActivityKit isn't wired"
  was stale; the only missing piece was this surface. The row reflects
  live on/off state and is hidden when there's no arriving service or the
  user has disabled Live Activities system-wide, so it never dead-ends.
- **WidgetKit surfaces aligned to the Soft palette (iOS).** Both the Home
  Screen widget (`LeyneStopWidget`) and the Live Activity
  (`LeyneLiveActivity`) had inline palettes left over from the pre-Soft
  theme (bg `#0E0E0A`/`#F7F4ED`, mint `#5EE597`/`#2BAA67`). Repointed every
  token at the current `Theme.swift` Soft values (bg `#15201C`/`#F4EFE7`,
  accent `#8EE6C0`/`#2D7A5A`, solid `liveBg`), nudging `dim`/`faint` alpha
  up for small-text legibility on-glass. Per UX direction: `.continuous`
  corners throughout; `.widgetAccentable` on the semantic elements (arriving
  ETA, mint arriving pill, the pinned `bookmark` glyph, compact/minimal bus
  number) so meaning survives StandBy / Lock-Screen monochrome tint; a
  numeric content-transition on the Live Activity countdown; Small-widget
  stop name bumped 12→13pt. Deferred (P2): swapping the Unicode `→` for an
  SF Symbol arrow.
- **Android V2 parity pass (Flutter).** Closed several iOS↔Android gaps a
  cross-platform UX review surfaced: (1) **pull-to-refresh** on Home / Stop /
  Bus via a new awaitable `DataStore.refreshArrivals(code)` (Home refreshes
  all pins concurrently); (2) Home pin card hides the chip when there's no
  real nickname instead of showing a redundant "PIN" (matches iOS); (3)
  Settings **Notifications** row now pushes the real `NotificationsScreen`,
  and the dead **Routines** section + **Language** row (no destinations, not
  on iOS) were removed; (4) removed the dead "Track in notifications" Live
  Activity card and the no-op AppBar lock button on the Bus screen — the
  Android ongoing-notification equivalent isn't built yet, so no dead
  affordance; (5) the bus map drops the phantom "BUS N" legend entry (LTA
  never shares that coordinate) for the same honest caption iOS uses.
- **Android stop alert controls (Flutter).** Closed the largest parity gap:
  the V2 stop screen now lets you choose which buses alert you, matching iOS
  in capability via Material-native controls. Per-bus **bell** `IconButton`
  on each row + primary card (tracked rows get a `liveBg` tint + left accent
  rule — two non-colour cues), an AppBar **master bell** (alert-all / clear),
  a `SegmentedButton` Soonest/Bus-no. sort, a discovery hint, and a
  `warnBg` banner with an "Enable" action when notifications are globally
  off. The FAB is gone — pinning is now implicit (first bell pins, last
  untap unpins), matching iOS's `pinned ⟺ ≥1 tracked bus` invariant. This
  reuses the existing `toggleTracked` / `setAllTracked` / `isTracked` APIs
  (so it also drives the Home card's tracked subset — by design) plus one
  new `AppModel.rescheduleIfNeeded()` that re-arms the scheduler immediately
  after a toggle. Per UX, the per-bus model was chosen over iOS-style
  independent alerts because both platforms already share the same
  `Pin.tracked` data model — iOS just had the UI wired first.
- **Android bus notify button + ongoing live-tracking notification
  (Flutter).** The bus screen gains a full-width arrival-alert toggle
  (same `toggleTracked` mechanism as the stop bells), closing the last
  notify-button parity gap. And the Android stand-in for the iOS Live
  Activity is now built: a silent, ongoing notification (new low-importance
  `leyne.tracking` channel) that follows one bus's ETA, started from a
  "Track in notifications" card on the bus screen (shown only when
  notifications are enabled, so it never dead-ends). `AppModel.toggleOngoing`
  manages a single tracker; the 1 s tick pushes ETA updates every ~5 s and
  finalises to a dismissable "Arriving now" when the bus arrives; tapping it
  deep-links back to the bus (new `track.<stop>.<bus>` payload). **Known
  limit:** updates run while the app process is alive — a fully background
  tracker needs a native foreground service (not built yet); the `ongoing`
  flag still pins it in the shade until arrival/stop.
- **Post-review hardening (team review fixes).** Ongoing-tracker leak fixed:
  it's now torn down when notifications are disabled/denied and on cold start
  (it was in-memory only, so the OS could otherwise keep showing a stale,
  frozen notification). `_refreshOngoing` finalises after ~15 s of the
  service being absent instead of pinning a frozen ETA forever; starting a
  tracker for a different bus now explicitly replaces the prior one.
  `clearAll`/`cancelAlightAlerts` gained `_initialized` guards (mirroring
  `scheduleArrivalAlerts`) so a pre-init toggle can't crash. iOS: the two
  missed `.widgetAccentable` modifiers (Large widget `bookmark`, service-row
  ETA numeral) added so the arriving signal survives StandBy tinting. The
  stop screen's master bell now reflects all-tracked vs partial honestly, and
  the ongoing-tracking card copy states updates run "while the app is open".
- **iOS-native CI + tests.** Added a third CI job (`ios-native`) that
  `xcodebuild`s the SwiftUI app + LeyneWidgets extension on every push —
  previously the iOS CI job only built the Flutter wrapper, so Swift/widget/
  Live-Activity errors were invisible until Xcode. Added
  `test/ongoing_tracking_test.dart` covering the ongoing-tracker lifecycle
  (activate/replace/disable-clears), `setAllTracked` edge cases, and
  `rescheduleIfNeeded` (Flutter suite now 91 passing).
- **Tests realigned.** Flutter suite green (83 passing): onboarding
  tests follow the 6-step no-Skip flow, the empty-state and settings
  copy match V2, and the notification toggle path mocks the
  permission / local-notification platform channels.
- See `specs/leyne-2.0-plan.md` for the full plan, sequencing, and
  open decisions.

## 2.2.9+21 — Android (closed testing) · 2026-05-27

Code-review polish pass — bugs/correctness + platform-design alignment.

- **RouteProgress no longer crashes on empty `route.stops`.** Defensive
  early-return in `lib/widgets/route_progress.dart` (and iOS sibling
  in `DetailView.swift`) — `int.clamp(0, -1)` was throwing
  `ArgumentError` in the unlikely case where a RouteInfo arrived with
  zero stops (malformed LTA response or bootstrap race). Now renders
  an empty `SizedBox` instead of taking down the screen.
- **`refreshNotificationAuth` no longer flips the toggle on
  `.notDetermined`.** `lib/state/app_model.dart` was treating "the
  system hasn't been asked yet" the same as "user said no", silently
  disabling the user's intent during boot-time prompt races. Now only
  flips off on explicit `.denied` / `.permanentlyDenied`. Mirrors the
  iOS guard.
- **Alight notification identifier uses the stop CODE, not the
  user-facing name.** `lib/services/notifications.dart` was building
  `alight.<busNo>.<stopName>` — names like "Opp Blk 211" contain
  spaces and punctuation that would make the payload awkward to parse
  if it ever became load-bearing for routing. Now uses
  `alight.<busNo>.<stopCode>`. iOS `AppModel.swift` got the same fix.
- **Onboarding Back button works on the final (ATT) step.**
  `lib/screens/onboarding_screen.dart` was leaving `_busy = true`
  after the ATT Continue tap (the caller drives dismissal), trapping
  the user with no Back if `AdConsent.gatherThenStart()` stalled. Now
  matches iOS — Back stays enabled on the final step.
- **On-bus alert card uses a Material `Switch` instead of a
  hand-drawn iOS-style sliding pill.** `lib/screens/detail_screen.dart`
  `_onBusAlertCard` is now a proper Material `Card` + `Switch` row —
  Android chrome on Android, per platform-design memory. iOS keeps
  its `TogglePill`.
- **"BOARD HERE" replaces "YOUR STOP" in iOS RouteProgress.** Both
  platforms now use the same vocabulary for the three trailing badges
  (BUS / BOARD HERE / ALIGHT). iOS DetailView also got a small badge
  for the user's stop, matching Flutter's filled-accent style.
- **Redundant "VIEWING BUS X → Y" heading row removed (iOS).** The
  hero card right below shows the same bus number and destination in
  much larger type — the meta row was duplicate ink.
- **Arrival notification body drops "head down to the stop" when
  `walkMin == 0`.** That suffix assumed "user is at the stop", but
  `walkMin == 0` means "no location fix yet" — read wrong when the
  user was actually elsewhere. Now just shows the stop label in that
  case. Both platforms.

## 2.2.3+12 — iOS (next archive) · 2026-05-26
## 2.2.8+20 — Android (closed testing) · 2026-05-26

Two QoL fixes, both platforms:

- **iOS DetailView top bar no longer paints a stray material band.**
  Removed `.background(t.glassSurface())` from `DetailView.topBar`
  (`DetailView.swift:187`). At scroll-zero with nothing scrolled
  beneath, the static glass material was visible as a rectangle band
  between the safe area and the page below — uncharacteristic of
  iOS-native chrome (system nav bars only paint material when content
  scrolls under them). Buttons now sit cleanly on `t.bg`.
- **Route Progress auto-extends to include the alight stop + adds a
  "Show all N stops" expander.** Previously the focused window was
  capped at `youIndex + 5`, so picking an alight 10 stops past the
  boarding stop was impossible (the picker couldn't reach the stop).
  Now: window auto-extends to `alightIdx + 1` when the user has set
  an alight, AND a bottom expander toggles between focused view and
  full route. Both platforms — `DetailView.swift` `RouteProgress`,
  `lib/widgets/route_progress.dart` (converted to StatefulWidget).

(Previous 2.2.2+11 iOS block content folded into this entry.)

## ~~2.2.2+11 — iOS (next archive) · 2026-05-26~~ (superseded by 2.2.3+12)

Project: `ios-native/Leyne.xcodeproj` — `MARKETING_VERSION = 2.2.2`,
`CURRENT_PROJECT_VERSION = 11` across all 3 targets (Leyne,
LeyneWidgets, LeyneTests).

The iOS-side companion to Android 2.2.7+17. Adds the same two
improvements landed in the Flutter codebase this turn:

- Default-on notifications + onboarding step 3 fires the system
  permission prompt (matches Location's pattern). Boot-time fallback
  in `RootView.task` covers existing users past onboarding so a fresh
  upgrade still gets prompted.
- Tap-to-open deep link: `LeyneAppDelegate.didReceive` broadcasts a
  `leyneOpenStopFromNotification` event with the notification's
  `userInfo`; `RootView.onReceive` reads `stopCode` + `busNo` and
  drills into the bus's DetailView. Alight notifications carry only
  `busNo`; the stopCode is sourced from the persisted `ActiveAlight`
  ride.

## 2.2.7+19 — Android (closed testing) · 2026-05-26

Build: `scripts/build-android-closed-test.sh` →
`build/app/outputs/bundle/release/app-release.aab`

versionCode-only rebumps after Play rejected +17 then +18 with
"Version code N has already been used" — both numbers were already
claimed by prior closed-testing uploads. Source identical to +17/+18.

## 2.2.7+17 — Android (closed testing) · 2026-05-26

Build: `scripts/build-android-closed-test.sh` →
`build/app/outputs/bundle/release/app-release.aab`

- **Notifications now opt-in at first launch.** Default switched to ON
  on both platforms; the onboarding "STAY PRESENT" step (3) now fires
  the system permission prompt directly, same pattern as the
  Location step. No more digging into Settings → Notifications to
  discover the feature.
- **Boot-time fallback** for existing users past onboarding: if the
  system has never asked for `POST_NOTIFICATIONS` and the intent flag
  is ON, the prompt fires once at next app launch. iOS uses the same
  flow via `RootView.task`. Idempotent — the OS only ever shows the
  dialog once.
- **Tap-to-open deep link.** Tapping an arrival or alight notification
  now opens the bus's detail view directly (previously, tapping just
  raised the app to whatever screen was last visible).
  - iOS: `LeyneAppDelegate.userNotificationCenter(didReceive:)` posts
    a `leyneOpenStopFromNotification` event with the userInfo
    (`kind`, `stopCode`, `busNo`); RootView's `.onReceive` calls
    `AppModel.open` to drill in.
  - Flutter: `NotificationsService.onNotificationTapped` parses the
    payload string (`arrival.<stopCode>.<busNo>` or
    `alight.<busNo>.<stopName>`) and pushes `DetailScreen` via the
    global navigator. `getNotificationAppLaunchDetails` replays the
    initial cold-start tap so a launch-from-notification lands too.
- iOS still pending an Archive; Android AAB ready to upload.

## 2.2.6+16 — Android (closed testing) · 2026-05-26

Build: `scripts/build-android-closed-test.sh` →
`build/app/outputs/bundle/release/app-release.aab`

- **Re-enabled exact alarm scheduling — Whatsapp-/SMS-like immediacy.**
  Bus arrival alerts now fire at the intended second, not within
  Android's Doze maintenance window. Previously inexact-only after the
  2.2.5+15 walk-back, which could delay an arrival heads-up by minutes.
- Declared `SCHEDULE_EXACT_ALARM` only (not `USE_EXACT_ALARM`). The
  former is the open-use permission that calendar reminders, ride-share
  pickup alerts, and transit apps commonly request; the latter is the
  alarm-clock/calendar-only restricted permission that Play rejected
  in 2.2.4+14.
- Auto-granted on Android 12–13. On Android 14+ the user is prompted
  once via the system's "Alarms & reminders" Settings screen at the
  moment Arrival alerts are toggled on. Denial degrades gracefully to
  inexact scheduling — the notification still fires, just batched.
- New `NotificationsService.requestExactAlarmAuthorization()` +
  internal `_scheduleMode()` resolver that picks exact vs inexact per
  the current permission state for both arrival and alight alerts.

## 2.2.5+15 — Android (closed testing) · 2026-05-26

Build: `scripts/build-android-closed-test.sh` →
`build/app/outputs/bundle/release/app-release.aab`

- **Removed `USE_EXACT_ALARM` and `SCHEDULE_EXACT_ALARM` permissions.**
  Play Console rejected 2.2.4+14 during release review — Google
  restricts these permissions to apps whose core functionality is
  calendar or alarm clock. Leyne is neither.
- Switched `flutter_local_notifications` `zonedSchedule` calls (both
  arrival and alight alerts) from `AndroidScheduleMode.exactAllow`
  `WhileIdle` to `inexactAllowWhileIdle`. Notifications still fire at
  approximately the right moment; the system may batch within its
  Doze maintenance window. Acceptable trade-off for a ~1-minute-out
  bus arrival heads-up.
- No code or UX changes beyond the permission + schedule-mode swap.

## 2.2.4+14 — Android (closed testing) · 2026-05-26

Build: `scripts/build-android-closed-test.sh` →
`build/app/outputs/bundle/release/app-release.aab`

- **On-bus alight alert wired end-to-end on both platforms.** Picking
  an alight stop in the route progress now arms a real notification
  that fires ~2 stops before the bus reaches the chosen stop. Previous
  builds only displayed the "Buzz me 2 stops before…" UI without
  actually scheduling anything.
- `ActiveAlight` model + persisted single-ride state in AppModel
  (Flutter) and equivalent `@AppStorage`-backed state on iOS native.
  One active ride at a time; persists across app restarts.
- `NotificationsService.scheduleAlightAlert` (Flutter) +
  `NotificationsManager.scheduleAlightAlert` (iOS) — fire 60 s before
  predicted alight time using a one-shot scheduled notification.
- Predicted fire time computed from RouteInfo: 90 s × max(0,
  stopsToAlight − 2) from now, using `busIndex` or `youIndex` as the
  starting reference. MVP estimate, accurate within a stop or two.
- Added the "Buzz me 2 stops before X" card to Flutter DetailScreen
  (previously iOS-only). Tappable to dismiss when active.

## 2.2.3+13 — Android (closed testing) · 2026-05-26

Build: `scripts/build-android-closed-test.sh` →
`build/app/outputs/bundle/release/app-release.aab`

- **Replaced in-app SnackBar arrival alerts with real native Android
  notifications.** Switched to `flutter_local_notifications` +
  `timezone` + `permission_handler` for system-level scheduling.
  Notifications fire ~60 s before each tracked bus's `arrivalDate` and
  appear on the lock screen / as a heads-up banner regardless of app
  lifecycle, matching the iOS-native behaviour.
- New `lib/services/notifications.dart` (`NotificationsService`):
  one-time tz database + Android channel init, per-service identifier
  (`arrival.<stopCode>.<busNo>`), idempotent reschedule that cancels
  orphans, `Importance.high` channel + `timeSensitive` interruption
  level on iOS targets.
- `AppModel.setNotificationsEnabled` is now `async` and requests the
  Android 13+ `POST_NOTIFICATIONS` runtime permission; the toggle
  snaps back to off if denied. Tick loop re-arms scheduled alerts
  every 10 s against live LTA data.
- `NotificationsScreen` dropped the "background alerts are on the
  roadmap" disclaimer; gained a denied-permission warning + **Open
  Android Settings** shortcut when iOS blocks the permission.
- `AndroidManifest.xml`: added `POST_NOTIFICATIONS`,
  `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`, `RECEIVE_BOOT_COMPLETED`;
  declared the `ScheduledNotificationReceiver` + boot receiver so
  scheduled alarms survive a reboot.

## 2.2.2+12 — Android (closed testing) · 2026-05-26

Build: `scripts/build-android-closed-test.sh` →
`build/app/outputs/bundle/release/app-release.aab`

- Swapped AdMob banner to Google's reserved test unit
  (`ca-app-pub-3940256099942544/6300978111`) so closed-testing tappers
  can't trigger invalid-traffic flags against the real leyne0000 unit.
  Toggle controlled by `--dart-define=LYNE_ADS_TEST=true` baked into
  the closed-test build script.
- Added `scripts/build-android-closed-test.sh` +
  `scripts/build-android-prod.sh` so each build path is a single
  command with the right flag.
- Added `BUILDING.md` at repo root documenting the dev/test/prod ad
  matrix for both platforms.

## 2.2.1+11 — Android · 2026-05-26 (re-ads-enabled)

Build: `flutter build appbundle --release` (legacy, before the scripts
existed). Served the real leyne0000 banner unit — superseded by
2.2.2+12 above because closed testers risked policy violations
on real-ad taps.

- Re-enabled ads after the AdMob suspension was resolved on
  `rommelsim@gmail.com`.
- Updated AdMob app + unit IDs back to leyne0000 (app ID
  `ca-app-pub-5864511655536507~5685985257`, banner unit
  `ca-app-pub-5864511655536507/6513878972`).

## 2.2.0+10 — Android · pre-2026-05-26

Bumped for release. See git commit `c7db613` for the diff.

## Pending — iOS (not yet archived)

Tracking unreleased iOS work currently in `ios-native/` working tree.
This section moves into a real version block on next Archive.

- **Real device notifications** — `UNUserNotificationCenter` schedules
  one-shot local notifications ~60 s before each tracked bus's
  `arrivalDate`. Time-sensitive interruption level on iOS 15+, threads
  by stop code, denied-permission warning + Open Settings shortcut in
  Settings ▸ Notifications. `LeyneAppDelegate` adopted as
  `UNUserNotificationCenterDelegate` so foreground alerts banner.
- **iOS-native edge-swipe-back** — `EdgeSwipeBack` ViewModifier in
  `RootView.swift` claims drags that start within 24 pt of the leading
  edge, drags DetailView / DetailPager 1:1 with the finger, commits on
  80 pt of travel or a flick. Coexists with DetailPager's TabView page
  swipes (those start further inboard).
- **iOS push animation switched to spring** — `RootView.swift`
  `.animation(.spring(response: 0.42, dampingFraction: 0.86), value:
  m.openCard)`, matching UIKit's `UINavigationController` curve. Pure
  slide transition (no opacity fade) on DetailView for crisper dismiss.
- **iOS TestFlight ad toggle** — `AdConfig.forceTestUnitForRelease` +
  paired `#warning` line in `AdBanner.swift`. Default `false` (App
  Store-safe). Flip both to `true` before TestFlight Archives; flip
  back before App Store-bound Archives. See BUILDING.md.
