---
name: parity-gaps-ios-flutter
description: Implementation gaps and parity gaps between native iOS and Flutter Android, plus technical debt. Source: specs/parity.md + code review 2026-05-29.
metadata:
  type: project
---

## Canonical source

`specs/parity.md` is the authoritative parity tracker. This memory is a distilled engineering view. When adding new features, cross-check both.

Sequencing rule (from `specs/leyne-2.0-plan.md`): **iOS native leads; Flutter ports from iOS.** iOS is the spec.

## Critical iOS gaps (things the V2 views are missing vs. the spec)

| Gap | File | Notes |
|---|---|---|
| Live Activity CTA in SoftBusView | `V2/SoftBusView.swift` | Built but commented out — waiting for parity.md Task #12 (ActivityKit wiring). `liveActivityCTA` view exists; the call site is removed from `body`. AppModel already has full ActivityKit wiring — the connection to the V2 UI is what's missing. |
| Alight alert properly wired | `V2/SoftBusView.swift:scheduleAlight` | Writes directly to UserDefaults. Should call `m.setActiveAlight(busNo:stopCode:stopName:fireAt:)` in AppModel which then calls `NotificationsManager.scheduleAlightAlert`. "Phase 3" comment is stale — AppModel already has `setActiveAlight`. |
| `SoftBusView.busCoord` always nil | `V2/SoftBusView.swift`, `DataStore.route` | `DataStore.route()` hard-codes `busCoord: nil`. `DataStore.liveBus(service:stopCode:)` CAN fetch real coordinates but is never called from route loading. The map therefore never shows the live bus marker. To fix: call `liveBus` after `route()` resolves and merge the coordinate in. |
| Home pinned card only shows tracked services | `V2/SoftHomeView.swift:filteredServices` | `filteredServices` applies the pin's tracked filter before passing to `SoftPinCard`. This is correct for the Home card but means the `overflowCount` chip says "+N more arrivals" when N counted buses are actually excluded by tracking filter, not absent — the count can mislead. |
| `SoftBusView.loadRoute` + bus position not polled | `V2/SoftBusView.swift` | `loadRoute` is called once on `onAppear` and once on pull-to-refresh. The bus coordinate won't update on the per-second tick (unlike arrival ETA which updates via AppModel.onTick). |

## Flutter Android gaps vs. iOS (from parity.md)

These are the things iOS ships that Flutter still lacks, in priority order per `specs/parity.md`:

1. **Variant B Smart Hero on Detail Mode B** — biggest delta; Flutter never had Mode B
2. **Heartbeat pulse + staggered entrance on Home cards** — the "alive" feel
3. **Operator stripe (3pt left edge) on service rows** — part of new identity
4. **5-step onboarding** — Flutter has 4 steps; notifications step is the added one
5. **Route progress vertical stem** — not in Flutter
6. **Glass-equivalent surfaces** — Flutter `BackdropFilter` can approximate
7. **Primary-bus long-press** for hero locking
8. **FlowChip horizontal scroll** for recents (Flutter wraps instead)
9. **Pin model `primaryBus` field** — Flutter Pin has no primary field
10. **Offline-red live chip state** — Flutter has live/stale but not offline-red

**Flutter changes already in uncommitted diff (2026-05-29):**
- Onboarding `onDone` callback removed + Skip button removed (matches iOS 5-step no-skip design)
- This closes one item from the onboarding parity gap.

## Technical debt

| Item | Severity | Notes |
|---|---|---|
| `AddStopSheet.swift` dead code | Low | `m.showAdd` never flips true in SoftRoot; the sheet is never shown. Safe to delete via Xcode. |
| Feedback.blip `delay` param silently ignored | Low | `when` is computed but then `_ = when` on line 120; the `delay` > 0 path uses `asyncAfter` instead of AVAudioTime scheduling. Works but the intent is misleading. |
| Stale `AppTab` enum in AppModel | Low | AppModel still has `AppTab: home/nearby/settings/search` and `.tab: AppTab`. SoftRoot uses its own `SoftTab` enum. The two enums are independent; openCard deep links use `AppModel.open(...)` which doesn't touch SoftTab directly. |
| `inflight` set not protected against concurrent access | Medium | `DataStore.inflight: Set<String>` is mutated from both `ensureArrivals` (Task) and `refreshArrivals` (async func called from `.refreshable`). Both run on MainActor (`@MainActor final class DataStore`) so this is safe — but worth documenting since the `@MainActor` annotation is doing the heavy lifting silently. |
| `kChangelog` only has `"2.0.0"` entry | Low | `AppModel.swift` has `kChangelog["2.0.0"]` only. Versions 2.1.0, 2.2.x have no entries — users upgrading from 2.0.x will see the What's New on 2.0.0 correctly, but 2.1/2.2 upgrades silently skip it. Add entries for shipped versions when content is ready. |
| Font: spec calls for Inter, app uses system-sans | Medium | `leyne-2.0-plan.md` specifies Inter (bundle weights 400/500/600/700). `Theme.swift` likely still uses `Font.custom("Inter-...", ...)` — verify these font files are actually bundled in Assets.xcassets / project target. Missing font = silent fallback to system sans. |

Related: [[architecture-ios-native]], [[uncommitted-changes-2026-05-29]], [[next-implementation-tasks]]
