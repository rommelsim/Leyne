// Theme tokens — palette for the redesigned Lyne UI.
//
// Dark variant is the design target (warm near-black bg, mint accent,
// JetBrains-style mono for numerics). Light variant mirrors the same
// structure with a darker mint that contrasts on a warm off-white bg.
//
// LyneTheme is exposed as a small data class plus a Material ThemeData
// factory so stock widgets (AppBar, NavigationBar, ListTile, etc.) inherit
// the look without per-widget styling.

import 'dart:ui' as ui;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'theme/soft_blue.dart';

@immutable
class LyneTheme {
  const LyneTheme({
    required this.isDark,
    required this.bg,
    required this.surface,
    required this.surfaceHi,
    required this.contrast,
    required this.contrastFg,
    required this.contrastSurface,
    required this.fg,
    required this.dim,
    required this.faint,
    required this.line,
    required this.lineHi,
    required this.accent,
    required this.live,
    required this.liveBg,
    required this.warn,
    required this.warnBg,
    required this.crit,
    required this.critBg,
    required this.soon,
    required this.soonBg,
    required this.mid,
    required this.midBg,
  });

  final bool isDark;

  /// Page background.
  final Color bg;

  /// Default raised surface (cards, list backgrounds).
  final Color surface;

  /// Stronger raised surface — for the hero card on Home.
  final Color surfaceHi;

  /// Inverse panel colour (FAB, dark banners on light bg, etc.).
  final Color contrast;

  /// Foreground used on top of `contrast`.
  final Color contrastFg;

  /// Darker companion to `contrast` (raised inside an inverse panel).
  final Color contrastSurface;

  /// Primary foreground text.
  final Color fg;

  /// Secondary text — `~52%` of fg.
  final Color dim;

  /// Tertiary text — `~32%` of fg. Stop IDs, "then NN" follow-up arrivals.
  final Color faint;

  /// Hairline borders + dividers.
  final Color line;

  /// Stronger border — for the hero card.
  final Color lineHi;

  /// Brand accent. Also used as the "live / arriving" colour.
  ///
  /// This field is the static fallback value. At runtime, `context.t.accent`
  /// (via `LyneThemeContext`) resolves to the *live* Material You accent —
  /// the resolved `ColorScheme.primary`, which is wallpaper-derived on
  /// Android 12+ or seed-derived below it — via `LyneTheme.withAccent`. See
  /// `materialTheme()` for the full dynamic-colour scope.
  final Color accent;

  /// Live-data colour (alias for accent in this palette).
  final Color live;

  /// Subtle background tint for live/arriving rows.
  final Color liveBg;

  /// Warning amber — "leave now", "delay".
  final Color warn;
  final Color warnBg;

  /// Critical red — "last bus", "service disrupted".
  final Color crit;
  final Color critBg;

  // ── Proximity / status colour (2.6.0+ monochrome overhaul) ─────────
  // These tokens are now MONOCHROME ink (white in dark, #111111 in light)
  // at varying opacities — matching iOS Theme.swift 2.6.0+. Green/amber
  // are gone from ETA proximity badges and arrival rows.
  //
  // Crowd/occupancy meters remain coloured, but their colour is HARDCODED
  // in confidence.dart / proximity.dart — NOT sourced from these tokens.
  // Colour is reserved only for MRT line pills and crowd meters.

  /// Imminent / active — monochrome ink (full opacity).
  final Color soon;
  final Color soonBg;

  /// Secondary / reduced — monochrome ink (~55% opacity).
  final Color mid;
  final Color midBg;

  // ── Typography ───────────────────────────────────────────────────────
  // `mono()` uses the system (Roboto/default) font with tabular figures
  // (`FontFeature.tabularFigures`) — proportional letters, fixed-width
  // digits. This mirrors iOS's `.monospacedDigit()` so ticking ETAs /
  // countdowns don't jitter as digit widths change, while keeping the
  // same letterform as the rest of the UI. The old `fontFamily:'monospace'`
  // was replaced in 2.4.0; see `sans()` for the regular font factory.
  TextStyle mono(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) => TextStyle(
    fontSize: size,
    fontWeight: weight,
    color: color ?? fg,
    fontFeatures: const [ui.FontFeature.tabularFigures()],
  );

