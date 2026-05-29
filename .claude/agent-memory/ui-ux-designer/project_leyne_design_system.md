---
name: project-leyne-design-system
description: Leyne app design system tokens, platform conventions, "Soft" brand language, and V2 redesign status as of 2026-05-29
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

## Known Design Issues (current, as of 2026-05-29)

**Open:**
1. ETA "56pt" in SoftBusView arrivalCard: hardcoded `.system(size: 56)`, bypasses Dynamic Type entirely — highest-impact single fix
2. No Dynamic Type anywhere: `Theme.sans/.mono` use fixed `.system(size:)` with no `relativeTo:` text style; entire app fails iOS accessibility expectation
3. SoftToggle (Settings): 38×22pt — below iOS 44pt minimum; no VoiceOver switch trait/value
4. RouteTimeline rows and sort chip targets: ~28–36pt height — below 44pt minimum
5. `t.dim` (fg@0.6 opacity) and `t.faint` (fg@0.35) at 9–11pt mono captions: likely WCAG AA failures for small text
6. No `.contextMenu` on SoftPinCard — no rename/reorder/unpin affordance in Home
7. Search filter chips (Postal/BusNo/Place) fall through to name search — cosmetic only; Stop ID is the only functional filter
8. Alight scheduling (RouteTimeline tap-to-alert) writes UserDefaults but not wired to NotificationsManager (Phase 3 comment)
9. MRT alert cards: tap-to-dismiss has no undo, no haptic on iOS (SoftHomeView `fb.select()` on dismiss is correct but no `.sensoryFeedback`)
10. No pin reorder/rename from Home — onboarding promises "Rename them. Reorder them."

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
