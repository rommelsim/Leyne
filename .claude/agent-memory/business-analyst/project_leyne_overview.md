---
name: project-leyne-overview
description: Core product facts — what Leyne is, platforms, data source, feature set, and current development state
metadata:
  type: project
---

Leyne is a free Singapore transit arrival-times app (bus + MRT). Data source: LTA DataMall (Bus Arrival v3, Bus Stops, Bus Services, Bus Routes, Train Service Alerts). Two shipping platforms: Flutter/Android (closed testing on Play, v2.2.8+20) and iOS-native SwiftUI (App Store, most recent archive v2.2.3+12). `ios-native/` is the live iOS target; `lib/` is the Flutter Android codebase and V2 behavioral reference.

**Monetization:** AdMob banner ads (interstitial not used). Free to user; ad-supported. ATT/UMP consent handled in onboarding. AdMob publisher `ca-app-pub-5864511655536507` (leyne0000@gmail.com). See [[project-accounts]].

**Why:** Solo developer (Rommel). iOS leads; Android ports from iOS feature-for-feature.

**Current state (2026-05-30, post-session update):** iOS V2 flag gate is removed — `RootView.swift` unconditionally mounts `SoftRoot` (no `leyne.softUI` guard in the production launch path). Android `main.dart` routes directly to `SoftRoot` (Flutter). Both platforms ship V2 as the default. The `leyne.softUI` argument still appears in the Xcode debug scheme only, which is correct.

**Session 2026-05-30 delivered:**
- iOS Live Activity CTA wired in SoftBusView (was commented out stub). Entry point is now live, with guard for `areActivitiesEnabled`.
- iOS widgets aligned to Soft brand palette.
- Android pull-to-refresh added to SoftStopScreen and SoftBusScreen.
- Android per-bus arrival-alert bells added to SoftStopScreen.
- Android "notify" button added to SoftBusScreen.
- Android ongoing "live tracking" notification added (`toggleOngoing`, `_ongoingKey`, `_refreshOngoing` in AppModel). Updates driven by the in-process per-second ticker — NOT a foreground service. Updates freeze if the OS kills the app process.
- Several dead/no-op affordances removed (honesty fixes, both platforms).

**Core feature inventory (grounded in code, 2026-05-30):**

| Feature | iOS Native | Flutter Android |
|---|---|---|
| Pinned stops (save, rename, reorder) | Yes | Yes |
| Per-pin bus filter (track subset of routes) | Yes | Yes |
| Primary bus designation per pin | Yes | Yes |
| Live arrival times (LTA DataMall) | Yes | Yes |
| Live/Scheduled provenance chip | Yes — `liveStatusChip`, `liveSchedTag`, `~ Scheduled` in BusView | Yes (partial — no chip on Android stop screen row) |
| Nearby stops (location-based) | Yes | Yes |
| Search by Stop ID / Postal code / Bus # / Place | Yes | Yes |
| Bus detail view (ETA hero, following 2, route timeline, map) | Yes | Yes |
| Alight alert (route timeline → notification) | Yes | Yes |
| Arrival alert per tracked bus | Yes | Yes |
| Per-bus notify button in BusView | Yes | Yes (new this session) |
| Deep-link from notification into stop/bus detail | Yes | Yes |
| MRT/LRT disruption alerts on Home | Yes | Yes (partial) |
| Home Screen widget | Yes — LeyneStopWidget | No (iOS-only) |
| Live Activity (Lock Screen + Dynamic Island) | Yes — entry point now live in SoftBusView | No (iOS-only) |
| Ongoing "live tracking" notification (Android analog) | N/A | Yes (new this session — process-alive limitation) |
| Core Spotlight indexing | Yes | No (iOS-only) |
| Settings | Yes | Yes |
| What's New screen | Yes | Yes |
| Onboarding (6 steps) | Yes | Yes |

**Remaining deferred work (from code + kChangelog gap):**
- First/last bus labels — referenced in kChangelog 2.0.0 "First & last bus" entry but NO implementation exists in `ios-native/` or `lib/`. This is an unfulfilled What's New promise.
- Android ongoing notification is process-alive only — no foreground service; updates stop when app is backgrounded by OS.
- Analytics SDK not wired (no Firebase, no Mixpanel).
- l10n — English-only in practice.
- Alight alert wiring in iOS is UserDefaults-direct (Phase 3 comment in SoftBusView); not yet through NotificationsManager.
- AddStopSheet in iOS is dead code (m.showAdd never flips).

**How to apply:** Frame all analysis against a solo-developer constraint. Avoid recommending work that assumes a team. The first/last bus gap is a launch blocker because it is promised in What's New copy.
