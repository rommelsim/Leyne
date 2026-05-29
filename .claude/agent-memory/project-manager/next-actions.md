---
name: next-actions
description: "Recommended next highest-value tasks for the Leyne project as of 2026-05-29, ordered by priority."
metadata:
  type: project
---

## Immediate (do before anything else)

1. **Commit in-flight work.** All eight modified files (`DataStore.swift`, three V2 views, `Feedback.swift`, `OnboardingView.swift`, `lib/main.dart`, `lib/screens/onboarding_screen.dart`) should be staged and committed together — they form one coherent "pull-to-refresh + onboarding parity" changeset. Update `CHANGELOG.md` with an "Unreleased" entry for these changes before committing.

## Next session — V2 default flip (highest value)

2. **Decide and execute V2 flag removal.** The V2 Soft UI is the real product. The flag is a dev scaffold. Remove the `leyne.softUI` guard from `RootView.swift` (iOS) and the conditional in `lib/main.dart` (Flutter) so V2 is unconditionally the default. This is the single highest-leverage change because it's what users actually ship.

3. **Delete or archive V1 dead code.** After V2 is the default: remove `AddStopSheet.swift` (dead code), and decide whether to archive V1 screens (`HomeView.swift`, `NearbyView.swift`, `DetailView.swift`, legacy `RootView` paths) or delete them. Keep the build compiling.

## Near-term (next iOS archive)

4. **iOS 2.2.3+12 Archive.** Once V2 is default and V1 dead code is removed, cut the Archive in Xcode. Check `kChangelog` in `AppModel.swift` has a 2.2.3 entry. Update `CHANGELOG.md`. Distribute via TestFlight before App Store submission.

5. **Android AAB for 2.2.9+21.** After onboarding Skip removal is committed, run `scripts/build-android-closed-test.sh` and upload to Play closed testing. Bump `pubspec.yaml` version if any further changes land before build. Update `CHANGELOG.md`.

## Polish (deferred, not blocking ship)

6. **Material redesign of Flutter `_onBusAlertCard`** in `lib/screens/detail_screen.dart` — currently uses an iOS-style toggle pill. Replace with a Material switch + Material card elevation. Only touch when in that file for another reason.

7. **`DetailView.swift` deferred features** — "~ scheduled" tag (needs `Monitored` bool on `Service`), first/last bus labels, alight picker in route progress. All non-blocking; pick up opportunistically.

**Why:** This ordering unblocks shipping without creating merge risk or scope creep. The flag removal is the critical-path step — everything else is prep or polish.
**How to apply:** Start every new session by checking git status first. If in-flight work is still uncommitted, that's action #1 before anything else.

Related: [[project-status]], [[project-risks]]
