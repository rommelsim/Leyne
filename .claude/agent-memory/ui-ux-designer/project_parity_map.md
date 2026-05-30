---
name: project-parity-map
description: Cross-platform iOS ↔ Flutter/Android V2 parity map — per-flow status, idiom-bleed violations, and open punch list (audited 2026-05-31, supersedes 2026-05-29 version)
metadata:
  type: project
---

Full audit of ios-native/Leyne/V2/ against lib/screens/v2/ as of 2026-05-31.
Governing rule: feature/flow parity required; platform-native implementation
correct; brand-layer (cards, chips, warm palette) intentionally shared.

## Resolved since last audit (2026-05-29 → 2026-05-31)

- GAP 3 RESOLVED: Flutter pin card chip logic now matches iOS exactly — empty when no nickname, empty when nickname == stop name.
- GAP 6 RESOLVED: Flutter Home has RefreshIndicator.
- GAP 7 RESOLVED: Flutter SoftStopScreen now has per-bus bell (_bell), master bell (_masterBell in AppBar), sort chips (Soonest/Bus no.), track hint row, and notifications-off banner. The hero+others layout is retained but all alert controls are present.
- GAP 9 RESOLVED: Flutter Stop detail has RefreshIndicator.
- GAP 11 RESOLVED: Flutter SoftBusScreen _ongoingCard is fully wired to AppModel.toggleOngoing — no longer a dead tap.
- GAP 13 RESOLVED: Flutter bus map legend no longer shows a BUS entry (matches iOS).
- GAP 14 RESOLVED: Flutter _timelineStops no longer passes etaMin to SoftRouteStop — no fabricated per-stop clock times.
- GAP 15 RESOLVED: Flutter Bus detail has RefreshIndicator.
- GAP 19 RESOLVED: Android V2 Settings Routines section is gone.
- GAP 20 RESOLVED: Android V2 Settings Notifications row navigates to NotificationsScreen.
- GAP 21 RESOLVED: Android V2 Settings Language row is absent (matches iOS V2 omission).

## Current Open Gaps

### Stop Detail screen
GAP A [PARITY]: Flutter SoftStopScreen hint row only shown when !isPinned
(lib/screens/v2/soft_stop_screen.dart:96). iOS SoftStopView shows trackHint
unconditionally whenever arrivals are loaded (SoftStopView.swift:116).
After the first bell tap the stop becomes pinned and the hint disappears on
Android. iOS keeps the hint visible throughout. Minor but creates slightly
different discoverability.

GAP B [PARITY]: Flutter SoftStopScreen notifications-off banner shown when
isPinned && !notificationsEnabled (stop_screen.dart:80). iOS SoftStopView has
no equivalent notifications-off banner. iOS-side gap: user can pin a stop with
notifications off and get no contextual warning. Android is more complete here.

GAP C [COPY]: Flutter stop master bell tooltip uses "Clear all alerts" (stop_screen.dart:141)
while iOS master pill label cycles "Alert all" / "N alerts" / "All alerts"
(SoftStopView.swift:43-46). Functional equivalence but label vocabulary differs.
Also: Flutter bell icon uses notifications_active/notifications_none; iOS uses
bell.fill/bell. Platform-appropriate difference, not bleed — but Android bell
tooltip "Clear all alerts" could be more explicit (iOS says "Alerting for N buses").

GAP D [PARITY/LAYOUT]: Flutter SoftStopScreen uses a "primary card" hero for
the first sorted bus + "Other buses" subsection for the rest (stop_screen.dart:102-104).
iOS SoftStopView renders all buses in a flat uniform list (SoftStopView.swift:151-161).
These produce different mental models: on Android the first sorted bus is
visually promoted regardless of tracking state; on iOS all buses are equal weight.
The primary card on Android has an extra "load · Then Xmin" summary row
(stop_screen.dart:308) that iOS bus rows in the stop view do not show.

GAP E [COPY]: Flutter SoftStopScreen primary card renders arrival as "Arriving now"
or "In N min" (stop_screen.dart:289-293). iOS SoftStopView bus row ETA column
shows `eta.big + eta.small` joined (SoftStopView.swift:218). Natural language
"In 4 min" vs mono "4 min" — not a usability blocker but copy register differs.

### Bus Detail screen
GAP F [COPY/PARITY]: Flutter SoftBusScreen uses "Next arrival" + "Following"
eyebrow labels in the arrival card (soft_bus_screen.dart:212-214).
iOS SoftBusView uses "Arrives in" + "Then" eyebrows (SoftBusView.swift:159-187).
"Following" was explicitly relabeled to "Then" on iOS in the 2026-05-29 pass to
avoid confusion with "the bus you're following". Android reverted/retained the
old label. Should align to "Then".

