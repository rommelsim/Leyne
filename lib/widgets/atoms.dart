// Shared atomic widgets used across all screens — service-number chip,
// mono-uppercase pill, mono-uppercase micro label.

import 'package:flutter/material.dart';
import '../theme.dart';

enum ChipSize { sm, md, lg }

/// Coloured rounded-rect with a service number in mono. The defining visual
/// element of the redesigned UI — used on every screen.
class BusChip extends StatelessWidget {
  const BusChip({super.key, required this.no, this.color, this.size = ChipSize.md});

  final String no;
  final Color? color;
  final ChipSize size;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final bg = color ?? t.accent;
    final ({double w, double h, double fs, double r}) m = switch (size) {
      ChipSize.sm => (w: 42, h: 28, fs: 13, r: 7),
      ChipSize.md => (w: 56, h: 40, fs: 17, r: 9),
      ChipSize.lg => (w: 72, h: 52, fs: 22, r: 11),
    };
    return Container(
      width: m.w,
      height: m.h,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(m.r),
      ),
      child: Text(
        no,
        style: t.mono(m.fs, weight: FontWeight.w600, color: t.contrastFg),
      ),
    );
  }
}

/// Tiny mono-uppercase status pill. Defaults to a 13% tint of `color` for the
/// background, matching the design's `${color}22` recipe.
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.color, this.background});

  final String label;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final fg = color ?? t.accent;
    final bg = background ?? fg.withValues(alpha: 0.13);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: t.mono(10, weight: FontWeight.w600, color: fg).copyWith(letterSpacing: 0.6),
      ),
    );
  }
}

/// Mono uppercase 11pt section label, used as a kicker above content blocks.
class MicroLabel extends StatelessWidget {
  const MicroLabel(this.label, {super.key, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Text(
      label.toUpperCase(),
      style: t.mono(11, color: color ?? t.dim).copyWith(letterSpacing: 1.1),
    );
  }
}
