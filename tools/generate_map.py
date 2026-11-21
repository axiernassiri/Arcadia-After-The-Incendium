#!/usr/bin/env python3
"""Generate Arcadia's province maps from the traced lore map.

Reads  map/source/land_mask.png and map/source/region_mask.png (made by tools/trace_lore_map.py
from map/source/lore_map.png, or painted by hand) and writes, for each layer (ground, sky):
  map/<layer>_provinces.png  - paintable province bitmap, one flat colour per province
  map/<layer>_index.png      - same shapes, province id encoded as R + 256*G (read by the game)
  map/<layer>_terrain.png    - shading underlay (terrain colours, relief, sea, sky)
  map/<layer>_map.json       - per-province colour, centre, area, neighbours (derived; never edit by hand)
and data/provinces.json (names, owners, goods, development, culture...) ONLY if it does not exist yet
or --force-provinces is given, so hand edits to provinces.json survive regeneration.

Usage:  python3 tools/generate_map.py [--force-provinces]
Needs: numpy, scipy, Pillow.
"""
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "map", "source")
W, H = 2000, 1092
RNG = np.random.default_rng(4289)  # the year the Arcadian Era begins

REGION_COLOURS = {
    "Mentos": (80, 140, 255), "Frost Reach": (180, 220, 255), "Sylvania": (60, 200, 90),
    "Midrea": (170, 80, 220), "Eurome": (200, 110, 60), "Western Archipelago": (150, 150, 150),
    "Southwest Island": (240, 220, 60), "Southern Isles": (60, 220, 220),
}
# target province size (game pixels) per region: smaller = more provinces
TARGET_AREA = {"Mentos": 4300, "Frost Reach": 4000, "Sylvania": 4000, "Midrea": 3900, "Eurome": 3900,
               "Western Archipelago": 900, "Southwest Island": 3000, "Southern Isles": 2200}
MIN_PIECE = 260          # islands smaller than this (game px) are merged into a neighbour

