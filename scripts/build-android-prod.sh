#!/usr/bin/env bash
# Builds the Android app bundle for a Play Store PRODUCTION upload.
#
# No LYNE_ADS_TEST flag → ad_banner.dart serves the real production
# banner unit (ca-app-pub-6816620800052795/4134673394, the verified
# personal Google AdMob account) and every impression / click earns.
# Only use this for the actual public release; closed-testing uploads
# must use build-android-closed-test.sh.
#
# Output: build/app/outputs/bundle/release/app-release.aab

set -euo pipefail
cd "$(dirname "$0")/.."

flutter build appbundle --release

echo
echo "✓ Production AAB ready (REAL ad unit baked in — do not let yourself click ads):"
echo "  build/app/outputs/bundle/release/app-release.aab"
