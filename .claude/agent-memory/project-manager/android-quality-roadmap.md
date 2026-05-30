---
name: android-quality-roadmap
description: "Full Android quality remediation roadmap from 6-agent audit 2026-05-30 — severity-ranked, sized, sequenced into 4 sprints."
metadata:
  type: project
---

## Context
Six specialist agents (android-tech-lead, qa, ux, devops, business-analyst, ios-tech-lead) audited the Flutter V2 Android app (`lib/screens/v2/`) on 2026-05-30. 36 distinct findings across 5 categories. This roadmap supersedes the loose "pre-ship polish" items in [[next-actions]] for the Android track.

## Headline answer
The two root causes of Android disappointment:
1. **Functional features are wired to nothing** — search chips (5/6 agents), alight alert, live/GPS provenance, third arrival, route ETA fabrication all look real but aren't. This is a trust/honesty problem, and one of them is a repeat store-rejection risk.
2. **The app ignores Android platform conventions** — no haptics, no font scaling, custom widgets without Semantics/ripple/touch targets, a NavigationBar that looks broken. It feels unfinished because Material norms are all unmet.

Fix the functional wiring first (Sprint 0–1); fix the feel second (Sprint 2).

---

## Sprint 0 — Minimum to be store-submittable (do before next AAB)
Goal: eliminate store-rejection risk and functional dishonesty. Critical path.

| # | Item | File | Size | Confidence | DoD |
|---|------|------|------|------------|-----|
| S0-1 | **Search filter chips wired** — postal→GeocodeService, Bus#→searchServices, StopID/Place→searchStops; FutureBuilder for async postal | `soft_search_screen.dart:104` | L | 5/6 agents | All four chips produce distinct, correct results |
| S0-2 | **Alight alert actually fires** — call `AppModel.setActiveAlight()`; clear on dispose | `soft_bus_screen.dart:32,101` | M | 2/6 agents | Notification fires at scheduled time; widget-local state gone |
| S0-3 | **Route timeline stops fabricating ETAs** — pass null for unknown per-stop times; label "est." or omit | `soft_bus_screen.dart:381-383` | S | 1/6 agents | No invented clock times shown as LTA data |
| S0-4 | **CI builds release AAB, not debug APK** — change `flutter build apk --debug` → `flutter build appbundle --release` | `.github/workflows/ci.yml:41` | S | 1/6 agents | CI output is an AAB; release code path validated |
| S0-5 | **Pin Flutter SDK version in CI** — add `flutter-version: 3.44.0` | `ci.yml` | S | 1/6 agents | No silent toolchain drift |
| S0-6 | **Fix Gradle JVM heap** — `org.gradle.jvmargs=-Xmx4G` (was 8G, > runner RAM) | `android/gradle.properties` | S | 1/6 agents | CI no longer OOM-flakes |
| S0-7 | **`key.properties` project-relative path** — replace `/Users/rommel/...jks` with `../leyne.jks` or env var | `android/key.properties` | S | 1/6 agents | AAB builds on any machine/CI without path edit |
| S0-8 | **CHANGELOG stale "Unreleased" blocks** — move both blocks to versioned entries | `CHANGELOG.md` | S | — | No "Unreleased" section remains for shipped builds |

**Critical path:** S0-1 (L) is the longest item and the store-rejection risk. Start there. S0-2 through S0-8 can all be done in parallel or same day.

---

## Sprint 1 — Reliability & honesty (week 1–2 post Sprint 0)
Goal: no silent failures, no wrong data shown, no misleading states.

| # | Item | File | Size | Notes |
|---|------|------|------|-------|
| S1-1 | `_liveService()` wrong-bus fallback → return null, handle null | `soft_bus_screen.dart:117` | S | Silent wrong-bus alert is worse than no alert |
| S1-2 | `DataStore.bootstrap()` in-flight guard (`_bootstrapping` flag) | `data_store.dart:263-305` | S | Concurrent cold-start double-fetch clears stop map |
| S1-3 | `refreshArrivals` inflight guard returns correct pending future | `data_store.dart:405-409` | S | RefreshIndicator dismisses while fetch still running |
| S1-4 | `_masterBell` disabled until arrivals loaded | `soft_stop_screen.dart:148-153` | S | Currently unpins stop silently on early tap |
| S1-5 | `WidgetsBindingObserver` in `soft_root.dart` — call `refreshNotificationAuth()` on resume | `soft_root.dart` / `main.dart` | S | Permission revocation undetected; bells show active while OS drops them |
| S1-6 | Hoist `_scheduleMode()` above reschedule loop (was N×M MethodChannel calls/10s) | `notifications.dart:434` | S | Perf + battery |
| S1-7 | Nearby: add `RefreshIndicator` + re-query on location change | `soft_nearby_screen.dart` | M | Only content tab without pull-to-refresh |
| S1-8 | Record recent searches — call `AppModel.addRecent()` from search screen | `soft_search_screen.dart` | S | Method exists, never called |
| S1-9 | Add pre-release gate script (`scripts/pre-release-check.sh`) | `scripts/` | M | CHANGELOG shows 5 versionCode rejections in one day from manual process |
| S1-10 | Play store readiness checklist: Data Safety (AD_ID + location), privacy policy URL, `assetlinks.json` | Play Console / hosting | M | Deep links show chooser without assetlinks |

