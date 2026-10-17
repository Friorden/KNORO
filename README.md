# KNORO

A turn-based kingdom + tabletop-RPG game on an isometric hex world, in Tiny Swords–style pixel art.
You are the Champion of one kingdom: you walk the map yourself, fight with a small war band, delve into caves
and dungeons, carry loot home, build your capital and push it through three ages — while a story about the
nine pieces of an old crown leads you across the valley.

## Play

- **`build/KNORO.exe`** (Windows 10/11): double-click. Nothing to install.
- **`build/KNORO_mac.zip`** (macOS): unzip, then right-click → Open the first time (the app is not signed).
- **`Open in Godot.bat`**: opens the project in the Godot 4.7.2 editor (in `engine/`).

The game starts at the **main menu**: Continue · New game · Load · Settings · How to play · Credits · Quit.
A new game shows a short prologue, then the kingdom choice and your Champion.

## Controls

| Action | How |
|---|---|
| Roll the day's movement (1D6 + DEX bonus) | **Roll** button or `Space` |
| Walk | hover a hex to see the route, left-click to go |
| Pan / zoom | drag, `WASD` / arrows · `+` / `−` (the mouse wheel is ignored on purpose) |
| City | `C` or the **City** button |
| Bag (equipment) | `I` |
| Quest log | `J`, the **Quests** button, or click the tracker on the right |
| Menu (save, load, settings, help) | `Esc` or the **Menu** button |
| End the day | **End day** or `Enter` |
| Battle | pick a skill (`1`–`3`), then a glowing target |
| Music / sounds / fullscreen | `M` / `N` / `F11` |

## What's in the game

- **Story & quests**: an 8-step main quest (raise the banner → the ruins → the Crystal cave → bandit camps → Town →
  the Old crypt → the Sunken fort → City) and side quests offered every week (hogs, wolves, deliveries, explorers…).
  Quest log, on-screen tracker, rewards sent to your kingdom.
- **Caves & dungeons**: Crystal cave, Old crypt, Sunken fort. A row of rooms — fights, chests, traps, shrines, rest —
  and a guardian (kobold chief, crypt lord, troll king). Leave between rooms whenever you like.
- **World**: generated valley with rivers, lakes, roads, borders, fog of war, caravans, patrols, camps and dens,
  outposts, secrets, ~55 road events with D20 checks, conversations with hidden checks.
- **City**: 29 buildings, upgrades to level 3 with specialisations, production modes, storehouse items, land
  clearing and expansion, three ages.
- **Army & battles**: Darkest Dungeon–style ranks, 30+ enemy types from several packs.
- **Saves & settings**: autosave every day + 3 slots; volumes (master, music, sounds), fullscreen, screen shake,
  battle speed, hints.

## Art

Every picture comes from free asset packs (Pixel Frog's Tiny Swords, Kings and Pigs, Pirate Bomb, Treasure Hunters;
Robert Pinero's monsters; ansimuz's Mountain Dusk, Parallax Forest and Caverns; CraftPix crystal caves; LimeZu and
Goblin's Archive icons). Licences and credits: `game/assets/LICENSES.md` and the in-game Credits.
Some packs forbid redistributing their files, so **do not publish `game/assets/` in a public repository**.

## Folder map

```
Game/
├─ build/            KNORO.exe (Windows) and KNORO_mac.zip (macOS)
├─ engine/           Godot 4.7.2 editor (Windows)
├─ art_in/packs/     the original asset packs (not shipped)
├─ game/             the Godot project
│  ├─ data/          ★ all numbers and text as JSON: balance, buildings, units, enemies, ages, events,
│  │                   dialogues, kingdoms, items, quests, dungeons
│  ├─ sim/           the rules (world, state, quests, dungeons, battle, saves): no drawing, testable headless
│  ├─ render/        map and city renderers, pixel UI kit, backdrops, shaders
│  ├─ ui/            one script per screen (title, story, select, world, city, dungeon, battle, dialogue…) + widgets
│  ├─ core/          main scene, style, audio, settings, campaign holder
│  ├─ assets/        pack art (see LICENSES.md), fonts, generated sounds
│  ├─ tests/         sim_test.gd: world, economy, battles, events, city, quests, dungeons, save/load
│  └─ tools/         ts_prepare.py / packs_prepare.py (copy and cut the packs), gen_audio.py
└─ README.md
```

## Changing the game

- **Balance, text, quests, dungeons**: edit `game/data/*.json`, restart. No code.
- **Headless test**: `engine\Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/sim_test.gd`
- **Jump straight somewhere** (testing): `KNORO.exe -- --screen=battle:bandit_camp`, `--screen=dungeon:old_crypt`, `--screen=world`.
