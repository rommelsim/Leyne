# Designing a More Minimal, Serious, and Sunlight-Legible Singapore Bus-Arrival App

## TL;DR
- **Go monochrome-plus-one, encode status by luminance not hue, and cut ornament — that is what makes transit design read as "serious" while staying glanceable.** The world's most authoritative transit systems (NYC subway, London Underground, Charles de Gaulle) achieve authority through a single neutral sans-serif on a strict grid, ruthless color restraint, and generous whitespace — never decoration.
- **For rushing commuters in tropical sunlight, luminance contrast beats color every time.** Peripheral and glance vision is driven by the luminance-sensitive magnocellular pathway; red-green discrimination collapses first both in the periphery and for the ~8% of men with color-vision deficiency, and sunlight glare desaturates all hues toward gray. Status must therefore be carried by lightness difference + shape/icon/position + short text, with color as reinforcement only.
- **Keep the LTA green/amber/red load convention (commuters already know it) but make it redundant and luminance-separated, reserve exactly one high-visibility accent for imminent arrivals, and treat MRT line colors as a locked vocabulary you never reuse for status.**

## Key Findings

**1. "Serious" transit design = neutrality + restraint + grid discipline.** Massimo Vignelli's NYC subway system standardized everything on Helvetica Medium set on a fixed tile grid with color bands reserved solely for line identification. London's Johnston (1916, Johnston100 since 2016) was briefed for "bold simplicity," intended to be understated, quotidian, part of the consistent background rather than a changing foreground. The Swiss/International Typographic Style is defined by cleanliness, readability, objectivity: a mathematical grid, neutral sans-serif type, asymmetric-but-balanced composition, active whitespace, and restricted color for maximum impact. Authority comes from what is removed, not added.

**2. Dieter Rams codified "functional color."** Across Braun products, Rams treated color as a functional language: neutral tones established the ground, and a rare accent (the red power button, the yellow indicator) carried the full weight of operational communication precisely because color appeared nowhere else. Teenage Engineering pushes the same idea to five colors total, where orange — borrowed from industrial safety equipment — signals "engineered and important." A near-achromatic base makes one functional accent unmistakable.

**3. Typography for numbers at a glance: humanist sans, high x-height, tabular figures, weight for hierarchy.** Frutiger was purpose-built for Charles de Gaulle so travelers rushing through corridors could read signs at a glance, at any distance, from any angle, at speed, using open apertures, a high x-height, prominent ascenders. For the ETA numbers, tabular (monospaced) figures are essential: every digit identical width so the number doesn't jitter as it counts down. Inter (current typeface) supports tabular figures via `font-variant-numeric: tabular-nums` and is an appropriate neutral high-x-height choice — no change of typeface required, only disciplined use.

**4. Contrast standards: meet WCAG AA as a floor, tune with APCA, exceed for the hero number.** WCAG 2 requires 4.5:1 normal text, 3:1 large text (≥24px, or 14pt bold) and UI components/icons; AAA raises these to 7:1 and 4.5:1. WCAG 2's ratio is luminance-only and overstates contrast for dark colors, so it can't give reliable dark-mode guidance. APCA (candidate for WCAG 3) outputs a perceptually-uniform lightness-contrast value (Lc) and is polarity-aware; target roughly Lc 75–90 for the hero ETA and small labels. For the hero number aim beyond AA — treat 7:1+ (AAA) as target given outdoor use.

**5. Sunlight physics forces high-luminance design.** Glare adds reflected white light that raises the black level and desaturates hues toward gray. Photopic sensitivity peaks at 555 nm (green) per CIE V(λ); high-luminance amber/yellow and yellow-green retain the most apparent brightness when glare washes out the screen — also why safety apparel (ANSI/ISEA 107) uses fluorescent yellow-green as most conspicuous in daylight and peripheral vision. Sunlight-readable displays need ~1,000+ nits; assume effective contrast may fall to ~2:1 outdoors. Use large elements, light fills with dark text (light fills survive glare better than dark), and never depend on saturation differences.

**6. Peripheral/glance vision is a luminance channel.** ~120 million rods vs ~6 million cones; peripheral/fast input runs via the magnocellular (luminance, motion) pathway. Red-green discrimination declines steeply toward the periphery (Hansen, Pracejus & Gegenfurtner, Journal of Vision, 2009) and drops out ~25–30° eccentricity; blue-yellow degrades much less. Enlarging elements partly compensates for peripheral color loss — large status elements are doubly justified. Avoid pure saturated blue for small text/icons (few S-cones, none in fovea → lower resolution).

