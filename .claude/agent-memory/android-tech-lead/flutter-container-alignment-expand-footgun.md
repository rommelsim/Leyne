---
name: flutter-container-alignment-expand-footgun
description: Container(alignment:) with no explicit width expands to fill loose-bounded incoming constraints — inside a Wrap this stretches tile/chip children to full row width, one per line; wrap in IntrinsicWidth
metadata:
  type: project
---

A `Container` that sets `alignment:` but no explicit `width`/`height` does NOT
shrink-wrap its child the way you'd expect — Flutter builds it as an internal
`Align`, and `Align` expands to fill the largest size its incoming
constraints allow whenever those constraints are bounded (finite max). Inside
a `Wrap` (`direction: Axis.horizontal`, the default), each child is given
`BoxConstraints(maxWidth: <wrap's own available width>)` — bounded, not
unbounded — so a chip/tile `Container(alignment: Alignment.center, ...)`
silently expands to the **full available row width** instead of hugging its
label. Visually this reads as every "chip" becoming a full-width pill and the
`Wrap` degenerating into a vertical one-per-line stack, which looks
identical to "someone used a Column instead of a Wrap" even though the code
is correctly using `Wrap`.

**Fix:** wrap the `Container` in `IntrinsicWidth` so it reports its child's
natural width upward instead of accepting the full bounded width. `minWidth`
constraints on the `Container` still work as a floor for very short labels
(e.g. single-digit bus numbers), so pills stay square/centred.

**Where this has already bitten:**
- `lib/screens/v2/soft_home_screen.dart` `_RouteChipsRow._tile()` /
  `_overflowTile()` — fixed 2026-07-03, has the full explanatory NOTE comment
  inline (search "no `alignment:` on these Containers").
- `lib/screens/v2/soft_favourites_screen.dart` `_ServiceChipRow._tile()` —
  same bug, found and fixed 2026-07-03 during a Saved-screen parity pass
  (owner reported "route chips stacked vertically" on the Holland Village
  saved-stop card). This one was a plain copy of the pre-fix pattern that
  hadn't picked up Home's fix.

**How to apply:** any future `soft_*.dart` screen (Alerts, MRT, Search, Bus,
Stop) that renders a horizontal row of bordered/pill tiles via `Wrap` should
be checked for this exact pattern — grep for `alignment: Alignment.center`
inside a `Container` that sits directly under a `Wrap`. If found without an
`IntrinsicWidth` wrapper, it's this bug. See also
[[design-remake-branch-conventions]] for the broader multi-agent/parity
context this keeps coming up in.
