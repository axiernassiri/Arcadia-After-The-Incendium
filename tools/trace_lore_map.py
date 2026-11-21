#!/usr/bin/env python3
"""Trace the hand-drawn lore map (map/source/lore_map.png) into two masks the map generator reads:

  map/source/land_mask.png    white = land, black = sea
  map/source/region_mask.png  one flat colour per lore region (see REGION_COLOURS)

Both masks are ordinary images, so you can also paint them by hand (any paint program) and skip
this script: generate_map.py only needs the masks. Run:  python3 tools/trace_lore_map.py
Needs: numpy, scipy, scikit-image, Pillow.

How it works: the lore map is a terrain picture with translucent region overlays, black region
outlines, labels and pig icons drawn on top. Region outlines that close (Eurome, the Western
Archipelago, the Southwest Island, the Southern Isles) are found by flood fill; Mentos, Sylvania
and Midrea share one open area and are split by the boundary lines traced below. Land is the
less-blue half of each region (Otsu threshold), with labels and icons filled in from their
surroundings. The Western Archipelago islands are faint, so they get their own detector.
"""
import os

import numpy as np
from PIL import Image
from scipy import ndimage
from skimage.filters import threshold_otsu

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "map", "source")

REGION_COLOURS = {
    "Mentos": (80, 140, 255),
    "Frost Reach": (180, 220, 255),
    "Sylvania": (60, 200, 90),
    "Midrea": (170, 80, 220),
    "Eurome": (200, 110, 60),
    "Western Archipelago": (150, 150, 150),
    "Southwest Island": (240, 220, 60),
    "Southern Isles": (60, 220, 220),
}

# Boundaries traced by hand from the lore map, in lore-map pixels (1251 x 682).
MENTOS_SOUTH = [(0, 200), (150, 205), (330, 220), (415, 252), (475, 257), (495, 232), (520, 245), (545, 285),
                (610, 250), (635, 257), (650, 285), (680, 300), (725, 275), (860, 265), (940, 290), (1251, 290)]
SYLVANIA_MIDREA = [(285, 545), (320, 565), (350, 590), (390, 610), (682, 640)]  # (y, x)
FROST_REACH_WEST = 748      # the snowfields east of this x in Mentos form Frost Reach
TERRAIN_AREA = (340, 70, 844, 668)      # x0, y0, x1, y1: the terrain picture inside the drawing
ISLAND_INSET = (88, 468, 196, 615)      # the Southwest Island's own inset picture
NOT_LAND = [(770, 28, 1235, 142),       # title box
            (545, 60, 665, 125),        # the big pig's crown
            (428, 535, 490, 605),       # the Western Archipelago pig
            (338, 215, 392, 250),       # the Mentos-Sylvania outline crossing the sea
            (758, 262, 846, 282)]       # the Mentos-Midrea outline crossing the sea
EXTRA_ISLANDS = [(1010, 337, 7)]        # the small pig on the equator: a lone islet (x, y, radius)


