---
name: project-status
description: "Leyne current project status — what's done, in-flight (uncommitted), and left before shipping V2 redesign. Snapshot as of 2026-05-29."
metadata:
  type: project
---

## Overall health: At Risk (uncommitted work sitting unstaged; V2 not yet the default UI)

## Platform versions in play

| Platform | Version | State |
|---|---|---|
| iOS native (`ios-native/`) | 2.2.3+12 | Active dev target. V2 Soft screens wired but behind `leyne.softUI` flag. Uncommitted changes. |
| Android/Flutter (`lib/`) | 2.2.9+21 | Closed testing on Play. Uncommitted onboarding changes. |

## What is DONE (as of last commit 1695293)

- Full V2 "Soft" palette deployed to both platforms (iOS `Theme.swift`, Flutter `lib/theme.dart`)
- iOS V2 screen layer: six screens (Home, Nearby, Stop, Bus, Search, Settings) + nine shared primitives, all in `ios-native/Leyne/V2/`
- Flutter V2 screen layer: matching six screens in `lib/screens/v2/`
- Notifications system on both platforms (arrival + alight alerts, exact scheduling, deep-link tap-to-open)
- Live Activities + WidgetKit (legacy scaffolding, palette refreshed to v2 tokens)
- DataStore: `servicesAtStop`, `ensureRoutes`, `warmNearby`, etc.
- Settings/About/Notifications/WhatsNew screens rewritten (iOS native)
- Onboarding v2 (both platforms): 4-step with location + notification + ATT priming
- `Monitored` flag on arrivals (distinguishing real-time vs scheduled ETAs)
- `TabView` per-tab `NavigationStack` (iOS)
- `CHANGELOG.md` + `BUILDING.md` at repo root; build scripts in `scripts/`

## What is IN-FLIGHT (uncommitted, as of 2026-05-29)

| File | Change | Status |
|---|---|---|
| `DataStore.swift` | New `refreshArrivals(stop:)` async method for pull-to-refresh (bypasses freshness window, awaits real network) | Staged work, not committed |
| `V2/SoftBusView.swift` | Wires `.refreshable` to `refreshArrivals`; fixes map annotation anchor to `.bottom`; `figure.walk` → `mappin.and.ellipse` icon in context line | Staged work, not committed |
| `V2/SoftStopView.swift` | Wires `.refreshable`; improved `trackAllLabel` logic ("Alert all" / "N alerts" / "All alerts"); better a11y copy; `figure.walk` → `mappin.and.ellipse` | Staged work, not committed |
| `V2/SoftHomeView.swift` | Wires `.refreshable` (refreshes all pins); removes "PIN" chip when no real nickname (chip was noise) | Staged work, not committed |
| `Feedback.swift` | Audio session fix: removes explicit `setActive(true)` so the app no longer interrupts user's background music on launch | Staged work, not committed |
| `OnboardingView.swift` | Comment/copy update: clarifies "no skip" intent | Staged work, not committed |
| `lib/main.dart` | Removes `onDone` param from `OnboardingScreen` call | Staged work, not committed |
| `lib/screens/onboarding_screen.dart` | Removes `onDone` callback + Skip button from Flutter onboarding; aligns with iOS no-skip pattern | Staged work, not committed |

**Theme of the in-flight work:** Pull-to-refresh wired across all three V2 stop/bus/home views (requires the new `refreshArrivals` in DataStore), UX copy polish (icon, label, a11y text), and a cross-platform onboarding parity fix (removing Skip).

## What is LEFT before shipping V2 as the default UI

### Critical path items (blocking V2 going live)

1. **Commit in-flight work** — uncommitted changes are sitting unstaged, at risk of loss.
2. **Feature-flag removal / default flip** — V2 is currently gated behind `leyne.softUI` UserDefaults toggle (iOS) and a flag check in `main.dart`. Neither is the default shipping UI yet. Decision needed: flip flag to default-on (or delete the old UI) before archiving/building.
3. **Old V1 screens cleanup** — `HomeView.swift`, `NearbyView.swift`, `DetailView.swift`, `RootView.swift` V1 paths. `AddStopSheet.swift` is acknowledged dead code (`m.showAdd` never flips). Delete or archive before next App Store submission.
4. **iOS archive + App Store submission** — version is 2.2.3+12. No archive has been cut yet for this version.
5. **Android AAB + Play upload** — Flutter 2.2.9+21 has the onboarding Skip removal pending commit.

### Polish items (deferred, not blocking ship)

- `DetailView.swift` "~ scheduled" tag for non-Monitored arrivals
- `DetailView.swift` first/last bus labels (needs LTABusServiceDTO fields)
- `DetailView.swift` alight picker in route progress
- Flutter `_onBusAlertCard` in `detail_screen.dart`: iOS-style toggle pill needs Material redesign (see [[platform-design-language]])
- `AddStopSheet.swift` dead code deletion

**Why:** Context for judging what to prioritize vs defer in the next session.
**How to apply:** Before any new feature work, confirm in-flight changes are committed and V2 flag status has been decided.

Related: [[project-risks]], [[platform-design-language]], [[native-rewrite-status]]