# ---------------------------------------------------------------------------
# Design. Positions are in LORE-MAP pixels (1251 x 682), so they can be read straight off the drawing.
# ---------------------------------------------------------------------------
LORE_W, LORE_H = 1251, 682
ANCHORS = [
    # (name, region, (x, y) on the lore map, overrides)
    ("Mentos", "Mentos", (600, 185), dict(dev=[5, 5, 4], flags=["capital"], goods="lotus", terrain="grassland")),
    ("Lotus Vale", "Mentos", (545, 200), dict(goods="lotus", terrain="grassland")),
    ("Canada Ruins", "Mentos", (470, 150), dict(goods="relics", terrain="hills")),          # the Pig Lord's old home
    ("Yellowstone Caldera", "Mentos", (420, 125), dict(goods="sulfur", terrain="volcanic", flags=["volcano"])),
    ("Falls Landing", "Mentos", (680, 245), dict(goods="water", terrain="hills")),
    ("Frost Reach", "Frost Reach", (790, 200), dict(goods="furs", terrain="tundra")),
    ("Bay of Pigs", "Sylvania", (405, 388), dict(goods="fish", terrain="coast")),
    ("Staircase Glade", "Sylvania", (485, 300), dict(goods="relics", terrain="anomalous", flags=["staircase"])),
    ("Midrea Labworks", "Midrea", (600, 330), dict(goods="tech", terrain="hills", dev=[3, 5, 2])),
    ("Space Observatory", "Midrea", (690, 410), dict(goods="tech", terrain="hills", flags=["observatory"])),
    ("Avalanche Pass", "Midrea", (735, 285), dict(hidden=True)),
    ("White Haze", "Midrea", (765, 300), dict(hidden=True, goods="gems")),
    ("Waterfall Peaks", "Midrea", (775, 345), dict(hidden=True, goods="water")),
    ("The Center", "Midrea", (750, 325), dict(hidden=True, goods="crystals", terrain="anomalous", flags=["mist"],
                                             dev=[2, 3, 1])),
    ("Eurome Fields", "Eurome", (680, 470), dict(goods="grain", terrain="farmland", dev=[4, 3, 3])),
    ("Ore Isle", "Western Archipelago", (385, 480), dict(goods="iron", flags=["mine_site"])),
    ("Mine Key", "Western Archipelago", (395, 560), dict(goods="iron", flags=["mine_site"])),
    ("Unity", "Southern Isles", (560, 612), dict(owner="MEN", goods="steel", terrain="fortress",
                                                  flags=["unity_base"], dev=[2, 2, 4])),
    ("Vesuvius", "Southern Isles", (790, 600), dict(owner=None, goods="sulfur", terrain="volcanic", flags=["volcano"])),
    ("Equator Isle", "Southern Isles", (1010, 337), dict(goods="water", terrain="coast", flags=["waterfall_base"], dev=[2, 2, 2])),
]
NAME_POOLS = {
    "Mentos": ["Pigwood", "Trufflebrook", "Hogsmere", "Snowsnout", "Northpen", "Boarhaven", "Sowbridge", "Oinkfield",
               "Pinkstone", "Hamlet Cove", "Curlytail", "Tuskmoor", "Mudwallow", "Whitefrost Bay", "Bristleback",
               "Lardmere", "Piggston", "Rindhold", "Silvermud", "Snowtrough", "Hoofcrest", "Coldsty", "Porkstead",
               "Grunting Hills", "Swillmarsh", "Baconvale", "Hogback Ridge", "Squealwater", "Mudpie Downs",
               "Ham Hollow", "Glacier Gate", "Frostsnout", "Pennyhoof", "Truffle Downs", "Sty Royal"],
    "Frost Reach": ["Snowtusk Fells", "Icejaw", "Rimeback", "Hoarfrost Point", "Glimmerice"],
    "Sylvania": ["Sylvan Deep", "Snoutshore", "Tusk Hollow", "Piglet Coast", "Mossy Trough", "Fernsnout", "Oakroot",
                 "Acorn Reach", "Greenhoof", "Willowsty", "Bramblepen", "Hazelmud", "Thornwallow", "Elderwood",
                 "Mosshog", "Sylvan Gate", "Pinesnout", "Rootdig", "Leafwallow", "Barkbristle", "Wildsow Glen",
                 "Dewpond", "Ferncombe"],
    "Midrea": ["Midrea Foothills", "Gearhollow", "Copper Snout", "Ironpen", "Steamsty", "Crystal Rise", "Marble Hog",
               "Prism Pass", "Coilworks", "Signal Peak", "Lenscombe", "Quartz Trough", "Dynamo Downs", "Circuit Vale",
               "Rivet Ridge", "Voltmire"],
    "Eurome": ["Grainhold", "Barleymarch", "Cornrow", "Hayfold", "Silo Plains", "Wheatwallow", "Oatstead", "Ryefield",
               "Millsnout", "Harvest Bay", "Haybale Heath", "Clover Sty", "Sunfurrow", "Duskfield", "Orchard Pen",
               "Turnip Downs", "Beetmarsh", "Ploughshare", "Granary Point", "Scarecrow Cape", "Sowland",
               "Dustfurrow", "Vineyard Coast", "Southfurrow"],
    "Western Archipelago": ["Slag Isle", "Copper Key", "Pickaxe Isle", "Shaft Rock", "Ironhoof Isle", "Lantern Key",
                            "Saltjaw Isle", "Gravel Key", "Quarry Isle", "Nugget Isle", "Tinsnout Key", "Deepdig Isle",
                            "Pebble Isle", "Flint Key", "Cobble Isle", "Ingot Rock"],
    "Southwest Island": ["Driftboar Shore", "Palmtusk", "Coconut Hollow", "Reefhoof", "Sunwallow", "Saltmarsh Point",
                         "Mango Sty", "Tidepen", "Lagoon Snout"],
    "Southern Isles": ["Coral Snout", "Pearl Isle", "Shellwallow", "Kelp Key", "Tide Isle", "Gull Rock", "Sandsnout",
                       "Lagoon Isle", "Driftwood Key", "Starfish Isle", "Brine Isle", "Spray Rock", "Seafoam Isle",
                       "Conch Key", "Urchin Isle", "Reef Rock"],
}
# names for small islands (pieces under ISLET_AREA) in any region
ISLET_POOL = ["Hogsfoot Isle", "Little Piglet Isle", "Snout Rocks", "Gull Isle", "Acorn Isle", "Mossy Isle",
              "Fern Key", "Lens Isle", "Haystack Isle", "Midrea Key", "Bristle Rock", "Curl Isle", "Trotter Key",
              "Muzzle Rock", "Pink Isle", "Wallow Key"]
ISLET_AREA = 3000
# region -> (culture, ethnicity, religion) for Menslosian land; tribes use TRIBES
MEN_CULTURE = {"Mentos": ("Mentosian", "Pig"), "Sylvania": ("Sylvanian", "Pig"), "Midrea": ("Midrean", "Pigman"),
               "Eurome": ("Euromean", "Pig"), "Western Archipelago": ("Archipelagan", "Pigman"),
               "Southern Isles": ("Archipelagan", "Pigman")}
TRIBES = {"SNT": ("Snowtusk", "Boar"), "SAL": ("Saltjaw", "Boar"), "DRF": ("Driftboar", "Boar"),
          "CRL": ("Coralsnout", "Boar"), "CDH": ("Cinderhoof", "Boar")}
# The pig states that hold the land Menslosia lost after the Incendium: (culture, people)
PIG_STATES = {"SYL": ("Sylvanian", "Pig"), "BAY": ("Sylvanian", "Pig"), "EUR": ("Euromean", "Pig"),
              "RYE": ("Euromean", "Pig"), "MID": ("Midrean", "Pigman")}
