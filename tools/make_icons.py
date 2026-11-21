#!/usr/bin/env python3
"""Arcadia icon set: one silhouette style on a 24x24 grid, white so the game can tint it.

Writes ui/style/icons.gd (the SVG sources the game rasterises at whatever size it needs) and,
with --preview, a contact sheet PNG. Edit the shapes here and re-run:
    python3 tools/make_icons.py [--preview sheet.png]
"""
import math
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W = "#ffffff"
DIM = 'fill-opacity="0.55"'


def poly(points):
    return "M" + " L".join(f"{x:.2f} {y:.2f}" for x, y in points) + "Z"


def star_points(cx, cy, r_out, r_in, n=5, rot=-90):
    pts = []
    for i in range(n * 2):
        a = math.radians(rot + i * 180 / n)
        r = r_out if i % 2 == 0 else r_in
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def circle_path(cx, cy, r):
    return f"M{cx - r} {cy} a{r} {r} 0 1 0 {2 * r} 0 a{r} {r} 0 1 0 {-2 * r} 0Z"


def gear(cx=12, cy=12, r_out=10.5, r_in=8.0, teeth=8, hole=3.4):
    pts = []
    for i in range(teeth):
        a0 = 2 * math.pi * i / teeth
        w = math.pi / teeth
        for a, r in [(a0 - w * 0.55, r_in), (a0 - w * 0.35, r_out), (a0 + w * 0.35, r_out), (a0 + w * 0.55, r_in)]:
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return f'<path fill-rule="evenodd" d="{poly(pts)} {circle_path(cx, cy, hole)}"/>'


def seal():
    pts = []
    for i in range(24):
        a = 2 * math.pi * i / 24
        r = 10.5 if i % 2 == 0 else 9.3
        pts.append((12 + r * math.cos(a), 12 + r * math.sin(a)))
    inner = star_points(12, 12.4, 5.2, 2.3)
    return (f'<path fill-rule="evenodd" d="{poly(pts)} {circle_path(12, 12, 7)}"/>'
            f'<path d="{poly(inner)}"/>')


SWORD = ('<path d="M12 0.6 L13.9 3.6 L13.9 15 L10.1 15 L10.1 3.6Z"/>'
         '<rect x="7" y="15" width="10" height="2.3" rx="0.7"/>'
         '<rect x="10.9" y="17.3" width="2.2" height="3.6"/>'
         '<circle cx="12" cy="22" r="1.7"/>')

