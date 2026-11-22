#!/usr/bin/env python3
"""Build the whole Arcadian world around the existing mainland map.

The mainland (map/ground_*.png from tools/generate_map.py, with every province id, shape and hand edit
in data/provinces.json) is kept exactly as it is and placed where "Mainland" sits on the world map
(map/source/world_map.png, from the Blueprint doc). Every other land on the world map is traced into
new provinces around it: Terra Incognito, the ice caps, the scattered isles, Combustion Ayam, Pelari,
the Satian Islands, and Oceania under the Deep Blue.

The world map was not drawn to the same geography west of the mainland as the old lore map (its
Terra Incognito reaches where the old map has the Western Archipelago), so the world is assembled in
two halves: everything west of WORLD_SPLIT_X goes on the left with open ocean before the mainland,
and the lands east of it are placed relative to the mainland. Inside the old map's rectangle the old
map wins; world land is only taken there where the old map has open sea far from any coast.

First run: copies the untouched mainland files to map/source/mainland_* so the tool can be re-run.
Writes map/ground_{index,provinces,terrain}.png, map/ground_map.json, and data/provinces.json (the old
provinces untouched, then the new ones, regenerated on every run). The sky layer is not touched.

Usage:  python tools/build_world.py
Needs: numpy, scipy, Pillow.
"""
import json
import os
import shutil
import zlib

import numpy as np
from PIL import Image
from scipy import ndimage

import generate_map as gm   # reuse the province partition, neighbours and lanes

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAP = os.path.join(ROOT, "map")
SRC = os.path.join(MAP, "source")
RNG = np.random.default_rng(4289)

WORLD = os.path.join(SRC, "world_map.png")
# --- how the world map lines up with the old mainland map (measured from the two drawings) ---
WORLD_MAIN_BBOX = (1224, 151, 1820, 782)      # "Mainland" on the world map: x0, y0, x1, y1
OLD_MAIN_BBOX = (604, 189, 1337, 999)         # the same continent on the old 2000 x 1092 map
WORLD_SPLIT_X = 1150                          # world-map x: west of this goes in the left half
GAP = 110                                     # game pixels of open ocean between the halves
OLD_LAND_X0 = 142                             # leftmost old land (old map pixels)
SEA_REACH = 55                                # sea lanes, as in generate_map.py

# labels and decorations drawn on the world map, in world-map pixels: (x0, y0, x1, y1) -> sea
LABELS = [
    (0, 0, 92, 1104),            # TERRA INCOGNITO, written down the left edge
    (1984, 0, 1999, 1104),       # the frame on the right edge
    (615, 50, 795, 84), (600, 165, 810, 198),                    # CASPIAN SEA, NORTHERN SEA
    (1725, 350, 1835, 382), (1835, 527, 1975, 640),              # Mainland, Equator Isles (+ note)
    (1110, 592, 1220, 622), (1198, 783, 1400, 815),              # Vesuvians, Western Archipelago
    (1543, 830, 1738, 862), (1785, 972, 1945, 1005),             # Eastern Archipelago, Satian Islands
    (1600, 1028, 1670, 1058), (1312, 998, 1505, 1028),           # Pelari, Combustion Ayam
    (668, 927, 882, 960), (170, 897, 418, 932),                  # SOUTHERN SEA, Oceania (Underwater)
    (12, 1040, 165, 1075), (228, 958, 318, 1050),                # DEEP BLUE, the dashed box
    # lands the old mainland map already has its own version of (Saltjaw's Western Archipelago, the
    # Southern Isles, Equator Isle under the Holy Waterfall): leave them to the old map
    (1190, 600, 1420, 795), (1430, 700, 1860, 860), (1855, 410, 1965, 515),
]
OCEANIA_CENTRE = (272, 1003)   # world-map pixels: the dashed box in the Deep Blue

