# Porting "Glance" into the iOS app — implementation plan

**Goal:** bring the `design-prototype/v2/` ("Glance") redesign into the production
SwiftUI app (`ios-native/Leyne`). The prototype **is the spec** — when in doubt,
match it. Built on `glance-redesign` branch.

**Why a plan, not a one-shot rewrite:** this environment can't build/Archive iOS,
and Glance is a wholesale identity change (monochrome → departures-first with line
colour + an arriving green + depth/motion). So it ships as **phases, each a
buildable Xcode increment** you verify on device before the next. This supersedes
the older monochrome `design_identity_pass` direction — by the owner's call.

---

## Phase 0 — Design tokens (foundation, do first)
File: `ios-native/Leyne/Theme.swift`
- **Type:** add a `rounded(_ size:_ weight:)` helper → `.system(size:weight:design:.rounded)` for ETAs/headlines (the prototype's `--round`). Keep `mono` (tabular figures) for countdowns; SF Pro Rounded has tabular figures.
- **Palette** (map prototype `:root` → `Theme.light`/`.dark`, both modes):
  `paper`/`bg`, `card`/`surface`, `card-2`/`surfaceHi`, `ink`/`fg`, `ink-2`/`dim`,
  `ink-3`→**`#767683` light / 48% white dark** (AA-corrected), `hair`/`line`.
  Add **`brand` `#5B5BD6`** (actions/pinned), **`go` `#0A8048` light / `#34D17A` dark**
  (arriving — AA verified), **`warnText` `#A06B00` light** (alert *text*; keep amber for fills).
- **Line colours:** reuse the existing `MRTLine` colours as the identity anchor; line chips need **dark text on CC orange + EW green** (AA), white on the rest.
- **Shape/elevation:** add soft-shadow modifiers (`.elev` / `.elevHi`) and larger radii (card 24, chip 13, badge 14). Depth replaces hairline borders.
- *Verify: app still builds; spot-check a couple screens for colour regressions.*

## Phase 1 — `DepartureCard` + Now board (the headline)
- New `DepartureCard` view: bus badge (ink chip) · destination · crowd glyph + "then X · Y" · **big rounded tabular live countdown** (live = pulsing wave + ink; arriving ≤1m = `go` green; scheduled = muted + "~"). This is THE reusable component.
- Rewrite `V2/SoftHomeView.swift` → departures board: search field ("Where to?") + Home/Work places row, saved stops first (pinned float to top), nearby below, each stop a section of `DepartureCard`s — **ETAs visible with zero taps**. Skeleton on first load; "updated Xs ago" stamp; contextual alert banner. Drop the big "Stops near you" title.
- *Verify: Now board renders live ETAs; tap → bus detail.*

## Phase 2 — Rail (network board · line diagram · station)
- `V2/SoftMrtView.swift` → **network status board** (each line: chip + Normal/Delays) + nearest stations with crowd.
- `V2/SoftMrtLineView.swift` → **visual line diagram** (TfL `x`-geometry: line-colour spine, donut nodes, **interchange nodes + connecting-line chips**, terminus caps, you-are-here pulse, per-station crowd as a *shape-encoded* glyph not colour-alone, direction segmented control, loop overview for CCL).
- `V2/SoftMrtStationView.swift` → **next trains grouped by direction** (scheduled-styled — LTA has no live train feed), platform, crowd, progressive-disclosure rows (lifts via FacilitiesMaintenance, exits, first/last, nearby buses).

## Phase 3 — Bus detail + GO trip companion
- `V2/SoftBusView.swift` → hero live ETA + native MapKit (keep iOS map; Android omits it) + route-progress timeline + **"Start trip"** → GO. Trim to progressive disclosure.
- New `LiveTripView` (GO): auto-advancing walk→wait→ride→alight→arrived, big countdown, progress strip, escalating "get off next" (haptics), steps. Mirror into the Live Activity / Dynamic Island (`LeyneActivityAttributes` already exists).

## Phase 4 — Search + Trip results
- `V2/SoftSearchView.swift` → "Where to?", saved places, recents, **live nearby board**, rich typed result rows.
- New `TripResultsView`: duration-hero rows with the **inline mode strip** (walk→bus→MRT in line colour) + fares + filter chips (incl. "Rain-safe").

## Phase 5 — Settings/About, Onboarding, IA cleanup
- `V2/SoftSettingsView.swift` → identity hero card + **glyph-tile rows** + section-footer microcopy; new `AboutView` (LTA attribution, rate, buy-me-a-coffee).
- `OnboardingView.swift` → value-first (welcome → location prime → into the live board).
- **`V2/SoftRoot.swift` — collapse the tab bar 5 → 2** (Now · Rail) + persistent search; **remove `SoftFavouritesView` and `SoftAlertsView` tabs** (saved folded into Now; alerts contextual). Settings via an avatar/gear in the header.

---

## Cross-cutting
- **Accessibility:** the AA-corrected token values above are mandatory; line/crowd/status never colour-alone (chip = colour + code text; crowd = bar glyph; live/scheduled = wave/"~").
- **Motion:** spring for finger-driven, easing for transitions; `Text(...).contentTransition(.numericText(countsDown:))` for the countdown tick; skeletons match layout.
- **Android:** the Flutter app is a **separate, later port** — do iOS first, then mirror per the parity rule (Android keeps no bus-view map).
- **Per phase:** update `kChangelog` in `AppModel.swift` + `CHANGELOG.md` when a build is cut.

**Reference:** the live prototype (`design-prototype/v2/`, served on :4322) is the source of truth for every layout, token, and interaction.
