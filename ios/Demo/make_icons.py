#!/usr/bin/env python3
"""Draws the 48x48 icons of the demo games and puts them into the jars (and the .jad files).

    python3 Demo/make_icons.py

For each jar: icon.png is added at the root, and `MIDlet-1: <name>, /icon.png, <class>` in the
manifest and the .jad points to it. Re-running replaces the icon. Needs Pillow.
"""
import math, os, re, sys, zipfile
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
S = 48


def gradient(top, bottom):
    im = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(im)
    for y in range(S):
        t = y / (S - 1)
        d.line([(0, y), (S, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return im


def star(d, cx, cy, R, r, fill):
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        rad = R if i % 2 == 0 else r
        pts.append((cx + rad * math.cos(a), cy + rad * math.sin(a)))
    d.polygon(pts, fill=fill)


def sparkles(d, spots, color=(255, 255, 255)):
    for x, y in spots:
        d.point((x, y), fill=color)


def star_catcher():
    im = gradient((27, 31, 94), (74, 42, 140))
    d = ImageDraw.Draw(im)
    sparkles(d, [(6, 7), (40, 9), (12, 22), (38, 24), (5, 30), (43, 33), (20, 5)])
    star(d, 24, 19, 17, 7.5, (255, 149, 0))
    star(d, 24, 19, 14.5, 6, (255, 214, 10))
    d.rectangle([22, 17, 25, 20], fill=(255, 245, 157))
    d.polygon([(9, 33), (39, 33), (35, 44), (13, 44)], fill=(196, 122, 44))
    d.rectangle([8, 31, 40, 34], fill=(240, 170, 80))
    d.line([(15, 37), (33, 37)], fill=(150, 90, 30))
    d.point((14, 8), fill=(255, 214, 10))
    return im


def void_wave():
    im = Image.new("RGB", (S, S), (2, 5, 26))
    d = ImageDraw.Draw(im)
    sparkles(d, [(5, 6), (41, 5), (9, 20), (37, 16), (44, 29), (4, 35), (31, 8), (16, 12)], (150, 160, 255))
    # an enemy
    d.polygon([(24, 12), (33, 7), (35, 14), (24, 19), (13, 14), (15, 7)], fill=(255, 59, 122))
    d.rectangle([19, 10, 21, 12], fill=(255, 255, 255))
    d.rectangle([27, 10, 29, 12], fill=(255, 255, 255))
    # the shots
    d.rectangle([23, 21, 24, 29], fill=(255, 255, 255))
    d.rectangle([22, 21, 25, 22], fill=(56, 225, 255))
    # the ship
    d.polygon([(24, 29), (31, 43), (24, 40), (17, 43)], fill=(56, 225, 255))
    d.polygon([(24, 33), (27, 40), (24, 38), (21, 40)], fill=(2, 5, 26))
    d.polygon([(14, 44), (20, 38), (20, 43)], fill=(0, 140, 200))
    d.polygon([(34, 44), (28, 38), (28, 43)], fill=(0, 140, 200))
    d.rectangle([23, 44, 24, 46], fill=(255, 214, 10))
    return im


def rainbow_hop():
    im = gradient((79, 179, 246), (198, 241, 255))
    d = ImageDraw.Draw(im)
    d.ellipse([34, 4, 44, 14], fill=(255, 242, 168))
    d.ellipse([36, 6, 42, 12], fill=(255, 224, 102))
    d.ellipse([3, 8, 14, 13], fill=(255, 255, 255))
    d.ellipse([8, 5, 18, 12], fill=(255, 255, 255))
    colors = [(255, 59, 48), (255, 149, 0), (255, 214, 10), (52, 199, 89), (50, 173, 230), (175, 82, 222)]
    cx, cy = 24, 36
    for i, c in enumerate(colors):
        r = 22 - 3 * i
        d.pieslice([cx - r, cy - r, cx + r, cy + r], 180, 360, fill=c)
    r = 4
    d.pieslice([cx - r, cy - r, cx + r, cy + r], 180, 360, fill=(160, 215, 250))
    # the island
    d.polygon([(11, 40), (37, 40), (24, 47)], fill=(107, 68, 35))
    d.rectangle([10, 36, 38, 40], fill=(154, 106, 58))
    d.rectangle([10, 34, 38, 37], fill=(76, 217, 100))
    # the hopper
    d.ellipse([18, 21, 30, 33], fill=(255, 123, 172))
    d.rectangle([20, 25, 22, 28], fill=(255, 255, 255))
    d.rectangle([26, 25, 28, 28], fill=(255, 255, 255))
    d.point((21, 27), fill=(32, 32, 64))
    d.point((27, 27), fill=(32, 32, 64))
    d.rectangle([22, 30, 26, 30], fill=(194, 24, 91))
    d.rectangle([23, 17, 25, 21], fill=(255, 214, 10))
    return im


def gem_swap():
    im = gradient((43, 16, 85), (217, 63, 135))
    d = ImageDraw.Draw(im)
    # a 2x2 board
    d.rectangle([3, 3, 44, 44], fill=(32, 16, 58))
    for gx in range(2):
        for gy in range(2):
            d.rectangle([4 + gx * 21, 4 + gy * 21, 24 + gx * 21 - 1, 24 + gy * 21 - 1],
                        fill=(58, 34, 104) if (gx + gy) % 2 == 0 else (46, 26, 84))
    d.ellipse([7, 7, 20, 20], fill=(255, 59, 48))                                   # red circle
    star(d, 34, 15, 9, 4, (255, 214, 10))                                           # yellow star
    d.rectangle([8, 29, 19, 40], fill=(52, 199, 89))                                # green square
    d.polygon([(34, 28), (42, 41), (26, 41)], fill=(50, 173, 230))                  # blue triangle
    for x, y in [(9, 9), (30, 10), (10, 31), (32, 31)]:
        d.rectangle([x, y, x + 1, y + 1], fill=(255, 255, 255))
    d.rectangle([24, 3, 44, 24], outline=(255, 255, 255))                           # the cursor
    return im


ICONS = {"StarCatcher": star_catcher, "VoidWave": void_wave, "RainbowHop": rainbow_hop, "GemSwap": gem_swap}


def put_icon(name, icon):
    jar = os.path.join(HERE, name + ".jar")
    jad = os.path.join(HERE, name + ".jad")
    png = os.path.join(HERE, "icons", name + ".png")
    os.makedirs(os.path.dirname(png), exist_ok=True)
    icon.save(png)
    data = open(png, "rb").read()
    src = zipfile.ZipFile(jar)
    items = [(i, src.read(i.filename)) for i in src.infolist() if i.filename != "icon.png"]
    src.close()
    out = zipfile.ZipFile(jar, "w", zipfile.ZIP_DEFLATED)
    for info, body in items:
        if info.filename == "META-INF/MANIFEST.MF":
            body = re.sub(rb"(?m)^(MIDlet-1:\s*[^,\r\n]*),[^,\r\n]*,", rb"\1, /icon.png,", body)
        out.writestr(info.filename, body)
    out.writestr("icon.png", data)
    out.close()
    text = open(jad).read()
    text = re.sub(r"(?m)^(MIDlet-1:\s*[^,\r\n]*),[^,\r\n]*,", r"\1, /icon.png,", text)
    text = re.sub(r"(?m)^MIDlet-Jar-Size:.*$", "MIDlet-Jar-Size: %d" % os.path.getsize(jar), text)
    open(jad, "w").write(text)
    print(name, os.path.getsize(jar), "bytes")


if __name__ == "__main__":
    for n, f in ICONS.items():
        put_icon(n, f())