# regions of the new lands: nearest anchor (world-map pixels) wins
ANCHORS = [
    ("Northern Incognita", 600, 350), ("Western Incognita", 300, 480), ("Central Incognita", 640, 520),
    ("Southern Incognita", 500, 690), ("Eastern Incognita", 880, 640),
    ("Farwest Isles", 230, 300), ("Farwest Isles", 260, 760), ("Northern Isles", 1000, 235),
    ("Southern Shoals", 760, 830), ("Northern Ice", 650, 60), ("Southern Ice", 800, 1065),
    ("Vesuvians", 1160, 565), ("Combustion Ayam", 1400, 935), ("Pelari", 1645, 980),
    ("Satian Islands", 1850, 925), ("Eastern Archipelago", 1650, 800), ("Northern Isles", 1600, 130),
    ("Southern Ice", 1210, 1075),
]
TARGET_AREA = {"Northern Incognita": 5200, "Western Incognita": 5200, "Central Incognita": 4600,
               "Southern Incognita": 5200, "Eastern Incognita": 5000, "Farwest Isles": 2600, "Northern Isles": 2400,
               "Southern Shoals": 2400, "Northern Ice": 14000, "Southern Ice": 14000, "Vesuvians": 2400,
               "Combustion Ayam": 2400, "Pelari": 2400, "Satian Islands": 2000, "Eastern Archipelago": 2200,
               "Oceania": 3000}
TRADE_NODE = {"Northern Incognita": "Terra Incognito", "Western Incognita": "Terra Incognito",
              "Central Incognita": "Terra Incognito", "Southern Incognita": "Terra Incognito",
              "Eastern Incognita": "Terra Incognito", "Farwest Isles": "Terra Incognito",
              "Northern Isles": "Terra Incognito", "Southern Shoals": "Terra Incognito",
              "Northern Ice": "Terra Incognito", "Southern Ice": "Ayam Sea", "Vesuvians": "Western Archipelago",
              "Combustion Ayam": "Ayam Sea", "Pelari": "Ayam Sea", "Satian Islands": "Ayam Sea",
              "Eastern Archipelago": "Southern Sea", "Oceania": "Deep Blue"}
NEW_TRADE_SEATS = {"Terra Incognito": "Central Incognita", "Ayam Sea": "Combustion Ayam", "Deep Blue": "Oceania"}

# who holds what at the start (the rest is uncolonised)
NATIONS = {
    "AYM": dict(regions=["Combustion Ayam"], capital_near=(1400, 900), culture="Ayam", ethnicity="Chicken",
                religion="Combustion Creed", dev=(7, 11), capital_name="Ayam Prime"),
    "SLK": dict(regions=["Central Incognita"], capital_near=(640, 520), count=9, culture="Silken", ethnicity="Incognitan",
                religion="The Long Road", dev=(5, 9), capital_name="Silkgate"),
    "OCE": dict(regions=["Oceania"], capital_near=OCEANIA_CENTRE, culture="Oceanian", ethnicity="Oceanian",
                religion="The Deep", dev=(5, 8), capital_name="Leviathan Throne"),
    # the other peoples of the "Ayam universe" in Arcadia - The Eschaton, on Terra Incognito
    "FUA": dict(regions=["Northern Incognita"], capital_near=(560, 330), count=9, culture="Fuarlander", ethnicity="Fuarlander",
                religion="The Old Fires", dev=(6, 10), capital_name="Fuar Hold"),
    "STE": dict(regions=["Eastern Incognita"], capital_near=(900, 620), count=8, culture="Stellarin", ethnicity="Stellarin",
                religion="The Starpath", dev=(5, 9), capital_name="Stellara"),
    "LLA": dict(regions=["Western Incognita"], capital_near=(280, 500), count=6, culture="Llaman", ethnicity="Llama",
                religion="The Long Road", dev=(4, 7), capital_name="Highpasture"),
    # the Satian Union (Arcadia - The Eschaton: "improved, but still below a Type 1"): all the Satian Islands
    "SAT": dict(regions=["Satian Islands"], capital_near=(1850, 925), culture="Satian", ethnicity="Satian",
                religion="The Tidewheel", dev=(3, 6), capital_name="Satia"),
}

