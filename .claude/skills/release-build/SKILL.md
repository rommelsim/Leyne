---
name: release-build
description: >
  Cut a Leyne release build and keep version + changelog hygiene correct across
  both platforms. Use whenever the user asks to build, archive, ship, cut a
  release, bump the version, or produce an iOS Archive / Android AAB. Encodes the
  mandatory "every build updates the changelog" rule and the three changelog
  locations that must stay in sync.
---

# Leyne release build

Leyne ships two apps from one repo:

- **iOS** — native SwiftUI in `ios-native/` (Xcode project `ios-native/Leyne.xcodeproj`).
- **Android** — Flutter in `lib/`, built from the repo root.

The iOS and Android version trains are **independent** and often drift (Android
usually lags iOS until parity lands). Never assume they share a version.

## Golden rule

**Every AAB or Archive updates the changelog.** This is non-negotiable project
policy. A build without a changelog update is incomplete.

## Where versions live

| Platform | Marketing version | Build number |
|----------|-------------------|--------------|
| iOS | `MARKETING_VERSION` in `ios-native/Leyne.xcodeproj/project.pbxproj` (appears twice — Debug + Release; update both) | `CURRENT_PROJECT_VERSION` in the same file (both configs) |
| Android | `version:` in `pubspec.yaml`, format `X.Y.Z+build` (the `+build` is the versionCode; `android/app/build.gradle.kts` reads it via `flutter.versionName`/`flutter.versionCode`) | the `+build` suffix in `pubspec.yaml` |

⚠️ Android `versionCode` must be **strictly increasing** on Play. Some codes may
already be burned on the console even if not in git history — check before
reusing a number; when unsure, jump ahead rather than collide.

## The three changelog locations (keep in sync per platform)

1. **`CHANGELOG.md`** (repo root) — the canonical log. One section per version,
   tagged with platform + build artifact path. Add an entry for **every** build.
2. **iOS user-facing:** `kChangelog` in `ios-native/Leyne/AppModel.swift` — the
   What's New screen reads this. Add a `WhatsNewEntry` for any user-facing iOS
   version, keyed by the marketing version string.
3. **Android user-facing:** `kChangelog` in `lib/data/changelog.dart` — the
   What's New screen reads this. Add a `WhatsNewEntry` for any user-facing
   Android version. Convert SF Symbol names to the nearest Material `IconData`.

If the What's New entry for the running version is missing, the screen never
appears on update — so a user-facing release MUST have a matching entry.

## Steps

1. **Confirm scope.** Which platform(s)? What version + build number? What
   user-facing summary? If unstated, infer from the current versions and ask
   only if genuinely ambiguous.
2. **Bump the version** in the location(s) above for the target platform(s).
3. **Update `CHANGELOG.md`** with a new section: version, platform, build number,
   date, artifact path, and bullet summary of what changed.
4. **Update the user-facing changelog** (`kChangelog` in `AppModel.swift` for
   iOS, `changelog.dart` for Android) if the release is user-facing. Mirror the
   wording across platforms where the feature exists on both.
5. **Build:**
   - Android AAB: `flutter build appbundle --release` (output under
     `build/app/outputs/bundle/release/`).
   - iOS Archive: build via `xcodebuild archive` with the `Leyne` scheme, or hand
     off to the user for a signed Archive in Xcode if signing is interactive.
6. **Verify** the build succeeded and report the artifact path. Quote the new
   version/build numbers back to the user.

## Notes

- For deeper review of platform-specific code before shipping, delegate to the
  `ios-tech-lead` or `android-tech-lead` agent.
- Respect the platform-native design language — do not let iOS idioms bleed into
  Android or vice versa.
