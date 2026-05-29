---
name: project-leyne-overview
description: Core product facts — what Leyne is, platforms, data source, feature set, and current development state
metadata:
  type: project
---

Leyne is a free Singapore transit arrival-times app (bus + MRT). Data source: LTA DataMall (Bus Arrival v3, Bus Stops, Bus Services, Bus Routes, Train Service Alerts). Two shipping platforms: Flutter/Android (closed testing on Play, v2.2.8+20) and iOS-native SwiftUI (App Store, most recent archive v2.2.3+12). `ios-native/` is the live iOS target; `lib/` is the Flutter Android codebase and V2 behavioral reference.

**Monetization:** AdMob banner ads (interstitial not used). Free to user; ad-supported. ATT/UMP consent handled in onboarding. AdMob publisher `ca-app-pub-5864511655536507` (leyne0000@gmail.com). See [[project-accounts]].

**Why:** Solo developer (Rommel). iOS leads; Android ports from iOS feature-for-feature.

**Current state (2026-05-29):** Leyne V2 "Soft" redesign execution complete — all V2 screens built in `ios-native/Leyne/V2/` (behind `leyne.softUI` flag) and mirrored in `lib/screens/v2/`. V2 is NOT the default shipping UI yet; flag must be removed / defaulted to true before next release.

**Core feature inventory (grounded in code, 2026-05-29):**

| Feature | iOS Native | Flutter Android |
|---|---|---|
| Pinned stops (save, rename, reorder) | Yes — Pin struct, AppModel.pins, HomeView | Yes |
| Per-pin bus filter (track subset of routes) | Yes — Pin.tracked, m.hiddenSet | Yes |
| Primary bus designation per pin | Yes — Pin.primary | Yes |
| Live arrival times (LTA DataMall) | Yes — DataStore, LTAService | Yes |
| Live/Scheduled provenance chip | Yes — Service.monitored, liveStatusChip | Yes |
| Nearby stops (location-based, sort by distance/arrival/service) | Yes — NearbyView, SoftNearbyView | Yes |
| Search by Stop ID / Postal code / Bus # / Place | Yes — SoftSearchView, SearchLogic, GeocodeService | Yes |
| Bus detail view (ETA hero, following 2 arrivals, route timeline, map) | Yes — SoftBusView, RouteTimeline | Yes |
| Alight alert (on-bus: tap stop in route timeline → notification N stops out) | Yes — alightId, scheduleAlight | Yes |
| Arrival alert ("buzz 2 min before") per tracked bus at pinned stop | Yes — NotificationsManager, toggleTracked | Yes |
| Deep-link from notification tap into stop/bus detail | Yes — SoftRoot openCard observation | Yes |
| MRT/LRT disruption alerts on Home screen | Yes — TrainAlert, DataStore.trainAlerts | Yes (partial) |
| Home Screen widget (Small/Medium/Large — next bus for 1-2 pinned stops) | Yes — LeyneStopWidget | No (iOS-only) |
| Live Activity (Lock Screen + Dynamic Island — ETA countdown) | Yes — LeyneLiveActivity, LeyneActivityAttributes | No (iOS-only) |
| Core Spotlight indexing of pinned stops | Yes — Spotlight.swift | No (iOS-only) |
| Settings (appearance, language, notifications, search radius, 24h, sound, haptic) | Yes — SettingsView | Yes |
| What's New screen (shown once per version update) | Yes — WhatsNewView, kChangelog | Yes |
| Onboarding (6 steps: hero, pin, narrow, notify, location, ads/ATT) | Yes — OnboardingView | Yes |

**V2 screens still flagged (not default):** SoftHomeView, SoftStopView, SoftBusView, SoftNearbyView, SoftSearchView, SoftSettingsView, SoftRoot. The flag is `leyne.softUI` (UserDefaults). Removing the flag gate is the key unlock for the next public release.

**Known deferred work (from code comments):**
- Live Activity CTA in SoftBusView is hidden (`// liveActivityCTA — hidden until ActivityKit is wired`) — the widget/activity code exists but the in-app entry point is commented out.
- AddStopSheet is dead code (RootView still mounts it but m.showAdd never flips).
- Flutter DetailView alight card still uses iOS-style toggle pill (Material redesign target).
- First/last bus labels in DetailView — requires reading LTABusServiceDTO first/last fields.
- "~ Scheduled" tag for non-monitored arrivals in DetailView (requires monitored field mapping).
- l10n — language picker is aspirational; ARB→xcstrings port not done; app is English-only in practice.

**How to apply:** Frame all analysis against a solo-developer constraint. Avoid recommending work that assumes a team. Prioritize highest-ROI items. The single most impactful pending action is shipping V2 as the default UI.
