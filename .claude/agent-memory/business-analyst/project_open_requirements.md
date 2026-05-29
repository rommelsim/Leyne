---
name: project-open-requirements
description: Requirements that must be defined before specific build tasks proceed — tracked as open questions needing answers
metadata:
  type: project
---

Last updated: 2026-05-30. Reflects session 2026-05-30 progress.

## CLOSED Requirements

### REQ-01: V2 Default Flag Removal [CLOSED — 2026-05-30]
Both platforms now ship V2 as the default. iOS: `RootView.swift` unconditionally mounts `SoftRoot`. Android: `main.dart` routes to `SoftRoot`. Xcode debug scheme retains the `-leyne.softUI 1` launch argument for dev use only — that is correct and does not affect the App Store build.

### REQ-02: Live Activity In-App Entry Point [CLOSED — 2026-05-30]
Option A (manual CTA, recommended) is now implemented. `liveActivityCTA` in `SoftBusView.swift` is a functional `@ViewBuilder` that guards on `areActivitiesEnabled` and wires to `AppModel.toggleLiveActivity`. The entry point was the gap; the underlying ActivityKit engine already existed.

---

## OPEN Requirements

### REQ-03: Widget Discoverability Prompt

**Decision needed:** Should the app prompt users to add the Home Screen widget, and if so, when?

Proposed trigger: 24h after the user's first pin is saved, if no widget has been configured (approximated by checking App Group — if the widget has never been read, the app can infer no widget is active).

**Acceptance criteria:**
- Given a user has set at least one pin AND has not been shown the widget prompt before, When 24 hours have elapsed since the first pin was set, Then on next app open, a one-time modal or banner explains the Home Screen widget and how to add it.
- Given the prompt has been shown once, It is never shown again (regardless of whether the user adds the widget).

### REQ-04: Analytics Event Schema (Unblocks funnel measurement)

**Decision needed:** Which analytics SDK, and minimum viable event set.

Proposed minimum events:
- `app_open` (cold start)
- `onboarding_step_viewed(step: 0–5)`
- `onboarding_completed`
- `att_granted` / `att_denied` / `att_restricted`
- `stop_pinned(stop_code)` / `stop_unpinned`
- `arrival_alert_toggled(on/off)`

**Acceptance criteria:**
- Given a user completes onboarding, All 6 step events + onboarding_completed are logged in order.
- Given the ATT prompt is shown and answered, att_granted or att_denied is logged within the same session.
- No PII (stop_code is not PII; bus numbers are not PII).

### REQ-05: First/Last Bus Feature [LAUNCH BLOCKER]

The `kChangelog["2.0.0"]` entry (both iOS `AppModel.swift` and Android `lib/data/changelog.dart`) explicitly promises:
- "Each service now shows its first and last bus for the day — with a heads-up when the last one has already left."

No implementation exists in `ios-native/` or `lib/`. The LTA Bus Services API (`BusServices`) provides the timing fields by day-of-week (WD/SAT/SUN). **This feature MUST be present before V2 ships as the default release.**

**Acceptance criteria:**
- Given any bus service card is shown in StopView or BusView, When the service has timing data from LTA BusServices, Then the first bus time and last bus time for the current day-of-week are displayed.
- Given the last bus has already departed for the day, When the service card is shown, Then a distinct warning state is shown (e.g., "Last bus has left") so the user knows not to wait.
- Given a service has no timing data (edge case), Then the field is omitted rather than showing a blank or zero.

### REQ-06: Android Ongoing Notification — Foreground Service Decision

**Decision needed:** Is the current process-alive ongoing notification acceptable for V2 launch, or does it require a native Android Foreground Service before ship?

**Context:** The current implementation drives ETA updates from AppModel's in-process per-second ticker. When the Android OS terminates the app process, ETA in the notification freezes. A Foreground Service (using WorkManager or a native Android plugin) would keep updates running even when backgrounded, matching iOS Live Activity behavior.

**Option A — Ship as-is with user-facing honesty copy:** The notification UI copy can be "Follow Bus X from your status bar" (which it already says). No explicit promise of background updates. Risk: users who background the app and later glance at the notification see a stale ETA and may be confused or miss their bus. The UI does not currently warn about this limitation.

**Option B — Add foreground service before launch (recommended if P0 quality bar):** Requires a native Android implementation. Medium effort for a solo dev; estimate 2–3 days.

**Option C — Add caveat copy to the ongoing card (mitigation for Option A):** Add a subtitle like "Updates while app is open." Low effort, sets honest expectations.

**Recommended decision:** Option C for V2 launch (honest framing, low effort), Option B as fast-follow in a 2.0.1 patch before wide release.

**Acceptance criteria (Option C):**
- Given the ongoing notification card is displayed in SoftBusScreen, Then a subtitle or tooltip reads "Updates while the app is open" (or equivalent honest framing).
- Given the app is backgrounded while an ongoing notification is active, When the user returns to the app and the ongoing is still keyed, Then the ETA resumes updating.

Related: [[project-leyne-overview]], [[project-gaps-opportunities]]
