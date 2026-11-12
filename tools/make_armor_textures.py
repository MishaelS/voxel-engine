"""Draws the armor and player textures (our own simple pixel art):
- assets/textures/extra/unused/armor/armor0.png, armor1.png, armor2.png: the armor
  bar's full, half and empty chestplate icons (9 x 9), like the classic
  HUD;
- assets/textures/armor/<cloth|chain|iron|gold|diamond>_1.png (helmet, chestplate, boots)
  and armor_<material>_2.png (leggings), 64 x 64 in the biped skin layout
  (head at 0,0, body at 16,16, arm at 40,16, leg at 0,16), drawn over the
  player model a little bigger than its parts, like the game's armor
  layers; chainmail has holes;
- assets/textures/mob/char.png: the player's skin (the "player" model
  in assets/models/mobs.json).

Textures that are already there are kept (add --force to redraw them).

Usage: python3 tools/make_armor_textures.py assets/textures [--force]
Needs Pillow and numpy.
"""
import os
import sys

import numpy as np
from PIL import Image

rng = np.random.default_rng(7)

MATERIALS = {
    "leather": (150, 95, 60),
    "chainmail": (150, 150, 150),
    "iron": (214, 214, 214),
    "diamond": (84, 222, 214),
    "golden": (246, 214, 70),
}

ICON = [
    ".##...##.",
    "#ii#.#ii#",
    "#iii#iii#",
    ".#iiiii#.",
    ".#iiiii#.",
    ".#iiiii#.",
    ".#iiiii#.",
    ".#######.",
    ".........",
]


FORCE = "--force" in sys.argv
# Beta 1.7.3's names of the armor materials (armor/<name>_1.png).
BETA = {"leather": "cloth", "chainmail": "chain", "golden": "gold"}


def save(img, path):
    if FORCE or not os.path.exists(path):
        Image.fromarray(img).save(path)


def bubbles(out_dir):
    """The air bubbles shown under water: full and popping (9 x 9)."""
    os.makedirs(out_dir, exist_ok=True)
    full = np.zeros((9, 9, 4), np.uint8)
    for y in range(9):
        for x in range(9):
            d = ((x - 4) ** 2 + (y - 4) ** 2) ** 0.5
            if d <= 4.2:
                full[y, x] = (40, 70, 160, 255) if d > 3.2 else (130, 180, 250, 255)
    full[2:4, 2:4] = (240, 250, 255, 255)
    save(full, os.path.join(out_dir, "bubble0.png"))
    pop = np.zeros((9, 9, 4), np.uint8)
    for x, y in ((1, 1), (7, 1), (1, 7), (7, 7), (4, 0), (0, 4), (8, 4), (4, 8), (3, 3), (5, 5), (5, 3), (3, 5)):
        pop[y, x] = (130, 180, 250, 255)
    save(pop, os.path.join(out_dir, "bubble1.png"))