# Who holds what at the start. Provinces not listed fall back to the region rules in design_ground.
OWNERS = {
    "MEN": ["Canada Ruins", "Oinkfield", "Piggston", "Hamlet Cove", "Curlytail", "Truffle Downs", "Sty Royal",
            "Lotus Vale", "Lardmere", "Mentos", "Coldsty", "Pigwood", "Whitefrost Bay", "Falls Landing", "Rindhold",
            "Bristleback", "Squealwater", "Mudwallow", "Sowbridge", "Midrea Labworks", "Dynamo Downs", "Marble Hog",
            "Gearhollow", "Ore Isle", "Slag Isle", "Unity"],
    "CDH": ["Yellowstone Caldera", "Swillmarsh", "Snowtrough", "Mudpie Downs"],
    "SNT": ["Boarhaven", "Glacier Gate", "Baconvale", "Grunting Hills", "Hoarfrost Point", "Frost Reach", "Icejaw"],
    "SYL": ["Sylvan Gate", "Staircase Glade", "Willowsty", "Wildsow Glen", "Elderwood", "Mosshog", "Rootdig",
            "Mossy Trough", "Tusk Hollow", "Dewpond", "Snoutshore", "Sylvan Deep"],
    "BAY": ["Bay of Pigs", "Leafwallow", "Thornwallow", "Oakroot", "Barkbristle", "Fernsnout", "Bramblepen", "Ferncombe"],
    "MID": ["Midrea Foothills", "Signal Peak", "Lenscombe", "Space Observatory", "Voltmire", "Prism Pass"],
    "EUR": ["Granary Point", "Vineyard Coast", "Sowland", "Wheatwallow", "Southfurrow", "Cornrow", "Hayfold",
            "Barleymarch", "Eurome Fields", "Grainhold", "Harvest Bay", "Sunfurrow", "Scarecrow Cape"],
    "RYE": ["Turnip Downs", "Dustfurrow", "Duskfield", "Ryefield", "Millsnout", "Ploughshare", "Beetmarsh",
            "Little Piglet Isle"],
    "SKY": ["Equator Isle"],
}
OWNER_OF = {name: tag for tag, names in OWNERS.items() for name in names}
# development per province at the start: (lowest, highest) total
DEV_RANGE = {"MEN": (5, 8), "SYL": (5, 9), "BAY": (5, 9), "EUR": (5, 9), "RYE": (4, 8), "MID": (5, 9),
             "SNT": (3, 6), "CDH": (3, 6), "SAL": (4, 7), "DRF": (4, 7), "CRL": (3, 5)}
TRADE_NODE = {"Mentos": "Arcadian Sea", "Frost Reach": "Arcadian Sea", "Sylvania": "Bay of Pigs", "Midrea": "Midrea",
              "Eurome": "Eurome", "Western Archipelago": "Western Archipelago",
              "Southwest Island": "Western Archipelago", "Southern Isles": "Southern Sea"}
# trade node seats: the stars on the lore map
TRADE_SEATS = {"Arcadian Sea": (195, 160), "Bay of Pigs": (390, 398), "Midrea": (720, 398), "Eurome": (645, 573),
               "Western Archipelago": (288, 635), "Southern Sea": (648, 665)}

MINE_GOODS = ("iron", "copper", "gems", "crystals", "salt", "sulfur", "marble")
REGION_THEME = {
    # region: (terrain weights, goods weights)
    "Mentos": ({"grassland": 3, "forest": 3, "hills": 2}, {"livestock": 3, "timber": 2, "truffles": 2, "wool": 2,
                                                          "grain": 2, "lotus": 1}),
    "Frost Reach": ({"tundra": 3, "mountains": 1}, {"furs": 3, "ice": 2}),
    "Sylvania": ({"forest": 5, "grassland": 1, "hills": 1}, {"timber": 3, "truffles": 3, "cloth": 1, "lotus": 1,
                                                            "livestock": 1}),
    "Midrea": ({"hills": 3, "mountains": 2}, {"copper": 2, "iron": 2, "gems": 1, "crystals": 1, "marble": 1,
                                              "glass": 1, "tech": 1}),
    "Eurome": ({"farmland": 4, "grassland": 2, "drylands": 2}, {"grain": 4, "livestock": 2, "wine": 2, "cloth": 1,
                                                               "glass": 1}),
    "Western Archipelago": ({"hills": 3, "coast": 1}, {"iron": 3, "copper": 2, "gems": 1, "salt": 1}),
    "Southwest Island": ({"jungle": 3, "grassland": 1, "coast": 1}, {"spices": 3, "fruit": 2, "dyes": 2, "fish": 1}),
    "Southern Isles": ({"coast": 3, "grassland": 1}, {"fish": 3, "pearls": 2, "salt": 2, "spices": 1}),
}
NORTH_SNOW_Y = 150       # lore-map y: Mentos provinces north of this are snowfields

