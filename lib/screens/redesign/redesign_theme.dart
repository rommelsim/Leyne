// Design tokens for the SG Transit redesign (Material 3 Expressive).
//
// This is a faithful Dart port of the CSS custom-property system in the
// "SG Transit App" design composition: the light/dark surface ramp, the
// primary / bus / mrt / amber colour roles, the eight Material You colour
// seeds, and the "premium" monochrome override. Tokens are resolved into an
// immutable [RdTokens] value and handed down the tree via [RdTheme].
//
// Typography is Hanken Grotesk (bundled variable font) — use [rdText]. Icons
// are Material Symbols Rounded via the material_symbols_icons package.

import 'package:flutter/widgets.dart';

Color _hex(String h) {
  final v = h.replaceAll('#', '');
  return Color(int.parse('FF$v', radix: 16));
}

/// Hanken Grotesk text style helper. CSS weights map 1:1 onto [FontWeight].
TextStyle rdText({
  required double size,
  FontWeight weight = FontWeight.w400,
  Color? color,
  double? height,
  double? letterSpacing,
}) {
  return TextStyle(
    fontFamily: 'HankenGrotesk',
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
    // tabular figures — the design relies on aligned numerals for ETAs.
    fontFeatures: const [FontFeature.tabularFigures()],
    leadingDistribution: TextLeadingDistribution.even,
  );
}

/// One selectable Material You colour seed.
class RdSeed {
  const RdSeed(this.key, this.name, this.dot, this.light, this.dark);

  /// Internal key (matches the prototype's seed ids).
  final String key;

  /// Label shown under the swatch in Settings.
  final String name;

  /// Swatch dot colour.
  final Color dot;

  /// `[primary, onPrimary, primaryContainer, onPrimaryContainer]` for light /
  /// dark. `null` means "use the base palette" (the Default seed).
  final List<Color>? light;
  final List<Color>? dark;
}

List<Color>? _seedSet(List<String>? hexes) =>
    hexes?.map(_hex).toList(growable: false);

/// The eight seeds, in the order the prototype lists them.
final List<RdSeed> kRdSeeds = [
  RdSeed('blue', 'Default', _hex('#1F66E0'), null, null),
  RdSeed('violet', 'Teal', _hex('#0F8A8A'),
      _seedSet(['#0F8A8A', '#FFFFFF', '#A8F2EE', '#00201F']),
      _seedSet(['#54D9D2', '#003735', '#00504D', '#A8F2EE'])),
  RdSeed('green', 'Cyan', _hex('#0B7EA0'),
      _seedSet(['#0B7EA0', '#FFFFFF', '#B5EAFF', '#001F2A']),
      _seedSet(['#5BD2F8', '#00344A', '#004C63', '#B5EAFF'])),
  RdSeed('coral', 'Fuchsia', _hex('#B5179E'),
      _seedSet(['#B5179E', '#FFFFFF', '#FFD7F0', '#3D0036']),
      _seedSet(['#FFA9E4', '#5E0052', '#820072', '#FFD7F0'])),
  RdSeed('teal', 'Rose', _hex('#C2185B'),
      _seedSet(['#C2185B', '#FFFFFF', '#FFD9E1', '#400014']),
      _seedSet(['#FFB1C5', '#65002A', '#8E0040', '#FFD9E1'])),
  RdSeed('rose', 'Slate', _hex('#475569'),
      _seedSet(['#475569', '#FFFFFF', '#D8E2F0', '#0A1B2E']),
      _seedSet(['#AEC3DE', '#1A2A3D', '#33455A', '#D8E2F0'])),
  RdSeed('amber', 'Plum', _hex('#7A1FA2'),
      _seedSet(['#7A1FA2', '#FFFFFF', '#F2D9FF', '#2C0043']),
      _seedSet(['#E3B0FF', '#4A0068', '#621A82', '#F2D9FF'])),
  RdSeed('indigo', 'Sand', _hex('#7A6A3A'),
      _seedSet(['#7A6A3A', '#FFFFFF', '#FFEFC2', '#261A00']),
      _seedSet(['#E8CE8E', '#3F2E00', '#5B4A1F', '#FFEFC2'])),
];

RdSeed _seedFor(String key) =>
    kRdSeeds.firstWhere((s) => s.key == key, orElse: () => kRdSeeds.first);

/// Resolved colour roles for one configuration of theme / seed / premium.
@immutable
class RdTokens {
  const RdTokens({
    required this.dark,
    required this.page,
    required this.page2,
    required this.surface,
    required this.sc,
    required this.scLow,
    required this.scHigh,
    required this.scHighest,
    required this.onSurface,
    required this.onVariant,
    required this.outline,
    required this.outlineVariant,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.bus,
    required this.busContainer,
    required this.onBusContainer,
    required this.mrt,
    required this.mrtContainer,
    required this.onMrtContainer,
    required this.amber,
    required this.amberContainer,
    required this.onAmberContainer,
  });

  final bool dark;
  final Color page, page2;
  final Color surface, sc, scLow, scHigh, scHighest;
  final Color onSurface, onVariant, outline, outlineVariant;
  final Color primary, onPrimary, primaryContainer, onPrimaryContainer;
  final Color bus, busContainer, onBusContainer;
  final Color mrt, mrtContainer, onMrtContainer;
  final Color amber, amberContainer, onAmberContainer;

  /// Fixed amber/orange used for the MRT-transfer affordances in the design
  /// (independent of the amber *role*, which shifts in dark mode).
  Color get transferOrange => _hex('#FA9E0D');
  Color get transferOnOrange => _hex('#3A2500');