SYLLABLES = {
    "Incognita": (["Ul", "Ver", "Ash", "Mor", "Kal", "Tess", "Or", "Bel", "Quin", "Sar", "Dra", "Hal", "Ny", "Vel", "Cor",
                   "Ith", "Zan", "Rho", "Lum", "Fen"],
                  ["dra", "mere", "thal", "vane", "holm", "garde", "wick", "ros", "dun", "mar", "teth", "loch", "vale",
                   "rith", "keld", "moor", "shan", "ford"]),
    "Ice": (["Frost", "Rime", "White", "Hoar", "Glacier", "Snow", "Pale", "Ice"],
            [" Shelf", " Waste", " Expanse", " Crown", " Reach", " Field", " Wall"]),
    "Isles": (["Gull", "Salt", "Kelp", "Reef", "Tide", "Spray", "Shell", "Storm", "Mist", "Drift", "Pearl", "Wave"],
              [" Isle", " Key", " Rock", " Cay", " Atoll", " Skerry", " Holm"]),
    "Ayam": (["Cluck", "Ember", "Pyre", "Spur", "Comb", "Wattle", "Flare", "Cinder", "Brood", "Plume"],
             ["haven", "forge", "roost", "burn", "crest", "kiln", "spire", "hatch"]),
    "Oceania": (["Abyss", "Coral", "Trench", "Pelagic", "Kraken", "Brine", "Fathom", "Sunken", "Leviathan"],
                [" Deep", " Spire", " Throne", " Garden", " Hollow", " Vault"]),
}
NAME_STYLE = {"Northern Ice": "Ice", "Southern Ice": "Ice", "Combustion Ayam": "Ayam", "Oceania": "Oceania"}
for r in ("Farwest Isles", "Northern Isles", "Southern Shoals", "Vesuvians", "Pelari", "Satian Islands",
          "Eastern Archipelago"):
    NAME_STYLE[r] = "Isles"

TERRAIN_COLOURS = {"glacier": (0.90, 0.92, 0.95), "abyss": (0.05, 0.16, 0.30)}
GOODS = {
    "grassland": {"grain": 3, "livestock": 3, "wool": 1, "fruit": 1},
    "forest": {"timber": 4, "furs": 1, "dyes": 1, "spices": 1},
    "drylands": {"salt": 2, "spices": 2, "copper": 1, "livestock": 1},
    "mountains": {"iron": 2, "copper": 2, "gems": 1, "marble": 1},
    "coast": {"fish": 4, "salt": 1, "pearls": 1},
    "glacier": {"ice": 4, "furs": 2},
    "volcanic": {"sulfur": 3, "glass": 1},
    "abyss": {"pearls": 3, "fish": 2, "crystals": 1},
}


# --------------------------------------------------------------------------- inputs

def keep_pristine():
    """The first run saves the mainland-only map so later runs start from it again."""
    for f in ("ground_index.png", "ground_terrain.png", "ground_provinces.png", "ground_map.json"):
        dst = os.path.join(SRC, "mainland_" + f)
        if not os.path.exists(dst):
            shutil.copy(os.path.join(MAP, f), dst)
    dst = os.path.join(SRC, "mainland_provinces.json")
    if not os.path.exists(dst):
        shutil.copy(os.path.join(ROOT, "data", "provinces.json"), dst)


def load_old():
    idx = np.array(Image.open(os.path.join(SRC, "mainland_ground_index.png")).convert("RGB")).astype(np.int32)
    ids = idx[..., 0] + 256 * idx[..., 1]
    terr = np.array(Image.open(os.path.join(SRC, "mainland_ground_terrain.png")).convert("RGB")).astype(float) / 255.0
    meta = json.load(open(os.path.join(SRC, "mainland_ground_map.json")))
    # provinces: take the CURRENT file's old entries, so hand edits since the first run are kept
    cur = json.load(open(os.path.join(ROOT, "data", "provinces.json")))
    pristine_ids = {p["id"] for p in json.load(open(os.path.join(SRC, "mainland_provinces.json")))["provinces"]}
    provs = [p for p in cur["provinces"] if p["id"] in pristine_ids]
    return ids, terr, meta, provs


