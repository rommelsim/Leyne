---
name: pipeline-hardening-recommendations
description: Concrete, prioritized recommendations to harden the Leyne build and release pipeline — ranked by impact vs effort for a solo developer
metadata:
  type: project
---

These are ordered by impact-to-effort ratio for a solo developer. High-ceremony solutions (Fastlane + Match, full GitOps) are noted but deprioritized unless the team grows.

## P1 — Add `xcodebuild` CI job for ios-native (high impact, low effort)

The native SwiftUI target at `ios-native/Leyne.xcodeproj` has zero CI coverage. A Swift compile error is invisible until Rommel opens Xcode.

**Add to `.github/workflows/ci.yml`:**
```yaml
ios-native:
  name: iOS native build
  runs-on: macos-latest
  steps:
    - uses: actions/checkout@v4
    - name: Build ios-native (no-sign simulator)
      run: |
        xcodebuild \
          -project ios-native/Leyne.xcodeproj \
          -scheme Leyne \
          -destination 'generic/platform=iOS Simulator' \
          -configuration Debug \
          CODE_SIGN_IDENTITY="" \
          CODE_SIGNING_REQUIRED=NO \
          build
```
This catches Swift compile errors and pbxproj misconfigurations on every push. Takes ~5-8 min on macos-latest. No signing secrets needed.

## P2 — Pin Flutter SDK version in CI (medium impact, low effort)

Currently `.github/workflows/ci.yml` uses `channel: stable` with no pinned version. A Flutter stable channel bump can silently break the build between pushes.

**Change in ci.yml:**
```yaml
- uses: subosito/flutter-action@v2
  with:
    flutter-version: '3.32.x'   # pin to current stable minor
    channel: stable
    cache: true
```
Re-pin when intentionally upgrading Flutter.

## P3 — Script the iOS version bump (medium impact, low effort)

iOS version lives in pbxproj across 6 config blocks. Partial bumps are a real risk.

**Add `scripts/bump-ios-version.sh`:**
```bash
#!/usr/bin/env bash
# Usage: ./scripts/bump-ios-version.sh 2.2.4 13
set -euo pipefail
MARKETING="$1"
BUILD="$2"
PBXPROJ="ios-native/Leyne.xcodeproj/project.pbxproj"
sed -i '' "s/MARKETING_VERSION = .*/MARKETING_VERSION = ${MARKETING};/" "$PBXPROJ"
sed -i '' "s/CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = ${BUILD};/" "$PBXPROJ"
echo "Bumped ios-native to ${MARKETING}+${BUILD}"
```
This ensures all 6 blocks update atomically.

## P4 — Add a pre-commit guard for the iOS ad toggle (medium impact, low effort)

`AdConfig.forceTestUnitForRelease = true` accidentally left in an App Store Archive means real users see test ads (revenue zero). The `#warning` helps but is a visual check only.

**Add `scripts/check-ad-toggle.sh`:**
```bash
#!/usr/bin/env bash
# Run before archiving for App Store. Exits non-zero if the test flag is on.
set -euo pipefail
if grep -q 'forceTestUnitForRelease = true' ios-native/Leyne/AdBanner.swift; then
  echo "ERROR: forceTestUnitForRelease is ON. Flip it to false before App Store Archive."
  exit 1
fi
echo "OK: forceTestUnitForRelease is false (App Store safe)."
```
Call this at the top of a future `archive-ios-appstore.sh` script.

## P5 — Store keystore as GitHub Actions secret for CI signed builds (medium impact, medium effort)

Currently signed AABs can only be produced on Rommel's machine. To enable CI-signed builds:

1. `base64 -i /Users/rommel/leyne-upload.jks | pbcopy` — copy base64 keystore.
2. Add GitHub Actions secrets: `KEYSTORE_BASE64`, `KEY_ALIAS` (`upload`), `KEY_PASSWORD`, `STORE_PASSWORD`.
3. Add step in ci.yml android job:
```yaml
- name: Decode keystore
  if: github.ref == 'refs/heads/main'
  run: |
    echo "${{ secrets.KEYSTORE_BASE64 }}" | base64 --decode > android/app/leyne-upload.jks
    cat > android/key.properties <<EOF
    storeFile=leyne-upload.jks
    storePassword=${{ secrets.STORE_PASSWORD }}
    keyPassword=${{ secrets.KEY_PASSWORD }}
    keyAlias=${{ secrets.KEY_ALIAS }}
    EOF
```
4. Update `build.gradle.kts` `storeFile` to use relative path `file("leyne-upload.jks")` instead of absolute.

This unblocks signed release builds in CI. Only needed when Fastlane/automated Play upload is desired.

## P6 — CHANGELOG enforcement via CI lint (low impact, low effort)

Add a step that checks `CHANGELOG.md` was modified on any push to `main`:
```yaml
- name: Check CHANGELOG updated
  if: github.ref == 'refs/heads/main'
  run: |
    git diff --name-only HEAD~1 HEAD | grep -q CHANGELOG.md || \
      echo "::warning::CHANGELOG.md was not updated in this commit."
```
Use `warning` not `error` — not all main commits are builds. This is an informational nudge, not a gate.

## P7 — ExportOptions.plist for scriptable iOS Archive (medium impact, medium effort)

Without an `ExportOptions.plist`, `xcodebuild -exportArchive` cannot be scripted. Add one at `ios-native/ExportOptions-appstore.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" ...>
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>JFQKT254NR</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadBitcode</key><false/>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
```
This enables: `xcodebuild -exportArchive -archivePath Leyne.xcarchive -exportPath ./export -exportOptionsPlist ios-native/ExportOptions-appstore.plist`

## NOT recommended (yet)

- **Fastlane Match** — certificate/profile management is working fine with Automatic signing for a solo developer. Match adds complexity without proportional benefit unless a second developer joins.
- **Fastlane Supply / Deliver** — Play Console and ASC uploads work manually. Automation makes more sense once release cadence increases above ~1/week.
- **GitHub Environments + approval gates** — overkill for a solo project.

**Why:** Solo developer project with irregular release cadence. Recommendations are scoped to the highest ROI improvements that reduce the chance of a bad build reaching users.
**How to apply:** Implement P1 first (zero-cost catch for the biggest CI blind spot). P2-P4 are all <30 min of work each. P5 only if CI-automated Play Console uploads become desired.

Related: [[release-hygiene-gaps]], [[signing-and-secrets]], [[build-release-setup]]
