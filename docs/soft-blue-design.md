# Soft Blue "4b" — Design Language Spec

Canonical tokens: `WSSoftTheme.swift` (`SoftBlue` enum). Ground truth screen: `WSHomeView.swift` `softBody`. This spec extends both to the rest of WhereSia. Supersedes `WSTheme.swift` (greendark) wherever a screen is ported — do not mix the two systems on one screen.

## 1. Palette

| Token | Hex | Role |
|---|---|---|
| `bg` | `#DCE9F4` | Page ground (tinted pale blue), always visible between cards |
| `card` | `#FFFFFF` | Floating surfaces — the only other large fill besides the hero |
| `ink` | `#1B2430` | Primary text on white/ground |
| `sub` | `#7A8794` | Secondary text (meta lines, captions) |
| `hairline` | `#EEF3F8` | In-card row separators only |
| `blue` | `#2E8FE0` | Hero gradient start, links, "View all" actions |
| `blueSoft` | `#5CB8F2` | Hero gradient end |
| `chipBg` | `#E4F1FC` | Tinted chips, icon tiles (the "B" stop-type tile, ETA chip fill) |
| `chipInk` | `#1F74C0` | Text/numerals on `chipBg` |
| `amber` | `#E8960C` | Disruptions, standing crowd — semantic only |
| `red` | `#D9483B` | Severe disruption, packed crowd — semantic only |
| `shadow` | `#173049` @ 7% | The one shadow tint, used everywhere (see §3) |

**Semantic rules**
- Blue is the ONE decorative accent. It never means "warning" or "identity" — it means "this app's interactive/live surface" (hero, links, selected chip fill... except the selected filter chip fill is `ink`, not blue — see §4).
- Official MRT line colours (`WSLine.colors`, unchanged from `WSTheme.swift`) are identity-only: line pills/bullets. Never repurpose a line colour for status.
- Amber/red are reserved exclusively for disruption state and crowd severity. Nowhere else — not for "attention" in a generic sense, not for accents.
- **"Arriving now" emphasis — mint is banned.** The old system's mint glow-edge + pulse dot has no equivalent tint in 4b. Do this instead:
  - Ring/numeral: when ETA ≤ 60s, the hero countdown ring's fill trim reaches (or nearly reaches) full circumference and the centre numeral reads "Arr" in the same bold white — no colour change, no glow. The ring's own motion (fill animating in) *is* the emphasis.
  - Row/chip context (SoftStopRow, SoftMrtTile): the ETA chip text goes bold `chipInk` and the chip background may deepen slightly (`chipBg` → mix 15% `blue`) — never a glow, never mint, never a shadow color change. If a designer wants a stronger cue, bold + slightly larger numeral is the correct lever, not colour or light.

## 2. Type Scale

`ws.sans(size, weight)` = Inter, run through `UIFontMetrics` (Dynamic Type honoured). All countdowns/codes/distances use `.monospacedDigit()` — never plain proportional figures.

| Role | Size | Weight | Notes |
|---|---|---|---|
| Hero eyebrow ("CLOSEST · STOP NAME") | 10.5 | semibold | kerning 0.5, opacity 0.85, uppercase |
| Hero title (bus + dest) | 19 | heavy | tracking −0.2 |
| Hero secondary ("then …") | 12 | regular | opacity 0.92, monospacedDigit |
| Hero big numeral (ring) | 19 (17 if "Arr") | heavy | monospacedDigit, `.contentTransition(.numericText)` |
| Hero ring unit label | 8.5 | semibold | opacity 0.85 |
| Page greeting | 13 | medium | `sub` colour |
| Page title | 23 | heavy | tracking −0.4, `ink`, lineLimit 1, minimumScaleFactor 0.8 |
| Section head | 16 | bold | `ink` |
| Section action ("View all") | 12.5 | semibold | `blue` |
| Card/row title (stop/station name) | 14.5 | semibold | `ink` |
| Big numeral elsewhere (stat tiles, big ETA outside hero) | 24–28 | heavy | monospacedDigit |
| Row meta (code · distance) | 11.5 | regular | monospacedDigit, `sub` |
| Chip label (filter pill) | 13 | semibold | white on `ink`-fill / `sub` on white-fill |
| ETA chip (in-row) | 12.5 | bold | monospacedDigit, `chipInk` |
| Icon-button / caption | 11–12 | regular–semibold | `sub` |

Fill gaps by interpolating within this table — never invent a size outside 8.5–28pt; never use a weight lighter than `.regular` for anything on the tinted ground (light text on light ground fails contrast).

## 3. Shape + Elevation

