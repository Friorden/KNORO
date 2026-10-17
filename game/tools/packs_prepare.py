#!/usr/bin/env python3
"""Imports the third-party packs KNORO uses beside Tiny Swords (licences: assets/LICENSES.md).

Usage (from game/):
    python3 tools/packs_prepare.py <packs dir>
where <packs dir> holds the unzipped packs:
    "Free Sprites/"                (Robert Pinero, credit required)
    "Kings and Pigs/"              (Pixel Frog, CC0)
    "Pirate Bomb/"                 (Pixel Frog, CC0)
    "Treasure Hunters/"            (Pixel Frog, CC0)
    "RPG_ARSENAL_V1.1/"            (LimeZu, credit required)
    "goblin/Icons 1.2/"            (Goblin's Archive "Goblin's Arsenal", credit required)
    "free-crystal-cave-pixel-art-backgrounds/" (CraftPix freebie licence)
    "parallax_forest_pack web/"    (ansimuz, CC BY 4.0, credit)
    "Super Mountain Dusk Files/"   (ansimuz, CC0)

Nothing here is drawn: files are copied, cropped, scaled, flattened or packed
into animation strips. Outputs:
    assets/bg/*.png       full-screen backdrops (layers flattened)
    assets/icons/*.png    one icon per item id (+ resource icons)
    assets/units/*.png    monster / NPC animation strips (frames side by side)
    assets/props/*.png    chests, barrels, boxes, coins
"""
import glob
import json
import os
import sys

from PIL import Image

SRC = sys.argv[1]
OUT = "assets"
for d in ("bg", "icons", "units", "props"):
    os.makedirs(os.path.join(OUT, d), exist_ok=True)


def P(*parts):
    return os.path.join(SRC, *parts)


def save(im, *parts):
    im.save(os.path.join(OUT, *parts))


def find(pattern):
    hits = sorted(h for h in glob.glob(P(pattern), recursive=True) if "__MACOSX" not in h)
    assert hits, pattern
    return hits[0]


# ------------------------------------------------------------------ backdrops
def flatten(layers, size=None):
    base = None
    for f in layers:
        im = Image.open(f).convert("RGBA")
        if base is None:
            base = Image.new("RGBA", size or im.size)
        if im.size != base.size:
            # tile narrow parallax layers across the width, bottom aligned
            row = Image.new("RGBA", base.size)
            for x in range(0, base.width, im.width):
                row.alpha_composite(im, (x, base.height - im.height))
            im = row
        base.alpha_composite(im)
    return base


cave = find("free-crystal-cave-pixel-art-backgrounds/PNG")
for i in range(1, 5):
    save(Image.open(os.path.join(cave, f"background {i}", f"background {i}.png")).convert("RGBA"), "bg", f"cave{i}.png")
fl = find("parallax_forest_pack web/**/v1/layers")
layers = sorted(glob.glob(os.path.join(fl, "*.png")))
order = ["back", "middle", "front", "lights"]
layers.sort(key=lambda f: next((i for i, k in enumerate(order) if k in os.path.basename(f)), 9))
save(flatten(layers), "bg", "forest1.png")
fl2 = find("parallax_forest_pack web/**/v2/layers")
layers2 = sorted(glob.glob(os.path.join(fl2, "*.png")))
layers2.sort(key=lambda f: next((i for i, k in enumerate(order) if k in os.path.basename(f)), 9))
save(flatten(layers2), "bg", "forest2.png")
md = find("Super Mountain Dusk Files/**/Assets")
save(flatten([os.path.join(md, "version A/Layers", n) for n in ("sky.png", "far-clouds.png", "far-mountains.png", "near-clouds.png", "mountains.png", "trees.png")], (320, 240)), "bg", "dusk_a.png")
save(flatten([os.path.join(md, "version B/Layers", n) for n in ("sky.png", "far-mountains.png", "middle-mountains.png", "far-trees.png", "myst.png", "near-trees.png")]), "bg", "dusk_b.png")
save(flatten([os.path.join(md, "Version C/layers", n) for n in ("sky.png", "clouds.png", "far-mountains.png", "canyon.png", "front.png")], (320, 240)), "bg", "canyon.png")
save(flatten([os.path.join(find("caverns-files-web/**/layers"), n) for n in ("background.png", "back-walls.png")], (512, 288)), "bg", "crypt.png")
# parallax layers kept separately for the animated title screen
for n in ("sky", "far-clouds", "far-mountains", "near-clouds", "mountains", "trees"):
    save(Image.open(os.path.join(md, "version A/Layers", n + ".png")).convert("RGBA"), "bg", f"title_{n.replace('-', '_')}.png")


