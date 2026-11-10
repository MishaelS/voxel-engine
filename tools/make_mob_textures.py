"""Draws the mob textures (assets/textures/mobs/*.png, 64 x 64) from the
model definitions (assets/models/mobs.json): each part's box is unfolded
like the game's skins (top and bottom squares, then the strip -X, front +Z,
+X, back -Z) and painted with its colors, a little noise and, on the
head's front, a face. Our own simple pixel art, in the spirit of the
classic game's mobs. Replace any file with a hand-drawn skin (same layout).

Usage: python3 tools/make_mob_textures.py assets/models/mobs.json assets/textures/mobs
Needs Pillow and numpy.
"""
import json
import os
import sys

import numpy as np
from PIL import Image

rng = np.random.default_rng(5)

# Colors per mob and part (part name prefix -> RGB), "*" = default.
PALETTES = {
    "zombie": {"head": (74, 130, 66), "body": (60, 110, 160), "right_arm": (74, 130, 66), "left_arm": (74, 130, 66),
               "right_leg": (70, 60, 140), "left_leg": (70, 60, 140)},
    "skeleton": {"*": (196, 196, 190)},
    "creeper": {"*": (90, 168, 80)},
    "pig": {"*": (236, 160, 160), "snout": (226, 130, 140)},
    "cow": {"*": (90, 62, 44), "horn": (210, 210, 200)},
    "sheep": {"head": (200, 180, 160), "*": (220, 210, 196)},
    "sheep_fur": {"*": (236, 236, 236)},
    "chicken": {"*": (246, 246, 246), "beak": (240, 170, 40), "wattle": (210, 40, 40), "leg": (230, 160, 50)},
    "spider": {"*": (54, 48, 44), "head": (44, 38, 36)},
    "slime": {"outer": (120, 200, 110), "inner": (90, 170, 80), "eye": (30, 50, 30), "mouth": (30, 50, 30)},
    "squid": {"*": (40, 70, 110), "tentacle": (36, 60, 96)},
    "wolf": {"*": (210, 206, 200), "snout": (230, 226, 220), "ear": (180, 176, 170), "tail": (196, 192, 186)},
}


def color_for(mob, part):
    palette = PALETTES[mob]
    for key, value in palette.items():
        if key != "*" and part.startswith(key):
            return value
    return palette.get("*", (200, 200, 200))


def face_rects(u, v, w, h, d):
    return {
        "top": (u + d, v, w, d), "bottom": (u + d + w, v, w, d),
        "west": (u, v + d, d, h), "front": (u + d, v + d, w, h),
        "east": (u + d + w, v + d, d, h), "back": (u + d + w + d, v + d, w, h),
    }


def fill(img, rect, rgb, noise=14, shade=1.0):
    x, y, w, h = [int(round(a)) for a in rect]
    for j in range(max(h, 1)):
        for i in range(max(w, 1)):
            n = rng.integers(-noise, noise + 1)
            img[y + j, x + i, :3] = np.clip(np.array(rgb) * shade + n, 0, 255)
            img[y + j, x + i, 3] = 255


def put(img, rect, dx, dy, rgb):
    x, y, w, h = [int(round(a)) for a in rect]
    if 0 <= dx < w and 0 <= dy < h:
        img[y + dy, x + dx, :3] = rgb
        img[y + dy, x + dx, 3] = 255


