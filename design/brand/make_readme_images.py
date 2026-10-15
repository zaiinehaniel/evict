"""Builds the README hero / GitHub social preview and the screenshots strip.

Inputs: docs/images/popover-{light,dark}.png (rendered by the Debug app with
`--render-screenshots`) and the app icon from the asset catalog.

  python3 design/brand/make_readme_images.py
"""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
IMAGES = os.path.join(ROOT, "docs", "images")
ICON = os.path.join(ROOT, "Evict", "Assets.xcassets", "AppIcon.appiconset", "icon_512x512@2x.png")
GLYPH = os.path.join(ROOT, "design", "icon", "preview", "menubar-36.png")

INK, MUTED, SOFT = (29, 29, 31), (88, 92, 112), (136, 141, 165)

def sf(size, weight=400, optical=None):
    font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size)
    font.set_variation_by_axes([100, optical or min(max(size, 17), 96), 400, weight])
    return font

def vertical_gradient(size, top, bottom):
    w, h = size
    grad = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(h - 1, 1)
        grad.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return grad.resize((w, h))

def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.size[0] - 1, img.size[1] - 1], radius=radius, fill=255)
    out = img.convert("RGBA"); out.putalpha(mask); return out

def drop_shadow(canvas, box, radius, blur, offset, opacity):
    x0, y0, x1, y1 = box
    pad = blur * 3
    layer = Image.new("RGBA", (x1 - x0 + pad * 2, y1 - y0 + pad * 2), (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle([pad, pad, pad + x1 - x0, pad + y1 - y0], radius=radius, fill=(20, 24, 70, int(255 * opacity)))
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(layer, (x0 - pad + offset[0], y0 - pad + offset[1]))

def popover(name, height):
    shot = Image.open(os.path.join(IMAGES, name)).convert("RGBA")
    scale = height / shot.height
    shot = shot.resize((round(shot.width * scale), height), Image.LANCZOS)
    return rounded(shot, round(22 * scale))

# ---------- Hero / social preview: 1280 x 640 ----------
W, H = 1280, 640
hero = vertical_gradient((W, H), (247, 248, 255), (226, 230, 246)).convert("RGBA")
d = ImageDraw.Draw(hero)

# A quiet menu bar with Evict's glyph "pressed", the popover hanging below it.
bar_h = 34
glyph_cx = 960
overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
o = ImageDraw.Draw(overlay)
o.rectangle([0, 0, W, bar_h], fill=(255, 255, 255, 150))
o.line([0, bar_h, W, bar_h], fill=(205, 209, 228, 255), width=1)
o.rounded_rectangle([glyph_cx - 19, 5, glyph_cx + 19, bar_h - 5], radius=6, fill=(0, 0, 0, 26))
hero.alpha_composite(overlay)
glyph = Image.open(GLYPH).convert("RGBA").resize((22, 22), Image.LANCZOS)
hero.alpha_composite(glyph, (glyph_cx - 11, (bar_h - 22) // 2))
d.text((W - 32, bar_h // 2), "Wed 9:41", font=sf(16, 500), fill=INK, anchor="rm")

pop = popover("popover-light.png", 568)
px, py = glyph_cx - pop.width // 2, bar_h + 14
drop_shadow(hero, (px, py, px + pop.width, py + pop.height), 12, 22, (0, 16), 0.22)
hero.alpha_composite(pop, (px, py))

icon = Image.open(ICON).convert("RGBA").resize((176, 176), Image.LANCZOS)
hero.alpha_composite(icon, (78, 120))
d.text((96, 318), "Evict", font=sf(92, 700), fill=INK)
d.text((98, 432), "Evict the apps that overstayed.", font=sf(34, 500), fill=MUTED)
d.text((98, 486), "A calm menu bar utility for macOS · Free & open source", font=sf(21, 400), fill=SOFT)
hero.convert("RGB").save(os.path.join(IMAGES, "hero.png"), optimize=True)

# ---------- Screenshots: light + dark side by side ----------
light, dark = popover("popover-light.png", 760), popover("popover-dark.png", 760)
gap, margin = 56, 64
strip = vertical_gradient((light.width * 2 + gap + margin * 2, light.height + margin * 2), (247, 248, 255), (226, 230, 246)).convert("RGBA")
for i, shot in enumerate([light, dark]):
    x, y = margin + i * (shot.width + gap), margin
    drop_shadow(strip, (x, y, x + shot.width, y + shot.height), 14, 20, (0, 14), 0.20)
    strip.alpha_composite(shot, (x, y))
strip.convert("RGB").save(os.path.join(IMAGES, "screenshots.png"), optimize=True)
# ---------- Settings: General tab, light ----------
shot = Image.open(os.path.join(IMAGES, "settings-general-light.png")).convert("RGBA")
shot = rounded(shot, 36)  # 2x render; shown at half size in the README
pad = 112
frame = vertical_gradient((shot.width + pad * 2, shot.height + pad * 2), (247, 248, 255), (226, 230, 246)).convert("RGBA")
drop_shadow(frame, (pad, pad, pad + shot.width, pad + shot.height), 36, 40, (0, 28), 0.22)
frame.alpha_composite(shot, (pad, pad))
frame.convert("RGB").save(os.path.join(IMAGES, "settings.png"), optimize=True)
print("hero", hero.size, "screenshots", strip.size, "settings", frame.size)