SKY_ISLANDS = [
    # (name, terrain, goods, dev, flags, cx, cy, radius) in game pixels; owner Skyfall unless listed in SKY_OWNERS
    ("Eden's Crown", "skyland", "core_energy", [6, 6, 6], ["capital", "core"], 1000, 500, 150),
    ("Holy Waterfall of Eden", "skyland", "water", [2, 2, 2], ["waterfall_top"], 670, 640, 92),     # lore
    ("Portal Isle", "anomalous", "relics", [1, 1, 1], ["doomsday_portal"], 1580, 712, 72),          # lore
    ("Volcanic Deltas", "volcanic", "sulfur", [2, 2, 1], [], 1405, 850, 84),                       # lore
    ("Iced Plateau", "tundra", "ice", [1, 2, 1], [], 1655, 500, 86),                               # lore
    ("Staircase Spire", "anomalous", "relics", [1, 1, 1], ["staircase"], 1280, 258, 64),           # lore
    ("Napoleon's Foundry", "skyland", "steel", [2, 3, 2], [], 1295, 575, 96),
    ("Angelreach", "skyland", "holy_relics", [2, 1, 2], [], 735, 303, 84),
    ("Cloudfarm", "skyland", "grain", [2, 1, 2], [], 470, 440, 80),
    ("Windward Isle", "skyland", "cloud_cotton", [1, 1, 2], [], 1000, 850, 76),
    ("Seraph Rock", "skyland", "feathers", [1, 2, 1], [], 1020, 175, 60),
    ("Gale Point", "skyland", "cloud_cotton", [1, 1, 1], [], 300, 700, 62),
    ("Halo Isle", "skyland", "holy_relics", [1, 2, 1], [], 520, 870, 58),
    ("Lantern Isle", "skyland", "glass", [1, 1, 1], [], 1580, 1000, 52),
    ("Sunward Shelf", "skyland", "feathers", [2, 1, 1], [], 1780, 280, 60),
    ("Mistveil", "skyland", "water", [1, 1, 1], [], 1830, 760, 56),
    # the Order of the Black Moon: a smaller chain of islands that worships the Doomsday Portal
    ("Moonfall Rock", "anomalous", "relics", [2, 2, 2], ["capital"], 1790, 905, 66),
    ("Hollow Spire", "anomalous", "crystals", [1, 2, 1], [], 1935, 990, 46),
    ("Eclipse Isle", "volcanic", "sulfur", [1, 1, 2], [], 1700, 1045, 42),
    ("Shade Reef", "anomalous", "feathers", [1, 1, 1], [], 1955, 840, 40),
    ("Umbral Cay", "volcanic", "relics", [1, 1, 1], [], 1440, 1040, 40),
]
SKY_OWNERS = {"Moonfall Rock": "BLM", "Hollow Spire": "BLM", "Eclipse Isle": "BLM", "Shade Reef": "BLM",
              "Umbral Cay": "BLM"}

TERRAIN_COLOURS = {
    "grassland": (0.62, 0.72, 0.45), "farmland": (0.78, 0.74, 0.45), "forest": (0.36, 0.55, 0.33),
    "hills": (0.62, 0.58, 0.45), "mountains": (0.55, 0.52, 0.50), "tundra": (0.88, 0.91, 0.93),
    "drylands": (0.76, 0.60, 0.42), "jungle": (0.30, 0.52, 0.30), "coast": (0.72, 0.72, 0.55),
    "volcanic": (0.42, 0.33, 0.31), "anomalous": (0.60, 0.50, 0.70), "fortress": (0.58, 0.58, 0.58),
    "skyland": (0.85, 0.86, 0.80), "wasteland": (0.55, 0.50, 0.45),
}


def lore_to_game(x, y):
    return x * W / LORE_W, y * H / LORE_H


def game_to_lore(x, y):
    return x * LORE_W / W, y * LORE_H / H


def smooth_noise(shape, sigma, rng):
    n = ndimage.gaussian_filter(rng.standard_normal(shape), sigma)
    return (n - n.min()) / (n.max() - n.min() + 1e-9)


def blob_mask(cx, cy, r, rng, wobble=0.35):
    yy, xx = np.mgrid[0:H, 0:W]
    ang = np.arctan2(yy - cy, xx - cx)
    phase = rng.uniform(0, 2 * np.pi, 3)
    rr = r * (1 + wobble * 0.5 * (np.sin(3 * ang + phase[0]) * 0.5 + np.sin(5 * ang + phase[1]) * 0.3
                                  + np.sin(7 * ang + phase[2]) * 0.2))
    return (xx - cx) ** 2 + (yy - cy) ** 2 <= rr ** 2