**7. Redundant encoding is the consensus rule for status color.** WCAG 2.2 SC 1.4.1 (Level A): color must not be the only means of conveying information. Red-green deficiency is ~8% of men (European), 4–6.5% of men of Chinese/Japanese ethnicity (Birch 2012) — directly relevant to Singapore. Bang Wong's Okabe-Ito palette (Nature Methods, 2011) uses colors with distinct luminance so it works in grayscale, and recommends avoiding red-green in favor of blue-orange. ISO 3864-1 locks each safety color to a distinct shape and requires luminance contrast. Blue+orange is the most universally distinguishable status pair across all CVD types.

**8. The 2-second glance budget caps information density.** NHTSA driver-distraction guidelines hold individual glances ≤2.0s; glances totaling >2s roughly double crash risk (Klauer et al., 2006, VTTI 100-Car Study). A commuter walking and glancing gets effectively one ≤2-second glance: present one primary status per glance, ~3–4 clearly luminance-separated states maximum, at large size.

**9. Singapore-specific vocabulary the design must respect.** LTA DataMall Bus Arrival encodes crowding as three states — SEA (Seats Available), SDA (Standing Available), LSD (Limited Standing) — mapping to the green/amber/red convention commuters know from SMRT platform crowd lights. The six MRT lines have fixed identity colors (NS red, EW green, NE purple, CC orange, DT blue, TE brown). These are a reserved wayfinding vocabulary; reusing MRT green/red/orange for app status risks semantic collision.

## Recommendations

**Stage 1 — Restructure the foundation:**
1. Rebuild both themes on a disciplined neutral gray ramp; remove decorative color. Dark theme uses elevated dark-gray surfaces + off-white text, not pure black/white.
2. Enforce `tabular-nums` everywhere; lock type to one family / 2–3 weights on a strict grid.
3. Flatten cards to whitespace + hairlines; delete gradients/shadows.

**Stage 2 — Rework color for glanceability:**
4. Reserve one high-luminance lime/spring-green accent exclusively for imminent arrivals; use it nowhere else.
5. Re-encode SEA/SDA/LSD with luminance separation + distinct icons + bar length + optional text. Keep traffic-light hues for familiarity but verify they differ in grayscale.
6. Audit every status/accent pair in an APCA checker for both themes; hero number ≥ Lc ~75–90.

**Stage 3 — Validate under real conditions:**
7. Test outdoors in direct midday sun on mid-range and flagship phones; if states aren't distinguishable at arm's length in ~1s, increase size and luminance gap before touching hue.
8. Test with a color-blindness simulator (protanopia/deuteranopia) — the pinned-stop view must remain fully legible in grayscale.

**Benchmarks that would change the plan:**
- If sunlight testing shows the lime accent washing out, shift toward high-luminance amber/orange (still off the red-green axis).
- If users confuse status states in grayscale, move the extreme states to a blue-orange axis rather than red-green.
- If the hero number fails APCA ~Lc 75 in dark mode, raise its lightness/weight before enlarging further.

## What to Remove or Simplify
- Gradients, drop shadows, heavy card chrome → whitespace + hairline dividers or subtle tonal blocks.
- Any illustration, mascot, or "friendly" flourish (the SBB/Citymapper register).
- Redundant color: every remaining hue should be functional (line identity, one accent, three status states).
- Excess weights/typefaces → one family, 2–3 weights.
- Anything not readable in a single 2-second glance on the pinned-stop view; push secondary detail behind a tap.

## Caveats
- Nits thresholds/washout figures come from tech-press roundups and a single patent measurement, not peer-reviewed studies — treat exact numbers as guidance.
- No published figure binds "N colors per 2-second glance"; the ~3–4-state ceiling is synthesized, not one cited law.
- APCA is still a WCAG 3 candidate; use WCAG 2.2 AA as the compliance floor and APCA as a tuning tool for dark mode.
- NHTSA glance research is about drivers, not walking commuters; transfers as a conservative analogy.
- MRT line colors and SMRT crowd-light conventions are Singapore-specific and may evolve; keep app status hues distinct from line-identity hues.
- The reserved-accent strategy depends on discipline: the moment the "go" accent appears elsewhere, it loses its instant-signal value.
