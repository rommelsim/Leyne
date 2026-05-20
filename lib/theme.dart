// Theme tokens — 1:1 port of legacy/ios-native/Lyne/Theme.swift.
//
// Same hex palette in light + dark variants. Exposed as a small data class
// (LyneTheme) plus a Material ThemeData factory so Material widgets pick
// up the right surface / outline / scheme without you having to translate
// every token at the call site.

import 'package:flutter/material.dart';

@immutable
class LyneTheme {
  const LyneTheme({
    required this.isDark,
    required this.bg,
    required this.surface,
    required this.contrast,
    required this.contrastFg,
    required this.contrastSurface,
    required this.fg,
    required this.dim,
    required this.line,
    required this.accent,
    required this.live,
    required this.liveBg,
    required this.warn,
    required this.crit,
  });

  final bool isDark;
  final Color bg;
  final Color surface;
  final Color contrast;
  final Color contrastFg;
  final Color contrastSurface;
  final Color fg;
  final Color dim;
  final Color line;
  final Color accent;
  final Color live;
  final Color liveBg;
  final Color warn;
  final Color crit;

  /// SF Mono on iOS, Roboto Mono on Android (Flutter's monospace fallback).
  static const TextStyle monoBase =
      TextStyle(fontFamily: 'monospace', fontFamilyFallback: ['Menlo', 'Courier']);

  TextStyle mono(double size, {FontWeight weight = FontWeight.w400}) =>
      monoBase.copyWith(fontSize: size, fontWeight: weight, color: fg);

  TextStyle sans(double size, {FontWeight weight = FontWeight.w400}) =>
      TextStyle(fontSize: size, fontWeight: weight, color: fg);

  // Hex constructor for the design tokens below.
  static Color _hex(String hex) {
    final s = hex.replaceFirst('#', '');
    return Color(int.parse('FF$s', radix: 16));
  }

  static final LyneTheme light = LyneTheme(
    isDark: false,
    bg: _hex('F7F4ED'),
    surface: _hex('FFFDF7'),
    contrast: _hex('1A1916'),
    contrastFg: _hex('F2EFE8'),
    contrastSurface: _hex('2A2925'),
    fg: _hex('171612'),
    dim: _hex('807A6E'),
    line: _hex('E5E0D2'),
    accent: _hex('8B5A2B'),
    live: _hex('3C8A4E'),
    liveBg: _hex('EEF5EF'),
    warn: _hex('B58A1F'),
    crit: _hex('C44A3A'),
  );

  static final LyneTheme dark = LyneTheme(
    isDark: true,
    bg: _hex('15140F'),
    surface: _hex('1F1D17'),
    contrast: _hex('F2EFE8'),
    contrastFg: _hex('15140F'),
    contrastSurface: _hex('E5E0D2'),
    fg: _hex('F2EFE8'),
    dim: _hex('8A8478'),
    line: _hex('2A2820'),
    accent: _hex('D9A86C'),
    live: _hex('5BC07A'),
    liveBg: _hex('1B2A1F'),
    warn: _hex('D9B466'),
    crit: _hex('E07A6A'),
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
      outline: line,
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
            fontSize: 17, fontWeight: FontWeight.w600, color: fg),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: accent.withValues(alpha: 0.18),
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
/// `LyneTheme.of(context)`. We resolve by looking at the current
/// brightness so the right palette comes back without a Theme provider.
extension LyneThemeContext on BuildContext {
  LyneTheme get t => Theme.of(this).brightness == Brightness.dark
      ? LyneTheme.dark
      : LyneTheme.light;
}
