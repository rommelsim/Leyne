#!/usr/bin/env python3
"""Frame Leyne Android screenshots in a Samsung S24 Ultra body with baked-on
Play Store captions. Output: store_assets/screenshots/android/NN-name.png

Run: python3 scripts/android_store_frames.py
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SRC_DIR = "/Users/rommel/Downloads/Telegram Desktop"
RAW_OUT = "screenshots/android"
OUT_DIR = "store_assets/screenshots/android"

# (source file, raw-name, headline, subcaption)
SHOTS = [
    ("Screenshot_20260622_190943.jpg", "01-nearby",
     "Your stops. Right now.", "Live arrivals at every stop near you"),
    ("Screenshot_20260622_191008.jpg", "02-stop-board",
     "Every bus, live to the minute", "All arrivals at your stop, one tap away"),
    ("Screenshot_20260622_191019.jpg", "03-bus-arriving",
     "Know before it arrives", "Live timing, seats and crowd as it nears"),
    ("Screenshot_20260622_191032.jpg", "04-bus-route",
     "Follow it, stop by stop", "See exactly where your bus is on the route"),
    ("Screenshot_20260622_191042.jpg", "05-mrt",
     "Trains too — every line, live", "MRT status across the whole network"),
    ("Screenshot_20260622_191134.jpg", "06-alerts",
     "Always know what's running", "Disruptions, advisories and lift maintenance"),
]

# --- layout (native units, downscaled at the end) ---
CANVAS_W, CANVAS_H = 1620, 3150
SW = 1300                 # screen width
BZ = 22                   # black bezel/glass border
RAIL = 8                  # titanium rail thickness
RS = 58                   # screen corner radius
DEVTOP = 500              # y of device top
OUT_W = 1080              # final width (=> 1080x2100, ratio 1.944 < 2:1 Play cap)

# light "App Store" gradient: pale blue top -> near-white bottom
TOP_RGB = (228, 237, 252)
BOT_RGB = (248, 249, 253)
HEAD_RGB = (26, 32, 44)        # dark navy headline
SUB_RGB = (119, 128, 141)      # gray subcaption

def font(paths, size):
    for p in paths:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                pass
    return ImageFont.load_default()

BOLD = ["/System/Library/Fonts/Supplemental/Arial Bold.ttf"]
REG  = ["/System/Library/Fonts/Supplemental/Arial.ttf"]
f_head = font(BOLD, 84)
f_sub  = font(REG, 46)

def gradient(w, h, top, bot):
    base = Image.new("RGB", (w, h))
    px = base.load()
    for y in range(h):
        t = y / (h - 1)
        r = int(top[0] + (bot[0]-top[0]) * t)
        g = int(top[1] + (bot[1]-top[1]) * t)
        b = int(top[2] + (bot[2]-top[2]) * t)
        for x in range(w):
            px[x, y] = (r, g, b)
    return base

def wrap(draw, text, fnt, maxw):
    words = text.split()
    lines, cur = [], ""
    for w in words:
        trial = (cur + " " + w).strip()
        if draw.measure if False else draw.textlength(trial, font=fnt) <= maxw:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines

def build_device(src):
    img = Image.open(src).convert("RGB")
    sw, sh = img.size
    scale = SW / sw
    screen_h = round(sh * scale)
    screen = img.resize((SW, screen_h), Image.LANCZOS).convert("RGBA")

    # round the screen corners
    mask = Image.new("L", (SW, screen_h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, SW-1, screen_h-1], radius=RS, fill=255)
    screen.putalpha(mask)

    dev_w = SW + 2*BZ
    dev_h = screen_h + 2*BZ
    full_w = dev_w + 2*RAIL
    full_h = dev_h + 2*RAIL
    dev = Image.new("RGBA", (full_w, full_h), (0, 0, 0, 0))
    d = ImageDraw.Draw(dev)
    # titanium rail (light metal) as the outermost rounded rect
    d.rounded_rectangle([0, 0, full_w-1, full_h-1], radius=RS+BZ+RAIL,
                        fill=(150, 152, 156, 255))
    # black glass inset by RAIL
    d.rounded_rectangle([RAIL, RAIL, RAIL+dev_w-1, RAIL+dev_h-1],
                        radius=RS+BZ, fill=(6, 6, 8, 255))
    # the screen
    dev.alpha_composite(screen, (RAIL+BZ, RAIL+BZ))
    # centered punch-hole camera
    cx = full_w // 2
    cy = RAIL + BZ + 44
    r = 17
    d.ellipse([cx-r-2, cy-r-2, cx+r+2, cy+r+2], fill=(26, 26, 28, 255))
    d.ellipse([cx-r, cy-r, cx+r, cy+r], fill=(4, 4, 6, 255))
    return dev

def render(src, headline, sub):
    canvas = gradient(CANVAS_W, CANVAS_H, TOP_RGB, BOT_RGB).convert("RGBA")
    dev = build_device(src)
    fw, fh = dev.size
    dx = (CANVAS_W - fw) // 2

    # soft drop shadow for depth
    shadow = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle([dx+10, DEVTOP+26, dx+fw+10, DEVTOP+fh+26],
                         radius=RS+BZ+RAIL, fill=(0, 0, 0, 120))
    shadow = shadow.filter(ImageFilter.GaussianBlur(30))
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(dev, (dx, DEVTOP))

    # caption block, centered in the 0..DEVTOP band
    draw = ImageDraw.Draw(canvas)
    maxw = CANVAS_W - 240
    hlines = wrap(draw, headline, f_head, maxw)
    line_gap = 12
    head_h = sum((f_head.getbbox(l)[3]-f_head.getbbox(l)[1]) + line_gap for l in hlines)
    sub_bb = f_sub.getbbox(sub)
    sub_h = sub_bb[3] - sub_bb[1]
    block_h = head_h + 28 + sub_h
    y = (DEVTOP - block_h) // 2 + 10

    for l in hlines:
        bb = f_head.getbbox(l)
        lw = draw.textlength(l, font=f_head)
        draw.text(((CANVAS_W-lw)//2, y - bb[1]), l, font=f_head, fill=HEAD_RGB + (255,))
        y += (bb[3]-bb[1]) + line_gap
    y += 16
    lw = draw.textlength(sub, font=f_sub)
    draw.text(((CANVAS_W-lw)//2, y - sub_bb[1]), sub, font=f_sub, fill=SUB_RGB + (255,))

    out_h = round(CANVAS_H * OUT_W / CANVAS_W)
    return canvas.convert("RGB").resize((OUT_W, out_h), Image.LANCZOS)

def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(RAW_OUT, exist_ok=True)
    for src_name, name, head, sub in SHOTS:
        src = os.path.join(SRC_DIR, src_name)
        # keep a clean raw copy too
        Image.open(src).convert("RGB").save(os.path.join(RAW_OUT, f"{name}.png"))
        out = render(src, head, sub)
        path = os.path.join(OUT_DIR, f"{name}.png")
        out.save(path)
        print(f"{path}  {out.size[0]}x{out.size[1]}")

if __name__ == "__main__":
    main()
