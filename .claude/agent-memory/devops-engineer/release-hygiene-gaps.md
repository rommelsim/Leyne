---
name: release-hygiene-gaps
description: Identified gaps in release hygiene — versioning, changelog discipline, CI coverage, and process risks
metadata:
  type: project
---

## Versioning

**Android:** Single source of truth in `pubspec.yaml` `version:` field. Manual edit required before each build. No enforcement — a build can be produced without bumping. Play Console will reject a duplicate versionCode, so the version bump is effectively enforced at upload time, not at build time.

**iOS:** Version split across `project.pbxproj` — `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` must both be updated, and they exist in 6 separate config blocks (2 per target × 3 targets). A partial bump (updating only some blocks) is easy to miss. As of 2026-05-29: `2.2.3` / `12`. Native iOS version is NOT sourced from `pubspec.yaml` — the two platforms can diverge silently.

**Cross-platform version drift:** Android is at `2.2.9+21`, iOS is at `2.2.3+12`. They are in different version spaces with no automated sync. This is an intentional consequence of having separate active development streams; just worth noting as a source of confusion when referencing "the current version."

## Changelog discipline

**Current state:** `CHANGELOG.md` at repo root exists and is well-maintained manually. The project has a strong established practice: every AAB and Archive must have a corresponding CHANGELOG.md entry (see [[changelog-after-build]] in project-scoped memory).

**iOS `kChangelog` in `AppModel.swift`:** Must also be updated for user-facing iOS releases (the in-app What's New screen reads from it). This is a second manual touch point that can be forgotten.

**Gap:** No tooling enforces either update. Nothing blocks a `git commit` that bumps `pubspec.yaml` without a `CHANGELOG.md` entry, or an Xcode Archive without a `kChangelog` update.

## CI coverage gaps

1. **Native iOS target never builds in CI.** The `ios job` runs `flutter build ios --no-codesign --debug` — this builds the Flutter iOS wrapper in `ios/`, not `ios-native/Leyne.xcodeproj`. A Swift compile error in `ios-native/` is invisible to CI.

2. **No release-mode Android build in CI.** CI produces a debug APK only. R8 is disabled (see `build.gradle.kts` comment — WorkManager crash), so this is lower risk than usual, but the release signing config and `--dart-define` flags are never exercised by CI.

3. **No version consistency check.** CI does not verify that `pubspec.yaml` version was bumped, or that `CHANGELOG.md` was updated, or that iOS pbxproj version was touched.

4. **No Play Console upload automation.** AAB upload to Play Console is 100% manual. Risk: uploading the wrong AAB (e.g., prod AAB when closed-test was intended, or a stale artifact).

5. **iOS ad toggle not verified by CI.** `AdConfig.forceTestUnitForRelease` must be `false` before App Store submission. There is a `#warning` guard but no automated check.

## Manual ritual risks

**Highest-risk manual step: iOS ad toggle.** Forgetting to flip `forceTestUnitForRelease` back to `false` before App Store submission means live users see Google's test creative, not real ads — immediate revenue impact. The `#warning` in Xcode mitigates this but requires the developer to read the build warning.

**Second risk: version bump race with Play Console versionCode.** Play Console is authoritative on used versionCodes. The `native_rewrite_status` memory notes: "Play tracks claimed versionCodes ruthlessly — check App bundle explorer in Play Console before each upload if uncertain." An incorrect versionCode causes an upload rejection (not a crash), so the impact is delay, not data loss.

**Third risk: signing key locality.** The upload keystore exists only on Rommel's machine at an absolute path. If the machine is unavailable, no signed AAB can be produced.

## What's well-done

- Scripts use `set -euo pipefail` — fail-fast on any error.
- `BUILDING.md` documents the ad-mode matrix clearly.
- `key.properties` is gitignored; no secrets in git history.
- CI concurrency group prevents redundant macOS runner usage.
- `CHANGELOG.md` format is established and followed consistently.

**Why:** Understanding these gaps allows prioritizing which hardening steps give the most blast-radius reduction per effort.
**How to apply:** When a build fails, check: (1) did version bump happen? (2) was the right build script used? (3) is the iOS ad toggle in the right state? When asked to help with a release, verify all three before producing any artifact.

Related: [[build-release-setup]], [[signing-and-secrets]], [[pipeline-hardening-recommendations]]
