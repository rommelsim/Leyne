// SoftBlue "4b" — Departly's shared design-language tokens + primitives.
//
// Ports docs/soft-blue-design.md (the BINDING spec) from the iOS reference
// implementation (ios-native/Leyne/WhereSia/WSSoftTheme.swift +
// WSHomeView.swift + WSBusStopView.swift) so Android ships the SAME look.
// This supersedes LyneTheme's monochrome/Material-You direction on every
// screen ported to this system — see the spec's §5 porting table. Do not mix
// `SoftBlue` tokens and `LyneTheme`/`context.t` on the same screen/file
// (spec anti-rule #8): port a screen wholesale or not at all.
//
// This file is the ONLY place allowed to declare new shared Soft* symbols
// (mirrors the iOS rule that WSSoftTheme.swift is the sole home for shared
// soft symbols) — promote a screen-local widget here if a second screen
// needs it, don't fork it.
//
// Anti-rules enforced by these primitives (spec §7 — violate none):
//   1. No glows — no `shadow(color: accent.opacity(x))` on text/edges.
//   2. No text-shadows anywhere, including the hero.
//   3. No gradients except the ONE hero gradient per screen.
//   4. No mint, in any opacity, for any purpose.
//   5. No bare-bordered/outlined chips — filled + shadow, or ink/blue solid.
//   6. No more than one saturated gradient card visible at a time.
//   7. No progress rings outside the hero.
//   8. Never mix WSTheme/LyneTheme tokens and SoftBlue tokens on one screen.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The SoftBlue palette (spec §1). All hex values are load-bearing — do not
/// "improve" them without updating docs/soft-blue-design.md first.
@immutable
abstract final class SoftBlue {
  /// Page ground (tinted pale blue) — always visible between cards.
  static const Color bg = Color(0xFFDCE9F4);

  /// Floating surfaces — the only other large fill besides the hero.
  static const Color card = Color(0xFFFFFFFF);

  /// Primary text on white/ground.
  static const Color ink = Color(0xFF1B2430);

  /// Secondary text — meta lines, captions.
  static const Color sub = Color(0xFF7A8794);

  /// In-card row separators only.
  static const Color hairline = Color(0xFFEEF3F8);

  /// Hero gradient start, links, "View all" actions. The ONE decorative
  /// accent — never means "warning" or "identity".
  static const Color blue = Color(0xFF2E8FE0);

  /// Hero gradient end.
  static const Color blueSoft = Color(0xFF5CB8F2);

  /// Tinted chips, icon tiles (the "B" stop-type tile, ETA chip fill).
  static const Color chipBg = Color(0xFFE4F1FC);

  /// Text/numerals on [chipBg].
  static const Color chipInk = Color(0xFF1F74C0);

  /// Disruptions, standing crowd — semantic only, never decorative.
  static const Color amber = Color(0xFFE8960C);

  /// Severe disruption, packed crowd — semantic only, never decorative.
  static const Color red = Color(0xFFD9483B);

  /// The one shadow tint (used at varying alpha/blur — see [cardShadow] and
  /// friends). Never use `Colors.black` for a shadow colour in this language.
  static const Color shadow = Color(0xFF173049);

  /// An ETA chip whose value deepened for "arriving now" emphasis (spec §1:
  /// "chip background may deepen slightly — chipBg → mix 15% blue"). Never a
  /// glow, never mint.
  static Color get chipBgEmphasis => Color.alphaBlend(
    blue.withValues(alpha: 0.15),
    chipBg,
  );

