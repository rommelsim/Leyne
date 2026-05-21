// Theme tokens — palette for the redesigned Lyne UI.
//
// Dark variant is the design target (warm near-black bg, mint accent,
// JetBrains-style mono for numerics). Light variant mirrors the same
// structure with a darker mint that contrasts on a warm off-white bg.
//
// LyneTheme is exposed as a small data class plus a Material ThemeData
// factory so stock widgets (AppBar, NavigationBar, ListTile, etc.) inherit
// the look without per-widget styling.

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

  static final LyneTheme dark = LyneTheme(
    isDark: true,
    bg: _hex('0E0E0A'),
    surface: _hex('161612'),
    surfaceHi: _hex('1D1C18'),
    contrast: _hex('ECE9E0'),
    contrastFg: _hex('0B0B08'),
    contrastSurface: _hex('2A251F'),
    fg: _hex('ECE9E0'),
    dim: const Color.fromRGBO(236, 233, 224, 0.52),
    faint: const Color.fromRGBO(236, 233, 224, 0.32),
    line: const Color.fromRGBO(255, 255, 255, 0.07),
    lineHi: const Color.fromRGBO(255, 255, 255, 0.14),
    accent: _hex('5EE597'),
    live: _hex('5EE597'),
    liveBg: const Color.fromRGBO(94, 229, 151, 0.14),
    warn: _hex('E9B04B'),
    warnBg: const Color.fromRGBO(233, 176, 75, 0.16),
    crit: _hex('E96A5C'),
    critBg: const Color.fromRGBO(233, 106, 92, 0.16),
  );

  static final LyneTheme light = LyneTheme(
    isDark: false,
    bg: _hex('F7F4ED'),
    surface: _hex('FFFDF7'),
    surfaceHi: _hex('F1ECDE'),
    contrast: _hex('1A1916'),
    contrastFg: _hex('F2EFE8'),
    contrastSurface: _hex('2A2925'),
    fg: _hex('171612'),
    dim: _hex('6D6859'),
    faint: _hex('A8A192'),
    line: _hex('E5E0D2'),
    lineHi: _hex('D8D3C5'),
    accent: _hex('2BAA67'),
    live: _hex('2BAA67'),
    liveBg: _hex('E3F5EA'),
    warn: _hex('B58A1F'),
    warnBg: _hex('F6EBC9'),
    crit: _hex('C44A3A'),
    critBg: _hex('F7DAD4'),
  );

  /// Material ThemeData built from this palette — wires bg/surface/accent
  /// into the Material 3 colour scheme so stock widgets (AppBar,
  /// NavigationBar, ListTile, etc.) inherit the look without per-widget
  /// styling.
  ThemeData get materialTheme {
    final scheme = ColorScheme(
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
    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: fg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
            fontSize: 28, fontWeight: FontWeight.w600, color: fg, letterSpacing: -0.3),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        indicatorColor: isDark
            ? const Color.fromRGBO(255, 255, 255, 0.06)
            : accent.withValues(alpha: 0.10),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: fg),
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
