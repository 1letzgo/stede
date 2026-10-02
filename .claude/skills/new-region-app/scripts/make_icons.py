#!/usr/bin/env python3
"""App-Icons einer Marke: iOS AppIcon (1024 px) und Android-Hintergrund (adaptive icon, 432 px).

Aufruf: python3 make_icons.py <region> [--dry-run]
Quelle: `brand.icon` (PNG, quadratisch, ≥ 1024 px, randlos) — sonst ein generiertes Icon: Leistenfarbe
als Fläche, App-Name in Weiß, darunter eine Welle in der Akzentfarbe. Android: Icon auf die sichtbaren
72 dp skaliert, Ränder fortgesetzt (wie bei Loog).
"""
import json, math, os, sys

from PIL import Image, ImageDraw, ImageFont

import spec as S

FONTS = ["/System/Library/Fonts/SFCompactRounded.ttf", "/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc"]


def generated(spec):
    b = spec["brand"]
    pal = S.palette(spec)
    img = Image.new("RGB", (1024, 1024), pal["Bar"][0])
    d = ImageDraw.Draw(img)
    # Welle unten in Akzentfarbe
    wave = [(x, 760 + int(40 * math.sin(x / 1024 * 6.283 * 1.2))) for x in range(0, 1025, 8)]
    d.polygon(wave + [(1024, 1024), (0, 1024)], fill=pal["Sea"][1])
    name = b["displayName"]
    font = None
    for f in FONTS:
        if os.path.exists(f):
            size = 300
            while size > 80:
                font = ImageFont.truetype(f, size)
                if d.textlength(name, font=font) < 820: break
                size -= 20
            break
    d.text((512, 470), name, fill="white", font=font, anchor="mm")
    return img


def main(region, dry):
    spec = S.load(region)
    b = spec["brand"]
    src = Image.open(S.path(b["icon"])).convert("RGB").resize((1024, 1024), Image.LANCZOS) if b.get("icon") else generated(spec)
    ios_dir = S.path(b["id"], "Assets.xcassets", "AppIcon.appiconset")
    android = S.path("android", "app", "src", b["id"], "res", "drawable-nodpi", "ic_launcher_back.png")
    small = src.resize((288, 288), Image.LANCZOS)
    back = Image.new("RGB", (432, 432))
    px, o = small.load(), back.load()
    for y in range(432):
        for x in range(432):
            o[x, y] = px[min(max(x - 72, 0), 287), min(max(y - 72, 0), 287)]
    print(f"+ {os.path.relpath(ios_dir, S.ROOT)}/icon.png\n+ {os.path.relpath(android, S.ROOT)}")
    if dry:
        return
    os.makedirs(ios_dir, exist_ok=True)
    src.save(os.path.join(ios_dir, "icon.png"))
    json.dump({"images": [{"filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
               "info": {"author": "xcode", "version": 1}}, open(os.path.join(ios_dir, "Contents.json"), "w"), indent=2)
    os.makedirs(os.path.dirname(android), exist_ok=True)
    back.save(android)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        raise SystemExit(__doc__)
    main(args[0], "--dry-run" in sys.argv)
