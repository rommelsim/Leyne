---
name: screenshot-captions
description: >
  Caption and sequence Leyne's App Store / Google Play marketing screenshots.
  Use when the user shares app UI screenshots they want to PUBLISH to the stores
  and asks for caption / headline overlay copy, marketing captions, store-listing
  screenshot text, or help ordering the screenshot set. NOT for debugging,
  dashboard, AdMob/Firebase, or bug-report screenshots — only store-listing
  marketing assets. Produces a per-shot headline (+ alternatives), the narrative
  order, and the platform specs.
---

# Store screenshot captions

Turn raw app screenshots into a captioned, ordered store-listing set. The text
sits **baked into the screenshot image** (it is not a metadata field), so this
skill outputs the overlay copy + the order, ready to drop into a frame template.

Ground every set in `docs/aso.md` — it holds the canonical screenshot order and
the approved example captions. This skill operationalises that doc per shot.

## When the user sends screenshots

For each one, establish: **what feature it shows**, **which platform** (App Store
/ Play / both), and **which is the lead shot**. If unclear, ask briefly — then
caption. Don't caption a debugging/dashboard screenshot; this is store-only.

## Leyne voice (the messaging palette)

- **Core promise: timely updates.** Lead with "right now / live / one glance."
  Present confidently — uncertainty is a whisper-quiet "~", never a headline
  (see [[feedback_timely_over_honest]]).
- **Benefit, not feature.** "Your bus, one glance away" > "Lock Screen widget."
- **Platform-native, system-blue identity** ([[design_identity_pass]]); copy
  reads clean and Apple-Maps-confident, no hype words ("ultimate", "best").
- **Value props to draw from:** live SG bus **and** MRT arrivals (LTA DataMall,
  no sign-up), pinned stops, arrival + alight alerts, Home/Lock-Screen widgets,
  Live Activity / Dynamic Island countdown, nearby stops with walk distance, MRT
  crowd levels, dark mode.

## Caption rules

1. **3–5 words.** Punchy. A glance, not a sentence.
2. **One message per shot** — the single thing that screen proves.
3. **Complement the visual, don't narrate it.** The image shows the *what*; the
   caption says the *why it matters*.
4. **Parallel structure across the set** — same voice, similar length, consistent
   case (Title Case or short phrase, pick one and hold it).
5. **Don't repeat the app name** in captions.
6. **Reinforce listing keywords** (arrival, timing, ETA, MRT, stop, Singapore)
   naturally — overlays aren't indexed, but echoing them lifts conversion.
7. **First 2–3 shots carry the listing** (they show in search results) — put the
   strongest, most differentiated value there.

## The narrative arc (order matters)

The set tells a story; sequence beats individual cleverness. Canonical order
(from `docs/aso.md`, re-shoot once the widget ships — the widget shot is the
single best converting asset):

1. **Lock Screen / widget, live ETA** — *"Your bus, one glance away"*
2. **Live Activity / Dynamic Island countdown** — *"Never miss it"*
3. **Home pinned-stop hero, live arrivals** — *"Your stops. Right now."*
4. **Arrival notification on Lock Screen** — *"A nudge before it pulls in"*
5. **Nearby stops + walk distances** — *"Find any stop, instantly"*

Adapt to what the user actually shot; keep the strongest value in slots 1–3.

## Platform specs

- **App Store:** up to 10 screenshots per device size; **first 3 show in search**.
  Supply the current required size (6.9"/6.5" iPhone). Captions baked in.
- **Google Play:** 2–8 screenshots, PNG/JPEG, 16:9 or 9:16. For a utility app,
  **make the widget shot the first asset** — Play surfaces it prominently. Use a
  device frame + real data.
- **Both:** real data (not lorem), device frame, brand-consistent background.

## Output format

For each screenshot, produce a row:

| # | Screen shows | **Headline (3–5 words)** | Alt options | Why / keyword tie-in |

- Always give **2 alternative headlines** per shot so the user can pick.
- Lead with a one-line **arc summary** (how the set reads top to bottom).
- Close with: any gaps (a value prop not yet shown), and which shot to **A/B
  test first** (per `docs/aso.md`, the first screenshot + icon are the highest-
  leverage conversion levers).

## Notes

- Caption *both* platforms when asked, but tune wording: App Store leans glance/
  premium; Play leans plain-benefit + "no sign-up".
- If the user only describes a screen (no image), caption from the description —
  don't block on the file.
- Keep a light touch: these are conversion assets, so clarity > cleverness. When
  in doubt, the simpler benefit line wins.
- Related: `docs/aso.md` (strategy + canonical set), and the store metadata
  (title/subtitle/short-description) lives there too — keep captions consistent
  with that positioning.
