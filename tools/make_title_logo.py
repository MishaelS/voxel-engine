"""Draws the title logo (assets/textures/extra/title_logo.png) the way the
classic logo was made: every letter is built from blocks on a grid, each
block shows the stone texture on its face, with a darker 3D side below it,
a crisp black outline and a soft shadow. The lower line uses smaller blocks.

Pixel art: drawn at native size (CELL texels per block) and scaled up by
SCALE with nearest neighbour, so it stays sharp.

Usage: python3 tools/make_title_logo.py assets/textures/terrain.png assets/textures/extra/title_logo.png
Needs Pillow and numpy.
"""
import random
import sys

import numpy as np
from PIL import Image

TITLE = "VOXEL ENGINE"
SUBTITLE = "BEDROCK EDITION"
CELL = 8            # texels per block of the title
SUB_CELL = 4        # texels per block of the subtitle
DEPTH = 0.75        # 3D side height, in blocks
SCALE = 4           # nearest-neighbour upscale of the final image
STONE = (1, 0)      # atlas tiles (16 px)
SUB_TILE = (1, 0)

GLYPHS = {
    "A": [".XXX.", "X...X", "XXXXX", "X...X", "X...X"],
    "B": ["XXXX.", "X...X", "XXXX.", "X...X", "XXXX."],
    "C": [".XXXX", "X....", "X....", "X....", ".XXXX"],
    "D": ["XXXX.", "X...X", "X...X", "X...X", "XXXX."],
    "E": ["XXXX", "X...", "XXX.", "X...", "XXXX"],
    "G": [".XXXX", "X....", "X..XX", "X...X", ".XXXX"],
    "I": ["XXX", ".X.", ".X.", ".X.", "XXX"],
    "K": ["X...X", "X..X.", "XXX..", "X..X.", "X...X"],
    "L": ["X...", "X...", "X...", "X...", "XXXX"],
    "N": ["X...X", "XX..X", "X.X.X", "X..XX", "X...X"],
    "O": [".XXX.", "X...X", "X...X", "X...X", ".XXX."],
    "R": ["XXXX.", "X...X", "XXXX.", "X..X.", "X...X"],
    "T": ["XXXXX", "..X..", "..X..", "..X..", "..X.."],
    "V": ["X...X", "X...X", "X...X", ".X.X.", "..X.."],
    "X": ["X...X", ".X.X.", "..X..", ".X.X.", "X...X"],
    " ": ["..", "..", "..", "..", ".."],
}


def block_grid(text):
    """Text -> boolean grid of blocks (5 rows), one empty column between letters."""
    columns = []
    for i, c in enumerate(text):
        rows = GLYPHS[c]
        for x in range(len(rows[0])):
            columns.append([r[x] == "X" for r in rows])
        if i < len(text) - 1:
            columns.append([False] * 5)
    return np.array(columns, bool).T


def tile(atlas, t):
    return atlas[t[1] * 16:(t[1] + 1) * 16, t[0] * 16:(t[0] + 1) * 16, :3].astype(float)


def render_word(grid, cell, texture, rng):
    """RGBA of the word: faces, 3D sides below, black outline."""
    rows, cols = grid.shape
    depth = int(round(cell * DEPTH))
    pad = 2
    h = rows * cell + depth + pad * 2
    w = cols * cell + pad * 2
    rgb = np.zeros((h, w, 3))
    alpha = np.zeros((h, w), bool)
    face = np.zeros((h, w), bool)
    # 3D sides first (below each block), then faces on top.
    for y in range(rows):
        for x in range(cols):
            if not grid[y, x]:
                continue
            x0, y0 = pad + x * cell, pad + y * cell
            for d in range(1, depth + 1):
                if y + 1 < rows and grid[y + 1, x] and d >= cell:
                    break
                yy = y0 + cell - 1 + d
                shade = 0.42 - 0.12 * d / depth
                row = texture[(d * 3) % 16, :, :]
                for i in range(cell):
                    if not face[yy, x0 + i]:
                        rgb[yy, x0 + i] = row[(i * 16 // cell) % 16] * shade
                        alpha[yy, x0 + i] = True
    for y in range(rows):
        for x in range(cols):
            if not grid[y, x]:
                continue
            x0, y0 = pad + x * cell, pad + y * cell
            ox, oy = rng.randrange(16 - cell + 1) if cell < 16 else 0, rng.randrange(16 - cell + 1) if cell < 16 else 0
            part = texture[oy:oy + cell, ox:ox + cell] if cell <= 16 else \
                np.array(Image.fromarray(texture.astype(np.uint8)).resize((cell, cell), Image.NEAREST), float)
            # Light from above: the top of the letter is a little brighter.
            light = 1.12 - 0.22 * (y / max(rows - 1, 1))
            rgb[y0:y0 + cell, x0:x0 + cell] = np.clip(part * light, 0, 255)
            alpha[y0:y0 + cell, x0:x0 + cell] = True
            face[y0:y0 + cell, x0:x0 + cell] = True
    # Black outline one texel wide around everything.
    grown = alpha.copy()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            grown |= np.roll(np.roll(alpha, dy, 0), dx, 1)
    out = np.zeros((h, w, 4), np.uint8)
    out[..., :3] = np.where(alpha[..., None], rgb, 0).astype(np.uint8)
    out[..., 3] = grown * 255
    return out


def main(atlas_path, out_path):
    atlas = np.array(Image.open(atlas_path).convert("RGBA"))
    rng = random.Random(3)
    title = render_word(block_grid(TITLE), CELL, tile(atlas, STONE), rng)
    sub = render_word(block_grid(SUBTITLE), SUB_CELL, tile(atlas, SUB_TILE), rng)
    gap = CELL // 2
    w = max(title.shape[1], sub.shape[1]) + 8
    h = title.shape[0] + gap + sub.shape[0] + 8
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    words = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    tx = (w - title.shape[1]) // 2
    sx = (w - sub.shape[1]) // 2
    words.paste(Image.fromarray(title), (tx, 2))
    sub_img = Image.fromarray(sub)
    words.alpha_composite(sub_img, (sx, 2 + title.shape[0] + gap))
    # Soft shadow: the silhouette, dark and half transparent, 2 texels down-right.
    shadow = np.array(words)
    shadow[..., :3] = 0
    shadow[..., 3] = (shadow[..., 3] * 0.45).astype(np.uint8)
    canvas.alpha_composite(Image.fromarray(shadow), (2, 2))
    canvas.alpha_composite(words)
    canvas = canvas.resize((w * SCALE, h * SCALE), Image.NEAREST)
    canvas.save(out_path)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