def world_land():
    w = np.array(Image.open(WORLD).convert("RGB")).astype(int)
    r, g, b = w[..., 0], w[..., 1], w[..., 2]
    water = (b > r + 30) & (b > g + 5)
    yellow = (r > 190) & (g > 160) & (b < 90)
    land = ~water & ~yellow
    for x0, y0, x1, y1 in LABELS:
        land[y0:y1, x0:x1] = False
    land = ndimage.binary_opening(land, np.ones((3, 3), bool))   # thin lettering and outlines
    lab, n = ndimage.label(land)
    sizes = ndimage.sum(land, lab, range(1, n + 1))
    keep = np.zeros(n + 1, bool)
    keep[1:] = sizes >= 40
    return keep[lab], w.astype(float) / 255.0


# --------------------------------------------------------------------------- assembly

def layout():
    sx = (OLD_MAIN_BBOX[2] - OLD_MAIN_BBOX[0]) / (WORLD_MAIN_BBOX[2] - WORLD_MAIN_BBOX[0])
    sy = (OLD_MAIN_BBOX[3] - OLD_MAIN_BBOX[1]) / (WORLD_MAIN_BBOX[3] - WORLD_MAIN_BBOX[1])
    s = (sx + sy) / 2.0
    dx = int(round(WORLD_SPLIT_X * s)) + GAP - OLD_LAND_X0     # where the old map's (0, 0) goes
    dy = 0
    dxr = dx + OLD_MAIN_BBOX[0] - WORLD_MAIN_BBOX[0] * s        # right-half world -> canvas
    dyr = dy + OLD_MAIN_BBOX[1] - WORLD_MAIN_BBOX[1] * s
    width = dx + 2000
    height = int(max(1104 * s, 1092 + dy, 1104 * s + dyr)) + 1
    return s, dx, dy, dxr, dyr, width, height


def world_to_canvas(x, y, s, dxr, dyr):
    if x < WORLD_SPLIT_X:
        return x * s, y * s
    return x * s + dxr, y * s + dyr


def place_world(land_w, colour_w, s, dxr, dyr, width, height):
    """World land and world colours on the canvas (left half and right half)."""
    yy, xx = np.mgrid[0:height, 0:width].astype(float)
    land = np.zeros((height, width), bool)
    colour = np.zeros((height, width, 3))
    for left in (True, False):
        wx = xx / s if left else (xx - dxr) / s
        wy = yy / s if left else (yy - dyr) / s
        ok = (wx >= 0) & (wx < 1999) & (wy >= 0) & (wy < 1104) & ((wx < WORLD_SPLIT_X) if left else (wx >= WORLD_SPLIT_X))
        ix = np.clip(wx.astype(int), 0, 1998)
        iy = np.clip(wy.astype(int), 0, 1103)
        land |= ok & land_w[iy, ix]
        colour[ok] = colour_w[iy[ok], ix[ok]]
    return land, colour


def region_map(land, s, dxr, dyr):
    pts = np.array([world_to_canvas(x, y, s, dxr, dyr) for _, x, y in ANCHORS])
    names = np.array([n for n, _, _ in ANCHORS], dtype=object)
    ys, xs = np.nonzero(land)
    # wobble the borders between regions so they don't run in straight lines across the land
    rng = np.random.default_rng(77)
    jx = (gm.smooth_noise(land.shape, 28, rng) - 0.5) * 220
    jy = (gm.smooth_noise(land.shape, 28, rng) - 0.5) * 220
    qx = xs + jx[ys, xs]
    qy = ys + jy[ys, xs]
    d = ((qx[:, None] - pts[None, :, 0]) ** 2 + (qy[:, None] - pts[None, :, 1]) ** 2)
    region = np.full(land.shape, "", dtype=object)
    region[ys, xs] = names[np.argmin(d, axis=1)]
    return region


