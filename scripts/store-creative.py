#!/usr/bin/env python3
"""Ghost Thread's App Store header and search results images (iOS 27's creative assets), from a race frame.

    scripts/store-creative.py <frame.png> <out.png> --focus X,Y [--zoom Z] [--logo] [--tagline TEXT] [--phone FILE]

The frame is a moment drawn with no HUD, bigger than the screen (scripts/store-capture.sh's moments with
`-ApexStoreCaptureScale`, README: App Store screenshots). A 16:9 window of it, 1/`--zoom` of its width, around `--focus`
(fractions of its width and height), becomes the 5244x2950 PNG App Store Connect takes for both placements; the race's
camera keeps the car in the left third, so the focus brings it in toward the middle, as Apple asks. `--logo` puts the
GHOST THREAD logo across the top middle (`--logo-y`) (Art/site/logo-large.png, drawn by the game's SiteArtTests), and `--tagline`
a short phrase in the screenshots' lettering. `--phone` saves the part an iPhone shows of a header (its middle half,
and the top 60% or so), to check before uploading.
"""
import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SIZE = (5244, 2950)
LOGO = Path(__file__).resolve().parent.parent / "Art/site/logo-large.png"
# The screenshots' lettering (scripts/store-frames.py): SF Rounded Black, leaning as the logo does.
FONT = "/System/Library/Fonts/SFNSRounded.ttf"
SLANT = 0.21


def window(frame, focus, zoom):
    """The 16:9 crop of `frame`, 1/`zoom` of its width, centered on `focus` as far as the frame allows."""
    width = round(frame.width / zoom)
    height = round(width * SIZE[1] / SIZE[0])
    if height > frame.height:
        height = frame.height
        width = round(height * SIZE[0] / SIZE[1])
    left = min(max(0, round(focus[0] * frame.width - width / 2)), frame.width - width)
    top = min(max(0, round(focus[1] * frame.height - height / 2)), frame.height - height)
    return frame.crop((left, top, left + width, top + height)).resize(SIZE, Image.LANCZOS)


def shadowed(canvas, layer, offset, blur):
    """Pastes `layer` over a soft dark shadow of itself."""
    shadow = Image.new("RGBA", canvas.size)
    alpha = layer.getchannel("A").point(lambda a: a * 0.65)
    shadow.paste((0, 0, 0, 255), (0, 0), alpha)
    shadow = shadow.transform(canvas.size, Image.AFFINE, (1, 0, 0, 0, 1, -offset)).filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(layer)


def logo(canvas, center_y):
    """The GHOST THREAD logo, 46% of the width, centered across the image, over a soft dark band: GHOST is see-through,
    as the ghost car is, and a shadow under it would turn it gray."""
    with Image.open(LOGO) as art:
        art = art.convert("RGBA")
        width = round(canvas.width * 0.46)
        art = art.resize((width, round(art.height * width / art.width)), Image.LANCZOS)
    band = Image.new("RGBA", canvas.size)
    ImageDraw.Draw(band).rounded_rectangle(
        ((canvas.width - width) // 2 - 160, round(center_y - art.height / 2) - 120,
         (canvas.width + width) // 2 + 160, round(center_y + art.height / 2) + 120), radius=200, fill=(0, 0, 0, 105))
    canvas.alpha_composite(band.filter(ImageFilter.GaussianBlur(150)))
    canvas.alpha_composite(art, ((canvas.width - art.width) // 2, round(center_y - art.height / 2)))


def tagline(canvas, text, center_y):
    """A short phrase across the image, leaning, in white."""
    font = ImageFont.truetype(FONT, round(canvas.height * 0.085))
    font.set_variation_by_name("Black")
    layer = Image.new("RGBA", canvas.size)
    ImageDraw.Draw(layer).text((canvas.width // 2, center_y), text, font=font, fill=(255, 255, 255, 255), anchor="mm")
    layer = layer.transform(canvas.size, Image.AFFINE, (1, SLANT, -SLANT * center_y, 0, 1, 0), resample=Image.BICUBIC)
    shadowed(canvas, layer, 14, 28)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("frame", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--focus", default="0.5,0.5", help="the window's middle, as fractions of the frame: x,y")
    parser.add_argument("--zoom", type=float, default=1.0, help="how much closer than the whole frame's width")
    parser.add_argument("--logo", action="store_true", help="the logo across the top middle")
    parser.add_argument("--logo-y", type=float, default=0.30, help="where the logo sits, as a fraction of the height")
    parser.add_argument("--tagline", help="a short phrase across the image")
    parser.add_argument("--tagline-y", type=float, default=0.17, help="where the tagline sits, as a fraction of the height")
    parser.add_argument("--phone", type=Path, help="also save what an iPhone shows of a header")
    args = parser.parse_args()

    with Image.open(args.frame) as frame:
        canvas = window(frame.convert("RGB"), tuple(float(v) for v in args.focus.split(",")), args.zoom).convert("RGBA")
    if args.logo:
        logo(canvas, canvas.height * args.logo_y)
    if args.tagline:
        tagline(canvas, args.tagline, canvas.height * args.tagline_y)
    picture = canvas.convert("RGB")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    picture.save(args.out)
    if args.phone:
        w, h = picture.size
        picture.crop((w // 4, 0, w * 3 // 4, round(h * 0.6))).save(args.phone)
    print(f"{args.out}: {picture.width}x{picture.height}")


main()
