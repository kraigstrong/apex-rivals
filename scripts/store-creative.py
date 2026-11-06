#!/usr/bin/env python3
"""Ghost Thread's App Store header and search results images (iOS 27's creative assets), from a race frame.

    scripts/store-creative.py <frame.png> <out.png> --placement header|search --focus X,Y [--zoom Z] [--logo]
        [--tagline TEXT] [--phone FILE]

The frame is a moment drawn with no HUD, bigger than the screen (scripts/store-capture.sh's moments with
`-ApexStoreCaptureScale`, README: App Store screenshots). A 16:9 window of it, 1/`--zoom` of its width, around `--focus`
(fractions of its width and height), becomes the 5244x2950 PNG App Store Connect takes for both placements. `--logo`
puts the GHOST THREAD logo across the middle (Art/site/logo-large.png, drawn by the game's SiteArtTests), and
`--tagline` a short phrase in the screenshots' lettering.

An iPhone shows only part of the image, and a different part in each placement (`PHONE`), so the logo or tagline has
to fit inside it, and so does what the picture is of. The script says when the logo or tagline doesn't, and `--phone`
saves what an iPhone shows, with what covers it there, to check before uploading.
"""
import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SIZE = (5244, 2950)
LOGO = Path(__file__).resolve().parent.parent / "Art/site/logo-large.png"
# The screenshots' lettering (scripts/store-frames.py): SF Rounded Black, leaning as the logo does.
FONT = "/System/Library/Fonts/SFNSRounded.ttf"
SLANT = 0.21

# What an iPhone shows of a 5244x2950 image, as fractions of it (left, top, right, bottom), measured from App Store
# Connect's iPhone preview of 1.0 (2026-11-05). Apple publishes no crops; check its preview after uploading.
PHONE = {
    # The product page's top: the middle 54% of the width, down to where the sheet with the icon starts. The top 15% is
    # under the status bar's blur, and the back and share buttons sit below that, at the sides.
    "header": (0.232, 0.0, 0.770, 0.630),
    # A search result's card: 3:2, the middle 41% of the width, above the middle.
    "search": (0.294, 0.143, 0.706, 0.629),
}
HEADER_BLUR = 0.153  # how far down the status bar's blur reaches
HEADER_BUTTONS = ((0.253, 0.147, 0.317, 0.261), (0.685, 0.147, 0.749, 0.261))  # back and share
# Where a logo or tagline is clear of all that, with a margin.
CLEAR = {"header": (0.26, 0.29, 0.74, 0.60), "search": (0.32, 0.17, 0.68, 0.60)}


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