  TextStyle sans(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
    // Sans (Inter/Roboto) numerals are proportional by default — unlike
    // `mono()`, which is always tabular. Pass true wherever a NUMBER (not a
    // word) is set in the sans face — a service-number badge, a bus count —
    // so ticking/adjacent digits don't jitter or misalign width-to-width.
    bool tabularFigures = false,
  }) => TextStyle(
    fontSize: size,
    fontWeight: weight,
    color: color ?? fg,
    fontFeatures: tabularFigures
        ? const [ui.FontFeature.tabularFigures()]
        : null,
  );

  static Color _hex(String hex) {
    final s = hex.replaceFirst('#', '');
    return Color(int.parse('FF$s', radix: 16));
  }

  // Monochrome dark — clean black-and-white, no brand green. The accent
  // (LIVE / arriving / pin) is pure white ink rather than the old mint, so
  // confidence reads from opacity/shape, not hue (mirrors the light mode's
  // black-ink accent). Warning amber + critical red are kept for disruption
  // severity. Cross-mode colours (MRT line hues, ME-dot blue) live on the
  // static `LyneSignal` helper / MRTLine enum below.
  //
  // Monochrome proximity tokens (2.6.0+, mirrors iOS Theme.swift dark):
  //   soon/soonBg/mid/midBg/warn/warnBg/crit/critBg are all white-ink at
  //   varying opacities. Colour is reserved ONLY for MRT line pills and
  //   crowd/occupancy meters (hardcoded in confidence.dart / proximity.dart).
  // SoftBlue "4b" port (2026-07-25, docs/soft-blue-design.md): the owner
  // decision is that iOS and Android ship the SAME look, superseding the
  // Material You / monochrome direction below for every screen ported to
  // SoftBlue. The spec's dark-twin token swap (§6) is explicitly
  // future-proofing only — "not building now" — so LyneTheme.dark is kept
  // numerically IDENTICAL to LyneTheme.light rather than diverging into a
  // separate near-black scheme: a user with system dark mode still sees the
  // same tinted-blue board as light mode, matching iOS (which has no dark
  // variant of this design either). Do not restore the old near-black
  // values here without first shipping the real dark twin from §6.
  static final LyneTheme dark = LyneTheme(
    isDark: true,
    bg: SoftBlue.bg,
    surface: SoftBlue.card,
    surfaceHi: SoftBlue.chipBg,
    contrast: SoftBlue.ink,
    contrastFg: Colors.white,
    contrastSurface: SoftBlue.ink,
    fg: SoftBlue.ink,
    dim: SoftBlue.sub,
    faint: SoftBlue.sub.withValues(alpha: 0.7),
    line: SoftBlue.hairline,
    lineHi: SoftBlue.hairline,
    accent: SoftBlue.blue,
    live: SoftBlue.blue,
    liveBg: SoftBlue.chipBg,
    warn: SoftBlue.amber,
    warnBg: SoftBlue.amber.withValues(alpha: 0.12),
    crit: SoftBlue.red,
    critBg: SoftBlue.red.withValues(alpha: 0.12),
    // "LIVE" badges / imminent-arrival emphasis now read blue (the app's one
    // decorative/live accent — spec §1), not monochrome ink.
    soon: SoftBlue.blue,
    soonBg: SoftBlue.chipBg,
    mid: SoftBlue.sub,
    midBg: SoftBlue.hairline,
  );

  // White & black light mode — mirrors iOS (ios-native/Leyne/Theme.swift).
  // Monochrome: the accent (LIVE / arriving / pin) is pure black ink rather
  // than the old mint green; confidence reads from opacity/shape, never hue.
  // `bg` is a hair off-white so white `surface` cards lift off it.
  //
  // Monochrome proximity tokens (2.6.0+, mirrors iOS Theme.swift light):
  //   soon/soonBg/mid/midBg/warn/warnBg/crit/critBg are all #111111 ink at
  //   varying opacities. Colour is reserved ONLY for MRT line pills and
  //   crowd/occupancy meters (hardcoded in confidence.dart / proximity.dart).
  // SoftBlue "4b" port (2026-07-25) — canonical palette, see the `dark` doc
  // comment above for why `dark` mirrors these same values instead of
  // diverging. Hex values come straight from docs/soft-blue-design.md §1 /
  // lib/theme/soft_blue.dart — do not hand-tune them here independently.
  static final LyneTheme light = LyneTheme(
    isDark: false,
    bg: SoftBlue.bg,
    surface: SoftBlue.card,
    surfaceHi: SoftBlue.chipBg,
    contrast: SoftBlue.ink,
    contrastFg: Colors.white,
    contrastSurface: SoftBlue.ink,
    fg: SoftBlue.ink,
    dim: SoftBlue.sub,
    faint: SoftBlue.sub.withValues(alpha: 0.7),
    line: SoftBlue.hairline,
    lineHi: SoftBlue.hairline,
    accent: SoftBlue.blue,
    live: SoftBlue.blue,
    liveBg: SoftBlue.chipBg,
    warn: SoftBlue.amber,
    warnBg: SoftBlue.amber.withValues(alpha: 0.12),
    crit: SoftBlue.red,
    critBg: SoftBlue.red.withValues(alpha: 0.12),
    soon: SoftBlue.blue,
    soonBg: SoftBlue.chipBg,
    mid: SoftBlue.sub,
    midBg: SoftBlue.hairline,
  );

  /// Foreground used on top of `accent` fills. Always white — SoftBlue's
  /// `accent`/`live` is pinned to `SoftBlue.blue` in both palettes now (see
  /// the `light`/`dark` doc comments), so this no longer flips with
  /// brightness the way the old monochrome accent did.
  Color get onAccent => Colors.white;

  /// Material ThemeData built from this palette — wires bg/surface into the
  /// Material 3 colour scheme so stock widgets (AppBar, NavigationBar,
  /// Switch, Chip, ListTile, etc.) inherit the look without per-widget
  /// styling.
  ///
  /// Material You / dynamic colour (owner decision, 2026-07-02 — supersedes
  /// the earlier "stay monochrome" call for Android; iOS is untouched and
  /// stays monochrome, see ios-native/Leyne/Theme.swift): on Android 12+ the
  /// OS derives [dynamicScheme] from the user's wallpaper (fed in from
  /// `DynamicColorBuilder` in lib/main.dart). Below API 31, or whenever
  /// dynamic colour is unavailable, [dynamicScheme] is null and we fall back
  /// to a seeded palette built from `LyneSignal.meBlue` — the app's existing
  /// transit-blue "you are here" colour, already established as a brand
  /// colour, so it's a natural seed.
  ///
  /// Scope is deliberately narrow: dynamic colour tints CHROME + ACCENT
  /// only.
  ///   • `primary`/`secondary` (and everything Flutter/Material derives from
  ///     them for free — `Switch`'s active track, `ChoiceChip`'s selected
  ///     fill) follow the resolved scheme, as does the NavigationBar
  ///     indicator pill below.
  ///   • `LyneTheme.accent`/`live` also follow it, but only via
  ///     `LyneThemeContext.t` → `withAccent` — the static fields on this
  ///     class stay the monochrome fallback value.
  ///   • `surface`/`onSurface`/`outline` stay pinned to this palette's own
  ///     surface/fg/line so the page background and body text never shift
  ///     with wallpaper. `error` stays pinned to `crit`.
  ///   • MRT line colours (`MRTLine.color`), severity colours
  ///     (`LyneSeverity`) and crowd/occupancy colours (`occupancyColor` in
  ///     proximity.dart) are DATA, not chrome — none of them read from
  ///     `ColorScheme` at all, dynamic or otherwise.
  // SoftBlue port (2026-07-25): [dynamicScheme] (Material You's
  // wallpaper-derived palette) is now IGNORED — the owner decision porting
  // SoftBlue explicitly supersedes the earlier Material You direction for
  // these screens ("blue is the ONE decorative accent... it never means
  // wallpaper-of-the-day"). The parameter is kept (not removed) so
  // `main.dart`'s `DynamicColorBuilder` call site doesn't need touching;
  // it's simply unused now. Every ColorScheme is seeded from `SoftBlue.blue`
  // instead, so Android's chrome accent matches iOS's fixed `#2E8FE0`
  // regardless of device wallpaper.
  ThemeData materialTheme({ColorScheme? dynamicScheme}) {
    final brightness = isDark ? Brightness.dark : Brightness.light;
    final resolved = ColorScheme.fromSeed(
      seedColor: SoftBlue.blue,
      brightness: brightness,
    ).harmonized();
    final scheme = resolved.copyWith(
      brightness: brightness,
      surface: surface,
      onSurface: fg,
      surfaceContainerHighest: bg,
      outline: isDark ? _hex('2A2A2A') : line,
      error: crit,
      onError: contrastFg,
    );
    final scaffoldBg = bg;
    final surfaceTint = Colors.transparent;
    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBg,
      // Visible push for detail routes (stop / bus / MRT station). The M3
      // default (subtle zoom) reads as "no animation" next to iOS's
      // NavigationStack slide — owner-flagged on the MRT station push,
      // 2026-07-04. FadeForwards is the current Android-native forward
      // motion (slide + fade, Android 15 activity spec), not an iOS bleed.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        foregroundColor: fg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: fg,
          letterSpacing: -0.3,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scaffoldBg,
        surfaceTintColor: surfaceTint,
        // Dynamic-colour indicator pill — the one spot in the nav bar that
        // now tints with wallpaper/seed instead of a flat monochrome wash.
        indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.20 : 0.12),
        // Resolve icon + label colour per state. Without this the bar's
        // icons fall back to Material's default ColorScheme slots (which
        // this palette never sets), rendering near-invisible on the light
        // warm-white background. Selected = full-contrast fg; unselected =
        // dim but clearly legible — on both light and dark. Icons stay
        // monochrome ink (not scheme.primary) so wayfinding never depends on
        // a colour some users may have low contrast with; the coloured pill
        // behind the icon is the accent moment instead.
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected) ? fg : dim,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: states.contains(WidgetState.selected) ? fg : dim,
          ),
        ),
      ),
      dividerColor: line,
      iconTheme: IconThemeData(color: fg),
    );
  }

  /// SoftBlue port (2026-07-25): this used to adopt the resolved Material You
  /// `ColorScheme.primary` (wallpaper colour) as `accent`/`live`. That's
  /// exactly the direction SoftBlue supersedes — "blue is the ONE
  /// decorative accent... it never means wallpaper-of-the-day" — so [color]
  /// is now ignored and this returns `this` unchanged; `accent`/`live` stay
  /// pinned to `SoftBlue.blue` from the `light`/`dark` palettes. Kept (not
  /// deleted) so `LyneThemeContext.t`'s call site doesn't need touching.
  LyneTheme withAccent(Color color) => LyneTheme(
    isDark: isDark,
    bg: bg,
    surface: surface,
    surfaceHi: surfaceHi,
    contrast: contrast,
    contrastFg: contrastFg,
    contrastSurface: contrastSurface,
    fg: fg,
    dim: dim,
    faint: faint,
    line: line,
    lineHi: lineHi,
    accent: accent,
    live: live,
    liveBg: liveBg,
    warn: warn,
    warnBg: warnBg,
    crit: crit,
    critBg: critBg,
    soon: soon,
    soonBg: soonBg,
    mid: mid,
    midBg: midBg,
  );
}

