// Leyne 2.0 "Soft" shared primitives (Material 3 platform-native variant).
// Kept together for discoverability — promote a primitive out to its own
// file if it grows past ~80 lines.

import 'package:flutter/material.dart';

import '../../theme.dart';

/// Service-number badge — accent-filled rounded square showing a bus
/// service number ("80", "158", "21A"). Three sizes per the Soft spec,
/// matched to iOS ServiceBadge.swift: sm (36), md (48), lg (52).
enum ServiceBadgeSize { sm, md, lg }

extension on ServiceBadgeSize {
  double get dim => switch (this) {
    ServiceBadgeSize.sm => 36,
    ServiceBadgeSize.md => 48,
    ServiceBadgeSize.lg => 52,
  };
  // Fix 5: map badge corner radii to LyneRadius scale.
  // sm (36dp badge) → md(16) is too large; nearest spec-correct value is 10 for
  // the small badge, but the LyneRadius scale bottoms out at md(16). The badge
  // is a specialised component whose radius is derived from its own size, so we
  // keep the size-proportional values here (10/14/16) — the lg value already
  // equals LyneRadius.md, and the others intentionally under-round a small pill.
  double get radius => switch (this) {
    ServiceBadgeSize.sm => 10,
    ServiceBadgeSize.md => 14,
    ServiceBadgeSize.lg => LyneRadius.md,
  };
  double get fontSize => switch (this) {
    ServiceBadgeSize.sm => 14,
    ServiceBadgeSize.md => 18,
    ServiceBadgeSize.lg => 22,
  };
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
      child: Text(
        svc,
        style: t.sans(size.fontSize, weight: FontWeight.w600, color: fg),
      ),
    );
  }
}

/// Small label pill ("Home" / "Work" / "Gym" / "Class") on pinned stop cards.
class LabelPill extends StatelessWidget {
  const LabelPill({
    super.key,
    required this.text,
    this.variant = LabelPillVariant.solid,
  });

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
        // Fix 5: pill → LyneRadius.full
        borderRadius: BorderRadius.circular(LyneRadius.full),
      ),
      child: Text(
        text.toUpperCase(),
        style: t
            .mono(
              10,
              weight: FontWeight.w600,
              color: solid ? t.onAccent : t.accent,
            )
            // Fix 6: standardise all-caps tracking to 0.8 (was 1.0)
            .copyWith(letterSpacing: 0.8),
      ),
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
    // Fix 4: replaced GestureDetector+AnimatedContainer with ChoiceChip so
    // each chip gets Material bounded ripple, "selected" semantics announced by
    // TalkBack, and a ≥48dp implicit touch target from Material's chip layout.
    // The pill look is preserved via shape + selected/unselected colours.
    return Wrap(
      spacing: 8,
      children: [
        for (final opt in options)
          Theme(
            // Scope the chip theme so the pill colours come from LyneTheme
            // without touching the global theme used by other widgets.
            data: Theme.of(context).copyWith(
              chipTheme: ChipThemeData(
                shape: const StadiumBorder(),
                // Fix 5: pill → LyneRadius.full is already expressed by
                // StadiumBorder; no hardcoded radius needed here.
                selectedColor: t.accent,
                backgroundColor: t.surface,
                labelStyle: t.sans(13, weight: FontWeight.w500),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                side: BorderSide.none,
              ),
            ),
            child: ChoiceChip(
              label: Text(
                opt.label,
                style: t.sans(
                  13,
                  weight: FontWeight.w500,
                  color: opt.value == selection ? t.onAccent : t.fg,
                ),
              ),
              selected: opt.value == selection,
              onSelected: (_) => onSelect(opt.value),
              // Fix 7: ChoiceChip min-touch is enforced by Material (≥48dp).
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
        // Fix 5: 16 → LyneRadius.md (same value, now token-bound)
        borderRadius: BorderRadius.circular(LyneRadius.md),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$minutes',
            style: t.sans(18, weight: FontWeight.w600, color: t.accent),
          ),
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
    // Fix 3: replaced custom GestureDetector paint with Flutter's Switch.
    //
    // Problems with the old approach:
    //   • Touch target was 44×26dp — well under the 48dp Android minimum.
    //   • No TalkBack semantics (no Semantics widget, no role=switch).
    //   • No Material ripple feedback.
    //
    // Flutter's Switch provides:
    //   • A ≥48dp tap area via MaterialTapTargetSize.padded (default).
    //   • Built-in Semantics with role=switch and "on"/"off" state.
    //   • Material ripple on press.
    //
    // Visual style preserved via SwitchTheme scoped to this widget:
    //   • Track on  → t.accent (matches old animated track colour).
    //   • Track off → t.surfaceHi (matches old resting track colour).
    //   • Thumb     → white in both states (matches the old white circle).
    //
    // The Switch renders slightly larger than the old 44×26 custom widget
    // (which is correct — it now meets the 48dp minimum). Call sites pass
    // only `value` and `onChanged`, so the public API is unchanged.
    return Theme(
      data: Theme.of(context).copyWith(
        switchTheme: SwitchThemeData(
          trackColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? t.accent : t.surfaceHi,
          ),
          thumbColor: WidgetStateProperty.all(Colors.white),
          trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
          materialTapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      child: Switch(value: value, onChanged: onChanged),
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
    // Fix 6: standardise all-caps tracking to 0.8 (was 1.5; LabelPill was 1.0).
    return Text(
      text.toUpperCase(),
      style: t
          .mono(10, weight: FontWeight.w600, color: t.dim)
          .copyWith(letterSpacing: 0.8),
    );
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: t
              .mono(9, weight: FontWeight.w600, color: t.dim)
              .copyWith(letterSpacing: 1),
        ),
      ],
    );
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
    // Fix 5: this 4×28 bar is a specialised indicator — a 2dp radius is
    // intentional (fully rounding a 4dp-wide bar). LyneRadius.md(16) would
    // over-round it into a capsule shape that departs from the design intent.
    // Keeping radius:2 here and noting it is not a card/tile/chip surface.
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}