  /// The ONE hero gradient — non-negotiable, one per screen (spec §4).
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [blue, blueSoft],
  );

  // ── Shadows (§3 — "the one shadow recipe") ───────────────────────────────

  static List<BoxShadow> cardShadow = [
    BoxShadow(
      color: shadow.withValues(alpha: 0.07),
      blurRadius: 9,
      offset: const Offset(0, 6),
    ),
  ];

  static List<BoxShadow> iconButtonShadow = [
    BoxShadow(
      color: shadow.withValues(alpha: 0.07),
      blurRadius: 6,
      offset: const Offset(0, 3),
    ),
  ];

  static List<BoxShadow> chipShadow = [
    BoxShadow(
      color: shadow.withValues(alpha: 0.07),
      blurRadius: 5,
      offset: const Offset(0, 3),
    ),
  ];

  /// The hero card is the only element allowed a TINTED shadow.
  static List<BoxShadow> heroShadow = [
    BoxShadow(
      color: blue.withValues(alpha: 0.30),
      blurRadius: 13,
      offset: const Offset(0, 8),
    ),
  ];

  // ── Shape (§3) ────────────────────────────────────────────────────────────

  static const double heroRadius = 24;
  static const double cardRadius = 20;
  static const double tileRadius = 18;
  static const double iconTileRadius = 12;
  static const double iconButtonRadius = 14;
  static const double etaChipRadius = 11;

  // ── Type (§2) ─────────────────────────────────────────────────────────────
  // Inter isn't a pubspec dependency; the platform default face at these
  // exact sizes/weights mirrors iOS's `ws.sans` scale closely enough that no
  // new font dependency is warranted for the port. Numerals are always
  // tabular via FontFeature — mirrors iOS's `.monospacedDigit()` — never
  // plain proportional figures for countdowns/codes/distances.

  static TextStyle sans(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
    bool tabular = false,
  }) => TextStyle(
    fontSize: size,
    fontWeight: weight,
    color: color ?? ink,
    letterSpacing: 0,
    fontFeatures: tabular ? const [ui.FontFeature.tabularFigures()] : null,
  );

  /// Tabular-figure numerals — countdowns, codes, distances, ETA chips.
  static TextStyle mono(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) => TextStyle(
    fontSize: size,
    fontWeight: weight,
    color: color ?? ink,
    fontFeatures: const [ui.FontFeature.tabularFigures()],
  );
}

/// Canonical motion timing — mirrors the pulse cadence used for the
/// "watching"/disruption chip opacity pulse (spec §5: "animate the chip's
/// opacity subtly — existing pulse timing: 1s ease-in-out repeat").
///
/// Superseded for new work by [SoftMotion] (2026-07-25 owner directive: "the
/// whole app moves as one weather system" — flow/drift/settle/breathe). Kept
/// for the existing `_OpacityPulse`/`SoftSkeletonBar` call sites that predate
/// that directive; don't add new ad-hoc `Duration`/`Curve` literals to
/// soft-blue screens — reach for [SoftMotion] instead.
abstract final class SoftBlueMotion {
  static const pulse = Duration(milliseconds: 1000);
  static const standard = Duration(milliseconds: 220);
}

/// The app-wide water/cloud motion vocabulary (owner 2026-07-25, ported from
/// iOS `SoftMotion` in WSSoftTheme.swift): nothing snaps — state changes
/// FLOW like water finding a level, appearances DRIFT in like cloud, ambient
/// tells BREATHE. Use these tokens instead of ad-hoc `Duration`/`Curves`
/// literals so the whole app moves as one weather system. Each token pairs a
/// [Duration] with the [Curve] iOS uses for the same role — apply both
/// together (e.g. `AnimatedContainer(duration: SoftMotion.flowDuration,
/// curve: SoftMotion.flowCurve, ...)` or via [SoftMotion.flow] for
/// `implicitly`-animated widgets that take a single `Curve`).
abstract final class SoftMotion {
  /// State changes (chips, expand/collapse, value updates): a soft spring
  /// with no bounce — water settling, not a mechanical snap. Mirrors iOS's
  /// `Animation.smooth(duration: 0.45)`.
  static const flowDuration = Duration(milliseconds: 450);
  static const flowCurve = Curves.easeOutCubic;
  static const flow = flowCurve;

  /// Appearances/entrances: slow start-fast-slow drift, like cloud moving.
  /// Mirrors iOS's `Animation.easeInOut(duration: 0.7)`.
  static const driftDuration = Duration(milliseconds: 700);
  static const driftCurve = Curves.easeInOut;
  static const drift = driftCurve;

  /// One-shot appear sweeps (ring fill, hero reveal). Mirrors iOS's
  /// `Animation.easeOut(duration: 0.9)`.
  static const settleDuration = Duration(milliseconds: 900);
  static const settleCurve = Curves.easeOut;
  static const settle = settleCurve;

  /// Ambient repeating tells (tip dots, live markers, ripple rings): a slow
  /// inhale/exhale. Mirrors iOS's
  /// `Animation.easeInOut(duration: 2.2).repeatForever(autoreverses: true)`.
  /// Callers drive an `AnimationController(duration: breatheDuration)
  /// ..repeat(reverse: true)` with `curve: breatheCurve` on the derived
  /// `CurvedAnimation` — there's no single-shot Flutter equivalent of
  /// SwiftUI's `repeatForever`.
  static const breatheDuration = Duration(milliseconds: 2200);
  static const breatheCurve = Curves.easeInOut;
}

// ═══════════════════════════════════════════════════════════════════════════
// Primitives
// ═══════════════════════════════════════════════════════════════════════════

/// White rounded card, radius 20, the one shadow recipe. The base surface for
/// every non-hero content block in this language.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = SoftBlue.cardRadius,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: SoftBlue.card,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: SoftBlue.cardShadow,
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

