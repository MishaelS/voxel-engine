"""Draws the intro logo (assets/textures/gui/titleIntroLogo.png): white text
in a blocky font on red, in the style of the original studio logo.

Glyphs are 5 units high with 1-unit strokes, built from rounded rectangles
(white) and holes (red); outer corners round, inner corners nearly square,
stepped joints. Rendered 4x supersampled for smooth edges.

Usage: python3 tools/make_intro_logo.py "https://github.com/MishaelS" assets/textures/gui/titleIntroLogo.png
Needs Pillow. Add glyphs to G for other characters.
"""
import math, sys
from PIL import Image, ImageDraw

BG = (240, 50, 62)
FG = (255, 255, 255)
W, H = 1920, 1080
SS = 4            # supersampling
O = 0.9           # outer corner radius (units)
I = 0.3           # inner corner radius

def R(x0, y0, x1, y1, r=(0, 0, 0, 0)):
    return ("R", x0, y0, x1, y1, r if isinstance(r, tuple) else (r,) * 4)
def X(x0, y0, x1, y1, r=(0, 0, 0, 0)):   # hole
    return ("X", x0, y0, x1, y1, r if isinstance(r, tuple) else (r,) * 4)

# Glyphs on a grid: height 5 units, stroke 1 unit. Corner radii order: tl, tr, br, bl.
G = {
    "o": (5, [R(0, 0, 5, 5, O), X(1, 1, 4, 4, I)]),
    "c": (5, [R(0, 0, 5, 5, (O, 0, 0, O)), X(1, 1, 5, 4, (I, 0, 0, I))]),
    "e": (5, [R(0, 0, 5, 5, (O, O, 0, O)), X(1, 1, 4, 2, I), X(1, 3, 5, 4, (I, 0, 0, I))]),
    "s": (5, [R(0, 0, 5, 5, (O, 0, O, 0)), X(1, 1, 5, 2, (I, 0, 0, I)), X(0, 3, 4, 4, (0, I, I, 0))]),
    "a": (5, [R(0, 0, 5, 5, (0, O, 0, O)), X(0, 1, 4, 2, (0, I, I, 0)), X(1, 3, 4, 4, I)]),
    "g": (5, [R(0, 0, 5, 5, (O, O, O, 0)), X(1, 1, 4, 2, I), X(0, 3, 4, 4, (0, I, I, 0))]),
    "h": (5, [R(0, 0, 1, 5, (O * 0.5, O * 0.5, 0, 0)), R(1, 2, 5, 5, (0, O, 0, 0)), X(1, 3, 4, 5, (I, I, 0, 0))]),
    "n": (5, [R(0, 0, 5, 5, (0, O, 0, 0)), X(1, 1, 4, 5, (I, I, 0, 0))]),
    "u": (5, [R(0, 0, 5, 5, (0, 0, O, O)), X(1, 0, 4, 4, (0, 0, I, I))]),
    "p": (5, [R(0, 0, 5, 4, (O, O, O, 0)), R(0, 3, 1, 5), X(1, 1, 4, 3, I)]),
    "b": (5, [R(0, 0, 1, 2, (O * 0.5, O * 0.5, 0, 0)), R(0, 1, 5, 5, (0, O, O, O)), X(1, 2, 4, 4, I)]),
    "m": (7, [R(0, 0, 7, 5, (O, O, 0, 0)), X(1, 1, 3, 5, (I, I, 0, 0)), X(4, 1, 6, 5, (I, I, 0, 0))]),
    "t": (3, [R(0, 0, 1, 5, (O * 0.5, O * 0.5, 0, O)), R(1, 1, 3, 2), R(1, 4, 3, 5)]),
    "i": (1, [R(0, 0, 1, 1, O * 0.4), R(0, 2, 1, 5, (O * 0.4, O * 0.4, 0, 0))]),
    # l with the stepped foot of the original
    "l": (2, [R(0, 0, 1, 4.2, (O * 0.5, O * 0.5, 0, I)), R(0.55, 4, 2, 5, (I, 0, 0, 0))]),
    ".": (1, [R(0, 4, 1, 5, O * 0.4)]),
    ":": (1, [R(0, 1, 1, 2, O * 0.4), R(0, 4, 1, 5, O * 0.4)]),
    # slash as a staircase of steps
    "/": (3, [R(0, 10 / 3, 1, 5, (I, 0, 0, 0)), R(1, 5 / 3, 2, 10 / 3, (I, 0, I, 0)), R(2, 0, 3, 5 / 3, (0, 0, I, 0))]),
}
G["d"] = (5, [R(4, 0, 5, 2, (O * 0.5, O * 0.5, 0, 0)), R(0, 1, 5, 5, (O, 0, O, O)), X(1, 2, 4, 4, I)])
G["M"] = G["m"]
G["S"] = G["s"]

def rounded_poly(x0, y0, x1, y1, radii):
    pts = []
    corners = [((x0, y0), (1, 1), 180), ((x1, y0), (-1, 1), 270), ((x1, y1), (-1, -1), 0), ((x0, y1), (1, -1), 90)]
    for ((cx, cy), (sx, sy), start), r in zip(corners, radii):
        r = min(r, (x1 - x0) / 2, (y1 - y0) / 2)
        if r <= 0:
            pts.append((cx, cy))
            continue
        ox, oy = cx + sx * r, cy + sy * r
        for k in range(17):
            a = math.radians(start + 90 * k / 16)
            pts.append((ox + r * math.cos(a), oy + r * math.sin(a)))
    return pts

def render(text, out):
    gap = 1.0
    total = sum(G[ch][0] for ch in text) + gap * (len(text) - 1)
    u = 0.86 * W / total
    img = Image.new("RGB", (W * SS, H * SS), BG)
    d = ImageDraw.Draw(img)
    x = (W - total * u) / 2
    y = (H - 5 * u) / 2
    for ch in text:
        width, parts = G[ch]
        for kind, a, b, c, e, r in parts:
            box = [(x + a * u) * SS, (y + b * u) * SS, (x + c * u) * SS, (y + e * u) * SS]
            poly = rounded_poly(*box, [k * u * SS for k in r])
            d.polygon(poly, fill=FG if kind == "R" else BG)
        x += (width + gap) * u
    img.resize((W, H), Image.LANCZOS).save(out)

render(sys.argv[1], sys.argv[2])