def farthest_point_seeds(points, k, rng):
    seeds = [points[rng.integers(len(points))]]
    d = np.full(len(points), np.inf)
    for _ in range(k - 1):
        d = np.minimum(d, ((points - seeds[-1]) ** 2).sum(1))
        seeds.append(points[int(np.argmax(d))])
    return np.array(seeds, dtype=float)


def lloyd(points, seeds, iters=8):
    for _ in range(iters):
        owner = np.argmin(((points[:, None, :] - seeds[None, :, :]) ** 2).sum(-1), axis=1)
        for i in range(len(seeds)):
            m = points[owner == i]
            if len(m):
                seeds[i] = m.mean(0)
    return seeds


def clean_components(ids, valid):
    """Keep each province's largest connected piece; give strays and holes to the nearest province."""
    out = ids.copy()
    for pid in np.unique(ids[ids > 0]):
        lab, n = ndimage.label(ids == pid)
        if n > 1:
            sizes = ndimage.sum(ids == pid, lab, range(1, n + 1))
            keep = 1 + int(np.argmax(sizes))
            out[(lab > 0) & (lab != keep)] = 0
    holes = valid & (out == 0)
    if holes.any():
        _, (iy, ix) = ndimage.distance_transform_edt(out == 0, return_indices=True)
        out[holes] = out[iy[holes], ix[holes]]
    return out


def load_masks():
    land_img = Image.open(os.path.join(SRC, "land_mask.png")).convert("L")
    land = np.array(land_img.resize((W, H), Image.BILINEAR)).astype(float) / 255.0
    land = ndimage.gaussian_filter(land, 1.6) > 0.5
    # drop hairline artefacts (traced region outlines over the sea): real land is thicker than this
    lab, n = ndimage.label(land)
    thick = ndimage.maximum(ndimage.distance_transform_edt(land), lab, range(1, n + 1))
    keep = np.zeros(n + 1, bool)
    areas = ndimage.sum(land, lab, range(1, n + 1))
    thick = np.array(thick)
    keep[1:] = (thick >= 4.5) & ~((areas / np.maximum(thick, 1) ** 2 > 60) & (thick < 5.5))
    land = keep[lab]
    reg_img = np.array(Image.open(os.path.join(SRC, "region_mask.png")).convert("RGB").resize((W, H), Image.NEAREST))
    region = np.full((H, W), "", dtype=object)
    for name, col in REGION_COLOURS.items():
        region[(reg_img == np.array(col)).all(-1)] = name
    # land pixels without a region (resampling seams) take the nearest region
    known = region != ""
    _, (iy, ix) = ndimage.distance_transform_edt(~known, return_indices=True)
    region[land & ~known] = region[iy[land & ~known], ix[land & ~known]]
    return land, region


def partition(land, region, rng):
    ids = np.zeros((H, W), np.int32)
    shapes = []   # (pid, region, piece_area)
    pid = 1
    wx2 = (smooth_noise((H, W), 10, rng) - 0.5) * 34
    wy2 = (smooth_noise((H, W), 10, rng) - 0.5) * 34
    for rname in REGION_COLOURS:
        rmask = land & (region == rname)
        lab, n = ndimage.label(rmask)
        if n == 0:
            continue
        sizes = ndimage.sum(rmask, lab, range(1, n + 1))
        for i in np.argsort(-sizes):
            area = sizes[i]
            if area < MIN_PIECE:
                continue   # handled by clean_components below
            ys, xs = np.nonzero(lab == i + 1)
            k = max(1, int(round(area / TARGET_AREA[rname])))
            if k == 1:
                ids[ys, xs] = pid
                shapes.append((pid, rname, int(area)))
                pid += 1
                continue
            pts = np.stack([xs + wx2[ys, xs], ys + wy2[ys, xs]], 1)
            sample = pts[rng.choice(len(pts), min(6000, len(pts)), replace=False)]
            seeds = lloyd(sample, farthest_point_seeds(sample, k, rng))
            owner = np.argmin(((pts[:, None, :] - seeds[None, :, :]) ** 2).sum(-1), axis=1)
            for j in range(k):
                ids[ys[owner == j], xs[owner == j]] = pid
                shapes.append((pid, rname, int(area)))
                pid += 1
    ids = clean_components(ids, land)
    return ids, shapes


def weighted(rng, weights):
    keys = list(weights)
    w = np.array([weights[k] for k in keys], float)
    return keys[int(rng.choice(len(keys), p=w / w.sum()))]


