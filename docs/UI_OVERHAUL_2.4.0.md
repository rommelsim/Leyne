# Leyne iOS UI Overhaul → 2.4.0

Tracking doc for the visual overhaul shown in the June 2026 mockups
(`HomeScreen.png`, `BusStopView.png`, `BusView.png`). Ships as **2.4.0
(build 18)**, *after* 2.3.3 (AdBanner reliability + chip-overflow fix) is live.

Built on branch `ui-overhaul-2.4.0` in an isolated worktree so the staged
2.3.3 release in the main checkout stays clean and shippable.

## Locked decisions (defaults taken per "do whatever you need")

| # | Decision | Choice |
|---|----------|--------|
| color | Semantic green/amber/grey returns | **Yes — light mode.** Used for ETA *proximity* + *occupancy* only. |
| dark mode | Color or monochrome | **Dark stays monochrome** (as shipped in 2.3.2). Revisit later. |
| confidence | Color vs shape | **Stays shape/opacity + "~" whisper** (color-blind safe, keeps the honesty thesis). Color is proximity/occupancy, not confidence. |
| tab bar | Liquid Glass accessory vs standard | **Standard labeled 4-tab bar**: Home · Favourites · Settings · Search. |
| ads | Placement after tab-bar change | **Anchored adaptive banner above the tab bar** (`adBannerGutter` bottom inset). Keep retry/rootVC fix. |
| full route times | Per-stop clock times | **Show only times we have** (queried stop + next 1–2). No interpolation. |

## Data feasibility (confirmed in code)

- `Service.dest` → "To Shenton Way" ✓
- `Service.load` (`.sea/.sda/.lsd`) → Seats/Standing/Limited occupancy ✓
- `Service.followingSec` + `thirdDate` → "Then 18 | 35 min" ✓
- `Service.monitored` + `Freshness` → confidence ✓
- `ServiceRoute.originName/destinationName` + `stops` → route endpoints + full list ✓
- ⚠️ Intermediate per-stop clock times → **no LTA source**; show only known times.

## Phases

### A — Foundations (do first; everything depends on it) ✅ DONE (builds)
- [x] A1 · `Theme.swift`: `soon`/`soonBg` (green) + `mid`/`midBg` (amber) tokens, **both modes** (dark gets brighter shades — revised from "dark mono"). Revert = set dark `soon`/`mid` to ink/grey.
- [x] A2 · `V2/Proximity.swift`: `ETATier.of(etaSec:)` + `etaColor(…)` gated on confidence (scheduled/ghost stays neutral — never paint an unverified time).
- [x] A3 · `V2/Proximity.swift`: `OccupancyLabel` (`Load → Seats/Standing/Limited` + icon + colour). `CrowdMeter` kept for Bus view.
- [x] A4 · `Confidence.swift`: LIVE dot (`ConfidenceDot` + `ConfidenceStatusPill`) → green; stale/scheduled keep hollow/dashed shapes.

### B — Tab bar + ads ✅ DONE (builds)
- [x] B1 · `SoftRoot`/`SoftTabBar`: four inline labelled tabs Home · Favourites · Settings · Search (Search no longer the detached `.search` role); `SoftTab.favourites` added; selection tint `meBlue`.
- [x] B2 · New `SoftFavouritesView` matching the FavouriteView/PinnedStops mockups: header (+ / gear), filter chips **All / Stops / Services / Bus + Stop**, **Pinned stops** (enriched `SoftStopCard` — gold star, distance + walk, chips, "Updated N ago" + crowd footer) and **Pinned services** (badge + "To {dest}" + location + primary ETA + next-two). Per-section **Edit** toggles inline remove. Home's "Pinned" section removed (Home = Nearby-only).
- [x] B4 · **Pin flow + favourite-services model** (the previously-deferred piece, now built):
  - New persisted `FavService { no, stop? }` on `AppModel` (`leyne.favServices`) — `stop == nil` = anywhere, set = at that stop. Helpers: `isFavService` / `toggleFavService` / `removeFavService`. Favourite **stops** stay `m.pins`; **services** are `m.favServices` (independent of `Pin.tracked`, which remains alerts-only).
  - New `SaveSheet` (title + subtitle + radio option cards + Save), presented from a fitted `.sheet` detent.
  - **Stop view**: pin button in the sort row → "Save this stop" (Save stop = add `Pin`; "Save a bus here" → hint to tap a bus).
  - **Bus view**: the old stop-Pin pill replaced by a circular favourite button → "Save this service" (anywhere → `FavService(no, nil)`; at this stop → `FavService(no, stop)`). Green-filled when saved.
  - Anywhere ETA = nearest stop on the service's route from `ds.nearby` (`anywhereArrival`). Filters: Stops→pins, Services→anywhere favs, Bus+Stop→at-stop favs, All→everything.
- [x] B3 · `adBannerGutter` (bottom safeAreaInset) carries over above the new bar unchanged.

### C — Home (`SoftHomeView` + `SoftStopCard`) ✅ DONE (builds)
- [x] C1 · Card header: distance on its own row + pin glyph; subtitle "Stop {code} · {road}".
- [x] C2 · Chips → equal-width card chips (svc + ETA stacked), ETA-ordered; lead chip green "Arriving soon" when imminent+live; proximity-coloured ETA; "+N more" tile. FlowLayout removed.
- [x] C3 · `liveRow`: "NEAR YOU" → blue (`meBlue`); LIVE dot → green.
- [x] C4 · Section header "Nearby" → "Nearby stops" (sentence case, not the uppercase eyebrow).

