---
name: project-gaps-opportunities
description: Business gaps and opportunities identified — monetization, retention, onboarding, feature gaps. Updated 2026-05-30.
metadata:
  type: project
---

Assessment last updated: 2026-05-30. Solo-developer constraint applies — recommendations sized for one person.

## CLOSED This Session (2026-05-30)

### Priority 1 — V2 Default UI [CLOSED]
V2 is now the unconditional default on both platforms. `RootView.swift` mounts `SoftRoot` directly (no flag guard in production path). Android `main.dart` routes to `SoftRoot` directly. The flag exists only in the Xcode debug scheme. Ship blocker is removed.

### Priority 2 — Live Activity Entry Point [CLOSED]
`liveActivityCTA` is now a live, functional `@ViewBuilder` in `SoftBusView.swift`. It guards on `areActivitiesEnabled` (honest: hidden when system has Live Activities disabled) and wires to `AppModel.toggleLiveActivity`. Entry point was the gap; underlying ActivityKit engine already existed. REQ-02 (Option A, manual CTA) is now implemented.

### Android Feature Parity Gaps [SUBSTANTIALLY CLOSED]
Pull-to-refresh, per-bus arrival-alert bells, notify button in BusScreen, and ongoing live-tracking notification are all now present in the Flutter Android codebase. Android is near-parity with iOS for the core tracking loop.

---

## OPEN / ACTIVE Gaps

### Gap 1 — First/Last Bus (Launch Blocker — What's New promise)

The `kChangelog["2.0.0"]` entry explicitly promises "First & last bus — each service now shows its first and last bus for the day." No implementation exists anywhere in `ios-native/` or `lib/`. The LTA Bus Services API does carry WD_FirstBus/WD_LastBus/SAT_FirstBus/SAT_LastBus/SUN_FirstBus/SUN_LastBus fields. This feature MUST ship before V2 is released, otherwise the What's New screen shown on update contains an outright false claim.

Business impact: User trust erosion if a prominently-advertised What's New feature is absent. Likely to generate 1-star reviews specifically calling out the missing feature.

### Gap 2 — Android Ongoing Notification Limitation (Quality Risk)

The ongoing live-tracking notification on Android (`toggleOngoing` / `_refreshOngoing`) is driven by the in-process per-second ticker in AppModel. If the Android OS terminates the app process (backgrounded beyond its process-lifetime budget), the ETA in the notification freezes — users see a stale number until they reopen the app. A true background tracker needs a native Android Foreground Service with WorkManager. See REQ-06 below.

### Gap 3 — Onboarding Analytics (Unmeasured Funnel)

No analytics SDK is wired. Step-by-step onboarding completion rate, ATT grant/deny rate, and retention are all invisible. Without this, it is impossible to know where users abandon or what optimizations to prioritize. This does not block launch but is a significant post-launch blind spot.

### Gap 4 — Widget Discoverability (Retention Lever)

No in-app prompt exists to guide users to add the Home Screen widget after their first pin. Widget-addicted users have higher retention in transit categories. One-time prompt after first pin (24h delay) is the recommended trigger.

### Gap 5 — Monetization Ceiling

Banner-only AdMob. Interstitial on cold launch is the highest-ROI next step (~1 implementation day). Rewarded ad tied to Live Activity session extension is a natural future fit.

---

## Priority Order (Updated)

| Priority | Item | Status |
|---|---|---|
| P0 — Launch Blocker | First/last bus feature (promised in What's New) | Open |
| P0 — Launch Risk | Android ongoing notification limitation documented | Shipped with caveat |
| P1 | Analytics SDK integration | Open |
| P2 | Widget discoverability prompt | Open |
| P3 | Interstitial ad on cold launch | Open |
| P4 | Android foreground service for background tracking | Fast-follow post-launch |

Related: [[project-leyne-overview]], [[project-value-prop]], [[project-open-requirements]]
