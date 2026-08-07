"""Turn a generated sprite pack into shippable Xcode imagesets.

Generalised from the Anime Ink pipeline so every remaining pack runs through
the same code. Usage:  python pack_pipeline.py <prefix>
reading <prefix>_urls.json (index -> image URL).

Background removal is a flood fill inwards from the edges rather than a global
white threshold. That distinction matters: several sprites have large white
highlights *inside* them (a corona's hot core, ice crystal facets), and a
threshold would punch holes straight through the artwork.
"""
import json
import os
import sys
import urllib.request
from collections import deque

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
# Resolve the asset catalogue relative to this file so the script works
# from any checkout rather than one hard-coded machine.
ASSETS = os.path.join(os.path.dirname(HERE), "Sources", "Assets.xcassets")
SIZE = 256

# index -> (asset key, tier). 4 base chains x 8 tiers, then 4 hybrids x tiers 3-7.
LAYOUT = {}
for i, key in enumerate(["fire", "ice", "void", "radiant"]):
    for tier in range(8):
        LAYOUT[i * 8 + tier] = (key, tier)
for i, key in enumerate(["tempest", "infernal", "aurora", "eclipse"]):
    for offset, tier in enumerate(range(3, 8)):
        LAYOUT[32 + i * 5 + offset] = (key, tier)


def remove_white_background(im, tolerance=26):
    """Flood fill from the border, clearing only white connected to an edge."""
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()

    def is_bg(x, y):
        r, g, b, a = px[x, y]
        return a > 0 and r >= 255 - tolerance and g >= 255 - tolerance and b >= 255 - tolerance

    seen = bytearray(w * h)
    queue = deque()
    for x in range(w):
        for y in (0, h - 1):
            if is_bg(x, y):
                queue.append((x, y))
                seen[y * w + x] = 1
    for y in range(h):
        for x in (0, w - 1):
            if is_bg(x, y):
                queue.append((x, y))
                seen[y * w + x] = 1

    while queue:
        x, y = queue.popleft()
        px[x, y] = (255, 255, 255, 0)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and is_bg(nx, ny):
                seen[ny * w + nx] = 1
                queue.append((nx, ny))
    return im


def trim_and_fit(im, size=SIZE, margin=8):
    """Crop to the artwork, then centre it in a square canvas."""
    box = im.getbbox()
    if box:
        im = im.crop(box)
    side = max(im.size) + margin * 2
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(im, ((side - im.width) // 2, (side - im.height) // 2), im)
    return canvas.resize((size, size), Image.LANCZOS)


def write_imageset(name, image):
    folder = os.path.join(ASSETS, f"{name}.imageset")
    os.makedirs(folder, exist_ok=True)
    image.save(os.path.join(folder, f"{name}.png"), "PNG", optimize=True)
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump({
            "images": [
                {"filename": f"{name}.png", "idiom": "universal", "scale": "1x"},
                {"idiom": "universal", "scale": "2x"},
                {"idiom": "universal", "scale": "3x"},
            ],
            "info": {"author": "xcode", "version": 1},
        }, f, indent=2)


def process(prefix, raw_dir, index, url):
    key, tier = LAYOUT[index]
    name = f"{prefix}_{key}_t{tier}"

    raw_path = os.path.join(raw_dir, f"{index:02d}.png")
    if not os.path.exists(raw_path):
        urllib.request.urlretrieve(url, raw_path)

    with Image.open(raw_path) as im:
        cut = remove_white_background(im)
        opaque = sum(1 for p in cut.getdata() if p[3] > 8)
        ratio = opaque / (cut.width * cut.height)
        write_imageset(name, trim_and_fit(cut))
    return name, ratio


def main(prefix):
    raw_dir = os.path.join(HERE, f"{prefix}_raw")
    os.makedirs(raw_dir, exist_ok=True)
    with open(os.path.join(HERE, f"{prefix}_urls.json")) as f:
        urls = json.load(f)

    missing = sorted(set(range(52)) - {int(k) for k in urls})
    if missing:
        print(f"ABORT: missing indices {missing}")
        return 1

    suspicious = []
    for index in sorted(int(k) for k in urls):
        name, ratio = process(prefix, raw_dir, index, urls[str(index)])
        # Nearly all opaque means the cut failed; nearly empty means it ate
        # the artwork. Either way a human should look before it ships.
        if ratio > 0.92 or ratio < 0.04:
            suspicious.append((name, round(ratio, 3)))

    print(f"wrote 52 imagesets for '{prefix}'")
    if suspicious:
        print("SUSPICIOUS (check these):", suspicious)
    else:
        print("all sprites cut cleanly")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
