<p align="center">
  <img src="docs/images/logo.png" width="128" alt="Platyplus logo">
</p>

<h1 align="center">Platyplus</h1>

<p align="center">
  <b>Press F. That's most of the addon.</b> (The rest is pretty cool too.)<br>
  A dozen quality-of-life addons in one platypus, for WoW Forever.
</p>

<p align="center">
  <a href="README.fr.md">Français</a> ·
  <a href="https://www.curseforge.com/wow/addons/platyplus">CurseForge</a> ·
  <a href="https://github.com/bloufed/Platyplus/releases/latest">Download</a> ·
  <a href="CHANGELOG.md">Changelog</a> ·
  <a href="https://github.com/bloufed/Platyplus/issues">Report a bug</a>
</p>

---

The platypus is a duck, a beaver and an otter that agreed to share one body. Platyplus does the same with your
AddOns folder: a dozen small quality-of-life addons, one install, one settings window, one look.

It was born on **WoW Forever**, while leveling a warrior who was tired of clicking on things. Written for the
Forever client (1.60) and its restrictions, not ported from somewhere else.

![Platyplus in game: the options window](docs/images/options-key.jpg)

## One key

Point at something (or don't: it picks the nearest thing) and press `F`:

- talk to NPCs, loot chests and corpses, gather herbs and ore, skin;
- go through dialogs, accept quests, turn them in (and pick the first dialog option, if you want);
- use the quest item where the quest wants it (hold Shift to interact normally instead).

Two more keys **eat** and **drink** the best food in your bags, or a potion in combat. Your mouse can finally
retire. Press F to pay respects.

## Combat

- **Proc alerts**: the ability that just lit up (Overpower, Revenge, Victory Rush...) pops up with its icon and the
  key to press. Works for every class (glowing spells for casters, plus any spell you add); choose how many, with or
  without sound.
- **Threat window**: one line per mob you are fighting, with its health, who it is hitting and your threat. Hover a
  line to spot its nameplate. Now you know who pulled before the healer tells you.
- **Threat nameplates**, in the spirit of Threat Plates: tank or damage colors, quest progress right on the plate
  (3/8 boars), rare / elite / boss tags, and cast bars that tell you when your interrupt is ready. Presets, live
  preview, and every color is yours to change.
- **Swing timer**: a bar that fills up until your next auto attack, to time Heroic Strike and friends.
- **Mob control tooltips**: hover a mob to see if it stuns, roots, slows or fears, and for how long. Find out which
  one will fear you into the next pack *before* you pull it.
- **Buff reminders** (Battle Shout and friends), the buffs you can give to your group, and a right-click "ask for a
  buff" that whispers politely for you.
- **Healer mana bar**: your healer's mana, always in sight.

## Loot and gold

- **Instant loot**, and **sparkles** on the herbs, ore, corpses and quest items you can pick up.
- **Floating loot feed**: what you just got, where you can see it, including what you bought, crafted, sold and
  received from quests.
- **Loot roll tracker**: every item, every roll, who won, plus a `/roll` tab. Settles "wait, who won that?" for good.
- **Auto-sell** greys and gear you can't use, with never-sell / always-sell lists and a preview before anything
  goes. **Auto-repair** too.
- **Auction house helper**: scan your bags, post in a few clicks, prices remembered per realm and faction, and what
  your recipes cost to craft.

## Windows

- **Quest and dialog window** in large type, with **reward cards** that highlight the best pick for you.
- **One bag window** for all your bags, with sorting.
- **Character window** with reputation, skills, PvP and currencies, item level and durability.
- **Chat** with tabs, spam filters, copyable links, and a history that survives a `/reload`.

## Comfort

- Accepts or declines group invites, duels and summons for you (your call); quieter error messages.
- Recommended **game settings** in one click.
- A small platypus icon with an info bar: FPS, latency, gold, bags, durability, item level and XP. Click the XP to
  switch between %, XP per hour, time to level and mobs to level.

![The info bar, in game](docs/images/launcher.png)

Every feature has its own switch. Don't like our quest window? Turn it off. The platypus doesn't hold grudges.

## Getting started

1. **Install.** From [CurseForge](https://www.curseforge.com/wow/addons/platyplus), or download the latest zip
   from [Releases](https://github.com/bloufed/Platyplus/releases/latest) and extract it so that you get
   `World of Warcraft\_forever_\Interface\AddOns\Platyplus\Platyplus.toc`. Restart the game.
2. **The guided tour.** On your first login, a short tour opens, in English. **Pick your language at the top of its
   first page** (Français, Deutsch, Español, Italiano, Português, Русский): the tour switches right away. Then one
   small page per big feature, each with its main switches. Replay it any time with `/pp bienvenue` (or `/pp tuto`).
3. **Pick a mode.** The tour's second page (and the **Modes** tab of `/pp`) offers four starting points. One click
   sets every feature; then change whatever you like. Hover a mode to see exactly what it changes.
   - **Recommended** (the default): the useful features on, nothing that decides for you.
   - **Complete**: everything on, automations included: invites from friends and guild, summons, resurrections,
     duels declined, all mail opened, quests accepted and turned in without the key, healer mana bar.
   - **Immersive**: fewer windows and numbers: no combat alerts, info bar, loot feed, threat window or colored
     plates, no red error messages. The quiet helpers stay (the key, instant loot, selling, large quest windows).
   - **Minimal**: everything off except the icon; turn on only what you want.

   A mode never touches your key, your lists, positions, sizes or colors. `/pp mode complete` works too.
4. **The options.** Type `/pp`, or left-click the Platyplus icon. Tabs are on the left; hover any setting to read
   what it does. Right-click the icon for a quick on/off menu.
5. **Lost?** `/pp help` lists every command in the chat.

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

Comments and source strings are in French; translations live in `Locales/`.

Releases are cut by pushing a tag (`v1.0.1`): a GitHub Action builds the zip, attaches it to the release and
uploads it to CurseForge.

## Credits and license

Platyplus is free software under the [GNU GPL v3 or later](LICENSE).

- Loot sparkles are adapted from **Forever Loot Sparkles** by Ashtar Senior (GPL-3.0-or-later).
- Mob control data is generated from the **VMaNGOS** database (GPL-2.0).
- Threat nameplates are inspired by **Threat Plates**; the optional dungeon journal is **DungeonJournal** by Exehn.
- See [`Licenses/`](Licenses) for the full notices.

World of Warcraft is a trademark of Blizzard Entertainment. Platyplus is not affiliated with Blizzard.
