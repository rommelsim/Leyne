---
name: project-android-v2-audit
description: Full Android V2 Soft UI/UX quality audit findings — Material 3 violations, accessibility failures, missing platform idioms, prioritized P0–P3 — 2026-05-30
metadata:
  type: project
---

Comprehensive audit of `lib/screens/v2/` and `lib/widgets/v2/` conducted 2026-05-30. Findings are prioritized P0–P3.

## P0 — Accessibility / functional blockers

1. **Zero font scaling support** — `LyneTheme.mono()` and `LyneTheme.sans()` call `TextStyle(fontSize:)` with no `textScaler`/`textScaleFactor` clamping and no `MediaQuery.textScalerOf()` call anywhere in V2. The 56sp ETA numeral in `soft_bus_screen.dart:189` (`t.mono(56)`) will overflow its fixed-height 160dp `Container` at Large text scale — confirmed by the hardcoded `height: 160`. All `t.faint` text at 9–11sp fails WCAG AA at 0.35 opacity regardless of scale.
2. **`t.faint` contrast failure** — dark mode: F1EDE7 @0.35 on #15201C ≈ 2.1:1. Used at 10sp in `soft_settings_screen.dart:67` (version string), 9sp in `route_timeline.dart:162` (past-stop dot). Fails WCAG AA (4.5:1 required for <18pt text).
3. **No haptic feedback anywhere in V2** — `HapticFeedback.mediumImpact()` / `HapticFeedback.lightImpact()` is never called on any tap in the V2 screens or components. Material 3 recommends haptics on state-changing actions (bell toggle, ongoing card, sort chip). Android users lose the tactile confirmation they expect.
4. **Onboarding missing permission footnote** — `_OnbStep` at `onboarding_screen.dart:48–59` has no `footnote` field. iOS `OnbStep` has `footnote: String?` on steps 4 (location) and 5 (ads). Android users hit the system permission dialog with no preparatory warning text.

## P1 — Material 3 idiom violations

5. **`SoftToggle` is a custom iOS-style toggle, not `Switch`** — `soft_components.dart:147`. Uses `GestureDetector` with `AnimatedContainer` (44×26dp). Material 3 uses `Switch` widget (which provides correct track/thumb sizing, state ripple, TalkBack "Switch, on/off" announcement, and `SwitchTheme` integration). The custom toggle has no `Semantics` annotation — TalkBack announces nothing.
6. **`SortChipRow` uses `GestureDetector`, not `FilterChip`/`ChoiceChip`** — `soft_components.dart:98`. Material 3's `FilterChip`/`ChoiceChip` provide built-in selected state animation, ripple bounded to the chip shape, correct `Semantics` (role="radio" equivalent), and participate in `ChipTheme`. The custom `AnimatedContainer` has no semantics and no ripple.
7. **`_notifyButton` in `soft_bus_screen.dart:202` is an `InkWell`+`Container` pill, not a `FilledButton`** — a full-width primary action button should be `FilledButton.icon(...)` so it inherits `FilledButton`'s elevation response, `ButtonTheme` sizing, and `Semantics(button: true)`. Current implementation has no button semantics.
8. **`_busRow` InkWell ripple bleeds outside the parent `Container`** — `soft_stop_screen.dart:360`. The `InkWell` is a direct child of a `Container` (no `Material` ancestor) inside a `Column` inside another `Container`. Without a `Material` ancestor the ink splash clips to the nearest `PhysicalModel`, which in this case is the outer `Scaffold` — the ripple visually floods outside the card boundary.
9. **Page transitions use default `MaterialPageRoute`** — all push navigations in `soft_root.dart` use `MaterialPageRoute` without specifying a `PageTransitionsBuilder`. On Android 12+ the system default is `ZoomPageTransitionsBuilder` (predictive back motion). This is actually correct behavior — but it means the tab-swap `AnimatedSwitcher` uses a plain `FadeTransition` (`soft_root.dart:88`) rather than Material 3's `FadeForwards`/`SharedAxisTransition`, which is the correct idiom for tab switching. The current fade is flat and does not convey spatial hierarchy.
10. **Search screen uses raw `TextField` inside a custom `Material` pill, not `SearchBar`** — `soft_search_screen.dart:68`. Material 3 introduces `SearchBar`/`SearchAnchor` as the canonical search entry point (spec: M3 Search). The custom pill works but misses the M3 back-button affordance (it uses `Icons.arrow_back` inside `prefixIcon`, which is correct, but the border/shape doesn't match M3's 56dp search bar height spec).

## P2 — Visual hierarchy and density issues