/// Section head — bold 16 title left + optional 12.5 semibold blue action
/// right, 4pt horizontal inset so it sits flush with the card content below.
class SoftSectionHead extends StatelessWidget {
  const SoftSectionHead({
    super.key,
    required this.title,
    this.action,
    this.onAction,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Text(
            title,
            style: SoftBlue.sans(16, weight: FontWeight.w700, color: SoftBlue.ink),
          ),
          if (action != null) ...[
            const Spacer(),
            GestureDetector(
              onTap: onAction,
              child: Text(
                action!,
                style: SoftBlue.sans(
                  12.5,
                  weight: FontWeight.w600,
                  color: SoftBlue.blue,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The ONLY chrome for header actions (search, map, back): 40×40 white
/// square, radius 14, icon 15pt ink@75%, the icon-button shadow. No
/// bordered/outlined/tinted variant, ever (spec §4).
class SoftIconButton extends StatelessWidget {
  const SoftIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: SoftBlue.card,
        borderRadius: BorderRadius.circular(SoftBlue.iconButtonRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(SoftBlue.iconButtonRadius),
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SoftBlue.iconButtonRadius),
              boxShadow: SoftBlue.iconButtonShadow,
            ),
            child: Icon(icon, size: 15, color: SoftBlue.ink.withValues(alpha: 0.75)),
          ),
        ),
      ),
    );
  }
}

/// The app-wide stop metadata string: `Stop 41101 · 2 min walk · 189m away`.
///
/// Ported from iOS `wsStopCodeLabel(_:suffix:)` (WSFormat.swift). The "Stop "
/// prefix is not decoration — a bare 5-digit number is ambiguous next to bus
/// numbers and MRT line codes, so the code NEVER prints alone (ui-checklist
/// §2). [suffix] carries the walk/distance fragment when a location fix is
/// available; without one the label degrades to the labelled code rather than
/// guessing.
String stopCodeLabel(String code, {String? suffix}) {
  if (suffix == null || suffix.isEmpty) return 'Stop $code';
  return 'Stop $code · $suffix';
}

/// Monospaced "Stop {code}" caption — the small identity fragment used in
/// row sublines throughout (bus stop code, station code). [suffix] appends the
/// shared walk/distance fragment via [stopCodeLabel].
class SoftStopCode extends StatelessWidget {
  const SoftStopCode(this.code, {super.key, this.color, this.suffix});
  final String code;
  final Color? color;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Text(
      stopCodeLabel(code, suffix: suffix),
      style: SoftBlue.mono(11.5, weight: FontWeight.w500, color: color ?? SoftBlue.sub),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// "This card is saved" mark — a filled star chip that sits directly after a
/// name on any Saved-tab card. Ported from iOS `WSSavedView.savedMark`
/// (2026-07-25): the Favourites list was visually identical to the Nearby
/// list, so nothing on a card said it was saved — the state was implied only
/// by which tab you were on.
class SoftSavedMark extends StatelessWidget {
  const SoftSavedMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Saved',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: SoftBlue.chipBg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Icon(Icons.star_rounded, size: 11, color: SoftBlue.chipInk),
      ),
    );
  }
}

/// One row of a hero card's mini departure board: service number · destination
/// · big ETA. Ported from iOS `SoftHeroBoardRow` (WSSoftTheme.swift).
///
/// The board replaced the countdown ring on both hero cards (owner
/// 2026-07-25): the ring spent a third of the card stating ONE number that
/// belonged to only one of the several buses at the stop, and forced every
/// other departure into a cramped "then …" strip. Three services with their
/// own destinations and their own times is strictly more of the answer in the
/// same space. [lead] emphasises the soonest slot with WEIGHT and opacity
/// only — never a larger size, which would break row alignment (§3).
class SoftHeroBoardRow extends StatelessWidget {
  const SoftHeroBoardRow({
    super.key,
    required this.no,
    required this.dest,
    required this.etaBig,
    this.lead = false,
  });

  final String no;
  final String dest;

  /// `fmtEta(...).big` — "Arr" or a minutes digit string.
  final String etaBig;
  final bool lead;