ICONS = {
    # resources
    "sanctum": f'<path fill-rule="evenodd" d="{circle_path(12, 12, 10.5)} {circle_path(12, 12, 8)}"/>'
               '<path d="M12 6.2 L16.4 12 L12 17.8 L7.6 12Z"/>'
               f'<path {DIM} d="M12 8.8 L14.4 12 L12 15.2 L9.6 12Z"/>',
    "coins": '<ellipse cx="9" cy="18" rx="7" ry="2.6"/><rect x="2" y="15.4" width="14" height="2.6"/>'
             '<ellipse cx="9" cy="14.2" rx="7" ry="2.6"/><rect x="2" y="11.6" width="14" height="2.6"/>'
             f'<ellipse cx="9" cy="10.4" rx="7" ry="2.6"/>'
             f'<path fill-rule="evenodd" d="{circle_path(16.5, 8, 6)} {circle_path(16.5, 8, 4.2)}"/>'
             f'<circle cx="16.5" cy="8" r="2.4" {DIM}/>',
    "manpower": f'<circle cx="15.5" cy="7.5" r="3.2" {DIM}/><path {DIM} d="M10 20 C10 15 12.5 12.6 15.5 12.6 C18.5 12.6 21.5 15 21.5 20Z"/>'
                '<circle cx="9" cy="8" r="3.8"/><path d="M2 21 C2 15.6 5 13 9 13 C13 13 16 15.6 16 21Z"/>',
    "person": '<circle cx="12" cy="7.5" r="4.2"/><path d="M3.5 21.5 C3.5 15.5 7.2 13 12 13 C16.8 13 20.5 15.5 20.5 21.5Z"/>',
    "stability": '<rect x="11.1" y="3" width="1.8" height="16"/><rect x="3" y="5.2" width="18" height="1.8" rx="0.9"/>'
                 '<circle cx="12" cy="3.4" r="1.7"/><rect x="7" y="19.2" width="10" height="2.3" rx="0.8"/>'
                 '<path d="M5.3 7 L2 13.5 H3.4 L5.3 9.6 L7.2 13.5 H8.6Z"/><path d="M1.6 13.8 H9 C9 16 7.3 17.4 5.3 17.4 C3.3 17.4 1.6 16 1.6 13.8Z"/>'
                 '<path d="M18.7 7 L15.4 13.5 H16.8 L18.7 9.6 L20.6 13.5 H22Z"/><path d="M15 13.8 H22.4 C22.4 16 20.7 17.4 18.7 17.4 C16.7 17.4 15 16 15 13.8Z"/>',
    "crown": '<path d="M2.5 17 L3.2 6.8 L8.3 11.2 L12 4.6 L15.7 11.2 L20.8 6.8 L21.5 17Z"/>'
             '<rect x="2.5" y="18.3" width="19" height="2.7" rx="0.6"/>'
             '<circle cx="3.2" cy="6" r="1.5"/><circle cx="12" cy="3.6" r="1.6"/><circle cx="20.8" cy="6" r="1.5"/>'
             f'<path {DIM} d="M10.6 13.4 L12 11 L13.4 13.4 L12 15.8Z"/>',
    "legitimacy": f'<path fill-rule="evenodd" d="{circle_path(12, 15, 7.5)} M4.9 13.8 H19.1 V15.6 H4.9Z"/>'
                  '<rect x="11.1" y="1.6" width="1.8" height="6.4"/><rect x="9" y="3.5" width="6" height="1.8"/>',
    "swords": f'<g transform="rotate(-42 12 12)">{SWORD}</g><g transform="rotate(42 12 12)">{SWORD}</g>',
    "sword": SWORD,
    "ship": '<path d="M1.8 15.4 H22.2 L19 20.6 H5Z"/><rect x="11.2" y="2" width="1.6" height="13"/>'
            '<path d="M13.4 3 L20.5 13.6 H13.4Z"/><path d="M10.6 5 L4.6 13.6 H10.6Z" fill-opacity="0.8"/>'
            '<path d="M12.8 2 L16.5 3.3 L12.8 4.6Z"/>',
    "hourglass": '<rect x="4.5" y="2" width="15" height="2.4" rx="0.8"/><rect x="4.5" y="19.6" width="15" height="2.4" rx="0.8"/>'
                 '<path fill-rule="evenodd" d="M6 4.4 H18 C18 8.6 13.6 10.6 13.6 12 C13.6 13.4 18 15.4 18 19.6 H6 C6 15.4 10.4 13.4 10.4 12 C10.4 10.6 6 8.6 6 4.4Z '
                 'M8 6 H16 C15.6 8 12.8 9.6 12.4 11 H11.6 C11.2 9.6 8.4 8 8 6Z M8.2 18 H15.8 C15.2 16.4 13.4 15.4 12 14.6 C10.6 15.4 8.8 16.4 8.2 18Z"/>'
                 f'<path {DIM} d="M9 7 H15 C14 8.6 12.6 9.6 12 10.4 C11.4 9.6 10 8.6 9 7Z M8.6 17.6 H15.4 C14.4 16.4 13 15.6 12 15.2 C11 15.6 9.6 16.4 8.6 17.6Z"/>',
    "shield_broken": '<path fill-rule="evenodd" d="M12 1.8 L20.5 5 V11.5 C20.5 16.6 16.8 20.4 12 22.2 C7.2 20.4 3.5 16.6 3.5 11.5 V5Z '
                     'M12.6 3.4 L10.4 8.4 L13.4 10.6 L10.2 15.2 L12.4 20.4 L13.4 20 L11.6 15.2 L14.8 10.4 L11.8 8.2 L13.8 3.8Z"/>',
    "scroll": f'<path fill-rule="evenodd" d="M6 4.5 H18 V19.5 H6Z M8.5 7.5 H15.5 V8.7 H8.5Z M8.5 10.5 H15.5 V11.7 H8.5Z M8.5 13.5 H13.5 V14.7 H8.5Z"/>'
              f'<rect x="3.5" y="2.5" width="17" height="3" rx="1.5"/><rect x="3.5" y="18.5" width="17" height="3" rx="1.5"/>',
    "quill": '<path d="M21 2.5 C13.4 3.2 8.2 8.6 6.6 15.6 L5.2 21 L6.7 21.4 L8.2 17.2 C10.6 16.6 12.8 15.4 14.2 13.4 L11.6 13.2 L15.4 11.6 C18.2 9.2 20.2 6.2 21 2.5Z"/>'
             f'<path {DIM} d="M3 21 H12 V22.4 H3Z"/>',
    "helmet": '<path fill-rule="evenodd" d="M4.6 13.6 C4.6 7.4 7.8 3.4 12 3.4 C16.2 3.4 19.4 7.4 19.4 13.6 V21 H15.2 V15.2 L13.6 13.6 V21.4 H10.4 V13.6 L8.8 15.2 V21 H4.6Z '
              'M6.8 10.4 H10.6 V12 H6.8Z M13.4 10.4 H17.2 V12 H13.4Z"/>'
              f'<path {DIM} d="M10.6 3.6 C11 2 13 2 13.4 3.6 L12 4.4Z"/>',
    "gear": gear(),
    "book": '<path d="M1.8 5 C5 3.6 8.6 3.8 11.2 5.8 V20.6 C8.6 18.8 5 18.6 1.8 19.8Z"/>'
            '<path d="M22.2 5 C19 3.6 15.4 3.8 12.8 5.8 V20.6 C15.4 18.8 19 18.6 22.2 19.8Z" fill-opacity="0.8"/>',
    "column": '<path d="M2 8.2 L12 2.2 L22 8.2Z"/><rect x="2.5" y="9" width="19" height="1.8"/>'
              '<rect x="4.2" y="11.6" width="2.6" height="7"/><rect x="9" y="11.6" width="2.6" height="7"/>'
              '<rect x="12.4" y="11.6" width="2.6" height="7"/><rect x="17.2" y="11.6" width="2.6" height="7"/>'
              '<rect x="2.5" y="19.4" width="19" height="2.4"/>',
    "hammer": '<g transform="rotate(-40 12 12)"><rect x="5.5" y="2.6" width="13" height="6.4" rx="1"/>'
              '<rect x="10.7" y="9" width="2.6" height="13.4" rx="1"/></g>',
    "trade": '<path d="M3 8.2 H16.6 V4.6 L22 9.4 L16.6 14.2 V10.6 H3Z"/>'
             '<path d="M21 15.8 H7.4 V12.4 L2 17.2 L7.4 22 V18.2 H21Z" fill-opacity="0.75"/>',
    "envelope": '<path fill-rule="evenodd" d="M2 5 H22 V19 H2Z M3.6 6.4 L12 12.8 L20.4 6.4Z"/>'
                f'<circle cx="12" cy="14" r="3.2" {DIM}/>',
    "flag": '<rect x="3.4" y="2" width="1.8" height="20" rx="0.6"/>'
            '<path d="M5.2 3.2 C9 1.4 12 5 16 3.6 C18 2.9 19.6 2.6 21 3 V13 C19.6 12.6 18 12.9 16 13.6 C12 15 9 11.4 5.2 13.2Z"/>',
    "help": f'<path fill-rule="evenodd" d="{circle_path(12, 12, 10.5)} '
            'M8.9 9.6 C8.9 7.4 10.3 6.2 12.1 6.2 C14 6.2 15.4 7.4 15.4 9.2 C15.4 11.6 13 11.9 13 13.8 V14.6 H11.2 V13.6 C11.2 10.9 13.5 10.6 13.5 9.2 C13.5 8.4 12.9 7.9 12.1 7.9 C11.2 7.9 10.7 8.5 10.7 9.6Z '
            f'{circle_path(12.1, 17.3, 1.2)}"/>',
    "flame": '<path d="M12 1.6 C13 5.6 18.8 8.4 18.8 14.4 C18.8 18.6 15.8 22 12 22 C8.2 22 5.2 18.6 5.2 14.6 C5.2 11.4 7 9.4 8.4 7.8 C8.4 10.4 9.4 11.8 10.6 12.4 C10 8.4 11.4 4.6 12 1.6Z"/>'
             f'<path {DIM} d="M12 12.6 C13.4 14.6 15.2 15.6 15.2 18 C15.2 19.8 13.8 21 12 21 C10.2 21 8.8 19.8 8.8 18.2 C8.8 16.2 10.8 15 12 12.6Z"/>',
    "fort": '<path fill-rule="evenodd" d="M4 22 V8 H6.6 V5 H8.8 V8 H10.9 V5 H13.1 V8 H15.2 V5 H17.4 V8 H20 V22Z M10 22 V17.4 C10 16.2 10.9 15.4 12 15.4 C13.1 15.4 14 16.2 14 17.4 V22Z '
            'M11.2 10.4 H12.8 V13 H11.2Z"/>'
            f'<path {DIM} d="M2.6 3.4 H6 V5 H2.6Z"/>',
    "star": f'<path d="{poly(star_points(12, 12.6, 10.6, 4.4))}"/>',
    "horseshoe": '<path fill-rule="evenodd" d="M4.6 3 H9.4 V12.4 C9.4 14 10.6 15.2 12 15.2 C13.4 15.2 14.6 14 14.6 12.4 V3 H19.4 V12.4 C19.4 17 16.2 20.6 12 20.6 C7.8 20.6 4.6 17 4.6 12.4Z '
                 'M6.2 6 H7.8 V7.6 H6.2Z M16.2 6 H17.8 V7.6 H16.2Z M6.4 11 H8 V12.6 H6.4Z M16 11 H17.6 V12.6 H16Z"/>'
                 '<rect x="3.6" y="2" width="6.8" height="2" rx="0.6"/><rect x="13.6" y="2" width="6.8" height="2" rx="0.6"/>',
    "cannon": '<g transform="rotate(-22 12 12)"><path d="M2 9.4 H17.6 L20.6 8.4 V14.6 L17.6 13.6 H2 C1.2 13.6 1 12.8 1 11.5 C1 10.2 1.2 9.4 2 9.4Z"/></g>'
              f'<path fill-rule="evenodd" d="{circle_path(8.6, 16.6, 5)} {circle_path(8.6, 16.6, 1.6)}"/>',
    "moon": f'<path fill-rule="evenodd" d="{circle_path(12, 12, 10)} {circle_path(16.4, 9.2, 8.4)}"/>'
            f'<circle cx="18" cy="17.6" r="1.3" {DIM}/><circle cx="20.6" cy="13.4" r="0.9" {DIM}/>',
    "seal": seal(),
    "warning": '<path fill-rule="evenodd" d="M12 2 L22.6 21 H1.4Z M10.9 8.4 H13.1 L12.7 15 H11.3Z M10.8 17.6 H13.2 V19.6 H10.8Z"/>',
    "pickaxe": '<path d="M2.6 9.6 C6 4.4 12.6 2 21.4 3.4 C14.6 4.4 9.6 6.4 5.2 10.4Z"/>'
               '<path d="M14.4 2.6 C18.2 6 20.4 11.2 20.4 16.6 C19 12.4 16.4 8.8 13 6Z"/>'
               '<path d="M12.6 5.4 L15 7.6 L4.6 21.6 C4 22.4 2.8 22.4 2.4 21.6 C2 21 2.1 20.4 2.6 19.8Z"/>',
    "close": '<g transform="rotate(45 12 12)"><rect x="10.7" y="3" width="2.6" height="18" rx="1"/><rect x="3" y="10.7" width="18" height="2.6" rx="1"/></g>',
    "play": '<path d="M7 4.2 L20 12 L7 19.8Z"/>',
    "pause": '<rect x="6" y="4.5" width="4.2" height="15" rx="1"/><rect x="13.8" y="4.5" width="4.2" height="15" rx="1"/>',
    "plus": '<rect x="10.6" y="4" width="2.8" height="16" rx="1"/><rect x="4" y="10.6" width="16" height="2.8" rx="1"/>',
    "minus": '<rect x="4" y="10.6" width="16" height="2.8" rx="1"/>',
    "menu": '<rect x="3.5" y="5" width="17" height="2.4" rx="1"/><rect x="3.5" y="10.8" width="17" height="2.4" rx="1"/><rect x="3.5" y="16.6" width="17" height="2.4" rx="1"/>',
    "house": '<path fill-rule="evenodd" d="M12 2.6 L22 11 H19.4 V21.4 H4.6 V11 H2Z M10 21.4 V15.4 H14 V21.4Z"/>',
    "map": '<path d="M2 5.4 L8 3 L16 5.6 L22 3.4 V18.8 L16 21 L8 18.4 L2 20.6Z" fill-opacity="0.55"/>'
           '<path d="M8 3 L16 5.6 V21 L8 18.4Z"/>',
    "eye": f'<path fill-rule="evenodd" d="M1.4 12 C4 7.2 7.8 5 12 5 C16.2 5 20 7.2 22.6 12 C20 16.8 16.2 19 12 19 C7.8 19 4 16.8 1.4 12Z {circle_path(12, 12, 4.4)}"/>'
           '<circle cx="12" cy="12" r="2.2"/>',
    "anchor": f'<path fill-rule="evenodd" d="{circle_path(12, 4.6, 2.6)} {circle_path(12, 4.6, 1.2)}"/>'
              '<rect x="11.1" y="7" width="1.8" height="14"/><rect x="7.6" y="9" width="8.8" height="1.8" rx="0.8"/>'
              '<path d="M3 13 L5.6 12 C5.6 16.4 8.4 19.4 12 19.8 C15.6 19.4 18.4 16.4 18.4 12 L21 13 C20.6 18.2 16.8 22 12 22 C7.2 22 3.4 18.2 3 13Z"/>',
    "wing": '<path d="M2 18 C5 9 12 4 22 3 C19.6 5 18 6.8 17 8.8 C15.2 8.6 13.6 9 12.4 9.8 C14 10 15.2 10.4 16 11.2 C14 11.4 12.2 12 10.8 13 C12.2 13.2 13.4 13.8 14 14.6 C10.4 14.2 6.4 15.6 2 18Z"/>',
    "waterfall": '<path d="M3 2 H21 V5.6 H3Z" fill-opacity="0.55"/><rect x="5" y="5.6" width="2.8" height="12" rx="1.2"/>'
                 '<rect x="10.6" y="5.6" width="2.8" height="15" rx="1.2"/><rect x="16.2" y="5.6" width="2.8" height="11" rx="1.2"/>'
                 '<path d="M2 20 C5 18.6 7 21.6 12 20.4 C17 21.6 19 18.6 22 20 V22.4 H2Z" fill-opacity="0.75"/>',
    "portal": f'<path fill-rule="evenodd" d="{circle_path(12, 12, 10.4)} {circle_path(12, 12, 7.4)}"/>'
              f'<path fill-rule="evenodd" d="{circle_path(12, 12, 5.6)} {circle_path(14.2, 10.6, 4.6)}" fill-opacity="0.8"/>',
    "mountain": '<path d="M1.6 20.4 L8.6 7.4 L12 13 L15.2 8.6 L22.4 20.4Z"/>'
                f'<path d="M8.6 7.4 L10.6 11 L9.4 10.2 L8.2 11.6 L7.2 10Z M15.2 8.6 L17 11.6 L15.8 11 L14.6 12Z" fill="#000" fill-opacity="0.35"/>',
    "sun": f'<path d="{poly(star_points(12, 12, 11, 6.6, 12, -90))}" fill-opacity="0.6"/><circle cx="12" cy="12" r="5.6"/>',
    "battle": f'<g transform="rotate(-42 12 12)">{SWORD}</g><g transform="rotate(42 12 12)">{SWORD}</g>'
              f'<path d="{poly(star_points(12, 12, 4.6, 2.2, 8, -90))}" fill-opacity="0.6"/>',
}


