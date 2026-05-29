---
name: project-leyne-overview
description: Leyne app core function, screens, navigation, and where the live UI actually lives in the repo
metadata:
  type: project
---

Leyne is a Singapore transit app. Core job-to-be-done: **let a commuter glance at live bus arrivals for the stops they use, and get alerted in time to walk to the stop** — so they stop compulsively checking their phone.

**Live UI = the "Soft" / 2.0 suite**, not the older top-level views.
- iOS (SwiftUI): `ios-native/Leyne/V2/Soft*.swift`, mounted by `V2/SoftRoot.swift`. Entry: `LeyneApp` → `RootView` → `SoftRoot`.
- Android (FLUTTER, not Compose/native): `lib/screens/v2/soft_*.dart` + `lib/widgets/v2/`. Android counterpart is Flutter, porting from iOS (specs say "iOS native leads; Flutter Android ports from iOS").
- LEGACY / mostly-dead iOS views: top-level `HomeView.swift`, `DetailView.swift`, `NearbyView.swift`, `SearchSheet.swift`, `PinnedCardView.swift`, `AddStopSheet.swift`, `SettingsView.swift`. Some still referenced by AppModel plumbing but not in the live SoftRoot tree. The legacy DetailView/AddStopSheet contain features (notify-at, bus-narrowing) that the live Soft UI dropped.

Screens (live): Home (`SoftHomeView` — greeting + pinned-stop cards + MRT alert cards + empty state), Nearby (`SoftNearbyView` — sort chips + nearby stop rows), Settings (`SoftSettingsView`), Search (`SoftSearchView` — own tab via `.search` role), Stop detail (`SoftStopView` — sortable bus list, pin toggle), Bus tracking (`SoftBusView` — big arrival numeral, Live Activity CTA, MapKit map, `RouteTimeline` alight picker). Onboarding = `OnboardingView` (5 steps).

Tabs (both platforms, this order): Home / Nearby / Settings / Search.

Arrival data states exist in `ArrivalState` enum (loading/loaded/empty/error) and `Freshness` (live/stale/offline) — the model supports states even where screens don't render them.

**Why:** Establishes scope so reviews target the live Soft UI, not dead legacy code.
**How to apply:** When reviewing or designing, work in `V2/` for iOS and `lib/screens/v2/` for Android. Treat top-level legacy Swift views as reference for dropped features, not as current UX.
