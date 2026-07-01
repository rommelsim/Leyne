# WhereSia — build handoff

A design-complete package for **WhereSia**, a Singapore public-transit real-time tracker (bus + MRT/LRT). No app code exists yet — this folder is everything an engineer (or Claude Code) needs to start building.

## What WhereSia is
A crowd-first live-arrivals app. Its one differentiator: for the next buses at a stop it shows **how full each one is**, so you can pick the emptier ride. Also covers MRT station crowd + forecast, service info, live bus tracking, and service alerts. **No trip-planning / routing and no map view** — both were deliberately cut from scope.

## Read these in order
1. **`BUILD-BRIEF.md`** — product scope, the 10 screens, navigation, interactions, and what's explicitly out of scope.
2. **`DESIGN-SYSTEM.md`** — the exact design tokens, color rules, typography, iconography, and component specs. This is a hard contract; follow it.
3. **`DATA-LTA.md`** — every screen mapped to its LTA DataMall API source, field by field, plus the auth/proxy note.

## Reference material
- **`reference/mockup.html`** — the visual source of truth. A single self-contained HTML file rendering all 10 screens as 390×844 phones. Open it in a browser. It is **themeable**: append `#light` to the URL (or set `body.light`) for the light variant. Treat its CSS as the token reference — the real app should reproduce this look, not necessarily this markup.
- **`reference/transit-board-dark.png` / `transit-board-light.png`** — rendered sheets of all 10 screens, dark and light.
- **`reference/wheresia-system-views.png`** — service bottom-sheet, Lock Screen Live Activity, and Dynamic Island (compact + expanded) treatments.

## Icon
- **`icon/wheresia-icon-{1024,180,120,60}.png`** — final app icon, full-bleed squares. iOS applies the squircle mask; upload the 1024 as-is to App Store Connect.
- **`icon/wheresia-app-icon-final.png`** — icon spec sheet (colors + home-screen preview).
- **`icon/icon-master.html`** — source, to re-export at any size.

## Status
Design is locked. Nothing here is implemented. Not a git repo yet — `git init` before building.
