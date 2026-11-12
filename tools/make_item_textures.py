"""Draws our own item-related pictures (simple pixel art):
- assets/textures/misc/dial.png: the clock's dial (16 x 16), turned by the
  time of day behind the clock icon's window (ItemAnimations): the day sky
  with the sun on top, the night with the moon below, like the classic
  clock.
- assets/textures/misc/mapbg.png: the parchment a map is drawn
  on in hand;
- assets/textures/environment/rain.png and snow.png: the falling rain
  streaks and snowflakes the weather draws (64 x 64, repeating);
- assets/textures/art/kz.png: our own paintings (at the places of Beta 1.7.3's) (little landscapes,
  256 x 256, 16 pixels per block) at the places PAINTINGS lists (the same
  table as scripts/entities/painting.gd); the cell at the top right is
  the wooden back.
Files that are already there are kept (add --force to redraw them).

Usage: python3 tools/make_item_textures.py assets/textures [--force]
Needs Pillow and numpy.
"""
import os
import sys
import zlib

import numpy as np
from PIL import Image

FORCE = "--force" in sys.argv
rng = np.random.default_rng(11)


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if FORCE or not os.path.exists(path):
        Image.fromarray(img).save(path)


def dial(root):
    img = np.zeros((16, 16, 4), np.uint8)
    for y in range(16):
        for x in range(16):
            day = y < 8
            base = np.array((110, 160, 230) if day else (20, 26, 60), float)
            # Lighter toward the horizon in the middle.
            base = base * (0.8 + 0.25 * (1 - abs(y - 7.5) / 7.5))
            img[y, x, :3] = np.clip(base + rng.integers(-6, 7), 0, 255)
            img[y, x, 3] = 255
    # The horizon: a strip of land.
    img[7:9, :, :3] = (70, 110, 40)
    # Sun on top, moon at the bottom.
    img[1:4, 6:10, :3] = (255, 230, 80)
    img[2:3, 7:9, :3] = (255, 250, 170)
    img[12:15, 6:10, :3] = (220, 220, 230)
    img[13, 6, :3] = (160, 160, 180)
    # Stars.
    for x, y in ((2, 11), (13, 12), (4, 14), (11, 10)):
        img[y, x, :3] = (230, 230, 250)
    save(img, os.path.join(root, "misc", "dial.png"))


def map_background(root):
    n = 142
    img = np.zeros((n, n, 4), np.uint8)
    for y in range(n):
        for x in range(n):
            edge = min(x, y, n - 1 - x, n - 1 - y)
            base = np.array((222, 204, 160), float) * (0.82 if edge < 4 else 1.0)
            if edge < 2:
                base = np.array((120, 90, 60), float)
            k = 1 + rng.uniform(-0.05, 0.05)
            img[y, x, :3] = np.clip(base * k, 0, 255)
            img[y, x, 3] = 255
    save(img, os.path.join(root, "misc", "mapbg.png"))


