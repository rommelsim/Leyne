#!/usr/bin/env python3
"""App icon generator — Departly "D" in the established icon design system.

SUPERSEDED 2026-07-04: the shipped icon is now the "pin-clock" artwork
(white map pin + clock face with green countdown arc on a coral→red
gradient), sourced from the SVGs in assets/icon/src/ — see the README
there for the regeneration steps. Running THIS script would overwrite the
pin-clock icon with the old letterform. Kept for reference only.

Reproduces the three artwork variants that shipped with the WhereSia "W"
icon (owner keeps the design language, letter changes with the rename):

  dark  (iOS dark appearance, the owner's favourite): charcoal vertical
        gradient bg + azure→deep-blue gradient glyph + soft blue halo.
  light (iOS universal + Android source art): white glyph, soft shadow,
        azure→deep-blue bg with a radial top highlight.
  mono  (Android 13+ themed icon): glyph alpha only, transparent bg.

Colour stops are sampled from the original artwork so the rename doesn't
drift the palette:
  dark bg   (31,35,42) → (13,17,21), mild corner vignette
  glyph     (80,169,251) → (17,105,201)
  light bg  (90,171,253) → (2,84,182), radial highlight near the top

Outputs (overwrites in place):
  ios-native/Leyne/Assets.xcassets/AppIcon.appiconset/AppIcon.png        (dark)
  ios-native/Leyne/Assets.xcassets/AppIcon.appiconset/AppIcon-Light.png  (light)
  assets/icon/leyne_icon.png                                             (light)
  assets/icon/leyne_icon_monochrome.png                                  (mono)

Then regenerate the Android mipmaps with:
  dart run flutter_launcher_icons -f flutter_launcher_icons.yaml
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / "ios-native/Leyne/WhereSia/Fonts/Inter-ExtraBold.ttf"
LETTER = "D"
SIZE = 1024
SS = 2  # supersample factor for smooth edges/glow
S = SIZE * SS

# Cap height of the original W ≈ 465px at 1024 (45% of canvas), centred.
CAP_TARGET = 530 * SS  # D is narrower than the W was; taller cap ≈ same visual mass


def glyph_mask() -> Image.Image:
    """White-on-transparent letter mask, cap height CAP_TARGET, centred."""
    # Find the font size whose cap height hits the target.
    size = CAP_TARGET  # starting guess; Inter cap/em ≈ 0.727
    for _ in range(6):
        font = ImageFont.truetype(str(FONT), size)
        l, t, r, b = font.getbbox(LETTER)
        h = b - t
        if abs(h - CAP_TARGET) <= SS:
            break
        size = round(size * CAP_TARGET / h)
    mask = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(mask)
    d.text((0, 0), LETTER, font=font, fill=255)
    # Centre by the MEASURED ink box — font metrics offsets left the glyph
    # visibly off-centre in the first render.
    l, t, r, b = mask.getbbox()
    shifted = Image.new("L", (S, S), 0)
    # +1.2% optical nudge right: a D is stem-heavy on the left, so the
    # geometric centre reads left-shifted (matches classic optical centring).
    nudge = round(S * 0.012)
    shifted.paste(
        mask.crop((l, t, r, b)),
        ((S - (r - l)) // 2 + nudge, (S - (b - t)) // 2),
    )
    return shifted


def v_gradient(top: tuple, bottom: tuple) -> Image.Image:
    g = Image.new("RGB", (1, S))
    for y in range(S):
        f = y / (S - 1)
        g.putpixel((0, y), tuple(round(a + (b - a) * f) for a, b in zip(top, bottom)))
    return g.resize((S, S))


def radial(centre: tuple, radius: float, strength: float) -> Image.Image:
    """L-mode falloff map: 255*strength at centre → 0 at radius.
    Computed per-pixel on a small grid then upscaled — a stepped-ellipse
    approximation left visible banding rings in the first render."""
    n = 128
    small = Image.new("L", (n, n), 0)
    px = small.load()
    cx, cy = centre[0] * n / S, centre[1] * n / S
    r_small = radius * n / S
    for y in range(n):
        for x in range(n):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            f = max(0.0, 1.0 - d / r_small)
            px[x, y] = round(255 * strength * f)
    return small.resize((S, S), Image.BICUBIC)


def dark_variant(mask: Image.Image) -> Image.Image:
    bg = v_gradient((31, 35, 42), (13, 17, 21))
    # Break up 8-bit banding on the long dark ramp with imperceptible noise.
    import random
    rnd = random.Random(7)
    noise = Image.effect_noise((S, S), 6)
    bg = Image.blend(bg, Image.merge("RGB", (noise, noise, noise)), 0.015)
    # Mild corner vignette: darken by up to ~8% outside the centre.
    vin = radial((S // 2, S // 2), S * 0.75, 1.0)
    black = Image.new("RGB", (S, S), (8, 10, 13))
    bg = Image.composite(bg, black, vin.point(lambda a: 155 + a * 100 // 255))
    # Soft blue halo behind the glyph.
    glow_col = Image.new("RGBA", (S, S), (60, 140, 240, 0))
    glow_col.putalpha(mask.point(lambda a: a * 55 // 100))
    glow = glow_col.filter(ImageFilter.GaussianBlur(30 * SS))
    out = bg.convert("RGBA")
    out.alpha_composite(glow)
    # Gradient-filled glyph.
    letter = v_gradient((80, 169, 251), (17, 105, 201)).convert("RGBA")
    letter.putalpha(mask)
    out.alpha_composite(letter)
    return out


def light_variant(mask: Image.Image) -> Image.Image:
    bg = v_gradient((90, 171, 253), (2, 84, 182))
    # Radial highlight near the top (original reads brightest at top-centre).
    hi = radial((S // 2, round(S * 0.16)), S * 0.75, 0.35)
    white = Image.new("RGB", (S, S), (168, 214, 255))
    bg = Image.composite(white, bg, hi)
    out = bg.convert("RGBA")
    # Soft glyph shadow.
    sh = Image.new("RGBA", (S, S), (0, 50, 120, 0))
    sh.putalpha(mask.point(lambda a: a * 35 // 100))
    sh = sh.filter(ImageFilter.GaussianBlur(16 * SS))
    out.alpha_composite(sh, (0, 10 * SS))
    letter = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    letter.putalpha(mask)
    out.alpha_composite(letter)
    return out


def mono_variant(mask: Image.Image) -> Image.Image:
    out = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    out.putalpha(mask)
    return out


def down(im: Image.Image) -> Image.Image:
    return im.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> None:
    mask = glyph_mask()
    dark = down(dark_variant(mask)).convert("RGB")
    light = down(light_variant(mask)).convert("RGB")
    mono = down(mono_variant(mask))

    appicon = ROOT / "ios-native/Leyne/Assets.xcassets/AppIcon.appiconset"
    dark.save(appicon / "AppIcon.png")
    light.save(appicon / "AppIcon-Light.png")
    light.save(ROOT / "assets/icon/leyne_icon.png")
    mono.save(ROOT / "assets/icon/leyne_icon_monochrome.png")
    print("wrote dark/light/mono icon artwork")


if __name__ == "__main__":
    main()