  @override
  Widget build(BuildContext context) {
    // Every ETA carries a unit, and "Arr" is banned in board contexts — print
    // "Now" (ui-checklist §2).
    final isNow = etaBig == 'Arr';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 46,
            child: Text(
              no,
              style: SoftBlue.sans(
                14,
                weight: FontWeight.w800,
                color: Colors.white,
                tabular: true,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Text(
              dest,
              style: SoftBlue.sans(
                12.5,
                weight: FontWeight.w600,
                color: Colors.white.withValues(alpha: lead ? 0.95 : 0.72),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          // Fixed-width time column so the board's numbers align down the card
          // regardless of "Now" vs "12 min" (§3).
          SizedBox(
            width: 62,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: isNow ? 'Now' : etaBig,
                    style: SoftBlue.sans(
                      17,
                      weight: lead ? FontWeight.w800 : FontWeight.w700,
                      color: Colors.white.withValues(alpha: lead ? 1 : 0.8),
                      tabular: true,
                    ),
                  ),
                  if (!isNow)
                    TextSpan(
                      text: ' min',
                      style: SoftBlue.sans(
                        10.5,
                        weight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: lead ? 0.8 : 0.62),
                      ),
                    ),
                ],
              ),
              textAlign: TextAlign.right,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// ETA chip — the trailing element on a service/stop row. `chipBg` fill,
/// radius 11, bold monospaced `chipInk` text, `"{no} · {mins} min"` or
/// `"{no} · Arr"`. Pass [emphasis] when the value is imminent (spec §1: bold
/// + a slightly deeper chip fill is the correct lever — never colour/glow).
class SoftEtaChip extends StatelessWidget {
  const SoftEtaChip({super.key, required this.label, this.emphasis = false});

  final String label;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: emphasis ? SoftBlue.chipBgEmphasis : SoftBlue.chipBg,
        borderRadius: BorderRadius.circular(SoftBlue.etaChipRadius),
      ),
      child: Text(
        label,
        style: SoftBlue.mono(
          12.5,
          weight: FontWeight.bold,
          color: SoftBlue.chipInk,
        ),
      ),
    );
  }
}

/// Segmented bus + time pill — ONE capsule, two segments: bright segment
/// carries the service number, dim segment the time, so the pair reads as a
/// unit while the halves stay distinct (ported from iOS `SoftBusTimePill` in
/// WSSoftTheme.swift, owner 2026-07-25; born on the Nearby hero, now the
/// app-wide idiom for any "bus X in N min" pairing). Pass [onGradient] for
/// use on the blue hero card (white 32%/12% segment fills, white text);
/// default styling is for white cards (chipBg fills, chipInk/ink text).
/// Fixed [noWidth]/[timeWidth] let a caller align the segment boundary down
/// a column of rows (spec item 2: "fixed segment widths so columns align
/// across rows").
class SoftBusTimePill extends StatelessWidget {
  const SoftBusTimePill({
    super.key,
    required this.no,
    required this.etaBig,
    this.onGradient = false,
    this.noWidth,
    this.timeWidth,
  });

  /// Service number, e.g. "170".
  final String no;

  /// `fmtEta(...).big` — "Arr" or a minutes digit string.
  final String etaBig;
  final bool onGradient;
  final double? noWidth;
  final double? timeWidth;

  @override
  Widget build(BuildContext context) {
    final timeLabel = etaBig == 'Arr' ? 'Arr' : '$etaBig min';
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(
            no,
            weight: FontWeight.w800,
            ink: onGradient ? Colors.white : SoftBlue.chipInk,
            bg: onGradient
                ? Colors.white.withValues(alpha: 0.32)
                : SoftBlue.chipBg,
            width: noWidth,
          ),
          _segment(
            timeLabel,
            weight: FontWeight.w600,
            ink: onGradient ? Colors.white : SoftBlue.ink,
            bg: onGradient
                ? Colors.white.withValues(alpha: 0.12)
                : SoftBlue.chipBg.withValues(alpha: 0.45),
            width: timeWidth,
          ),
        ],
      ),
    );
  }

  Widget _segment(
    String text, {
    required FontWeight weight,
    required Color ink,
    required Color bg,
    double? width,
  }) {
    return Container(
      width: width,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(
        horizontal: 8,
        vertical: onGradient ? 3.5 : 6,
      ),
      color: bg,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: SoftBlue.mono(onGradient ? 11 : 12, weight: weight, color: ink),
      ),
    );
  }
}

/// Leading identity tile (38–44pt, tinted chipBg fill) — the "B" stop-type
/// tile / service-number tile pattern used at the head of a white-card row.
class SoftIdentityTile extends StatelessWidget {
  const SoftIdentityTile({
    super.key,
    required this.label,
    this.size = 44,
    this.fontSize = 15,
  });

  final String label;
  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: SoftBlue.chipBg,
        borderRadius: BorderRadius.circular(SoftBlue.iconTileRadius),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: SoftBlue.sans(
          fontSize,
          weight: FontWeight.w700,
          color: SoftBlue.chipInk,
          tabular: true,
        ),
      ),
    );
  }
}

