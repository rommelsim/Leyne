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

  // ── Proximity / status colour (2.4.0 overhaul) ──────────────────────
  // Semantic green/amber used for ETA *proximity* and *occupancy* only.
  // Confidence (live/stale/scheduled) stays shape + opacity + "~" whisper —
  // never colour. Dark uses brighter shades tuned for near-black surfaces.

  /// Imminent / good — green. "Arriving soon", seats available.
  final Color soon;
  final Color soonBg;

  /// Medium / caution — amber. Mid-range ETA, standing-only.
  final Color mid;
  final Color midBg;

  // ── Typography ───────────────────────────────────────────────────────
  // `mono()` uses the system (Roboto/default) font with tabular figures
  // (`FontFeature.tabularFigures`) — proportional letters, fixed-width
  // digits. This mirrors iOS's `.monospacedDigit()` so ticking ETAs /
  // countdowns don't jitter as digit widths change, while keeping the
  // same letterform as the rest of the UI. The old `fontFamily:'monospace'`
  // was replaced in 2.4.0; see `sans()` for the regular font factory.
  TextStyle mono(double size, {FontWeight weight = FontWeight.w400, Color? color}) =>
      TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color ?? fg,
        fontFeatures: const [ui.FontFeature.tabularFigures()],
      );

  TextStyle sans(double size, {FontWeight weight = FontWeight.w400, Color? color}) =>
      TextStyle(fontSize: size, fontWeight: weight, color: color ?? fg);

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
  static final LyneTheme dark = LyneTheme(
    isDark: true,
    bg: _hex('0F0F0F'),
    surface: _hex('1A1A1A'),
    surfaceHi: _hex('262626'),
    contrast: _hex('FFFFFF'),
    contrastFg: _hex('0F0F0F'),
    contrastSurface: _hex('2E2E2E'),
    fg: _hex('FFFFFF'),
    dim: const Color.fromRGBO(255, 255, 255, 0.6),
    faint: const Color.fromRGBO(255, 255, 255, 0.35),
    line: const Color.fromRGBO(255, 255, 255, 0.1),
    lineHi: const Color.fromRGBO(255, 255, 255, 0.16),
    accent: _hex('FFFFFF'),
    live: _hex('FFFFFF'),
    liveBg: _hex('242424'),
    warn: _hex('F4B870'),
    warnBg: const Color.fromRGBO(244, 184, 112, 0.16),
    crit: _hex('F08F7C'),
    critBg: const Color.fromRGBO(240, 143, 124, 0.16),
    // 2.4.0 proximity tokens — brighter shades for near-black dark surfaces.
    soon: _hex('3DD68C'),
    soonBg: const Color.fromRGBO(61, 214, 140, 0.16),
    mid: _hex('F4B870'),
    midBg: const Color.fromRGBO(244, 184, 112, 0.16),
  );

  // White & black light mode — mirrors iOS (ios-native/Leyne/Theme.swift).
  // Monochrome: the accent (LIVE / arriving / pin) is pure black ink rather
  // than the old mint green; confidence reads from opacity/shape, never hue.
  // Warning amber + critical red are kept so disruptions still read at a
  // glance. `bg` is a hair off-white so white `surface` cards lift off it.
  static final LyneTheme light = LyneTheme(
    isDark: false,
    bg: _hex('F2F2F2'),
    surface: _hex('FFFFFF'),
    surfaceHi: _hex('E9E9E9'),
    contrast: _hex('111111'),
    contrastFg: _hex('FFFFFF'),
    contrastSurface: _hex('2A2A2A'),
    fg: _hex('111111'),
    dim: const Color.fromRGBO(17, 17, 17, 0.6),
    faint: const Color.fromRGBO(17, 17, 17, 0.35),
    line: const Color.fromRGBO(17, 17, 17, 0.1),
    lineHi: const Color.fromRGBO(17, 17, 17, 0.16),
    accent: _hex('111111'),
    live: _hex('111111'),
    liveBg: _hex('EDEDED'),
    warn: _hex('A0631A'),
    warnBg: const Color.fromRGBO(160, 99, 26, 0.14),
    crit: _hex('A4422F'),
    critBg: const Color.fromRGBO(164, 66, 47, 0.14),
    // 2.4.0 proximity tokens — darker shades for legibility on white surfaces.
    soon: _hex('1AA251'),
    soonBg: const Color.fromRGBO(26, 162, 81, 0.12),
    mid: _hex('C2740A'),
    midBg: const Color.fromRGBO(194, 116, 10, 0.12),
  );

  /// Foreground used on top of `accent` fills. White in light mode (black
  /// accent), black in dark mode (white accent) — monochrome both ways.
  Color get onAccent => isDark ? _hex('111111') : _hex('FFFFFF');

  /// Material ThemeData built from this palette — wires bg/surface/accent
  /// into the Material 3 colour scheme so stock widgets (AppBar,
  /// NavigationBar, ListTile, etc.) inherit the look without per-widget
  /// styling.
  ///
  /// When [dynamicScheme] is non-null (Material You is available on the
  /// device — Android 12+), the user's wallpaper-derived palette is
  /// harmonised against Leyne's brand colours: surfaces and tonal
  /// containers take on the wallpaper tint, while `live` (mint), `warn`
  /// (amber), and `crit` (red) keep their semantic identity. On older
  /// Android, [dynamicScheme] is null and we use the static palette
  /// verbatim.
  ThemeData materialTheme({ColorScheme? dynamicScheme}) {
    final base = ColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: accent,
      onPrimary: contrastFg,
      secondary: live,
      onSecondary: contrastFg,
      surface: surface,
      onSurface: fg,
      surfaceContainerHighest: bg,
      outline: isDark ? _hex('2A2A2A') : line,
      error: crit,
      onError: contrastFg,
    );
    // Material You overlay: take the wallpaper-derived scheme as the
    // base (so surfaces tint with the user's wallpaper) and re-paint
    // Leyne's brand slots on top. `harmonized()` shifts the accent
    // hue toward the dynamic primary so mint reads as part of the
    // wallpaper family without losing its mint identity.
    final scheme = dynamicScheme == null
        ? base
        : dynamicScheme.copyWith(
            primary: accent.harmonizeWith(dynamicScheme.primary),
            onPrimary: contrastFg,
            secondary: live.harmonizeWith(dynamicScheme.primary),
            onSecondary: contrastFg,
            error: crit.harmonizeWith(dynamicScheme.primary),
            onError: contrastFg,
          );
    final scaffoldBg = dynamicScheme == null ? bg : scheme.surface;
    final surfaceTint = dynamicScheme == null ? Colors.transparent : scheme.surfaceTint;
    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBg,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        foregroundColor: fg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
            fontSize: 28, fontWeight: FontWeight.w600, color: fg, letterSpacing: -0.3),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scaffoldBg,
        surfaceTintColor: surfaceTint,
        indicatorColor: isDark
            ? const Color.fromRGBO(255, 255, 255, 0.06)
            : accent.withValues(alpha: 0.12),
        // Resolve icon + label colour per state. Without this the bar's
        // icons fall back to Material's default ColorScheme slots (which
        // this palette never sets), rendering near-invisible on the light
        // warm-white background. Selected = full-contrast fg; unselected =
        // dim but clearly legible — on both light and dark.
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
}

/// Convenience extension: any widget can read the current LyneTheme via
/// `context.t`. We resolve by looking at the current brightness so the
/// right palette comes back without a Theme provider.
extension LyneThemeContext on BuildContext {
  LyneTheme get t => Theme.of(this).brightness == Brightness.dark
      ? LyneTheme.dark
      : LyneTheme.light;
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

/// Cross-mode signal colours that don't change between dark and light.
/// Use for transit-specific overlays (MRT line indicators, "ME" dots).
class LyneSignal {
  /// MRT NE-line purple — alert cards and dots.
  static const Color mrtNE = Color(0xFF9B26B6);
  /// Live "ME" location dot on maps.
  static const Color meBlue = Color(0xFF3B82F6);
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
