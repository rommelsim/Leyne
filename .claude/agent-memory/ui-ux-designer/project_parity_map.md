---
name: project-parity-map
description: Cross-platform iOS ↔ Flutter/Android V2 parity map — per-flow status, idiom-bleed violations, and open punch list (audited 2026-05-29)
metadata:
  type: project
---

Full audit of ios-native/Leyne/V2/ against lib/screens/v2/ as of 2026-05-29.
Governing rule: feature/flow parity required; platform-native implementation
correct; brand-layer (cards, chips, warm palette) intentionally shared.

## Flow Parity Status

### Onboarding
PARITY: Both platforms have 6 steps (Hero → Pin → Narrow → Notify → Location → Ads)
in the same order with identical copy and no Skip. Both fire the same callbacks
at the same steps (step 3 notifications, step 4 location, step 5 ATT/tracking).
Both use Back-only nav (hidden at step 0), identical dot indicators, and identical
CTA logic including the single-shot guard on the final step.
GAP 1: iOS steps 4 and 5 carry footnote callouts (`OnboardingView.OnbStep.footnote`
rendered as an info-circle row beneath the subtitle). Flutter has no footnote
slot — those two steps show the marketing copy but drop the contextual hint
("You'll see the standard iOS location prompt next." / "Next, iOS asks whether
Leyne can track."). Minor copy parity gap; not a flow gap.
GAP 2: Flutter transition is a directional slide (respects Back direction via
`_direction` variable). iOS uses `.opacity.combined(with:.move(edge:.trailing))`
— always slides left regardless of Back direction. Low-impact visual only.

### Home / Pinned Stops
PARITY: Both platforms show a greeting eyebrow + "Your stops" title, pinned-stop
cards sorted by next arrival (up to 3 services visible), walk-time chip, overflow
link, quiet state, empty state with Nearby/Search CTAs, and MRT alert cards with
tap-to-dismiss.
GAP 3 (FLOW): iOS pin card shows the nickname chip ONLY when a non-empty nickname
that differs from the stop name exists. Flutter always shows a chip — it falls
back to "PIN" when no nickname is set. Every card on Android shows a "PIN" chip
even when no nickname has been given, adding noise on every card. Behavioural
parity broken: iOS is correct, Flutter has the old behaviour.
GAP 4 (FLOW): Home search button. iOS renders a `plus` icon in a circle
(suggests "add a stop"). Flutter renders `IconButton.filledTonal(Icons.search_rounded)`
(Material search). These represent the SAME action (open Search) but with
different iconography — a minor discoverability inconsistency, not idiom bleed.
GAP 5 (FLOW): MRT alert tap-to-dismiss. iOS wraps the card in a SwiftUI
`Button` with `.easeOut` animation + haptic. Flutter uses `InkWell` + `setState`
— dismiss is instant, no fade animation, no haptic. Low-impact but the
animated removal is noticeably different between platforms.
GAP 6 (PARITY): Pull-to-refresh on Home. iOS has `.refreshable` on the
ScrollView (all pins refreshed). Flutter has no `RefreshIndicator` on the
home `ListView`. Missing feature on Android.

### Stop Detail
PARITY: Both platforms show stop header (eyebrow, stop name, road name), arrival
list, bus rows tappable to bus detail. Both show live/sched tag per bus row.
GAP 7 (FLOW — CRITICAL): Alert / tracking controls are completely different in
structure. iOS: per-bus bell toggle on every row (44pt tap) + master "Alert all /
All alerts / N alerts" GlassPillButton in the top action row. Sort chips (Soonest /
Bus no.) present. Track hint text appears above the list.
Flutter: FAB for pin/unpin only — no bell per row, no per-bus tracking, no master
alert pill, no sort chips. The FAB toggles the entire stop pin (`togglePin`) but
does NOT toggle individual bus tracking. This is a P0 flow parity gap: the core
"narrow to buses you ride" flow (onboarding Step 2) is absent on Android's V2 stop screen.
GAP 8 (FLOW): Flutter stop detail has a DISTINCT LAYOUT pattern — `_primaryCard`
elevated hero for the first service, then an `_otherBuses` section with "See all N"
truncation + a separate full-list route push. iOS has a flat sorted list for all
services with sort chips. These produce different mental models for the same data.
The Flutter hero+others layout is unique to that platform and not reflected in iOS
at all, making the conceptual model diverge.
GAP 9 (FLOW): Pull-to-refresh: iOS has `.refreshable`. Flutter Stop has no
`RefreshIndicator`. Missing on Android.
GAP 10 (FLOW): AppBar on Flutter stop shows "Stop {code}" as the title. iOS
has no navigation bar — uses GlassPillButton Back + Bell pill. This is the
platform-correct difference (Material AppBar vs Liquid Glass pills) — NOT a parity
gap, just correct native chrome.