  static RdTokens resolve({
    required bool dark,
    required String seed,
    required bool premium,
  }) {
    // Base light / dark ramp.
    RdTokens base = dark ? _darkBase : _lightBase;

    // Premium monochrome takes precedence over seeds and recolours the whole
    // surface ramp to neutral greys (line colours stay as the only accent).
    if (premium) {
      return base.copyWith(
        surface: _hex('#FFFFFF'),
        sc: _hex('#EFEFF2'),
        scLow: _hex('#F5F5F7'),
        scHigh: _hex('#ECECEF'),
        scHighest: _hex('#E5E5EA'),
        onSurface: _hex('#1C1C1E'),
        onVariant: _hex('#6E6E73'),
        outline: _hex('#A6A6AD'),
        outlineVariant: _hex('#E5E5EA'),
        page: _hex('#F5F5F7'),
        page2: _hex('#FFFFFF'),
        primary: _hex('#1C1C1E'),
        onPrimary: _hex('#FFFFFF'),
        primaryContainer: _hex('#F0F0F2'),
        onPrimaryContainer: _hex('#1C1C1E'),
      );
    }

    // Seed override of the four primary roles.
    final set = dark ? _seedFor(seed).dark : _seedFor(seed).light;
    if (set != null) {
      base = base.copyWith(
        primary: set[0],
        onPrimary: set[1],
        primaryContainer: set[2],
        onPrimaryContainer: set[3],
      );
    }
    return base;
  }

  RdTokens copyWith({
    Color? page,
    Color? page2,
    Color? surface,
    Color? sc,
    Color? scLow,
    Color? scHigh,
    Color? scHighest,
    Color? onSurface,
    Color? onVariant,
    Color? outline,
    Color? outlineVariant,
    Color? primary,
    Color? onPrimary,
    Color? primaryContainer,
    Color? onPrimaryContainer,
  }) {
    return RdTokens(
      dark: dark,
      page: page ?? this.page,
      page2: page2 ?? this.page2,
      surface: surface ?? this.surface,
      sc: sc ?? this.sc,
      scLow: scLow ?? this.scLow,
      scHigh: scHigh ?? this.scHigh,
      scHighest: scHighest ?? this.scHighest,
      onSurface: onSurface ?? this.onSurface,
      onVariant: onVariant ?? this.onVariant,
      outline: outline ?? this.outline,
      outlineVariant: outlineVariant ?? this.outlineVariant,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      onPrimaryContainer: onPrimaryContainer ?? this.onPrimaryContainer,
      bus: bus,
      busContainer: busContainer,
      onBusContainer: onBusContainer,
      mrt: mrt,
      mrtContainer: mrtContainer,
      onMrtContainer: onMrtContainer,
      amber: amber,
      amberContainer: amberContainer,
      onAmberContainer: onAmberContainer,
    );
  }

  static final RdTokens _lightBase = RdTokens(
    dark: false,
    page: _hex('#E6E9ED'),
    page2: _hex('#EFF1F4'),
    surface: _hex('#FFFFFF'),
    sc: _hex('#EFF2F6'),
    scLow: _hex('#F5F7FA'),
    scHigh: _hex('#E8ECF1'),
    scHighest: _hex('#DFE4EC'),
    onSurface: _hex('#14161A'),
    onVariant: _hex('#4A515B'),
    outline: _hex('#79808B'),
    outlineVariant: _hex('#D5DAE1'),
    primary: _hex('#1F66E0'),
    onPrimary: _hex('#FFFFFF'),
    primaryContainer: _hex('#D9E6FF'),
    onPrimaryContainer: _hex('#0A2C66'),
    bus: _hex('#1F8A4C'),
    busContainer: _hex('#DCEFE0'),
    onBusContainer: _hex('#0A3D20'),
    mrt: _hex('#D23B2C'),
    mrtContainer: _hex('#FBE2DD'),
    onMrtContainer: _hex('#551812'),
    amber: _hex('#B0670C'),
    amberContainer: _hex('#FCE6C8'),
    onAmberContainer: _hex('#3A2500'),
  );

  static final RdTokens _darkBase = RdTokens(
    dark: true,
    page: _hex('#0A0C10'),
    page2: _hex('#12151B'),
    surface: _hex('#13161C'),
    sc: _hex('#1D212A'),
    scLow: _hex('#171A21'),
    scHigh: _hex('#262B36'),
    scHighest: _hex('#30363F'),
    onSurface: _hex('#EAEDF2'),
    onVariant: _hex('#B4BBC6'),
    outline: _hex('#878E9A'),
    outlineVariant: _hex('#2A2F3A'),
    primary: _hex('#9CC0FF'),
    onPrimary: _hex('#0A2C66'),
    primaryContainer: _hex('#234890'),
    onPrimaryContainer: _hex('#D6E6FF'),
    bus: _hex('#5FCB8A'),
    busContainer: _hex('#123524'),
    onBusContainer: _hex('#9FE6BC'),
    mrt: _hex('#F5708A'),
    mrtContainer: _hex('#36161C'),
    onMrtContainer: _hex('#FBC4CE'),
    amber: _hex('#F5B53D'),
    amberContainer: _hex('#4A3410'),
    onAmberContainer: _hex('#FCE6C8'),
  );
}

/// Inherited carrier so any descendant can read the resolved [RdTokens].
class RdTheme extends InheritedWidget {
  const RdTheme({super.key, required this.tokens, required super.child});

  final RdTokens tokens;

  static RdTokens of(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<RdTheme>();
    assert(w != null, 'RdTheme.of() called with no RdTheme in the tree');
    return w!.tokens;
  }

  @override
  bool updateShouldNotify(RdTheme old) => old.tokens != tokens;
}