/// White-card row anatomy: leading identity tile → name/meta left → trailing
/// ETA chip or chevron (never both — spec §4). Used for stop rows, service
/// rows, saved rows.
class SoftServiceTile extends StatelessWidget {
  const SoftServiceTile({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.showHairline = false,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Row divider inset to align with row text (spec §3: 64pt leading inset
  /// when following an icon-tile row).
  final bool showHairline;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: SoftBlue.sans(14.5, weight: FontWeight.w600, color: SoftBlue.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: SoftBlue.mono(11.5, color: SoftBlue.sub),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          ?trailing,
        ],
      ),
    );
    final tappable = onTap == null && onLongPress == null
        ? row
        : InkWell(onTap: onTap, onLongPress: onLongPress, child: row);
    if (!showHairline) return tappable;
    return Column(
      children: [
        tappable,
        Padding(
          padding: const EdgeInsets.only(left: 64),
          child: Divider(height: 1, thickness: 1, color: SoftBlue.hairline),
        ),
      ],
    );
  }
}

/// Filter pill — capsule, selected = ink fill + white text; unselected =
/// white fill + sub text. BOTH keep the shadow (an unselected chip without
/// one reads as flat/disabled). Never `blue` as the selected fill (spec §4).
class SoftFilterChip extends StatelessWidget {
  const SoftFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? SoftBlue.ink : SoftBlue.card,
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.circular(999),
            boxShadow: SoftBlue.chipShadow,
          ),
          child: Text(
            label,
            style: SoftBlue.sans(
              13,
              weight: FontWeight.w600,
              color: selected ? Colors.white : SoftBlue.sub,
            ),
          ),
        ),
      ),
    );
  }
}

/// Disruption chip — ports the old amber glow-edge/left-border-accent card
/// (banned) to a contained textual capsule (spec §5): a small amber-tinted
/// capsule sitting where the meta line normally is, e.g.
/// "⚠ Delay on North East Line". [severe] swaps amber → red for the worse
/// tier. Pass [pulse] to animate opacity subtly (1s ease-in-out repeat) for
/// urgency — never a colour-shift or glow.
class SoftDisruptionChip extends StatelessWidget {
  const SoftDisruptionChip({
    super.key,
    required this.text,
    this.severe = false,
    this.pulse = false,
  });

  final String text;
  final bool severe;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final color = severe ? SoftBlue.red : SoftBlue.amber;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '⚠ $text',
        style: SoftBlue.sans(11.5, weight: FontWeight.w600, color: color),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    if (!pulse) return chip;
    return _OpacityPulse(child: chip);
  }
}

class _OpacityPulse extends StatefulWidget {
  const _OpacityPulse({required this.child});
  final Widget child;

  @override
  State<_OpacityPulse> createState() => _OpacityPulseState();
}

class _OpacityPulseState extends State<_OpacityPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: SoftBlueMotion.pulse,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(
        begin: 0.6,
        end: 1.0,
      ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}

/// Filled blue bell badge — replaces the banned mint bell badge (spec §5):
/// solid blue circle, white glyph, same position/size, no glow.
class SoftBellBadge extends StatelessWidget {
  const SoftBellBadge({super.key, this.size = 18});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: SoftBlue.blue, shape: BoxShape.circle),
      child: Icon(Icons.notifications_rounded, size: size * 0.6, color: Colors.white),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Hero
// ═══════════════════════════════════════════════════════════════════════════

/// The countdown ring (Nearby hero ONLY — spec §4 / spec item 3c,
/// 2026-07-25): stroke 7, track white@28%, arc fill a sweep gradient from
/// white@45% (tail, 12 o'clock) to solid white (leading tip), trim animates
/// 0→frac where `frac = max(0.08, min(1, 1 - sec/900))`. A small white dot
/// breathes at the exact tip angle, and two thin rings ripple outward from
/// the ring bounds as an ambient "live" tell. The ONLY progress-ring
/// instance in the language — never add one to a non-hero tile, and never
/// add this to the Bus Stop screen's hero (spec item 4b: ring is
/// Nearby-exclusive there).
///
/// iOS shipped a bug here (2026-07-25 spec note) where the sweep gradient
/// was computed in the full-circle frame and the arc drawn in a separately
/// rotated frame, landing the bright tip ~90° off the dot/arc-end. This
/// port avoids that class of bug entirely by deriving the gradient's
/// `startAngle`/`endAngle` from the SAME `tipAngle` used for the arc sweep
/// and the dot position — one angle, three consumers, no way for them to
/// drift apart.
class SoftHeroRing extends StatefulWidget {
  const SoftHeroRing({
    super.key,
    required this.etaSeconds,
    this.size = 64,
    this.unitLabel = 'min',
    this.walkMin,
  });

  final int etaSeconds;
  final double size;
  final String unitLabel;

