# App icon sources — "pin-clock" (2026-07-04)

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

1. Render each SVG to a 1024×1024 PNG. With no SVG rasterizer installed,
   `qlmanage -t -s 1024 -o <outdir> <file>.svg` works BUT flattens
   transparency onto opaque white — fine for `light`/`dark`/`bg`, wrong for
   `fg`/`mono`. For those two, render twice (once over a black rect, once
   over white, injected as the first child of `<svg>`) and reconstruct the
   alpha per pixel: `a = 1 - (white - black)`, `rgb = black / a`.
   (With `rsvg-convert`/`resvg` installed, a single direct render is fine.)
2. Copy the outputs to the paths in the table (iOS appiconset paths are
   `ios-native/Leyne/Assets.xcassets/AppIcon.appiconset/`).
3. Regenerate the Android launcher set:
   `dart run flutter_launcher_icons -f flutter_launcher_icons.yaml`

Geometry note: the pin glyph is 708px tall on the 1024 canvas (~69%); the
adaptive icon's 16% inset lands it at ~70% of the visible tile, inside the
66/108dp safe zone and optically matching the iOS icon. Keep `fg.svg` and
`mono.svg` in the same geometry so the themed icon sits identically.