---

## Sprint 2 — Parity & feel (week 2–3)
Goal: close the gap between iOS and Android experience. No net-new native code yet.

| # | Item | File | Size | Notes |
|---|------|------|------|-------|
| S2-1 | **Font scaling** — replace all raw `TextStyle(fontSize:)` with `textScaler`-aware sizes | `lib/theme.dart:94-98` + all screens | L | App ignores Android system font size; 56sp ETA clips at large scale. Same root as iOS Dynamic Type issue |
| S2-2 | Third arrival time in BusView (`thirdDate` parsed, never shown) | `soft_bus_screen.dart` | S | iOS shows 3 |
| S2-3 | Live/Scheduled provenance chip on Stop rows + Bus card (`monitored` field, never surfaced) | `soft_stop_screen.dart`, `soft_bus_screen.dart` | M | iOS has `liveStatusChip()`; commute reliability info |
| S2-4 | Pin/unpin affordance in BusView | `soft_bus_screen.dart` | S | iOS has it |
| S2-5 | Settings: wire Sound, Haptics, Search Radius toggles | `soft_settings_screen.dart` | M | `AppModel` fields exist; UI not wired |
| S2-6 | Onboarding priming footnotes on location/notification steps | `onboarding_screen.dart:48-59` | S | Android users hit OS dialogs cold; iOS warns |
| S2-7 | Remove iOS-specific icon (`Icons.phone_iphone`) from Android onboarding; remove false promises ("Rename/Reorder") | `onboarding_screen.dart` | S | — |
| S2-8 | **Haptics** — add `HapticFeedback` calls at key interactions (tap chip, pin, notify) | V2 screens | M | iOS has 4-intensity `Feedback.swift`; Android taps feel dead |
| S2-9 | Replace `🔔` emoji chips + Unicode arrows with `Icons.*` | V2 screens | S | Render inconsistently across Android fonts |
| S2-10 | NavigationBar selected indicator → tonal color (not `t.liveBg` arrival-green) | `soft_tab_bar.dart:29` | S | Selected tab looks like a live-arrival state |

---

## Sprint 3 — Polish, a11y & infra hardening (week 3–4)
Goal: TalkBack-compliant, WCAG AA, branch-protected CI, R8 enabled.

| # | Item | Size | Notes |
|---|------|------|-------|
| S3-1 | `Semantics` annotations across all V2 custom widgets | L | Zero annotations; TalkBack reads nothing useful |
| S3-2 | Replace `SoftToggle` with `Switch` (44×26 < 48dp, no TalkBack), `SortChipRow` with `ChoiceChip`/`InkWell`, notify button with `FilledButton` | M | Custom widgets lack Semantics, correct touch targets, ripple |
| S3-3 | Fix `_busRow` InkWell (no Material ancestor → ripple floods screen) — wrap card in `Material` | S | `soft_stop_screen.dart:360` |
| S3-4 | Fix `t.faint` contrast (fails WCAG AA ~2.1:1 dark mode) | S | Captions, version string, chevrons |
| S3-5 | Enable R8/minify + add `proguard-rules.pro` keep rules | M | Currently disabled; google_mobile_ads ships consumer rules |
| S3-6 | Branch protection on `main` | S | Infra; CI is currently advisory |

---

## Net-new native items (XL — post-launch fast-follow, do not block launch)

| # | Item | Size | Notes |
|---|------|------|-------|
| N1 | **Android foreground service** for true background tracking (Kotlin, FOREGROUND_SERVICE + SPECIAL_USE manifest, WorkManager or FGS) | XL | iOS has Live Activities + Dynamic Island. Biggest capability gap. Not a launch gate. |
| N2 | **Home screen widget** (Jetpack Glance + WorkManager) | XL | iOS has WidgetKit `LeyneStopWidget`. Net-new scope. |

---

## Parallelizable work
- Sprint 0: S0-2 through S0-8 are all independent and can run simultaneously while S0-1 (largest) is in progress.
- Sprint 1: S1-1 through S1-6 are independent one-file fixes; all can ship in a single commit.
- Sprint 2: S2-8 (haptics) and S2-9 (emoji→Icons) can be done alongside S2-1 (font scaling).

## Critical path to confident Play launch
S0-1 (search chips, L) → S0-2 (alight, M) → Sprint 1 reliability batch → Play Store readiness (S1-10) → AAB submit

**Why:** Updated 2026-05-30 from 6-agent Android audit. Search chips are the repeat store-rejection risk; everything else is quality depth.
**How to apply:** Run through Sprint 0 checklist at the start of any Android build session. Do not cut an AAB until S0-1 and S0-2 are done.

Related: [[project-risks]], [[project-status]], [[next-actions]]
