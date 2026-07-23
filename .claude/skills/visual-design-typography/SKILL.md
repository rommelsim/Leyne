---
name: visual-design-typography
description: >-
  Evidence-based visual-design and typography reference for building or reviewing any UI in this
  repo: type scale and hierarchy, the 8pt spacing grid, tap-target minimums, colour usage and
  WCAG contrast, elevation/depth, and how to keep a screen calm yet glanceable. Use this whenever
  you choose or judge fonts, sizes, weights, line-height, padding/margins, colours, contrast, or
  spacing; when a screen feels cluttered, cramped, or inconsistent; when defining tokens; or when
  the owner asks "does this look right / is the spacing off / is this readable?" — even without the
  words "typography" or "contrast". This owns the LOOK; pair with ux-laws (why a layout works) and
  transit-ui-patterns (domain). For iOS-26-specific Liquid Glass APIs use the ios-modern-design skill.
metadata:
  domain: design
  platforms: [ios, android]
---

# Visual Design & Typography (for a glanceable transit app)

The owner is not a designer — give concrete numbers and a reason, not vibes. Everything below
serves *time-to-answer in bright, moving, one-handed conditions*. When two options are close,
pick the calmer, higher-contrast, more scannable one.

## Typographic hierarchy

A glance needs an obvious 1-2-3 of importance. Build hierarchy with **size, weight, and colour**
— in that order — not with many fonts.

- **One type family for text** (repo uses Inter; IBM Plex where already established). A single
  family with multiple weights carries the whole hierarchy. Don't add a third face.
- **Type scale** — use a modular scale, not arbitrary sizes. A practical mobile ramp (pt/sp):
  `34 / 28 / 22 / 17 / 15 / 13 / 11`. The hero ETA lives at the top; captions/labels at the
  bottom. Steps should be visibly distinct — if two levels are within ~2pt, merge them.
- **Weight** — reserve the heaviest weight for the single most important element per view (the
  ETA/answer). Body is Regular; labels are Medium. Too many bold things = nothing is bold.
- **Line height** — ~1.3–1.5× for body; tighter (~1.1–1.2) for large display numbers so a big
  ETA doesn't float. Numeric data: use **tabular / monospaced figures** so "1 min" and "11 min"
  don't shift width and jitter on refresh.
- **Line length** — ~30–40 characters on mobile for any running text; transit UI rarely has
  long text, which is good — keep it that way.
- **Alignment** — left-align identity (line names/stops), right-align the numeric answer into a
  scannable rail. Never centre lists. Never truncate the line identity (owner rule); truncate
  secondary text instead.
- **Dynamic Type** — sizes must scale with the OS accessibility setting (iOS Dynamic Type /
  Android font scale). Never hard-cap or the app breaks for large-text users. Use text styles,
  not fixed points, wherever the platform offers them.

## Spacing — the 8pt grid

Consistent spacing is the single biggest driver of a "clean" feel. Use an **8pt base grid**
(4pt for fine adjustments only).
- Allowed spacings: `4, 8, 12, 16, 24, 32, 48`. Pick from this set; don't invent `13` or `21`.
- **Proximity does the grouping** (Gestalt): tight gaps *within* a departure (4–8pt between its
  fields), larger gaps *between* departures (16–24pt). If a board looks like undifferentiated
  soup, the fix is usually more space between groups, not dividers.
- Screen margins: 16pt standard gutters. Give the hero card room to breathe (24pt+).
- Whitespace is not wasted space — it's what makes the ETA findable. Resist filling it.

## Tap targets (where look meets Fitts)

- **Minimum interactive size: 44×44pt (iOS) / 48×48dp (Android).** WCAG 2.2 floor is 24px, but
  use the platform values — MIT Touch Lab: fingertips are 16–20mm; small targets raise error
  rates up to ~75%. A visually small control (a 16pt icon) still needs a 44/48 *hit area*.
- Keep ≥8pt between adjacent targets so a walking user doesn't hit the wrong one.

## Colour

Colour is a data channel here, not decoration. See the `transit-color-semantics` memory — this
skill covers the mechanics.
- **A module's own colour contract overrides this skill where it's stricter.** Some surfaces
  (e.g. the WhereSia board, `WSTheme.swift`: "colour = data, never chrome; crowd is NEVER
  colour-coded — greyscale gauge + word") deliberately forbid the traffic-light palette below.
  Read the theme file's header rules first; never introduce a status colour a module has banned.
- **Semantic, not decorative.** Line colour = identity. Status uses traffic-light meaning:
  green (good/arriving, kept rare), amber (minor disruption), red (major disruption), blue =
  neutral accent/system. Attention order red > amber > green > blue. **Always pair colour with a
  word** — never colour-only, for colour-blind users (~8% of men).
- **Restraint** — a resting screen is mostly neutral (greys/surface) so that the *one* coloured
  thing (the answer) draws the eye. A rainbow board defeats itself.
- **Contrast (WCAG 2.1):** body/small text ≥ **4.5:1**; large text (≥24px or ≥19px bold) and
  meaningful icons ≥ **3:1**; AAA is 7:1 for critical text. The hero ETA should clear 7:1 —
  it's read in sunlight. Check both light and dark themes; grey-on-grey secondary text is the
  usual failure.
- **Dark mode** — don't use pure `#000`/`#FFF`; use near-black surfaces and off-white text to
  cut halation. Elevate surfaces with lighter greys, not just shadows.

## Depth & elevation

- Use elevation to say "this is the answer / this is interactive," not for decoration. The hero
  departure sits forward; the board behind is flatter.
- Platform-native depth: iOS 26 Liquid Glass (see ios-modern-design skill) for translucency/
  layering; Android Material You tonal elevation + dynamic colour. Don't cross the idioms.
- Shadows: soft, low-opacity, single light source. Avoid harsh drop shadows and heavy borders —
  prefer tonal contrast and spacing to separate regions.

## Motion (brief — full timing in ux-laws/Doherty + ios-modern-design)

- Motion should clarify (where did this come from / what changed), never entertain. 200–300ms
  standard transitions; ease-out for entering, ease-in for leaving.
- Animate the *change* on refresh (a number counting/fading) so updates feel alive but calm —
  never a jarring full-list reflow. Respect Reduced Motion: drop to fades/instant.

## Review output

When reviewing, report: (1) hierarchy — can you find the answer in one glance? name what competes
with it; (2) spacing — off-grid values and where grouping is unclear; (3) contrast — any pair
under threshold, per theme, with the ratio; (4) targets under 44/48; (5) any colour used without
a paired word or against semantics. Give concrete replacements (exact pt/weight/token), not
adjectives. Defer *why-the-layout-works* to ux-laws and domain specifics to transit-ui-patterns.

## Sources
- Apple HIG — Typography & Layout — https://developer.apple.com/design/human-interface-guidelines/typography
- Material Design 3 — Typography & Layout — https://m3.material.io/styles/typography
- WCAG 2.2 contrast & target size — https://www.w3.org/WAI/WCAG22/Understanding/
- Touch target sizes (LogRocket / MIT Touch Lab) — https://blog.logrocket.com/ux-design/all-accessible-touch-target-sizes/
- Accessible tap targets (Smashing) — https://www.smashingmagazine.com/2023/04/accessible-tap-target-sizes-rage-taps-clicks/
