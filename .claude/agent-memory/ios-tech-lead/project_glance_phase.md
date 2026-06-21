---
name: project-glance-phase
description: Glance redesign phase status — which phases are done, what branch, and what to verify
metadata:
  type: project
---

ALL 5 phases of the Glance redesign are implemented on the `retention-ux` branch.

**Phase 0:** Design tokens — `t.brand`, `t.go`, `t.warnText`, `t.ink3`, `Theme.cardRadius/badgeRadius/chipRadius`, `t.rounded()`, `.glanceCard(fill:)` in `Theme.swift`.

**Phase 1:** Home (departures board) — `SoftHomeView.swift`. DepartureCards, pinned stops, context line. Phase 5 added optional callbacks: `onOpenSaved`, `onOpenAlerts`, `onOpenSettings`.

**Phase 2:** Rail — `SoftMrtView.swift`, `SoftMrtLineView.swift`, `SoftMrtStationView.swift`.

**Phase 3:** Bus + GO — `SoftBusView.swift` (floating glass back, glanceHero, liveMapCard, startTripButton), `LiveTripView.swift` (GOPhase enum, stopsRemaining, haptic).

**Phase 4:** Search + Trip — `SoftSearchView.swift` (nearbyNowBoard, ServiceBadge leads), `TripResultsView.swift` (UI-complete shell, no routing engine).

**Phase 5 (2026-06-20):** Settings/About, IA cleanup — `SoftSettingsView.swift` (rewrite), `SoftRoot.swift` (rewrite).

**Phase 5 IA key facts:**
- Tabs: 5 → 2 (Now · Rail). `SoftTab` enum still has all 5 cases — only `.home` and `.mrt` are used.
- Search: fullScreenCover from Now search bar. `onOpenSearch` still the callback name.
- Saved: `.sheet` from star button in Now search bar → `savedSheet` in SoftRoot.
- Alerts: `.sheet` from bell button in Now search bar + overlay bell on Rail tab.
- Settings: `.sheet` from gear button in Now search bar + overlay gear on Rail tab.
- MRT rail tab: `mrtHeaderControls` overlay (bell + gear ultraThinMaterial circles, top-trailing).
- Deep links: unchanged. `m.openCard` → `homeStack`/`mrtStack`. `RootView.onOpenURL` unchanged.
- `SoftAlertsView` still has its own `showSettings` (gear in its scroll header → nested Settings sheet). Keep this.

**Phase 5 Settings redesign:**
- `AboutView` extracted as separate struct (in `SoftSettingsView.swift`), presented as `.sheet`.
- Identity hero card: gradient tile + "Leyne · Singapore bus & MRT · vX.Y.Z".
- Glyph tiles: 30×30 coloured rounded tiles (Color.gtGreen/gtGold/gtIndigo etc.).
- `openBuyMeCoffee` → `https://rommelsim.github.io/Leyne/support.html`.

**Phase 5 version bump:** `kChangelog["3.0.0"]` added to AppModel. CHANGELOG.md updated.

**How to apply:** When touching SoftRoot, tabs = `.home` and `.mrt` only. Everything else is a sheet. Do NOT reinstate Saved/Search/Alerts/Settings as tabs.
