# WhereSia — design system

The look is a **dark "departure board"**: near-black surfaces, tabular/monospace numerals, thin single-weight line icons, no emoji. A light variant exists (same tokens, swapped values). `reference/mockup.html` is the canonical implementation — port these tokens verbatim.

## The one hard rule: color = data, never chrome
This is the spine of the whole design. Do not break it.

- **The ONLY color anywhere in the app is official MRT/LRT line identity** (the line "bullet" tiles). Everything else — backgrounds, text, buttons, bus route numbers, icons — is greyscale/tonal.
- **Bus route numbers are neutral** (never colored).
- **Crowd is NOT color-coded.** It is a neutral occupancy gauge (fill length = how full) **plus a word**. This was a deliberate decision: LTA's green/amber/red load scheme collided with line hues (EWL green, NSL red, TEL brown), so crowd is fully greyscale. **Never reintroduce green/amber/red for crowd.**
- The app **icon** tile is ink-blue — that's the one exception, and it's fine because the icon is OS chrome, outside the app UI.

### Official line colors (the only palette)
| Line | Code | Hex |
|---|---|---|
| North South | NSL / NS | `#E1251B` |
| East West | EWL / EW | `#009645` |
| North East | NEL / NE | `#9E28B5` |
| Circle | CCL / CC | `#FFAD00` |
| Downtown | DTL / DT | `#005EC4` |
| Thomson–East Coast | TEL / TE | `#9D5B25` |
| LRT (BP/SK/PG) | — | `#748477` |

Line bullets render as small mono tiles with white text on the line color (e.g. `NS22`, `TE14`, `EWL`).

## Color tokens (CSS custom properties)
Ported directly from the mockup. Use these names as your token layer.

```css
/* DARK (default) */
--bg:      #0F1216;  /* screen background */
--panel:   #161A20;  /* cards */
--panel2:  #1B2027;  /* nested surfaces / pills */
--input:   #181D24;  /* search field */
--text:    #E8EAED;  /* primary text + gauge fill + accents */
--dim:     #8A93A2;  /* secondary text */
--faint:   #5A626E;  /* tertiary / disabled */
--rule:    #242A33;  /* hairline borders + empty gauge track */
--tabbar:  #12161B;  /* tab bar bg */
--bezel:   #05070A;  /* device bezel (mockup only) */

/* LIGHT (body.light) */
--bg:      #FFFFFF;
--panel:   #F5F6F8;
--panel2:  #EEF0F3;
--input:   #F1F2F5;
--text:    #14181D;
--dim:     #6B7280;
--faint:   #A2A8B2;
--rule:    #E6E8EC;
--tabbar:  #FFFFFF;
```

## Typography
- **Sans (UI):** system stack — `-apple-system, "SF Pro Text", "Inter", "Segoe UI", Roboto, sans-serif`.
- **Mono (all numerals & codes):** `ui-monospace, "SF Mono", Menlo, monospace`. Use for arrival minutes, stop codes, line codes, times, frequencies — anything tabular. Apply `font-variant-numeric: tabular-nums`.
- Weights: titles 800, row names 700, body 600, captions 500. Letter-spacing: tight on titles (`-.4px`), wide on uppercase eyebrows/labels (`1.2–1.4px`).
- Scale (px): screen title 22 · row name 15.5 · arrival time 19 · caption 11–12 · eyebrow/label 11 uppercase.

## Iconography
- **One** thin line-icon set. Stroke `1.7`, `fill:none`, round caps/joins, 24×24 viewBox (`.ico` in the mockup). No emoji, ever.
- Key custom glyphs (copy the SVG paths from `reference/mockup.html`):
  - **Bus, single-deck** — short body, one window line, two wheels.
  - **Bus, double-deck** — taller body, two window lines, two wheels. (These replace "SD/DD" text.)
  - **Wheelchair** — WAB / wheelchair-accessible bus.
  - **Live ")))"** — the arriving-wave glyph; pulses. Present = live/`Monitored`; absent = scheduled.
  - **MRT/train** — station glyph.
  - **Bookmark** — the single save icon (used everywhere; do not mix with a star).

## Core components
- **Crowd gauge (`.load`)** — a 26×6 rounded track (`--rule`) with a `--text` fill. Fill widths: **34% / 67% / 100%**. Bus load classes `sea`/`sda`/`lsd` and station classes `low`/`mod`/`high` are aliases of the same three widths. `sched` = 0% (empty) for scheduled buses. Fills animate on appear via `scaleX`. **Always pair with a word.**
  - Bus words: **Seats** (SEA) · **Standing** (SDA) · **Limited / Full** (LSD).
  - Station words: **Low** · **Moderate** · **High**.
- **Route tiles** — mono, neutral (`.tile.num` = `--panel2` bg, `--text`). Small (`.tile`, ~21px) in lists, large (`.tileL`, 46×40) as a screen subject. Overflow chip `.tile.ovf` = dashed border `+N` when a stop has more services than fit.
- **Arrival pills (`.buspill`)** — flex row of up to 3, each = minutes (mono, tabular) + gauge + word, stretched full width (`flex:1`). First = `.now` (highlighted border); scheduled = `.sched` (dimmed).
- **Line bullet tile** — mono tile, white text on the official line hex (see table).
- **Cards (`.card`)**, **section headers (`.sec`)** with uppercase label + hairline + right-side meta (e.g. `UPD 9:41`), **tab bar (`.tabbar`)**, **toggle (`.tog`)**, **segmented control (`.segbar`/`.seg`)**, **chip (`.chip`)** — all specced in the mockup CSS.

## Motion
Restrained. Gauges fill, crowd forecast bars grow, live/tracked-bus glyphs pulse. Everything is wrapped in `@media (prefers-reduced-motion: reduce){ *{ animation:none !important } }` — keep that.

## App icon
Stop pin (off-white `#E8EAED`, aperture `#0B1220`) on an ink-blue tile (`linear-gradient(150deg,#1D2941,#101A2C,#080D16)`). Full-bleed square masters in `icon/`; iOS applies the squircle mask. See `icon/wheresia-app-icon-final.png`.
