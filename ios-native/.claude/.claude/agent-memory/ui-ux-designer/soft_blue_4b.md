---
name: soft-blue-4b
description: Soft Blue "4b" design language for WhereSia (Departly iOS) — tokens, rules, full spec location
metadata:
  type: project
---

Owner picked a new design direction 2026-07 (post-greendark): "Soft Blue 4b", from a pastel health-app reference image (tinted pale-blue ground, floating white cards, ONE saturated blue gradient hero card per screen with a countdown ring, pill chips, mini tiles). Source ref image: `~/Desktop/abb62bf0af6789d69183b638f2ad058b.webp`.

**Why:** owner wants a warmer, lighter, less "control-panel" feel than the greendark mint system for at least some WhereSia screens; only Nearby (`WSHomeView.swift` `softBody`) is implemented so far, sitting alongside the still-live greendark `darkBody` for quick revert.

**How to apply:** tokens live in `WSSoftTheme.swift` (`SoftBlue` enum + `softCard`/`SoftSectionHead`/`SoftIconButton` helpers). Ground truth component patterns (hero+ring, stop row, MRT tile, chips) are in `WSHomeView.swift`'s soft* views. I wrote a full prescriptive spec (palette, type scale, shape/elevation, component inventory, semantic porting rules for crowd dots/disruption glow/armed-alert badge, dark-twin token guidance, anti-rules) to `/private/tmp/.../scratchpad/study-design-spec.md` during that session — treat that content as the reference to re-derive from if asked to extend 4b to another screen, since the scratchpad file itself won't persist. Key irreversible rules: mint is fully banned in 4b, blue is the ONE accent, only one gradient hero per screen, no glows/dot-pulses (crowd/disruption become text+tinted chips instead), no rings outside the hero.

See also [[feedback_platform_design]] (platform-native rule, unaffected — this is still iOS-only work) and [[greendark_redesign]] equivalent note if present — 4b is positioned as greendark's successor for screens it's ported to, not a parallel permanent system.
