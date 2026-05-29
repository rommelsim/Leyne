---
name: project-ios-native-gaps
description: iOS 26 / Liquid Glass native-correctness gaps observed in Leyne's V2 SwiftUI
metadata:
  type: project
---

Observed in `ios-native/Leyne/V2/` (as of 2026-05-29 review):

- Toolbar hidden on EVERY screen (`SoftRoot.navStack` applies `.toolbar(.hidden, for: .navigationBar)`), replaced by custom `GlassPillButton` Back/Pin (`V2/IOSGlassPill.swift`). Costs: no large-title behavior, no native back chrome, swipe-back needs a `SwipeBackEnabler` UIViewControllerRepresentable hack to re-enable. Native `.navigationTitle` + `.toolbar` would give Liquid Glass, large titles, a11y, and edge-swipe for free.
- No native `List`/`Form` anywhere live — all lists are `ScrollView`+`VStack`+custom `Button`. Loses swipe-to-delete (unpin), free separators/insets, list a11y, `.refreshable`. Settings especially should be grouped `List` (`.insetGrouped`).
- Search tab uses a custom `TextField` pill + custom "Cancel" + custom filter chips instead of `.searchable` / `.searchScopes`. The native `.search`-role Tab is used for the container but not the field.
- Custom `SoftToggle` (38x22) instead of native `Toggle`/`UISwitch` — wrong size (Apple switch ~51x31), no a11y switch trait, no system tint behavior.
- Font system (`Theme.sans/.mono`) uses fixed `.system(size:)` with NO `relativeTo:` text style → no Dynamic Type scaling. See [[project-accessibility-status]].
- `RouteTimeline` rows and many card rows are below 44pt tap height; chips ~28pt.
- `liveActivityCTA` in `SoftBusView` is a no-op (TODO comment) — looks tappable, does nothing. Alight scheduling writes UserDefaults but isn't wired to notifications.
- No `.contextMenu` on pinned cards (natural place for rename/unpin/reorder on iOS).
- No pull-to-refresh on arrival lists (was a planned Phase 4 item).

**Why:** These are where the "platform-native iOS 26" goal is actually unmet — not the brand visuals (see [[project-soft-design-language]]).
**How to apply:** Recommend adopting native containers/controls (List, Toggle, .searchable, .navigationTitle/.toolbar, .refreshable, .contextMenu) which also resolve most a11y gaps. Verify against current code before asserting — the rewrite is in flight.
