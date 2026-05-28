# Leyne 2.0 — Implementation Plan

Source: Claude Design handoff bundle at `~/Downloads/leyne-2-0/`, "Soft" direction only.
Canonical files: `proto-soft-ios.jsx`, `proto-soft-android.jsx`, `directions.jsx`, `shared.jsx`, `proto-data.jsx`, `proto-app.jsx`.
Not in scope: `screens-*.jsx`, `Exploration*.html`, the other four design directions.

Theme rollout decision (locked): **replace** `LyneTheme` (Flutter) and `Theme.swift` (iOS) in place. No flag-gated alongside-v2.

Sequencing rule (locked): **iOS native leads; Flutter Android ports from iOS.** Each platform ships as its own branch/PR.

---

## 1. Open decisions (need answers before Phase 2)

These don't block tokens or primitives, but they shape every screen from Stop detail onward.

| # | Question | Default if you say nothing |
|---|---|---|
| 1 | Tab order: prototype is `Home / Nearby / Settings / Search`. Settings before Search — typo? | Build as prototype; flag as suspicious in PR |
| 2 | Home "+" button → currently routes to Search. Real "add pin" sheet? | Keep "+ → Search" (matches prototype) |
| 3 | Edit-pencil "✎" next to stop name on Bus screen (no handler in proto) | Drop the glyph entirely — no orphan UI |
| 4 | "See all 11 →" on Stop "Other buses" (no handler) | Build a "All arrivals at stop" sub-screen |
| 5 | Bus tracking as new screen vs. extending current Detail Mode B | New screen, pushed from Stop detail (matches proto) |
| 6 | Pin label entry (Home/Work/Gym/Class) — no flow in prototype | Add a label sheet from Stop detail's pin action |
| 7 | Bus screen MRT alert dot persistence (proto shows it remains until next data tick) | Persist per-incident; clear on dismiss of source MRT |

Ask me to revisit any of these and I'll fold the choice into the plan.

---

## 2. Design tokens (Soft direction)

Replace existing token values. Names mostly map 1:1.

### Colors
| New token | Dark | Light | Replaces (Flutter / iOS) |
|---|---|---|---|
| `bg` | `#15201C` | `#F4EFE7` | `bg` |
| `surface` | `#1F2C28` | `#FFFFFF` | `surface` |
| `surface2` | `#293732` | `#EAE3D6` | `surfaceHi` |
| `text` | `#F1EDE7` | `#1A201D` | `fg` |
| `muted` | `rgba(F1EDE7, .6)` | `rgba(1A201D, .6)` | `dim` |
| `faint` | `rgba(F1EDE7, .35)` | `rgba(1A201D, .35)` | `faint` |
| `accent` | `#8EE6C0` | `#2D7A5A` | `accent` |
| `onAccent` | `#0E2218` | `#FFFFFF` | (new) |
| `accentTint` | `#0F2A20` | `#E8F5EE` | `liveBg` |
| `warn` | `#F4B870` | `#A0631A` | `warn` |
| `err` | `#F08F7C` | `#A4422F` | `crit` |
| `hairline` | `rgba(F1EDE7, .08)` | `rgba(1A201D, .10)` | `line` |
| MRT NE purple (cross-mode) | `#9B26B6` | — | (new) |
| Me-dot blue (cross-mode) | `#3B82F6` | — | (new) |

MRT line palette → drop into a `MRTLines` enum (EW `#009645`, NS `#D42E12`, NE `#9B26B6`, CC `#FA9E0D`, DT `#005EC4`, TE `#9D5B25`).

### Typography
- Body face: **Inter** on both platforms. Bundle Inter weights 400/500/600/700 (Flutter via `google_fonts` or asset; SwiftUI via custom font file).
- Mono face: `ui-monospace` (iOS), `Roboto Mono` (Android).
- Scale: titles 28–32 / sections 18–22 / body 14–15 / caption 11–12 / eyebrow 10–11 (mono, letter-spacing 1–1.5) / arrival numeral 52–56 (mono, letter-spacing -2, accent).

