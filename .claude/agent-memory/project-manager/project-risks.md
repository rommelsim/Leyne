---
name: project-risks
description: "Key risks and dependencies for shipping Leyne V2 — likelihood, impact, and mitigations. Updated 2026-05-30 (post d3980e2)."
metadata:
  type: project
---

## Top risks as of 2026-05-30 (updated with Android audit findings)

### R0 — Android search chips DECORATIVE → LAUNCH BLOCKER / Play store rejection risk (Likelihood: High, Impact: Critical)
`soft_search_screen.dart:104` — `_results()` calls `DataStore.searchStops(q)` unconditionally regardless of filter state. The Postal, Bus#, StopID, and Place chips are purely cosmetic. `GeocodeService` and `DataStore.searchServices()` are never called. This is the **exact same Guideline 2.2 defect** that caused the iOS App Store rejection in build 2.2.1/2.2.3 (since fixed in `SoftSearchView.swift`). On Android it remains unfixed. Google Play "Deceptive Behavior" policy covers this; 5 of 6 audit agents flagged it independently.
**Mitigation:** Port the iOS fix to `soft_search_screen.dart` before submitting any Android AAB. Branch `_results()` on `_filter`: postal→`GeocodeService.postalCode`→stopsWithin; bus#→`searchServices`→originStop; stopID/place→`searchStops`. ~80 lines + FutureBuilder. Effort: L (~half day). This is Sprint 0 item S0-1 in [[android-quality-roadmap]].

### R0b — Alight alert never fires on Android (Likelihood: High, Impact: High)
`soft_bus_screen.dart:32,101-102` — `_alightId` is widget-local state; `AppModel.setActiveAlight()` is never called. The 🔔 ALIGHT chip renders, accepts taps, and shows nothing wrong — but schedules zero notifications. This is a functional promise the app does not keep.
**Mitigation:** Port `_onAlightChanged` from `lib/screens/detail_screen.dart:61-79`. Wire `onAlight`, clear on dispose. Sprint 0 item S0-2. Effort: M.

## Top risks as of 2026-05-30

### R1 — Second App Store rejection (Likelihood: Medium, Impact: High)
2.2.1/2.2.3 was rejected for Guideline 2.2 (beta labels + stub features). The 2.3.0 submission strips all "beta" text, wires the alight alert for real, and fixes iOS search chips. However, Android search chips remain decorative (`soft_search_screen.dart` routes all four chips to `searchStops`). If Apple reviews the Android binary or a reviewer stress-tests edge cases, a second rejection is possible.
**Mitigation:** Port the iOS postal/Bus#/StopID filter logic to `soft_search_screen.dart` before the next Android store submission. For the iOS-only 2.3.0 resubmit, risk is low (iOS fix is committed).

### R2 — What's New screen silently broken for all upgraders (Likelihood: High, Impact: Medium)
`kChangelog` in `AppModel.swift` only has a `"2.0.0"` entry. Current version is `2.3.0`. Every user upgrading from any version sees no What's New content — the screen never surfaces. This is a user-retention and trust-building miss, not a crash.
**Mitigation:** Add `"2.1.0"`, `"2.2.0"`, `"2.3.0"` entries to `kChangelog` before the next Archive. Small effort (~20 lines). Currently P1 pre-archive.

### R3 — Android ongoing notification is foreground-only (Likelihood: High, Impact: Medium)
The live-tracking notification (`leyne.tracking` channel) only updates while the app process is alive. A backgrounded user gets a frozen/stale notification. This is documented in CHANGELOG.md but not surfaced to users in-app.
**Mitigation:** Accepted for now. Must be in release notes. True fix requires an Android foreground service — substantial engineering. Copy in-app should say "updates while the app is open" (already fixed in the committed copy).

### R4 — iOS Archive ritual has manual error-prone steps (Likelihood: Medium, Impact: Medium)
The `forceTestUnitForRelease` toggle in `AdBanner.swift` is the only guard between serving test ads (TestFlight) and real ads (App Store). No automated check. A missed flip means either real ads in TestFlight (minor) or test ads in the store (policy violation).
**Mitigation:** Short-term: verify grep before each Archive (`grep forceTestUnitForRelease ios-native/Leyne/AdBanner.swift` must show `false`). Long-term: `check-ad-toggle.sh` gate in the Archive script (not yet built).

### R5 — Android exact-alarm permission regression (Likelihood: Low, Impact: High)
Must use `SCHEDULE_EXACT_ALARM` (not `USE_EXACT_ALARM`) in `AndroidManifest.xml`. Play Console rejects the latter.
**Mitigation:** Build script enforces the right flag. Never change without re-reading Play policy.

**Why:** Updated post d3980e2 commit. R1 (uncommitted work) fully resolved. R2 (kChangelog) elevated — it is the #1 remaining correctness issue before next archive.
**How to apply:** Run through R1–R4 at the start of any session that touches a build.

Related: [[project-status]], [[next-actions]]