# name: (width, height in blocks, cell x, cell y, scene)
PAINTINGS = {
    "sunrise": (1, 1, 0, 0, dict(sky=((250, 170, 90), (120, 150, 220)), ground=(70, 120, 50), horizon=0.7, sun=(0.5, 0.62))),
    "lake": (1, 1, 1, 0, dict(sky=((150, 190, 240), (90, 140, 220)), ground=(60, 110, 50), horizon=0.5, water=0.65)),
    "flower": (1, 1, 2, 0, dict(sky=((60, 90, 70), (40, 60, 50)), flower=True)),
    "tower": (1, 1, 3, 0, dict(sky=((170, 200, 240), (110, 150, 220)), ground=(90, 130, 60), horizon=0.75, tower=True)),
    "moon": (1, 1, 4, 0, dict(sky=((20, 24, 60), (40, 50, 100)), ground=(20, 40, 30), horizon=0.8, moon=(0.65, 0.3), stars=6)),
    "forest_path": (1, 1, 5, 0, dict(sky=((140, 190, 230), (100, 150, 210)), ground=(80, 120, 50), horizon=0.55, trees=3, path=True)),
    "star": (1, 1, 6, 0, dict(sky=((10, 10, 30), (30, 20, 60)), stars=10, big_star=True)),
    "hills": (2, 1, 0, 1, dict(sky=((160, 200, 240), (100, 150, 220)), ground=(90, 150, 60), horizon=0.6, hills=3)),
    "sea": (2, 1, 2, 1, dict(sky=((170, 210, 245), (110, 160, 230)), ground=(40, 90, 170), horizon=0.5, water=0.5, boat=True)),
    "desert": (2, 1, 4, 1, dict(sky=((250, 220, 150), (120, 170, 230)), ground=(220, 200, 130), horizon=0.6, sun=(0.75, 0.3), cactus=2)),
    "road": (2, 1, 6, 1, dict(sky=((160, 200, 240), (110, 160, 220)), ground=(90, 140, 60), horizon=0.5, path=True, trees=2)),
    "clouds": (2, 1, 8, 1, dict(sky=((130, 180, 240), (80, 130, 220)), clouds=4)),
    "waterfall": (1, 2, 0, 2, dict(sky=((150, 190, 240), (100, 140, 210)), ground=(100, 100, 100), horizon=0.3, waterfall=True)),
    "tree": (1, 2, 1, 2, dict(sky=((170, 210, 240), (120, 170, 230)), ground=(80, 130, 50), horizon=0.8, big_tree=True)),
    "mountain": (2, 2, 2, 2, dict(sky=((170, 205, 240), (110, 150, 225)), ground=(80, 130, 60), horizon=0.7, mountains=2)),
    "village": (2, 2, 4, 2, dict(sky=((180, 210, 240), (120, 170, 230)), ground=(90, 140, 60), horizon=0.6, houses=3, trees=2)),
    "storm": (2, 2, 6, 2, dict(sky=((70, 70, 90), (110, 110, 130)), ground=(50, 80, 50), horizon=0.75, clouds=5, lightning=True, dark_clouds=True)),
    "garden": (2, 2, 8, 2, dict(sky=((160, 200, 240), (120, 170, 230)), ground=(70, 130, 50), horizon=0.4, flowers=14, trees=1)),
    "panorama": (4, 2, 0, 4, dict(sky=((250, 180, 120), (110, 140, 220)), ground=(70, 120, 50), horizon=0.62, mountains=3, sun=(0.2, 0.45), water=0.8)),
    "river_valley": (4, 3, 0, 6, dict(sky=((160, 200, 240), (100, 150, 220)), ground=(80, 140, 60), horizon=0.45, hills=4, river=True, trees=5)),
    "night_sky": (4, 4, 0, 9, dict(sky=((10, 12, 40), (40, 40, 90)), ground=(20, 35, 25), horizon=0.85, stars=40, moon=(0.75, 0.2), mountains=2, night=True)),
    "volcano": (4, 4, 4, 9, dict(sky=((90, 40, 40), (200, 110, 70)), ground=(50, 40, 40), horizon=0.8, volcano=True, clouds=3, dark_clouds=True)),
}


