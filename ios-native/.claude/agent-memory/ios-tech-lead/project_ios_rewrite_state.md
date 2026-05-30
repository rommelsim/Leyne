---
name: ios-rewrite-state
description: iOS native rewrite current state — V2 (Soft* views) is the default; parity gaps and known concerns as of 2026-05-30
metadata:
  type: project
---

V2 (Soft* views) is the current default and only active UI path. V1 views (HomeView, DetailView, PinnedCardView, SettingsView) still exist in the project but are no longer reachable from the running app — SoftRoot is the entry point.

**Why:** V2 flip was done in commit d3980e2 (Leyne 2.3.0). V1 code is retained as reference but should not be treated as live.

**How to apply:** When reviewing iOS code, focus on V2/Soft* files. V1 code is legacy context only.

## Known V2 parity gaps (vs V1 and Android)

- Pin reorder (drag-and-drop) — AppModel.movePin exists, no V2 UI entry point
- Pin rename (inline text field) — AppModel.rename exists, no V2 UI entry point
- Primary-bus selection (setPrimary) — AppModel method exists, no V2 UI entry point
- Search radius setting — SoftSettingsView omits this row (V1 SettingsView had it)
- Language picker — SoftSettingsView omits this row
- About / What's New nav rows — SoftSettingsView omits these
- Onboarding replay — SoftSettingsView omits this
- Nearby pull-to-refresh — SoftNearbyView has no .refreshable modifier
- Live bus position (busIndex/busCoord) — always nil; LTA API doesn't expose it

## Key file locations

- Entry: ios-native/Leyne/V2/SoftRoot.swift
- Home: ios-native/Leyne/V2/SoftHomeView.swift
- Stop detail: ios-native/Leyne/V2/SoftStopView.swift
- Bus tracking: ios-native/Leyne/V2/SoftBusView.swift
- Route timeline: ios-native/Leyne/V2/RouteTimeline.swift
- Nearby: ios-native/Leyne/V2/SoftNearbyView.swift
- Search: ios-native/Leyne/V2/SoftSearchView.swift
- Settings: ios-native/Leyne/V2/SoftSettingsView.swift
- App state: ios-native/Leyne/AppModel.swift
- Data layer: ios-native/Leyne/DataStore.swift
- Widget + Live Activity: ios-native/LeyneWidgets/
