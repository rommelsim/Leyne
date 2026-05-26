#!/usr/bin/env bash
# Builds the Android app bundle for a Play Store CLOSED-TESTING upload.
#
# Forces Google's reserved test banner unit
# (ca-app-pub-3940256099942544/6300978111) by passing
# --dart-define=LYNE_ADS_TEST=true. Testers see the always-test creative,
# so accidental taps can never trigger AdMob's invalid-traffic detection
# against your real ad unit.
#
# Use this for every closed-testing AAB. For the production upload run
# build-android-prod.sh instead.
#
# Output: build/app/outputs/bundle/release/app-release.aab

set -euo pipefail
cd "$(dirname "$0")/.."

flutter build appbundle \
  --release \
  --dart-define=LYNE_ADS_TEST=true

echo
echo "✓ Closed-test AAB ready (test ad unit baked in):"
echo "  build/app/outputs/bundle/release/app-release.aab"
