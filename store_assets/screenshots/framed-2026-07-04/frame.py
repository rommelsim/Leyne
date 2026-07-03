#!/usr/bin/env python3
"""Frame Departly screenshots in iPhone 17 Pro Max / S24 Ultra mockups,
with the ASO headline baked in above the device.

Everything is drawn at 2x and LANCZOS-downscaled (PIL shapes aren't
antialiased at 1x). Each device's screen = white status band (with island /
punch-hole + minimal status glyphs) + the screenshot anchored below it.
Device width is computed so the whole phone fits under the caption band.
"""
from PIL import Image, ImageDraw, ImageFilter, ImageFont

SRC = {
    "home": "/Users/rommel/Downloads/IMG_4830.jpg",
    "station": "/Users/rommel/Downloads/IMG_4832.jpg",
    "bus": "/Users/rommel/Downloads/IMG_4815.jpg",
    "alerts": "/Users/rommel/Downloads/IMG_4831.jpg",
}
# Store order: strongest, most differentiated value in slots 1-3.
ORDER = ["bus", "home", "station", "alerts"]
CAPTIONS = {
    "iphone17promax": {
        "bus": "Watch your bus roll in",
        "home": "Every stop near you, live",
        "station": "Know the crowd first",
        "alerts": "Know before you go",
    },
    "s24ultra": {
        "bus": "Watch your bus roll in",
        "home": "Live arrivals. No sign-up.",  # Play: plain benefit + no friction
        "station": "Know the crowd first",
        "alerts": "Know before you go",
    },
}
OUT = "/private/tmp/claude-501/-Users-rommel-Documents-Leyne/cca9bbb3-8430-430e-977a-1851688e23d0/scratchpad/store_frames/"

SRC_W, SRC_H = 1320, 2708  # tallest source; shorter ones get white-padded

DEVICES = {
    "iphone17promax": dict(
        # 1284x2778: App Store Connect's accepted 6.5" portrait size — ASC
        # rejected the 6.9" 1320x2868 for this listing.
        canvas=(1284, 2778), band=116,
        bezel=22, ring=8, body_r=176, screen_r=148,
        body="#2E2F33", edge="#4A4B50",
        cutout=("island", 300, 86),
        caption_h=320, bottom=90, cap_size=92,
    ),
    "s24ultra": dict(
        canvas=(1440, 3120), band=118,
        bezel=14, ring=6, body_r=64, screen_r=44,
        body="#1F2124", edge="#3C3E43",
        cutout=("punch", 34, 52),
        caption_h=350, bottom=100, cap_size=100,
    ),
}

S = 2  # supersample factor
INK = (17, 17, 17, 255)


def font(size, bold=False):
    return ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc",
                              size, index=1 if bold else 0)


def status_glyphs(d, band_w, band_h):
    """Time left, signal/wifi/battery right — minimal dark shapes (2x px)."""
    cy = band_h // 2
    d.text((110 * S, cy), "9:41", font=font(40 * S, bold=True),
           fill=INK, anchor="lm")
    right = band_w - 110 * S
    bw, bh = 62 * S, 30 * S
    bx, by = right - bw, cy - bh // 2
    d.rounded_rectangle([bx, by, bx + bw, by + bh], radius=8 * S,
                        outline=(17, 17, 17, 140), width=3 * S)
    d.rounded_rectangle([bx + 5 * S, by + 5 * S, bx + bw - 16 * S, by + bh - 5 * S],
                        radius=4 * S, fill=INK)
    d.rounded_rectangle([bx + bw + 3 * S, cy - 7 * S, bx + bw + 8 * S, cy + 7 * S],
                        radius=3 * S, fill=(17, 17, 17, 140))
    wx = bx - 30 * S
    for r in (26, 17, 8):
        rr = r * S
        d.arc([wx - rr, cy - rr + 6 * S, wx + rr, cy + rr + 6 * S],
              start=225, end=315, fill=INK, width=6 * S)
    d.ellipse([wx - 4 * S, cy + 2 * S, wx + 4 * S, cy + 10 * S], fill=INK)
    sx = wx - 46 * S
    for i in range(4):
        h = (12 + 6 * i) * S
        x = sx - (3 - i) * 12 * S
        d.rounded_rectangle([x, cy + 15 * S - h, x + 7 * S, cy + 15 * S],
                            radius=3 * S, fill=INK)


