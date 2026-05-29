---
name: project-feature-gaps
description: Features promised by onboarding/legacy but missing or stubbed in Leyne's live Soft UI
metadata:
  type: project
---

Live Soft UI (V2) is mid-rewrite; several core promises are unmet (as of 2026-05-29):

P0 gaps 1–3 below were CLOSED on 2026-05-29 (see resolution note at end) — verify against code before re-flagging.

1. **Notify-when-bus-is-close** [RESOLVED] — Onboarding Step 3 promises "Set notify-at-2-min on any stop." Legacy `DetailView.notifyCard` had it. NO notify toggle existed in `V2/`. `SoftBusView.liveActivityCTA` is still a no-op (TODO: ActivityKit, parity.md Task #12). Headline value prop. Now delivered via per-bus bell on SoftStopView (tracking a bus arms the existing ~1-min-before arrival alert) + a real Notifications screen in Settings.
2. **Bus narrowing / "track only buses you ride"** [RESOLVED] — Onboarding Step 2 promises it; legacy `AddStopSheet` had it. `SoftStopView` Pin button used to pin ALL services. Now each bus row has a bell wired to `m.toggleTracked`, and the top pill is a track-all/clear master (`m.setAllTracked`) showing "Tracking N".
3. **Dead Settings rows** [PARTIALLY RESOLVED] — `SoftSettingsView` was rewritten to a native inset-grouped `List`. "Notifications" is now a real `NavigationLink` → legacy `NotificationsView` (reused as-is; uses V2 Theme). "Language" row was REMOVED (no destination existed; removed rather than leave a dead chevron). Native List supplies chevrons only for nav rows now.
4. **Search filter chips are cosmetic** — `SoftSearchView` Postal/Bus#/Place all fall through to `ds.searchStops(query)` (name search). Only Stop ID is real.
5. **Alight scheduling** writes UserDefaults keys but isn't wired to NotificationsManager (comment says Phase 3).
7. **SoftBusView map bus marker** [RESOLVED 2026-05-29 SoftBusView pass] — legend BUS entry removed, dead `r.busCoord` annotation branch + `MapBusMarker` struct deleted, honest "Live bus position isn't available" caption added under the map. Live bus marker stays DEFERRED behind that empty state (DataStore.route still hard-codes busCoord: nil). `MapStopMarker` redrawn as filled accent ring+pin so it's unambiguous vs the system blue user dot. Timeline `.here`/"X STOPS AWAY" still unreachable until busIndex is populated, but harmless (guarded).
8. **SoftBusView route-timeline fake clock ETAs** [RESOLVED 2026-05-29] — deleted `estimatedMinutes` + `RouteTimeline.clockETA` + `RouteStop.etaMin` + the `now` param. Timeline is now a clean route list (no per-stop times); kept tap-to-alert + real-data highlights. No replacement times invented.
9. **`Service.monitored` not surfaced in SoftBusView** [RESOLVED 2026-05-29] — added `liveSchedTag` (mirrors SoftStopView: dot.radiowaves / clock, "live"/"sched") in the hero card under the destination row, shown when a service is loaded.
10. **SoftBusView "Following 17min · 32min" copy** [RESOLVED 2026-05-29] — eyebrow relabeled "Following" → "Next buses". Values unchanged.
6. **No pin reorder/rename/unpin affordance** in the live Home (onboarding promises "Rename them. Reorder them."). Unpin only reachable from inside Stop detail.

**Why:** A flow that promises alerts in onboarding but can't set one fails the core job-to-be-done; dead chevrons erode trust.
**How to apply:** Prioritize re-surfacing notify-at and bus-narrowing as P0/P1 in any roadmap discussion. Re-verify against code each time — these are actively being built and may have landed.

**Resolution (2026-05-29 SoftBusView "now" pass):** Gaps 7–10 closed, scoped to `SoftBusView.swift` + `RouteTimeline.swift`. Live Activity CTA hidden (removed from `body`, view kept + TODO → parity.md Task #12) — re-add the call site to restore. Build verified (scheme Leyne, iPhone 17 Pro sim). Live bus marker remains the one deferred item, behind the honest empty state.

**Resolution (2026-05-29 P0 pass):** Gaps 1+2 are the same affordance — the model already auto-schedules arrival alerts for tracked buses, so the fix was purely UI: a per-row bell + track-all pill on `SoftStopView`. Gap 3 fixed by native-List rewrite of `SoftSettingsView` + reusing legacy `NotificationsView`. Build verified (scheme Leyne, iPhone 17 Pro sim). Still OPEN: SoftBusView Live Activity CTA (#1 tail), gaps 4/5/6, and the P1 Dynamic Type / VoiceOver pass (deliberately deferred — bell/pill got a11y labels but no full audit). User is OPEN to native SwiftUI swaps (List/Form/Toggle/.searchable) as long as the Soft brand stays inside cells.
