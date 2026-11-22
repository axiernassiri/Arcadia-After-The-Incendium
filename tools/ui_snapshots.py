#!/usr/bin/env python3
"""UI screenshot regression test.

Runs the game once per scenario with the automation flags in scripts/main.gd, saves a screenshot,
shrinks it to half size and compares it with the baseline in tests/ui_snapshots/baseline/. A scenario
fails when more than FAIL_SHARE of its pixels changed noticeably (the water shimmers and a few things
animate, so small differences are allowed). Failures leave the new image and a red-on-grey diff in
tests/ui_snapshots/out/ so you can see what moved.

Usage:
  python tools/ui_snapshots.py             compare every scenario with its baseline
  python tools/ui_snapshots.py --update    accept the current screenshots as the new baselines
  python tools/ui_snapshots.py economy     only the scenarios whose names contain "economy"
Set GODOT to the Godot console executable, or keep it in Downloads or on the Desktop.
Needs: Pillow, numpy. Opens a game window for each scenario (it needs a display, not --headless).
"""
import glob
import os
import subprocess
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = os.path.join(ROOT, "tests", "ui_snapshots", "baseline")
OUT = os.path.join(ROOT, "tests", "ui_snapshots", "out")
PIXEL_TOLERANCE = 40      # 0-255 summed over RGB: smaller changes don't count
FAIL_SHARE = 0.015        # fail when more than 1.5% of pixels changed

SCENARIOS = {
    "main_menu": ["--menu"],
    "nation_select": ["--select-screen"],
    "game_start": ["--nation=MEN"],
    "court": ["--nation=MEN", "--panel=court"],
    "government_estates": ["--nation=MEN", "--panel=government"],
    "economy": ["--nation=MEN", "--panel=economy", "--days=60"],
    "production": ["--nation=MEN", "--panel=production"],
    "diplomacy": ["--nation=MEN", "--panel=diplomacy"],
    "missions": ["--nation=MEN", "--panel=missions"],
    "ledger": ["--nation=MEN", "--panel=ledger"],
    "ages": ["--nation=MEN", "--panel=ages"],
    "province": ["--nation=MEN", "--select=Mentos"],
    "army": ["--nation=MEN", "--army"],
    "war_overview": ["--nation=MEN", "--war=SNT", "--days=120", "--warview"],
    "skyfall": ["--nation=SKY"],
    "world_seam": ["--nation=MEN", "--zoom=0.45", "--focus=Equator Isle"],
    "supply_mode": ["--nation=MEN", "--mode=supply", "--army"],
    "settings": ["--nation=MEN", "--settings"],
}


def find_godot():
    if os.environ.get("GODOT"):
        return os.environ["GODOT"]
    home = os.path.expanduser("~")
    for root in (ROOT, os.path.join(home, "Downloads"), os.path.join(home, "Desktop")):
        hits = glob.glob(os.path.join(root, "**", "Godot*console*.exe"), recursive=True)
        if hits:
            return hits[0]
    sys.exit("Godot not found: set GODOT to the console executable.")


def shoot(godot, name, flags):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".png")
    if os.path.exists(path):
        os.remove(path)
    cmd = [godot, "--path", ROOT, "--"] + flags + ["--screenshot=" + path]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=180)
    if not os.path.exists(path):
        return None
    img = Image.open(path).convert("RGB")
    img = img.resize((img.width // 2, img.height // 2), Image.BILINEAR)
    img.save(path)
    return img


def compare(new, old):
    a = np.asarray(new).astype(int)
    b = np.asarray(old).astype(int)
    if a.shape != b.shape:
        return 1.0, None
    changed = np.abs(a - b).sum(-1) > PIXEL_TOLERANCE
    diff = (np.asarray(new.convert("L")).astype(float) * 0.35).astype(np.uint8)
    diff = np.stack([diff] * 3, -1)
    diff[changed] = [235, 40, 40]
    return float(changed.mean()), Image.fromarray(diff)


def main():
    update = "--update" in sys.argv
    only = [a for a in sys.argv[1:] if not a.startswith("--")]
    godot = find_godot()
    os.makedirs(BASE, exist_ok=True)
    failed = 0
    for name, flags in SCENARIOS.items():
        if only and not any(o in name for o in only):
            continue
        img = shoot(godot, name, flags)
        if img is None:
            print(f"  FAIL  {name}: no screenshot (did the game crash?)")
            failed += 1
            continue
        base_path = os.path.join(BASE, name + ".png")
        if update or not os.path.exists(base_path):
            img.save(base_path)
            print(f"  SAVE  {name} (baseline)")
            continue
        share, diff = compare(img, Image.open(base_path).convert("RGB"))
        if share > FAIL_SHARE:
            failed += 1
            if diff is not None:
                diff.save(os.path.join(OUT, name + "_diff.png"))
            print(f"  FAIL  {name}: {share * 100:.1f}% of pixels changed (see tests/ui_snapshots/out/{name}_diff.png)")
        else:
            print(f"  PASS  {name} ({share * 100:.2f}% changed)")
    print(f"UI SNAPSHOT FAILURES: {failed}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