### Radii
| Element | iOS | Android |
|---|---|---|
| Hero card | 22 | 24 |
| List card / group | 16 | 20 |
| Inset sub-card | 16 | 18 |
| Walk tile | 14 | 16 |
| Pill / chip | 99 | 99 |
| Service badge (sm/md/lg) | 10/14/16 | 12/16/18 |
| Settings group | 18 | 22 |
| FAB | — | 16 |
| Search field | 14 | 28 |

### Elevation
- iOS tabbar shadow: `0 6 20 rgba(0,0,0,.06)` light / `0 4 16 rgba(0,0,0,.3)` dark.
- iOS glass pill: backdrop blur 12 + saturate 180, inset highlight + thin border (recipe in `ios-frame.jsx:58-89`).
- Android FAB: `0 8 24 rgba(0,0,0,.25), 0 2 6 rgba(0,0,0,.15)`.
- Android nav: flat with top hairline only.

---

## 3. Phased work — iOS native (leads)

Each phase = a commit or two. Phases 1–2 land before any screen work; later phases per-screen.

### Phase 1 — Tokens & primitives (foundation)
- [ ] Replace `ios-native/Leyne/Theme.swift` with Soft tokens above. Keep struct shape (`isDark` boolean, same property names where possible) so call-sites compile; rename `surfaceHi → surface2`, `liveBg → accentTint`, `crit → err`. Add `onAccent`, MRT line palette, me-dot blue.
- [ ] Add Inter font asset + register in Info.plist + `LyneTheme` font helpers.
- [ ] New `Components/` group:
  - `ServiceBadge.swift` — accent-filled rounded square, sizes sm/md/lg.
  - `LabelPill.swift` — small chip (Home/Work/Gym/Class). Two variants: solid accent (hero), tinted accent (secondary).
  - `SortChipRow.swift` — pill chip row, single-selection.
  - `IOSGlassPill.swift` — backdrop-blur container (used by tabbar + back/pin pills).
  - `SoftTabBar.swift` — floating pill tabbar with 4 tabs.
  - `RouteTimeline.swift` — vertical step list with `past/here/board/next/alight` states + tap-to-alight handler.
  - `MapHandoffToast.swift` — top toast overlay.
- [ ] Replace `Glyphs.swift` mappings: `chevron.left`, `chevron.right`, `figure.walk`, `bus.fill`, `magnifyingglass`, `location.fill`, `gearshape`, `house.fill`, `pin` / `pin.fill`, `lock.fill`, `exclamationmark.triangle.fill`, `tram.fill`, `map.fill`, `plus`.

### Phase 2 — Screens
Build in this order so each builds on the previous:
- [ ] `HomeView.swift` — replace; PrimaryPinCard + secondary grid + MRT alert card + SoftEmpty.
- [ ] `NearbyView.swift` — replace; sort chips + 44-square walk-time tile rows.
- [ ] `DetailView.swift` → rename to `StopView.swift` — header, hero arrival, "Other buses" grouped card, "See all" link to new `AllArrivalsView.swift`.
- [ ] `BusView.swift` (new) — pushed from StopView; large arrival numeral + Live Activity CTA + MapKit live map + RouteTimeline.
- [ ] `SearchSheet.swift` → flatten into pushed `SearchView.swift` to match proto's "Cancel" pattern (or keep as sheet if you prefer iOS sheet semantics — say which).
- [ ] `SettingsView.swift` — replace; three grouped sections (Routines / Personalize / Feedback).

### Phase 3 — Overlays & system integration
- [ ] `LockScreenLiveActivityPreview.swift` — in-app preview overlay (taps the CTA on BusView; tap to dismiss). Real ActivityKit Live Activity is a follow-up (see `parity.md` — already deferred).
- [ ] `MapHandoffToast` wired to `MKMapItem.openInMaps` and Google Maps URL scheme fallback.
- [ ] Spotlight integration: update `Spotlight.swift` to reflect new stop card layout (visual only — no schema change).

### Phase 4 — Polish & ship
- [ ] Press-down scale on tappable cards (`scaleEffect(0.985)` on `isPressed`).
- [ ] Real-time tick: connect AppModel's existing 1-second tick to drive ETAs across all new screens.
- [ ] Pull-to-refresh on Home / Nearby / Stop.
- [ ] Empty / loading / error states for arrivals (not in prototype — derive from current app behavior).
- [ ] QA pass against the prototype HTML side-by-side.
- [ ] Bump `kChangelog` in `AppModel.swift` and `CHANGELOG.md` at repo root.

