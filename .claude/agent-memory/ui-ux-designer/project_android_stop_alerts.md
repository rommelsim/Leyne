---
name: project-android-stop-alerts
description: Android (Flutter) stop-screen alert interaction spec — model decision, Material component spec, copy, build plan. Closes GAP 7 (P0) from the parity map.
metadata:
  type: project
---

## Decision: Reuse Pin.tracked + global notifications. Do NOT build per-bus-independent alerts.

**Why:** The Flutter model already has all the primitives needed:
- `toggleTracked(code, busNo, allNos)` — per-bus toggle; pins the stop on first bell tap, unpins on last
- `setAllTracked(code, allNos, tracked)` — master arm/clear
- `isTracked(code, busNo)` — per-row state read
- `notificationsEnabled` — global gate
- `scheduleArrivalAlerts(pins, cards)` — fires for all tracked buses across all pins; respects `Pin.tracked`

The iOS "independent bell per bus" model is a UI affordance that maps 1:1 onto this exact Flutter model — iOS's bells write to `tracked`, Android's checkboxes/bells write to `tracked`. The semantics are identical. Engineering cost of adopting iOS's model: zero new state, zero new APIs. The only work is wiring existing AppModel methods into the stop screen UI.

The global `notificationsEnabled` flag is a feature, not a limitation — it matches the Android notification permission model (one POST_NOTIFICATIONS grant covers all of Leyne's alerts). Design around it honestly.

**What it implies for AppModel/notifications:** No new state or APIs needed. All methods are present in Flutter AppModel as of 2026-05-29. `scheduleArrivalAlerts` already filters by `Pin.tracked`. The only required model change is a `rescheduleIfEnabled` helper that wraps the `if notificationsEnabled { scheduleArrivalAlerts(...) }` pattern from `_onTick` — to be called after any `toggleTracked` / `setAllTracked` call from the stop screen.

---

## Interaction Spec

### Layout changes to SoftStopScreen

**AppBar actions:** Add one `IconButton` in the `AppBar.actions` slot:
- Icon: `Icons.notifications_active` when `isPinned && notificationsEnabled`
- Icon: `Icons.notifications_outlined` in all other states (not pinned, or pinned but notif off)
- This is the master bell — it mirrors iOS's GlassPillButton but as a Material AppBar action icon (correct platform idiom for Android secondary actions on a detail screen)
- Tapping it calls `setAllTracked(code, allNos, tracked: !isPinned)` + reschedule
- Accessibility label: "Alerting for N buses at this stop. Tap to stop." when active / "Alert me for every bus at this stop" when inactive

**Per-row bell (both _primaryCard and _busRow):**
- Add a trailing `IconButton` inside each row, RIGHT of the ETA text
- Icon: `Icons.notifications_active_rounded` (filled, `t.accent` colour) when tracked
- Icon: `Icons.notifications_none_rounded` (outline, `t.dim` colour) when not tracked
- Size: 48dp minimum tap target — use `IconButton` which pads to 48dp automatically in Material 3
- Tapping calls `toggleTracked(code, busNo, allNos)` + reschedule
- Accessibility label: "Alerting for bus N. Tap to stop." / "Alert me about bus N"

**Tracked row highlight:** When `isTracked` is true for a row, add a left-side colored bar:
- A `Container` with `width: 3, color: t.accent` positioned as a leading decoration inside the row's `Stack` or use a `DecoratedBox` with `border: Border(left: BorderSide(color: t.accent, width: 3))`
- Row background: `t.liveBg` (same as iOS `tracked` state)
- Do NOT rely on color alone — the accent bar is the non-color signal (accessibility: don't signal with color only)

**Track hint:** Below the stop header, above the bus list, when arrivals are loaded:
- A single-line hint row: `Icons.notifications_outlined` icon (12dp, `t.accent`) + `Text("Tap the bell on a bus to be alerted ~1 min before it arrives.", style: t.mono(11, color: t.dim))`
- Disappear this row once any bus is tracked at this stop (i.e. `isPinned` is true) — the hint is for the zero state only

**FAB change:** The current `FloatingActionButton.extended` with pin/unpin is REMOVED. Pinning is now a side effect of tapping any bell (first bell tap = pin + track that bus). Unpinning happens automatically when the last bell is untoggled. The concept "pin a stop" merges with "alert me for a bus" — same as iOS where pin and track are unified. This matches the existing model invariant (pinned ⟺ ≥1 tracked bus).

If product wants an explicit "unpin this stop" escape hatch visible on screen, surface it as a text button in the AppBar overflow menu (`Icons.more_vert` → "Remove from home") — but this is a P2 polish concern, not needed for parity.

### States and copy

**Zero state (not pinned, no bells active):**
- AppBar bell icon: `Icons.notifications_outlined` (dim)
- All row bells: outline icon, dim
- Hint row visible: "Tap the bell on a bus to be alerted ~1 min before it arrives."
- No FAB

**Some state (pinned, some buses tracked, notif ON):**
- AppBar bell icon: `Icons.notifications_active` (accent colour)
- Tracked rows: accent bar + `t.liveBg` background + filled bell icon
- Untracked rows: no tint + outline bell
- Hint row hidden
- No FAB

**All state (pinned, tracked == null, notif ON):**
- AppBar bell icon: `Icons.notifications_active` (accent colour)
- All rows: accent bar + `t.liveBg` + filled bell
- Hint row hidden

**Notifications OFF (global toggle is false):**
- When user taps any bell and `notificationsEnabled == false`:
  - Show a `SnackBar` (Material-native, bottom of screen): "Turn on notifications in Settings to get arrival alerts."
  - Action button on SnackBar: "Settings" → navigates to `NotificationsScreen` (GAP 20 fix is a prerequisite)
  - The bell still toggles visually (the `Pin.tracked` state updates) — the user's intent is recorded; alerts will fire once they enable notifications. This is honest and non-blocking.
  - Alternatively (stronger signal): show a `MaterialBanner` pinned below the AppBar if `isPinned && !notificationsEnabled` — "Notifications off. Alerts won't fire." with an "Enable" action. Dismiss on tap to Settings. This persistent warning is closer to iOS behavior and avoids the "bell lit but nothing fires" confusion.
  - Recommendation: Use the `MaterialBanner` approach. It stays visible as long as the contradiction exists, unlike a `SnackBar` which auto-dismisses.

**Sort chips (GAP 8 related):** Add a `SegmentedButton<StopSort>` row between the hint and the bus list — "Soonest" and "Bus no." segments. This is a Material 3 `SegmentedButton` (two-segment, single-select). It drives a local `_sort` state var that reorders the `state.services` list before rendering. This closes the sort-chip parity gap partially noted in GAP 7.

### Component summary

| Concern | Material component | Spec |
|---|---|---|
| Master bell | `IconButton` in `AppBar.actions` | 48dp, outline/filled by isPinned |
| Per-row bell (primary card) | `IconButton` trailing inside row | 48dp, outline/filled by isTracked |
| Per-row bell (other buses) | `IconButton` trailing inside `_busRow` | same |
| Tracked row tint | `DecoratedBox` left border + `t.liveBg` bg | 3dp left accent bar |
| Hint text | `Row(Icon + Text)` above bus list | Mono 11pt, hidden once pinned |
| Notifications-off warning | `MaterialBanner` below AppBar | "Enable" action → NotificationsScreen |
| Sort | `SegmentedButton<StopSort>` | "Soonest" / "Bus no." |

---

## Honest Labels (Material copy)

- Master bell icon (off state) — no label (icon only in AppBar, self-evident)
- Master bell icon (on state) — no label (icon only in AppBar)
- Per-row bell off: accessibility label "Alert me about bus N"
- Per-row bell on: accessibility label "Alerting for bus N. Tap to stop."
- MaterialBanner copy: "Notifications off — arrival alerts won't fire."
- MaterialBanner action: "Enable"
- SnackBar fallback: "Turn on notifications to receive arrival alerts." + action "Settings"
- Hint row: "Tap the bell on a bus to get alerted ~1 min before it arrives."

Do NOT use "Track" — it's ambiguous (track on a map?). iOS resolved this same copy problem; the Flutter copy should match iOS's resolution: bells = arrival alerts, not tracking.

---

## Build Plan

**Step 1 — Wire GAP 20 first (prerequisite, 10 min):**
In `SoftSettingsScreen` (or wherever the Settings Notifications row is), change `onTap: () {}` to navigate to `NotificationsScreen`. Without this, the "Enable" action in the MaterialBanner dead-ends. One-liner.

**Step 2 — Add `rescheduleIfNeeded()` helper to AppModel (15 min):**
```dart
Future<void> rescheduleIfNeeded() async {
  if (!_notificationsEnabled) return;
  await NotificationsService.shared.scheduleArrivalAlerts(
    pins: _pins, cards: allPinnedCards);
}
```
Call this after any `toggleTracked` / `setAllTracked` call that originates from the stop screen. Keeps alert schedule in sync with per-bus changes mid-session without waiting for the 10s tick.

**Step 3 — Remove FAB from SoftStopScreen (5 min):**
Delete the `floatingActionButton` property from the `Scaffold`. Add the `AppBar.actions` master bell `IconButton` wired to `setAllTracked` + `rescheduleIfNeeded`.

**Step 4 — Add per-row bell to `_busRow` (30 min):**
Add an `IconButton` as the last widget in the `_busRow` Row (after the ETA Text). Read `isTracked` from `AppModel.shared` inside `ListenableBuilder`. On tap: `toggleTracked` then `rescheduleIfNeeded`. Apply `t.liveBg` background and 3dp left accent bar via `DecoratedBox` when tracked.

**Step 5 — Apply same bell + tint to `_primaryCard` (20 min):**
The primary card is a standalone `Container`. Add an `IconButton` in the card's top-right area (inside the existing `Row` that has `ServiceBadge`, column, and `chevron_right` — replace the chevron with a two-icon row: bell + chevron, or position bell as a separate overlay). The tracked tint on the primary card background can change `liveBg` opacity: use `t.liveBg` as the card color when tracked, `t.liveBg` (existing) when not — these are the same token, so the primary card already looks "tracked" state-neutral. To make the distinction clear, change the card background to `t.surface` when not tracked, keeping `t.liveBg` only when tracked. Confirm with product before changing existing color.

**Step 6 — Add hint row + MaterialBanner (20 min):**
Insert hint row in `_header` output (or as first child of the ListView after the header). Show `MaterialBanner` via `ScaffoldMessenger` when `isPinned && !notificationsEnabled` — use a StatefulWidget `didChangeDependencies` or `ListenableBuilder` to toggle the banner.

**Step 7 — Add SegmentedButton sort (20 min):**
Add `_sort` state var (`StopSort.arrival` default). Insert `SegmentedButton` between hint and `_otherBuses`. Sort `state.services` before passing to `_primaryCard` (first element) and `_otherBuses`. Note: sort chip changes the logical "first" service, which means the hero primary card now shows the soonest bus, not just index 0. Verify this is desired before landing.

**Home-card impact (critical):**
Steps 3–5 change `Pin.tracked` via `toggleTracked` / `setAllTracked`. The home card already reads `liveServices(code, tracked: pin.tracked ?? [])` and filters by `tracked`. Any change to `tracked` on the stop screen will immediately change what shows on the home card for that stop. This is CORRECT and INTENDED behavior — same as iOS. Document this for QA: tapping a bell on the stop screen removes or adds that bus from the home card's visible services row.

**Regression risk:** `toggleTracked` already contains the "untrack last bus = unpin" logic. If a user un-bells every bus at a stop, the stop disappears from Home. This is the correct behavior (same as iOS) but may surprise users who expected "pinned = always on Home". The hint row + MaterialBanner together make this implicit contract visible.

**Why:** Closing GAP 7 is the P0 parity gap. The "narrow to buses you ride" promise is made in onboarding Step 2; the Android V2 stop screen currently cannot deliver it at all.
**How to apply:** Use this spec as the implementation contract. Steps are ordered by dependency. Step 1 is a prerequisite for the notifications warning UX to be complete. Steps 2–6 are the core alert interaction. Step 7 is a quality-of-life addition that also partially addresses GAP 8.

See also: [[project-parity-map]] GAP 7, GAP 8, GAP 20.