### Bus Detail
PARITY: Both platforms show: arrival hero with large ETA, "Following" next buses,
notify/alert button, live map section with stop pin, route timeline (tap-to-alight).
Both have a Live Activity concept (iOS = real ActivityKit CTA; Android = deferred
"Track in notifications" card). Both show a live/sched provenance chip.
GAP 11 (FLOW): Live Activity. iOS `liveActivityCTA` is fully wired to
`m.toggleLiveActivity` and shown only when `ActivityAuthorizationInfo().areActivitiesEnabled`.
Flutter `_liveActivityCard` is a static non-tappable display card (onPressed is empty
comment). The card looks tappable (has a `chevron_right`) but does nothing. This is
a dead-button trust violation on Android — same pattern that was fixed on iOS
(where liveActivityCTA was previously a no-op stub). Should be hidden until wired,
not shown as a tappable row that doesn't respond.
GAP 12 (FLOW): Flutter bus screen AppBar title is a generic "Bus tracking" string.
iOS bus view header shows the service number as a 40pt bold hero with the stop
name in the back pill. The Flutter header section shows "Stop {code}" eyebrow +
stop name — it doesn't lead with the service number at all. The mental framing
is reversed: iOS = "I am tracking Bus 88 from this stop"; Flutter = "I am at stop
X watching bus 88". Both contain the same info but the hierarchy differs.
GAP 13 (MAP LEGEND): Android map legend in `_mapLegend` shows "BUS {svc}" as a
legend entry with a bus icon. However `_route?.busCoord` is still always nil
(DataStore.route hard-codes busCoord: nil — same state as iOS before the fix),
so the BUS marker can never appear on the map. iOS correctly removed the BUS
legend entry after its 2026-05-29 fix. Android still shows a "BUS N" legend item
for a marker that will never render. Dishonest empty state — mirrors the iOS P
resolved bug, now re-opened on Android.
GAP 14 (FLOW): Route timeline per-stop ETA. Android's `_timelineStops` computes
`etaMin` for stops in the `next` state using `(baseMin + (idx - yIdx) * 2)` —
fabricated per-stop minute estimates. iOS explicitly deleted this (`estimatedMinutes`
removed in 2026-05-29 SoftBusView pass). Android is back to showing invented
per-stop clock times.
GAP 15 (FLOW): Pull-to-refresh on Bus detail. iOS has `.refreshable`. Flutter has
no `RefreshIndicator`. Missing on Android.

### Nearby
PARITY: Both show "Stops within 500m" eyebrow, "Near you" title, three sort
chips (Distance / Arrival / Service), stop rows with WalkTile + name + distance
+ stop code. Both respect location-denied/not-determined empty states. Both
show up to 20 results.
GAP 16 (FEATURE): Flutter nearby row shows first live arrival inline in the
subtitle row (`first.no + ETA big+small` in accent). iOS nearby row does not —
shows only distance + stop code in the dim caption. Android shows more info per
row; iOS rows are quieter. Mild parity difference, Android is richer here.
GAP 17 (PARITY): Pull-to-refresh: not present on either platform for Nearby.
Consistent absence — not a parity gap. But it's a usability gap on both.