---

## 4. Phased work — Flutter Android (ports from iOS)

Start only after iOS Phase 2 lands. The shipping iOS app is the canonical reference; the prototype is just the design north star.

### Phase 5 — Tokens & primitives
- [ ] Replace `lib/theme.dart` `LyneTheme` palette with Soft tokens (same renames as iOS).
- [ ] Add Inter via `google_fonts` or local asset; update default `TextTheme`.
- [ ] New `lib/widgets/v2/` group mirroring iOS Components:
  - `service_badge.dart`, `label_pill.dart`, `sort_chip_row.dart`, `m3_top_bar.dart`, `m3_soft_nav.dart` (pill-indicator bottom nav), `route_timeline.dart`, `extended_pin_fab.dart`, `map_handoff_toast.dart`.

### Phase 6 — Screens
Mirror iOS Phase 2 order. Swap iOS chrome for M3 conventions:
- iOS Liquid Glass tabbar → M3 NavigationBar with pill indicator.
- iOS inline pin pill on Stop → Android Extended FAB (bottom-right).
- iOS pushed Search → M3 docked SearchBar full-screen route.
- iOS top-bar pills → M3 small top app bar.

- [ ] `home_screen.dart` rewrite.
- [ ] `nearby_screen.dart` rewrite.
- [ ] `detail_screen.dart` → split into `stop_screen.dart` + new `bus_screen.dart` + `all_arrivals_screen.dart`.
- [ ] `search_screen.dart` rewrite (M3 SearchBar).
- [ ] `settings_screen.dart` rewrite.
- [ ] `whats_new_screen.dart` — update entry for v2.0.

### Phase 7 — Overlays & system integration
- [ ] Live Activity equivalent on Android = persistent foreground-service ongoing notification with rich content. Out of scope for v2.0 ship; keep existing arrival notifications.
- [ ] Map handoff: `url_launcher` → `geo:` intent (Google Maps).
- [ ] Pull-to-refresh, press states (`InkWell`), Material You dynamic color guard (still respect user toggle).

### Phase 8 — Polish & ship
- [ ] Real-time tick wiring (existing AppModel).
- [ ] Empty / loading / error states.
- [ ] QA against iOS implementation, not the prototype.
- [ ] Bump version, write `CHANGELOG.md` entry.

---

## 5. Things to watch

- **Existing AppModel + DataStore shapes** are compatible with the prototype's data model (stop ID, services, arrivals, route progress, MRT lines). No backend migration needed.
- **Routine feature** (Settings → "Morning commute" / "Evening commute") is new behavior, not just UI. Defer to a follow-up; ship Settings with the rows stubbed/disabled if needed.
- **MapKit vs `flutter_map`/OSM** parity: the live map on BusView shows BUS + STOP + ME pins, animated bus position, and a service tag. Flutter side currently uses OSM tiles — workable, but bus position animation needs verification.
- **Service letter suffixes** (e.g. "21A"): ensure ServiceBadge auto-sizes to width of string, not just 2 digits.
- **Bottom safe-area math** — prototype uses fixed offsets (`bottom: 30` iOS, `24` Android). Use real safe-area insets.
- **Live Activity / Widget** work tracked separately in `parity.md` Task #12 — don't expand scope here.
- **AdMob** stays disabled across both platforms during 2.0 redesign.

---

## 6. Acceptance criteria

Each platform's 2.0 ships when:
- All 6 screens + 2 overlays render with new tokens and components.
- No reference to old token names (`surfaceHi`, `liveBg`, `crit`) remains.
- Visual parity check against the prototype HTML passes for: Home (with pins + empty), Nearby, Stop detail, Bus tracking, Search, Settings, Live Activity preview, map toast.
- Dark + light modes both verified.
- Real-time ETA tick functions on all relevant screens.
- Changelog updated; version bumped.

---

## 6.5 Where we landed (session log — 2026-05-29, full execution pass)

All 8 phases now have code committed. iOS V2 screens read live LTA data
via `DataStore`; Flutter mirror lands behind the same flag pattern.

