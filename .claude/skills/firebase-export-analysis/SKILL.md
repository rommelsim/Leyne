---
name: firebase-export-analysis
description: >
  Analyze Leyne's Firebase / Google Analytics (GA4) exports and turn them into
  revenue + growth decisions. Use when the user shares a Firebase/GA4 export
  (CSV, screenshot, or pasted numbers), asks for a daily/weekly analytics review,
  wants to know DAU / retention / ARPDAU / ad-revenue trends, or asks "what
  should I do to grow / earn more" from the data. Produces a structured read of
  the numbers, what changed vs last time, and a ranked list of concrete actions.
  Pairs with ad-revenue-estimate (projection) — this skill works the ACTUALS.
---

# Firebase export analysis

Leyne ships Firebase Analytics + Crashlytics (Phase 0, iOS first — see
`docs/firebase-setup.md`). This skill reads what comes back out and decides what
to do next. The job is **measurement → decision**, never just describing numbers.

> Project: `leyne-da16f` · AdMob `pub-5864511655536507` · market: Singapore (SGD).
> Revenue is **ads-only** (no IAP). The dominant lever is DAU; ad tuning is
> secondary. See the revenue model below.

## 0. Reality checks before reading anything

- **Data lag:** standard reports/GA4 lag ~24–48h. Realtime = last 30 min only.
  DebugView shows ONLY debug devices — never treat it as real traffic.
- **Shipped?** Analytics only accrue from an installed build carrying the SDK.
  If no analytics build is live yet, every report is empty/your own test
  session — say so and stop. Don't analyze a test session as if it were users.
- **iOS vs Android:** iOS shipped Phase 0 first. Until Android's google-services
  + SDK ship, GA4 is iOS-only — scope every conclusion to the platform present.
- **Cardinality:** high-cardinality params (`stop_code`) bucket to "(other)"
  after ~500 distinct values in standard reports. Top values are fine; full
  per-stop work needs BigQuery (Blaze plan) — flag it, don't fake it.

## 1. What to ask the user to export

Request whichever of these are relevant (CSV from GA4, or a screenshot):

| Report | Where | Gives |
|--------|-------|-------|
| **Dashboard / Realtime** | Firebase → Analytics → Dashboard | DAU (1/7/30-day actives), trend |
| **Retention** | GA4 → Reports → Retention (or Explore → Cohort) | D1/D7/D30 cohorts |
| **Events** | Firebase → Analytics → Events | counts per event (the 7 below) |
| **ad_impression revenue** | GA4 → Monetization / Explore on `ad_impression` `value` | ad revenue, by `ad_format` / `ad_unit_name` |
| **Funnel** | GA4 → Explore → Funnel | first_open → stop_viewed → favourite_added |
| **Crashlytics** | Firebase → Crashlytics | crash-free users %, top crashes |

If they only have a screenshot of the AdMob "App overview" (earnings, eCPM,
match rate, per-unit), analyze that too — it's the revenue side; GA4 is the user
side. Best decisions come from both together.

## 2. The Leyne event model (what each signal means)

The 7 instrumented events and how they map to the growth funnel:

- `app_open` / `session_start` (auto) → engagement frequency (transit apps reopen
  many times/day — high frequency is the whole value prop).
- `stop_viewed` (`kind`: bus|mrt) → core action. The numerator of "did they use it."
- `favourite_added` (`kind`: stop|service) → **the habit signal.** Pinning predicts
  retention; treat it as the key activation event.
- `search_performed` → discovery; high search w/ low favourite = activation leak.
- `alert_set` → deepest engagement (intent to rely on the app).
- `onboarding_completed` → top-of-funnel completion; gap vs first_open = onboarding drop.
- `notification_tapped` → proven value moment (also drives the ratings prompt).
- `ad_impression` (ILRD: `value`, `currency`, `ad_format`, `ad_unit_name`) → revenue,
  attributable per user/cohort.