def design_ground(ids, shapes, rng):
    centres = {pid: centre(ids, pid) for pid, _, _ in shapes}
    dist_sea = ndimage.distance_transform_edt(ids > 0)
    coastal = {pid: bool(((ids == pid) & (dist_sea <= 2)).any()) for pid, _, _ in shapes}
    regions = {pid: r for pid, r, _ in shapes}
    pieces = {pid: a for pid, _, a in shapes}
    names = {}
    overrides = {}
    for name, rname, (lx, ly), ov in ANCHORS:
        gx, gy = lore_to_game(lx, ly)
        island = ov.get("island", rname in ("Western Archipelago", "Southern Isles", "Southwest Island"))
        cands = [pid for pid in centres if regions[pid] == rname and pid not in names
                 and (island or pieces[pid] >= ISLET_AREA)]
        best = min(cands, key=lambda p: (centres[p][0] - gx) ** 2 + (centres[p][1] - gy) ** 2)
        names[best] = name
        overrides[best] = ov
    pools = {r: list(v) for r, v in NAME_POOLS.items()}
    for r in pools:
        rng.shuffle(pools[r])
    islets = list(ISLET_POOL)
    rng.shuffle(islets)
    counters = {}
    provinces = []
    for pid, rname, piece in shapes:
        if pid not in names:
            if piece < ISLET_AREA and rname not in ("Western Archipelago", "Southern Isles", "Southwest Island") \
                    and islets:
                names[pid] = islets.pop()
            elif pools.get(rname):
                names[pid] = pools[rname].pop()
            else:
                counters[rname] = counters.get(rname, 0) + 1
                names[pid] = f"{rname} {counters[rname]}"
        ov = overrides.get(pid, {})
        lx, ly = game_to_lore(*centres[pid])
        terr_w, goods_w = REGION_THEME[rname]
        terrain = weighted(rng, terr_w)
        if rname == "Mentos" and ly < NORTH_SNOW_Y:
            terrain = "tundra"
        if coastal[pid] and rng.random() < 0.35 and rname not in ("Frost Reach", "Midrea"):
            terrain = "coast"
        goods = weighted(rng, goods_w)
        if coastal[pid] and rng.random() < 0.25:
            goods = "fish" if rname not in ("Midrea", "Frost Reach") else goods
        if terrain == "tundra" and rname == "Mentos":
            goods = weighted(rng, {"furs": 2, "wool": 2, "ice": 1})
        flags = list(ov.get("flags", []))
        if coastal[pid]:
            flags.append("coastal")
        hidden = ov.get("hidden", False)
        if hidden:
            flags.append("hidden")
            terrain = ov.get("terrain", "mountains")
        # ownership
        if names[pid] in OWNER_OF:
            owner = OWNER_OF[names[pid]]
        elif "owner" in ov:
            owner = ov["owner"]
        elif hidden:
            owner = None
        elif rname == "Frost Reach":
            owner = "SNT"
        elif rname == "Southwest Island":
            owner = "DRF"
        elif rname == "Western Archipelago":
            owner = "SAL"
        elif rname == "Southern Isles":
            owner = "CRL" if lx < 700 else None
        else:
            owner = None   # scattered islets are uninhabited
        drng = np.random.default_rng(1000 + pid)   # its own dice, so changing one rule doesn't reshuffle the map
        if owner is None or owner not in DEV_RANGE:
            dev = [1, 1, 1]
        else:
            lo, hi = DEV_RANGE[owner]
            total = int(drng.integers(lo, hi + 1)) + (1 if rname == "Mentos" and owner == "MEN" else 0)
            split = drng.dirichlet([2, 2, 2])
            dev = [max(1, int(round(total * sp))) for sp in split]
            if rname == "Eurome":
                dev[0] += 1
            if rname == "Midrea":
                dev[1] += 1
        if "dev" in ov and owner in ("MEN", None):
            dev = ov["dev"]
        if owner in TRIBES:
            culture, ethnicity = TRIBES[owner]
            religion = "Mud Spirits"
        elif owner in PIG_STATES:
            culture, ethnicity = PIG_STATES[owner]
            religion = "Lotus Faith"
        elif owner == "MEN":
            culture, ethnicity = MEN_CULTURE.get(rname, ("Mentosian", "Pig"))
            religion = "Lotus Faith"
        elif owner == "SKY":
            culture, ethnicity, religion = "Edenite", "Human", "Will of Eden"
        else:
            culture, ethnicity, religion = "", "", ""
        if goods in MINE_GOODS or "mine_site" in ov.get("flags", []):
            flags.append("mine_site")
        provinces.append(dict(
            id=pid, name=names[pid], region=rname, layer="ground", owner=owner,
            terrain=ov.get("terrain", terrain), goods=ov.get("goods", goods), development=dev, flags=flags,
            culture=culture, ethnicity=ethnicity, religion=religion, trade_node=TRADE_NODE[rname], links=[]))
    return provinces


