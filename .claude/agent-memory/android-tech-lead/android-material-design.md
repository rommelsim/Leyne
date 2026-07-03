---
name: android-material-design
description: Findings from the 2026-07-02 Material 3 design-language audit of the live Android (Flutter) surface — what's genuinely modern vs deliberately opted-out vs actually dated
metadata:
  type: project
---

Full audit done 2026-07-02 against `lib/theme.dart` + the live `lib/screens/v2/` surface (see [[project-structure]] for how liveness was confirmed). Overall grade: **Modern**, disciplined M3 usage, with a few deliberate opt-outs and a handful of real gaps. Re-verify file:line citations before reusing — grep for the symbol first, this is a snapshot.

**Confirmed modern / correctly done:**
- `useMaterial3: true` in `lib/theme.dart` materialTheme(), custom `ColorScheme(...)` (not `.fromSeed`) wired into NavigationBar/AppBar/Switch/Chip themes.
- `NavigationBar` (M3, with `Badge` for the Alerts unseen-count) in `lib/widgets/v2/soft_tab_bar.dart` — not legacy `BottomNavigationBar`.
- `Switch` and `ChoiceChip` in `lib/widgets/v2/soft_components.dart` replaced hand-painted `GestureDetector` toggles specifically to get Material ripple, ≥48dp touch targets, and TalkBack semantics — see the "Fix 3/4/7" comments there. This was a real, scoped prior accessibility/Material pass — but it only touched this one shared-primitives file, not per-screen literals (see gaps below).
- Predictive back is correctly wired: `android:enableOnBackInvokedCallback="true"` in AndroidManifest.xml + a hand-rolled `PopScope`/`SystemNavigator.setFrameworkHandlesBack` sync in `soft_root.dart` with detailed comments explaining the Android 13+ OnBackInvokedCallback gotcha (nested Navigator's NavigationNotification silently unregistering the callback). This is above-average engineering — matches the known-fixed [[android_back_exit_rootcause]] class of bug.
- No `pageTransitionsTheme` override → Flutter's Android default `ZoomPageTransitionsBuilder` (M3-style, predictive-back compatible) applies for granted on all `MaterialPageRoute` pushes (Stop/Bus/Station). Search intentionally overrides to a plain fade (`FadeTransition`, documented rationale: feel identical to a tab swap).
- `SafeArea` used consistently across all live screens; targetSdk resolves to 36 via Flutter tooling, so edge-to-edge is the engine default — no manual edge-to-edge wiring needed or missing.
- Cupertino import only exists in the generated `l10n/app_localizations.dart` boilerplate (`GlobalCupertinoLocalizations.delegate`) — not real iOS-idiom bleed. No Cupertino widgets used anywhere.

**Deliberate opt-outs (documented in code, not bugs):**
- No M3 `TextTheme`/typography scale — `ThemeData` never sets `textTheme`; all type comes from `LyneTheme.sans()/mono()` bespoke helpers instead of `Theme.of(context).textTheme.*`. Internally consistent design system, but bypasses the M3 type scale/Typography.material2021 entirely.
- No `SearchBar`/`SearchAnchor` — `soft_search_screen.dart` hand-rolls a `TextField` styled to look like a search field. Functionally fine, visually close to M3, but forgoes the built-in M3 search transition/suggestions scaffolding.

**Gaps fixed 2026-07-02 (owner-directed modernization pass — see [[material-you-implementation]] for full detail):**
- Material You / dynamic colour: was a deliberate opt-out (monochrome-by-design, mirrors iOS), owner decision superseded it for Android only. Now wired for real via `DynamicColorBuilder` in `lib/main.dart` → `LyneTheme.materialTheme(dynamicScheme:)` in `lib/theme.dart`.
- Splash screen: added `android/app/src/main/res/values-v31/styles.xml` + `values-night-v31/styles.xml` (API 31+ SplashScreen attrs layered onto the existing pre-12 LaunchTheme, NOT parented on `Theme.SplashScreen` — see [[material-you-implementation]] for why that parent doesn't link on this toolchain). Pre-12 `values{,-night}/styles.xml` + `drawable/launch_background.xml` untouched.
- Severity colours: centralised into `enum LyneSeverity` in `lib/theme.dart` (normal/warning/critical/unknown → green/orange/red/grey, values unchanged). All ~20 call sites across `soft_mrt_screen.dart`, `soft_mrt_line_screen.dart`, `soft_mrt_station_screen.dart`, `soft_alerts_screen.dart` now reference it instead of raw `Colors.*`. The two duplicated `_crowdColor(CrowdLevel)` private helpers (soft_mrt_line_screen.dart, soft_mrt_station_screen.dart) still exist as separate functions — only their bodies were repointed at `LyneSeverity`, the duplication itself wasn't deduped (out of scope for that task).
- `mrt_map_screen.dart` now routes through `LyneTheme.light.contrast`/`contrastFg` (aliased locally as `inv`) instead of raw `Colors.black`/`white`/`white60`, still unconditionally dark regardless of app theme — see [[material-you-implementation]] for why `LyneTheme.light` (not `context.t`) is the correct source for that.
- Dead V1 tree deleted entirely (see [[project-structure]] — that memory's "V1 dead files" list is now stale, files no longer exist): `lib/screens/{root_scaffold,home_screen,detail_screen,nearby_screen,search_screen,settings_screen,notifications_screen,about_screen}.dart`, `lib/widgets/{pinned_card,route_map,route_progress,service_row,stops_map,eta_pill,home_hero}.dart`, plus their 4 now-orphaned test files (`test/{settings_features,eta_pill,screens,pinned_card}_test.dart`).