def oceania_mask(shape, s, rng):
    cx, cy = world_to_canvas(*OCEANIA_CENTRE, s, 0, 0)
    m = np.zeros(shape, bool)
    for i, (ox, oy, r) in enumerate([(0, 0, 70), (-75, 10, 48), (70, -15, 52), (10, 62, 45)]):
        old_h, old_w = gm.H, gm.W
        gm.H, gm.W = shape
        m |= gm.blob_mask(cx + ox, cy + oy, r, rng, wobble=0.4)
        gm.H, gm.W = old_h, old_w
    return m


def partition_new(land, region, first_id, rng):
    ids = np.zeros(land.shape, np.int32)
    shapes = []
    pid = first_id
    wx2 = (gm.smooth_noise(land.shape, 10, rng) - 0.5) * 30
    wy2 = (gm.smooth_noise(land.shape, 10, rng) - 0.5) * 30
    for rname in TARGET_AREA:
        rmask = land & (region == rname)
        lab, n = ndimage.label(rmask)
        if n == 0:
            continue
        sizes = ndimage.sum(rmask, lab, range(1, n + 1))
        for i in np.argsort(-sizes):
            area = sizes[i]
            if area < gm.MIN_PIECE * 0.6:
                continue
            ys, xs = np.nonzero(lab == i + 1)
            k = max(1, int(round(area / TARGET_AREA[rname])))
            if k == 1:
                ids[ys, xs] = pid
                shapes.append((pid, rname))
                pid += 1
                continue
            pts = np.stack([xs + wx2[ys, xs], ys + wy2[ys, xs]], 1)
            sample = pts[rng.choice(len(pts), min(6000, len(pts)), replace=False)]
            seeds = gm.lloyd(sample, gm.farthest_point_seeds(sample, k, rng))
            owner = np.argmin(((pts[:, None, :] - seeds[None, :, :]) ** 2).sum(-1), axis=1)
            for j in range(k):
                if (owner == j).sum() == 0:
                    continue
                ids[ys[owner == j], xs[owner == j]] = pid
                shapes.append((pid, rname))
                pid += 1
    return ids, shapes


def terrain_of(colour_px, rname):
    if rname in ("Northern Ice", "Southern Ice"):
        return "glacier"
    if rname == "Oceania":
        return "abyss"
    c = colour_px.mean(0)
    r, g, b = c
    bright = c.mean()
    if bright > 0.68 and abs(r - b) < 0.08:
        return "glacier" if bright > 0.8 else "mountains"
    if bright > 0.50 and r > g * 1.05 and r > b * 1.3:
        return "drylands"
    if g > r * 1.15 and bright < 0.30:
        return "forest"
    if abs(r - g) < 0.06 and bright > 0.45:
        return "mountains"
    return "grassland"


def names_for(shapes, rng):
    used = set()
    out = {}
    for pid, rname in shapes:
        style = NAME_STYLE.get(rname, "Incognita")
        a, b = SYLLABLES[style]
        for _ in range(200):
            nm = a[int(rng.integers(len(a)))] + b[int(rng.integers(len(b)))]
            if nm not in used:
                break
        used.add(nm)
        out[pid] = nm
    return out


def weighted(rng, w):
    k = list(w)
    p = np.array([w[x] for x in k], float)
    return k[int(rng.choice(len(k), p=p / p.sum()))]


