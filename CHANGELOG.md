# Changelog

## 1.0.1

- **Threat window** redrawn: each row is now the mob's health bar, with a colored stripe for its state, who holds
  it and your threat percentage in fixed columns, and a summary in the title bar ("5 mobs", "2 lost").
- **Threat window, on hover**: a tooltip says in plain words where you stand ("You hold it", "You are losing it",
  "It escaped you"...) and the mob's nameplate is outlined in the world so you can find it.
- **Threat window, diagnosis**: `/pp menace etat` explains why the window is shown or hidden and lists every mob it
  sees; `/pp menace` now says why when the window stays hidden. `/pp menace clic` tests whether your game accepts
  targeting a mob from a button (groundwork for click-to-target).
- **Fixed**: a row could flash "lost" at the start of a fight for a mob remembered from the previous one.
- **Fixed**: the eat and drink keys sometimes found nothing right after logging in, reloading or resurrecting.
- **Fixed**: "en combat :" stayed in French on the Eat and drink card in other languages.

## 1.0.0

Platyplus reaches 1.0: a guided tour, ready-made modes, and a Platyplus look for the dungeon journal.

- **Ready-made modes**: pick a starting point in one click — **Recommended** (the default), **Complete**
  (everything on, automations included), **Immersive** (fewer windows and numbers) or **Minimal** (everything off
  except the icon). On the tour's second page, in the new **Modes** tab (first tab of `/pp`) or with `/pp mode`.
  Hover a mode to see what it changes; your key, lists, positions and colors are never touched.
- **Guided tour**: the first-login welcome is now a short tour — one welcome page, then one small page per big
  feature (the key, combat, threat, loot, selling, windows, the icon) with its main switches and a link to its
  tab, and a last page with the commands to remember. Replay it with `/pp bienvenue` (also `/pp tuto`), from the
  Advanced tab or from the game's AddOns options.
- **Language first**: Platyplus now starts in English, and the first page of the tour offers every language
  (Français, Deutsch, Español, Italiano, Português, Русский) in one click; the tour switches right away. If your
  game is in one of them, a line in that language points you to it. Existing installs keep their language.
- **Dungeon journal**: with DungeonJournal by Exehn installed next to Platyplus, its window now gets the Platyplus
  look, a "Dungeons" column on the left (advised level, quests done, click to open) and an "At your level" row on
  the home page. Each has its switch in the Dungeons tab. Nothing of that addon is bundled or modified.
- **Removed**: the resource bar, the resource number on portraits and the spell costs on action buttons. The swing
  timer stays (Combat tab). Their old settings are cleaned from your saved variables.
- **Combat tab** reordered: swing timer, buff reminders, threat window, healer mana, mob controls.
- **Texts**: options, help and README reviewed in French and English (clearer tab descriptions, `/pp help` listed,
  English wording fixes); the quick menu of the icon gains a "Proc alert" switch.

## 0.3.0 — first public release

Platyplus goes public: everything built while leveling on WoW Forever, in one addon.

- **The key**: one key to interact, loot, talk, accept and turn in quests, use quest items; two keys to eat and drink.
- **Combat**: resource bar with spell costs, swing timer, proc alerts with keybinds, buff reminders and
  "ask for a buff", healer mana bar, mob control tooltips.
- **Threat**: threat-colored nameplates (presets, quest progress, cast bars, interrupt ready) and a threat window.
- **Loot**: instant loot, sparkles on lootables, floating loot feed, loot roll tracker with a `/roll` tab.
- **Selling**: auto-sell with lists and preview, auto-repair, auction house helper with a price database.
- **Windows**: quest and dialog window, reward cards, single bag window, character window, chat window.
- **Comfort**: launcher icon with info bar, auto accept/decline, recommended game settings.
- **Languages**: French, English, German, Spanish, Italian, Brazilian Portuguese, Russian.

The dungeon journal is not bundled: install DungeonJournal by Exehn and Platyplus opens it from its menu.
