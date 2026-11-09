"""Draws the chest textures into the block atlas (assets/textures/terrain.png),
in the style of the classic Beta chest: oak planks with a dark frame, the
lid seam on the sides and a gray latch on the front.

Tiles written (unused placeholder tiles of the atlas):
  27 - chest top, 42 - chest side, 189 - chest front.

Usage: python3 tools/make_chest_tiles.py assets/textures/terrain.png
Needs Pillow.
"""
import sys

from PIL import Image

TOP, SIDE, FRONT = 27, 42, 189
PLANKS = 4


def tile_box(index):
    return ((index % 16) * 16, (index // 16) * 16, (index % 16) * 16 + 16, (index // 16) * 16 + 16)


def shade(color, factor):
    return tuple(max(0, min(255, int(c * factor))) for c in color[:3]) + (255,)


def main(path):
    atlas = Image.open(path).convert("RGBA")
    planks = atlas.crop(tile_box(PLANKS))

    def base():
        img = planks.copy()
        px = img.load()
        for y in range(16):
            for x in range(16):
                # A little darker and warmer than planks.
                r, g, b, a = px[x, y]
                px[x, y] = (int(r * 0.9), int(g * 0.82), int(b * 0.7), 255)
        return img

    def frame(img):
        px = img.load()
        for i in range(16):
            for x, y in ((i, 0), (i, 15), (0, i), (15, i)):
                px[x, y] = shade(px[x, y], 0.45)
            for x, y in ((i, 1), (1, i)):
                if 0 < i < 15:
                    px[x, y] = shade(px[x, y], 1.12)
            for x, y in ((i, 14), (14, i)):
                if 0 < i < 15:
                    px[x, y] = shade(px[x, y], 0.75)

    top = base()
    frame(top)

    side = base()
    frame(side)
    px = side.load()
    for x in range(16):
        px[x, 5] = shade(px[x, 5], 0.45)  # the lid seam
        px[x, 6] = shade(px[x, 6], 0.8)

    front = side.copy()
    px = front.load()
    latch_dark = (60, 60, 60, 255)
    latch = (170, 170, 170, 255)
    latch_light = (215, 215, 215, 255)
    for y in range(3, 8):
        for x in range(7, 9 + 1):
            edge = x in (7, 9) or y in (3, 7)
            px[x, y] = latch_dark if edge else latch
    px[8, 4] = latch_light

    for index, img in ((TOP, top), (SIDE, side), (FRONT, front)):
        atlas.paste(img, tile_box(index)[:2])
    atlas.save(path)


if __name__ == "__main__":
    main(sys.argv[1])