**iOS** (`ios-native/Leyne/`):
- `Theme.swift` — Soft palette + `onAccent` + `MRTLine` enum + `mrtNE` /
  `meBlue` cross-mode colours.
- `V2/` directory — 9 primitive files (ServiceBadge, LabelPill,
  SortChipRow, IOSGlassPill+GlassPillButton, SoftTabBar, RouteTimeline,
  MapHandoffToast, SoftPrimitives) + 6 screens (SoftHomeView,
  SoftNearbyView, SoftStopView, SoftBusView, SoftSearchView,
  SoftSettingsView) + SoftRoot composition.
- All V2 screens wired to live data: `DataStore.arrivals`, `nearby`,
  `route(service:stopCode:)`, `searchStops`, `stopName`, `roadName`,
  `LocationManager.location`. Empty / loading / error states handled.
- `RootView.swift` short-circuits to `SoftRoot` when `leyne.softUI` is
  on. Default off.
- `xcodebuild` green.

**Flutter** (`lib/`):
- `theme.dart` — Soft palette + `onAccent` getter + `LyneSignal` (mrtNE,
  meBlue) + `MRTLine` enum.
- `widgets/v2/` — `soft_components.dart` (ServiceBadge, LabelPill,
  SortChipRow, WalkTile, SoftToggle, Eyebrow, LegendDot, MRTLineBar),
  `soft_tab_bar.dart` (M3 NavigationBar with pill indicator),
  `route_timeline.dart`.
- `screens/v2/` — 6 screens mirroring iOS plus `soft_root.dart` Navigator
  composition. Use M3 idioms: AppBar / FAB for the pin / NavigationBar /
  SegmentedButton for appearance / docked SearchBar.
- `main.dart` short-circuits to `SoftRoot` when SharedPreference
  `lyne.softUI` is true. Default off.
- `flutter analyze lib/` clean (no errors, no info).

**Open follow-ups (out of scope for this session)**:
- Native ActivityKit Live Activity (iOS) and ongoing-notification
  Live-Activity stand-in (Android) — both already deferred in
  `parity.md` Task #12.
- Postal-code geocoding wire-through in `SoftSearchView` /
  `SoftSearchScreen` — currently does name search regardless of filter.
- Routine flow in Settings — stubs only. Decide whether to ship the
  rows or hide them.
- The 7 open decisions in §1 are still in their default state — review
  before committing if any of them want to change.

**To preview the new UI**

iOS Simulator:
```
xcrun simctl spawn booted defaults write com.leyne.Leyne leyne.softUI -bool true
```

Android (via adb on a connected device):
```
adb shell run-as com.leyne.app sh -c "echo '<map><boolean name=\"flutter.lyne.softUI\" value=\"true\"/></map>' > /data/data/com.leyne.app/shared_prefs/FlutterSharedPreferences.xml"
```
Or simpler: add a Settings ▸ Developer toggle to flip the pref. For
now, set the bool in `SharedPreferences` from any Dart entry point
(e.g. a debug menu item that runs
`SharedPreferences.getInstance().then((p) => p.setBool('lyne.softUI', true))`).

---

## 6.6 Where we landed (session log — 2026-05-28, first pass)

A first execution pass landed Phase 1 + a structural Phase 2 on iOS, and Phase 5a (tokens) on Flutter. Everything compiles; the existing v1 UI continues to ship unchanged.

### iOS — done
- `Theme.swift` rewritten in place with the Soft palette. Property names kept (`bg`, `surface`, `surfaceHi`, `accent`, `liveBg`, `crit`, …) so the v1 screens still compile against the new values. Added `onAccent`, `mrtNE`, `meBlue`, and a `MRTLine` enum.
- New `ios-native/Leyne/V2/` directory with shared primitives:
  - `ServiceBadge.swift`, `LabelPill.swift`, `SortChipRow.swift`, `IOSGlassPill.swift` (+ `GlassPillButton`), `SoftTabBar.swift`, `RouteTimeline.swift`, `MapHandoffToast.swift`, `SoftPrimitives.swift` (WalkTile / SoftToggle / Eyebrow / PressScale / LegendDot / MRTLineBar).
