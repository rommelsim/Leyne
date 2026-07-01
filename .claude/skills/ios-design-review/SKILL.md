---
name: ios-design-review
description: >
  Review Leyne's native iOS SwiftUI UI against Apple's Human Interface Guidelines
  and this app's own design language. Use when the user asks to check iOS design,
  validate the design language, audit a SwiftUI screen for HIG compliance, review
  spacing/typography/colour/navigation/accessibility, or "make sure it feels
  native / like an Apple app." Produces a per-dimension scorecard, concrete
  findings with file:line, and a prioritised fix list. iOS only — for Material /
  Flutter use android-design-review.
---

# iOS design review (SwiftUI · HIG)

Review the iOS app against **Apple's HIG** *and* Leyne's established design
language. iOS is the design source of truth for this project, so this review sets
the bar the Android app is later held to.

## Where the UI lives

- **Active redesign (default):** `ios-native/Leyne/Redesign/` — `RedesignRoot`,
  `RedesignHome`, `RedesignDetail` (Stop/Station/Route), `RedesignRouteTimeline`,
  `RedesignMore` (Lines/Saved/Switch/Settings), `RedesignOverlays` (Search/Live
  Update/Toast), `RedesignCommon` (shared: `RDArrivalRow`, `RDSym`, `RDDot`,
  `RDCircleButton`), `RedesignTokens` (`rdFont`, `RDTokens`), `RedesignBridge`
  (live-data adapters). Gated by `RedesignFlags.enabled` in `RootView`.
- **Production "Soft" UI:** `ios-native/Leyne/V2/` (shown when the flag is off).
- Shared chrome: `Theme.swift` (`MRTLine` colours), `ios-native/Leyne/AppModel.swift`.

Read the actual files — never review from screenshots alone. Screenshots confirm;
code is the source of truth (and reveals Dynamic Type, a11y, tap targets).

## Leyne's design language (the local rules — check these first)

These are owner-approved decisions; a violation is a finding even if it's "HIG-ok":

1. **Semantic colour, blue reserved for interaction.**
   - Green (`t.bus`) = arriving / seats-available / live.
   - Orange = MRT line identity (per-line via `MRTLine.color`).
   - Red (`t.mrt`) = disruption / packed / critical.
   - Amber (`t.amber`) = caution / standing / "some crowd".
   - **Blue (`t.primary`) = interactive controls only** — tab selection, links,
     primary buttons. NOT status (an ETA is not blue; "Now" is green).
2. **Apple-Maps-style grouped list**, not cards. Flat rows + hairline dividers
   (full-bleed = section, inset-78 = item). The only filled surfaces allowed:
   bus-number badge, MRT accent bar, and primary controls (Save/Notify/Search).
3. **Navigation motion:** every push slides **right→left**; every pop (back button
   *or* edge swipe) slides **left→right**. Consistent across all screens.
4. **ETA hierarchy:** ETA dominates each arrival row; `Now` (green) when arriving,
   else neutral number; destination secondary; occupancy tertiary (dot + text).
5. **Honesty:** never fabricate data. If LTA doesn't publish it (train ETAs, first/
   last train, station exits/facilities), don't invent it — say what's shown
   instead. Uncertainty is a quiet "~", never a loud banner.
6. **Restraint:** fewer colours, fewer borders, more hierarchy. A control that
   duplicates an existing cue (e.g. a "live" dot next to a green "Now") is a finding.

## HIG dimensions & concrete checks

Score each 1–10. For every miss, cite `file:line` and the fix.

### 1. Typography & Dynamic Type
- All redesign text goes through `rdFont(_:_ :)` (scales via `UIFontMetrics`). Flag
  any raw `.font(.system(size:))` or fixed sizing that bypasses it.
- Clear hierarchy: one dominant element per view (title OR ETA), supporting text
  dialed back (weight + colour, not just size).
- No more than ~3–4 weights on a screen. Overuse of `.heavy/.black` is a finding.
- Line limits + `minimumScaleFactor` on names that can overflow.

### 2. Colour & Dark Mode
- Resolve `RDTokens` for both light and dark (`RDTokens.resolve(dark:seed:premium:)`);
  check text-on-surface contrast in both. Every `t.accent` fill pairs with an
  `onAccent`/legible foreground.
- Apply the semantic-colour rules above. Grep for `t.primary`/blue used on
  non-interactive status.
- Contrast target: body text ≥ 4.5:1, large text ≥ 3:1 against its surface.

### 3. Layout, spacing & touch targets
- **Minimum 44×44pt** hit target for every tappable control (`.frame` + `.contentShape`).
- Consistent margins (18pt horizontal is the redesign's grid) and vertical rhythm.
- Respect safe areas; no content under the notch / home indicator; `.ignoresSafeArea`
  used deliberately (maps/backgrounds only).
- No fixed-width containers that clip at large Dynamic Type.

### 4. Navigation & motion
- Push right→left, pop left→right (see local rule 3). Verify in `RedesignRoot`
  (`screensLayer`/`onChange(of: m.screen)`), including the edge swipe-back.
- No flicker / double-`onAppear` on push (screens keyed once).
- Transitions purposeful, ~0.3–0.45s, spring or easeOut; nothing that janks or
  blocks input.
- Back is always reachable (button + swipe). `canHandleBack` correct.

### 5. Controls, feedback & materials
- Prefer standard affordances; buttons look tappable. Selected states are subtle
  (tint), not a full filled row.
- Haptics on meaningful actions (`Feedback`/`fb.select()`), not on scroll.
- Floating controls (Notify pill) hover with a soft shadow / material, not flat.
- Lists use the inset-grouped idiom (dividers), not stacked cards.

### 6. Accessibility
- Every icon-only control has an `.accessibilityLabel`.
- Works at the largest Dynamic Type size without clipping the primary content.
- Honour Reduce Motion where a big animation exists.
- Colour is never the *only* signal (crowd = dot **and** text; disruption = icon +
  copy + colour).

### 7. Content, empty & loading states
- Every async view has an empty state and a loading state (no blank flash).
- Copy is friendly and honest (rule 5), not developer-ish ("Live train arrivals
  aren't available" → "Showing live line status…").
- Numbers formatted for humans ("Now", "3 min", "Next 14 min").

### 8. Consistency
- The same concept looks the same everywhere (arrival row = `RDArrivalRow` on Home
  **and** Stop; badges, headers, freshness indicators identical). Divergence between
  two screens for the same element is a finding.

## How to run the review

1. List the redesign files; read the ones relevant to the request (or all, for a
   full audit). Also read `RedesignTokens` + `Theme` for the colour system.
2. Walk each of the 8 dimensions; for each, note passes and cite misses as
   `path:line — problem — fix`.
3. Optional: build + capture screenshots to confirm layout/contrast in light **and**
   dark (`RD_DARK=1`). Deep-link via the dev hooks: `SIMCTL_CHILD_RD_PHASE=app
   SIMCTL_CHILD_RD_SCREEN=<map|stop|station|route|lines> [RD_SVC / RD_STOP /
   RD_STATION / RD_DARK / RD_SEED]`. Note the recurring sim "Open in SG Transit?"
   dialog is an artefact, not the UI.
4. For a large audit, fan out one reviewer per dimension (Agent tool) and merge.

## Output format

- **Scorecard** — table of the 8 dimensions with a /10 and a one-line verdict, plus
  an overall score.
- **Findings** — grouped by severity (Blocker / Should-fix / Polish), each with
  `file:line`, what's wrong, and the concrete fix.
- **What's strong** — 3–5 things to keep.
- End with the single highest-leverage change.

Keep it specific and kind: name the file and the fix, not vague adjectives.
