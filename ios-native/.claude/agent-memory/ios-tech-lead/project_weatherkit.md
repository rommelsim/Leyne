---
name: project-weatherkit
description: WeatherKit integration — files created, entitlement, project.pbxproj edits, known runtime prerequisites
metadata:
  type: project
---

WeatherKit was added on 2026-06-10. Two new files:
- `Leyne/WeatherService.swift` — `@MainActor ObservableObject` singleton; wraps `WeatherKit.WeatherService.shared`; graceful nil-snapshot fallback on error; 15-min periodic refresh timer; fetches `attribution` URLs alongside weather.
- `Leyne/WeatherHeader.swift` — `WeatherHeader` SwiftUI view (greeting + TimelineView clock + temp/condition/rain-hint + attribution link) + `WeatherBackdrop` (greyscale vertical gradient only, no hue).

Entitlement added to `Leyne.entitlements`: `com.apple.developer.weatherkit = true`.

`project.pbxproj` edits: added `WeatherKit.framework` PBXFileReference (SDKROOT path), PBXBuildFile, Frameworks group, wired into target `1A0000000000000000000005 (Leyne)` PBXFrameworksBuildPhase. Keys used: `WK0000000000000000000000/01/02`.

`SoftHomeView.swift` change: `header` computed var now embeds `WeatherHeader(t: t)` above the title row; old `greeting` private var removed (now lives inside `WeatherHeader`).

**Why:** user-facing weather feature; monochrome constraint (zero hue, greyscale only per Theme.swift); must not crash when capability unprovisionioned.

**How to apply:** WeatherKit will silently return nil until the owner enables the capability at developer.apple.com. The app works normally in that state. See manual-setup steps in the implementation report.