def main():
    im = np.array(Image.open(os.path.join(SRC, "lore_map.png")).convert("RGB")).astype(float)
    h, w = im.shape[:2]
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    yy, xx = np.mgrid[0:h, 0:w]

    # --- regions
    black = im.max(2) < 75
    lab, n = ndimage.label(~black)
    sizes = ndimage.sum(~black, lab, range(1, n + 1))
    closed = {}
    for i, s in enumerate(sizes):
        if 3000 < s < 200000:   # skip the big open sea
            m = lab == i + 1
            cx, cy = xx[m].mean(), yy[m].mean()
            name = ("Southwest Island" if cx < 200 else "Western Archipelago" if cx < 540 and cy > 450
                    else "Southern Isles" if cy > 560 else "Eurome")
            closed[name] = ndimage.binary_dilation(m, iterations=4)
    south = np.array(MENTOS_SOUTH, float)
    above = yy < np.interp(xx, south[:, 0], south[:, 1])
    sm = np.array(SYLVANIA_MIDREA, float)
    sylmid_x = np.interp(yy, sm[:, 0], sm[:, 1])
    region = np.full((h, w), "Sylvania", dtype=object)
    region[(~above) & (xx > sylmid_x)] = "Midrea"
    region[above] = "Mentos"
    region[above & (xx > FROST_REACH_WEST)] = "Frost Reach"
    for k, m in closed.items():
        region[m] = k

    # --- land
    blue = b - (r + g) / 2
    bad = (im.max(2) < 90) | ((r > 200) & (g < 200)) | ((r > 200) & (g > 180) & (b < 120)) \
        | ((r > 230) & (g > 150) & (b > 150) & (r - b > 40))
    _, (iy, ix) = ndimage.distance_transform_edt(bad, return_indices=True)
    bf = ndimage.gaussian_filter(blue[iy, ix], 1.2)
    area = np.zeros((h, w), bool)
    for x0, y0, x1, y1 in (TERRAIN_AREA, ISLAND_INSET):
        area[y0:y1, x0:x1] = True
    land = np.zeros((h, w), bool)
    for reg in set(region.ravel()):
        if reg == "Frost Reach":
            continue
        m = ((region == reg) | ((reg == "Mentos") & (region == "Frost Reach"))) & area
        if m.sum() > 200:
            land |= m & (bf < threshold_otsu(bf[m]))
    land = ndimage.binary_opening(land, iterations=1)
    land = ndimage.binary_closing(land, iterations=2)
    land = ndimage.binary_fill_holes(land)

    # the Western Archipelago: faint yellow islands on a grey overlay
    yel = ((r + g) / 2 - b)[iy, ix]
    d = ndimage.gaussian_filter(yel - ndimage.median_filter(yel, 25), 1.0)
    wa = (region == "Western Archipelago") & area
    isl = wa & (d > np.percentile(d[wa], 90)) & ~ndimage.binary_dilation(bad, iterations=6)
    isl[:, 432:] = False
    isl = ndimage.binary_opening(isl, iterations=1)
    land |= ndimage.binary_dilation(isl, iterations=2)

    for x0, y0, x1, y1 in NOT_LAND:
        land[y0:y1, x0:x1] = False
    for cx, cy, rad in EXTRA_ISLANDS:
        land |= (xx - cx) ** 2 + (yy - cy) ** 2 <= rad ** 2
        region[(xx - cx) ** 2 + (yy - cy) ** 2 <= rad ** 2] = "Southern Isles"
    lab, n = ndimage.label(land)
    sizes = ndimage.sum(land, lab, range(1, n + 1))
    keep = np.zeros(n + 1, bool)
    keep[1:] = sizes >= 40
    land = keep[lab]

    # Coastal slivers of the mainland that fall outside a hand-drawn outline belong to the mainland
    # region next to them, not to the island region whose overlay happens to cover them.
    lab, n = ndimage.label(land)
    sizes = ndimage.sum(land, lab, range(1, n + 1))
    island_regions = ("Southern Isles", "Western Archipelago")
    for i, s in enumerate(sizes):
        if s < 8000:
            continue
        comp = lab == i + 1
        stray = comp & np.isin(region, island_regions)
        good = comp & ~stray
        if stray.any() and good.any():
            dist, (jy, jx) = ndimage.distance_transform_edt(~good, return_indices=True)
            sliver = stray & (dist <= 8)   # only thin coastal strips, not whole islands
            region[sliver] = region[jy[sliver], jx[sliver]]

    Image.fromarray((land * 255).astype(np.uint8)).save(os.path.join(SRC, "land_mask.png"))
    rgb = np.zeros((h, w, 3), np.uint8)
    for name, col in REGION_COLOURS.items():
        rgb[region == name] = col
    Image.fromarray(rgb).save(os.path.join(SRC, "region_mask.png"))
    for name in REGION_COLOURS:
        print(f"  {name:20s} land px {int(((region == name) & land).sum()):6d}")
    print("wrote map/source/land_mask.png and region_mask.png")


if __name__ == "__main__":
    main()
