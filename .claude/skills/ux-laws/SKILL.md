---
name: ux-laws
description: >-
  Research-backed UX laws and usability heuristics for judging and improving mobile UI
  in this repo — Fitts's, Hick's, Miller's, Jakob's, Doherty, Postel's, Peak-End, and the
  Gestalt grouping principles, plus Nielsen's 10 heuristics — each translated into concrete
  moves for a glanceable transit app. Use this whenever you are laying out controls, deciding
  how many options/tabs/chips to show, sizing tap targets, ordering information, judging whether
  a screen is "too busy", reviewing a layout, or explaining WHY one design reads faster than
  another — even if the user never says "UX law" or "heuristic". Pair it with the
  visual-design-typography skill (look/spacing) and transit-ui-patterns skill (domain).
metadata:
  domain: design
  platforms: [ios, android]
---

# UX Laws & Heuristics (for a glanceable transit app)

The owner is not a UI designer. Your job here is to bring the *reasoning* — name the law,
say what it predicts, then make the concrete change. Never cite a law without turning it into
a decision. These are predictive models of human perception/cognition, not style opinions, so
they settle "is this better?" arguments objectively.

The overriding context: Departly is a **glanceable** app. Users look at it for 1–3 seconds
while walking, one-handed, often in sun or motion. Every law below is applied through that
lens — the goal is *time-to-answer*, not decoration.

## The laws that matter most here

**Fitts's Law** — time to hit a target grows with distance and shrinks with target size.
- Primary actions (the bus/stop the user came to tap) go in the **thumb zone** (bottom ~⅓,
  reachable one-handed) and are large. A departure row the user taps to track should be a
  full-width, tall hit area, not a tiny chevron.
- Screen edges and corners are "infinite" targets (you can't overshoot them) — good for
  nav bars and back gestures. Destructive actions go *far* from frequent ones.
- Never rely on a target smaller than the platform minimum (see Fitts + WCAG in
  visual-design-typography). A 20pt chevron is a rage-tap generator.

**Hick's Law** — decision time grows logarithmically with the number of choices.
- Fewer top-level choices = faster. This is the research reason the app trends toward
  2–4 tabs, not a wall of options. When a screen sprouts a 5th competing action, that's the
  signal to fold something into a sheet or context menu.
- Break big decisions into steps (progressive disclosure) rather than showing everything.
  A Home screen showing the *one* nearest departure beats one showing twelve.
- Exception: for *expert/repeated* actions, don't over-hide — a regular commuter wants their
  saved line one tap away, not buried behind a menu.

**Miller's Law** — working memory holds ~7±2 items, realistically ~4 for glancing.
- Chunk. Group a departure into {line identity | ETA | status} — three chunks, not eight
  loose fields. Saved lines in groups of ~5, not one 20-long list.
- Don't make the user *remember* across screens; carry context forward (Jakob + heuristic #6).

**Jakob's Law** — users spend most of their time in *other* apps, so they expect yours to work
like the ones they already know (Apple Maps, Google Maps, Transit, Citymapper, the OS itself).
- Match platform idioms: iOS back-swipe, pull-to-refresh, share sheet, bottom sheets; Android
  predictive back, FAB conventions, Material navigation. This is *why* the repo insists on
  platform-native design (no cross-platform idiom bleed) — familiarity is a measurable speedup,
  not a preference.
- Innovate on *value* (timely, confident ETAs), conform on *mechanics* (how you tap/scroll/back).

**Doherty Threshold** — engagement holds when the system responds in <400ms.
- A tap must give feedback instantly even if data is still loading. Show the row's pressed
  state and a skeleton/`~` immediately; never a frozen screen. Optimistic UI over spinners.
- This is the reasoning behind the app's "timely updates, uncertainty is a quiet ~" stance —
  responsiveness is felt as trust.

**Postel's Law (robustness)** — be liberal in what you accept, conservative in what you emit.
- Tolerate messy realtime feeds (missing ETAs, stale timestamps, GTFS gaps) gracefully;
  still present a clean, confident surface. Degrade to scheduled/`~` rather than showing an error.

**Peak-End Rule** — people judge an experience by its most intense moment and its end.
- The "peak" is the moment the ETA answers their question — make it unmistakable and calm.
  The "end" is often a successful arrival notification or a clean refresh. Polish those two;
  they set the remembered quality of the whole app.

**Aesthetic-Usability Effect** — people perceive good-looking interfaces as more usable and
forgive minor issues. Real, but don't weaponize it to paper over a slow/wrong ETA; in a transit
app, *accuracy* is the aesthetic.

## Gestalt principles (how the eye groups a departure board)

The eye pre-consciously groups elements. Use these to make a dense board parse in one glance:
- **Proximity** — spacing does the grouping work; a departure's fields sit tight, with clear
  gaps *between* departures. Related things near, unrelated things apart. This beats drawing
  boxes/dividers everywhere.
- **Similarity** — same role → same visual treatment (all ETAs same type style; all line
  badges same shape). Users learn the pattern once.
- **Common Region / Enclosure** — a card groups more strongly than proximity alone; use a card
  for the hero departure, not for every row (over-carding kills the grouping signal).
- **Continuity & Alignment** — align to a grid so the eye can run down a column (all ETAs
  right-aligned into a scannable rail; all identities left-aligned). Misalignment reads as
  unrelated and slows scanning.
- **Figure/Ground** — the answer (ETA) is figure; chrome is ground. Contrast and elevation
  should make the ETA pop *forward*.

## Nielsen's 10 usability heuristics (audit checklist)

Use these to *review* a screen — walk each one and ask "does this hold?":
1. **Visibility of system status** — is data fresh? Show last-updated / live state (quietly).
2. **Match to the real world** — "3 min", "Arriving", real line names/colours — not codes.
3. **User control & freedom** — easy back/undo; never trap the user in a sheet.
4. **Consistency & standards** — same word for the same thing app-wide; platform conventions.
5. **Error prevention** — prevent bad taps (spacing, confirmation on destructive only).
6. **Recognition over recall** — show, don't make them remember; carry context forward.
7. **Flexibility & efficiency** — shortcuts for commuters (saved, recents) without cluttering novices.
8. **Aesthetic & minimalist** — every element earns its place; remove what doesn't answer the question.
9. **Help users recover from errors** — plain-language empty/error states with a next step, not codes.
10. **Help & documentation** — ideally unneeded; if present, searchable and contextual.

## How to apply in a review

When asked to review or improve a layout, produce: (1) the **time-to-answer** read — what the
user is looking for and how many seconds/scans it takes; (2) 2–4 concrete changes, each tagged
with the law/heuristic that justifies it and the predicted effect; (3) anything that violates
Jakob (non-native idiom) or Fitts (too-small/mis-placed target) flagged first, since those are
the most objective failures. Keep colour/type/spacing specifics to the visual-design-typography
skill and domain specifics to transit-ui-patterns; this skill owns *why the layout works*.

## Sources
- Laws of UX (Yablonski) — https://lawsofux.com
- Nielsen Norman Group, 10 Usability Heuristics — https://www.nngroup.com/articles/ten-usability-heuristics/
- UX laws reference — https://www.parallelhq.com/blog/ux-laws-design-principles
- MIT Touch Lab fingertip study (via) — https://blog.logrocket.com/ux-design/all-accessible-touch-target-sizes/
