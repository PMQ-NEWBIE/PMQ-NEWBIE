"""Vẽ icon app Cân Lỏ: mặt cân trắng có đồng hồ kim trên nền xanh."""
import os, sys
from PIL import Image, ImageDraw

GREEN = (15, 122, 90, 255)
DARK = (10, 84, 62, 255)
WHITE = (255, 255, 255, 255)
out = sys.argv[1]
SS = 4  # vẽ to rồi thu nhỏ cho mượt

def glyph(d, cx, cy, w):
    """Mặt cân rộng w, tâm (cx, cy)."""
    h = w * 0.92
    x0, y0 = cx - w / 2, cy - h / 2
    d.rounded_rectangle([x0, y0, x0 + w, y0 + h], radius=w * 0.2, fill=WHITE)
    # đồng hồ nửa vòng
    r = w * 0.30
    gx, gy = cx, y0 + h * 0.46
    d.pieslice([gx - r, gy - r, gx + r, gy + r], 180, 360, fill=GREEN)
    r2 = r * 0.62
    d.pieslice([gx - r2, gy - r2, gx + r2, gy + r2], 180, 360, fill=WHITE)
    # kim
    import math
    ang = math.radians(-55)
    nx, ny = gx + math.cos(ang) * r * 0.95, gy + math.sin(ang) * r * 0.95
    d.line([gx, gy, nx, ny], fill=DARK, width=max(2, int(w * 0.05)))
    d.ellipse([gx - w * 0.045, gy - w * 0.045, gx + w * 0.045, gy + w * 0.045], fill=DARK)
    # chân cân
    fw = w * 0.16
    for fx in (x0 + w * 0.2, x0 + w * 0.8 - fw):
        d.rounded_rectangle([fx, y0 + h * 0.78, fx + fw, y0 + h * 0.86], radius=w * 0.03, fill=GREEN)

def legacy(px):
    S = px * SS
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, S - 1, S - 1], radius=S * 0.22, fill=GREEN)
    glyph(d, S / 2, S / 2 + S * 0.02, S * 0.6)
    return im.resize((px, px), Image.LANCZOS)

def foreground(px):
    # 108dp, vùng an toàn 66dp ở giữa
    S = px * SS
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    glyph(d, S / 2, S / 2 + S * 0.01, S * 0.56)
    return im.resize((px, px), Image.LANCZOS)

dens = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
for name, k in dens.items():
    dd = os.path.join(out, f'mipmap-{name}')
    os.makedirs(dd, exist_ok=True)
    legacy(int(48 * k)).save(os.path.join(dd, 'ic_launcher.png'))
    foreground(int(108 * k)).save(os.path.join(dd, 'ic_launcher_foreground.png'))

os.makedirs(os.path.join(out, 'mipmap-anydpi-v26'), exist_ok=True)
open(os.path.join(out, 'mipmap-anydpi-v26', 'ic_launcher.xml'), 'w').write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/can_lo_icon_bg" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
''')
os.makedirs(os.path.join(out, 'values'), exist_ok=True)
open(os.path.join(out, 'values', 'can_lo_colors.xml'), 'w').write('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="can_lo_icon_bg">#0F7A5A</color>
</resources>
''')
os.makedirs(os.path.join(out, 'drawable'), exist_ok=True)
# Icon thông báo: phải là hình đơn sắc trắng, nếu không Android vẽ thành ô vuông trắng.
open(os.path.join(out, 'drawable', 'ic_stat_scale.xml'), 'w').write('''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp"
    android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFFFF"
        android:pathData="M6,3h12a3,3 0,0 1,3 3v12a3,3 0,0 1,-3 3H6a3,3 0,0 1,-3 -3V6a3,3 0,0 1,3 -3zM12,7a5,5 0,0 0,-5 5h2.2a2.8,2.8 0,0 1,4.3 -2.4l1.6,-1.6A5,5 0,0 0,12 7zM14.5,10.2 12.6,12.1a0.9,0.9 0,1 0,1.3 1.3l1.9,-1.9a5,5 0,0 0,-1.3 -1.3z" />
</vector>
''')
print('ok')
