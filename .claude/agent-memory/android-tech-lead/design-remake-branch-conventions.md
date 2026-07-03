---
name: design-remake-branch-conventions
description: Working conventions for the design-remake branch's Android Material screens (lib/screens/v2/) — iOS reference, type-scale floor, multi-agent file ownership
metadata:
  type: project
---

On branch `design-remake`, Android's Material-idiom "Soft" screens
(`lib/screens/v2/soft_*.dart`, `lib/widgets/v2/`) are being brought to visual
parity with iOS's WhereSia redesign (`ios-native/Leyne/WhereSia/`), NOT with
the old plain-V2 screens and NOT monochrome — the `port-ios-feature` skill's
"stay monochrome" rule is stale for this branch; current Android styling is
the existing soft_*.dart Material You idiom (dynamic colour, see
[[material-you-implementation]]). WhereSia (`WSHomeView.swift`, `WSTheme.swift`,
`WSComponents.swift`, `WSFormat.swift`) is the design spec to mirror.

**Type-scale floor (owner directive, 2026-07-03):** when aligning an Android
font size to its iOS point value, never render body/meta text below 11pt on
Android even if the iOS source uses less (WSHomeView has several 9.5/10/10.5pt
elements — e.g. `WSLiveBadge` at 9.5, `whenColumn`'s secondary line at 10,
`MrtCard`'s subline at 10.5). Match iOS 1:1 (Flutter logical px ≈ iOS pt) for
anything ≥11pt; floor anything below that up to exactly 11. This came up
auditing `soft_home_screen.dart` against `WSHomeView.swift` and is likely to
recur on other screens ported from WhereSia.

**`LyneTheme.sans()` (theme.dart) gained an optional `tabularFigures` bool**
(2026-07-03) — `mono()` was always tabular, `sans()` wasn't. Pass
`tabularFigures: true` wherever a NUMERAL (not a word) is set in the sans
face, e.g. a service-number badge — `ServiceBadge` in `soft_components.dart`
still doesn't do this (flagged, not fixed — owned by a different file/agent).

**Multi-agent file ownership on this branch:** the owner runs punch-list work
as parallel agents, each scoped to a named section/file (e.g. "Section A —
Home view, own soft_home_screen.dart + theme.dart only"). Agents must NOT edit
`lib/screens/v2/*.dart` or `lib/widgets/v2/*.dart` files outside their own
scope even when the audit surfaces a real bug there — list it in the report
instead. Coordinator messages can arrive mid-task relaying findings from a
concurrently-running sibling agent (e.g. an icon-convention audit from a
"Section B" agent) — treat those as in-scope work items for whatever's inside
your own file, not as license to touch other agents' files.

See also [[icon-glyph-bookmark-vs-star]], [[redesign_main_view]] (user-level
memory, different redesign track — don't conflate the two).
