---
name: project-widget-soft-spec
description: Definitive V2 Soft token mapping and design spec for LeyneStopWidget and LeyneLiveActivity, produced 2026-05-29
metadata:
  type: project
---

Produced as a concrete implementation-ready spec to align WidgetKit surfaces with Theme.swift Soft tokens.

## Why it exists
Both widget files carry inline palettes (`wBg`/`wFg`/… in StopWidget; `ink`/`paper`/`green`/`dim` in LiveActivity) whose hex values belong to the OLD pre-Soft palette. The widget extension cannot import the app module, so tokens must be duplicated inline. This spec is the canonical mapping from old inline hex → Soft hex.

## Corrected token values

### StopWidget palette (light / dark hex, no alpha)

| Token   | Old light hex | New light hex | Theme.swift source    | Old dark hex | New dark hex | Theme.swift source    |
|---------|--------------|---------------|-----------------------|--------------|--------------|----------------------|
| wBg     | F7F4ED       | F4EFE7        | bg (light)            | 0E0E0A       | 15201C       | bg (dark)            |
| wFg     | 171612       | 1A201D        | fg (light)            | ECE9E0       | F1EDE7       | fg (dark)            |
| wDim    | 6D6859 @1.0  | 1A201D @0.60  | dim (light)           | ECE9E0 @0.52 | F1EDE7 @0.60 | dim (dark) — NOTE: raise alpha to 0.60 from 0.52 for widget legibility |
| wFaint  | A8A192 @1.0  | 1A201D @0.45  | faint (light) — NOTE: raise from Theme's 0.35 to 0.45 for widget context | ECE9E0 @0.32 | F1EDE7 @0.45 | faint (dark) — raise from 0.35 to 0.45 |
| wLine   | E5E0D2 @1.0  | 1A201D @0.10  | line (light)          | FFFFFF @0.07 | F1EDE7 @0.08 | line (dark)          |
| wLive   | 2BAA67       | 2D7A5A        | accent/live (light)   | 5EE597       | 8EE6C0       | accent/live (dark)   |
| wLiveBg | E3F5EA @1.0  | E8F5EE        | liveBg (light)        | 5EE597 @0.14 | 0F2A20       | liveBg (dark)        |

### LiveActivity palette (light / dark hex)

| Token  | Old dark hex  | New dark hex | Theme.swift source | Old light hex | New light hex | Theme.swift source |
|--------|--------------|--------------|-------------------|---------------|---------------|--------------------|
| ink    | 0E0E0A (dark bg)  | 15201C   | bg (dark)         | F7F4ED (light bg) | F4EFE7   | bg (light)         |
| paper  | ECE9E0 (dark fg)  | F1EDE7   | fg (dark)         | 171612 (light fg) | 1A201D   | fg (light)         |
| green  | 5EE597 (dark)     | 8EE6C0   | accent/live (dark)| 2BAA67 (light)    | 2D7A5A   | accent/live (light)|
| dim    | ECE9E0 @0.52 (dark) | F1EDE7 @0.60 | dim (dark) — raise alpha for LA legibility | 6D6859 @1.0 (light) | 1A201D @0.60 | dim (light) |

## wDim/wFaint alpha adjustment rationale
Theme.dark.dim uses F1EDE7 @0.60. Theme.dark.faint uses F1EDE7 @0.35. For widget surfaces (tiny canvas, unpredictable wallpaper bleeds through, no scroll context) raise faint to @0.45. Do NOT go lower — the 9pt captions using wFaint/faint already fail WCAG AA at 0.35.

## widgetAccentable tinting behavior
- wLive / green: MUST be `.widgetAccentable`. In StandBy yellow/monochrome and Lock Screen tinting modes, this maps to the system accent, which correctly highlights the "arriving" state. If NOT marked, the arriving pill and ETA numerals lose their semantic meaning in monochrome modes.
- wLiveBg row wash background: do NOT mark `.widgetAccentable` — the full-row fill should remain neutral/clear in tinted modes; only the foreground accent elements should tint.
- wBg / ink (widget background): NOT `.widgetAccentable`. It passes through `.containerBackground` which WidgetKit manages separately.
- wFg / paper (primary text): NOT `.widgetAccentable` — must stay readable as content foreground.
- bookmark.fill glyph in Medium/Large header: SHOULD be `.widgetAccentable` — it is a semantic "pinned" indicator and its tinting to the system accent is appropriate and desirable.
- Dynamic Island keylineTint(green): update to new Soft green (8EE6C0 dark / 2D7A5A light). This is already correct usage.

## Typography corrections

### StopWidget
- Stop name header: 12pt semibold sans — correct family but consider raising to 13pt for systemSmall legibility. Keep sans (not mono) — it is a label, not a number.
- Hero bus number (Small): 24pt bold mono — on target, keep.
- Hero ETA numeral (Small): 40pt medium mono (or 30pt for "Arr") — correct size. Good.
- "then Xm" secondary ETA (Small): 10pt mono — acceptable at widget scale; this is the minimum, do not go lower.
- "+N" chip text: 10pt medium mono — correct. The Capsule stroke using wLine is the right Soft idiom for a tertiary chip.
- WServiceRow bus number: 16pt bold mono — correct.
- WServiceRow ETA numeral: 22pt medium mono (or 17pt for "Arr") — correct.
- WServiceRow "then Xm": 9pt mono — this is below readable widget minimum. Raise to 10pt.
- Medium/Large stop name header: 14pt/13pt semibold sans — correct. The size differential between Medium (14) and Large (13) is intentional and appropriate given Large has two chunks.
- "No live arrivals" empty string: 12pt/11pt sans dim — acceptable.

