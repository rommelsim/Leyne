# Leyne — Held Changes Spec (batch implementation)

Four screens researched; one theme unites them: **rows hide the most important thing, and the "single best departure / raw proximity" pattern is too thin.** Every list must show *the bus* and rank/label by *catchability*.

---

## 1. Hero / Pinned card
**Problem:** Stop name is gray body text, lost mid-card. The route badge and the huge ETA sit at opposite corners, reading as two unrelated objects, not "the 96 arrives in 1 min."

**Fix:**
- Stop name becomes the card **title** (~22px bold), with road + walk time as quiet subtitle.
- A hairline divider separates "where" (stop) from "what's coming" (departure).
- Route badge + destination + load chip + ETA sit in **one horizontal row**, read left→right as one fact.
- Drop hero ETA from ~88px to ~44px — relative dominance, not absolute size, is what the research means by "supersized."
- Applies to BOTH the home pinned card and the stop-detail hero (shared layout).

## 2. Nearby view
**Problem:** One bus per stop, picked by soonest — so an uncatchable "Now" becomes the headline. Every stop shows a different bus number (no route-first scanning). Walk time buried in the subtitle.

**Fix:**
- **Rank by catchability**, not raw proximity: blend walk time vs next arrival (arrival − walk = buffer). Comfortably catchable rises.
- **Suppress uncatchable "Now"**: if the soonest bus can't be reached given walk time, show the next *makeable* bus instead (or show 2 arrivals).
- **Walk time as a first-class chip**, not subtitle tail.
- Show the **bus number** on every row (already implied via "52 to Bishan Int" — keep and make consistent).

## 3. Saved view
**Problem:** Same one-bus trap, worse — bus number hidden entirely. Subtitle is admin metadata (stop code + road) instead of what's coming. Only saves *stops*, not *routes*. Everything green (dilutes the reserved accent). No per-row alert bell.

**Fix:**
- **Show the bus, not just the time** — each row names the relevant route(s): "52 · Now · then 8".
- **Replace code/road subtitle** with live route info (walk time + next bus).
- **Add saved buses** as a first-class type ("the 52 from Blk 329"), shown alongside saved stops.
- **Neutralize non-arrival green**: "Synced" → gray. Green stays only for real ETAs.
- **Per-row alert bell** for one-tap "buzz me" on the stops you care most about.

## 4. Search view
**Problem:** Rows hide their type — "96" (route), "Clementi Int" (stop name), "17239" (stop code) all render identically. Recents are stripped-down text, not mirroring result format. Empty state only shows recents (blank for new users). No live info on results.

**Fix:**
- **Type-distinct rows**: route badge for buses, pin/stop glyph for stops — kind readable at a glance.
- **Recents mirror result formatting** (badges/icons), grouped by type where it helps.
- **Useful empty state**: nearby stops / common routes when recents are few.
- **Inline ETA on stop results** where cheap.

---

## Cross-cutting principles (apply everywhere)
1. **Every list row shows the bus** — never just a time.
2. **Rank/label by catchability** — walk time vs arrival, not raw distance or raw soonest.
3. **Reserved green** — imminent arrivals only; neutralize decorative green.
4. **One aligned row primitive** (`.lcell`) — leading icon/badge, growing content, trailing value + chevron.