def face(img, mob, rect):
    """Eyes, nose and mouth on a head's front."""
    x, y, w, h = [int(round(a)) for a in rect]
    black = (20, 20, 20)
    white = (240, 240, 240)
    if mob == "creeper":
        for px, py in [(1, 2), (2, 2), (1, 3), (2, 3), (5, 2), (6, 2), (5, 3), (6, 3),
                       (3, 4), (4, 4), (2, 5), (3, 5), (4, 5), (5, 5), (2, 6), (5, 6), (2, 7), (5, 7)]:
            put(img, rect, px, py, black)
    elif mob == "spider":
        for px, py in [(1, 3), (2, 3), (5, 3), (6, 3), (2, 5), (5, 5), (3, 2), (4, 2)]:
            put(img, rect, px, py, (220, 30, 30))
    elif mob in ("zombie", "skeleton"):
        eye = black if mob == "skeleton" else (20, 40, 20)
        for px in (1, 2, 5, 6):
            put(img, rect, px, 4, eye)
        if mob == "skeleton":
            for px in range(2, 6):
                put(img, rect, px, 6, (90, 90, 90))
        else:
            put(img, rect, 3, 6, (40, 80, 40))
            put(img, rect, 4, 6, (40, 80, 40))
    elif mob == "slime":
        return
    else:
        ey = max(h // 2 - 1, 1)
        put(img, rect, 0, ey, white)
        put(img, rect, 1, ey, black)
        put(img, rect, w - 2, ey, black)
        put(img, rect, w - 1, ey, white)
        if mob == "cow":
            for py in range(2, h):
                for px in range(2, w - 2):
                    if (px + py) % 5 != 0:
                        put(img, rect, px, py, (236, 236, 230))
            put(img, rect, 3, h - 2, (40, 30, 30))
            put(img, rect, w - 4, h - 2, (40, 30, 30))
        if mob == "squid":
            put(img, rect, 3, ey, white)
            put(img, rect, w - 4, ey, white)


def paint(models, mob, part_list, img, texture):
    for p in part_list:
        if p.get("texture", mob) != texture:
            continue
        w, h, d = p["size"]
        w, h, d = int(round(w)), int(round(h)), int(round(d))
        u, v = p["uv"]
        rgb = color_for(texture, p["name"])
        rects = face_rects(u, v, w, h, d)
        for name, rect in rects.items():
            shade = {"top": 1.08, "bottom": 0.8}.get(name, 1.0)
            fill(img, rect, rgb, shade=shade)
        if p["role"] == "head" and p["name"] == "head":
            face(img, mob, rects["front"])
        if mob == "cow" and p["name"] == "body":
            # White patches on the brown hide.
            for k in range(10):
                rect = rects[["west", "east", "top", "back"][k % 4]]
                cx, cy = rng.integers(0, max(int(rect[2]) - 4, 1)), rng.integers(0, max(int(rect[3]) - 3, 1))
                fill(img, (rect[0] + cx, rect[1] + cy, 4, 3), (236, 236, 230), noise=6)
        if mob == "skeleton" and p["name"] == "body":
            for row in range(2, 12, 2):
                for col in range(1, 7):
                    put(img, rects["front"], col, row, (90, 90, 90))
        if mob == "sheep" and p["role"].startswith("leg"):
            # Wool on the upper legs.
            for name in ("west", "front", "east", "back"):
                x, y, rw, rh = rects[name]
                fill(img, (x, y, rw, 6), (236, 236, 236), noise=8)
        if mob == "wolf" and p["name"] in ("body", "mane"):
            fill(img, rects["top"], (150, 146, 140), noise=10)
        if mob == "pig" and p["name"] == "snout":
            put(img, rects["front"], 1, 1, (150, 80, 90))
            put(img, rects["front"], 2, 1, (150, 80, 90))
        if mob == "wolf" and p["name"] == "snout":
            put(img, rects["front"], 1, 0, (20, 20, 20))
        if mob == "creeper":
            # Mottled skin.
            for name, rect in rects.items():
                x, y, rw, rh = [int(round(a)) for a in rect]
                for k in range(rw * rh // 4):
                    put(img, rect, rng.integers(0, max(rw, 1)), rng.integers(0, max(rh, 1)), (60, 130, 56))
            if p["name"] == "head":
                face(img, mob, rects["front"])


def main(models_path, out_dir):
    models = json.load(open(models_path))
    os.makedirs(out_dir, exist_ok=True)
    for mob, model in models.items():
        textures = {p.get("texture", mob) for p in model["parts"]}
        for texture in textures:
            img = np.zeros((64, 64, 4), np.uint8)
            paint(models, mob, model["parts"], img, texture)
            Image.fromarray(img).save(os.path.join(out_dir, texture + ".png"))
            print("wrote", texture)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
