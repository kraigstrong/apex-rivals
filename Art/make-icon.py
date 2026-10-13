"""Draws the app icon: an S-bend running left to right, as the game shows it, with curbs on the inside of each bend,
the racing line cutting nearly straight through it (straight is fast), and the car mid-S.

Run with python3 (needs Pillow): writes Apex/Assets.xcassets/AppIcon.appiconset/AppIcon.png at 1024 x 1024, no alpha.
"""
import math, os
from PIL import Image, ImageDraw

S = 4  # supersampling
N = 1024 * S
img = Image.new("RGB", (N, N), (76, 133, 66))
d = ImageDraw.Draw(img)

# Mown stripes, like the trackside in the game.
for k in range(-12, 24):
    x = k * 150 * S
    d.polygon([(x, 0), (x + 75 * S, 0), (x + 75 * S - N * 0.36, N), (x - N * 0.36, N)], fill=(84, 145, 72))

def P(x, y):
    return (x * S, y * S)

# The S: the road runs left to right, dropping from upper left to lower right through two bends.
TOP, DROP, START, SPAN = 300, 430, 120, 790
W = 280  # road width

def center(x):
    """Centerline y at x, and its slope: a smoothstep from TOP down to TOP + DROP."""
    u = min(max((x - START) / SPAN, 0), 1)
    y = TOP + DROP * (u * u * (3 - 2 * u))
    dy = DROP * 6 * u * (1 - u) / SPAN if 0 < u < 1 else 0
    return y, dy

def edge(x, offset):
    """A point `offset` across the road from the centerline at x (positive is toward the bottom of the icon)."""
    y, dy = center(x)
    n = math.hypot(1, dy)
    return (x - dy / n * offset, y + 1 / n * offset)

xs = [x / 2 for x in range(-200, 2300)]
upper = [edge(x, -W / 2) for x in xs]
lower = [edge(x, W / 2) for x in xs]
d.polygon([P(*p) for p in upper] + [P(*p) for p in reversed(lower)], fill=(66, 68, 74))

def stroke(points, width, fill):
    """A smooth round-ended stroke: a disc stamped every couple of pixels along the points."""
    r = width * S / 2
    dense = []
    for a, b in zip(points, points[1:]):
        steps = max(1, int(math.dist(a, b) / 2))
        dense += [(a[0] + (b[0] - a[0]) * k / steps, a[1] + (b[1] - a[1]) * k / steps) for k in range(steps)]
    for x, y in dense + points[-1:]:
        d.ellipse([x * S - r, y * S - r, x * S + r, y * S + r], fill=fill)

# Curbs on the inside of each bend: the lower edge through the first, the upper edge through the second.
def curb(x0, x1, side, blocks):
    for b in range(blocks):
        a, z = x0 + (x1 - x0) * b / blocks, x0 + (x1 - x0) * (b + 1) / blocks
        span = [a + (z - a) * k / 20 for k in range(21)]
        outer = [edge(x, side * W / 2) for x in span]
        inner = [edge(x, side * (W / 2 - 32)) for x in reversed(span)]
        d.polygon([P(*p) for p in outer + inner], fill=(222, 38, 38) if b % 2 == 0 else (246, 246, 246))

curb(START + 40, START + SPAN * 0.42, 1, 8)
curb(START + SPAN * 0.58, START + SPAN - 40, -1, 8)

stroke(upper, 12, (214, 218, 226))
stroke(lower, 12, (214, 218, 226))

# The racing line: wide at the top on the way in, clipping each curb, wide at the bottom on the way out. Through an
# S it's nearly straight.
def catmull(points, samples=80):
    out = []
    for i in range(len(points) - 3):
        p0, p1, p2, p3 = points[i:i + 4]
        for k in range(samples):
            u = k / samples
            out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * u + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * u * u
                                    + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * u ** 3) for j in range(2)))
    return out

apex1 = edge(START + SPAN * 0.25, W / 2 - 44)
apex2 = edge(START + SPAN * 0.75, -(W / 2 - 44))
line = catmull([edge(-260, -(W / 2 - 46)), edge(-60, -(W / 2 - 46)), apex1, apex2,
                edge(START + SPAN + 180, W / 2 - 46), edge(START + SPAN + 380, W / 2 - 46)])
stroke(line, 28, (255, 205, 32))
for apex in (apex1, apex2):
    r = 34
    d.ellipse([P(apex[0] - r, apex[1] - r), P(apex[0] + r, apex[1] + r)], fill=(255, 205, 32), outline=(28, 30, 36),
              width=8 * S)

# The car, mid-S on the line, heading right.
k = int(len(line) * 0.5)
(x0, y0), (x1, y1) = line[k - 3], line[k + 3]
h = math.atan2(y1 - y0, x1 - x0)
cx0, cy0 = line[k]
SCALE = 5.6  # px per car unit (the car is 34 long)

def car(px, py):
    u, v = px * SCALE, py * SCALE
    return P(cx0 + u * math.cos(h) - v * math.sin(h), cy0 + u * math.sin(h) + v * math.cos(h))

def box(x, y, w, hgt, fill):
    d.polygon([car(x, y), car(x + w, y), car(x + w, y + hgt), car(x, y + hgt)], fill=fill)

tire, carbon, livery = (18, 18, 20), (40, 40, 44), (230, 30, 26)
box(-14.5, 3.6, 8, 4.1, tire); box(-14.5, -7.7, 8, 4.1, tire)
box(5.5, 3.9, 6.5, 3.6, tire); box(5.5, -7.5, 6.5, 3.6, tire)
box(-17.5, -6.2, 3.4, 12.4, carbon); box(14.1, -6.6, 3.4, 13.2, livery)
d.polygon([car(*q) for q in [(-14.5, -2.6), (-9, -4.9), (0, -4.9), (4.5, -2.2), (15, -1.1), (15, 1.1), (4.5, 2.2),
                             (0, 4.9), (-9, 4.9), (-14.5, 2.6)]], fill=livery)
box(-13, -0.7, 27, 1.4, (250, 250, 250))
hx, hy = car(-2, 0)
hr = 1.7 * SCALE * S
d.ellipse([hx - hr, hy - hr, hx + hr, hy + hr], fill=(255, 215, 30))

out = img.resize((1024, 1024), Image.LANCZOS)
here = os.path.dirname(os.path.abspath(__file__))
path = os.path.join(here, "..", "Apex", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")
os.makedirs(os.path.dirname(path), exist_ok=True)
out.save(path)
print(os.path.normpath(path))
