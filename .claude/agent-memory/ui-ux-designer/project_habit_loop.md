---
name: habit-loop-strategy
description: "Habit-forming UX strategy for Leyne — trigger/action/reward/investment analysis, commute card, notification plan, and top-5 retention changes (2026-06-09)"
metadata:
  type: project
---

Leyne's biggest retention gap is the **missing external trigger**. The habit loop
is otherwise sound (fast reward via live ETAs, investment via pinning), but the
app is entirely reactive — it only works when the user already has the habit.

## Key decisions from the 2026-06-09 growth strategy session

**#1 priority: Commute-time reminder notification**
- Two time pickers in Settings (Morning / Evening), weekday-only toggle.
- Pure on-device: `UNCalendarNotificationTrigger` on iOS, `AlarmManager` on Android.
- Off by default; surfaced in onboarding as an optional fourth step after the
  three permission steps (location/notifs/ATT).
- Suppress next reminder if user opened app within 5 min of that slot firing.
- Mon–Fri only by default; weekend toggle available.

**Context-aware commute card on Home (view-layer only, no new model)**
- Appears above the nearby stops list during 6:00–9:30am and 5:00–8:30pm weekdays.
- Shows first pinned stop with top-2 services and 3-col ETAs.
- Bell icon in card corner opens StopAlertSheet directly.
- Outside commute windows: collapses to a 2-line row.
- Does NOT require a backend or My Commute model — pure `m.pins + Date()`.

**Post-onboarding notification recovery**
- If notifications were skipped in onboarding, show a one-shot t.surface pill
  banner at the top of Home on first open (not blocking; dismiss forever on tap-outside).

**Notification copy personalisation**
- If location granted → nearest stop name resolved before notification primer:
  replace generic "Never miss your bus" with "Know when to leave [Stop Name]".

**Share ETA virality**
- ShareLink (iOS) / share_plus (Android) on Stop detail screen.
- Produces: "Bus 67 at Bishan Interchange: 4 min, 9 min, 14 min\nleyne.app/stop/75009"
- Universal link → App Store / Play Store fallback. No backend needed.

**Ratings prompt timing**
- After Live Activity ends with `arrived: true` (peak reward moment), OR
- After user's 3rd distinct calendar day of use (tracked in UserDefaults).
- iOS: SKStoreReviewController. Android: Play In-App Review API.

**Widget discovery prompt**
- One-shot card on Home after first successful Stop detail view + first pin exists.
- "Show me how →" → WidgetCenter hint on iOS.

## What genuinely needs backend (deferred)
- "Leave now" intelligence (personalised walk-time + specific bus alert)
- Bus delay / disruption push (LTA has no per-bus delay feed)
- True My Commute screen (home stop ↔ office stop model)

See [[redesign_9screen_2_4_0]] — My Commute screen explicitly deferred.
See [[ios_widgets]] — widget set exists; discoverability is the gap.
