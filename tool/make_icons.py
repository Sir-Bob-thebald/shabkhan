"""Builds the app icons from the logo artwork.

    py tool/make_icons.py path/to/logo_source.png

The source is the rounded-square logo on black (1254 px). Its faint border
is masked off and the inside is cropped square; that becomes assets/logo.png
(used in the app) and every launcher icon (Android legacy and adaptive, iOS,
web, Windows).
"""
import json
import os
import sys

from PIL import Image, ImageDraw

BG = (6, 6, 6)  # the logo's own background, also the adaptive icon background

src = Image.open(sys.argv[1]).convert('RGB')
# The rounded square in the source, measured: edges and corner radius.
x0, y0, x1, y1, r = 106, 124, 1148, 1138, 232
inset = 18
mask = Image.new('L', src.size, 0)
ImageDraw.Draw(mask).rounded_rectangle((x0 + inset, y0 + inset, x1 - inset, y1 - inset), radius=r - inset, fill=255)
clean = Image.new('RGB', src.size, BG)
clean.paste(src, (0, 0), mask)
side = min(x1 - x0, y1 - y0) - 2 * inset
cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
sq = clean.crop((cx - side // 2, cy - side // 2, cx + side // 2, cy + side // 2)).resize((1024, 1024), Image.LANCZOS)
os.makedirs('assets', exist_ok=True)
sq.save('assets/logo.png')


def rounded(img, size, radius_frac=0.22):
    im = img.resize((size, size), Image.LANCZOS).convert('RGBA')
    m = Image.new('L', (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size - 1, size - 1), radius=int(size * radius_frac), fill=255)
    im.putalpha(m)
    return im


res = 'android/app/src/main/res'
for d, k in {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}.items():
    os.makedirs(f'{res}/mipmap-{d}', exist_ok=True)
    rounded(sq, int(48 * k)).save(f'{res}/mipmap-{d}/ic_launcher.png')
    # Adaptive foreground: a 108 dp canvas with the art in the middle 76 dp.
    c, a = int(108 * k), int(76 * k)
    fg = Image.new('RGBA', (c, c), BG + (255,))
    fg.paste(sq.resize((a, a), Image.LANCZOS), ((c - a) // 2, (c - a) // 2))
    fg.save(f'{res}/mipmap-{d}/ic_launcher_foreground.png')
os.makedirs(f'{res}/mipmap-anydpi-v26', exist_ok=True)
with open(f'{res}/mipmap-anydpi-v26/ic_launcher.xml', 'w') as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@color/ic_launcher_background"/>\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            '</adaptive-icon>\n')
with open(f'{res}/values/colors.xml', 'w') as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
            '    <color name="ic_launcher_background">#060606</color>\n</resources>\n')

ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
if os.path.isdir(ios):
    for im in json.load(open(f'{ios}/Contents.json'))['images']:
        if 'filename' in im:
            px = round(float(im['size'].split('x')[0]) * float(im['scale'].rstrip('x')))
            sq.resize((px, px), Image.LANCZOS).save(f"{ios}/{im['filename']}")
if os.path.isdir('web/icons'):
    for n, s in [('Icon-192.png', 192), ('Icon-512.png', 512), ('Icon-maskable-192.png', 192), ('Icon-maskable-512.png', 512)]:
        sq.resize((s, s), Image.LANCZOS).save(f'web/icons/{n}')
    sq.resize((32, 32), Image.LANCZOS).save('web/favicon.png')
if os.path.isdir('windows/runner/resources'):
    rounded(sq, 256).save('windows/runner/resources/app_icon.ico',
                          sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print('icons written')