# ------------------------------------------------------------------ monsters (Pinero, RPG Maker side-view battlers)
PIN = os.path.dirname(find("**/wolf_0001_brown.png"))
MOTIONS = {"idle": (0, 1), "attack": (1, 1), "hurt": (0, 4), "dead": (2, 5)}
PINERO = {  # key: (file, target battle height in px)
    "wolf": ("wolf_0001_brown.png", 135), "alpha": ("Werewolf_0004_brown.png", 150), "rat": ("Rat_0004_dark.png", 100),
    "bat": ("Bat_0000_dark.png", 95), "skeleton": ("skelleton sheet.png", 140), "slime": ("slime waterB sheet.png", 85),
    "goblin": ("goblin sheet.png", 105), "kobold": ("kobold_0000_red.png", 120), "gnoll": ("gnoll sheet.png", 150),
    "troll": ("troll_0000_green.png", 190), "zombie": ("Zombies/zombie battler/zombie1 battler.png", 140),
}
for key, (fname, target) in PINERO.items():
    im = Image.open(os.path.join(PIN, fname)).convert("RGBA")
    cw, ch = im.width / 9.0, im.height / 6.0
    cells = []
    for motion, (grp, row) in MOTIONS.items():
        for f in range(3):
            x0, y0 = int(round((grp * 3 + f) * cw)), int(round(row * ch))
            cells.append((motion, f, im.crop((x0, y0, int(round(x0 + cw)), int(round(y0 + ch))))))
    # common scale from the tallest drawn figure in the idle frames
    h_drawn = max((c[2].getbbox() or (0, 0, 0, ch))[3] - (c[2].getbbox() or (0, 0, 0, 0))[1] for c in cells if c[0] == "idle")
    k = target / max(1, h_drawn)
    fw, fh = int(cw * k), int(ch * k)
    for motion in MOTIONS:
        for size_name, s in (("", 1.0), ("_map", 0.55)):
            w2, h2 = int(fw * s), int(fh * s)
            strip = Image.new("RGBA", (w2 * 3, h2))
            for (m, f, fr) in cells:
                if m == motion:
                    strip.paste(fr.resize((w2, h2), Image.LANCZOS), (f * w2, 0))
            save(strip, "units", f"pinero_{key}_{motion}{size_name}.png")


# ------------------------------------------------------------------ Pixel Frog characters (pigs, pirates, crabs)
def pf_strip(path_png, fw, scale, name):
    im = Image.open(path_png).convert("RGBA")
    im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
    save(im, "units", name)


KP = find("Kings and Pigs/Sprites")
for who, (folder, size) in {"pig": ("03-Pig", "34x28"), "kingpig": ("02-King Pig", "38x28")}.items():
    for src, dst in (("Idle", "idle"), ("Attack", "attack"), ("Hit", "hurt"), ("Dead", "dead")):
        pf_strip(os.path.join(KP, folder, f"{src} ({size}).png"), 0, 4, f"kp_{who}_{dst}.png")