def main():
    keep_pristine()
    old_ids, old_terr, old_meta, old_provs = load_old()
    land_w, colour_w = world_land()
    s, dx, dy, dxr, dyr, W, H = layout()
    print(f"scale {s:.3f}, old map at ({dx}, {dy}), canvas {W} x {H}")

    ids = np.zeros((H, W), np.int32)
    oh, ow = old_ids.shape
    ids[dy:dy + oh, dx:dx + ow] = old_ids
    old_land = ids > 0

    new_land, colour = place_world(land_w, colour_w, s, dxr, dyr, W, H)
    # inside the old rectangle only open sea well away from the old coasts may become new land
    inside = np.zeros((H, W), bool)
    inside[dy:dy + oh, dx:dx + ow] = True
    far = ndimage.distance_transform_edt(~old_land) > 40
    new_land &= ~old_land & (~inside | far)
    ocean = oceania_mask((H, W), s, RNG) & ~old_land
    new_land &= ~ocean
    region = region_map(new_land, s, dxr, dyr)
    region[ocean] = "Oceania"
    new_land |= ocean

    first_id = max(p["id"] for p in json.load(open(os.path.join(ROOT, "data", "provinces.json")))["provinces"]
                   if p["id"] in {q["id"] for q in old_provs}) + 1
    first_id = max(first_id, max(p["id"] for p in old_provs) + 1)
    new_ids, shapes = partition_new(new_land, region, first_id, RNG)
    gm.H, gm.W = H, W
    new_ids = gm.clean_components(new_ids, new_ids > 0)
    ids[new_ids > 0] = new_ids[new_ids > 0]
    present = set(np.unique(new_ids).tolist())
    shapes = [(p, r) for p, r in shapes if p in present]

    # ---- new provinces
    names = names_for(shapes, RNG)
    land_all = ids > 0
    coast_ring = ndimage.binary_dilation(~land_all, np.ones((3, 3), bool)) & land_all
    new_provs = []
    for pid, rname in shapes:
        m = ids == pid
        coastal = bool((coast_ring & m).any())
        terrain = terrain_of(colour[m], rname)
        if coastal and terrain == "grassland" and RNG.random() < 0.3:
            terrain = "coast"
        goods = weighted(RNG, GOODS.get(terrain, GOODS["grassland"]))
        flags = ["coastal"] if coastal else []
        if rname == "Oceania":
            flags.append("underwater")
        new_provs.append(dict(id=pid, name=names[pid], region=rname, layer="ground", owner=None, terrain=terrain,
                              goods=goods, development=[1, 1, 1], flags=flags, culture="", ethnicity="", religion="",
                              trade_node=TRADE_NODE[rname], links=[]))

    # ---- nations of the new world
    by_id = {p["id"]: p for p in new_provs}
    cent = {p["id"]: np.argwhere(ids == p["id"]).mean(0)[::-1] for p in new_provs}
    for tag, spec in NATIONS.items():
        cands = [p for p in new_provs if p["region"] in spec["regions"]]
        cx, cy = world_to_canvas(*spec["capital_near"], s, dxr, dyr)
        cands.sort(key=lambda p: (cent[p["id"]][0] - cx) ** 2 + (cent[p["id"]][1] - cy) ** 2)
        take = cands[:spec.get("count", len(cands))]
        drng = np.random.default_rng(zlib.crc32(tag.encode()))   # stable: Python's hash() changes every run
        for i, p in enumerate(take):
            p["owner"] = tag
            p["culture"], p["ethnicity"], p["religion"] = spec["culture"], spec["ethnicity"], spec["religion"]
            lo, hi = spec["dev"]
            total = int(drng.integers(lo, hi + 1)) + (3 if i == 0 else 0)
            split = drng.dirichlet([2, 2, 2])
            p["development"] = [max(1, int(round(total * x))) for x in split]
            if i == 0:
                p["flags"].append("capital")
                p["name"] = spec["capital_name"]
        print(f"{tag}: {len(take)} provinces, capital {take[0]['name']}")
    # uncolonised natives keep dev 1-2
    for p in new_provs:
        if p["owner"] is None:
            p["development"] = [int(RNG.integers(1, 3)), 1, int(RNG.integers(1, 3))]

    # ---- terrain image: generated sea for the whole world, old land as it was, new land painted
    gm.H, gm.W = H, W
    # the world loops east-west, so measure the sea (and lay its noise) as if the map repeats
    dist_sea = ndimage.distance_transform_edt(np.concatenate([~land_all] * 3, axis=1))[:, W:2 * W]
    depth = np.clip(dist_sea / 160.0, 0, 1)
    terr = np.stack([0.13 + 0.10 * (1 - depth), 0.30 + 0.15 * (1 - depth), 0.52 + 0.12 * (1 - depth)], -1)
    sea_noise = ndimage.gaussian_filter(RNG.standard_normal((H, W)), 18, mode="wrap")
    sea_noise = (sea_noise - sea_noise.min()) / (sea_noise.max() - sea_noise.min() + 1e-9)
    terr += (sea_noise[..., None] - 0.5) * 0.04
    shallow = (~land_all) & (dist_sea < 7)
    terr[shallow] = terr[shallow] * 0.65 + 0.35 * np.array([0.55, 0.72, 0.80])
    old_block = terr[dy:dy + oh, dx:dx + ow]
    ol = old_ids > 0
    old_block[ol] = old_terr[ol]
    terr[dy:dy + oh, dx:dx + ow] = old_block
    nl = new_ids > 0
    painted = colour.copy()
    painted = 0.15 + 0.80 * painted   # a touch lighter, like the old map's land
    terr[nl] = painted[nl]
    deep = ids_in = np.isin(ids, [p["id"] for p in new_provs if "underwater" in p["flags"]])
    swirl = gm.smooth_noise((H, W), 6, RNG)
    terr[deep] = np.stack([0.05 + 0.06 * swirl, 0.20 + 0.10 * swirl, 0.34 + 0.12 * swirl], -1)[deep]

    # ---- write the layer (neighbours and lanes for everything, old colours kept)
    allp = old_provs + new_provs
    ground = [p for p in allp if p["layer"] == "ground"]
    seats = {k: [v[0] + dx, v[1] + dy] for k, v in old_meta.get("trade_seats", {}).items()}
    for node, rname in NEW_TRADE_SEATS.items():
        ps = [p for p in new_provs if p["region"] == rname]
        if ps:
            c = cent[max(ps, key=lambda p: sum(p["development"]))["id"]]
            seats[node] = [int(c[0]), int(c[1])]
    print("computing neighbours and sea lanes...")
    meta = write_ground(ids, ground, terr, old_meta, dict(trade_seats=seats, offset=[dx, dy]), W, H)

    out = os.path.join(ROOT, "data", "provinces.json")
    with open(out, "w") as f:
        f.write('{\n "_note": "Generated by tools/generate_map.py (the mainland and Skyfall) and tools/build_world.py '
                '(the rest of the world; those provinces are regenerated on every run). id and layer must match the '
                'map images.",\n "provinces": [\n')
        f.write(",\n".join("  " + json.dumps(p) for p in allp))
        f.write("\n ]\n}\n")
    counts = {}
    for p in new_provs:
        counts[p["region"]] = counts.get(p["region"], 0) + 1
    print(f"world: {len(new_provs)} new provinces {counts}")


