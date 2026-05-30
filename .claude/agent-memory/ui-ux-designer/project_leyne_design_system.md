---
name: project-leyne-design-system
description: Leyne app design system tokens, platform conventions, "Soft" brand language, and V2 redesign status as of 2026-05-30
metadata:
  type: project
---

Leyne is a Singapore LTA bus/MRT arrival-times app with two codebases:
- Flutter/Android in `lib/` (Material 3)
- SwiftUI native iOS in `ios-native/` (iOS 26 Liquid Glass)

## Design Tokens

- Warm dark bg: #15201C / warm light bg: #F4EFE7
- Mint accent (`t.accent`)
- Token names: `t.bg`, `t.fg`, `t.dim`, `t.faint`, `t.surface`, `t.surfaceHi`, `t.liveBg`, `t.live`, `t.line`, `t.accent`, `t.onAccent`, `t.meBlue`
- Fonts: `t.sans()`, `t.mono()` — custom sans + mono ramps
- Both platforms share token *names* but resolve to platform-appropriate implementations

## "Soft" Brand Language

Shared custom visual design across platforms: rounded 16–22pt cards, mono eyebrows (11pt, tracking 1.4), ServiceBadge chips, sort-chip rows, GlassPillButton back/action pills, warm surface fills, accent-coloured live state. **The brand layer is intentionally shared; only navigation chrome is platform-native.** See [[project-soft-design-language]] for the resolution on this.

## V2 Redesign Status (as of 2026-05-29)

iOS V2: 6 screens live in `ios-native/Leyne/V2/` behind `leyne.softUI` flag:
- SoftHomeView, SoftNearbyView, SoftStopView, SoftBusView, SoftSearchView, SoftSettingsView
- Plus primitives: SoftPrimitives.swift, IOSGlassPill.swift, SoftTabBar.swift, SoftRoot.swift
- Uses native iOS 26 TabView with Liquid Glass tab bar (`.search` role detach)
- GlassPillButton for back/action pills on pushed views
- `softTopEdgeBlur()` extension restores scroll-edge blur when nav bar is hidden

Flutter V2: 7 screens in `lib/screens/v2/` — uses Material 3 bottom nav, FAB, AppBar

## Platform Convention (STRICT)

- iOS: Liquid Glass, GlassPillButton, native TabView, `.regularMaterial` fills, no AppBar
- Android: Material 3 NavigationBar, FAB, AppBar, FilledButton, OutlinedButton
- Per project rule: NO cross-platform idiom bleed between iOS and Android *controls/affordances*
- Brand visuals (cards, chips, mono eyebrows, warm palette) are exempt — they are intentional brand language, not idiom bleed

## Soft Language Consistency Across V2 Views (2026-05-29 audit)

Highly consistent across all three audited views:
- All use `t.surface` / `RoundedRectangle(cornerRadius: 22, style: .continuous)` for cards
- `Eyebrow` component used consistently (mono 11pt, tracking 1.4, `t.dim`)
- GlassPillButton used on all pushed views (Back + primary action, top-left/right)
- PressScaleButtonStyle on SoftPinCard tappable card — not on SoftBusView/SoftStopView list rows (acceptable: list rows are visually bounded)
- MRT alert cards missing press feedback (no buttonStyle set, uses `.plain` but no scale)
- SortChipRow used in SoftStopView; not needed in others — appropriate
- `t.liveBg` tint on tracked/live rows — consistent across Home card rows, Stop bus rows, Bus notify button

One inconsistency: SoftBusView `arrivalCard` ETA numeral uses `.system(size: 56, weight: .regular, design: .monospaced)` (hardcoded) while all other body text goes through `t.mono()`. This is the only hardcoded size in the audited views.

## Known Design Issues (current, as of 2026-05-30 — re-verified against code)

