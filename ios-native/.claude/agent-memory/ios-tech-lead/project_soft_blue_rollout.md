---
name: project-soft-blue-rollout
description: Per-screen progress converting WhereSia from greendark to the soft-blue "4b" design language
metadata:
  type: project
---

The app is mid-pivot from the "greendark" dark palette (`WSTheme.swift`,
design-greendark branch, 2026-07-24) to the "soft blue 4b" language
(`WSSoftTheme.swift`: tinted `SoftBlue.bg` ground, white `SoftBlue.card`
floating cards, one blue accent, `SoftMotion` water/cloud easing). Owner
picked soft-blue over greendark on 2026-07-24/25; the conversion is
COMPLETE as of 2026-07-25 — every WhereSia screen plus widgets/Live
Activity/app icon are soft-blue. Greendark survives only as dormant code
(`WSTheme.swift` tokens, WSHomeView's unused `darkBody`).

**Converted to soft-blue (ALL screens, 2026-07-24/25):**
- `WSHomeView.swift` (Nearby/Home) — first screen, source of the shared
  tokens/components in `WSSoftTheme.swift`.
- Stop detail (`WSBusStopView.swift`), MRT station, Search, Saved, Alerts,
  ServiceInfo, tab bar — 2026-07-25 rollout (docs/soft-blue-design.md).
- Widgets + Live Activity (`LeyneWidgets/`) — 2026-07-25, local
  `WidgetSoftBlue`-style tokens (extension can't import the app target).
- App icon — sky-blue re-palette 2026-07-25 (assets/icon/src/).
- `WSMapView.swift` (Nearby Map) — last one, converted 2026-07-25. Light MapKit style
  (removed the forced `.environment(\.colorScheme, .dark)` on the `Map`),
  white `SoftIconButton`/card chrome, bus stops in `SoftBlue.blue`, MRT/LRT
  markers keep official line colours (never restyled — identity rule).
  Bottom stop/station cards use `softCard()` + `SoftBusTimePill` instead of
  the old `RouteTile`/`ArrivalPill` pair. Added an optional `color:` param
  to the shared `WSPing` (`WSComponents.swift`) so soft-blue screens can
  pass `SoftBlue.blue`/a line colour instead of inheriting greendark mint
  `ws.accentSoft` — existing greendark call sites are unaffected (param
  defaults to nil → old behavior).

**Why it matters for review:** the rollout is complete, so a screen reading
greendark colour tokens (`ws.accent`, dark literals) IS now a bug — except
inside the deliberately-dormant `darkBody`/`WSTheme` code. The soft-blue
convention is: keep `ws.sans`/`ws.mono` for
Dynamic-Type fonts, but never read colour off `ws` — use raw `SoftBlue.*`
tokens instead.

See also [[project_ios_rewrite_state]].