def build(dev_key, slug, slot):
    p = DEVICES[dev_key]
    cw, ch = p["canvas"]
    W, H = cw * S, ch * S
    band = p["band"] * S
    bez, ring = p["bezel"] * S, p["ring"] * S

    # device width such that the full phone fits between caption and bottom
    avail = (ch - p["caption_h"] - p["bottom"]) * S
    content_avail = avail - band - 2 * (bez + ring)
    sw = round(content_avail * SRC_W / SRC_H)

    shot = Image.open(SRC[slug]).convert("RGB")
    scale = sw / shot.width
    shot = shot.resize((sw, round(shot.height * scale)), Image.LANCZOS)
    screen_h = band + round(SRC_H * sw / SRC_W)
    screen = Image.new("RGBA", (sw, screen_h), (255, 255, 255, 255))
    screen.paste(shot, (0, band))
    sd = ImageDraw.Draw(screen)
    status_glyphs(sd, sw, band)
    kind = p["cutout"]
    if kind[0] == "island":
        iw, ih = kind[1] * S, kind[2] * S
        y0 = (band - ih) // 2
        sd.rounded_rectangle([(sw - iw) // 2, y0, (sw + iw) // 2, y0 + ih],
                             radius=ih // 2, fill=(5, 5, 7, 255))
    else:
        dia, cyy = kind[1] * S, kind[2] * S
        sd.ellipse([(sw - dia) // 2, cyy - dia // 2,
                    (sw + dia) // 2, cyy + dia // 2], fill=(5, 5, 7, 255))
    mask = Image.new("L", (sw, screen_h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw, screen_h],
                                           radius=p["screen_r"] * S, fill=255)
    screen.putalpha(mask)

    dev_w = sw + 2 * (bez + ring)
    dev_h = screen_h + 2 * (bez + ring)
    dx = (W - dev_w) // 2
    dy = p["caption_h"] * S

    canvas = Image.new("RGBA", (W, H))
    top, bot = (245, 243, 240), (231, 227, 221)
    grad = Image.new("RGBA", (1, H))
    for y in range(H):
        t = y / (H - 1)
        grad.putpixel((0, y), tuple(round(top[i] + (bot[i] - top[i]) * t)
                                    for i in range(3)) + (255,))
    canvas.paste(grad.resize((W, H)))

    # headline — shrink-to-fit, centred in the caption zone
    d = ImageDraw.Draw(canvas)
    text = CAPTIONS[dev_key][slug]
    size = p["cap_size"] * S
    while size > 40 * S:
        f = font(size, bold=True)
        if d.textlength(text, font=f) <= W - 180 * S:
            break
        size -= 4 * S
    d.text((W // 2, int(p["caption_h"] * S * 0.54)), text,
           font=font(size, bold=True), fill=(23, 24, 26, 255), anchor="mm")

    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        [dx + 8 * S, dy + 30 * S, dx + dev_w - 8 * S, dy + dev_h + 26 * S],
        radius=p["body_r"] * S, fill=(20, 18, 16, 90))
    canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(34 * S)))

    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle([dx, dy, dx + dev_w, dy + dev_h],
                        radius=p["body_r"] * S, fill=p["body"],
                        outline=p["edge"], width=2 * S)
    d.rounded_rectangle([dx + ring, dy + ring,
                         dx + dev_w - ring, dy + dev_h - ring],
                        radius=(p["body_r"] - p["ring"]) * S, fill=(8, 8, 10, 255))
    canvas.alpha_composite(screen, (dx + ring + bez, dy + ring + bez))

    out = canvas.resize((cw, ch), Image.LANCZOS).convert("RGB")
    path = f"{OUT}{dev_key}_{slot}_{slug}.png"
    out.save(path)
    print("wrote", path, out.size)


for dev in DEVICES:
    for i, slug in enumerate(ORDER, 1):
        build(dev, slug, i)