/// Convenience extension: any widget can read the current LyneTheme via
/// `context.t`. We resolve by looking at the current brightness so the
/// right palette comes back without a Theme provider, then swap in the live
/// Material You accent (`Theme.of(this).colorScheme.primary` — wallpaper-
/// derived on Android 12+, seed-derived fallback otherwise; see
/// `materialTheme()` / `LyneTheme.withAccent`) so every `t.accent`/`t.live`
/// call site in the app picks up dynamic colour automatically.
extension LyneThemeContext on BuildContext {
  LyneTheme get t {
    final theme = Theme.of(this);
    final base = theme.brightness == Brightness.dark
        ? LyneTheme.dark
        : LyneTheme.light;
    return base.withAccent(theme.colorScheme.primary);
  }
}

/// Shared corner-radius scale. Before this, screens used ad-hoc radii
/// (10/14/16/18/20/22/24/26) so cards of the same kind looked different
/// across screens. Three steps cover every surface; pills use [full].
///   md  → list-item cards, search results, row containers, leading tiles
///   lg  → hero/primary cards, empty states, settings sections, sheet edge
///   full→ pills, chips, toggle tracks
class LyneRadius {
  const LyneRadius._();
  static const double md = 16;
  static const double lg = 24;
  static const double full = 99;
}

