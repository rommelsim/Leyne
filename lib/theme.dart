// Theme tokens — palette for the redesigned Lyne UI.
//
// Dark variant is the design target (warm near-black bg, mint accent,
// JetBrains-style mono for numerics). Light variant mirrors the same
// structure with a darker mint that contrasts on a warm off-white bg.
//
// LyneTheme is exposed as a small data class plus a Material ThemeData
// factory so stock widgets (AppBar, NavigationBar, ListTile, etc.) inherit
// the look without per-widget styling.

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

  /// SF Mono on iOS, Roboto Mono on Android (Flutter's monospace fallback).
  static const TextStyle monoBase =
      TextStyle(fontFamily: 'monospace', fontFamilyFallback: ['Menlo', 'Courier']);

  TextStyle mono(double size, {FontWeight weight = FontWeight.w400, Color? color}) =>
      monoBase.copyWith(fontSize: size, fontWeight: weight, color: color ?? fg);

  TextStyle sans(double size, {FontWeight weight = FontWeight.w400, Color? color}) =>
      TextStyle(fontSize: size, fontWeight: weight, color: color ?? fg);

  static Color _hex(String hex) {
    final s = hex.replaceFirst('#', '');
    return Color(int.parse('FF$s', radix: 16));
  }

  // Leyne 2.0 "Soft" palette — warm dark (#15201C) / warm light
  // (#F4EFE7) with mint accent. Property names preserved from v1 so
  // call sites compile unchanged. Cross-mode colours (MRT NE purple,
  // ME-dot blue) live on the static `LyneSignal` helper below.
  static final LyneTheme dark = LyneTheme(
    isDark: true,
    bg: _hex('15201C'),
    surface: _hex('1F2C28'),
    surfaceHi: _hex('293732'),
    contrast: _hex('F1EDE7'),
    contrastFg: _hex('0E2218'),
    contrastSurface: _hex('293732'),
    fg: _hex('F1EDE7'),
    dim: const Color.fromRGBO(241, 237, 231, 0.6),
    faint: const Color.fromRGBO(241, 237, 231, 0.35),
    line: const Color.fromRGBO(241, 237, 231, 0.08),
    lineHi: const Color.fromRGBO(241, 237, 231, 0.14),
    accent: _hex('8EE6C0'),
    live: _hex('8EE6C0'),
    liveBg: _hex('0F2A20'),
    warn: _hex('F4B870'),
    warnBg: const Color.fromRGBO(244, 184, 112, 0.16),
    crit: _hex('F08F7C'),
    critBg: const Color.fromRGBO(240, 143, 124, 0.16),
  );

  static final LyneTheme light = LyneTheme(
    isDark: false,
    bg: _hex('F4EFE7'),
    surface: _hex('FFFFFF'),
    surfaceHi: _hex('EAE3D6'),
    contrast: _hex('1A201D'),
    contrastFg: _hex('FFFFFF'),
    contrastSurface: _hex('2A2925'),
    fg: _hex('1A201D'),
    dim: const Color.fromRGBO(26, 32, 29, 0.6),
    faint: const Color.fromRGBO(26, 32, 29, 0.35),
    line: const Color.fromRGBO(26, 32, 29, 0.1),
    lineHi: const Color.fromRGBO(26, 32, 29, 0.16),
    accent: _hex('2D7A5A'),
    live: _hex('2D7A5A'),
    liveBg: _hex('E8F5EE'),
    warn: _hex('A0631A'),
    warnBg: const Color.fromRGBO(160, 99, 26, 0.14),
    crit: _hex('A4422F'),
    critBg: const Color.fromRGBO(164, 66, 47, 0.14),
  );

  /// Foreground used on top of `accent` fills. White in light mode,
  /// near-black mint-tinted in dark.
  Color get onAccent => isDark ? _hex('0E2218') : _hex('FFFFFF');

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
      outline: isDark ? _hex('2A2820') : line,
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
