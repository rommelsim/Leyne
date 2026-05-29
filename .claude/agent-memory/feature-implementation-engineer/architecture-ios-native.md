---
name: architecture-ios-native
description: iOS native app architecture — data flow, state management, key types, file map. Snapshot as of 2026-05-29.
metadata:
  type: project
---

## Layer map

```
LeyneApp.swift         — SwiftUI @main; injects AppModel/DataStore/Feedback as EnvironmentObjects;
                         calls AppModel.setCurrentVersion() at boot.
RootView.swift         — Launch splash (zIndex 200) → Onboarding gate (zIndex 50) → WhatsNew modal
                         (zIndex 55) → SoftRoot. Theme + deep-link wiring live here.
SoftRoot.swift         — Native iOS 26 TabView (Liquid Glass bar). 4 tabs, each owns an independent
                         NavigationStack ([SoftRoute]), so drilldowns don't bleed across tabs.
                         SoftRoute enum: .stop(String), .bus(stopCode:svc:), .search.
                         Deep links: m.openCard publishes → SoftRoot pushes Stop or Bus onto homeStack.
```

## Key singletons

| Type | Pattern | Purpose |
|---|---|---|
| `AppModel` | `@MainActor ObservableObject`; `@EnvironmentObject` in views | User preferences, pins, notification intent, Live Activity, What's New gate, per-second tick |
| `DataStore` | `static let shared`; also `@EnvironmentObject` in views | LTA reference data + live arrivals; train alerts; route geometry |
| `Feedback` | `static let shared` | Haptic + synthesised-audio tones (4 levels: tap/select/success/arrival) |
| `LocationManager` | `static let shared` | CoreLocation wrapper; provides `location` to views and DataStore.updateNearby |
| `LTAService` | `static let shared` | HTTP transport layer; pageWindow=6 for bus stops |
| `NotificationsManager` | inline in AppModel.swift | UNUserNotificationCenter scheduling; arrival + alight identifiers |

## Data flow

```
User location → LocationManager → DataStore.updateNearby → DataStore.nearby [@Published]
                                                          → DataStore.stopByCode (lookup)

AppModel.onTick() (1 Hz) → DataStore.ensureArrivals(stop:) per pinned stop + openCard
                          → NotificationsManager.scheduleArrivalAlerts (every 10 ticks)
                          → DataStore.refreshTrainAlertsIfStale (60 s gate)

User action → DataStore.refreshArrivals(stop:) [async, awaitable for pull-to-refresh]

DataStore.arrivals: [String: ArrivalState]  ← @Published; ArrivalState = .loading | .loaded([Service]) | .empty | .error(String)
DataStore.lastFetched: [String: Date]        ← @Published; drives freshness dot on Home
```

## Pin model invariant

`Pin.tracked == nil` means "track all services". A non-nil array is an explicit subset. An empty array is never stored — it means unpin (the Pin is removed). `pinned ⟺ ≥1 tracked bus`.

`Pin.primary: String?` = user-locked hero bus for the Home card; nil falls back to soonest-tracked.

Persistence key: `leyne.pins` (UserDefaults, JSON-encoded `[Pin]`). Matches Flutter's key so migrations preserve data.

## Theme system

`Theme.swift` — two static instances `.dark` / `.light`. `AppModel.t` selects based on `isDark` (which mirrors `LeyneThemeMode` + system scheme). Views receive the theme via `m.t`, NOT via environment. The accent palette is mint: `5EE597` dark / `2BAA67` light (old) — note: the Soft 2.0 spec calls for `#8EE6C0` / `#2D7A5A`. Verify current values in `Theme.swift` against `leyne-2.0-plan.md` spec before building new screens.

## Inline-everything strategy

To avoid pbxproj surgery, new types live inside existing files:
- `NotificationsManager` inline in `AppModel.swift`
- `GeocodeService` inline in `LTAService.swift`
- `AboutView`, `NotificationsView`, `WhatsNewView`, `OptionSheet` inline in `SettingsView.swift`

Adding a genuinely new `.swift` file requires editing 4 sections of `project.pbxproj` (PBXFileReference, PBXBuildFile, Lyne group children, Lyne target Sources). Prefer inlining until Xcode UI can be used to add files cleanly.

Related: [[uncommitted-changes-2026-05-29]], [[parity-gaps-ios-flutter]]