def icons(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    outline = (30, 30, 30, 255)
    full = (210, 210, 210, 255)
    shade = (160, 160, 160, 255)
    empty = (60, 60, 60, 255)
    for name, cut in (("armor0", 9), ("armor1", 4), ("armor2", -1)):
        img = np.zeros((9, 9, 4), np.uint8)
        for y, row in enumerate(ICON):
            for x, c in enumerate(row):
                if c == "#":
                    img[y, x] = outline
                elif c == "i":
                    filled = x <= cut
                    img[y, x] = (shade if y >= 5 else full) if filled else empty
        save(img, os.path.join(out_dir, name + ".png"))


def faces(u, v, w, h, d):
    """Unfolded box faces (x, y, width, height), like the mob skins."""
    return {
        "top": (u + d, v, w, d), "bottom": (u + d + w, v, w, d),
        "west": (u, v + d, d, h), "front": (u + d, v + d, w, h),
        "east": (u + d + w, v + d, d, h), "back": (u + 2 * d + w, v + d, w, h),
    }


def paint(img, rect, rgb, rows=None, holes=False, noise=10):
    x, y, w, h = rect
    for j in range(h):
        if rows is not None and j not in rows:
            continue
        for i in range(w):
            if holes and (i + j) % 2 == 1:
                continue
            edge = i == 0 or i == w - 1 or j == 0 or j == h - 1
            k = (0.78 if edge else 1.0) + rng.uniform(-noise, noise) / 255
            img[y + j, x + i, :3] = np.clip(np.array(rgb) * k, 0, 255)
            img[y + j, x + i, 3] = 255


def sides(box):
    return [box[n] for n in ("west", "front", "east", "back")]


def armor(out_dir):
    head = faces(0, 0, 8, 8, 8)
    body = faces(16, 16, 8, 12, 4)
    arm = faces(40, 16, 4, 12, 4)
    leg = faces(0, 16, 4, 12, 4)
    for material, rgb in MATERIALS.items():
        holes = material == "chainmail"
        # Layer 1: helmet, chestplate, boots.
        img = np.zeros((64, 64, 4), np.uint8)
        paint(img, head["top"], rgb, holes=holes)
        for name in ("west", "east", "back"):
            paint(img, head[name], rgb, rows=range(0, 6), holes=holes)
        x, y, w, h = head["front"]
        paint(img, (x, y, w, 2), rgb, holes=holes)  # brow; the face stays open
        paint(img, (x, y, 1, 5), rgb, holes=holes)
        paint(img, (x + w - 1, y, 1, 5), rgb, holes=holes)
        for rect in [body["top"], body["bottom"]] + sides(body):
            paint(img, rect, rgb, holes=holes)
        paint(img, arm["top"], rgb, holes=holes)
        for rect in sides(arm):
            paint(img, rect, rgb, rows=range(0, 5), holes=holes)
        paint(img, leg["bottom"], rgb, holes=holes)
        for rect in sides(leg):
            paint(img, rect, rgb, rows=range(8, 12), holes=holes)
        save(img, os.path.join(out_dir, f"{BETA.get(material, material)}_1.png"))
        # Layer 2: leggings.
        img = np.zeros((64, 64, 4), np.uint8)
        for rect in [body["bottom"]] + sides(body):
            paint(img, rect, rgb, rows=None if rect == body["bottom"] else range(8, 12), holes=holes)
        paint(img, leg["top"], rgb, holes=holes)
        for rect in sides(leg):
            paint(img, rect, rgb, rows=range(0, 9), holes=holes)
        save(img, os.path.join(out_dir, f"{BETA.get(material, material)}_2.png"))


def player(out_dir):
    """Our own player: dark hair, a red shirt, gray trousers, brown shoes."""
    img = np.zeros((64, 64, 4), np.uint8)
    skin = (204, 152, 116)
    hair = (64, 42, 26)
    shirt = (156, 44, 44)
    trousers = (64, 66, 78)
    shoes = (54, 40, 30)
    head = faces(0, 0, 8, 8, 8)
    for rect in head.values():
        paint(img, rect, skin, noise=6)
    paint(img, head["top"], hair, noise=8)
    paint(img, head["back"], hair, rows=range(0, 6), noise=8)
    for name in ("west", "east"):
        paint(img, head[name], hair, rows=range(0, 3), noise=8)
    x, y, w, h = head["front"]
    paint(img, (x, y, w, 2), hair, noise=8)
    for px, rgb in ((1, (245, 245, 245)), (2, (40, 60, 120)), (5, (40, 60, 120)), (6, (245, 245, 245))):
        img[y + 4, x + px, :3] = rgb
    img[y + 6, x + 3, :3] = img[y + 6, x + 4, :3] = (150, 90, 70)
    body = faces(16, 16, 8, 12, 4)
    for rect in body.values():
        paint(img, rect, shirt)
    for u, v in ((40, 16), (40, 32)):
        arm = faces(u, v, 4, 12, 4)
        for rect in arm.values():
            paint(img, rect, skin, noise=6)
        paint(img, arm["top"], shirt)
        for rect in sides(arm):
            paint(img, rect, shirt, rows=range(0, 5))
    for u, v in ((0, 16), (0, 32)):
        leg = faces(u, v, 4, 12, 4)
        for rect in leg.values():
            paint(img, rect, trousers)
        paint(img, leg["bottom"], shoes)
        for rect in sides(leg):
            paint(img, rect, shoes, rows=range(10, 12))
    save(img, os.path.join(out_dir, "char.png"))


if __name__ == "__main__":
    root = sys.argv[1]
    icons(os.path.join(root, "extra", "unused", "armor"))
    bubbles(os.path.join(root, "extra", "unused", "bubble"))
    armor(os.path.join(root, "armor"))
    player(os.path.join(root, "mob"))