### LiveActivity — Lock Screen view
- Bus number badge: 16pt bold mono on green fill — correct.
- Destination arrow line: 10pt mono dim uppercased — the uppercase + mono pairing is the correct Soft "eyebrow" idiom.
- Status text: 16–20pt semibold sans — correct.
- Stop name / stops-away caption: 11pt sans dim — acceptable minimum; do not reduce.
- ETA numeral: 40pt light mono / 22pt for arrived — this is intentionally large for glanceability. Keep weight as .light (correct, distinct from the .medium ETA in the widget).
- "min" label: 11pt mono dim — correct.

### LiveActivity — Dynamic Island expanded
- Bus number badge: 16pt bold mono — correct.
- ETA numeral: 22pt semibold mono — correct for compact expanded region.
- Destination: 12pt medium sans — correct.
- Bottom metadata: 9.5pt mono dim — minimum acceptable; do not reduce. This is the DI expanded bottom region where space is constrained.
- Compact/minimal bus number: 13pt/11pt bold mono — correct.

## Corner radius corrections
- WServiceRow arriving background: currently 6pt RoundedRectangle. Soft system uses continuous style. Change to `RoundedRectangle(cornerRadius: 6, style: .continuous)`.
- LiveActivity Lock Screen bus number badge: currently 12pt. Soft card language uses 16–22pt but the badge is a small inline chip (~46×46pt). Keep at 12pt — it matches the Soft chip radius (not the card radius) and is appropriate for a pill-badge. However add `style: .continuous`.
- Dynamic Island expanded bus number badge: currently 8pt RoundedRectangle. Add `style: .continuous`.

## Per-surface concrete tweaks

### systemSmall
1. wBg update is the highest-impact single line change — the old 0E0E0A dark background has a blue-black cast vs the Soft warm #15201C.
2. The arriving color (wLive) change from 5EE597 to 8EE6C0 is a subtle warmth correction that aligns with the mint-teal direction of V2.
3. Mark the ETA `Text` foreground `.widgetAccentable` when `arriving == true` so StandBy mode preserves the semantic highlight.
4. The "+N" chip: the Capsule stroke uses wLine (a hairline). This is correct Soft idiom — no change needed beyond the token value update.

### systemMedium
1. `bookmark.fill` header glyph: add `.widgetAccentable` modifier so it receives the system accent tint on Lock Screen / StandBy. Currently it uses wLive foreground which is correct for normal rendering but will be stripped in monochrome.
2. The hairline `Rectangle().fill(wLine)` divider: purely an opacity token correction — update to 1A201D@0.10 light / F1EDE7@0.08 dark. Visual delta is minimal but correct.
3. WServiceRow `wLiveBg` row wash: in dark mode, old value was 5EE597@0.14 (a green-tinted alpha), new value is the solid #0F2A20 from Theme.dark.liveBg. This is a meaningful warmth correction — the new value reads as a deep forest-green wash vs the prior floaty translucent green. Implementer note: the `dyn()` helper approach is retained; just swap the UIColor values.

### systemLarge
1. Same token corrections as Medium apply to both StopChunk headers.
2. The inter-chunk divider `Rectangle().fill(wLine)` — same hairline correction as Medium.
3. Large with single stop (secondary == nil) shows up to 5 rows via `maxRows: 5`. WServiceRow secondary ETA "then Xm" is 9pt here — raise to 10pt per typography note above.

### Live Activity — Lock Screen
1. `activityBackgroundTint(ink)` — ink is the dark-mode bg. This is intentional (LA always renders on dark Lock Screen). Token value correction: 0E0E0A → 15201C. The visual change is subtle (warmer black vs cool black) but correct for Soft language consistency.
2. `activitySystemActionForegroundColor(paper)` — paper is the fg. Correction: ECE9E0 → F1EDE7.
3. Bus number badge: add `style: .continuous` to RoundedRectangle(cornerRadius: 12).
4. The `→` arrow in the destination line is a Unicode character, not an SF Symbol. Consider replacing with `Image(systemName: "arrow.right")` + `.foregroundStyle(dim)` for proper optical weight alignment with the 10pt mono text, but this is polish-tier, not a blocking fix.
5. Arrived ETA size jump (40pt → 22pt) creates a content transition. Consider pairing with `.contentTransition(.numericText())` for polish, already done in StopWidget — bring parity.

### Live Activity — Dynamic Island
1. `keylineTint(green)` — update to new Soft green values.
2. Bus number badge in leading region: add `style: .continuous`.
3. No structural changes needed — the DI layout is compact and correct.

## Priority ranking

### P0 — Must fix (palette drift is live in production)
1. All 7 wBg/wFg/wDim/wFaint/wLine/wLive/wLiveBg token values in LeyneStopWidget.swift
2. All 4 ink/paper/green/dim token values in LeyneLiveActivity.swift
3. wDim and wFaint alpha raise (0.52→0.60 dim, 0.32→0.45 faint) in both files — legibility safety net

### P1 — High value, low risk (one-liners each)
4. `.widgetAccentable` on wLive/green foreground uses (ETA arriving text, mint pill, bookmark.fill glyph)
5. WServiceRow "then Xm": 9pt → 10pt in LargeCommuteView
6. `style: .continuous` on all RoundedRectangle badge/row backgrounds in both files

### P2 — Polish (do after P0/P1 ship)
7. LA Lock Screen: `.contentTransition(.numericText())` on ETA numeral for arrived transition
8. LA Lock Screen: `→` Unicode → `Image(systemName: "arrow.right")`
9. Stop name header in Small: 12pt → 13pt (legibility micro-nudge)

**Why:** [[project-leyne-design-system]]