GAP G [PARITY — FEATURE]: iOS SoftBusView shows a THIRD arrival in the "Then"
row when available (SoftBusView.swift:139-198 — thirdDate). Flutter SoftBusScreen
only shows following (one bus after next), not a third. iOS shows "Next · Then
14min · 28min"; Android shows "Following 14min" only. Data model has thirdDate on
both platforms (models.dart:75); Flutter just doesn't render it.

GAP H [PARITY — FEATURE]: iOS SoftBusView shows a `liveStatusChip` in the
arrival card showing "Live · GPS" (green dot) or "~ Scheduled" (clock icon)
based on Service.monitored (SoftBusView.swift:211-233). Flutter SoftBusScreen
arrival card has no provenance chip. The field exists in the Flutter data model
(models.dart:69) but is not displayed. User has no way to know if the ETA is
GPS-accurate or estimated on Android.

GAP I [PARITY — FEATURE]: iOS SoftBusView "Alerts" section groups the notify
button and Live Activity CTA under a single "ALERTS" eyebrow header
(SoftBusView.swift:286-292), making both actions feel like two flavours of one
intent. Flutter SoftBusScreen has the notify button and ongoing card as siblings
in the list with no grouping header — the relationship between them is unclear.

GAP J [PARITY]: iOS SoftBusView has an "alertsSection" block — the notify
button and live-activity CTA are always in a group. Flutter shows the _ongoingCard
only when `live != null && m.notificationsEnabled` (soft_bus_screen.dart:127-130),
which means it disappears when notifications are off — opposite of what a user
needs to see when deciding whether to enable them.

### Home screen
GAP K [COPY]: iOS home header + button uses a `plus` circle icon
(SoftHomeView.swift:69). Android uses `Icons.search_rounded` in a
`IconButton.filledTonal` (soft_home_screen.dart:118). Same action (open Search),
different icons. "Plus" reads as "add a stop"; "search" reads as "find something".
The plus is more semantically accurate for the empty-state CTA context.

GAP L [PARITY]: MRT alert dismiss: iOS has `.easeOut(duration: 0.2)` animation
on removal (SoftHomeView.swift:125). Flutter has instant setState dismiss (no
animation). Minor polish gap.

### Settings screen
GAP M [PARITY — FEATURE]: iOS SoftSettingsView has a "Feedback" section with
Sound and Haptics toggles (SoftSettingsView.swift:51-64). Flutter SoftSettingsScreen
has no Feedback section at all — no Sound or Haptics controls. iOS shows two
extra settings rows Android does not have. Android has no sound/haptic control
surface in V2 settings.

GAP N [PARITY — FEATURE]: iOS Settings (V1 SettingsView.swift, not V2 SoftSettingsView)
has Language and Search Radius rows in Personalize (SettingsView.swift:122-133).
Flutter settings_screen.dart also has these. However, iOS V2 SoftSettingsView
omits Language and Search Radius, while the V1 SettingsView (still used)
retains them. This creates an internal iOS V1/V2 settings divergence, not an
iOS/Android cross-platform divergence — but worth noting that Android V2
(SoftSettingsScreen) also omits these rows, consistent with iOS V2.

### Onboarding
GAP O [COPY/POLISH]: iOS OnboardingView has footnote callouts on steps 4 and 5
(OnboardingView.swift:47-50 — info-circle row with platform context hint).
Flutter OnboardingScreen has no footnote slot. Both steps show the marketing
copy but drop "You'll see the standard iOS location prompt next." / "Next, iOS
asks whether Leyne can track." These are platform-specific context notes; their
absence on Android is arguably correct since the prompts look different anyway.
Minor.

GAP P [POLISH]: iOS onboarding Back transition always slides from trailing
regardless of direction (uses `.move(edge:.trailing)` — OnboardingView.swift:85).
Flutter correctly reverses slide direction for Back (uses `_direction` variable).
iOS should match Flutter here — sliding right to go back is the standard gesture
direction.

### Nearby screen
GAP Q [PARITY]: Flutter SoftNearbyScreen nearby row shows first live arrival
inline in the subtitle (first.no + ETA in accent — soft_nearby_screen.dart:153-159).
iOS SoftNearbyView nearby row shows only distance + stop code (SoftNearbyView.swift:105).
Android is more informative here; iOS rows are quieter.

