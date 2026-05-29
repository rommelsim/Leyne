---
name: signing-and-secrets
description: Signing configuration and secrets hygiene for both platforms — what is safe, what is risky, what needs hardening
metadata:
  type: project
---

## Android signing

**Keystore:** `/Users/rommel/leyne-upload.jks` — absolute path on Rommel's local machine. Upload key alias: `upload`.

**CRITICAL — key.properties contains plaintext passwords:**
```
storePassword=oldDog98
keyPassword=oldDog98
keyAlias=upload
storeFile=/Users/rommel/leyne-upload.jks
```
The file IS gitignored (`.gitignore` has `/android/key.properties`, `*.jks`, `*.keystore`). Git history clean — `git ls-files android/key.properties` returns empty. File is not tracked. This is the correct state; do not commit this file.

**CI gap:** The keystore is not available in CI. `build.gradle.kts` handles this gracefully — falls back to debug signing when `key.properties` is absent. CI builds a debug APK, not a signed release AAB. Signed AABs can only be produced on Rommel's machine or a CI runner that has the keystore injected as a secret.

**LTA API key (both platforms):**
- Dart (`lib/data/lta_config.dart`): hardcoded fallback key `+6zJ3XstTqOcDkvczHttWA==` with `--dart-define=LTA_API_KEY` override. Key embedded in source, in the repo.
- Swift (`ios-native/Leyne/LTAConfig.swift`): hardcoded directly in source: `static let accountKey = "+6zJ3XstTqOcDkvczHttWA=="`.
- **Risk level: Low.** LTA DataMall keys are public open-data / rate-limited. The key appears in the README. No financial or auth risk. Acceptable for this project scope. Per code comment: "DataMall keys are low-sensitivity (public open-data, rate-limited) so embedding is acceptable."

**AdMob IDs (both platforms):**
- AdMob App IDs and banner unit IDs embedded in source (`AdBanner.swift`, `ad_banner.dart`, `LeyneInfo.plist`, `AndroidManifest.xml`). These are public by nature (visible in compiled app binary). Not a security risk. Standard practice.

## iOS signing

- CODE_SIGN_STYLE = Automatic — Xcode manages provisioning profiles automatically. Works correctly for single-developer workflow with Rommel's Apple ID.
- DEVELOPMENT_TEAM = JFQKT254NR (hardcoded in `project.pbxproj`). Fine — team ID is not a secret.
- No `ExportOptions.plist` exists, so `xcodebuild -exportArchive` cannot be scripted without creating one.
- No CI signing — the `ios job` in CI uses `--no-codesign`. Signed archives can only be produced on a Mac with Rommel's Apple ID signed into Xcode.

## Summary risk table

| Item | Location | Committed? | Risk |
|---|---|---|---|
| Android keystore password | `android/key.properties` | NO (gitignored) | Low — local only |
| Android keystore file | `/Users/rommel/leyne-upload.jks` | NO | Low — local only |
| LTA API key | `LTAConfig.swift`, `lta_config.dart` | YES | Low — public open-data key |
| AdMob IDs | Multiple source files | YES | None — public by design |
| Apple Team ID | `project.pbxproj` | YES | None — not a secret |

**Why:** Knowing what is and isn't committed prevents accidental secret rotation or unnecessary alarm.
**How to apply:** If CI needs to produce a signed AAB (e.g., for automated Play Console upload), the keystore must be base64-encoded and stored as a GitHub Actions secret, then written to disk in CI before the build step. Do not commit key.properties.

Related: [[build-release-setup]], [[pipeline-hardening-recommendations]]
