---
name: project-status
description: "Leyne current project status — what's done, in-flight (uncommitted), and left before shipping V2 redesign. Snapshot as of 2026-05-30."
metadata:
  type: project
---

## Overall health: At Risk (large body of uncommitted cross-cutting work on main; version not bumped)

## Platform versions in play

| Platform | Version | State |
|---|---|---|
| iOS native (`ios-native/`) | 2.2.3+12 | Active dev target. V2 Soft screens in use. Uncommitted: widget palette, Live Activity CTA wired. |
| Android/Flutter (`lib/`) | 2.2.9+21 | Closed testing on Play. Uncommitted: Android parity pass, stop alerts, bus notify, ongoing notification. |

## What is DONE (committed, as of 9175bff)

- Full V2 "Soft" palette on both platforms
- iOS V2 screen layer: six screens + nine shared primitives
- Flutter V2 screen layer: matching six screens
- Notifications system (arrival + alight alerts, exact scheduling, deep-link tap-to-open)
- Live Activities + WidgetKit (iOS), scaffolded Android notification concept
- Pull-to-refresh on iOS V2 (Home/Stop/Bus); DataStore `refreshArrivals`
- Onboarding v2 (both platforms): no-skip, 4/5-step with location + notification + ATT priming
- `Monitored` flag on arrivals
- `TabView` per-tab `NavigationStack` (iOS)
- Flutter notification-default bug fix + 83 tests passing (9175bff)

## What is IN-FLIGHT (uncommitted — 14 modified files as of 2026-05-30)

| File | Change |
|---|---|
| `ios-native/Leyne/V2/SoftBusView.swift` | Live Activity V2 CTA wired to `m.toggleLiveActivity` |
| `ios-native/LeyneWidgets/LeyneLiveActivity.swift` | Soft palette re-alignment |
| `ios-native/LeyneWidgets/LeyneStopWidget.swift` | Home Screen widget Soft palette re-alignment |
| `lib/screens/v2/soft_stop_screen.dart` | Android stop alert controls: per-bus bells, AppBar master bell, SegmentedButton sort, notif-off banner, implicit pinning (FAB removed) |
| `lib/screens/v2/soft_home_screen.dart` | PIN chip suppressed when no nickname (parity fix) |
| `lib/screens/v2/soft_bus_screen.dart` | Android bus notify button; ongoing live-tracking notification (foreground-only limitation documented); dead Live Activity card removed; dead map BUS legend removed |
| `lib/screens/v2/soft_settings_screen.dart` | Notifications row wired to NotificationsScreen; dead Routines + Language rows removed |
| `lib/services/notifications.dart` | New ongoing notification logic |
| `lib/state/app_model.dart` | `rescheduleIfNeeded()` for alert state; supporting model changes |
| `lib/data/data_store.dart` | Supporting data changes |
| `lib/main.dart` | Minor wiring |
| `CHANGELOG.md` | Updated (session changes not yet committed) |
| `.claude/agent-memory/business-analyst/MEMORY.md` | Agent memory update |
| `.claude/agent-memory/ui-ux-designer/MEMORY.md` | Agent memory update |

**Theme:** Android parity pass (stop alerts, bus notify, ongoing notification, settings wiring), iOS widget/LA palette re-alignment. Flutter analyze clean, 83 tests pass, iOS builds.

## Parity gaps CLOSED this session

- GAP 7 (P0): Flutter stop screen per-bus bell + master alert pill — DONE
- GAP 20 (P0): Flutter Settings Notifications row dead — DONE (wired)
- GAP 11 (P0): Flutter bus screen Live Activity card tappable no-op — DONE (dead card removed; replaced with real ongoing notification)
- GAP 13: Flutter bus map BUS legend for nil busCoord — DONE (removed)
- GAP 19 + GAP 21: Android Settings dead rows (Routines, Language) — DONE (removed)
- GAP 3: Flutter pin card "PIN" chip when no nickname — DONE (suppressed)

## Parity gaps STILL OPEN (from parity map)

### P0
- (none remaining from original P0 list — all closed)

### P1
- GAP 6/9/15: Pull-to-refresh on Android Home, Stop, Bus — iOS has `.refreshable` on all three; Android not yet wired (note: DataStore.refreshArrivals exists)
- GAP 8: Flutter stop detail hero-card-first layout vs iOS flat sorted list (divergent mental model)

### P2 (iOS-side)
- BLEED 1 / GAP 22: iOS `SoftToggle` should be native SwiftUI `Toggle`
- `SoftBusView.scheduleAlight` writes raw UserDefaults instead of calling `m.setActiveAlight(...)` (stale stub, ~5 lines)
- Live bus map marker never shows (`DataStore.route()` hard-codes `busCoord: nil`)
- `kChangelog` in `AppModel.swift` only has `"2.0.0"` — add 2.1.0/2.2.x entries
- Dynamic Type: `Theme.swift` `sans`/`mono` use `.system(size:)` with no `relativeTo:` — whole app ignores Dynamic Type

### P3 (Android)
- GAP 14: Flutter route timeline invents per-stop ETA minutes (`etaMin` fabrication — iOS removed this)
- GAP 1: Flutter onboarding missing footnote hints on steps 4–5
- GAP 12: Flutter bus screen header leads with stop name rather than bus number
- GAP 16: iOS nearby row doesn't show first live arrival inline (Android richer here)
- Android "true background tracking" via foreground service — current ongoing notification is foreground-only

## What is LEFT before shipping

### Critical path (blocking ship)
1. Commit in-flight work (14 files, multiple concerns — needs thoughtful split)
2. Version bump: iOS 2.2.3+12 → 2.3.0 (or 2.2.4), Flutter pubspec bump
3. Feature-flag status: V2 is the active path on both platforms; confirm V1 dead code removal strategy
4. iOS Archive + TestFlight → App Store
5. Android AAB + Play upload

### Deferred / not blocking
- True background foreground-service tracking (Android)
- iOS widget review punch list (open items above)
- iOS CI for `ios-native/` target (currently zero coverage)
- P2/P3 parity items above

**Why:** Captures the full post-session state for the next conversation.
**How to apply:** Start every session with git status. If uncommitted work remains, that is action #1.

Related: [[project-risks]], [[next-actions]]