11. **`_arrivalCard` fixed height 160dp breaks at large text scale** — `soft_bus_screen.dart:155`. The `Container` height is hardcoded. If system text scale is ≥1.4, the left-column `Eyebrow`+`Spacer`+`Eyebrow`+`Text` stack overflows the column, Spacer cannot give space, and the 56sp numeral right-column may clip.
12. **`_busRow` vertical padding is 6dp top+bottom** — `soft_stop_screen.dart:372` `EdgeInsets.fromLTRB(12, 6, 4, 6)`. The bell `IconButton` default touch target is 48dp (Material) but the row is visually only ~40dp tall at default text scale. The 4dp right padding also clips the bell ripple.
13. **AppBar title is 18sp w500 on Stop and Bus screens** — `soft_stop_screen.dart:52`, `soft_bus_screen.dart:59`. The screen has an in-content heading (26sp / 24sp) that already identifies the screen. The AppBar title duplicates this context but at a smaller size and does not update to the stop name (it reads "Stop 12345" vs the in-content h1 which reads the actual stop name). This creates redundant chrome that takes up 56dp and provides less information than the in-content header 8dp below it. The pattern contradicts M3's large-title scrolling AppBar pattern.
14. **Corner radii inconsistent across cards** — stop screen: primaryCard=24dp, otherBuses container=20dp, emptyCard=20dp, notifOffBanner=16dp. Home screen: PinCard=22dp. Nearby: row=20dp. Search: result=14dp. No single card radius — the 14dp on search results is noticeably smaller than the 20–24dp elsewhere. Should consolidate to one token (22dp is the brand value).
15. **`+N more arrivals →` is plain `Text`, not tappable** — `soft_home_screen.dart:280`. The `→` implies navigability but the tap target is the whole `_PinCard` (`InkWell` on the `Material`), which opens the stop screen. There is no visual distinction between this affordance link and static body text.
16. **Unicode `→` used as a UI glyph throughout** — `soft_home_screen.dart:354`, `soft_stop_screen.dart:283`, `soft_home_screen.dart:280`, `soft_stop_screen.dart:332`. Should be `Icon(Icons.arrow_forward, size: 12)` or `Icons.arrow_right_alt` so it scales with text and has correct optical weight.
17. **RouteTimeline `🔔 ALIGHT` chip uses emoji** — `route_timeline.dart:146`. Emoji rendering is platform-dependent, may be invisible with certain accessibility settings, and has no accessible label. Replace with `Icon(Icons.notifications_active, size: 10)` inline or prepend before the text with `Image.asset`.

## P3 — Polish and minor

18. **`_OnbVisualNotification` uses `Icons.phone_iphone`** — `onboarding_screen.dart:829`. This is an iOS-specific icon being rendered on Android. Replace with `Icons.smartphone` or `Icons.phone_android` to maintain platform neutrality in the mock.
19. **`_OnbVisualStack` step claims "Rename them. Reorder them."** but neither is implemented — `onboarding_screen.dart:73`. An unimplemented promise in onboarding erodes trust at first launch. Either remove the copy or gate step 1 behind the feature existing.
20. **No `Nearby` pull-to-refresh** — `soft_nearby_screen.dart` has no `RefreshIndicator`. The other three content screens (Home, Stop, Bus) all have it. Nearby is the most location-sensitive screen and the most likely to be stale.
21. **`SoftTabBar` Navigation indicator color is `t.liveBg`** — `soft_tab_bar.dart:29`. `t.liveBg` in dark mode is the deep forest-green `#0F2A20`. The M3 NavigationBar indicator is supposed to use `secondaryContainer` / a tonal color derived from `primary`. The current liveBg pill looks like a random "arriving" state tint, not a selected-tab indicator.
22. **Settings `_row` `InkWell` has no `borderRadius` clip** — `soft_settings_screen.dart:98`. The `InkWell` wraps `Padding` without matching the parent `Container`'s 22dp corner radius, so the ink ripple square-corners on the first and last rows of a section card.

## Root cause summary

The Android V2 UI looks lower-quality than iOS because: it uses custom replicas of native Material components (`SoftToggle` instead of `Switch`, `SortChipRow` instead of `ChoiceChip`, `InkWell`+`Container` pill instead of `FilledButton`) that have no semantics, no ripple, and no system integration — while iOS uses genuine platform controls (`Toggle`, `Picker`, native `NavigationBar`) that the OS renders correctly. The result is a screen that passes a visual design review but fails at every layer the OS normally handles for free.

**Why:** [[project-leyne-design-system]]
