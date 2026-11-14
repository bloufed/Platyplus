<p align="center">
  <img src="docs/images/logo.png" width="128" alt="Platyplus logo">
</p>

<h1 align="center">Platyplus</h1>

<p align="center">
  <b>All-in-one quality of life for WoW Forever.</b><br>
  One key that does almost everything, combat alerts and threat you can read at a glance, loot and selling without
  clicks, and cleaner windows — in a single addon.
</p>

<p align="center">
  <a href="README.fr.md">Français</a> ·
  <a href="https://github.com/bloufed/Platyplus/releases/latest">Download</a> ·
  <a href="CHANGELOG.md">Changelog</a> ·
  <a href="https://github.com/bloufed/Platyplus/issues">Report a bug</a>
</p>

---

Platyplus started as a single shortcut I wanted while leveling my warrior on **WoW Forever**, and it kept growing
through the whole adventure: every time something in the game felt slow, noisy or hard to read, it became a new
module. Today it replaces a dozen small addons with one, with a single options window and one look.

The useful features are on from the start, so you can just play. Prefer another starting point? Pick a ready-made
mode (**Recommended**, **Complete**, **Immersive** or **Minimal**) and every feature is set in one click. Each one
still has its own switch in `/pp`, and a short guided tour on your first login shows what each feature does.

![The options window](docs/images/options-key.jpg)

> The images on this page are rendered by the addon's offline simulator (item and spell icons are placeholders).
> In-game screenshots are coming.

## Why Platyplus

- **One addon instead of twelve.** Interaction, loot, selling, combat alerts, nameplates, threat, procs, chat, bags,
  character sheet: one install, one settings window, one consistent style.
- **One key that does everything.** Press `F` (or any key you choose) to talk, loot, gather, skin, accept and turn
  in quests, and use the quest item where it belongs.
- **Threat you can actually read.** Nameplates colored by threat, plus a threat window listing every mob you are
  fighting and who holds it.
- **Windows redone.** Quests, bags, character, chat and loot rolls in large, clean windows drawn from scratch.
- **Built for Forever.** Written against the Forever client (1.60) and its secret-value restrictions, not ported
  from another game version.
- **7 languages.** Français, English, Deutsch, Español, Italiano, Português (BR), Русский.

## Getting started

