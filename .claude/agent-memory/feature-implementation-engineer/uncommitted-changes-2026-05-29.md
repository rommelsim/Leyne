---
name: uncommitted-changes-2026-05-29
description: What the current working-tree changes (as of 2026-05-29) are implementing across iOS and Flutter.
metadata:
  type: project
---

## Summary of in-progress changes

Six iOS native files and two Flutter files are modified. All changes are polish/correctness; no new features behind a flag.

### ios-native/Leyne/DataStore.swift — new `refreshArrivals(stop:) async`

Added a deliberate-user pull path alongside the existing fire-and-forget `ensureArrivals`. Key differences:
- Awaitable (so SwiftUI `.refreshable` keeps its spinner until data lands).
- Bypasses the freshness window AND the in-flight guard — a user-initiated pull always hits the network.
- On error, only overwrites the state if the current state is `.loading` or `nil` (doesn't clobber a stale-but-valid `.loaded` state from a retried pull).

### ios-native/Leyne/Feedback.swift — audio session fix

Removed the explicit `setActive(true)` call. The root cause was that activating the shared AVAudioSession explicitly — even under `.ambient + .mixWithOthers` — was interrupting background music on app launch. Letting `AVAudioEngine.start()` activate the session on demand (which honours the category) fixes the regression. Also adds `.mode: .default` for correct category overload.

### ios-native/Leyne/OnboardingView.swift — comment only

Updated the comment above the top bar from "back / skip" to "back only (no skip)" — reflects the design decision to remove Skip (skip was removed in a prior commit; comment lagged).

### ios-native/Leyne/V2/SoftHomeView.swift — two changes

1. Pull-to-refresh on the Home scroll view: `.refreshable { for pin in m.pins { await ds.refreshArrivals(stop: pin.code) } }`. Refreshes all pinned stops in order, sequentially.
2. `pinChipLabel` now returns `""` instead of `"PIN"` when the stop has no real nickname. `headerRow` already gates on `!pinChipLabel.isEmpty`, so the chip simply disappears. "PIN" was noise on every card.

### ios-native/Leyne/V2/SoftStopView.swift — two changes

1. Pull-to-refresh on the stop scroll view: `.refreshable { await ds.refreshArrivals(stop: stopCode) }`.
2. New `trackAllLabel` computed property: replaces the static string `"Tracking N"` / `"Track all"` with intent-accurate copy — `"Alert all"` (CTA when nothing armed), `"All alerts"` (when every service armed), or `"N alerts"` / `"1 alert"` (partial). Accessibility labels updated to match.
3. `figure.walk` icon in stop header replaced with `mappin.and.ellipse` — walk icon implied a walk-time number that was never populated; map pin is honest about what the context line actually states (a location, not a duration).

### ios-native/Leyne/V2/SoftBusView.swift — three changes

1. Pull-to-refresh: `await ds.refreshArrivals(stop: stopCode)` + `loadRoute()` — refreshes both arrivals and route geometry.
2. `figure.walk` → `mappin.and.ellipse` in header context line (same rationale as SoftStopView).
3. Map annotation `anchor: .bottom` added to `MapStopMarker` — lifts the teardrop's body above the coordinate point so the stop pin doesn't cover the user-location dot when the user is standing at the stop.

### lib/main.dart — remove `onDone` param from OnboardingScreen call

`OnboardingScreen` no longer takes an `onDone` callback. The parameter was removed from the widget signature (see onboarding_screen.dart below); the call site in `main.dart` drops the named argument.

### lib/screens/onboarding_screen.dart — remove Skip button

Removes the `onDone: VoidCallback` required field and the "Skip" `TextButton` from the top bar. Onboarding now only exits by completing the final step (ATT/ads priming). Comment block updated to reflect no-skip design. A back-navigation guard comment is updated to note that without Skip, a stalled consent flow "would trap the user" (Back on the final step still works — the guard comment explains why Back must keep working even after the final Continue is tapped).

## Coherence assessment

**Coherent.** All changes fall in two logical clusters:
1. Pull-to-refresh surface: DataStore adds the async awaitable path; all three V2 scroll views wire it. The Home view sequentially refreshes all pins; Stop and Bus refresh their single stop. No race or inconsistency.
2. UX copy/icon honesty: "PIN" chip suppression, "Alert"/"alerts" rename, `mappin` vs `figure.walk`, and the Flutter onboarding skip removal are all the same design directive — don't surface affordances or labels that don't match what the app actually does.

**Completeness:** Complete for their scope. The alight alert in `SoftBusView.scheduleAlight` is still stubbed to raw UserDefaults (noted with "Phase 3 wires this to NotificationsManager.scheduleAlightAlert") — that's pre-existing debt, not introduced by these changes.

Related: [[architecture-ios-native]], [[parity-gaps-ios-flutter]]
