---
name: transit-ui-patterns
description: >-
  Domain-specific UI/UX patterns for realtime public-transit apps, tuned to Departly: how to
  present departures/ETAs, structure a departure board, communicate live vs scheduled and
  confidence, handle stale/missing/degraded realtime data, order and group lines, and design
  glanceable one-handed transit surfaces. Use this whenever you build or review a Home/Stop/Bus/
  MRT screen, a departure row, an ETA display, a live badge, an arrival capsule, a widget or Live
  Activity, an alert/disruption surface, or any place showing arrival/departure times — even if
  the user just says "the bus screen" or "the arrivals". This owns DOMAIN decisions; pair with
  ux-laws (why layouts work) and visual-design-typography (look/spacing/colour mechanics).
metadata:
  domain: design
  platforms: [ios, android]
---

# Transit UI Patterns (Departly)

Transit UX lives or dies on **trust in the number**. Research on transit apps repeatedly finds
the top user pain is *inaccurate / conflicting / unreliable ETAs* — not looks. So every pattern
here optimizes for: answer the "when's my ride?" question fast, and be honest-but-confident about
certainty. Departly's selling point is *timely* updates presented confidently — see the
`feedback_timely_over_honest` and `transit_color_semantics` memories; this skill is the applied
domain layer on top of ux-laws and visual-design-typography.

## The core object: a departure row

A departure answers three things, in this reading order (left→right, F-pattern):
1. **Identity** — line/route number + colour badge, and where it's going (destination/direction).
   Never truncate identity (owner rule). This is *what*.
2. **Status** — live vs scheduled, any disruption. This is *how trustworthy*.
3. **ETA — the answer** — right-aligned into a scannable rail, the boldest/largest thing in the
   row. This is *when*.

Chunk it (Miller): {identity | status | ETA}, three groups, tight within, spaced between rows.

### ETA display rules
- **Relative time for the near term**: "Now", "1 min", "3 min", "12 min" — people think in
  minutes-until, not clock times, when the ride is imminent.
- **Switch to clock time when far out** (>~30–60 min) or scheduled-only: "14:35". Mixing is fine
  if consistent.
- **"Now" / "Arriving"** for the imminent departure — a distinct capsule, the peak moment
  (Peak-End). Green, used sparingly, paired with the word.
- **Tabular figures** so numbers don't jitter on refresh; animate the *change*, not a reflow.
- **Multiple upcoming** per line: show the next, then "+7, +15" as lighter secondary text — the
  first answer dominates; the rest are reassurance (Hick — don't make them parse a table).
- **Number-sorted / soonest-first** board so the top row is always the most relevant.

## Live vs scheduled vs degraded — the confidence ladder

This is the heart of transit trust. Be **confident by default, uncertain only in a whisper**
(owner rule) — never a loud banner that undermines the app.

- **Live (realtime feed healthy):** a quiet LIVE indicator (small dot/word), fresh timestamp.
  Present the number plainly and confidently.
- **Slightly stale / interpolated:** keep showing the number; prepend a subtle `~` ("~4 min").
  The tilde is the *entire* uncertainty signal — no warning colour, no banner.
- **Scheduled only (no realtime):** show the timetable time, mark it "Scheduled" quietly. Don't
  fake liveness, but don't apologize loudly either.
- **Missing / no data:** graceful empty state in plain language with a next step ("No departures
  in the next hour" / "Pull to refresh"), never an error code (Nielsen #9). Degrade, don't break
  (Postel's Law).
- **Disruption / cancelled:** *this* is when colour escalates — amber (minor/delay) or red
  (cancelled/major), always paired with a word, placed on/near the affected row so it can't be
  missed. Reserve red/amber for real disruptions so they keep their meaning.

Freshness must be visible (Nielsen #1) but subordinate: a small "updated 5s ago" or a live dot,
not a headline.

## Screen-level patterns

- **Home** — answer first: the nearest/most-relevant departure as a hero card (ETA-in-chip,
  "Now" label, computed +N, otherwise neutral resting state — see `home_hero_redesign` memory).
  Don't open with a menu; open with an answer.
- **Stop view** — a departure *board*: all lines at a stop, soonest-first, grouped by line,
  each row the standard departure object. This is the densest surface — lean hardest on
  proximity-grouping and the right-aligned ETA rail so it parses in one glance.
- **Bus/line tracking** — follow one line; iOS keeps the native MapKit overlay, **Android has no
  map by design** (`android_no_map` memory — don't re-add without an explicit ask). Show
  progress toward the user's stop and the live ETA prominently.
- **MRT** — free for all, enriched with live crowd (greyscale scale, not alarming colours) and
  lift/facility maintenance status. Crowd is *information*, not an alert — keep it calm.
- **Saved / Alerts** — commuter shortcuts (Jakob/efficiency): saved lines one tap away, grouped
  in ~5s. Alerts surface disruptions on saved routes.

## Glanceability constraints (non-negotiable)

Users read this for 1–3 seconds, one-handed, in motion, often in sunlight:
- Primary actions in the **thumb zone** (Fitts); board scrolls, answer stays reachable.
- The answer must clear **7:1 contrast** and survive bright light (visual-design-typography).
- No circular/ambiguous progress indicators for time — people scan linearly, not radially
  (`reading_patterns` memory). Use text + a linear sense of "closer".
- Widgets / Live Activity / notifications follow the same object and confidence ladder, stripped
  to the single most important line (the Nearest Stop widget shows name+code, no ETA clutter —
  `ios_widgets` memory). Two-tier arrival notifications: "approaching" then "arriving".

## Anti-patterns (call these out in review)

- ETA buried below identity or left-aligned so the eye can't rail down it.
- Loud uncertainty (warning banners, red "unreliable" labels) that erode trust for normal staleness.
- Colour without a word; green used so often it stops meaning "good/arriving".
- A board sorted by anything other than soonest-first without a reason.
- Truncated line identity; jittering (non-tabular) numbers; full-list reflow on refresh.
- Cross-platform idiom bleed (Android map re-added, iOS given Material patterns, etc.).

## Review output

When reviewing a transit surface, report: (1) can the user get the ETA answer in one glance? what
competes with it; (2) is the confidence state (live/`~`/scheduled/degraded) correct and *quiet*;
(3) is disruption colour correctly escalated and word-paired; (4) sort order and grouping; (5) any
anti-pattern above. Defer layout-reasoning to ux-laws and pixel/type/colour mechanics to
visual-design-typography.

## Sources
- Transit 6.0 design (ETA-first, supersized) — https://blog.transitapp.com/six-o/
- Public-transit mobile UX best practices (AltexSoft) — https://www.altexsoft.com/blog/best-mobile-user-experience-design-practices-for-public-transportation-apps/
- Transportation app UI/UX best practices (Fuselab) — https://fuselabcreative.com/transportation-app-ui-ux-design-best-practices/
- GTFS Realtime (feed reality behind the confidence ladder) — https://gtfs.org/realtime/