1. **Install.** Download the latest zip from [Releases](https://github.com/bloufed/Platyplus/releases/latest)
   (or from CurseForge) and extract it so that you get
   `World of Warcraft\_forever_\Interface\AddOns\Platyplus\Platyplus.toc`. Restart the game.
2. **The guided tour.** On your first login, a short tour opens, in English. **Pick your language at the top of its
   first page** (Français, Deutsch, Español, Italiano, Português, Русский): the tour switches right away. Then: one welcome page, then one small page per big
   feature (the key, combat, threat, loot, selling, windows, the icon), each with its main switches. Skip it or come
   back to it any time with `/pp bienvenue` (or `/pp tuto`).
3. **Pick a mode.** The tour's second page (and the **Modes** tab of `/pp`) offers four starting points. One click
   sets every feature; then change whatever you like. Hover a mode to see exactly what it changes.
   - **Recommended** (the default): the useful features on, nothing that decides for you.
   - **Complete**: everything on, automations included: invites from friends and guild, summons, resurrections,
     duels declined, all mail opened, quests accepted and turned in without the key, healer mana bar.
   - **Immersive**: fewer windows and numbers: no combat alerts, info bar, loot feed, threat window or colored
     plates, no red error messages. The quiet helpers stay (the key, instant loot, selling, large quest windows).
   - **Minimal**: everything off except the icon; turn on only what you want.

   A mode never touches your key, your lists, positions, sizes or colors. `/pp mode complete` works too.
4. **The options.** Type `/pp`, or left-click the Platyplus icon on your screen. Tabs are on the left; hover any
   setting to read what it does. Right-click the icon for a quick on/off menu.
5. **Lost?** `/pp help` lists every command in the chat.

![The guided tour](docs/images/tour.jpg)

## Features

### The key

- One key to interact with what you point at, or the nearest thing: NPCs, chests, herbs, corpses to skin.
- The same key advances dialogs, accepts quests and turns them in, and can pick the first dialog option.
- Uses the quest item at the right place (hold Shift to interact normally instead).
- Two more keys to **eat** and **drink**: the best food or drink in your bags out of combat, a potion in combat.

### Combat

![Proc alert, loot feed and swing timer](docs/images/hud.jpg)

- **Proc alerts**: the ability that just became usable pops up with its icon and its keybind (Overpower, Revenge,
  Execute, Riposte, Counterattack and the like, glowing spells for casters, plus any spell you add).
- **Swing timer**: a bar that fills up until your next auto attack, to time Heroic Strike and friends.
- **Threat window**: one line per mob in combat — health, who it is attacking, your threat percentage.
- **Threat nameplates** in the spirit of Threat Plates: tank or damage colors, quest progress, rare / elite / boss
  tags, cast bars that tell you when your interrupt is ready. Presets, rounded bars, live preview.
- **Buff reminders** (Battle Shout and friends), the buffs you can give to allies, and "ask for a buff" in the
  right-click menu of a player.
- **Healer mana bar** for your group, and **mob control tooltips**: which stuns, roots, slows and fears a mob has,
  and how long they last.

| Threat window | Threat nameplates |
|---|---|
| ![Threat window](docs/images/threat.jpg) | ![Nameplate options with live preview](docs/images/options-plates.jpg) |

### Loot and gold

- **Instant loot**, sparkles on what you can pick up (herbs, quest objects, corpses with loot), and a floating
  **loot feed** that also shows what you bought, crafted, sold and received from quests.
- **Loot roll tracker**: every item, every player, who needs, who greeds, who won — plus a `/roll` tab.
- **Auto-sell** grey items and unusable gear, with "never sell" / "always sell" lists and a preview before anything
  is sold. Auto-repair.
- **Auction house helper**: scan your bags, post in a few clicks, remember prices per realm and faction, and see
  what a recipe costs against the auction house.

![Loot rolls](docs/images/loot-rolls.jpg)

### Windows

- **Quest and dialog window** in large type, with big **reward cards** that highlight the best choice for you.
- **One bag window** for all your bags, with sorting.
- **Character window** with reputation, skills, PvP and currency tabs, item level and durability.
- **Chat**: a cleaner chat window with tabs, spam filters, history that survives a reload, and copyable links.

| Reward cards | Quest window |
|---|---|
| ![Reward cards](docs/images/reward-cards.jpg) | ![Quest window](docs/images/quest-window.jpg) |

| Character | Chat |
|---|---|
| ![Character window](docs/images/character.jpg) | ![Chat window](docs/images/chat.jpg) |

### Comfort

- Accept or decline group invites, duels and summons for you; quieter error messages.
- A small **launcher icon** with an info bar: FPS, latency, gold, bag space, durability, item level, XP and XP per
  hour — placed wherever you like.
- Recommended **game settings** in one click.

## Commands

| Command | What it does |
|---|---|
| `/pp` | Open the options window |
| `/pp help` | List every command |
| `/pp bienvenue` | Replay the guided tour (also `/pp tuto`) |
| `/pp mode [name]` | Show your mode, or switch: `recommended`, `complete`, `immersive`, `minimal` |
| `/pp key` | Change the key |
| `/pp menace` | Threat window (`on`, `off`, `test`, `reset`) |
| `/pp plates` | Nameplates (`on`, `off`, `tank`, `dps`, `auto`) |
| `/pp proc` | Proc alert: what is watched, preview |
| `/pp jets` | Loot roll window |
| `/pp mob` | Mob control tooltips |
| `/pp langue` | Language (`auto`, `frFR`, `enUS`, `deDE`, `esES`, `itIT`, `ptBR`, `ruRU`) |

## Good to know

- **Status.** Platyplus is young and under active development. It was built and played on a warrior; other
  classes are supported but less battle-tested. Bug reports are very welcome.
- **Windows replaced.** Platyplus draws its own quest, bag, character and chat windows. If you prefer the game's
  own windows, turn them off in the **Windows** and **Chat** tabs (or on the "Windows" page of the tour): the
  originals come back at once.
- **Your key.** Platyplus uses `F` by default. If the game already had something on that key, the tab **The key**
  tells you; pick another key there or with `/pp key`.
- **Dungeon journal.** Platyplus does not include a dungeon journal. If you install
  [DungeonJournal by Exehn](https://www.curseforge.com/wow/addons/dungeonjournal), Platyplus opens it from its
  menu, its Dungeons tab and `/pp donjons`, and dresses it up: the Platyplus look, a "Dungeons" column on the
  left and an "At your level" row on the home page (each with its own switch). These are Platyplus's work, not
  Exehn's: switch them off in the Dungeons tab before reporting a bug to DungeonJournal.
- **Translator companion.** The `Traducteur/` folder of this repository is an optional Windows program (Python +
  a local Ollama model) that translates chat into French. It is not part of the addon download.

## For developers

The repository root is the addon folder. `dev/` holds an offline WoW simulator, about fifty test files and the
tools around them; none of it ships in the release zip.

```
python -I dev/verifier.py          # syntax of every file + all offline tests
python -I dev/apercu.py            # render the HTML previews of every window
```

`CLAUDE.md` is the map of the code (modules, widgets, recipes, pitfalls of the Forever client). Comments and
source strings are in French; translations live in `Locales/`.

Releases are cut by pushing a tag (`v1.0.0`): a GitHub Action builds the zip, attaches it to the release and
uploads it to CurseForge.

## Credits and license

Platyplus is free software under the [GNU GPL v3 or later](LICENSE).

- Loot sparkles are adapted from **Forever Loot Sparkles** by Ashtar Senior (GPL-3.0-or-later).
- Mob control data is generated from the **VMaNGOS** database (GPL-2.0).
- Threat nameplates are inspired by **Threat Plates**; the optional dungeon journal is **DungeonJournal** by Exehn.
- See [`Licenses/`](Licenses) for the full notices.

World of Warcraft is a trademark of Blizzard Entertainment. Platyplus is not affiliated with Blizzard.
