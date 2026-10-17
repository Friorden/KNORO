#!/usr/bin/env python3
"""Cuts Robert Pinero's "Free Sprites" battlers into KNORO strips.
Credit required: "Robert Pinero" (see assets/LICENSES.md). No redistribution of the raw pack.

Usage (from game/): python3 tools/pinero_prepare.py "<Free Sprites dir>"

The sheets use the RPG Maker MV side-view battler layout: a 9 x 6 grid of
cells = 18 motions of 3 frames, facing left. Motion (column group, row):
  wait (0,1) · swing (1,1) · damage (0,4) · dead (2,5)
Each motion becomes a 3-frame strip, scaled down (smooth, it's painted art).
"""
import os
import sys
from PIL import Image

SRC = sys.argv[1]
OUT = "assets/tinyswords/units"
MOTIONS = {"idle": (0, 1), "attack": (1, 1), "hurt": (0, 4), "dead": (2, 5)}
SHEETS = {"wolf": ("wolf_0001_brown.png", 0.62), "alpha": ("Werewolf_0004_brown.png", 0.62), "rat": ("Rat_0004_dark.png", 0.9)}

for key, (fname, scale) in SHEETS.items():
    im = Image.open(os.path.join(SRC, fname)).convert("RGBA")
    cw, ch = im.width / 9.0, im.height / 6.0
    for motion, (grp, row) in MOTIONS.items():
        frames = []
        for f in range(3):
            x0, y0 = int(round((grp * 3 + f) * cw)), int(round(row * ch))
            frames.append(im.crop((x0, y0, int(round(x0 + cw)), int(round(y0 + ch)))))
        w, h = int(cw * scale), int(ch * scale)
        for size_name, k in (("", 1.0), ("_map", 0.55)):
            fw, fh = int(w * k), int(h * k)
            strip = Image.new("RGBA", (fw * 3, fh))
            for i, fr in enumerate(frames):
                strip.paste(fr.resize((fw, fh), Image.LANCZOS), (i * fw, 0))
            strip.save(os.path.join(OUT, f"pinero_{key}_{motion}{size_name}.png"))
print("ok")
