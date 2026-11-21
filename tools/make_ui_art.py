#!/usr/bin/env python3
"""Generates Arcadia's UI graphics into assets/ui/. Re-run after changing colours:
    python3 tools/make_ui_art.py

Art direction: "After the Incendium". Charred slate and ink panels with burnished brass trim and
ember accents, like a war-room table where the old empire's maps are still singed at the edges.
Colours here mirror ui/style/tokens.gd.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "ui")
os.makedirs(OUT, exist_ok=True)
RNG = np.random.default_rng(4289)

INK = (10, 11, 14)
SLATE = (21, 24, 30)
SLATE_HI = (31, 35, 43)
BRASS = (176, 146, 88)
BRASS_DIM = (110, 92, 58)
BRASS_HI = (236, 206, 140)


def grain(w, h, strength=7.0, blur=0.6):
    n = RNG.normal(0.0, 1.0, (h, w))
    im = Image.fromarray(((n * 40) + 128).clip(0, 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(blur))
    a = (np.asarray(im).astype(np.float32) - 128.0) / 40.0
    return a * strength


def tileable_grain(size, strength, blur):
    """Noise that tiles: blur a wrapped 3x3 copy and cut the middle."""
    n = RNG.normal(0.0, 1.0, (size, size))
    big = np.tile(n, (3, 3))
    im = Image.fromarray(((big * 40) + 128).clip(0, 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(blur))
    a = np.asarray(im).astype(np.float32)[size:2 * size, size:2 * size]
    return (a - 128.0) / 40.0 * strength


def vgradient(w, h, top, bottom):
    t = np.linspace(0.0, 1.0, h)[:, None, None]
    return (np.array(top)[None, None, :] * (1 - t) + np.array(bottom)[None, None, :] * t).repeat(w, axis=1)


def to_img(rgb, alpha=None):
    rgb = np.clip(rgb, 0, 255).astype(np.uint8)
    if alpha is None:
        alpha = np.full(rgb.shape[:2], 255, np.uint8)
    return Image.fromarray(np.dstack([rgb, alpha]), "RGBA")


def frame(size, bg_top, bg_bot, border_outer, border_inner, inner_inset, corner, alpha=245, noise=6.0, radius=3):
    """A framed panel tile for nine-patch use."""
    w = h = size
    rgb = vgradient(w, h, bg_top, bg_bot) + tileable_grain(size, noise, 0.7)[:, :, None]
    img = to_img(rgb, np.full((h, w), alpha, np.uint8))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=radius, outline=border_outer + (255,), width=1)
    if border_inner:
        d.rounded_rectangle([inner_inset, inner_inset, w - 1 - inner_inset, h - 1 - inner_inset], radius=max(radius - 1, 0),
                            outline=border_inner + (255,), width=1)
    # cut the rounded corners out of the alpha
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius=radius, fill=255)
    a = np.minimum(np.asarray(img)[:, :, 3], np.asarray(mask))
    img.putalpha(Image.fromarray(a.astype(np.uint8)))
    if corner:
        for cx, cy in [(inner_inset, inner_inset), (w - 1 - inner_inset, inner_inset),
                       (inner_inset, h - 1 - inner_inset), (w - 1 - inner_inset, h - 1 - inner_inset)]:
            r = corner
            d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=BRASS_HI + (255,), outline=BRASS_DIM + (255,))
    return img


def save(img, name):
    p = os.path.join(OUT, name)
    img.save(p)
    print("wrote", os.path.relpath(p, ROOT), img.size)


def panels():
    # main floating panel: 48px, nine-patch margins 12
    save(frame(48, SLATE_HI, SLATE, INK, BRASS_DIM, 3, 2, alpha=246, noise=5.0, radius=4), "panel.png")
    # card inside panels: lighter, no ornaments
    save(frame(24, (34, 38, 46), (28, 31, 38), (52, 50, 44), None, 0, 0, alpha=255, noise=3.5, radius=3), "card.png")
    # tooltip: ink with brass hairline
    save(frame(24, (14, 15, 19), (10, 11, 14), BRASS_DIM, None, 0, 0, alpha=250, noise=3.0, radius=3), "tooltip.png")
    # top bar strip: 8 wide x 44 high, brass rule along the bottom
    w, h = 8, 44
    rgb = vgradient(w, h, (30, 33, 40), (14, 15, 19))
    img = to_img(rgb, np.full((h, w), 248, np.uint8))
    d = ImageDraw.Draw(img)
    d.line([(0, h - 3), (w, h - 3)], fill=BRASS_DIM + (255,))
    d.line([(0, h - 2), (w, h - 2)], fill=BRASS + (255,))
    d.line([(0, h - 1), (w, h - 1)], fill=INK + (255,))
    save(img, "topbar.png")


def buttons():
    states = {
        "normal": ((52, 56, 66), (35, 38, 45), (16, 17, 21), BRASS_DIM, (255, 255, 255, 28)),
        "hover": ((66, 70, 82), (44, 47, 56), (16, 17, 21), BRASS, (255, 255, 255, 40)),
        "pressed": ((40, 36, 28), (62, 54, 38), (16, 17, 21), BRASS_HI, (0, 0, 0, 0)),
        "disabled": ((34, 36, 41), (29, 31, 35), (18, 19, 22), (58, 58, 58), (255, 255, 255, 8)),
        "selected": ((86, 70, 40), (58, 46, 26), (16, 17, 21), BRASS_HI, (255, 240, 200, 50)),
    }
    for name, (top, bot, outer, inner, hl) in states.items():
        s = 24
        rgb = vgradient(s, s, top, bot) + tileable_grain(s, 2.5, 0.6)[:, :, None]
        img = to_img(rgb)
        d = ImageDraw.Draw(img)
        d.rounded_rectangle([0, 0, s - 1, s - 1], radius=4, outline=outer + (255,))
        d.rounded_rectangle([1, 1, s - 2, s - 2], radius=3, outline=inner + (255,))
        mask = Image.new("L", (s, s), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, s - 1, s - 1], radius=4, fill=255)
        img.putalpha(mask)
        if hl[3] > 0:
            over = Image.new("RGBA", (s, s), (0, 0, 0, 0))
            ImageDraw.Draw(over).line([(3, 2), (s - 4, 2)], fill=hl)
            img.alpha_composite(over)
        save(img, f"button_{name}.png")


def divider():
    w, h = 320, 11
    scale = 4
    big = Image.new("RGBA", (w * scale, h * scale), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    cy = h * scale // 2
    # tapering rules either side of a central lozenge
    for side in (-1, 1):
        x0 = w * scale // 2 + side * 12 * scale
        x1 = w * scale // 2 + side * (w * scale // 2)
        steps = 60
        for i in range(steps):
            t0, t1 = i / steps, (i + 1) / steps
            a = int(255 * (1 - t0) ** 1.4)
            d.line([(x0 + (x1 - x0) * t0, cy), (x0 + (x1 - x0) * t1, cy)], fill=BRASS + (a,), width=scale)
    cx = w * scale // 2
    r = 5 * scale
    d.polygon([(cx, cy - r), (cx + r * 1.6, cy), (cx, cy + r), (cx - r * 1.6, cy)], fill=BRASS_HI + (255,))
    r2 = 2 * scale
    d.polygon([(cx, cy - r2), (cx + r2 * 1.6, cy), (cx, cy + r2), (cx - r2 * 1.6, cy)], fill=SLATE + (255,))
    for side in (-1, 1):
        dx = cx + side * 9 * scale
        d.ellipse([dx - 1.6 * scale, cy - 1.6 * scale, dx + 1.6 * scale, cy + 1.6 * scale], fill=BRASS + (255,))
    save(big.resize((w, h), Image.LANCZOS), "divider.png")


def map_paper():
    s = 256
    a = tileable_grain(s, 1.0, 1.4) * 0.6 + tileable_grain(s, 1.0, 6.0) * 0.8
    a = (a - a.min()) / (a.max() - a.min())
    im = Image.fromarray((a * 255).astype(np.uint8), "L")
    save(im.convert("RGBA"), "map_paper.png")


def emblem():
    """The Arcadian sigil: a sun broken by the Black Moon, for the title screen."""
    s, k = 256, 4
    S = s * k
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = S / 2
    rays = 24
    for i in range(rays):
        a0 = 2 * math.pi * i / rays
        long = i % 2 == 0
        r_out = S * (0.48 if long else 0.40)
        r_in = S * 0.30
        w = math.pi / rays * (0.55 if long else 0.45)
        pts = [(c + r_in * math.cos(a0 - w), c + r_in * math.sin(a0 - w)),
               (c + r_out * math.cos(a0), c + r_out * math.sin(a0)),
               (c + r_in * math.cos(a0 + w), c + r_in * math.sin(a0 + w))]
        d.polygon(pts, fill=BRASS + (255,) if long else BRASS_DIM + (255,))
    d.ellipse([c - S * 0.29, c - S * 0.29, c + S * 0.29, c + S * 0.29], fill=BRASS_HI + (255,))
    d.ellipse([c - S * 0.26, c - S * 0.26, c + S * 0.26, c + S * 0.26], fill=(232, 178, 92, 255))
    # the black moon eclipsing it
    mc = (c + S * 0.08, c - S * 0.05)
    d.ellipse([mc[0] - S * 0.22, mc[1] - S * 0.22, mc[0] + S * 0.22, mc[1] + S * 0.22], fill=(18, 12, 26, 255))
    d.ellipse([c - S * 0.29, c - S * 0.29, c + S * 0.29, c + S * 0.29], outline=BRASS_HI + (255,), width=2 * k)
    d.ellipse([c - S * 0.335, c - S * 0.335, c + S * 0.335, c + S * 0.335], outline=BRASS + (255,), width=3 * k)
    save(img.resize((s, s), Image.LANCZOS), "emblem.png")


def vignette():
    s = 256
    y, x = np.mgrid[0:s, 0:s] / (s - 1) * 2 - 1
    r = np.sqrt(x * x * 0.9 + y * y * 1.1)
    a = np.clip((r - 0.55) / 0.75, 0, 1) ** 1.6 * 200
    img = Image.fromarray(np.dstack([np.zeros((s, s, 3), np.uint8), a.astype(np.uint8)]), "RGBA")
    save(img, "vignette.png")


if __name__ == "__main__":
    panels()
    buttons()
    divider()
    map_paper()
    emblem()
    vignette()