| Component class | Corner radius | Notes |
|---|---|---|
| Hero card | 24 (continuous) | |
| Standard card (stop list, MRT card) | 20 (continuous) | |
| Grid tile (MRT 2-up tile) | 18 (continuous) | |
| Icon tile / stat tile (44×44, "B" tile) | 12–14 (continuous) | 40×40 icon buttons use 14; 44×44 content tiles use 12–13 |
| Chip / pill (filter, ETA chip) | Capsule, or 11 for rectangular ETA chip | |
| Skeleton bars | 5–8 depending on element | matches the real element it stands in for |

**The one shadow recipe**: `shadow(color: SoftBlue.shadow, radius: 9, y: 6)` for cards/tiles; lighter `radius: 6, y: 3` for small icon buttons; `radius: 5, y: 3` for chips. The hero card is the only element allowed a tinted shadow: `shadow(color: SoftBlue.blue.opacity(0.30), radius: 13, y: 8)`. Never use `.black` for a shadow colour in this language — always `SoftBlue.shadow` or the hero's blue-tinted variant.

**Hairline insets**: row dividers are `SoftBlue.hairline`, 1pt, inset `.padding(.leading, 64)` when following an icon-tile row (aligns with row text, not the tile), or flush when there's no leading tile. Card content padding: 16h/14-15v for rows, 18 all sides for hero, 13 all sides for grid tiles, 14h/12v for the "B"-tile stop row.

## 4. Component Inventory

**Gradient hero — ONE per screen, non-negotiable.** It is the single saturated element; everything else stays white-on-tint. What the hero IS, per screen:
- Nearby (shipped): closest stop + soonest bus + countdown ring.
- Stop detail: the featured/soonest service at that stop, same ring pattern, "then …" line for the rest.
- Saved: the single most-urgent saved item (soonest ETA across all saved stops/lines) — do not build a hero for "saved" as a concept; if nothing has a live ETA, drop the hero entirely for that screen state and start straight at the section list (never fabricate a hero to fill the slot).
- Alerts: NO hero — alerts is a status list, not a countdown; using the gradient hero here would misrepresent a disruption feed as "the one live thing to look at." Alerts gets a plain white summary card at top (count + severity), not gradient.
- Search: no hero — search is a utility screen, plain white result rows on tint only.

**Countdown ring** (hero only): stroke width 7, track `white.opacity(0.28)`, fill `white` solid, trim animates `0→frac` where `frac = max(0.08, min(1, 1 - sec/900))` (empty-ish at 15 min out, full at arrival), centre numeral + unit label per §2. This ring is the ONLY progress-ring instance in the language — don't add rings to non-hero tiles (a stat tile with a ring reads as a second hero and breaks the "one per screen" rule).

**White card + row anatomy**: leading icon/identity tile (38–44pt, tinted `chipBg` fill) → name (bold, `ink`) left with meta line directly under in `sub`/monospacedDigit → trailing ETA chip or chevron. This order is fixed: identity always left, answer/action always right (F-pattern scan — see reading-patterns convention). Never put the chevron AND an ETA chip stacked; pick one per row (list rows get chevron, hero/expanded rows get the chip).

