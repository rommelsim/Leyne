// Leyne 2.0 "Soft" shared primitives (Material 3 platform-native variant).
// Kept together for discoverability — promote a primitive out to its own
// file if it grows past ~80 lines.

import 'package:flutter/material.dart';

import '../../theme.dart';

/// Service-number badge — accent-filled rounded square showing a bus
/// service number ("80", "158", "21A"). Three sizes per the Soft spec:
/// sm (40), md (48), lg (56).
enum ServiceBadgeSize { sm, md, lg }

extension on ServiceBadgeSize {
  double get dim => switch (this) { ServiceBadgeSize.sm => 40, ServiceBadgeSize.md => 48, ServiceBadgeSize.lg => 56 };
  double get radius => switch (this) { ServiceBadgeSize.sm => 12, ServiceBadgeSize.md => 16, ServiceBadgeSize.lg => 18 };
  double get fontSize => switch (this) { ServiceBadgeSize.sm => 14, ServiceBadgeSize.md => 18, ServiceBadgeSize.lg => 22 };
}

class ServiceBadge extends StatelessWidget {
  const ServiceBadge({
    super.key,
    required this.svc,
    this.size = ServiceBadgeSize.md,
    this.inverted = false,
  });

  final String svc;
  final ServiceBadgeSize size;
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final fill = inverted ? t.surface : t.accent;
    final fg = inverted ? t.accent : t.onAccent;
    return Container(
      constraints: BoxConstraints(minWidth: size.dim, minHeight: size.dim),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(size.radius),
      ),
      child: Text(svc,
          style: t.sans(size.fontSize, weight: FontWeight.w600, color: fg)),
    );
  }
}

/// Small label pill ("Home" / "Work" / "Gym" / "Class") on pinned stop cards.
class LabelPill extends StatelessWidget {
  const LabelPill({super.key, required this.text, this.variant = LabelPillVariant.solid});

  final String text;
  final LabelPillVariant variant;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final solid = variant == LabelPillVariant.solid;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: solid ? t.accent : t.liveBg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(text.toUpperCase(),
          style: t.mono(10, weight: FontWeight.w600,
              color: solid ? t.onAccent : t.accent)
            .copyWith(letterSpacing: 1.0)),
    );
  }
}

enum LabelPillVariant { solid, tinted }

/// Single-selection pill chip row used on Nearby / Search.
class SortChipRow<V> extends StatelessWidget {
  const SortChipRow({
    super.key,
    required this.selection,
    required this.options,
    required this.onSelect,
  });

  final V selection;
  final List<({V value, String label})> options;
  final ValueChanged<V> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Wrap(
      spacing: 8,
      children: [
        for (final opt in options)
          GestureDetector(
            onTap: () => onSelect(opt.value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: opt.value == selection ? t.accent : t.surface,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(opt.label,
                  style: t.sans(13, weight: FontWeight.w500,
                      color: opt.value == selection ? t.onAccent : t.fg)),
            ),
          ),
      ],
    );
  }
}

/// Walk-time tile — leading element on Nearby rows.
class WalkTile extends StatelessWidget {
  const WalkTile({super.key, required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.liveBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$minutes',
              style: t.sans(18, weight: FontWeight.w600, color: t.accent)),
          Text('min', style: t.mono(9, color: t.dim)),
        ],
      ),
    );
  }
}

/// Soft toggle switch — track flips to accent when on.
class SoftToggle extends StatelessWidget {
  const SoftToggle({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 44,
        height: 26,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: value ? t.accent : t.surfaceHi,
          borderRadius: BorderRadius.circular(99),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 2,
                    offset: const Offset(0, 1)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Eyebrow caption (mono, all caps, tracked) above page titles.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Text(text.toUpperCase(),
        style: t.mono(10, weight: FontWeight.w600, color: t.dim)
            .copyWith(letterSpacing: 1.5));
  }
}

/// Map legend dot ("● BUS 80   ● STOP   ● ME").
class LegendDot extends StatelessWidget {
  const LegendDot({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: t.mono(9, weight: FontWeight.w600, color: t.dim).copyWith(letterSpacing: 1)),
    ]);
  }
}

/// Vertical MRT-line bar (coloured 4×28) leading an alert card.
class MRTLineBar extends StatelessWidget {
  const MRTLineBar({super.key, required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 4,
        height: 28,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
      );
}