**Open (re-verified 2026-05-30):**
1. ETA "56pt" in SoftBusView arrivalCard: CONFIRMED hardcoded `.system(size: 56, weight: .regular, design: .monospaced)` at line 145. Flutter equivalent also hardcoded via `t.mono(56)` in soft_bus_screen.dart. Both bypass Dynamic Type.
2. No Dynamic Type anywhere: `Theme.swift` `sans()` and `mono()` use `.system(size:)` with no `relativeTo:` — confirmed in Theme.swift lines 72–77. Entire iOS app fails. Flutter `theme.dart` same pattern.
3. SoftToggle (iOS, Settings): CONFIRMED 38×22pt at SoftPrimitives.swift:28. Used in SoftSettingsView via `SoftToggle(t: t, value: binding)`. No `.accessibilityAddTraits(.isToggle)` — no system switch trait or value announced by VoiceOver. `buttonStyle(.plain)` means no a11y default.
4. `GlassPillButton` hit target: 14pt H-padding + 8pt V-padding + 13pt font ≈ 29pt tall — below 44pt. Back pill and Pin pill on Stop/Bus views both affected.
5. `t.dim` (opacity 0.6) and `t.faint` (opacity 0.35) at 9–11pt mono captions: likely WCAG AA failures. `t.faint` specifically: dark mode fg=F1EDE7 at 0.35 on bg=15201C ≈ 2.1:1 contrast — fails AA (4.5:1 required for <18pt text).
6. Search filter chips: CONFIRMED FIXED on iOS (SoftSearchView now routes each chip to a distinct code path: postal → GeocodeService, busNo → searchServices, stopID/place → searchStops). Flutter `soft_search_screen.dart` still routes ALL chips to `DataStore.shared.searchStops(query)` — the 2026-05-30 fix note confirms this gap is open on Android.
7. Alight scheduling: CONFIRMED FIXED — SoftBusView.scheduleAlight now calls `m.setActiveAlight(busNo:stopCode:stopName:fireAt:)` (lines 425-440). No longer a UserDefaults stub.
8. MRT alert dismiss: no haptic/sensory feedback annotation on the dismiss `Button` in SoftHomeView. `fb.select()` is called, but that triggers the `Feedback` system-sound, not a UIKit `.selectionChanged` haptic. No `.sensoryFeedback` modifier in SoftHomeView.
9. No pin reorder/rename: confirmed — no `.contextMenu` on SoftPinCard, no `ForEach` with `.onMove` / `.onDelete`. Onboarding step 1 still promises "Rename them. Reorder them."
10. SoftSettingsView: uses `.navigationTitle("Settings")` + `.toolbar(.visible, for: .navigationBar)` — introduces a system NavigationBar on the Settings tab root, inconsistent with other tab roots (Home, Nearby, Search) which suppress the nav bar. Also confirms navigation title duplication: the in-content `Text("Settings")` heading and the nav bar title render simultaneously.
11. Android SoftHomeScreen home refresh: CONFIRMED FIXED — uses `Future.wait(pins.map(...refreshArrivals))` (fan-out). iOS SoftHomeView still uses sequential `for pin in m.pins { await }` loop — N×latency bug still open on iOS.
12. `_OnbStep` in Flutter onboarding_screen.dart: CONFIRMED no `footnote` field. iOS OnbStep has `footnote: String?` (confirmed lines 6-10 of OnboardingView.swift). Steps 4 and 5 carry footnote callouts on iOS; Android drops them.

**Resolved (as of 2026-05-29):**
- Per-bus bell alert toggle on SoftStopView (closes onboarding promise)
- Track-all pill on SoftStopView (master arm/clear)
- SoftBusView fake clock ETAs removed from RouteTimeline
- SoftBusView live bus position: honest "not shared yet" caption; `MapBusMarker` removed
- SoftBusView `Service.monitored` surfaced in `liveSchedTag`
- SoftBusView "Following" eyebrow relabeled
- SoftSettingsView rewritten to native inset-grouped List
- Partial VoiceOver: SoftStopView bell buttons + master pill have `.accessibilityLabel`; SoftBusView liveStatusChip + notifyButton + stop map marker have labels
- Pull-to-refresh (`.refreshable`) live on SoftHomeView, SoftStopView, SoftBusView
- iOS PIN chip: only shows when nickname is non-empty and differs from stop name (correct)

**Why:** V2 is the flagship redesign; design parity at feature level is intentional; component-level parity is not required (platform-specific implementations are correct).