def frames_dir(d, scale, name):
    fs = sorted(glob.glob(os.path.join(d, "*.png")), key=lambda f: int("".join(c for c in os.path.basename(f) if c.isdigit()) or 0))
    ims = [Image.open(f).convert("RGBA") for f in fs]
    w = max(i.width for i in ims)
    h = max(i.height for i in ims)
    strip = Image.new("RGBA", (w * len(ims), h))
    for k, i in enumerate(ims):
        strip.paste(i, (k * w + (w - i.width) // 2, h - i.height))
    strip = strip.resize((strip.width * scale, strip.height * scale), Image.NEAREST)
    save(strip, "units", name)
    return len(ims)


FRAMES = {}
PB = find("Pirate Bomb/Sprites")
for who, folder, motions in (("bigguy", "4-Enemy-Big Guy", {"1-Idle": "idle", "7-Attack": "attack", "12-Hit": "hurt", "14-Dead Ground": "dead"}),
                             ("captain", "5-Enemy-Captain", {"1-Idle": "idle", "7-Attack": "attack", "9-Hit": "hurt", "11-Dead Ground": "dead"}),
                             ("baldpirate", "2-Enemy-Bald Pirate", {"1-Idle": "idle", "7-Attack": "attack", "8-Hit": "hurt", "10-Dead Ground": "dead"})):
    for sub, m in motions.items():
        FRAMES[f"pb_{who}_{m}"] = frames_dir(os.path.join(PB, folder, sub), 2, f"pb_{who}_{m}.png")
TH = find("Treasure Hunters/Treasure Hunters")
for who in ("Crabby", "Fierce Tooth", "Pink Star"):
    base = os.path.join(TH, "The Crusty Crew/Sprites", who)
    key = who.lower().replace(" ", "")
    for sub, m in (("01-Idle", "idle"), ("07-Attack", "attack"), ("08-Hit", "hurt"), ("10-Dead Ground", "dead")):
        d = os.path.join(base, sub)
        if os.path.isdir(d):
            FRAMES[f"th_{key}_{m}"] = frames_dir(d, 3, f"th_{key}_{m}.png")
json.dump(FRAMES, open(os.path.join(OUT, "units", "frames.json"), "w"), indent=1)

# props: chest (idle + opening), barrel, boxes, coins
frames_dir(os.path.join(TH, "Merchant Ship/Sprites/Chest/Unlocked"), 3, "../props/chest_open.png")
chest = Image.open(sorted(glob.glob(os.path.join(TH, "Merchant Ship/Sprites/Chest/Idle/*.png")))[0]).convert("RGBA")
chest.resize((chest.width * 3, chest.height * 3), Image.NEAREST).save(os.path.join(OUT, "props", "chest.png"))
for n in ("Barrel", "Red Bottle", "Green Bottle", "Skull", "Table"):
    f = os.path.join(PB, "7-Objects/12-Other Objects", n + ".png")
    if os.path.exists(f):
        im = Image.open(f).convert("RGBA")
        im.resize((im.width * 2, im.height * 2), Image.NEAREST).save(os.path.join(OUT, "props", n.lower().replace(" ", "_") + ".png"))
box = Image.open(os.path.join(KP, "08-Box/Idle.png")).convert("RGBA")
box.resize((box.width * 3, box.height * 3), Image.NEAREST).save(os.path.join(OUT, "props", "box.png"))


# ------------------------------------------------------------------ item icons
GA = find("goblin/Icons 1.2")
LZ = find("RPG_ARSENAL_V1.1/Icons_no_background")
TR = os.path.join(TH, "Pirate Treasure/Sprites")
weapons_sheet = Image.open(os.path.join(GA, "All_Weapon_Icons 32x32.png")).convert("RGBA")


def wcell(c, r):
    return weapons_sheet.crop((c * 32, r * 32, c * 32 + 32, r * 32 + 32))


def gfile(sub, n):
    return Image.open(os.path.join(GA, sub, f"{n}.png")).convert("RGBA")


def first(dirname):
    fs = sorted(glob.glob(os.path.join(TR, dirname, "*.png")))
    return Image.open(fs[0]).convert("RGBA")


def lz(sub, n):
    return Image.open(os.path.join(LZ, sub, f"rpg_icons{n}.png")).convert("RGBA")


ICONS = {
    # weapons
    "spear": wcell(8, 0), "sword": wcell(0, 1), "hunter_bow": wcell(6, 0), "war_hammer": wcell(2, 2),
    "bandit_knife": wcell(3, 2), "chief_axe": wcell(3, 0), "starsteel": wcell(0, 2), "iron_mace": wcell(2, 4),
    "steel_sword": wcell(9, 0), "walking_stick": wcell(5, 0),
    # armour
    "padded_vest": gfile("Armors", 1), "hide_cloak": gfile("Armors", 12), "chainmail": gfile("Armors", 11),
    "wolf_pelt": gfile("Armors", 4), "leather_jerkin": gfile("Armors", 3), "fur_cloak": gfile("Armors", 8),
    "plate_cuirass": gfile("Armors", 2),
    # trinkets
    "lucky_coin": first("Gold Coin"), "boots": gfile("Accesories", 23), "wolf_tooth": gfile("Accesories", 4),
    "hermit_charm": gfile("Accesories", 11), "compass": gfile("Accesories", 17), "river_stone": gfile("Accesories", 12),
    "merchant_seal": gfile("Accesories", 15), "war_horn": gfile("Accesories", 3), "pearl_pendant": gfile("Accesories", 30),
    # consumables
    "salve": gfile("Misc", 15), "bread": gfile("Misc", 8), "honey": gfile("Misc", 34), "rations": gfile("Misc", 46),
    "tea": gfile("Misc", 23), "smoke_bomb": gfile("Misc", 20), "torch": wcell(2, 1), "wine": gfile("Misc", 16),
    "potion": lz("consumables", 129), "fish_pie": gfile("Misc", 47), "vigor_tonic": gfile("Misc", 22),
    # valuables
    "old_map": first("Big Map/Idle"), "sealed_letter": gfile("Misc", 43), "relic": first("Golden Skull"),
    "meteor_shard": gfile("Misc", 2), "gem": gfile("Misc", 11), "hide": gfile("Misc", 49), "pearl": gfile("Misc", 59),
    # resources / stats
    "res_iron": gfile("Misc", 3), "res_xp": first("Blue Diamond"), "res_hp": gfile("Misc", 15),
}
for k, im in ICONS.items():
    bb = im.getbbox()
    if bb:
        im = im.crop(bb)
    side = max(im.width, im.height)
    sq = Image.new("RGBA", (side, side))
    sq.paste(im, ((side - im.width) // 2, (side - im.height) // 2))
    sq = sq.resize((side * max(1, 64 // side), side * max(1, 64 // side)), Image.NEAREST)
    save(sq, "icons", k + ".png")
print("packs ok:", len(ICONS), "icons,", len(FRAMES), "pixel-frog strips")