def ground_terrain(ids, provinces, rng):
    relief = smooth_noise((H, W), 5, rng)
    fine = smooth_noise((H, W), 1.5, rng)
    terr = np.zeros((H, W, 3))
    by_id = {p["id"]: p for p in provinces}
    for pid, p in by_id.items():
        m = ids == pid
        terr[m] = TERRAIN_COLOURS.get(p["terrain"], (0.7, 0.7, 0.6))
    land = ids > 0
    rough = np.isin(ids, [p["id"] for p in provinces if p["terrain"] in ("mountains", "hills", "volcanic")])
    shade = 0.86 + 0.16 * relief - 0.18 * rough * fine
    terr *= shade[..., None]
    dist_sea = ndimage.distance_transform_edt(~land)
    depth = np.clip(dist_sea / 160.0, 0, 1)
    sea = np.stack([0.13 + 0.10 * (1 - depth), 0.30 + 0.15 * (1 - depth), 0.52 + 0.12 * (1 - depth)], -1)
    sea += (smooth_noise((H, W), 18, rng)[..., None] - 0.5) * 0.04
    shallow = (~land) & (dist_sea < 7)
    sea[shallow] = sea[shallow] * 0.65 + 0.35 * np.array([0.55, 0.72, 0.80])
    terr[~land] = sea[~land]
    return terr


def build_sky(rng, first_id):
    ids = np.zeros((H, W), np.int32)
    provinces = []
    pid = first_id
    for (name, terrain, goods, dev, flags, cx, cy, r) in SKY_ISLANDS:
        m = blob_mask(cx, cy, r, rng, wobble=0.5) & (ids == 0)
        ids[m] = pid
        owner = SKY_OWNERS.get(name, "SKY")
        cult = owner == "BLM"
        if not cult:
            dev = [dev[0] + 1, dev[1], dev[2] + (1 if dev[2] <= 2 else 0)]
        provinces.append(dict(id=pid, name=name, region="Black Moon Isles" if cult else "Skyfall", layer="sky",
                              owner=owner, terrain=terrain, goods=goods, development=dev,
                              flags=list(flags) + ["coastal"], culture="Moonsworn" if cult else "Edenite",
                              ethnicity="Human" if cult or name not in ("Angelreach", "Seraph Rock", "Halo Isle") else "Angel",
                              religion="Black Moon" if cult else "Will of Eden", trade_node="Skyfall", links=[]))
        pid += 1
    yy = np.mgrid[0:H, 0:W][0] / H
    clouds = smooth_noise((H, W), 20, rng)
    terr = np.stack([0.42 + 0.20 * yy + 0.10 * clouds, 0.55 + 0.15 * yy + 0.10 * clouds,
                     0.78 + 0.08 * yy + 0.08 * clouds], -1)
    relief = smooth_noise((H, W), 5, rng)
    land = ids > 0
    for c in range(3):
        terr[..., c][land] = 0.82 + 0.12 * relief[land]
    under = ndimage.shift(land.astype(float), (14, 0), order=0) > 0
    under &= ~land
    terr[under] = terr[under] * 0.45
    return ids, provinces, terr


STRAITS = [("Curl Isle", "Elderwood")]


def neighbours(ids, provinces, sea_reach):
    """Shared-border neighbours, plus sea/air lanes between shapes within sea_reach pixels."""
    adj = {p["id"]: set() for p in provinces}
    for a, b in ((ids[:, :-1], ids[:, 1:]), (ids[:-1, :], ids[1:, :])):
        m = (a != b) & (a > 0) & (b > 0)
        for x, y in set(zip(a[m].tolist(), b[m].tolist())):
            adj[x].add(y)
            adj[y].add(x)
    lanes = {p["id"]: set() for p in provinces}
    coastal = [p["id"] for p in provinces if "coastal" in p["flags"]]
    dist = {}
    for pid in coastal:
        d = ndimage.distance_transform_edt(ids != pid)
        dist[pid] = {q: float(d[ids == q].min()) for q in coastal if q != pid}
    for pid in coastal:
        near = sorted(dist[pid].items(), key=lambda kv: kv[1])
        for q, dq in near:
            if q not in adj[pid] and dq <= sea_reach:
                lanes[pid].add(q)
                lanes[q].add(pid)
        if len(adj[pid]) == 0 and len(lanes[pid]) < 2:   # every island gets two links
            for q, dq in near[:2]:
                if q not in adj[pid]:
                    lanes[pid].add(q)
                    lanes[q].add(pid)
    return adj, lanes


def connect_components(provinces, adj, lanes, ids):
    """Make sure the layer is one connected graph: link each stray group to its nearest shape."""
    allids = [p["id"] for p in provinces]
    def groups():
        seen, out = set(), []
        for s in allids:
            if s in seen:
                continue
            stack, comp = [s], set()
            while stack:
                x = stack.pop()
                if x in comp:
                    continue
                comp.add(x)
                stack.extend(adj[x] | lanes[x])
            seen |= comp
            out.append(comp)
        return out
    gs = groups()
    while len(gs) > 1:
        gs.sort(key=len)
        small, rest = gs[0], set().union(*gs[1:])
        d = ndimage.distance_transform_edt(~np.isin(ids, list(small)))
        best = min(rest, key=lambda q: d[ids == q].min())
        bd = ndimage.distance_transform_edt(ids != best)
        src = min(small, key=lambda q: bd[ids == q].min())
        lanes[src].add(best)
        lanes[best].add(src)
        gs = groups()


