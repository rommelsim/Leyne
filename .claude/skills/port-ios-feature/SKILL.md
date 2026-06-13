---
name: port-ios-feature
description: >
  Port a feature from the iOS app (native SwiftUI) to the Android app (Flutter),
  or close a specific Android parity gap. Use when the user asks to add an iOS
  feature to Android, bring Android up to parity on something specific, mirror an
  iOS screen/component on Android, or "make Android match iOS" for a named
  feature. iOS is the source of truth; Android mirrors it idiomatically.
---

# Port an iOS feature to Android

iOS (native SwiftUI, `ios-native/Leyne/`) leads; Android (Flutter, `lib/`)
follows. The job is to reproduce iOS behavior/visuals on Android **in idiomatic
Flutter**, not to transliterate Swift.

## Procedure

1. **Read the iOS reference first.** Find the SwiftUI source (usually under
   `ios-native/Leyne/V2/`) and understand layout, data, interactions, navigation,
   and states. It is the spec.
2. **Find the Android landing spots.** Locate the matching Flutter files under
   `lib/screens/v2/` and `lib/widgets/v2/`, plus any data layer it needs
   (`lib/data/`, `lib/state/app_model.dart`, `lib/services/`). Read neighbouring
   code so the new code matches existing style and state management (Provider /
   ChangeNotifier as the app already uses).
3. **Mirror it.** Build the Flutter equivalent. Reuse `lib/theme.dart` tokens.
   Match section order, copy, data shown, and navigation destinations to iOS.
4. **Wire navigation** if it's a new screen (tab in `widgets/v2/soft_tab_bar.dart`
   + mount in `screens/v2/soft_root.dart`; or a `Navigator.push` route for a
   detail screen — match the iOS push/present semantics).
5. **Verify:** run `flutter analyze` (must be clean) and `dart format` on changed
   files. Build only if analyze passes and a build is warranted.
6. **Report** per the iOS→Android mapping: files changed, how each iOS capability
   maps to your Android implementation, the analyze result, and any deliberate
   gaps left.

## Design rules (do not violate)

- **Monochrome design.** The app is greyscale; colour is reserved for **MRT line
  pills** and **crowd/occupancy** (green / amber / red). Don't introduce other
  hues.
- **Platform-native language.** Use Material idioms (`Dismissible`, bottom sheets,
  `SnackBar`, Material icons) — don't force SwiftUI metaphors. But keep the
  *behavior* and *information* identical.
- **Timely over honest.** Uncertainty is a whisper (a faint `~`), never a banner.

## Do NOT port (iOS-exclusive)

- The **bus-view map** (Android has no map — use the route-progress bar) and
  **MapHandoffToast**.
- **ATT** (Android uses UMP consent), **Live Activities, widgets, WeatherKit,
  Spotlight, Siri**, symbol-bounce animations, true system share sheet, iOS-26
  glass chrome.

## Boundaries

- **Don't bump versions or edit changelogs here** — that's `release-build` /
  `changelog-update`, run when the build is actually cut.
- For deeper Flutter architecture decisions, delegate to the `android-tech-lead`
  agent.
- To first discover *what* needs porting, run the `parity-audit` skill.