**Soft pill chips (filter)**: Capsule, selected = `ink` fill + white text + shadow; unselected = white fill + `sub` text + same shadow (both states keep the shadow — a shadow-less unselected chip would read as flat/disabled, which filter chips aren't). Never use `blue` as the selected-chip fill — that's reserved for the hero/links; `ink` reads as "selected/pressed" the way system controls do.

**SoftIconButton chrome**: 40×40 white square, radius 14, icon 15pt at `ink.opacity(0.75)`, shadow per §3. This is the ONLY chrome for header actions (search, map, back) — no bordered/outlined variant, no tinted variant, ever.

**Section heads**: bold 16 title left + optional 12.5 semibold `blue` action right, 4pt horizontal inset so it sits flush with card content below it, not the screen edge.

**ETA chip** (SoftStopRow trailing element): `chipBg` fill, radius 11, `chipInk` bold monospacedDigit text, format `"{no} · {mins} min"` or `"{no} · Arr"`.

**MRT tile** (SoftMrtTile): line bullet(s) top, station name (13.5 bold), meta line (distance · crowd word) bottom — same white-card/shadow treatment as everything else, 2-up grid.

**Empty / loading states**: skeleton cards ONLY — white rounded-rect cards on the tinted ground with pulsing opacity bars mirroring the real component's anatomy and exact dimensions (hero-shaped skeleton for the hero slot, row-shaped skeletons below), matching `WSSkeletonCard`'s existing pattern but re-skinned: bars are `SoftBlue.ink.opacity(0.06/0.09)` on white card, not `Color.white.opacity()` on a dark card. Never a spinner, never a blank screen with just text.

## 5. Porting Old Semantics

| Old (greendark) | 4b treatment |
|---|---|
| Mint/amber/red crowd dots | Crowd becomes a **word**, not a dot: append to the tile/row meta line as plain text (`"320 m · Standing"` / `"320 m · Packed"`), coloured `sub` normally, `amber`/`red` text colour ONLY when standing/packed. No dot, no glow — colour lives in the word's text colour alone, never as a separate mark. |
| Amber glow-edge on disruption card | **No left-border-accent, no top-glow-edge.** Instead: the affected row/card gets a thin amber-tinted **chip row appended below the identity line** — e.g. a small capsule `"⚠ Delay on North East Line"` in `amber` text on an amber-tinted (`amber.opacity(0.12)`) capsule background, sitting where the meta line normally is. This keeps disruption info textual and contained, matching how crowd/ETA info already reads as chips/text in this language, rather than reintroducing a decorative edge-lit border. |
| Mint pulsing "!" badge (station disruption) | Same chip-row treatment as above, scoped to the MRT tile/row — no separate pulsing badge. If motion is wanted for urgency, animate the chip's opacity subtly (existing pulse timing: 1s ease-in-out repeat), never colour-shift or glow. |
| Mint bell badge (armed alert) | A filled `blue` bell glyph badge (solid `blue` circle, white glyph) replaces the mint version — same position/size, blue instead of mint, no glow. |
| `WSGlowEdge` / `WSPulseDot` components generally | Retired for 4b screens. Any "this is live/urgent" signal in 4b comes from typography weight, the hero ring, or a text-coloured chip — never a glow or a dot. |

## 6. Dark-Twin Guidance (future-proofing only — not building now)

Structure all 4b views to read colour from `SoftBlue` (or a future `.ws4b` environment value), never hardcode hex inline, so a dark variant is a token swap:
- `bg` → ~`#10151B`
- `card` → ~`#1A2028`
- `ink` → near-white (`#F0F3F6`), `sub` → `#8B929C`
- `hairline` → low-alpha white (`white.opacity(0.06)`)
- `blue` / `blueSoft` stay the SAME hex — the one accent doesn't shift between light/dark, only its surroundings do.
- `chipBg` becomes a low-alpha blue tint on dark (`blue.opacity(0.16)`) rather than a pale fill; `chipInk` lightens to `blueSoft`.
- `shadow` on dark becomes `black.opacity(0.4)` rather than the blue-tinted ambient shadow (soft ambient shadows disappear against dark grounds; use a harder black shadow instead).

Do not hand-roll a `darkBody` per screen the way `WSHomeView` currently keeps `darkBody` around as a fallback — that pattern is a temporary bridge during the greendark→4b migration, not the target architecture.

## 7. Anti-Rules (violate none of these)

1. No glows. No `.shadow(color: accent.opacity(x), radius: y)` on text or edges — the old `WSGlowEdge`/mint-glow pattern is fully retired.
2. No text-shadows anywhere, including on the hero (the hero's shadow is on the CARD, not the text inside it).
3. No gradients except the ONE hero gradient per screen. Chips, tiles, buttons are flat fills.
4. No mint, anywhere, in any opacity, for any purpose. If a screen still references `WSTheme.accent`/`mintGradient`, it hasn't been ported yet — don't blend it with `SoftBlue` tokens on the same screen.
5. No bare-bordered/outlined dark-style chips or buttons (the greendark `chip()` with a stroke-only capsule). Every chip/button in 4b has either a solid fill + shadow (unselected chip, icon button) or the ink/blue solid fill (selected chip, hero CTA) — never just a stroke on transparent.
6. No more than one saturated gradient card visible on screen at a time, even across sections (e.g. don't add a second gradient promo card below the hero).
7. No progress rings outside the hero.
8. Never mix `WSTheme` (greendark) tokens and `SoftBlue` tokens within the same screen/file — port a screen wholesale or not at all.

---

# Appendix: Rollout notes (from the 2026-07-24 design study)

- **Component forks, not in-place restyles**: WSMapView stays dark (owner call) and shares LineBullet/CrowdGauge/RouteTile/ArrivalPill — those originals are untouched; soft screens use Soft* equivalents in WSSoftTheme.swift (the ONLY file allowed to declare new shared soft symbols).
- **WSBusStopView regression watch**: the 2026-07-24 field-test fixes (74pt compact-header collapse, dataPulse on refresh, ≤2min gating, custom swipe-to-arm DragGesture) must survive restyling verbatim.
- **Known cross-cutting risks**: wsDetailAdBanner paints the global dark Theme surface behind ads (mismatch on light screens — parameterize); status-bar legibility on the pale ground; onboarding→light-screen handoff; amber contrast against #DCE9F4.
- **Not in scope**: WSMapView (chrome reconciliation is a design-review ticket); dark twin (token swap per §6, do NOT hand-roll darkBody per screen).
- Full study artifacts (session scratchpad): study-design-spec.md, study-inventory.md, study-eng-plan.md.
