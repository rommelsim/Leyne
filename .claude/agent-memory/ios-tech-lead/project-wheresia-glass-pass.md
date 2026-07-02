---
name: project-wheresia-glass-pass
description: 2026-07-02 Liquid Glass chrome pass on ios-native/Leyne/WhereSia/ (branch design-remake) — decisions, what changed, what's still open
metadata:
  type: project
---

Owner-directed Liquid Glass + audited UI-fixes pass landed on `ios-native/Leyne/WhereSia/` (branch `design-remake`), uncommitted in the working tree as of 2026-07-02. Builds clean (Debug + Release, iOS Simulator, zero warnings from any WhereSia file).

**Chrome architecture decisions** (relevant to any future WhereSia chrome work):
- Tab bar (`WSRoot.swift` `WSTabBar`): kept the custom 4-tab mono-label layout, NOT native `TabView` — rendered as a floating capsule via a new `wsGlassChrome(cornerRadius:tint:)` helper in `WSTheme.swift` (real `glassEffect(.regular.tint(...))` on iOS 26, `.ultraThinMaterial` + tint fallback ≤25). Composed via `.safeAreaInset(edge: .bottom)` on the tab-switch `Group`, not a manual `ZStack` + fixed `.padding(.bottom, 76)` — this is what lets scroll content actually reach and show through the glass at the bottom of a list, not just stop short of it.
- Screen headers (`WSBusStopView`/`WSMrtStationView`/`WSServiceInfoView`/`WSTrackBusView`, all 4 pushed destinations): switched from in-body `WSHeaderBar` view to a `.wsHeaderBar(eyebrow:onBack:trailing:)` **view modifier** (`WSComponents.swift`) that drives a real `.toolbar` (leading/principal/trailing) with the nav bar left *visible* (only `navigationBarBackButtonHidden(true)`, not `.toolbar(.hidden)`). This gets real system Liquid Glass nav-bar chrome for free AND restores the interactive edge-swipe-back gesture natively — hiding the back *button* doesn't kill that gesture, only hiding the whole bar (the prior approach) did. The `enableSwipeBack()` hack (still defined in `V2/SoftRoot.swift`, still used by non-WhereSia Soft* views — do not delete it) is no longer called anywhere in WhereSia.
- Tab ROOT screens (Home/Saved/Alerts/Me) keep their own inline custom header — untouched, out of scope (task 1b was specifically about the pushed-destination `WSHeaderBar`).
- Search (`WSRoot.swift`): `.fullScreenCover` → `.sheet` + `.presentationDetents([.large])` + `.presentationBackground(.ultraThinMaterial)`.

**Contrast**: `WSTheme.dim` token already existed pre-pass (added by an earlier, already-approved font/motion commit) and already clears WCAG AA 4.5:1 against `bg` in both themes (~6.06:1 dark, ~4.83:1 light) — the fix was swapping specific `ws.faint`-on-real-content spots to `ws.dim` (tab bar labels, "AT THIS STOP", "· scheduled", live-attribution footer, MRT crowd hint, `WSSectionHeader` meta, Home's "—" empty-ETA dash, TrackBus passed-stop names), not inventing a new token. `ws.faint` stays correct for pure decoration (chevrons, toggle knob, timeline rail dashes).
- **Known near-miss, not fixed (flag if revisited)**: `dim` on `panel` (not `bg`) in **light** theme computes to ~4.47:1 — just under 4.5:1 AA (vs ~4.83:1 on raw `bg`). Affects `WSCard` titles/`WSKV` keys etc. in light mode. Didn't touch `WSTheme`'s dim/light hexes since it wasn't in the explicit task scope and is an owner-approved token; worth a follow-up if a strict a11y audit is ever run.

**Not addressed (flagged, out of explicit scope)**: icon-only buttons (`WSHairButton`, tab items) have no explicit `.accessibilityLabel` — `WSIcon` is unconditionally `.accessibilityHidden(true)`, so VoiceOver gets no name on these. Pre-existing gap, not introduced by this pass; worth a dedicated a11y audit.

**Mechanical**: all 17 `.foregroundColor(` → `.foregroundStyle(` (incl. `Text` concatenation spots — `Text.foregroundStyle` has a dedicated overload returning `Text` so `+` concatenation still works). `WSIcon`'s hand-rolled pulse replaced with `.symbolEffect(.pulse, isActive:)`. `WSMrtStationView`'s `UIScreen.main.bounds`-based gauge width replaced with a local `GeometryReader`. Bendy bus (`WSGlyph.busBendy`) now `"bus.fill"` (SF Symbols has no articulated-bus glyph; differentiated via the filled variant vs `busSingle`'s outline). `WSTrackBusView`'s route-loading `Task{}` moved from `.onAppear` into `.task` so it cancels on pop.

Simulator device names on this machine: no "iPhone 16" exists (SDK is iOS 26.5 / Xcode 26.5) — use `iPhone 16e`, `iPhone 17`, `iPhone 17 Pro`, etc., or resolve by `id=` UUID via `xcrun simctl list devices`.
