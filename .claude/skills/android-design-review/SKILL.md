---
name: android-design-review
description: >
  Review Leyne's Android Flutter UI against Material 3 (Material You) guidelines
  and this app's design language. Use when the user asks to check Android/Material
  design, validate the Flutter UI, audit a screen for Material 3 compliance, review
  colour-roles/type-scale/components/motion/accessibility, or "make it feel like a
  proper Android app." Produces a per-dimension scorecard, findings with file:line,
  and a prioritised fix list. Android/Flutter only — for SwiftUI/HIG use
  ios-design-review.
---

# Android design review (Flutter · Material 3)

Review the Android app against **Material 3 (Material You)** *and* Leyne's design
language. Features must reach parity with iOS, but the **design is platform-native**:
express it in Material idioms, never as a pixel copy of the SwiftUI app. Copying an
iOS pattern that fights Material (e.g. an iOS-style grouped list where a Material
list/Card belongs, an iOS back-chevron instead of the system/predictive back) is a
finding.

## Where the UI lives

- **Active redesign (default):** `lib/screens/redesign/` — `redesign_app` (root),
  `redesign_home`, `redesign_detail` (Stop/Station/Route), `redesign_route_timeline`,
  `redesign_more` (Lines/Saved/Switch/Settings), `redesign_overlays`
  (Search/Live-Update/Toast), `redesign_common` (shared widgets), `redesign_theme`
  (`rdText`, `RdTokens`), `redesign_bridge` (live-data adapters). Wired as
  `LyneApp`'s default `home:`; `LegacyAppRoot` is the fallback shell.
- **Production "Soft" UI:** `lib/screens/v2/` + `lib/widgets/v2/`.
- Fonts: bundled **Hanken Grotesk** (`assets/fonts/`) + `material_symbols_icons`.

Read the actual Dart — never review from screenshots alone.

## Leyne's design language (local rules — check first)

Semantic colour is shared with iOS, but **map it onto Material colour roles**:

1. **Colour meaning** — green = arriving / seats / live; per-line MRT colour =
   line identity; error/red = disruption / packed; amber/tertiary = caution /
   standing. **`colorScheme.primary` is for interaction** (FAB, filled buttons,
   selected nav) — not for status text.
2. **Honesty** — never fabricate data LTA doesn't publish (train ETAs, first/last
   train, exits/facilities). Show what's real; uncertainty is a quiet "~".
3. **Restraint** — don't stack redundant cues; prefer hierarchy over borders.
4. **Parity, not mimicry** — the screen must *do* what iOS does, but *look* Material.

## Material 3 dimensions & concrete checks

Score each 1–10; cite `file:line` for every miss.

### 1. Colour roles & dynamic colour
- Use M3 **colour roles**, not hard-coded hex: `primary / onPrimary /
  primaryContainer / onPrimaryContainer`, `secondary*`, `tertiary*`, `error*`,
  `surface / surfaceContainer(Low/High/Highest) / onSurface / onSurfaceVariant`,
  `outline / outlineVariant`. Check `RdTokens`/`redesign_theme` expose these.
- Support **dynamic colour** where reasonable, and both light + dark. Every
  `on*` pairs with its container for contrast (≥4.5:1 body, ≥3:1 large).
- Surfaces use **tonal elevation** (surface-tint), not just drop shadows.

### 2. Type scale
- Use the M3 type scale — display / headline / title / body / label, each
  Large/Medium/Small — expressed via `rdText`/`TextTheme`. Flag ad-hoc font sizes
  that don't ladder to the scale.
- One dominant element per screen; supporting text steps down clearly.
- Respect `MediaQuery.textScaler` (font scaling) — no clipping at large scale.

### 3. Components (use the real Material widgets / idioms)
- Buttons: Filled / Filled-tonal / Outlined / Text / Icon — correct emphasis for
  the action. One primary action per screen.
- Cards: elevated / filled / outlined used intentionally (not a card around every row).
- Lists: `ListTile`-style rows with correct leading/trailing + dividers; 3-line max.
- Chips (assist/filter/input), Segmented buttons for mutually-exclusive choices.
- **NavigationBar** (M3) for top-level tabs — not a custom iOS tab bar; correct
  active indicator pill + label behaviour.
- Top app bar (small/center/large) with correct scroll behaviour.
- **FAB / extended FAB** for the primary create/track action where it fits Material.

### 4. Shape
- Corner radii follow the M3 shape scale: xs 4 · sm 8 · md 12 · lg 16 · xl 28.
  Flag arbitrary radii. Components use their canonical shape (FAB large, chips full).

### 5. Elevation & state layers
- Elevation levels 0–5 used per component role; interactive surfaces show a
  **state layer** (hover/focus/pressed) — i.e. **`InkWell`/`InkResponse` ripple**
  on every tappable area. A tappable `Container` with no ripple is a finding.

### 6. Motion
- Use Material motion: emphasized easing, standard durations (short 50–200ms,
  medium 250–400ms, long 450–600ms). Transitions have direction/meaning
  (shared-axis for peer nav, container-transform for open-detail).
- **Predictive back** (Android 14+) not broken by custom `PopScope` handling —
  cross-check the known back-exit pitfall (`OnBackInvoked`/`setFrameworkHandlesBack`).

### 7. Touch targets & density
- **Minimum 48×48dp** for every interactive element (`InkWell` padding / `IconButton`
  / `minimumSize`). Comfortable density; adequate spacing.

### 8. Layout, insets & edge-to-edge
- Edge-to-edge with correct **system-bar insets** (`SafeArea` / `MediaQuery.padding`);
  content not under the status/nav bars or the gesture pill.
- Consistent margins (16dp Material grid) and a clear vertical rhythm.

### 9. Accessibility
- `Semantics` / `Tooltip` / `IconButton(tooltip:)` on icon-only controls (TalkBack).
- Colour never the only signal (crowd = dot **and** text).
- Works at large font scale; honours reduce-motion.

### 10. Content, empty & loading, consistency
- Every async view has empty + loading states (skeleton/spinner), no blank flash.
- Friendly, honest copy (local rule 2).
- Same concept looks the same across screens (one shared arrival-row widget).

## How to run the review

1. List `lib/screens/redesign/`; read the files relevant to the request (or all).
   Read `redesign_theme` for the token/colour-role setup.
2. Walk the 10 dimensions; record passes, cite misses as `path:line — problem — fix`.
3. Optional: `flutter run` / screenshot in light **and** dark to confirm contrast,
   ripples and insets.
4. For a big audit, fan out one reviewer per dimension (Agent tool) and merge.

## Output format

- **Scorecard** — the 10 dimensions ×/10 + one-line verdict + overall.
- **Findings** — Blocker / Should-fix / Polish, each with `file:line` + the fix.
  Call out any **iOS-idiom bleed** (patterns that should be re-expressed in Material).
- **What's strong** — 3–5 keeps.
- End with the single highest-leverage change.