def write_ground(ids, provinces, terr, old_meta, extra, W, H):
    adj, lanes = neighbours_fast(ids, provinces, SEA_REACH)
    # the mainland keeps exactly the borders and sea lanes it had; only links to new land are added
    old = {int(k): v for k, v in old_meta["provinces"].items()}
    for pid in old:
        if pid in adj:
            adj[pid] = {q for q in adj[pid] if q not in old} | set(old[pid]["neighbours"])
            lanes[pid] = {q for q in lanes[pid] if q not in old} | set(old[pid]["lanes"])
    for pid in list(adj):   # keep both directions in step
        for q in list(adj[pid]):
            adj[q].add(pid)
        for q in list(lanes[pid]):
            lanes[q].add(pid)
    gm.H, gm.W = H, W
    add_ocean_crossings(ids, provinces, adj, lanes)
    gm.connect_components(provinces, adj, lanes, ids)
    rng = np.random.default_rng(7)
    used = {tuple(v["colour"]) for v in old_meta["provinces"].values()}
    bitmap = np.zeros((H, W, 3), np.uint8)
    meta = {}
    objs = ndimage.find_objects(ids)
    for p in provinces:
        pid = p["id"]
        old = old_meta["provinces"].get(str(pid))
        col = tuple(old["colour"]) if old else gm.colour_for(rng, used)
        sl = objs[pid - 1]
        m = ids[sl] == pid
        bitmap[sl][m] = col
        cy, cx = centre_in(m)
        meta[str(pid)] = dict(colour=list(col), centre=[int(cx + sl[1].start), int(cy + sl[0].start)],
                              area=int(m.sum()), neighbours=sorted(adj[pid]), lanes=sorted(lanes[pid]))
    index = np.zeros((H, W, 3), np.uint8)
    index[..., 0] = ids % 256
    index[..., 1] = ids // 256
    Image.fromarray(bitmap).save(os.path.join(MAP, "ground_provinces.png"))
    Image.fromarray(index).save(os.path.join(MAP, "ground_index.png"))
    Image.fromarray((np.clip(terr, 0, 1) * 255).astype(np.uint8)).save(os.path.join(MAP, "ground_terrain.png"))
    out = dict(width=W, height=H, provinces=meta)
    out.update(extra)
    with open(os.path.join(MAP, "ground_map.json"), "w") as f:
        json.dump(out, f, indent=1)
    return meta


