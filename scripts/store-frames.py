#!/usr/bin/env python3
"""Captions Ghost Thread's App Store screenshots.

    scripts/store-frames.py [--only ghosts,line] <captures dir> <out dir>

The captures are scripts/store-capture.sh's screenshots (NN-<moment>.png, at any one App Store size). Each shot in
SHOTS gets its caption in the game's lettering (SF Rounded Black, leaning forward as the game's titles do), in listing
order: the shot a little smaller under a caption band, over a soft, darkened blur of itself, with no device frame. Every
shot is framed this way, since the race's timing, buttons and map run across the top where an overlaid caption would
sit. Modeled on Bigger Fish's scripts/bigger-fish-store-frames.py. Output keeps the captures' size, with no alpha, as
App Store Connect wants. Upload with appstore/push.py media.
"""
import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT = "/System/Library/Fonts/SFNSRounded.ttf"
WEIGHT = "Black"
# How far the letters lean: the logo's slant (Apex/Logo.swift).
SLANT = 0.21

# (capture, caption), in listing order (Kraig, 2026-11-02: the line first): the line it's all about (search often shows
# only the first), the race with its ghosts, a medal, where a lap stands, then the circuits and the unlock.
SHOTS = [
    ("line", "THREAD THE PERFECT LINE"),
    ("ghosts", "RACE YOUR GHOST"),
    ("medal", "WIN EVERY MEDAL"),
    ("standing", "SEE WHERE YOU STAND"),
    ("circuits", "SIX CIRCUITS TO MASTER"),
    ("unlock", "ONE UNLOCK, EVERY CIRCUIT"),
]


def font_for(caption, size, width):
    while True:
        font = ImageFont.truetype(FONT, size)
        font.set_variation_by_name(WEIGHT)
        if font.getlength(caption) <= width:
            return font
        size -= 4


def lean(layer, center_y):
    """Leans a layer's letters forward about their middle line, as an italic would."""
    return layer.transform(layer.size, Image.AFFINE, (1, SLANT, -SLANT * center_y, 0, 1, 0), resample=Image.BICUBIC)


def caption_text(canvas, caption, font, center, unit):
    """The caption, centered and leaning, over a soft shadow of itself."""
    w, h = canvas.size
    shadow = Image.new("RGBA", (w, h))
    ImageDraw.Draw(shadow).text((center[0], center[1] + 6 * unit), caption, font=font, fill=(0, 0, 0, 160), anchor="mm")
    shadow = lean(shadow, center[1]).filter(ImageFilter.GaussianBlur(10 * unit))
    canvas.paste(shadow, (0, 0), shadow)
    letters = Image.new("RGBA", (w, h))
    ImageDraw.Draw(letters).text(center, caption, font=font, fill=(255, 255, 255), anchor="mm")
    letters = lean(letters, center[1])
    canvas.paste(letters, (0, 0), letters)


def frame(shot, caption):
    """The shot shrunk under a caption band, over a soft, darkened blur of itself: no border."""
    w, h = shot.size
    unit = min(w / 2868, h / 1320)
    top = round(h * 0.17)
    sw, sh = round(w * (h - top) / h), h - top
    x = (w - sw) // 2
    full = shot.convert("RGB")
    canvas = full.filter(ImageFilter.GaussianBlur(60 * unit))
    canvas = Image.blend(canvas, Image.new("RGB", (w, h), (0, 0, 0)), 0.45)
    canvas.paste(full.resize((sw, sh), Image.LANCZOS), (x, top))
    font = font_for(caption, round(118 * unit), w * 0.86)
    caption_text(canvas, caption, font, (w // 2, top // 2 + round(4 * unit)), unit)
    return canvas


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--only", help="comma-separated captures to frame (line,medal,...)")
    parser.add_argument("captures", type=Path)
    parser.add_argument("out", type=Path)
    args = parser.parse_args()
    found = {p.stem.split("-", 1)[1]: p for p in args.captures.glob("[0-9][0-9]-*.png")}
    only = set(args.only.split(",")) if args.only else None
    missing = [name for name, _ in SHOTS if name not in found and (not only or name in only)]
    if missing:
        sys.exit(f"missing captures: {', '.join(missing)}")
    args.out.mkdir(parents=True, exist_ok=True)
    if not only:
        # push.py media uploads every PNG in the folder, so a shot no longer in the listing goes.
        current = {f"{index:02d}-{name}.png" for index, (name, _) in enumerate(SHOTS, 1)}
        for stale in args.out.glob("[0-9][0-9]-*.png"):
            if stale.name not in current:
                stale.unlink()
    for index, (name, caption) in enumerate(SHOTS, 1):
        if only and name not in only:
            continue
        with Image.open(found[name]) as shot:
            frame(shot, caption).save(args.out / f"{index:02d}-{name}.png")
    print(f"{args.out}: {len(only) if only else len(SHOTS)} screenshots")


main()
