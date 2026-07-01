# Paste this to Claude Code to start the build

You're building **WhereSia**, a Singapore public-transit real-time tracker (bus + MRT/LRT). This folder is a complete design handoff — no app code exists yet.

## First, read (in this order)
1. `README.md` — overview + what's here
2. `BUILD-BRIEF.md` — scope, the 10 screens, navigation, what's explicitly OUT of scope
3. `DESIGN-SYSTEM.md` — exact tokens + the hard "color = data only" rule
4. `DATA-LTA.md` — each screen mapped to its LTA DataMall endpoint + fields
5. `reference/mockup.html` — the visual source of truth (open it; add `#light` for the light theme). Reproduce this **look**, don't port its static markup.

Also check `/Users/rommel/Downloads/LTA_DataMall_API_User_Guide.md` — the authoritative API spec. Verify field names/values against it before wiring data.

## Before writing any UI, settle these with me
1. **Stack.** The design is iOS-first; **Live Activity + Dynamic Island are iOS-native only** (ActivityKit/WidgetKit). Native SwiftUI gives all of it; React Native/Flutter degrade those two to a plain push. Recommend one and ask me to confirm.
2. **Backend proxy.** The LTA `AccountKey` is secret and DataMall has no CORS — the client cannot call it directly. Propose a thin proxy (holds the key, caches, serves the app) before building screens.
3. **Static-data caching.** `BusStops` / `BusServices` / `BusRoutes` are large, paginated, and change rarely. Plan to fetch once, cache locally, refresh on a schedule — they power search and the route timeline.

## Non-negotiables (from the design)
- **Color = data only.** The ONLY color in the app is official MRT/LRT line bullets (hex table in DESIGN-SYSTEM.md). Bus numbers are neutral. **Crowd is never color-coded** — it's a greyscale gauge (34/67/100%) + a word (Seats/Standing/Limited · Low/Moderate/High). Never use green/amber/red for crowd.
- **No trip planning, no routing, no map view.** Out of scope by decision.
- **No invented data.** No minute-level bus timetable exists (frequency bands only); no full live-vehicle GPS (approximate from BusArrival coords + stop sequence); crowd is 3-level only. See "Honest limitations" in DATA-LTA.md.
- **One thin line-icon set, no emoji.** Tabular/mono numerals. Motion restrained and gated behind `prefers-reduced-motion`.
- **Accessibility floor:** VoiceOver labels (speak the crowd word, never rely on the gauge alone), Dynamic Type, visible focus.

## Suggested build order
1. Backend proxy + LTA client + models (Load/Type/Feature/Monitored/CrowdLevel).
2. Static-data cache (stops/services/routes) + search.
3. Design-token layer (port DESIGN-SYSTEM.md) + shared components (crowd gauge, route tile, line bullet, arrival pill, bus-type/wheelchair/live icons).
4. Screens: Home → Bus stop → MRT station → Service info → Track bus → Alerts → Saved → Me.
5. iOS extras (if native): Live Activity + Dynamic Island for active tracking.

This isn't a git repo yet — `git init` first.