def centre(ids, pid):
    dist = ndimage.distance_transform_edt(np.pad(ids == pid, 1))[1:-1, 1:-1]
    y, x = np.unravel_index(int(np.argmax(dist)), dist.shape)
    return [int(x), int(y)]


def colour_for(rng, used):
    while True:
        c = tuple(int(v) for v in rng.integers(40, 236, 3))
        if c not in used:
            used.add(c)
            return c


def write_layer(layer, ids, provinces, terr, sea_reach, extra=None):
    adj, lanes = neighbours(ids, provinces, sea_reach)
    connect_components(provinces, adj, lanes, ids)
    rng = np.random.default_rng(7 if layer == "ground" else 11)
    used = set()
    bitmap = np.zeros((H, W, 3), np.uint8)
    meta = {}
    for p in provinces:
        col = colour_for(rng, used)
        bitmap[ids == p["id"]] = col
        meta[str(p["id"])] = dict(colour=list(col), centre=centre(ids, p["id"]),
                                  area=int((ids == p["id"]).sum()),
                                  neighbours=sorted(adj[p["id"]]), lanes=sorted(lanes[p["id"]]))
    index = np.zeros((H, W, 3), np.uint8)
    index[..., 0] = ids % 256
    index[..., 1] = ids // 256
    Image.fromarray(bitmap).save(os.path.join(ROOT, "map", f"{layer}_provinces.png"))
    Image.fromarray(index).save(os.path.join(ROOT, "map", f"{layer}_index.png"))
    Image.fromarray((np.clip(terr, 0, 1) * 255).astype(np.uint8)).save(os.path.join(ROOT, "map", f"{layer}_terrain.png"))
    out = dict(width=W, height=H, provinces=meta)
    out.update(extra or {})
    with open(os.path.join(ROOT, "map", f"{layer}_map.json"), "w") as f:
        json.dump(out, f, indent=1)
    return meta


def main():
    os.makedirs(os.path.join(ROOT, "map"), exist_ok=True)
    land, region = load_masks()
    g_ids, shapes = partition(land, region, RNG)
    g_prov = design_ground(g_ids, shapes, RNG)
    g_terr = ground_terrain(g_ids, g_prov, RNG)
    s_ids, s_prov, s_terr = build_sky(RNG, first_id=len(g_prov) + 1)
    seats = {k: [int(v) for v in lore_to_game(*xy)] for k, xy in TRADE_SEATS.items()}
    seats["Skyfall"] = [1000, 500]
    gm = write_layer("ground", g_ids, g_prov, g_terr, sea_reach=55, extra=dict(trade_seats=seats))
    sm = write_layer("sky", s_ids, s_prov, s_terr, sea_reach=150)

    allp = g_prov + s_prov
    # the only ground-sky link in the lore: the Holy Waterfall of Eden
    top = next(p for p in allp if "waterfall_top" in p["flags"])
    base = next(p for p in allp if "waterfall_base" in p["flags"])
    top["links"] = [base["id"]]
    base["links"] = [top["id"]]
    # straits (EU4): armies walk across unless the enemy holds the water
    by_name = {p["name"]: p for p in allp}
    for a, b in STRAITS:
        if a in by_name and b in by_name:
            by_name[a].setdefault("straits", []).append(by_name[b]["id"])
            by_name[b].setdefault("straits", []).append(by_name[a]["id"])

    out = os.path.join(ROOT, "data", "provinces.json")
    if not os.path.exists(out) or "--force-provinces" in sys.argv:
        with open(out, "w") as f:
            f.write('{\n "_note": "Generated by tools/generate_map.py, then safe to hand-edit. id and layer must match '
                    'the map images.",\n "provinces": [\n')
            f.write(",\n".join("  " + json.dumps(p) for p in allp))
            f.write("\n ]\n}\n")
        print("wrote data/provinces.json")
    else:
        print("kept existing data/provinces.json (use --force-provinces to overwrite)")
    counts = {}
    for p in g_prov:
        counts[p["region"]] = counts.get(p["region"], 0) + 1
    print(f"ground: {len(g_prov)} provinces {counts}, sky: {len(s_prov)} provinces")
    owners = {}
    for p in allp:
        owners[p["owner"]] = owners.get(p["owner"], 0) + 1
    print("owners:", owners)
    for p in allp:
        m = (gm if p["layer"] == "ground" else sm)[str(p["id"])]
        if m["area"] < 250:
            print("  warning: small province", p["name"], m["area"])


if __name__ == "__main__":
    main()
