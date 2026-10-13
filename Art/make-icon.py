"""Draws the app icon: the car, big, at the apex of a right-hander. Its inside tires ride the red-and-white curb, its
nose points along the bend, and the yellow racing line swings wide before and after, touching the curb here.

Run with python3 (needs Pillow): writes Apex/Assets.xcassets/AppIcon.appiconset/AppIcon.png at 1024 x 1024, no alpha.
"""
import math, os
from PIL import Image, ImageDraw, ImageFilter

S = 4  # supersampling
N = 1024 * S

RED, WHITE, YELLOW = (219, 18, 18), (246, 246, 246), (255, 210, 30)
TIRE, CARBON, ASPHALT, GRASS = (20, 20, 22), (44, 44, 48), (60, 62, 68), (76, 140, 66)

img = Image.new("RGB", (N, N), ASPHALT)
d = ImageDraw.Draw(img)


def P(x, y):
    return (x * S, y * S)


def arc(cx, cy, r, a0, a1, n=400):
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * k / n)),
             cy + r * math.sin(math.radians(a0 + (a1 - a0) * k / n))) for k in range(n + 1)]


def stroke(points, width, fill):
    """A smooth round-ended stroke: a disc stamped every couple of pixels along the points."""
    r = width * S / 2
    dense = []
    for a, b in zip(points, points[1:]):
        steps = max(1, int(math.dist(a, b) / 2))
        dense += [(a[0] + (b[0] - a[0]) * k / steps, a[1] + (b[1] - a[1]) * k / steps) for k in range(steps)]
    for x, y in dense + points[-1:]:
        d.ellipse([x * S - r, y * S - r, x * S + r, y * S + r], fill=fill)


# The corner: its centre is off the bottom right, so the car's path (curb radius plus how far it sits off the curb)
# passes through the middle of the icon heading up and to the right.
CAR_AT, CAR_SCALE, HEADING = (512, 512), 23, math.radians(-45)  # px, px per car unit, nose direction
CURB_RADIUS, OFF_CURB, LINE_BOW = 560, 130, 650
diag = math.sqrt(0.5)
path_radius = CURB_RADIUS + OFF_CURB
cx, cy = CAR_AT[0] + path_radius * diag, CAR_AT[1] + path_radius * diag

# Grass on the inside, edged with curb blocks.
d.ellipse([(cx - CURB_RADIUS) * S, (cy - CURB_RADIUS) * S, (cx + CURB_RADIUS) * S, (cy + CURB_RADIUS) * S], fill=GRASS)
edge = arc(cx, cy, CURB_RADIUS, 140, 310, 1200)
travelled = 0.0
for (x0, y0), (x1, y1) in zip(edge, edge[1:]):
    length = math.dist((x0, y0), (x1, y1))
    nx, ny = -(y1 - y0) / length, (x1 - x0) / length  # toward the corner's centre
    color = RED if int(travelled / 64) % 2 == 0 else WHITE
    d.polygon([P(x0, y0), P(x1, y1), P(x1 + nx * 64, y1 + ny * 64), P(x0 + nx * 64, y0 + ny * 64)], fill=color)
    travelled += length

# The racing line: a wider circle that only meets the car's path at the apex.
stroke(arc(cx + LINE_BOW * diag, cy + LINE_BOW * diag, path_radius + LINE_BOW, 190, 260), 22, YELLOW)


# The car, as the game draws it (CarArt in Livery.swift): nose to +x, in car units (34 long).
def rounded_rect(x, y, w, h, r, steps=6):
    points = []
    for corner_x, corner_y, start in [(x + w - r, y + r, -90), (x + w - r, y + h - r, 0), (x + r, y + h - r, 90),
                                      (x + r, y + r, 180)]:
        points += [(corner_x + r * math.cos(math.radians(start + 90 * k / steps)),
                    corner_y + r * math.sin(math.radians(start + 90 * k / steps))) for k in range(steps + 1)]
    return points


def ellipse(x, y, w, h, steps=48):
    return [(x + w / 2 + w / 2 * math.cos(2 * math.pi * k / steps), y + h / 2 + h / 2 * math.sin(2 * math.pi * k / steps))
            for k in range(steps)]


body = [(-14.5, -2.6), (-9, -4.9), (0, -4.9), (4.5, -2.2), (15, -1.1), (15, 1.1), (4.5, 2.2), (0, 4.9), (-9, 4.9),
        (-14.5, 2.6)]
pieces = [
    (TIRE, rounded_rect(-14.5, 3.6, 8, 4.1, 0.8)), (TIRE, rounded_rect(-14.5, -7.7, 8, 4.1, 0.8)),
    (TIRE, rounded_rect(5.5, 3.9, 6.5, 3.6, 0.8)), (TIRE, rounded_rect(5.5, -7.5, 6.5, 3.6, 0.8)),
    (CARBON, rounded_rect(-17.5, -6.2, 3.4, 12.4, 0.5)),
    (RED, rounded_rect(14.1, -6.6, 3.4, 13.2, 0.5)),
    (RED, body),
    (WHITE, rounded_rect(-13, -0.7, 27, 1.4, 0.3)),
    (CARBON, ellipse(-5.5, -2, 7, 4)),
    (YELLOW, ellipse(-3.6, -1.6, 3.2, 3.2)),
]


def car(point, dx=0, dy=0):
    u, v = point[0] * CAR_SCALE, point[1] * CAR_SCALE
    return P(CAR_AT[0] + u * math.cos(HEADING) - v * math.sin(HEADING) + dx,
             CAR_AT[1] + u * math.sin(HEADING) + v * math.cos(HEADING) + dy)


# A soft shadow down and to the right lifts the car off the track.
shadow = Image.new("L", (N, N), 0)
sd = ImageDraw.Draw(shadow)
for _, points in pieces[:6] + [(None, body)]:
    sd.polygon([car(p, 14, 18) for p in points], fill=255)
img.paste((0, 0, 0), (0, 0), shadow.filter(ImageFilter.GaussianBlur(6 * S)).point(lambda v: v * 0.45))

for color, points in pieces:
    d.polygon([car(p) for p in points], fill=color)
# A highlight along the sidepod, so the car reads as a shape rather than a sticker.
d.polygon([car(p) for p in [(-9, -4.4), (0, -4.4), (3.5, -2.4), (-8, -2.6)]], fill=(255, 39, 39))

out = img.resize((1024, 1024), Image.LANCZOS)
here = os.path.dirname(os.path.abspath(__file__))
path = os.path.join(here, "..", "Apex", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")
os.makedirs(os.path.dirname(path), exist_ok=True)
out.save(path)
print(os.path.normpath(path))