def svg(body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="{W}">'
            f'{body}</svg>')


def write_gd():
    out = os.path.join(ROOT, "ui", "style", "icons.gd")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    lines = [
        "extends RefCounted",
        "## The Arcadia icon set. GENERATED by tools/make_icons.py: edit the shapes there, not here.",
        "## Icons are white SVG silhouettes on a 24 px grid, rasterised on demand at the size asked for",
        "## (twice over, with mipmaps) so they stay sharp at any UI scale. Tint them with modulate.",
        "## Usage: const Icons = preload(\"res://ui/style/icons.gd\")   Icons.tex(\"sanctum\", 18)",
        "",
        "const SVG := {",
    ]
    for k, v in ICONS.items():
        lines.append(f'\t"{k}": \'{svg(v)}\',')
    lines += [
        "}",
        "",
        "static var _cache := {}",
        "",
        "",
        "static func tex(name: String, px: int = 20) -> Texture2D:",
        "\tvar key = \"%s@%d\" % [name, px]",
        "\tif _cache.has(key):",
        "\t\treturn _cache[key]",
        "\tvar src: String = SVG.get(name, SVG[\"help\"])",
        "\tvar img = Image.new()",
        "\timg.load_svg_from_string(src, px * 2.0 / 24.0)",
        "\timg.generate_mipmaps()",
        "\tvar t = ImageTexture.create_from_image(img)",
        "\t_cache[key] = t",
        "\treturn t",
        "",
        "",
        "static func rect(name: String, px: int = 20, tint: Color = Color.WHITE) -> TextureRect:",
        "\t## A TextureRect showing the icon at px x px, tinted.",
        "\tvar r = TextureRect.new()",
        "\tr.texture = tex(name, px)",
        "\tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE",
        "\tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED",
        "\tr.custom_minimum_size = Vector2(px, px)",
        "\tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS",
        "\tr.modulate = tint",
        "\tr.mouse_filter = Control.MOUSE_FILTER_IGNORE",
        "\tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER",
        "\treturn r",
        "",
    ]
    open(out, "w").write("\n".join(lines))
    print("wrote", out, len(ICONS), "icons")


def preview(path):
    import tempfile
    from PIL import Image
    cell, cols = 64, 10
    names = list(ICONS)
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell, rows * cell), (40, 44, 52, 255))
    with tempfile.TemporaryDirectory() as td:
        for i, k in enumerate(names):
            f = os.path.join(td, k + ".svg")
            open(f, "w").write(svg(ICONS[k]))
            p = os.path.join(td, k + ".png")
            subprocess.run(["rsvg-convert", "-w", "48", "-h", "48", f, "-o", p], check=True)
            im = Image.open(p)
            sheet.alpha_composite(im, ((i % cols) * cell + 8, (i // cols) * cell + 8))
    sheet.save(path)
    print("preview", path, names)


if __name__ == "__main__":
    write_gd()
    if "--preview" in sys.argv:
        preview(sys.argv[sys.argv.index("--preview") + 1])
