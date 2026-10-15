"""Generates Evict's icon sources (SVG). Concept D, "Free Slot":
one tile lifts away from the grid, leaving room to breathe.

  python3 design/icon/generate.py   ->  icon.svg, icon-small.svg, menubar.svg
"""
import math, os

HERE = os.path.dirname(os.path.abspath(__file__))

def squircle(cx=512, cy=512, r=412, n=5.0, steps=360):
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        pts.append(f"{cx + r * math.copysign(abs(c) ** (2 / n), c):.2f},"
                   f"{cy + r * math.copysign(abs(s) ** (2 / n), s):.2f}")
    return "M" + " L".join(pts) + " Z"

SQ = squircle()

COMMON_DEFS = f'''
<clipPath id="sq"><path d="{SQ}"/></clipPath>
<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#E2E6F2"/></linearGradient>
<linearGradient id="t1" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#7180FF"/><stop offset="1" stop-color="#4A55EA"/></linearGradient>
<linearGradient id="t2" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4B56DC"/><stop offset="1" stop-color="#2D35A8"/></linearGradient>
<linearGradient id="t3" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#9AA6FF"/><stop offset="1" stop-color="#6E7AF5"/></linearGradient>
<linearGradient id="lift" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#EEF0FF"/></linearGradient>
<linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF" stop-opacity="0.22"/><stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0"/></linearGradient>
<filter id="iconShadow" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="10" stdDeviation="14" flood-color="#000" flood-opacity="0.26"/></filter>
<filter id="tileShadow" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="6" stdDeviation="8" flood-color="#2A2F7A" flood-opacity="0.18"/></filter>
<filter id="liftShadow" x="-40%" y="-40%" width="180%" height="180%"><feDropShadow dx="-12" dy="24" stdDeviation="22" flood-color="#2A2F7A" flood-opacity="0.30"/></filter>
'''

def icon(small=False):
    t, g, rx = (236, 36, 62) if small else (216, 40, 56)   # tile, gap, corner
    x0 = 512 - (2 * t + g) / 2 - (8 if small else 14)
    y0 = 512 - (2 * t + g) / 2 + (8 if small else 14)
    tiles = [(x0, y0, "t1"), (x0, y0 + t + g, "t2"), (x0 + t + g, y0 + t + g, "t3")]
    tile_svg = "".join(
        f'<rect x="{x}" y="{y}" width="{t}" height="{t}" rx="{rx}" fill="url(#{f})"/>'
        f'<rect x="{x}" y="{y}" width="{t}" height="{t}" rx="{rx}" fill="url(#gloss)"/>'
        for x, y, f in tiles)

    sx, sy = x0 + t + g, y0          # the empty slot
    if small:
        slot = (f'<rect x="{sx + 10}" y="{sy + 10}" width="{t - 20}" height="{t - 20}" rx="{rx - 8}" '
                f'fill="none" stroke="#A3ABCF" stroke-width="20"/>')
        lift_fill, lift_stroke, dx, rot = "#D9DDFF", "#B5BCF0", 70, 10
    else:
        slot = (f'<rect x="{sx + 8}" y="{sy + 8}" width="{t - 16}" height="{t - 16}" rx="{rx - 6}" '
                f'fill="none" stroke="#8E97C0" stroke-width="12" stroke-dasharray="34 24" stroke-linecap="round"/>')
        lift_fill, lift_stroke, dx, rot = "url(#lift)", "#D6DBF5", 82, 12

    cx, cy = sx + t / 2, sy + t / 2
    lifted = (f'<g transform="translate({dx} {-dx}) rotate({rot} {cx} {cy})" filter="url(#liftShadow)">'
              f'<rect x="{sx}" y="{sy}" width="{t}" height="{t}" rx="{rx}" fill="{lift_fill}" stroke="{lift_stroke}" stroke-width="{4 if small else 2}"/>'
              f'</g>')

    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>{COMMON_DEFS}</defs>
<path d="{SQ}" fill="url(#bg)" filter="url(#iconShadow)"/>
<g clip-path="url(#sq)">
<g filter="url(#tileShadow)">{tile_svg}</g>
{slot}
{lifted}
</g>
<path d="{SQ}" fill="none" stroke="#000" stroke-opacity="0.06" stroke-width="2"/>
</svg>
'''

MENUBAR = '''<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18">
<rect x="1.5" y="1.5" width="6.6" height="6.6" rx="1.8" fill="#000"/>
<rect x="1.5" y="9.9" width="6.6" height="6.6" rx="1.8" fill="#000"/>
<rect x="9.9" y="9.9" width="6.6" height="6.6" rx="1.8" fill="#000"/>
<rect x="10.55" y="2.15" width="5.3" height="5.3" rx="1.3" fill="none" stroke="#000" stroke-width="1.3" stroke-dasharray="1.8 1.3"/>
</svg>
'''

for name, svg in [("icon.svg", icon()), ("icon-small.svg", icon(small=True)), ("menubar.svg", MENUBAR)]:
    with open(os.path.join(HERE, name), "w") as f:
        f.write(svg)
print("ok")
