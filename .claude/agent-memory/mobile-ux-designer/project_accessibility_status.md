---
name: project-accessibility-status
description: Accessibility state of Leyne's V2 UI — Dynamic Type, VoiceOver, contrast, tap targets
metadata:
  type: project
---

As of 2026-05-29 review, the V2 SwiftUI suite has effectively NO accessibility work:
- Zero `accessibilityLabel/Hint/Value/AddTraits` across all `V2/*.swift` (grep clean).
- No Dynamic Type: `Theme.sans/.mono` use fixed `.system(size:)` with no `relativeTo:` text style and no `@ScaledMetric`. Text will not scale with the user's content-size setting → fails iOS HIG + accessibility expectation. This is the single highest-impact a11y fix.
- Icon-only / glyph-only controls (the Home "+" button = `Image("plus")`, walk tiles, sort chips, map markers, the `xmark.circle.fill` clear button) have no VoiceOver labels.
- Custom `SoftToggle` has no switch trait/value for VoiceOver.
- Several tap targets < 44pt (RouteTimeline rows, chips ~28pt).
- Color-only signals: bus load (sea/sda/lsd) is a colored dot + a tiny mono word — word saves it, but ETA "now" relies on accent color alone in some rows.
- Contrast risk: `t.dim` = fg at 0.6 opacity and `t.faint` at 0.35 on warm bg; small mono captions at 9–11pt in `faint` likely fail WCAG AA for body text.

No explicit accessibility commitment found in specs yet — TBD with user.

**Why:** Accessibility is non-negotiable per operating principles; this is the project's biggest systemic gap and adopting native components (List/Toggle/.searchable) fixes much of it for free.
**How to apply:** Lead a11y recommendations with Dynamic Type (switch `Theme.sans` to `.system(_, weight:)` via `Font.system(size:weight:).` won't scale — use `relativeTo:` or map to text styles). Always re-verify with a grep before claiming "still no a11y" — may have changed.