### Navigation / shell
GAP R [PARITY — IDIOM]: iOS SoftRoot uses native iOS 26 TabView with Liquid Glass
floating tab bar. The Search tab uses `.role(.search)` which renders as a
detached search circle in the Liquid Glass bar (SoftRoot.swift:94). Android
SoftRoot uses a Navigator + AnimatedSwitcher for tab switching with a custom
SoftBottomBar (Material NavigationBar). Both are idiomatically correct for their
platform. Noting for completeness: not a gap.

## Idiom-Bleed Check (current state)

BLEED 1 (ACTIVE): `SoftToggle` on iOS (SoftPrimitives.swift:28) — custom 38×22pt
hand-drawn toggle replaces UISwitch. 38pt height < 44pt iOS minimum. No system
accessibility trait (no UISwitch role). Settings is the only place this appears in
V2. Should be replaced with native SwiftUI `Toggle` styled to match visual spec.

BLEED 2 (ACTIVE): iOS SortChipRow is a custom pill-chip row (SortChipRow.swift).
Android uses the same custom SortChipRow (soft_components.dart:79). The iOS
platform-native alternative would be a `Picker(.segmented)` or
`UISegmentedControl`. However given that these chips are brand-language (Soft
spec) and the app custom-draws them on both platforms intentionally, this is a
deliberate brand decision, not unintentional bleed. Low risk.

BLEED 3 (NOT BLEED): GlassPillButton (iOS) vs Material AppBar + IconButton
(Android) for back/bell navigation. Correct native divergence.

## Consistency Wins (current state)
- Onboarding: near-perfect step/copy/CTA parity (only footnote and Back animation differ).
- Home: pin card layout, service rows, overflow link, quiet state, empty state, MRT alerts — all matched.
- Nearby: three sort chips, same empty messages, WalkTile, 20-row cap — matched.
- Stop: bell icons, sort chips (Soonest/Bus no.), track hint, per-bus toggle, master bell — all matched as of 2026-05-31.
- Bus: arrival hero, notify button, map legend (STOP/YOU only), route timeline tap-to-alight — matched.
- Route timeline: states (past/here/board/next/alight), connector colors, tap behavior — matched.
- Theme tokens: shared naming convention across platforms.
- Appearance picker: Picker(.segmented) / SegmentedButton — both native, no bleed.
- RefreshIndicator / .refreshable: all three main screens present on both platforms.

## Prioritized Punch List (2026-05-31)

### P0 — Feature/Experience gaps that directly affect core value prop
1. GAP H: Flutter bus screen missing live/scheduled provenance chip.
   The field is in the model. Add a chip to the arrival card matching iOS
   liveStatusChip. One widget addition.
2. GAP G: Flutter bus screen shows only 1 following bus; iOS shows 2 ("Then 14min · 28min").
   Add thirdDate rendering to Flutter arrival card. One Text widget addition.
3. GAP M: Flutter Settings V2 has no Sound/Haptics controls.
   iOS v2 Settings has a whole Feedback section. Add toggleRows to Flutter
   SoftSettingsScreen. Low effort, significant parity gap.

### P1 — Noticeable parity gaps
4. GAP F: "Following" label → should be "Then" (matches iOS, avoids ambiguity).
   One string change in soft_bus_screen.dart:214.
5. GAP D (layout): Flutter stop primary-card-hero vs iOS flat list creates
   different mental models. Consider whether to unify or accept as deliberate.
6. GAP I/J: Flutter bus screen missing "Alerts" grouping header + incorrect
   visibility rule for ongoing card. Add Eyebrow("Alerts") and show ongoing
   card regardless of notificationsEnabled (let the card explain the off state).
7. GAP Q: iOS nearby rows don't show first live arrival. Add first-arrival
   accent label to iOS SoftNearbyView row caption.
8. GAP K: Home header icon — plus vs search. Align to plus on both platforms.

### P2 — Idiom violations
9. BLEED 1: iOS SoftToggle → replace with native SwiftUI Toggle. Settings only.

### P3 — Polish
10. GAP L: MRT alert dismiss animation missing on Android. Wrap in AnimatedSize.
11. GAP A: Flutter hint row visibility (hide after pinning vs always visible on iOS). Align.
12. GAP B: iOS stop screen missing notifications-off banner. Add to iOS SoftStopView.
13. GAP P: iOS onboarding Back always slides trailing → add _direction inversion.
14. GAP O: Flutter onboarding missing footnote hints on steps 4-5.

**Why:** P0 items directly affect the "stop reaching for your phone" promise
(provenance chip tells user if ETA is trustworthy; third arrival helps planning).
P1 items create divergent mental models for the same data. Bleed-1 affects
accessibility on iOS.
**How to apply:** Verify against code before acting — this audit is a snapshot.