/// Standard vertical gap between a screen header and its first content
/// section, and between stacked sections. Use instead of one-off SizedBox
/// heights so rhythm is consistent across screens.
const double kSectionGap = 16;

/// Canonical motion timing constants. Always pick the closest semantic bucket
/// rather than hard-coding millisecond literals.
///
///   fast         120 ms  tap feedback (toggles, ripples)
///   short        180 ms  switchers, small state changes
///   standard     220 ms  page/tab transitions
///   emphasis     320 ms  expand/collapse panels
///   pulse       1400 ms  shimmer / live pulse loops
class LyneMotion {
  const LyneMotion._();
  static const fast = Duration(milliseconds: 120);
  static const short = Duration(milliseconds: 180);
  static const standard = Duration(milliseconds: 220);
  static const emphasis = Duration(milliseconds: 320);
  static const pulse = Duration(milliseconds: 1400);
  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;
  static const standardCurve = Curves.easeInOutCubic;
}

/// Cross-mode signal colours that don't change between dark and light.
/// Use for transit-specific overlays (MRT line indicators, "ME" dots).
class LyneSignal {
  /// MRT NE-line purple — alert cards and dots.
  static const Color mrtNE = Color(0xFF9B26B6);

  /// Live "ME" location dot on maps. Also `materialTheme()`'s seed colour
  /// for the Material You fallback palette (see there) — already an
  /// established brand-ish blue, so it doubles as a sensible seed.
  static const Color meBlue = Color(0xFF3B82F6);
}

