---
name: ad-revenue-estimate
description: >
  Estimate AdMob revenue for Leyne from the ad placements ("ads planted") across
  iOS and Android. Use when the user asks how much the ads could/will earn,
  to project ad revenue, to model revenue vs DAU, to compare what a new ad
  placement would add, or "calculate revenue based on number of ads." Produces a
  per-format and total daily/monthly estimate from stated assumptions.
---

# Ad revenue estimate

Estimate ad revenue from the placements actually shipped, on both platforms.
This is a **model**, not a guarantee — always state the assumptions and present a
low / mid / high range. Real numbers come from the AdMob console.

## What's planted (current inventory — verify before quoting)

Both iOS (`ios-native/Leyne/`) and Android (`lib/`) ship the same four formats.
Confirm placements against the code each time (placements change):

| Format | Unit | iOS file | Android file | Placement |
|--------|------|----------|--------------|-----------|
| Anchored adaptive **banner** | `AdConfig.bannerUnitID` / `_bannerUnitId()` | `AdBanner.swift` | `widgets/ad_banner.dart` | bottom of the non-Stop tabs (Home/Saved/Search/Settings/MRT) |
| **MREC** 300×250 | `AdConfig.mrecUnitID` / `_mrecUnitId()` | `AdBanner.swift` | `widgets/ad_banner.dart` | inline on the **Stop** screen (replaces the banner there — exactly one ad shows) |
| **Interstitial** | — | `InterstitialAd.swift`, `FullScreenAdGate.swift` | `services/interstitial_ad.dart`, `services/full_screen_ad_gate.dart` | on exit from Stop/Bus detail, frequency-capped |
| **App-open** | — | `AppOpenAd.swift` | `services/app_open_ad.dart` | warm resume only (cold-launch disabled) |

> AdMob publisher account is in memory (`pub-5864511655536507`). A dedicated MREC
> unit is still a TODO — MREC currently reuses the banner unit, so its reporting
> is shared (note this caveat in any per-format breakdown).

## Inputs (ask, or use these defaults — clearly label them as assumptions)

- **DAU** per platform (the main driver). If only MAU is known, DAU ≈ MAU × 0.2–0.4.
- **Sessions / user / day** — default 2.
- **Impressions per session, per format:**
  - banner: ~1 refreshing unit visible per screen → assume ~3–6 impressions/session
  - MREC: ~1 per Stop visit → ~1–2 impressions/session
  - interstitial: frequency-capped → ~0.5–1 impressions/session
  - app-open: warm resume only → ~0.5 impressions/session
- **Fill rate** — default 0.9.
- **eCPM (USD)** — geo-dependent (Leyne is Singapore, mid-tier eCPM). Defaults as
  ranges; let the user override with real console eCPMs:
  - banner: $0.50 – $2.00
  - MREC: $1.00 – $3.50
  - interstitial: $3.00 – $9.00
  - app-open: $2.00 – $6.00

## Formula

For each platform, for each format:

```
daily_impressions = DAU × sessions_per_day × impressions_per_session × fill_rate
daily_revenue     = daily_impressions × (eCPM / 1000)
```

Then:

```
platform_daily = Σ formats
total_daily    = iOS_daily + Android_daily
monthly        = total_daily × 30.4
```

## Output

1. Restate the input assumptions (DAU per platform, sessions, eCPMs used).
2. A table: format | platform | daily impressions | daily $ (low–high).
3. Per-platform and combined **daily** and **monthly** totals, as a low / mid /
   high range.
4. Caveats: estimates only; MREC shares the banner unit today; eCPM varies by geo
   and season; actuals live in the AdMob console.

## Notes

- If the user asks "what would adding placement X earn," model the delta: extra
  impressions/session × DAU × eCPM, holding everything else constant.
- Keep it UX-first per the monetization plan — if asked, flag when a placement
  count would hurt retention rather than just maximizing the number.