## 3. Revenue model (compute these every time)

```
ARPDAU      = ad_revenue / DAU            # revenue per daily active user
revenue     ≈ DAU × ARPDAU                # the whole game
ARPDAU      ≈ impressions_per_DAU × eCPM / 1000
activation  = favourite_added users / new users      # habit rate
funnel_drop = 1 − onboarding_completed / first_open  # onboarding leak
```

Anchor points (update as actuals arrive): early read was ~35 DAU, blended eCPM
~SGD 0.77, ARPDAU ≈ SGD 0.008. First meaningful money (~SGD 100+/mo) lands near
**500 DAU**. Revenue scales ~linearly with DAU, so retention > ad tuning.

## 4. Analysis steps

1. **Restate the window + scope** (date range, platform, shipped-or-test).
2. **Pull the headline numbers:** DAU, new users, retention D1/D7, ad revenue,
   ARPDAU, eCPM, crash-free %.
3. **Delta vs last update** (this is why daily cadence matters — track the
   direction, not just the level). Keep a running note in the analysis history
   file (see §6) so trends are visible.
4. **Funnel + activation:** first_open → onboarding_completed → stop_viewed →
   favourite_added. Where's the biggest leak?
5. **Revenue breakdown:** ad_impression `value` by `ad_format`/`ad_unit_name`.
   Is the interstitial still ~dead? Is App Open pulling weight? eCPM trend?
6. **Anomalies:** crash spikes, an event that flatlined (instrumentation broke?),
   a retention cliff.
7. **Decisions** (§5).

## 5. Decision rules (what to actually do)

- **Retention is the priority lever.** If D7 < ~15%, growth/ads work is premature
  — fix the leak first (onboarding, activation-to-pin). Every retained user is
  linear revenue.
- **Activation:** high `search_performed` / `stop_viewed` but low `favourite_added`
  → push pinning in onboarding/UI. Pinning is the habit that monetizes.
- **Ad placement:** only tune ads once retention is stable. Use Remote Config to
  A/B (MREC vs banner, interstitial cadence) and measure revenue AND retention —
  never trade one blindly for the other.
- **The dead interstitial:** if `ad_impression` for Interstitial stays ~0 while it's
  enabled, diagnose trigger/cap (it's frequency-gated off by default — confirm
  `InterstitialAdConfig.enabled`). Fixing it is "free" revenue.
- **eCPM:** blended SGD 0.77 is depressed; expect drift up as the optimizer
  matures + App Open weights in. Track it; don't over-react to one bad day.
- **Backend trigger:** only build server push when **D7 > 20% AND DAU > ~500**
  (growth-review rule). This skill is how you know you've hit it.
- **Crashes:** a falling crash-free % silently bleeds retention — top crashes
  jump the queue.

## 6. Output format

Produce a tight **daily/period review**, not a data dump:

1. **Scope line** — window, platform, shipped-or-test.
2. **Headline table** — DAU, new, D1/D7, ad rev, ARPDAU, eCPM, crash-free %,
   each with ▲/▼ vs last update.
3. **Funnel read** — one line on the biggest leak.
4. **Revenue read** — one line on per-format split + eCPM.
5. **Top 1–3 actions**, ranked, each tied to the number that justifies it.
6. **Watch-list** — anything ambiguous to confirm next update.

Append the headline numbers to `docs/analytics-log.md` (create if missing — a
dated one-line history) so deltas are real and trends are visible over weeks.

## Notes

- Firebase Analytics volume is free + uncapped on Spark; DAU scale is never the
  bottleneck (built for billions of events/day). Limits are 500 event names and
  param cardinality, not volume — reassure if asked.
- When data is thin (first days post-launch), say so and resist over-reading
  noise; daily cadence is for catching the *trend*, not reacting to one day.
- Cross-reference `ad-revenue-estimate` to project forward from the actuals here,
  and the growth plan (`MEMORY.md → growth_plan`) for the strategic frame.