def logo(canvas, center_y, share):
    """The GHOST THREAD logo, `share` of the width, centered across the image, over a soft dark band: GHOST is
    see-through, as the ghost car is, and a shadow under it would turn it gray. Returns where the logo is."""
    with Image.open(LOGO) as art:
        art = art.convert("RGBA")
        width = round(canvas.width * share)
        art = art.resize((width, round(art.height * width / art.width)), Image.LANCZOS)
    pad = round(width * 0.07)
    band = Image.new("RGBA", canvas.size)
    ImageDraw.Draw(band).rounded_rectangle(
        ((canvas.width - width) // 2 - pad, round(center_y - art.height / 2) - pad * 3 // 4,
         (canvas.width + width) // 2 + pad, round(center_y + art.height / 2) + pad * 3 // 4), radius=pad,
        fill=(0, 0, 0, 105))
    canvas.alpha_composite(band.filter(ImageFilter.GaussianBlur(pad)))
    left, top = (canvas.width - art.width) // 2, round(center_y - art.height / 2)
    canvas.alpha_composite(art, (left, top))
    return left, top, left + art.width, top + art.height


def tagline(canvas, text, center_y, size):
    """A short phrase across the image, `size` of its height, leaning, in white. Returns where the phrase is."""
    font = ImageFont.truetype(FONT, round(canvas.height * size))
    font.set_variation_by_name("Black")
    layer = Image.new("RGBA", canvas.size)
    ImageDraw.Draw(layer).text((canvas.width // 2, center_y), text, font=font, fill=(255, 255, 255, 255), anchor="mm")
    layer = layer.transform(canvas.size, Image.AFFINE, (1, SLANT, -SLANT * center_y, 0, 1, 0), resample=Image.BICUBIC)
    box = layer.getbbox()
    shadowed(canvas, layer, round(14 * size / 0.085), round(28 * size / 0.085))
    return box


def check(placement, box, what):
    """Says when `box` (pixels) isn't clear of what covers an iPhone's view in `placement`."""
    w, h = SIZE
    left, top, right, bottom = CLEAR[placement]
    inside = (box[0] >= left * w and box[1] >= top * h and box[2] <= right * w and box[3] <= bottom * h)
    if not inside:
        print(f"warning: the {what} ({box[0] / w:.2f}-{box[2] / w:.2f} across, {box[1] / h:.2f}-{box[3] / h:.2f} down) "
              f"isn't inside what an iPhone shows clearly in {placement} ({left}-{right} across, {top}-{bottom} down)")


def phone(picture, placement):
    """What an iPhone shows of `picture` in `placement`: the header under the status bar's blur and the buttons, or a
    search result's card with its rounded corners."""
    w, h = picture.size
    left, top, right, bottom = PHONE[placement]
    box = (round(left * w), round(top * h), round(right * w), round(bottom * h))
    view = picture.crop(box).convert("RGBA")
    if placement == "header":
        blur_h = round(HEADER_BLUR * h)
        blurred = view.crop((0, 0, view.width, blur_h * 2)).filter(ImageFilter.GaussianBlur(60))
        fade = Image.linear_gradient("L").resize((view.width, blur_h * 2)).point(lambda v: 255 - v)
        view.paste(blurred, (0, 0), fade)
        draw = ImageDraw.Draw(view)
        for bl, bt, br, bb in HEADER_BUTTONS:
            draw.ellipse((round(bl * w) - box[0], round(bt * h) - box[1], round(br * w) - box[0], round(bb * h) - box[1]),
                         fill=(236, 236, 236, 235))
    else:
        mask = Image.new("L", view.size)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, view.width - 1, view.height - 1), radius=round(view.width * 0.04),
                                               fill=255)
        card = Image.new("RGBA", view.size, (255, 255, 255, 255))
        card.paste(view, (0, 0), mask)
        view = card
    return view.convert("RGB")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("frame", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--placement", choices=sorted(PHONE), required=True, help="where the image goes")
    parser.add_argument("--focus", default="0.5,0.5", help="the window's middle, as fractions of the frame: x,y")
    parser.add_argument("--zoom", type=float, default=1.0, help="how much closer than the whole frame's width")
    parser.add_argument("--logo", action="store_true", help="the logo across the middle")
    parser.add_argument("--logo-y", type=float, default=0.36, help="where the logo sits, as a fraction of the height")
    parser.add_argument("--logo-width", type=float, default=0.30, help="the logo's width, as a fraction of the width")
    parser.add_argument("--tagline", help="a short phrase across the image")
    parser.add_argument("--tagline-y", type=float, default=0.27, help="where the tagline sits, as a fraction of the height")
    parser.add_argument("--tagline-size", type=float, default=0.055, help="its lettering, as a fraction of the height")
    parser.add_argument("--phone", type=Path, help="also save what an iPhone shows of it")
    args = parser.parse_args()

    with Image.open(args.frame) as frame:
        canvas = window(frame.convert("RGB"), tuple(float(v) for v in args.focus.split(",")), args.zoom).convert("RGBA")
    if args.logo:
        check(args.placement, logo(canvas, canvas.height * args.logo_y, args.logo_width), "logo")
    if args.tagline:
        check(args.placement, tagline(canvas, args.tagline, canvas.height * args.tagline_y, args.tagline_size), "tagline")
    picture = canvas.convert("RGB")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    picture.save(args.out)
    if args.phone:
        phone(picture, args.placement).save(args.phone)
    print(f"{args.out}: {picture.width}x{picture.height}")


main()
