"""Draws the explosion and poof particle sheet (our own pixel art, like the
modern game's misc/explosion.png and Beta's smoke cells of particles.png):
- assets/textures/extra/explosion.png, 64 x 72:
  - rows 0..63: 16 frames of 16 x 16 (4 x 4, left to right, top to bottom)
    of a big explosion puff: a cluster of round white clouds shaded light
    gray toward the lower right, growing and graying, then breaking up into
    specks;
  - row 64..71: 8 frames of 8 x 8 of a small poof (a creature gone, the
    explosion's small puffs), smallest (frame 0) to biggest (frame 7), like
    Beta's cells 0..7.
BlockParticles puts it into the particle atlas at (320, 0).

The sheet is kept if it is already there (add --force to redraw it).

Usage: python3 tools/make_explosion_texture.py assets/textures [--force]
Needs Pillow and numpy.
"""
import os
import sys

import numpy as np
from PIL import Image

rng = np.random.default_rng(11)

# Shades of a cloud, lit from the upper left: white to dark gray.
SHADES = [255, 238, 218, 196, 172, 148, 124]

# The explosion's clouds: (x, y, radius, when it hollows out 0..1).
BLOBS = [(8.0, 8.0, 4.4, 0.55), (4.8, 5.8, 3.2, 0.35), (11.2, 5.4, 3.0, 0.45),
         (4.6, 10.8, 3.0, 0.5), (11.4, 10.6, 3.2, 0.4), (8.0, 3.4, 2.5, 0.3),
         (8.4, 12.8, 2.6, 0.6)]
# Coarse noise (2 x 2 pixel cells) for ragged edges.
NOISE = np.kron(rng.random((8, 8)), np.ones((2, 2)))


def cloud(size, blobs, t, grow):
    """One frame at time `t` (0..1): the union of the blobs, each shaded by
    where the pixel is in it (darker to the lower right and at the rim,
    grayer with time); late on each blob hollows out from its middle into
    a ragged ring and breaks up."""
    out = np.zeros((size, size, 4), np.uint8)
    noise = NOISE[:size, :size]
    for y in range(size):
        for x in range(size):
            best = None
            for bx, by, r, hollow in blobs:
                r *= grow
                dx, dy = x + 0.5 - bx, y + 0.5 - by
                d = (dx * dx + dy * dy) ** 0.5 / r
                k = max(t - hollow, 0.0) / max(1.0 - hollow, 1e-3)  # 0..1 how gone
                inner = k * 0.85 - 0.15 + noise[y, x] * 0.3 if k > 0.0 else 0.0
                if d <= 1.0 - k * 0.15 and d >= inner:
                    shade = d * 0.9 + (dx + dy) / r * 0.45
                    best = shade if best is None else min(best, shade)
            if best is None:
                continue
            level = int(np.clip(best * 2.4 + t * 3.0, 0, len(SHADES) - 1))
            v = SHADES[level]
            out[y, x] = (v, v, v, 255)
    return out


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "assets/textures"
    path = os.path.join(root, "extra", "explosion.png")
    if os.path.exists(path) and "--force" not in sys.argv:
        print("kept", path)
        return
    sheet = np.zeros((72, 64, 4), np.uint8)
    for f in range(16):
        t = f / 15.0
        grow = 0.75 + 0.35 * min(t * 2.5, 1.0)
        frame = cloud(16, BLOBS, t, grow)
        sheet[(f // 4) * 16:(f // 4) * 16 + 16, (f % 4) * 16:(f % 4) * 16 + 16] = frame
    for f in range(8):
        r = 1.2 + f * 0.42
        frame = cloud(8, [(4.0, 4.0, r, 1.0)], 0.25, 1.0)
        sheet[64:72, f * 8:f * 8 + 8] = frame
    Image.fromarray(sheet, "RGBA").save(path)
    print("drew", path)


if __name__ == "__main__":
    main()
