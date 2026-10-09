"""Draws the StripSnap icon + Play feature graphic. Run: python tool/make_icons.py"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
REQ = r'D:\REQUIREMNT'
TEAL_TOP, TEAL_BOT = (8, 145, 178), (14, 116, 144)
PADS = [(245, 180, 0), (236, 72, 153), (34, 197, 94), (249, 115, 22)]

def gradient(w, h, top, bot):
    g = Image.new('RGB', (w, h), top); d = ImageDraw.Draw(g)
    for y in range(h):
        t = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
    return g

def drop(d, cx, cy, r, fill):
    # teardrop: circle + triangle on top
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)
    d.polygon([(cx - r * 0.86, cy - r * 0.5), (cx + r * 0.86, cy - r * 0.5), (cx, cy - r * 2.05)], fill=fill)

def symbol(size, transparent=False, scale=1.0):
    """Drop + test strip, drawn on a size x size canvas (centre area if scale<1)."""
    S = size * 4
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0)) if transparent else gradient(S, S, TEAL_TOP, TEAL_BOT).convert('RGBA')
    d = ImageDraw.Draw(im)
    k = S * scale; o = (S - k) / 2
    # strip (white, rounded) on the right
    sx0, sy0, sx1, sy1 = o + k * 0.56, o + k * 0.14, o + k * 0.76, o + k * 0.86
    d.rounded_rectangle([sx0, sy0, sx1, sy1], radius=k * 0.05, fill=(255, 255, 255, 255))
    ph = (sy1 - sy0) * 0.13
    for i, c in enumerate(PADS):
        y = sy0 + (sy1 - sy0) * 0.08 + i * ph * 1.45
        d.rounded_rectangle([sx0 + k * 0.03, y, sx1 - k * 0.03, y + ph], radius=k * 0.015, fill=c + (255,))
    # water drop on the left
    drop(d, o + k * 0.33, o + k * 0.60, k * 0.17, (255, 255, 255, 255))
    d.ellipse([o + k * 0.25, o + k * 0.56, o + k * 0.30, o + k * 0.66], fill=(186, 230, 253, 255))
    return im.resize((size, size), Image.LANCZOS)

def save_png(im, path, rgb=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    (im.convert('RGB') if rgb else im).save(path)

res = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
for name, px in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
    save_png(symbol(px), os.path.join(res, f'mipmap-{name}', 'ic_launcher.png'))
    # adaptive icon foreground: 108dp canvas, art inside the 66dp safe zone
    save_png(symbol(int(px * 108 / 48), transparent=True, scale=0.62), os.path.join(res, f'mipmap-{name}', 'ic_launcher_foreground.png'))
os.makedirs(os.path.join(res, 'mipmap-anydpi-v26'), exist_ok=True)
open(os.path.join(res, 'mipmap-anydpi-v26', 'ic_launcher.xml'), 'w').write(
    '<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <background android:drawable="@color/ic_launcher_background"/>\n'
    '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n</adaptive-icon>\n')
open(os.path.join(res, 'values', 'ic_launcher_background.xml'), 'w').write(
    '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#0891B2</color>\n</resources>\n')

# web icons too (the web build is used for screenshots)
web = os.path.join(ROOT, 'web')
for f, px in [('favicon.png', 32), ('icons/Icon-192.png', 192), ('icons/Icon-512.png', 512),
              ('icons/Icon-maskable-192.png', 192), ('icons/Icon-maskable-512.png', 512)]:
    save_png(symbol(px), os.path.join(web, f))

# Play Store: 512x512 32-bit PNG icon
icon512 = symbol(512)
save_png(icon512, os.path.join(REQ, '01_icon_512x512.png'))

# Play Store: 1024x500 feature graphic, no alpha
fg = gradient(1024, 500, TEAL_TOP, TEAL_BOT)
ic = symbol(300).convert('RGBA')
mask = Image.new('L', (300, 300), 0); ImageDraw.Draw(mask).rounded_rectangle([0, 0, 299, 299], radius=60, fill=255)
shadow = Image.new('RGBA', (340, 340), (0, 0, 0, 0)); ImageDraw.Draw(shadow).rounded_rectangle([20, 26, 320, 326], radius=60, fill=(0, 0, 0, 90))
fg.paste(shadow.filter(ImageFilter.GaussianBlur(10)), (50, 80), shadow.filter(ImageFilter.GaussianBlur(10)))
fg.paste(ic, (70, 100), mask)
fd = r'C:\Windows\Fonts'
bold = ImageFont.truetype(os.path.join(fd, 'segoeuib.ttf'), 92)
reg = ImageFont.truetype(os.path.join(fd, 'segoeui.ttf'), 38)
d = ImageDraw.Draw(fg)
d.text((420, 120), 'StripSnap', font=bold, fill='white')
d.text((424, 245), 'Read any pool or hot tub', font=reg, fill=(224, 247, 250))
d.text((424, 292), 'test strip from one photo', font=reg, fill=(224, 247, 250))
d.text((424, 370), 'Any brand  ·  On your phone  ·  No account', font=ImageFont.truetype(os.path.join(fd, 'segoeui.ttf'), 26), fill=(186, 230, 253))
save_png(fg, os.path.join(REQ, '02_feature_graphic_1024x500.png'), rgb=True)
print('ok')
