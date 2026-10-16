# make_slime_ase.py - plugins/spriteanim/samples/slime.aseprite from slime.png:
# 8 frames of 32 x 32 (RGBA, zlib cels), tags idle (1-4, looping) and hop (5-8,
# once), a slice "hit1" with a pivot (Aseprite's file format: its spec). CC0.
#   python3 make_slime_ase.py   (needs Pillow)
import os, struct, zlib
from PIL import Image
here = os.path.dirname(os.path.abspath(__file__))
sheet = Image.open(os.path.join(here, "..", "samples", "slime.png")).convert("RGBA")
W = H = 32
frames = [sheet.crop((i % 4 * W, i // 4 * H, i % 4 * W + W, i // 4 * H + H)) for i in range(8)]
def string(s): b = s.encode(); return struct.pack("<H", len(b)) + b
def chunk(t, data): return struct.pack("<IH", len(data) + 6, t) + data
def frame(dur, chunks):
    body = b"".join(chunks)
    return struct.pack("<IHHH2sI", 16 + len(body), 0xF1FA, len(chunks), dur, b"\0\0", len(chunks)) + body
out = []
for i, im in enumerate(frames):
    cs = []
    if i == 0:
        cs.append(chunk(0x2004, struct.pack("<HHHHHHB3s", 1, 0, 0, 0, 0, 0, 255, b"\0\0\0") + string("slime")))
        tags = struct.pack("<H8s", 2, b"\0" * 8)
        tags += struct.pack("<HHBH6s3sB", 0, 3, 0, 0, b"\0" * 6, b"\0\0\0", 0) + string("idle")
        tags += struct.pack("<HHBH6s3sB", 4, 7, 0, 1, b"\0" * 6, b"\0\0\0", 0) + string("hop")
        cs.append(chunk(0x2018, tags))
        cs.append(chunk(0x2022, struct.pack("<III", 1, 2, 0) + string("hit1") + struct.pack("<IiiIIii", 0, 5, 14, 22, 16, 11, 15)))
    px = zlib.compress(im.tobytes())
    cs.append(chunk(0x2005, struct.pack("<HhhBHh5s", 0, 0, 0, 255, 2, 0, b"\0" * 5) + struct.pack("<HH", W, H) + px))
    out.append(frame(160 if i < 4 else 110, cs))
body = b"".join(out)
head = struct.pack("<IHHHHHIHIIB3sHBBhhHH", 128 + len(body), 0xA5E0, 8, W, H, 32, 1, 100, 0, 0, 0, b"\0\0\0", 0, 1, 1, 0, 0, 16, 16)
head += b"\0" * (128 - len(head))
p = os.path.join(here, "..", "samples", "slime.aseprite")
open(p, "wb").write(head + body)
print(p, len(head + body))