  /// Walk time in MINUTES (never metres) shown under "Arr" once arrived at
  /// the window where the walk time is the more useful readout (spec item
  /// 3c-v). Omitted (no second line) when null.
  final int? walkMin;

  static double fractionFor(int sec) => (1 - sec / 900).clamp(0.08, 1.0);

  @override
  State<SoftHeroRing> createState() => _SoftHeroRingState();
}

class _SoftHeroRingState extends State<SoftHeroRing>
    with TickerProviderStateMixin {
  // Breathing tip dot: scale 1→1.35, soft glow, ping-ponging.
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: SoftMotion.breatheDuration,
  );

  // Two ripple rings, same 2.6s non-autoreversing loop, second offset 1.3s
  // (half a cycle) later so they read as a continuous outward pulse rather
  // than two rings in lockstep.
  static const _rippleDuration = Duration(milliseconds: 2600);
  static const _rippleOffset = Duration(milliseconds: 1300);
  late final AnimationController _ripple1 = AnimationController(
    vsync: this,
    duration: _rippleDuration,
  );
  late final AnimationController _ripple2 = AnimationController(
    vsync: this,
    duration: _rippleDuration,
  );

  bool _started = false;

  void _startIfNeeded(bool reduceMotion) {
    if (_started || reduceMotion) return;
    _started = true;
    _breathe.repeat(reverse: true);
    _ripple1.repeat();
    Future.delayed(_rippleOffset, () {
      if (mounted) _ripple2.repeat();
    });
  }

  @override
  void dispose() {
    _breathe.dispose();
    _ripple1.dispose();
    _ripple2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    _startIfNeeded(reduceMotion);
    if (reduceMotion) {
      _breathe.stop();
      _ripple1.stop();
      _ripple2.stop();
    }

    final arriving = widget.etaSeconds <= 60;
    final mins = (widget.etaSeconds / 60).ceil().clamp(0, 999);
    final fraction = SoftHeroRing.fractionFor(widget.etaSeconds);
    // Same tipAngle feeds the arc's gradient, the arc's sweep, and the dot
    // position (see class doc) — the one fix for the iOS double-rotation bug.
    final tipAngle = -math.pi / 2 + 2 * math.pi * fraction;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Ripple rings — drawn first, behind everything else.
          if (!reduceMotion) ...[
            AnimatedBuilder(
              animation: _ripple1,
              builder: (context, _) =>
                  _RippleRing(size: widget.size, progress: _ripple1.value),
            ),
            AnimatedBuilder(
              animation: _ripple2,
              builder: (context, _) =>
                  _RippleRing(size: widget.size, progress: _ripple2.value),
            ),
          ],
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fraction),
            duration: SoftMotion.settleDuration,
            curve: SoftMotion.settleCurve,
            builder: (context, frac, _) => CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _RingPainter(
                fraction: frac,
                tipAngle: -math.pi / 2 + 2 * math.pi * frac,
              ),
            ),
          ),
          // Breathing dot, locked to the tip angle — never orbits freely.
          AnimatedBuilder(
            animation: _breathe,
            builder: (context, _) {
              final t = reduceMotion ? 0.0 : _breathe.value;
              final scale = 1.0 + 0.35 * t;
              return _TipDot(size: widget.size, angle: tipAngle, scale: scale);
            },
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                arriving ? 'Arr' : '$mins',
                style: SoftBlue.mono(
                  arriving ? 17 : 19,
                  weight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              if (!arriving)
                Text(
                  widget.unitLabel,
                  style: SoftBlue.sans(
                    8.5,
                    weight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                )
              else if (widget.walkMin != null)
                Text(
                  '${widget.walkMin} min walk',
                  style: SoftBlue.sans(
                    8.5,
                    weight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The dot riding the arc's tip, locked to [angle] — positioned in the same
/// coordinate frame `_RingPainter` uses (centre + radius on the stroke
/// centreline), so it always sits exactly on the tip regardless of [scale].
class _TipDot extends StatelessWidget {
  const _TipDot({required this.size, required this.angle, required this.scale});
  final double size;
  final double angle;
  final double scale;

  static const double _strokeWidth = 7;
  static const double _dotSize = 7;

  @override
  Widget build(BuildContext context) {
    final radius = (size - _strokeWidth) / 2;
    final dx = radius * math.cos(angle);
    final dy = radius * math.sin(angle);
    return Transform.translate(
      offset: Offset(dx, dy),
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: _dotSize,
          height: _dotSize,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.55),
                blurRadius: 5,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One outward-rippling ring, ambient "live" tell (spec item 3c-iv):
/// scale 1→~1.4, opacity 0.45→0 across [progress] 0→1.
class _RippleRing extends StatelessWidget {
  const _RippleRing({required this.size, required this.progress});
  final double size;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final scale = 1.0 + 0.4 * progress;
    final opacity = 0.45 * (1 - progress);
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.fraction, required this.tipAngle});
  final double fraction;

  /// Same angle the dot/gradient use — see [SoftHeroRing] class doc.
  final double tipAngle;
  static const double strokeWidth = 7;
  static const double _startAngle = -math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final track = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    if (fraction <= 0) return;
    // Sweep gradient spans EXACTLY the drawn arc (_startAngle → tipAngle) —
    // tail at white@45%, tip at solid white. Deriving startAngle/endAngle
    // from the same _startAngle/tipAngle the arc itself uses is what keeps
    // the bright end pinned to the visual tip (see class doc re: the iOS bug).
    final end = tipAngle == _startAngle ? _startAngle + 0.001 : tipAngle;
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: _startAngle,
        endAngle: end,
        colors: [Colors.white.withValues(alpha: 0.45), Colors.white],
      ).createShader(rect);
    canvas.drawArc(rect, _startAngle, 2 * math.pi * fraction, false, fill);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.fraction != fraction || oldDelegate.tipAngle != tipAngle;
}

/// Gradient "board" hero — the 2026-07-25 hero for Nearby and Saved, ported
/// from iOS `SoftHeroCard` / `WSSavedView.savedHero`.
///
/// PLACE FIRST, THEN DEPARTURES (ui-checklist §2). The card used to lead with
/// the soonest bus ("Bus 165 · Hougang Ctrl Int") while the stop name sat
/// above it in 14pt — so the biggest words on the screen answered a question
/// the user hadn't asked yet. WHERE am I standing comes before WHICH bus, so
/// the stop name is the title and the buses follow it as a board.
///
/// [decision] is the one line on the card that isn't data ("Leave in 4 min" on
/// Saved); it gets its own capsule rather than becoming a fourth field on a
/// metadata line nobody would read that far into.
class SoftBoardHeroCard extends StatelessWidget {
  const SoftBoardHeroCard({
    super.key,
    required this.title,
    required this.meta,
    required this.board,
    this.decision,
    this.ctaLabel,
    this.onTap,
    this.onLongPress,
    this.emptyLabel = 'No live arrivals right now',
  });

  /// The STOP NAME — never a bus number.
  final String title;

  /// `Stop 41101 · 2 min walk · 189m away`, built by [stopCodeLabel].
  final String meta;

  /// Up to three DISTINCT services, soonest first. A feed repeat of the same
  /// bus is noise when the question is "which bus can I take" (§2).
  final List<({String no, String dest, String etaBig})> board;

  /// Optional decision capsule, e.g. "Leave in 4 min".
  final String? decision;
  final String? ctaLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Missing data gets a sentence, not blank columns (§3).
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: SoftBlue.heroGradient,
        borderRadius: BorderRadius.circular(SoftBlue.heroRadius),
        boxShadow: SoftBlue.heroShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title block. The glyph carries "bus stop", so no eyebrow row has
          // to spell it out; on Nearby the closest stop is self-evidently the
          // closest, so there's no "CLOSEST" label either.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.directions_bus_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: SoftBlue.sans(
                        21,
                        weight: FontWeight.w800,
                        color: Colors.white,
                      ).copyWith(letterSpacing: -0.3),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      style: SoftBlue.sans(
                        11.5,
                        weight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.8),
                        tabular: true,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (decision != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          decision!,
                          style: SoftBlue.sans(
                            11,
                            weight: FontWeight.w700,
                            color: Colors.white,
                            tabular: true,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (board.isEmpty)
            Text(
              emptyLabel,
              style: SoftBlue.sans(
                14,
                weight: FontWeight.w600,
                color: Colors.white,
              ),
            )
          else
            for (var i = 0; i < board.length; i++) ...[
              if (i > 0)
                Container(height: 1, color: Colors.white.withValues(alpha: 0.20)),
              SoftHeroBoardRow(
                no: board[i].no,
                dest: board[i].dest,
                etaBig: board[i].etaBig,
                lead: i == 0,
              ),
            ],
          if (ctaLabel != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
              ),
              child: Text(
                ctaLabel!,
                style: SoftBlue.sans(
                  12,
                  weight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null && onLongPress == null) return card;
    // The whole card is the tap target — a card that represents a destination
    // is tappable as a whole, not only via its CTA (ui-checklist §7).
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(SoftBlue.heroRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(SoftBlue.heroRadius),
        onTap: onTap,
        onLongPress: onLongPress,
        child: card,
      ),
    );
  }
}

/// Gradient hero card — ONE per screen, non-negotiable (spec §4). Layout:
/// eyebrow ("CLOSEST · STOP NAME") → title (bus + dest) → "then …" line →
/// ring trailing. The hero's own tinted shadow is the only exception to the
/// single shadow recipe.
///
/// SUPERSEDED on Nearby and Saved by [SoftBoardHeroCard] (owner 2026-07-25 —
/// the ring came out). Still used where a single-value countdown is the whole
/// answer.
class SoftHeroCard extends StatelessWidget {
  const SoftHeroCard({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.etaSeconds,
    this.secondaryLine,
    this.thenServices = const [],
    this.ctaLabel,
    this.onCta,
    this.onTap,
    this.walkMin,
  });

  /// e.g. "CLOSEST · WOODLANDS INT"
  final String eyebrow;

  /// e.g. "Bus 170 → Woodlands"
  final String title;

  /// Live countdown, drives the ring + numeral.
  final int etaSeconds;

  /// e.g. "Leave in 2 min · 3 min walk" (Favourites' decision line). For
  /// later BUSES prefer [thenServices] — segmented pills keep the number
  /// and the minutes visually distinct (owner 2026-07-25: "then 165 5 min"
  /// as a string was unreadable).
  final String? secondaryLine;

  /// Later buses rendered as "then" + onGradient [SoftBusTimePill]s.
  /// Takes precedence over [secondaryLine] when non-empty.
  final List<({String no, String etaBig})> thenServices;

  /// Walk time in minutes to the featured stop — shown under the ring's
  /// "Arr" numeral (spec item 3c-v). Ignored while `etaSeconds` isn't in the
  /// "Arr" window.
  final int? walkMin;

  /// e.g. "Open stop"
  final String? ctaLabel;
  final VoidCallback? onCta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: SoftBlue.heroGradient,
        borderRadius: BorderRadius.circular(SoftBlue.heroRadius),
        boxShadow: SoftBlue.heroShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  eyebrow.toUpperCase(),
                  style: SoftBlue.sans(
                    10.5,
                    weight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85),
                  ).copyWith(letterSpacing: 0.5),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: SoftBlue.sans(
                    19,
                    weight: FontWeight.w800,
                    color: Colors.white,
                  ).copyWith(letterSpacing: -0.2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (thenServices.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'then',
                        style: SoftBlue.sans(
                          11.5,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                      for (final s in thenServices.take(2)) ...[
                        const SizedBox(width: 8),
                        SoftBusTimePill(
                          no: s.no,
                          etaBig: s.etaBig,
                          onGradient: true,
                        ),
                      ],
                    ],
                  ),
                ] else if (secondaryLine != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    secondaryLine!,
                    style: SoftBlue.mono(
                      12,
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (ctaLabel != null) ...[
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: onCta,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        ctaLabel!,
                        style: SoftBlue.sans(
                          13,
                          weight: FontWeight.w700,
                          color: SoftBlue.blue,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 14),
          SoftHeroRing(etaSeconds: etaSeconds, walkMin: walkMin),
        ],
      ),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(SoftBlue.heroRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(SoftBlue.heroRadius),
        onTap: onTap,
        child: card,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Skeletons (spec §4 — "Empty / loading states")
// ═══════════════════════════════════════════════════════════════════════════

/// A pulsing skeleton bar — ink@6%/9% on a white card, never
/// `Color.white.opacity()` on a dark card (that was the greendark recipe).
class SoftSkeletonBar extends StatefulWidget {
  const SoftSkeletonBar({
    super.key,
    this.width,
    this.height = 12,
    this.radius = 6,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<SoftSkeletonBar> createState() => _SoftSkeletonBarState();
}

class _SoftSkeletonBarState extends State<SoftSkeletonBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: SoftBlueMotion.pulse,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: SoftBlue.ink.withValues(alpha: 0.06 + 0.03 * _c.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Skeleton card — a white rounded-rect card on the tinted ground holding
/// skeleton bars mirroring the real component's anatomy. Never a spinner,
/// never a blank screen with just text.
class SoftSkeletonCard extends StatelessWidget {
  const SoftSkeletonCard({
    super.key,
    this.height = 76,
    this.padding = const EdgeInsets.all(16),
  });

  final double height;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: SoftBlue.card,
        borderRadius: BorderRadius.circular(SoftBlue.cardRadius),
        boxShadow: SoftBlue.cardShadow,
      ),
      child: Row(
        children: [
          SoftSkeletonBar(width: 44, height: 44, radius: SoftBlue.iconTileRadius),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                SoftSkeletonBar(width: 140, height: 14),
                SizedBox(height: 8),
                SoftSkeletonBar(width: 90, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
