// Shared primitives for the redesign screens: a Material Symbols icon wrapper
// (variable fill/weight), occupancy → icon/label/colour resolution, and a few
// small reused chip/circle-button builders.

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'redesign_data.dart';
import 'redesign_theme.dart';

/// Wraps a tappable child in a Material ink surface so it shows the M3 ripple /
/// state layer. Use on the flat grouped-list rows (which sit on a transparent
/// surface) — the redesign was built with bare GestureDetectors and had no
/// ripple feedback anywhere, the most un-Material thing about it.
Widget rdInk({
  required VoidCallback? onTap,
  required Widget child,
  BorderRadius? borderRadius,
}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(onTap: onTap, borderRadius: borderRadius, child: child),
  );
}

/// Material Symbols Rounded icon with the variable-font axes the design uses.
class RdIcon extends StatelessWidget {
  const RdIcon(
    this.icon, {
    super.key,
    required this.size,
    required this.color,
    this.fill = 0,
    this.weight = 400,
  });

  final IconData icon;
  final double size;
  final Color color;
  final double fill; // 0 = outline, 1 = filled
  final double weight;

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon,
      size: size,
      color: color,
      fill: fill,
      weight: weight,
      opticalSize: size,
    );
  }
}

/// Occupancy resolved for the arrival rows: (icon, label, colour).
({IconData icon, String label, Color color}) rdOcc(RdLoad load, RdTokens t) {
  switch (load) {
    case RdLoad.seats:
      return (icon: Symbols.airline_seat_recline_normal, label: 'Seats available', color: t.bus);
    case RdLoad.standing:
      return (icon: Symbols.accessibility_new, label: 'Standing room', color: t.amber);
    case RdLoad.packed:
      return (icon: Symbols.groups, label: 'Packed', color: t.mrt);
  }
}

/// Crowd dot colour for the bus / amber / mrt roles.
Color rdLoadColor(RdLoad load, RdTokens t) => switch (load) {
      RdLoad.seats => t.bus,
      RdLoad.standing => t.amber,
      RdLoad.packed => t.mrt,
    };

/// 8px circular dot used throughout (crowd / live indicators).
class RdDot extends StatelessWidget {
  const RdDot(this.color, {super.key, this.size = 7});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Circular outline icon button used in detail-screen headers.
class RdCircleButton extends StatelessWidget {
  const RdCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.label,
    this.bordered = true,
    this.iconColor,
    this.bg,
    this.fill = 0,
    this.size = 42,
    this.iconSize = 21,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? label; // TalkBack label for this icon-only control
  final bool bordered;
  final Color? iconColor;
  final Color? bg;
  final double fill;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final t = RdTheme.of(context);
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: bg ?? Colors.transparent,
        shape: bordered
            ? CircleBorder(side: BorderSide(color: t.outlineVariant))
            : const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkResponse(
          onTap: onTap,
          radius: size / 2 + 4,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: RdIcon(icon, size: iconSize, color: iconColor ?? t.onSurface, fill: fill),
            ),
          ),
        ),
      ),
    );
  }
}

/// Standard detail-screen top bar padding (status bar handled by SafeArea).
const EdgeInsets kRdHeaderPad = EdgeInsets.fromLTRB(10, 6, 10, 0);