### D — Stop view (`SoftStopView`) ✅ DONE (builds)
- [x] D1 · "Updated N ago" refresh row under header.
- [x] D2 · Sort chips reordered ETA / Bus no. / Distance.
- [x] D3 · Arrival cards: proximity-coloured `ServiceBadge` (new `fillOverride`/`fgOverride` + `serviceBadgeColors`); "To {dest}" + `OccupancyLabel`; big coloured ETA + dot; "Arriving soon" lead row (green tint); LTA-estimates footer. (Route-endpoint subtitle dropped — no clean per-arrival source; dest is enough.)

### E — Bus view (`SoftBusView`) ✅ DONE (builds)
- [x] E1 · Green LIVE dot (`ConfidenceStatusPill`); green hero "Now"/ETA when imminent + live-wave glyph; `CrowdMeter` recoloured + fuller "Seats available" labels.
- [x] E2 · Notify (black) + Live Activity (grey) already matched the mockup — left as-is.
- [x] E3a · `RouteTimeline` recoloured to green progress (checked past · green bus-here glyph · green your-stop ring · grey upcoming); green map stop pin.
- [x] E3b · **ROUTE PROGRESS** horizontal summary (new `RouteProgressBar`) + "N stops remaining"; **FULL ROUTE** list now has per-stop times ("FULL ROUTE" header + "View all stops" toggle). Bus-on-route position derived from the same ETA estimate as the map pin (`estimatedBusIndex`); upcoming times prefixed "ETA", passed stops show a check but **no fabricated past time** (`etaClock`, `fmtClock` honours `use24h`).
- [ ] E3c · Still open: green route **polyline** on the map (markers are green; the connecting line isn't drawn).

### F — Polish ⚠️ PARTIAL
- [x] **Typography → SF Pro** (per the supplied spec): `t.mono()` flipped from SF Mono to **SF Pro with monospaced _digits_** (one edit in `Theme.swift` — applies app-wide: numbers, ETAs, codes, eyebrows). `t.sans()` already = SF Pro with automatic Display/Text optical sizing. Dashboard titles ("Stops near you", "Favourites") bumped 30 semibold → 33 bold. Per-element size scale (ETA 36–44, etc.) only partly applied — font family + main titles done; finer sizes pending on-device tuning.
- [x] Dynamic Type — fonts already route through `UIFontMetrics` (`t.sans`/`t.mono`); chips use `minimumScaleFactor`.
- [x] VoiceOver — honest a11y labels carried/added on chips, arrival cards, occupancy, route dots.
- [x] Dark-mode — colour tokens defined for both modes (builds; **needs an on-device eyeball**).
- [x] Screenshot mode — ad gutter still self-suppresses; no change.
- [ ] Android parity — not touched this pass (iOS-only overhaul).
- [ ] **On-device visual QA of every screen** (couldn't run a simulator here).

### G — Release ✅ DONE (worktree)
- [x] `MARKETING_VERSION` → 2.4.0, `CURRENT_PROJECT_VERSION` → 18 (Release build passes).
- [x] `kChangelog["2.4.0"]` ("A brighter, clearer Leyne.") + `CHANGELOG.md` entry.
- [ ] Merge `ui-overhaul-2.4.0` → main after 2.3.3 is live, then Archive.

## Android (Flutter) port — ✅ DONE (`flutter analyze` clean)

Ported on the same `ui-overhaul-2.4.0` branch, Material idiom (not an iOS clone). Files:
- `lib/theme.dart` — `soon`/`soonBg`/`mid`/`midBg` tokens (dark + light); `mono()` → default font + `FontFeature.tabularFigures()` (Android equivalent of SF Pro + mono-digits).
- `lib/widgets/v2/proximity.dart` (new) — `EtaTier`, `etaColor`, `serviceBadgeColors`, `occupancyColor`, `OccupancyLabel`.
- `lib/widgets/v2/confidence.dart` — green LIVE dot; `CrowdMeter` coloured + fuller labels.
- `lib/widgets/v2/save_sheet.dart` (new) — Material `showModalBottomSheet` save flow (radio cards).
- `lib/widgets/v2/route_timeline.dart` — green route progress (check past · bus glyph here · your-stop ring · grey upcoming), green connectors/chips, per-stop times. *(I fixed this post-agent — it had been left on `t.accent`.)*
- `lib/widgets/v2/soft_tab_bar.dart` — `SoftTab.favourites`, 4-dest `NavigationBar`.
- `lib/screens/v2/{soft_stop,soft_bus,soft_favourites,soft_root}_screen.dart` — proximity badges/ETAs/occupancy, pin buttons + save sheets, Favourites screen (filter chips, pinned stops + services, remove).
- `lib/screens/v2/soft_home_screen.dart` — mini-chip ETA now proximity-coloured (`etaColor`). *(Post-agent parity fix.)*
- `lib/state/app_model.dart` — `FavService { no, stop? }` + `lyne.favServices` persistence + helpers.
- `lib/data/changelog.dart` — 2.4.0 What's New entry.

**Android notes / deltas from iOS:** Home keeps Material **capsule** mini-chips (not the iOS card-chips) — a legitimate platform choice; only the proximity *colour* was brought to parity. Android versionCode/pubspec version NOT bumped (user does that, per build convention). Needs on-device visual QA + an Android `flutter build` before release.
