# Leyne — Platform Parity Tracker

**Purpose:** what's in iOS-native (`ios-native/`, v2.2.0+9) that Flutter Android (`lib/`, v2.1.0+8) hasn't caught up to. This is the porting work queue if/when Android is brought to design parity with the new Variant B Smart Hero.

**Last reconciled:** 2026-05-25 (after the no-ads ship-prep).

**How to use:** when a row says "iOS only", the iOS implementation is the spec — port to Flutter when prioritized. When a row says "Flutter only", iOS is missing it. When a row says "both, diverged", treat the iOS version as canonical and fix Flutter (per `design-spec.md`).

---

## Legend

- ✅ — implemented to spec
- 🟡 — partial / older design
- ❌ — not implemented
- ➖ — N/A (platform doesn't support)

---

## Visual / design

| Area | iOS-native | Flutter | Notes |
|---|---|---|---|
| Variant B Smart Hero card | ✅ | ❌ | Flutter still has the v2.0 fixed hero layout |
| Liquid Glass surfaces (`glassSurface`) | ✅ | ❌ | Flutter `BackdropFilter` approximation needed; won't match natively |
| Operator stripe (3pt left edge) | ✅ | ❌ | New in iOS-native |
| Heartbeat pulse on arriving cards | ✅ | ❌ | 1.012 scale, 1.4s repeatForever |
| Staggered entrance (60ms per-card) | ✅ | ❌ | Pinned card list |
| Editable stop label with pencil affordance | ✅ | 🟡 | Flutter has rename but UX is older |
| Sticky compact bar on Home + Nearby | ✅ | 🟡 | Flutter has it but glass is opaque |
| Pull-to-refresh (custom indicator) | ✅ | 🟡 | Flutter uses standard `RefreshIndicator` |
| Coachmark on first card | ✅ | ❌ | "Long-press to make primary" hint |
| Swipe-hint chevrons on Detail pager | ✅ | ➖ | Pager only exists on iOS |
| Primary-bus long-press menu | ✅ | ❌ | Flutter has tracked-list, no primary lock |
| FlowChip recents (horizontal scroll, clock glyph) | ✅ | 🟡 | Flutter wraps; refactor to horizontal scroll |
| "Scan poster QR" footer in search | ❌ | ❌ | Removed from both — keep removed |
| Postal-code → nearest-stops query | ✅ | 🟡 | Both have it; iOS layout is the new spec |
| Onboarding 5-step flow | ✅ | 🟡 | Flutter has older 4-step ad-prompt sequence |

---

## Detail view

| Area | iOS-native | Flutter | Notes |
|---|---|---|---|
| Stop-overview Mode A (services list) | ✅ | 🟡 | Flutter shows services but layout differs |
| Service drill-in Mode B (hero card) | ✅ | ❌ | Flutter never had Mode B |
| Live map embed (Apple Maps / OSM) | ✅ | 🟡 | Flutter has `flutter_map` (OSM); marker styling diverged |
| Route progress vertical stem | ✅ | ❌ | Not in Flutter |
| Live Activity "Start" button | ✅ | ➖ | ActivityKit is iOS-only; Android has no equivalent (foreground service possible) |
| Notify-2-min-before card | ✅ | 🟡 | Flutter has the toggle, different visual |
| Editable big title with pencil | ✅ | 🟡 | |
| Walk-time meta in heading | ✅ | 🟡 | |

---

## Home

| Area | iOS-native | Flutter | Notes |
|---|---|---|---|
| Global hero (smallest ETA-walk margin) | ✅ | ❌ | Flutter has no hero selection logic |
| Pinned card edit mode (draggable) | ✅ | 🟡 | Flutter has reorder, different drop indicator |
| "N/M tracked" subtitle | ✅ | 🟡 | |
| Day/date eyebrow | ✅ | ✅ | |
| Live chip with freshness states | ✅ | 🟡 | Flutter has live/stale, no offline-red state |
| Empty state with two CTAs | ✅ | 🟡 | |

---

## Search

| Area | iOS-native | Flutter | Notes |
|---|---|---|---|
| Search field on glass top bar | ✅ | 🟡 | Flutter has opaque |
| Detected-kind pill | ✅ | ✅ | |
| Recent FlowChips (horizontal scroll) | ✅ | 🟡 | Flutter wraps |
| SRRow (bus lead / icon lead) | ✅ | 🟡 | |
| Postal-code mode | ✅ | ✅ | Layout differs |
| "Stops near me" card → Nearby | ✅ | ✅ | |
| Embedded ad banner | ❌ | ❌ | Removed from both for ads-disabled build |

---

## Nearby

| Area | iOS-native | Flutter | Notes |
|---|---|---|---|
| Sort buttons (3 capsules) | ✅ | 🟡 | |
| Row with distance column | ✅ | 🟡 | iOS layout is the new spec |
| Inline service chips | ✅ | 🟡 | |
| "ARRIVING" pill | ✅ | 🟡 | |
| Radius chip top-right | ✅ | 🟡 | |

---

## Onboarding

| Area | iOS-native | Flutter | Notes |
|---|---|---|---|
| 5 steps: Hero → Pin → Narrow → Notify → Location | ✅ | ❌ | Flutter has older 4-step flow |
| Step transitions (`.opacity + .move`) | ✅ | 🟡 | |
| Visual mocks per step | ✅ | 🟡 | Different mocks |
| Dot indicators (20×6 active) | ✅ | ✅ | |

---

## Platform integrations

| Area | iOS-native | Flutter | Notes |
|---|---|---|---|
| Live Activities (ActivityKit) | ✅ | ➖ | iOS only |
| Widget (WidgetKit) | 🟡 | ➖ | Stub on iOS, not built yet |
| Spotlight search | ✅ | ➖ | iOS only |
| App Links / Universal Links | ✅ | ✅ | `lyne.sg/stop/{code}`, `lyne.sg/service/{busNo}` |
| Custom URL scheme | ✅ | ✅ | `lyne://stop/{code}` |
| Apple Maps (iOS) / OSM (Android) | ✅ | ✅ | Intentionally divergent |
| In-app review prompt | 🟡 | 🟡 | |

---

## Data / behavior

| Area | iOS-native | Flutter | Notes |
|---|---|---|---|
| Pin model (stop + nickname + tracked + primaryBus) | ✅ | 🟡 | Flutter has no `primaryBus` field |
| Recent searches (max 8, dedup) | ✅ | ✅ | |
| Live chip freshness windows | ✅ | 🟡 | |
| 2-min notification threshold | ✅ | 🟡 | |
| Hidden service filtering | ✅ | ✅ | |
| App Group storage (shared with widget) | ✅ | ➖ | iOS only |
| Background polling tick | ✅ | 🟡 | Flutter has timer, less efficient |

---

## Ads / monetization (current state)

| Area | iOS-native | Flutter | Notes |
|---|---|---|---|
| Master switch `adsEnabled = false` | ✅ | ✅ | Both shipping no-ads while AdMob suspended |
| Banner reservation when disabled | ❌ | ❌ | Both short-circuit to `SizedBox.shrink()` |
| Privacy manifest reflects no-ads | ✅ | ➖ | iOS xcprivacy stripped |
| `AD_ID` permission disabled | ➖ | ✅ | Android manifest comments it out |
| ATT prompt removed | ✅ | 🟡 | iOS-native removed; Flutter still calls if iOS |
| UMP / consent flow gated | ✅ | ✅ | `AdConsent.gatherThenStart()` early-returns |

When AdMob is reinstated: flip both `adsEnabled` flags + restore xcprivacy entries + uncomment Android `AD_ID` permission. They move in lock-step.

---

## Priority order for porting (if Android is brought to parity)

These are the changes that would do the most to make Flutter Android *feel* like the new Leyne, in rough ROI order:

1. **Variant B Smart Hero on Detail Mode B** — biggest visual delta. Without this, Android looks like the v2.0 app.
2. **Operator stripes + arriving pill on pinned card service rows** — quiet but defines the new identity.
3. **Heartbeat pulse + staggered entrance** — the "alive" feel of the new app.
4. **5-step onboarding** (without the ad-prompt step).
5. **Glass-equivalent surfaces** (Flutter `BackdropFilter` with frosted overlay — won't match iOS 26 Liquid Glass, but lifts the perceived quality).
6. **FlowChip horizontal scroll** for recents.
7. **Primary-bus long-press** for hero locking.
8. **Custom pull-to-refresh** with the arrow rotation.

Anything iOS-only (Live Activities, Spotlight, App Group) stays iOS-only — Android has no equivalent that's worth the effort for a solo dev.
