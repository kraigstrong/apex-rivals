"""Draws the app icon: a right-angle corner on mown grass, a kerb on its inside, and the racing line clipping the apex.

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

# The corner's centerline: up the left, a right-hand bend, out along the top.
cx, cy, R = 600, 560, 270          # bend centre and radius
W = 300                            # road width
def centerline(t):
    """t in [0, 3]: 0-1 the entry straight, 1-2 the bend, 2-3 the exit straight."""
    if t <= 1:
        return (cx - R, 1150 - (1150 - cy) * t), math.pi / 2
    if t <= 2:
        a = math.pi - (t - 1) * math.pi / 2
        return (cx + R * math.cos(a), cy - R * math.sin(a)), a - math.pi / 2
    return (cx + (1150 - cx) * (t - 2), cy - R), 0.0

def edge(offset, t):
    """A point `offset` across the road from the centerline (negative is the outside of the bend)."""
    (x, y), h = centerline(t)
    return (x + math.sin(h) * offset, y + math.cos(h) * offset)


def stroke(points, width, fill):
    """A smooth round-ended stroke: a disc stamped every couple of pixels along the points."""
    r = width * S / 2
    dense = []
    for a, b in zip(points, points[1:]):
        steps = max(1, int(math.dist(a, b) / 2))
        dense += [(a[0] + (b[0] - a[0]) * k / steps, a[1] + (b[1] - a[1]) * k / steps) for k in range(steps)]
    for x, y in dense + points[-1:]:
        d.ellipse([x * S - r, y * S - r, x * S + r, y * S + r], fill=fill)

ts = [i / 200 for i in range(601)]
left = [edge(-W / 2, t) for t in ts]     # outside of the bend
right = [edge(W / 2, t) for t in ts]     # inside of the bend
road = [P(*p) for p in left] + [P(*p) for p in reversed(right)]
d.polygon(road, fill=(66, 68, 74))

# Kerb on the inside of the bend: red and white blocks.
blocks = 14
for b in range(blocks):
    t0 = 0.88 + b * (1.24 / blocks)
    t1 = t0 + 1.24 / blocks
    seg = [i / 40 for i in range(41)]
    outer = [edge(W / 2, t0 + (t1 - t0) * u) for u in seg]
    inner = [edge(W / 2 - 34, t0 + (t1 - t0) * u) for u in reversed(seg)]
    d.polygon([P(*p) for p in outer + inner], fill=(222, 38, 38) if b % 2 == 0 else (246, 246, 246))

# Barrier lines along both edges.
stroke(left, 12, (214, 218, 226))
stroke(right, 12, (214, 218, 226))

# The racing line: wide on entry, the apex on the inside kerb, wide on exit (a smooth curve through those points).
def catmull(points, samples=60):
    out = []
    for i in range(len(points) - 3):
        p0, p1, p2, p3 = points[i:i + 4]
        for k in range(samples):
            u = k / samples
            out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * u + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * u * u
                                    + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * u ** 3) for j in range(2)))
    return out

apex = edge(W / 2 - 52, 1.5)
line = catmull([edge(-W / 2 + 46, -0.4), edge(-W / 2 + 46, 0.15), edge(-W / 2 + 60, 0.62), apex,
                edge(-W / 2 + 60, 2.38), edge(-W / 2 + 46, 2.85), edge(-W / 2 + 46, 3.4)])
stroke(line, 30, (255, 205, 32))

# The car, powering out of the corner along the line.
k = int(len(line) * 0.70)
(x0, y0), (x1, y1) = line[k - 3], line[k + 3]
h = math.atan2(y1 - y0, x1 - x0)
cx0, cy0 = line[k]
def car(px, py):
    """A point of the car (nose along +x, 4.6 px per unit of its 34-unit length) placed on the line."""
    u, v = px * 4.6, py * 4.6
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
d.ellipse([hx - 1.7 * 4.6 * S, hy - 1.7 * 4.6 * S, hx + 1.7 * 4.6 * S, hy + 1.7 * 4.6 * S], fill=(255, 215, 30))

r = 40
d.ellipse([P(apex[0] - r, apex[1] - r), P(apex[0] + r, apex[1] + r)], fill=(255, 205, 32), outline=(28, 30, 36),
          width=9 * S)

out = img.resize((1024, 1024), Image.LANCZOS)
here = os.path.dirname(os.path.abspath(__file__))
path = os.path.join(here, "..", "Apex", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")
os.makedirs(os.path.dirname(path), exist_ok=True)
out.save(path)
print(path)
