---
name: section-g-icon-and-onboarding-order
description: Punch-list Section G (2026-07-03) — Android launcher icon replaced from iOS artwork via flutter_launcher_icons; onboarding-vs-splash ordering bug and its fix
metadata:
  type: project
---

Punch-list Section G (app-level, Android) landed 2026-07-03, uncommitted on
`design-remake`. Two independent items; both verified (build + tests), not
committed per instruction. See [[design-remake-branch-conventions]] for the
multi-agent file-ownership rule this was done under (scope: android/ res
dirs, pubspec.yaml dev deps, onboarding_screen.dart, launch_screen.dart,
main.dart only).

**Icon regeneration recipe** — reusable if the iOS AppIcon artwork changes
again: `flutter_launcher_icons` (pinned exact `0.14.4`, config in
`flutter_launcher_icons.yaml` at repo root, `ios: false` so it never touches
the iOS icon) reads `ios-native/Leyne/Assets.xcassets/AppIcon.appiconset/
AppIcon-Light.png` directly as `image_path` + `adaptive_icon_foreground`.
`adaptive_icon_background` is a flat hex sampled from the artwork's own
bottom edge (`#0052B4` for the current W-on-blue-gradient icon — resample if
the art changes, don't reuse this hex blindly). The tool's own `<inset>` XML
mechanism (default 16%, i.e. content scaled to the centre 68%) handles the
adaptive-icon safe-zone padding — do NOT assume it needs overriding; verify
with the actual glyph's bounding-box math against Android's documented
66dp/108dp safe-zone circle (`dist_from_center = hypot(dx,dy)` of the
glyph's bbox corner, compare to `33/108≈0.3056` after scaling by the inset
factor) before bumping `adaptive_icon_foreground_inset` — for this artwork
the default was already safe with ~5dp of margin, no override needed. The
Android 13+ themed/monochrome layer needs a SEPARATE image: a real
alpha-only glyph cutout (the OS discards RGB and tints by alpha), not the
full gradient square — extracted here via Pillow by thresholding
`min(r,g,b)` (background blue never exceeds r≈91 in this artwork). `sips`
was the instructed fallback tool but lacks a clean alpha-padding path;
Pillow was used instead for both the measurement and the monochrome
extraction — same deliverable, more reliable tool.

**Onboarding-splash ordering bug (root cause + fix, main.dart):**
`_AppRootState`'s `_launching` splash overlay was gated on
`_launching && onboardingDone` — meaning on a fresh install (onboardingDone
false) the elaborate `LaunchScreen` board-reveal animation never played at
all going in; instead it appeared for the FIRST TIME right after the user
tapped "Enter WhereSia" on onboarding's done step — i.e. AFTER both
permission primers had already fired. iOS's `RootView.swift` never had this
bug: `LaunchScreenView` sits at `zIndex(200)`, unconditional on
`m.showOnboarding`, so it always covers everything (including
`OnboardingView`, which is already mounted underneath) until it dismisses.
Fix was to drop the `&& onboardingDone` condition so `_launching` alone
gates the overlay, matching iOS's structure — first-run users now see the
splash, then onboarding's welcome step (which repeats the same wordmark/line
beat without the staged reveal — an intentional duplication, since iOS does
the exact same thing and the owner's directive was "animation first on both
platforms," not "no duplication"). Verified no permission request can fire
from underneath: `OnboardingScreen` has no `initState` side effects, and
`LocationService.startIfAuthorized()` (called from `SoftHomeScreen`/
`SoftMrtScreen` init, not from onboarding) never prompts — only
`requestAndStart()` does, and that's only reachable via a primer button tap,
which the splash's opaque `GestureDetector` blocks while it's up.
