#!/usr/bin/env bash
# Builds the Android app bundle for a Play Store PRODUCTION upload.
#
# Passes --dart-define=LYNE_ADS_TEST=false explicitly (also the source default
# in ad_banner.dart) so the app serves the real production banner unit
# (ca-app-pub-5864511655536507/6513878972, the leyne0000 Google AdMob account)
# and every impression / click earns. Belt-and-suspenders: explicit here so the
# prod AAB never silently depends on the source default.
# Only use this for the actual public release; closed-testing uploads
# must use build-android-closed-test.sh.
#
# Output: build/app/outputs/bundle/release/app-release.aab

set -euo pipefail
cd "$(dirname "$0")/.."

flutter build appbundle --release --dart-define=LYNE_ADS_TEST=false

echo
echo "✓ Production AAB ready (REAL ad unit baked in — do not let yourself click ads):"
echo "  build/app/outputs/bundle/release/app-release.aab"
