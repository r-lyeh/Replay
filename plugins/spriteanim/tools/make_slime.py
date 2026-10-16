# make_slime.py - plugins/spriteanim/samples/slime.png: a slime, 32 x 32 frames
# (4 x 2: idle 1-4, hop 5-8), drawn by code (CC0, as the tilemap's tiles).
#   python3 make_slime.py   (needs Pillow)
import math, os
from PIL import Image, ImageDraw
W = H = 32
img = Image.new("RGBA", (W * 4, H * 2), (0, 0, 0, 0))
def slime(d, ox, oy, squash, lift):
    w = 22 * (1 + squash * 0.25); h = 16 * (1 - squash * 0.25)
    cx, base = ox + W / 2, oy + H - 3 - lift
    d.ellipse([cx - w / 2 - 1, base - h - 1, cx + w / 2 + 1, base + 1], fill=(30, 70, 40, 255))
    d.ellipse([cx - w / 2, base - h, cx + w / 2, base], fill=(90, 200, 110, 255))
    d.ellipse([cx - w / 4, base - h + 3, cx - w / 4 + 5, base - h + 6], fill=(200, 255, 210, 255))
    for ex in (-4, 3):
        d.rectangle([cx + ex, base - h / 2 - 2, cx + ex + 1, base - h / 2 + 1], fill=(20, 40, 25, 255))
    if lift < 1: d.ellipse([cx - w / 2, oy + H - 3, cx + w / 2, oy + H - 1], fill=(0, 0, 0, 60))
d = ImageDraw.Draw(img)
for i in range(4): slime(d, i * W, 0, math.sin(i / 4 * math.tau) * 0.3, 0)
for i, (sq, lift) in enumerate([(0.5, 0), (-0.3, 6), (-0.2, 10), (0.3, 2)]): slime(d, i * W, H, sq, lift)
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "samples", "slime.png")
img.save(out)
print(out)
