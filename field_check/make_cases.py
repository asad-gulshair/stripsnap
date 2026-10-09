"""Makes 'real phone photo' versions of the synthetic fixtures for a field check.
Output: field_check/images/*.jpg + field_check/cases.json"""
import json, random, math, os
from PIL import Image, ImageFilter, ImageEnhance, ImageDraw

random.seed(7)
ROOT = os.path.dirname(os.path.abspath(__file__))
FX = os.path.join(ROOT, '..', 'test', 'fixtures')
OUT = os.path.join(ROOT, 'images'); os.makedirs(OUT, exist_ok=True)
fx = json.load(open(os.path.join(FX, 'fixtures.json')))
pools = [f for f in fx if f['profile'] == 'generic_pool_6'][:3]
spas = [f for f in fx if f['profile'] == 'generic_spa_4'][:2]
cases = []

def tint(im, r, g, b):
    ch = im.split()
    return Image.merge('RGB', [c.point(lambda v, k=k: min(255, int(v * k))) for c, k in zip(ch, (r, g, b))])

def noise(im, amt):
    px = im.load(); w, h = im.size
    for y in range(0, h):
        for x in range(0, w):
            if random.random() < 0.5:
                p = px[x, y]; n = random.randint(-amt, amt)
                px[x, y] = tuple(max(0, min(255, c + n)) for c in p)
    return im

def clamp_box(b, w, h):
    x, y, bw, bh = b
    bw = min(bw, w); bh = min(bh, h)
    x = max(0, min(x, w - bw)); y = max(0, min(y, h - bh))
    return [x, y, bw, bh]

def add(name, f, im, cond, expect, profile=None, sbox=None, cbox=None, truth=True):
    fn = f"{name}_{f['file']}"
    im.convert('RGB').save(os.path.join(OUT, fn), quality=88)
    w, h = im.size
    cases.append(dict(file=fn, condition=cond, expect=expect, profile=profile or f['profile'],
                      strip_box=clamp_box(sbox or f['strip_box'], w, h),
                      chart_box=clamp_box(cbox or f['chart_box'], w, h),
                      true_pos=f['true_pos'] if truth else None))

for f in pools + spas:
    base = Image.open(os.path.join(FX, f['file'])).convert('RGB')
    w, h = base.size
    sx, sy, sw, sh = f['strip_box']
    add('00clean', f, base.copy(), 'Clean photo (baseline)', 'read')
    add('01warm', f, tint(base, 1.12, 0.97, 0.72), 'Warm indoor light (yellow bulb)', 'read')
    g = base.copy(); ov = Image.new('RGBA', base.size, (0, 0, 0, 0)); d = ImageDraw.Draw(ov)
    cx = sx + sw * 0.35; cy = sy + sh / 2
    for r in range(int(sw * 0.22), 0, -6):
        d.ellipse([cx - r, cy - r * 0.6, cx + r, cy + r * 0.6], fill=(255, 255, 255, int(90 * (1 - r / (sw * 0.22))) + 8))
    g = Image.alpha_composite(ImageEnhance.Brightness(g).enhance(1.25).convert('RGBA'), ov)
    add('02glare', f, g, 'Bright sun + glare spot on strip', 'warn_or_read')
    s = base.copy(); m = Image.new('L', base.size, 255); d = ImageDraw.Draw(m)
    d.polygon([(sx + sw * 0.5, 0), (w, 0), (w, h), (sx + sw * 0.2, h)], fill=110)
    s = Image.composite(s, Image.new('RGB', base.size, (0, 0, 0)), m.filter(ImageFilter.GaussianBlur(25)))
    add('03shadow', f, s, 'Hard shadow across half the strip and chart', 'warn_or_read')
    add('04blur', f, base.filter(ImageFilter.GaussianBlur(3.5)), 'Slightly blurry (hand shake)', 'read')
    add('05rot', f, base.rotate(6, resample=Image.BICUBIC, fillcolor=(120, 80, 60)), 'Phone tilted ~6 degrees', 'warn_or_read')
    add('06misalign', f, base.copy(), 'Frames placed badly (strip frame half off the strip)', 'warn',
        sbox=[sx, sy + sh * 0.7, sw, sh])
    cut = base.crop((0, 0, int(sx + sw * 0.6), h))
    add('07cutoff', f, cut, 'Strip partly outside the photo', 'warn')
    dk = noise(ImageEnhance.Brightness(base).enhance(0.3), 12)
    add('08dark', f, dk, 'Dark photo (evening, no flash) + sensor noise', 'warn_or_read')
    jp = base.copy(); jp.save(os.path.join(OUT, '_tmp.jpg'), quality=18)
    add('09lowq', f, Image.open(os.path.join(OUT, '_tmp.jpg')).copy(), 'Heavy JPEG compression (WhatsApp-style)', 'read')
    # random non-strip photo with the same frame positions
    rnd = Image.new('RGB', base.size, (random.randint(0, 255),) * 3); d = ImageDraw.Draw(rnd)
    for _ in range(60):
        x0, y0 = random.randint(0, w), random.randint(0, h)
        d.ellipse([x0, y0, x0 + random.randint(40, 400), y0 + random.randint(40, 300)],
                  fill=tuple(random.randint(0, 255) for _ in range(3)))
    add('10random', f, rnd.filter(ImageFilter.GaussianBlur(6)), 'Not a strip at all (random photo)', 'refuse', truth=False)
    wrong = 'generic_spa_4' if f['profile'] == 'generic_pool_6' else 'generic_pool_6'
    add('11wrongtype', f, base.copy(), f'Wrong strip type picked (read as {wrong})', 'warn', profile=wrong, truth=False)

os.remove(os.path.join(OUT, '_tmp.jpg'))
json.dump(cases, open(os.path.join(ROOT, 'cases.json'), 'w'), indent=1)
print(len(cases), 'cases')
