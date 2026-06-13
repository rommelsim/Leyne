---
name: parity-audit
description: >
  Audit cross-platform parity between the iOS app (native SwiftUI) and the
  Android app (Flutter). Use whenever the user asks to compare the two platforms,
  check that screens/features/navigation match, verify parity, find what Android
  is missing vs iOS, or confirm a feature shipped on both. Produces a parity
  table per screen, a list of divergences to fix on Android, and the iOS-exclusive
  skip-list.
---

# iOS ↔ Android parity audit

Leyne ships two apps that should feel the same:

- **iOS** — native SwiftUI, source of truth, in `ios-native/Leyne/V2/` (the active
  "V2 / Soft" UI) plus a few top-level views.
- **Android** — Flutter, in `lib/screens/v2/` + `lib/widgets/v2/`.

iOS leads; Android usually follows. **Treat iOS as the design source of truth**
unless the user says otherwise. Note where Android is *richer* too — those are
candidates to port *to* iOS, not bugs.

⚠️ The non-`v2` files are **legacy/dead code** on both sides (e.g.
`ios-native/Leyne/HomeView.swift`, `NearbyView.swift`; `lib/screens/home_screen.dart`,
`lib/screens/nearby_screen.dart`, `lib/screens/root_scaffold.dart`,
`lib/widgets/pinned_card.dart`). Don't audit those — confirm they're unreachable
and ignore. The live "Nearby" tab is the **Home** screen (`SoftHomeView` ↔
`soft_home_screen.dart`), not the file named "Nearby."

## Screen pairings (iOS ↔ Android)

| Cluster | iOS | Android |
|---------|-----|---------|
| App shell / nav / tabs | `V2/SoftRoot.swift`, `V2/SoftTabBar.swift` | `screens/v2/soft_root.dart`, `widgets/v2/soft_tab_bar.dart` |
| Home (the "Nearby" tab) | `V2/SoftHomeView.swift`, `V2/SoftStopCard.swift` | `screens/v2/soft_home_screen.dart` |
| Saved | `V2/SoftFavouritesView.swift` | `screens/v2/soft_favourites_screen.dart` |
| Search | `V2/SoftSearchView.swift` | `screens/v2/soft_search_screen.dart` |
| MRT board | `V2/SoftMrtView.swift` | `screens/v2/soft_mrt_screen.dart` |
| Settings | `V2/SoftSettingsView.swift` | `screens/v2/soft_settings_screen.dart` |
| Stop detail | `V2/SoftStopView.swift` | `screens/v2/soft_stop_screen.dart` |
| Bus detail | `V2/SoftBusView.swift` | `screens/v2/soft_bus_screen.dart` |
| Manage alerts | `V2/ManageAlertsView.swift` | `screens/v2/manage_alerts_screen.dart` |
| Hidden stops | `V2/HiddenStopsView.swift` | `screens/v2/hidden_stops_screen.dart` |
| Onboarding | `OnboardingView.swift` | `screens/onboarding_screen.dart` |
| What's New | `kChangelog` in `AppModel.swift` | `screens/whats_new_screen.dart`, `data/changelog.dart` |
| Shared widgets | `V2/RouteTimeline.swift`, `Confidence.swift`, `Proximity.swift`, `ServiceBadge.swift`, `SaveSheet.swift` | `widgets/v2/route_timeline.dart`, `confidence.dart`, `proximity.dart`, `route_progress.dart`, `save_sheet.dart` |

## How to run it

For a broad audit, **fan out parallel subagents** (`general-purpose` or the
platform tech-leads), one per screen cluster, each comparing its iOS file(s) to
the Android counterpart and returning a structured report. For a single screen,
just compare directly. Each comparison should cover:

1. Layout & sections (order, headers, cards)
2. Per-item data shown
3. Interactions (tap, long-press, swipe, drag-reorder, pull-to-refresh)
4. Navigation flows — what each gesture pushes/presents, and whether it matches
5. Empty / loading / permission states

## Output

Produce, per cluster:

- **Parity table:** feature | iOS | Android | status (✅ match / ⚠️ differs /
  ❌ missing on Android / 🍎 iOS-exclusive)
- **Divergences to fix on Android** — concrete, with file references
- **iOS-exclusive features to skip** (see list below)
- **Android-richer extras** — flag as port-to-iOS candidates, not bugs

## iOS-exclusive — SKIP on Android (these are NOT gaps)

- **Bus-view map** (MapKit) + **MapHandoffToast** — Android intentionally has no
  map; its horizontal route-progress bar is the replacement. Never re-add a map.
- **ATT (App Tracking Transparency)** — Android uses **UMP consent** instead.
- **Live Activities, Home Screen widgets, WeatherKit, Spotlight, Siri** —
  iOS-native platform features.
- **Symbol-bounce animations, true system share sheet, iOS-26 Liquid Glass
  chrome** — platform idioms; Android's flat/Material equivalents are correct.

Respect the platform-native design language: do not flag a correct Material
implementation as a divergence just because it isn't a 1:1 SwiftUI copy.

## Follow-up

To actually close gaps, use the `port-ios-feature` skill. For version/changelog,
use `release-build` / `changelog-update`.