def scene(w, h, spec):
    srng = np.random.default_rng(zlib.crc32(repr(sorted(spec.items())).encode()))  # the same every run
    img = np.zeros((h, w, 3), float)
    top, bottom = [np.array(c, float) for c in spec["sky"]]
    for y in range(h):
        img[y, :] = top + (bottom - top) * (y / max(h - 1, 1))
    horizon = int(h * spec.get("horizon", 1.0))

    def rect(x0, y0, x1, y1, color):
        x0, y0, x1, y1 = max(int(x0), 0), max(int(y0), 0), min(int(x1), w), min(int(y1), h)
        if x1 > x0 and y1 > y0:
            img[y0:y1, x0:x1] = color

    def disc(cx, cy, r, color):
        for y in range(max(int(cy - r), 0), min(int(cy + r) + 1, h)):
            for x in range(max(int(cx - r), 0), min(int(cx + r) + 1, w)):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                    img[y, x] = color

    for _ in range(spec.get("stars", 0)):
        img[srng.integers(0, max(horizon, 2) - 1), srng.integers(0, w)] = (240, 240, 255)
    if spec.get("big_star"):
        cx, cy = w // 2, h // 2
        for d in range(-3, 4):
            img[cy, cx + d] = img[cy + d, cx] = (255, 240, 160)
        img[cy - 1:cy + 2, cx - 1:cx + 2] = (255, 255, 220)
    if "sun" in spec:
        disc(w * spec["sun"][0], h * spec["sun"][1], max(h, w) * 0.09 + 1, (255, 225, 110))
    if "moon" in spec:
        disc(w * spec["moon"][0], h * spec["moon"][1], max(h, w) * 0.07 + 1, (230, 230, 210))
    for _ in range(spec.get("clouds", 0)):
        cx, cy = srng.uniform(0, w), srng.uniform(1, h * 0.35)
        color = (110, 110, 125) if spec.get("dark_clouds") else (245, 245, 250)
        for k in range(4):
            disc(cx + k * 2.5 - 4, cy + srng.uniform(-1, 1), 2.2 + srng.uniform(0, 1.5), color)
    if spec.get("lightning"):
        x = w * 0.6
        for y in range(int(h * 0.3), horizon):
            x += srng.integers(-1, 2)
            if 0 <= int(x) < w:
                img[y, int(x)] = (255, 255, 180)
    for m in range(spec.get("mountains", 0)):
        peak = srng.uniform(0.15, 0.85) * w
        height = srng.uniform(0.3, 0.55) * h
        for x in range(w):
            top_y = horizon - max(height - abs(x - peak) * 1.1, 0)
            for y in range(int(top_y), horizon):
                snowy = spec.get("night") is None and y < horizon - height * 0.7
                img[y, x] = (235, 235, 240) if snowy else (110 - m * 15, 110 - m * 15, 120 - m * 10)
    if spec.get("volcano"):
        for x in range(w):
            top_y = horizon - max(h * 0.55 - abs(x - w / 2) * 0.9, 0)
            top_y = max(top_y, horizon - h * 0.45)
            for y in range(int(top_y), horizon):
                img[y, x] = (70, 50, 45)
        for y in range(int(horizon - h * 0.45), horizon, 2):
            x = int(w / 2 + srng.integers(-2, 3))
            img[y, x] = (250, 120, 30)
        disc(w / 2, horizon - h * 0.47, w * 0.06, (255, 150, 40))
    rect(0, horizon, w, h, spec.get("ground", (70, 120, 50)))
    for hill in range(spec.get("hills", 0)):
        cx = srng.uniform(0, w)
        r = srng.uniform(0.25, 0.5) * w
        shade = np.array(spec["ground"], float) * (0.85 + 0.08 * hill)
        for x in range(w):
            dy = max(r * r - (x - cx) ** 2, 0) ** 0.5 * 0.35
            rect(x, horizon - dy, x + 1, horizon + 1, shade)
    if "water" in spec:
        rect(0, int(h * spec["water"]), w, h, (50, 100, 190))
        for _ in range(w // 3):
            img[srng.integers(int(h * spec["water"]), h), srng.integers(0, w)] = (150, 190, 240)
    if spec.get("river"):
        x = w * 0.3
        for y in range(horizon, h):
            x += (y - horizon) * 0.05
            rect(x, y, x + 3 + (y - horizon) * 0.25, y + 1, (60, 110, 200))
    if spec.get("waterfall"):
        rect(w * 0.35, h * 0.3, w * 0.65, h, (90, 150, 230))
        for _ in range(w * 2):
            img[srng.integers(int(h * 0.3), h), srng.integers(int(w * 0.35), int(w * 0.65))] = (200, 230, 255)
        rect(0, h * 0.85, w, h, (60, 110, 200))
    if spec.get("path"):
        for y in range(horizon, h):
            half = 1 + (y - horizon) * 0.4
            rect(w / 2 - half, y, w / 2 + half, y + 1, (170, 140, 90))
    for _ in range(spec.get("trees", 0)):
        x = srng.uniform(1, w - 2)
        y = horizon + srng.uniform(0, max(h - horizon - 2, 1))
        rect(x, y - 4, x + 1, y + 1, (90, 60, 30))
        disc(x + 0.5, y - 5, 2.5, (40, 100, 40))
    if spec.get("big_tree"):
        rect(w / 2 - 1, h * 0.45, w / 2 + 1, horizon + 1, (100, 70, 40))
        disc(w / 2, h * 0.35, w * 0.4, (50, 120, 45))
        for _ in range(12):
            img[srng.integers(int(h * 0.2), int(h * 0.5)), srng.integers(1, w - 1)] = (200, 40, 40)
    for _ in range(spec.get("houses", 0)):
        x = srng.uniform(1, w - 7)
        y = horizon + srng.uniform(1, max(h - horizon - 6, 2))
        rect(x, y, x + 6, y + 5, (200, 180, 140))
        for k in range(4):
            rect(x - 1 + k, y - 1 - k, x + 7 - k, y - k, (150, 60, 50))
        rect(x + 2, y + 2, x + 4, y + 5, (90, 60, 40))
    for _ in range(spec.get("cactus", 0)):
        x = srng.uniform(2, w - 3)
        rect(x, horizon - 6, x + 2, horizon + 2, (60, 130, 50))
        rect(x - 2, horizon - 4, x, horizon - 3, (60, 130, 50))
    if spec.get("boat"):
        y = int(h * spec["water"]) - 1
        rect(w * 0.4, y, w * 0.6, y + 2, (110, 70, 40))
        rect(w * 0.5, y - 6, w * 0.5 + 1, y, (90, 60, 40))
        rect(w * 0.5 + 1, y - 6, w * 0.58, y - 2, (240, 240, 240))
    if spec.get("tower"):
        rect(w * 0.4, h * 0.3, w * 0.6, horizon + 1, (150, 150, 150))
        rect(w * 0.37, h * 0.25, w * 0.63, h * 0.32, (120, 120, 120))
        rect(w * 0.47, h * 0.45, w * 0.53, h * 0.55, (40, 40, 60))
    if spec.get("flower"):
        rect(w / 2, h * 0.45, w / 2 + 1, h, (50, 120, 40))
        disc(w / 2 + 0.5, h * 0.4, w * 0.18, (220, 60, 60))
        disc(w / 2 + 0.5, h * 0.4, w * 0.07, (250, 220, 80))
    for _ in range(spec.get("flowers", 0)):
        x, y = srng.integers(0, w), srng.integers(horizon + 1, h)
        img[y, x] = [(230, 60, 60), (250, 220, 70), (240, 240, 250)][srng.integers(0, 3)]
    img += srng.normal(0, 5, img.shape)
    return np.clip(img, 0, 255)


def paintings(root):
    img = np.zeros((256, 256, 4), np.uint8)
    for name, (bw, bh, cx, cy, spec) in PAINTINGS.items():
        w, h = bw * 16, bh * 16
        picture = scene(w, h, spec)
        picture[0, :] = picture[-1, :] = picture[:, 0] = picture[:, -1] = (70, 45, 25)  # the frame
        img[cy * 16:cy * 16 + h, cx * 16:cx * 16 + w, :3] = picture.astype(np.uint8)
        img[cy * 16:cy * 16 + h, cx * 16:cx * 16 + w, 3] = 255
    # The back: wooden boards.
    for y in range(16):
        for x in range(16):
            shade = 0.85 if y % 4 == 0 else 1.0
            img[y, 240 + x, :3] = np.clip(np.array((150, 110, 65)) * shade + rng.integers(-8, 9), 0, 255)
            img[y, 240 + x, 3] = 255
    # Put at the places of Beta's kz.png (Painting.ARTS): old cell -> new cell.
    kz = np.zeros_like(img)
    kz[0:16, 192:208] = img[0:16, 240:256]  # the back
    for name, (bw, bh, cx, cy, _spec) in PAINTINGS.items():
        nx, ny = KZ_PLACES.get(name, (cx, cy))
        kz[ny * 16:(ny + bh) * 16, nx * 16:(nx + bw) * 16] = img[cy * 16:(cy + bh) * 16, cx * 16:(cx + bw) * 16]
    save(kz, os.path.join(root, "art", "kz.png"))


# Where each picture is in kz.png (16 px cells), like Beta's pictures of its size.
KZ_PLACES = {
    "hills": (0, 2), "sea": (2, 2), "desert": (4, 2), "road": (6, 2), "clouds": (8, 2),
    "waterfall": (0, 4), "tree": (1, 4), "mountain": (0, 8), "village": (2, 8), "storm": (4, 8), "garden": (6, 8),
    "panorama": (0, 6), "river_valley": (12, 4), "night_sky": (0, 12), "volcano": (4, 12),
}


def weather(root):
    rain = np.zeros((64, 64, 4), np.uint8)
    for _ in range(28):
        x, y, length = rng.integers(0, 64), rng.integers(0, 64), rng.integers(3, 7)
        for k in range(length):
            rain[(y + k) % 64, x] = (160, 180, 235, 70 + 110 * k // length)
    save(rain, os.path.join(root, "environment", "rain.png"))
    snow = np.zeros((64, 64, 4), np.uint8)
    for _ in range(60):
        x, y = rng.integers(0, 63), rng.integers(0, 63)
        size = 2 if rng.random() < 0.4 else 1
        snow[y:y + size, x:x + size] = (250, 250, 255, 255)
    save(snow, os.path.join(root, "environment", "snow.png"))


if __name__ == "__main__":
    root = sys.argv[1]
    dial(root)
    map_background(root)
    paintings(root)
    weather(root)