### Search
PARITY: Both platforms present a full-screen search overlay (not a tab body)
with a text input, 4 filter chips (Postal / Stop ID / Bus # / Place), and result
rows showing stop name + "Stop {code} · {road}". Both autofocus the field on
appear. Both filters currently fall through to name search (cosmetic filter chips).
DIFFERENCE (NATIVE, CORRECT): iOS uses a custom pill `TextField` + "Cancel"
`Button` because `.searchable` isn't wired to the Search tab yet. Flutter uses
a `Material TextField` with `borderRadius: 28` and `Icons.arrow_back` as the
prefix — effectively a Material search bar. Both are custom implementations but
the Flutter one looks materially closer to a standard Material 3 search bar.
This is acceptable native-divergence, not bleed.
GAP 18 (FLOW): Flutter search "Cancel/back" is an `Icons.arrow_back` inside
the search field prefixIcon — same as the system back button on Android, which
is correct. iOS uses a separate text "Cancel" button outside the search field.
Both are platform-appropriate patterns. Not a gap.

### Settings
PARITY: Both platforms show Personalize section (Notifications, Appearance,
24-hour time), Feedback section (Sound, Haptics on iOS), version footer.
Appearance control uses platform-native segmented picker on both (`Picker(.segmented)`
on iOS, `SegmentedButton` on Android — both are the correct native control).
GAP 19 (FLOW): Android Settings has a "Routines" section at the top
(Morning commute, Evening commute, Add routine) with all rows wired to empty
`onTap: () {}` callbacks — all dead rows. iOS Settings has no Routines section
at all. This is two parity problems in one: (a) Android has an extra section
iOS lacks, and (b) every row in it is dead. Should be removed or hidden behind a
feature flag until wired.
GAP 20 (FLOW): Android "Notifications" row in settings taps to `onTap: () {}`
— empty callback, dead row. iOS NavigationLink properly pushes `NotificationsView`.
The Notifications screen exists in Flutter (`NotificationsScreen`) but is never
navigated to from Settings. Critical: this is the path to enable/disable bus
alerts, the app's primary value prop.
GAP 21 (FLOW): Android "Language" row present in Settings (taps to empty `() {}`).
iOS removed the Language row entirely because no destination existed (resolved in
prior pass). Android kept the dead row. Should be removed to match iOS.
GAP 22 (PARITY): SoftToggle on iOS is 38×22pt — below the 44pt iOS minimum. On
Android, `SoftToggle` is 44×26pt — closer to spec. Android is actually more correct
on toggle size here. iOS toggle should be replaced with native `Toggle` (which
renders a UISwitch at correct size with free a11y). See [[project-leyne-design-system]].

## Idiom-Bleed Violations

BLEED 1: `SoftToggle` on iOS (`ios-native/Leyne/V2/SoftPrimitives.swift:28`).
A custom 38×22pt hand-drawn toggle exists on BOTH platforms (Swift + Dart).
On Android (Flutter) this is the custom brand toggle — acceptable since Material
Switch is not required. On iOS specifically the native `UISwitch` / SwiftUI `Toggle`
is expected; replacing a UISwitch with a smaller custom pill is a regression in
accessibility (no system switch trait, no a11y value), size (38pt < 44pt minimum),
and system-tint behavior. iOS should use native `Toggle`; Android may keep `SoftToggle`
since Material doesn't mandate the native Switch appearance.

BLEED 2: `SortChipRow` for Stop sort in `SoftStopView.swift` — present on iOS,
absent on Flutter. This is not bleed per se (the iOS component is Soft-brand chips,
not Android idiom), but the PRESENCE is iOS-only, creating a flow difference (GAP 7).

BLEED 3: `GlassPillButton` on iOS for Back + master Bell vs Material `AppBar` +
`FloatingActionButton.extended` on Android for Back + Pin. These are correct
platform-native differences. NOT bleed. Listed here only to clarify they are exempt.

BLEED 4 (MINOR): Flutter `SoftSearchScreen` search field uses `Material(borderRadius: 28)`
wrapping a `TextField` with `Icons.arrow_back` prefix. This closely mimics a Material
3 SearchBar, which is correct. However the custom-drawn pill is not the native
`SearchBar` widget (M3 `SearchBar` / `SearchAnchor`). Low-impact — still looks native
enough on Android. No iOS bleed.

## Consistency Wins
- Onboarding: near-perfect step/copy/CTA parity across both platforms.
- Home card layout: stop name, service badge, ETA, overflow link, quiet state —
  pixel-spec matched between platforms.
- WalkTile: identical spec on both (44pt square, liveBg, accent number, dim "min").
- Nearby: same three sort chips, same empty messages, same 20-row cap.
- Bus detail: arrival card layout (ETA hero, Following, notify button) — closely aligned.
- Route timeline: same tap-to-alight interaction, same state enum (past/here/board/next).
- Theme tokens: both platforms share `t.bg`, `t.surface`, `t.accent`, `t.liveBg` by name.
- AppBar title on Android stop/bus views uses correct Material pattern.
- SegmentedButton/Picker for Appearance: both platforms use the native segmented control — no bleed.

## Prioritized Punch List

### P0 — Flow/Parity Bugs (blocks the core value prop)
1. GAP 7: Flutter SoftStopScreen missing per-bus bell + master alert pill.
   The "narrow to buses you ride" promise is onboarding Step 2; V2 Android doesn't
   deliver it. Fix: replicate iOS `busRow` bell button + `GlassPillButton`-equivalent
   FAB-replacement (or AppBar action) for track-all. Substantial work.
2. GAP 20: Flutter Settings Notifications row is a dead `onTap: () {}`.
   One-liner fix: navigate to `NotificationsScreen`. Critical path to alert management.
3. GAP 11: Flutter Bus Screen `_liveActivityCard` is a tappable no-op (chevron_right
   visible, onPressed empty). Either wire to Android ongoing notification or hide the
   card until wired. One-liner hide: wrap in `if false` or remove until wired.
4. GAP 14: Flutter route timeline invents per-stop ETA minutes. iOS removed this
   in the 2026-05-29 pass. Delete `etaMin` computation in `_SoftBusScreenState._timelineStops`.
   One-liner data-model change.
5. GAP 13: Flutter bus map legend shows "BUS N" entry for a marker that can never
   appear (busCoord always nil). Remove the `item(Icons.directions_bus, …, 'BUS N')` line.
   One-liner.

### P1 — Flow/Parity Bugs (noticeable but not blocking)
6. GAP 6 / GAP 9 / GAP 15: Pull-to-refresh missing on Android Home, Stop detail,
   Bus detail. iOS has `.refreshable` on all three. Wrap each Flutter `ListView` in
   a `RefreshIndicator` that calls the appropriate `DataStore.shared.refreshArrivals`.
7. GAP 19 + GAP 21: Android Settings dead rows (Routines section: 3 rows; Language row).
   Remove until wired. These actively erode trust. One-liner removal each.
8. GAP 3: Flutter pin card shows "PIN" chip when no nickname set. Change the Flutter
   `_PinCard` `chip` logic to return empty string (matching iOS) and hide the chip
   widget when empty. One-liner.
9. GAP 8: Flutter stop detail uses hero-card-first layout vs iOS flat sorted list.
   Consider aligning to a single model — the hero card is fine but it means the first
   bus always appears prominent regardless of whether the user tracks it. Moderate effort.

### P2 — Idiom Violations
10. BLEED 1 / GAP 22: iOS `SoftToggle` → replace with native SwiftUI `Toggle` styled
    with `toggleStyle`. Gets correct UISwitch size, a11y trait, and system tint for free.
    Settings is the only place it's used in V2. One-liner swap, moderate styling work.

### P3 — Polish
11. GAP 1: Flutter onboarding missing footnote hints on steps 4–5. Add a footnote
    widget to `_OnbStep` and the Flutter step definitions.
12. GAP 2: iOS onboarding Back transition always slides from right regardless of direction.
    Add a `_direction` state variable and reverse the `.move` edge for Back.
13. GAP 4: Home search button iconography (plus circle on iOS vs search icon on Android).
    Consider aligning to a `plus` on both since the action is "add a stop" not "search".
14. GAP 5: MRT alert dismiss animation missing on Android. Add an `AnimatedSize` or
    `AnimatedOpacity` wrapper to the alert list items on Flutter.
15. GAP 12: Flutter bus screen header leads with stop name rather than bus number.
    Restructure `_compactHeader` to promote the service number as the headline, matching
    iOS's v3 header (`Text(svc)` at 40pt bold).
16. GAP 16: iOS nearby row doesn't show first live arrival inline. Add the first-arrival
    accent label to the iOS nearby row caption (already done on Android).

**Why:** Gaps 1–5 map to features explicitly promised in onboarding (PIN, NARROW,
STAY PRESENT). Dead rows and invented data erode trust immediately. Pull-to-refresh
is a hygiene expectation on both platforms.
**How to apply:** Use this map in any roadmap discussion. Re-verify each gap
against code before acting — active development may have closed items.
