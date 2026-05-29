---
name: build-release-setup
description: Current build and release mechanics for both Android (Flutter AAB) and iOS (Xcode Archive) — what exists, what is manual, what is missing
metadata:
  type: project
---

## Android (Flutter AAB)

**Build scripts:** `scripts/build-android-closed-test.sh` and `scripts/build-android-prod.sh` — both wrap `flutter build appbundle --release`. Closed-test script adds `--dart-define=LYNE_ADS_TEST=true` to force Google's reserved test unit. Output is always `build/app/outputs/bundle/release/app-release.aab`.

**Signing:** Upload keystore at `/Users/rommel/leyne-upload.jks`. Credentials loaded from `android/key.properties` (gitignored via `.gitignore`). `android/app/build.gradle.kts` falls back to debug signing if `key.properties` is absent, so CI builds succeed without the keystore. The keystore path is hardcoded as an absolute local path — works on Rommel's machine only; any second developer or CI machine needs the file at the same path.

**Version source:** `pubspec.yaml` `version:` field (`2.2.9+21` as of 2026-05-29). versionName + versionCode both flow from there via `flutter.versionCode` / `flutter.versionName` in `build.gradle.kts`. Version bump is manual (edit `pubspec.yaml`).

**Play Console track:** Internal Testing / Closed Testing. Production track not yet promoted. Account: `leyne0000@gmail.com`. App ID: `com.leyne.leyne`.

**What is fully manual (no automation):**
- Version bump in `pubspec.yaml`
- Running the build script locally
- Uploading the AAB to Play Console manually (no `bundletool`, no Google Play API, no Fastlane supply)
- Writing the CHANGELOG.md entry
- Promoting from internal to closed to production track

## iOS (Xcode Archive)

**Build path:** Manual — Xcode → Product → Archive → Organizer → Distribute App → App Store Connect → Upload. No `xcodebuild archive` script exists.

**Signing:** CODE_SIGN_STYLE = Automatic. DEVELOPMENT_TEAM = JFQKT254NR (`rommelsim@gmail.com` Apple ID). Provisioning profile managed automatically by Xcode. No exported `ExportOptions.plist` exists.

**Ad unit toggle ritual (critical manual step):** `ios-native/Leyne/AdBanner.swift` `AdConfig.forceTestUnitForRelease` must be manually flipped before each Archive:
- TestFlight: `true` + uncomment `#warning`
- App Store: `false` + re-comment `#warning`
The `#warning` surfaces during compile to prevent accidental App Store builds with the test unit. Default is `false` (App Store-safe). See `BUILDING.md`.

**Version source:** `ios-native/Leyne.xcodeproj/project.pbxproj` — `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` across all 3 targets (Leyne, LeyneWidgets, LeyneTests). As of 2026-05-29: `2.2.3` / `12`. Version bump is manual (edit pbxproj or Xcode project settings).

**App Store Connect:** Account `rommelsim@gmail.com`, bundle ID `com.leyne.Leyne`. Last submitted: v2.2.1+10 (with ads). Next archive pending.

**What is fully manual (no automation):**
- Ad toggle flip before each archive
- Archive via Xcode UI
- Upload via Xcode Organizer
- Version bump in pbxproj
- CHANGELOG.md + `kChangelog` in `AppModel.swift` update

## CI (GitHub Actions)

One workflow at `.github/workflows/ci.yml`. Runs on every push and PR.

- **android job** (ubuntu-latest): `flutter analyze` + `flutter test` + `flutter build apk --debug` — verifies compilation, no signing, no AAB.
- **ios job** (macos-latest): `flutter build ios --no-codesign --debug` — builds Flutter iOS wrapper only; does NOT build `ios-native/` (the active SwiftUI target).

Concurrency group `ci-${{ github.ref }}` cancels in-flight runs on new push — good runner-minute hygiene.

**Critical gap:** CI never builds or validates the native SwiftUI target (`ios-native/Leyne.xcodeproj`). Breakage there is invisible until Rommel tries to archive locally.

**Why:** Reference for understanding the full release pipeline before making any automation changes.
**How to apply:** Any recommendation to automate a step must account for the manually-managed keystore path (Android) and the ad-toggle ritual (iOS). The native iOS target is the active ship target — CI coverage there is zero.

Related: [[signing-and-secrets]], [[release-hygiene-gaps]]