def add_ocean_crossings(ids, provinces, adj, lanes):
    """The world loops east-west: link the nearest coasts across the seam, one crossing in the north and
    one in the south, so ships (and armies with transports) can sail round the world."""
    H, W = ids.shape
    objs = ndimage.find_objects(ids)
    cent = {}
    for p in provinces:
        if "coastal" in p["flags"] and "underwater" not in p["flags"]:
            sl = objs[p["id"] - 1]
            cent[p["id"]] = ((sl[1].start + sl[1].stop) / 2.0, (sl[0].start + sl[0].stop) / 2.0)
    west = [k for k, c in cent.items() if c[0] < W * 0.3]
    east = [k for k, c in cent.items() if c[0] > W * 0.7]
    for north in (True, False):
        best = None
        for a in east:
            for b in west:
                ya, yb = cent[a][1], cent[b][1]
                if (ya < H / 2) != north or (yb < H / 2) != north:
                    continue
                d = ((W - cent[a][0] + cent[b][0]) ** 2 + (ya - yb) ** 2) ** 0.5
                if best is None or d < best[0]:
                    best = (d, a, b)
        if best:
            lanes[best[1]].add(best[2])
            lanes[best[2]].add(best[1])
            print(f"ocean crossing: {best[1]} <-> {best[2]} ({best[0]:.0f} px across the seam)")


def centre_in(m):
    dist = ndimage.distance_transform_edt(np.pad(m, 1))[1:-1, 1:-1]
    return np.unravel_index(int(np.argmax(dist)), dist.shape)


def neighbours_fast(ids, provinces, sea_reach):
    """generate_map.neighbours, but each distance transform only looks at a window around the province."""
    adj = {p["id"]: set() for p in provinces}
    for a, b in ((ids[:, :-1], ids[:, 1:]), (ids[:-1, :], ids[1:, :])):
        m = (a != b) & (a > 0) & (b > 0)
        for x, y in set(zip(a[m].tolist(), b[m].tolist())):
            if x in adj and y in adj:
                adj[x].add(y)
                adj[y].add(x)
    lanes = {p["id"]: set() for p in provinces}
    objs = ndimage.find_objects(ids)
    H, W = ids.shape
    coastal = [p["id"] for p in provinces if "coastal" in p["flags"]]
    cset = set(coastal)
    dist = {}
    pad = sea_reach * 3
    for pid in coastal:
        sl = objs[pid - 1]
        y0, y1 = max(0, sl[0].start - pad), min(H, sl[0].stop + pad)
        x0, x1 = max(0, sl[1].start - pad), min(W, sl[1].stop + pad)
        win = ids[y0:y1, x0:x1]
        d = ndimage.distance_transform_edt(win != pid)
        near = {}
        for q in np.unique(win).tolist():
            if q != pid and q in cset:
                near[q] = float(d[win == q].min())
        dist[pid] = near
    for pid in coastal:
        near = sorted(dist[pid].items(), key=lambda kv: kv[1])
        for q, dq in near:
            if q not in adj[pid] and dq <= sea_reach:
                lanes[pid].add(q)
                lanes[q].add(pid)
        if len(adj[pid]) == 0 and len(lanes[pid]) < 2:
            for q, dq in near[:2]:
                if q not in adj[pid]:
                    lanes[pid].add(q)
                    lanes[q].add(pid)
    return adj, lanes


if __name__ == "__main__":
    main()