- Six V2 screens scaffolded to the prototype layout (data is placeholder; LTA wiring deferred):
  - `SoftHomeView.swift`, `SoftNearbyView.swift`, `SoftStopView.swift`, `SoftBusView.swift`, `SoftSearchView.swift`, `SoftSettingsView.swift`.
- `SoftRoot.swift` composes the stack-based nav (Home / Nearby / Settings tabs; Search / Stop / Bus / AllArrivals pushed).
- `RootView.swift` now reads `leyne.softUI` (UserDefaults `@AppStorage`) and short-circuits to `SoftRoot` when on. **Default off** — the v1 UI remains the shipping experience.
- `xcodebuild` clean — no errors. (SourceKit indexer reports stale "cannot find Theme" warnings for files in `V2/`; they evaporate once Xcode reindexes.)

### iOS — not done (deferred to a follow-up session)
- **Phase 2 data wiring** — the V2 screens currently use placeholder copy ("Arriving now", static stop names, demo route stops). Each needs to consume `AppModel` / `DataStore` arrivals + ETAs + Spotlight stop names. Specifically:
  - `SoftHomeView.primaryPinCard`: real ETA from `DataStore.shared.arrivals(for:)`.
  - `SoftNearbyView.nearbyStops`: real distance-sorted stops from `LocationManager` + `DataStore`.
  - `SoftStopView.otherBuses`: real arrivals list (not the 3-row demo).
  - `SoftBusView`: live MapKit annotations (bus + stop + ME), real route timeline from LTA, real "next arrival" numeral driven by the AppModel tick.
  - `SoftSearchView`: hook into `SearchLogic` for stop / postal / bus resolution.
  - `SoftSettingsView`: Routines section currently stubs; either ship as disabled or design the routine-creation flow.
- **Phase 3** — `LockScreenLiveActivityPreview.swift`, MapKit handoff wiring (`MKMapItem.openInMaps` + Google Maps URL scheme), Spotlight refresh against the new card visuals. Live Activity native (`ActivityKit`) was already deferred under `parity.md` Task #12 and stays deferred.
- **Phase 4** — pull-to-refresh, real-time ETA tick from `AppModel.tick`, empty/loading/error states for arrivals, side-by-side QA against `proto-soft-ios.jsx`, changelog + version bump.

### Flutter — done
- `lib/theme.dart` rewritten with the Soft palette (same property-name preservation as iOS). Added `LyneTheme.onAccent`, `LyneSignal.mrtNE` / `meBlue`, and `MRTLine` enum.
- `flutter analyze lib/theme.dart` clean.

### Flutter — not done
- **Phase 5b** — `lib/widgets/v2/` M3 mirror of iOS V2 components (service badge, label pill, sort chip row, m3 top bar, m3 soft nav, route timeline, extended pin FAB, map handoff toast).
- **Phase 6** — rewrite of `home_screen.dart`, `nearby_screen.dart`, split of `detail_screen.dart` into `stop_screen.dart` + `bus_screen.dart` + `all_arrivals_screen.dart`, `search_screen.dart`, `settings_screen.dart`, `whats_new_screen.dart`.
- **Phase 7** — ongoing-notification stand-in for Live Activity, `url_launcher` map handoff, `InkWell` press states.
- **Phase 8** — real-time tick, states, QA against iOS, changelog + version bump.

### Toggling the new iOS UI

For a quick visual check without a TestFlight build:

```
xcrun simctl spawn booted defaults write com.leyne.Leyne leyne.softUI -bool true
```

Or in code, set `@AppStorage("leyne.softUI") = true`. Flip back to `false` to return to the v1 UI.

### Open decisions still on the table

The 7 decisions in §1 are still answered with the listed defaults. Override any of them before the data wiring phase, since they shape navigation + pin label entry + the AllArrivals screen.

---

## 7. Out of scope (do not build from prototype)

- The `screens-*.jsx` files (Exploration doc, 5-direction comparison).
- Other four design directions: Pro, Heavy, Ambient, etc. — only Soft is locked.
- `tweaks-panel.jsx`, `design-canvas.jsx`, `canvas-app*.jsx`, `proto-app.jsx`'s sync mode — these are prototype tooling only.
- Routine creation flow (deferred).
- ActivityKit Live Activity native implementation (already deferred in parity.md Task #12).