/// Disruption / crowd-density severity colour — the MRT line service status
/// (normal / disrupted) and the station/line `CrowdLevel` tier (low /
/// moderate / high / unknown). Centralises what used to be ~20 ad-hoc
/// `Colors.orange`/`Colors.green`/`Colors.red` literals scattered across
/// `soft_mrt_screen.dart`, `soft_mrt_line_screen.dart`,
/// `soft_mrt_station_screen.dart` and `soft_alerts_screen.dart` into one
/// named set, so severity can be re-tuned in one place. Values are UNCHANGED
/// from the old inline literals — this is a refactor for control, not a
/// redesign.
///
/// Cross-mode (same value in light/dark) like `LyneSignal`/`MRTLine` — these
/// are DATA-severity colours, not surface tokens, so they don't flex with
/// `LyneTheme.light`/`dark` and never come from Material You (dynamic colour
/// tints chrome + accent only, never data — see `materialTheme()`). This is
/// a different axis from bus-occupancy colour (`occupancyColor` in
/// proximity.dart, seats/standing/limited from the LTA `Load` field) — that
/// one stays exactly as-is, untouched by this token.
enum LyneSeverity {
  /// Operating normally / all-clear / low crowd — the check-mark tier.
  normal(Colors.green),

  /// Disrupted / delayed / moderate crowd — the dominant severity colour
  /// across MRT + Alerts (banners, borders, icons, status text).
  warning(Colors.orange),

  /// High crowd — the worst `CrowdLevel` tier. Disruption status has no
  /// "critical" tier of its own (LTA only reports disrupted/not).
  critical(Colors.red),

  /// Crowd level not reported — neutral grey, not "normal".
  unknown(Color.fromRGBO(128, 128, 128, 0.35));

  const LyneSeverity(this.color);
  final Color color;
}

/// Singapore MRT line palette. Subset for the colours surfaced in
/// Leyne 2.0; expand as additional lines need annotation.
enum MRTLine {
  ew(Color(0xFF009645), 'East-West', 'EW'),
  ns(Color(0xFFD42E12), 'North-South', 'NS'),
  ne(Color(0xFF9B26B6), 'North-East', 'NE'),
  cc(Color(0xFFFA9E0D), 'Circle', 'CC'),
  dt(Color(0xFF005EC4), 'Downtown', 'DT'),
  te(Color(0xFF9D5B25), 'Thomson-East Coast', 'TE');

  const MRTLine(this.color, this.displayName, this.code);
  final Color color;
  final String displayName;

  /// Two-letter code used in card headers ("NE Line · disrupted").
  final String code;

  /// Map LTA TrainServiceAlerts `Line` strings to our palette enum.
  /// Returns null for lines we haven't catalogued yet — callers fall
  /// back to a neutral marker so the alert still surfaces.
  static MRTLine? fromLtaCode(String raw) {
    switch (raw.toUpperCase()) {
      case 'EWL':
      case 'CGL':
      case 'EWN':
        return MRTLine.ew;
      case 'NSL':
        return MRTLine.ns;
      case 'NEL':
        return MRTLine.ne;
      case 'CCL':
      case 'CEL':
      case 'CGE':
        return MRTLine.cc;
      case 'DTL':
        return MRTLine.dt;
      case 'TEL':
        return MRTLine.te;
      default:
        return null;
    }
  }

  /// Short human label for an LTA line code ("NE Line"). Falls back to
  /// the raw code when we don't have a mapping.
  static String shortLabelForLta(String raw) {
    final m = fromLtaCode(raw);
    return m == null ? raw : '${m.code} Line';
  }
}
