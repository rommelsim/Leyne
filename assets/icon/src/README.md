# App icon sources — "route + live dot" (sky-blue palette, 2026-07-25)

Design: the Departly mark from the owner's Claude Design project ("Departly
App Icon Sky.dc.html") — a white route curve sweeping up to a station node
whose centre is the deep-blue (#1F74C0) "live" dot, on a sky diagonal gradient
(`#5CB8F2 → #2E8FE0`); subtle top gloss. Dark appearance inverts: sky-blue
(#5CB8F2) route on near-black navy (`#1C2B3A → #0D1420`), inner dot = the
dark background. Re-palettes the mint greendark icon (2026-07-24), which
replaced the pin-clock icon (2026-07-04).
Design: white map pin whose head is a clock face (dark plum) with a green
countdown arc, on a coral→red diagonal gradient (`#FF8A5C → #EF4351`).
Replaces the WhereSia/Departly letterform icons (see
`scripts/generate_app_icon.py`, kept for reference but superseded).

| SVG | Renders to | Used as |
|---|---|---|
| `light.svg` | `AppIcon-Light.png` + `assets/icon/leyne_icon.png` | iOS light/universal, Android legacy mipmaps + store art |
| `dark.svg` | `AppIcon.png` | iOS dark appearance (gradient-filled pin on near-black) |
| `bg.svg` | `assets/icon/leyne_icon_bg.png` | Android adaptive background (gradient alone) |
| `fg.svg` | `assets/icon/leyne_icon_fg.png` | Android adaptive foreground (glyph on transparency) |
| `mono.svg` | `assets/icon/leyne_icon_monochrome.png` | Android 13+ themed icon (alpha silhouette, clock face punched out) |

## Regenerating

1. `python3` + Pillow renders the set directly (no SVG rasterizer needed) —
   the geometry lives in these SVGs and is mirrored in the render script the
   design-greendark session used (bezier flattening + circle stamping,
   4× supersampled). Any SVG rasterizer (`rsvg-convert`, `resvg`) also works
   on these sources directly.
2. Copy outputs per the table (iOS appiconset path is
   `ios-native/Leyne/Assets.xcassets/AppIcon.appiconset/`).
3. Regenerate the Android launcher set:
   `dart run flutter_launcher_icons -f flutter_launcher_icons.yaml`

Geometry note: viewBox is 160; route path `M-10 112 C 40 112, 55 48, 96 48
L 175 48` (round caps, w=14), node r17 @ (96,48), inner dot r8. The dot sits
at (0.60, 0.30) of the tile — inside the Android adaptive 66% safe zone.
