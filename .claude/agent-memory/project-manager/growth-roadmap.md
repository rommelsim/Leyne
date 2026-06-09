---
name: growth-roadmap
description: "DAU growth strategy and phased roadmap — Phase 0 (analytics), Phase 1 (ASO/ratings/share/onboarding), Phase 2 (Android widgets), Phase 3 (backend+push). RICE scores and critical path documented. Authored 2026-06-09."
metadata:
  type: project
---

Leyne growth plan authored 2026-06-09 to drive DAU → ad revenue.

**Key finding: Zero analytics instrumentation today.** No Firebase, no Mixpanel, no crash reporting. DAU is unknown. This is Phase 0 — mandatory before any other investment can be validated.

**Revenue formula:** eCPM × DAU × sessions/day × impressions/session. DAU is the multiplier.

## Phase 0 — Measurement (3–5 days, FIRST)
- Firebase Analytics + Crashlytics (Flutter: package; iOS: SPM)
- 5 core funnel events: onboarding_started, onboarding_permission_granted, stop_viewed, bus_tracked, alert_set
- AdMob ILRD → Firebase link (free, enables ARPDAU visibility)

## Phase 1 — Quick Wins (2–3 weeks, no backend)
Top RICE items (no-backend, ship immediately):
- ASO keyword refresh (both stores): "SingaBus alternative", "Singapore bus arrival", "LTA bus timing", "SG bus ETA"
- Ratings prompt: StoreKit/in_app_review, triggered AFTER first successful arrival notification fires (highest-confidence value moment)
- Share stop ETA: native share sheet with lyne:// deeplink (organic WhatsApp/Telegram loop)
- Android onboarding footnote parity (missing vs iOS today)
- Location-denied recovery banner (contextual "Open Settings" CTA)

## Phase 2 — Android Widgets (3–4 weeks, parallel with Phase 1, no backend)
Largest parity gap. iOS has 3 widgets + Live Activity; Android has NONE.
- Approach: Kotlin Glance native module alongside Flutter (same pattern as iOS WidgetKit)
- Priority: Pinned Stop (M size, 3-ETA columns) → Nearby (S/M) → onboarding entry point
- WorkManager for 15-min refresh (OS minimum)
- Gate to proceed: spike day 1 to confirm Glance bridging is feasible

## Phase 3 — Backend + Push (4–6 weeks, START ONLY IF D30 retention > 20%)
- Minimum backend: Firebase + Cloud Functions (free tier until ~10k DAU)
- FCM push token registration → LTA disruptions polling → My Commute AM/PM push
- LTA caveat: NO per-bus delay feed. Push scope = MRT/LRT disruptions + feeder bus alerts at affected interchanges
- Interstitial enable: flip kLyneInterstitialEnabled when Analytics confirms DAU > 1000
- Mediation (AppLovin/Meta) after ILRD data shows fill rate gaps

## Critical path gating
- Backend is NOT a gate for widgets, analytics, ASO, ratings, or share sheet
- Backend IS a gate for: any push while app is closed, My Commute, disruption alerts
- AdMob MREC dedicated unit: create in console before next store submission (policy risk — currently reuses banner unit)

## RICE top 5 (DAU-relevant)
1. Ratings prompt (700 — after first notif fires)
2. ASO refresh (640)
3. Onboarding optimization (600)
4. Analytics (475)
5. Share sheet (84)

## Open risks
- R1: No retention baseline (HIGH likelihood/impact — Phase 0 mitigates)
- R3: LTA no per-bus delay feed (HIGH likelihood — scope push to MRT disruptions only)
- R5: Solo dev bandwidth (HIGH — serialize Phase 1 before Phase 2, gate Phase 3 on data)
- R7: AdMob MREC reuses banner unit (HIGH likelihood, open policy risk)

See [[admob-revenue-plan]], [[ios-widgets]], [[android-quality-roadmap]]
