"""Génère MobControlsData.lua : quels mobs étourdissent, immobilisent, ralentissent, apeurent... et à quel rythme.

Sources :
  * VMaNGOS (https://github.com/vmangos/core, licence GPL-2.0), base du monde au format SQLite :
    release « db_latest », fichier db-sqlite-*.zip -> sqlite-dump/mangos.sqlite (gardé dans AddOns/_ref/vmangos).
    - creature_template.spell_list_id -> creature_spells : jusqu'à 8 sorts par mob, avec chance et délais
      (1er lancer entre delayInitialMin et Max secondes après le début du combat, puis toutes les
      delayRepeatMin à Max secondes) ;
    - creature_ai_events + creature_ai_scripts (commande 15 = lancer un sort) : sorts lancés par des
      événements (minuteur en combat, seuil de vie, engagement, distance, quand la cible incante...).
    VMaNGOS reproduit le jeu d'origine (1.12) : délais à prendre comme des ordres de grandeur.
  * Tables du client Forever (wago.tools, build fixé dans dev/wago.py, cache AddOns/_ref/wago) :
    SpellEffect (auras, effets, mécanique, cibles), SpellCategories (mécanique), SpellMisc (durée,
    temps d'incantation), SpellDuration, SpellCastTimes. C'est le client qui dit ce que fait un sort.

Résultat (ns.MobControlsData) :
  D.spells[spellID] = { "cat", durée en s (0 = inconnue, -1 = jusqu'à dissipation), incantation en s }
  D.lists[i]        = { spellID, quand, a, b, c, d, chance, ... }   (7 nombres par sort)
  D.mobs[npcID]     = i
  « quand » : 0 = minuteur en combat (a-b = 1er lancer, c-d = répétition, en s),
              2 = seuil de vie du mob (a = sous a %, c-d = répétition), 4 = à l'engagement,
              9 = selon la distance (a-b mètres, c-d = répétition), 12 = vie de la cible (a = sous a %),
              13 = quand la cible incante (c-d = répétition), 99 = autre déclencheur.

Usage :
  python -I dev\\make_mobcontrols.py [<mangos.sqlite>] [<dossier Platyplus>]
"""
import csv
import os
import sqlite3
import sys
from collections import defaultdict

DEV = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, DEV)
import wago  # noqa: E402  (cache et build du client)

ADDONS = os.path.normpath(os.path.join(DEV, "..", ".."))
DEFAULT_DB = os.path.join(ADDONS, "_ref", "vmangos", "sqlite-dump", "mangos.sqlite")

# Ordre = priorité quand un sort fait plusieurs choses (on garde la plus gênante).
CATS = ["stun", "incap", "fear", "charm", "root", "silence", "disarm", "knockback", "snare", "slowattack"]

AURA = {12: "stun", 5: "incap", 7: "fear", 2: "charm", 6: "charm", 26: "root", 27: "silence",
        60: "silence", 67: "disarm", 33: "snare"}
MECH = {12: "stun", 2: "incap", 10: "incap", 14: "incap", 17: "incap", 20: "incap", 30: "incap",
        5: "fear", 24: "fear", 1: "charm", 7: "root", 13: "root", 9: "silence", 3: "disarm",
        11: "snare", 27: "snare", 8: "slowattack", 18: "incap"}
APPLY_AURA_EFFECTS = {6, 27, 35, 65, 119, 128, 129}   # appliquer une aura (cible, zone persistante, zones)
KNOCK_BACK = 98
TRIGGER_EFFECTS = {64}                                 # déclencher un autre sort
TRIGGER_AURAS = {23}                                   # aura qui déclenche un sort à intervalle
CASTER_ONLY = {1}                                      # cible = le lanceur lui-même
MELEE_HASTE = 138                                      # ralentit les attaques si la valeur est négative

HEADER = """\
-- Platyplus : contrôles des mobs (étourdir, immobiliser, ralentir...) et leur rythme. Fichier GÉNÉRÉ par
-- dev/make_mobcontrols.py : ne pas modifier à la main.
-- Source des sorts par mob : VMaNGOS (https://github.com/vmangos/core), licence GPL-2.0 (Licenses/VMaNGOS.txt),
-- qui reproduit le jeu d'origine : délais à prendre comme des ordres de grandeur. Effet des sorts : client Forever.
-- D.spells[id] = { cat, durée s, incantation s } ; D.lists[i] = { sort, quand, a, b, c, d, chance, ... } ;
-- D.mobs[npcID] = i (voir le script pour « quand »)
local ADDON, ns = ...

local D = { spells = {}, lists = {}, mobs = {} }
ns.MobControlsData = D
"""


def table(name):
    wago.charger(name, False, False)   # télécharge si absent du cache
    path = os.path.join(wago.CACHE, f"{name}_{wago.BUILD}.csv")
    with open(path, encoding="utf-8-sig", errors="replace", newline="") as f:
        return list(csv.DictReader(f))


def num(v):
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return 0


def load_client():
    effects = defaultdict(list)
    for r in table("SpellEffect"):
        if num(r["DifficultyID"]) == 0:
            effects[num(r["SpellID"])].append(r)
    mech = {num(r["SpellID"]): num(r["Mechanic"]) for r in table("SpellCategories") if num(r["DifficultyID"]) == 0}
    misc = {num(r["SpellID"]): r for r in table("SpellMisc") if num(r["DifficultyID"]) == 0}
    dur = {num(r["ID"]): num(r["Duration"]) for r in table("SpellDuration")}
    cast = {num(r["ID"]): num(r["Base"]) for r in table("SpellCastTimes")}
    return effects, mech, misc, dur, cast


def classify(spell, client, depth=0):
    """Catégorie la plus gênante d'un sort pour la cible (None si ce n'est pas un contrôle)."""
    effects, mech, misc, _, _ = client
    if spell not in misc:
        return None
    found = set()
    spell_mech = MECH.get(mech.get(spell, 0))
    for e in effects.get(spell, ()):
        effect, aura = num(e["Effect"]), num(e["EffectAura"])
        on_self = num(e["ImplicitTarget_0"]) in CASTER_ONLY and num(e["ImplicitTarget_1"]) in (0, 1)
        if effect == KNOCK_BACK and not on_self:
            found.add("knockback")
        if effect in APPLY_AURA_EFFECTS and not on_self:
            cat = AURA.get(aura)
            if aura == 56 and spell_mech == "incap":         # transformation (métamorphose)
                cat = "incap"
            if aura == MELEE_HASTE and num(e["EffectBasePointsF"]) < 0:
                cat = "slowattack"
            if cat:
                found.add(cat)
            em = MECH.get(num(e["EffectMechanic"]))
            if em and cat:
                found.add(em)
        if depth == 0 and (effect in TRIGGER_EFFECTS or aura in TRIGGER_AURAS):
            sub = classify(num(e["EffectTriggerSpell"]), client, 1)
            if sub:
                found.add(sub)
    if found and spell_mech:
        return spell_mech      # la mécanique du sort prime (Bannir = aura d'étourdissement mais mécanique « bannir »)
    for cat in CATS:
        if cat in found:
            return cat
    return None


def spell_info(spell, client):
    _, _, misc, dur, cast = client
    m = misc[spell]
    d = dur.get(num(m["DurationIndex"]), 0)
    seconds = -1 if d < 0 else round(d / 1000, 1)
    return seconds, round(cast.get(num(m["CastingTimeIndex"]), 0) / 1000, 1)


def sec(ms):
    return round(max(0, ms) / 1000, 1)


def entries_from_spell_lists(db):
    """npcID -> [(sort, quand, a, b, c, d, chance)] depuis creature_spells (délais en secondes)."""
    lists = {}
    cols = [r[1] for r in db.execute("pragma table_info(creature_spells)")]
    for row in db.execute("select * from creature_spells"):
        r = dict(zip(cols, row))
        out = []
        for i in range(1, 9):
            spell = r.get(f"spellId_{i}") or 0
            if spell:
                out.append((spell, 0, r[f"delayInitialMin_{i}"], r[f"delayInitialMax_{i}"],
                            r[f"delayRepeatMin_{i}"], r[f"delayRepeatMax_{i}"], r[f"probability_{i}"] or 100))
        lists[r["entry"]] = out
    mobs = {}
    # Une ligne par patch : on garde la plus récente (1.12 = patch 10).
    for entry, list_id in db.execute(
            "select t.entry, t.spell_list_id from creature_template t "
            "where t.patch = (select max(patch) from creature_template u where u.entry = t.entry)"):
        if list_id and list_id in lists:
            mobs[entry] = list(lists[list_id])
    return mobs


def entries_from_event_ai(db):
    casts = defaultdict(list)
    for sid, spell in db.execute("select id, datalong from creature_ai_scripts where command = 15 and datalong > 0"):
        casts[sid].append(spell)
    mobs = defaultdict(list)
    for (npc, etype, chance, p1, p2, p3, p4, a1, a2, a3) in db.execute(
            "select creature_id, event_type, event_chance, event_param1, event_param2, event_param3, event_param4, "
            "action1_script, action2_script, action3_script from creature_ai_events"):
        if etype in (1, 11, 6, 5, 7):      # hors combat, apparition, mort, victoire, retour : pas un contrôle subi
            continue
        for script in (a1, a2, a3):
            for spell in casts.get(script, ()):
                if etype == 0:
                    t = (0, sec(p1), sec(p2), sec(p3), sec(p4))
                elif etype == 2:
                    t = (2, p1, p2, sec(p3), sec(p4))
                elif etype == 4:
                    t = (4, 0, 0, 0, 0)
                elif etype == 9:
                    t = (9, p1, p2, sec(p3), sec(p4))
                elif etype == 12:
                    t = (12, p1, p2, sec(p3), sec(p4))
                elif etype == 13:
                    t = (13, 0, 0, sec(p3), sec(p4))
                else:
                    t = (99, 0, 0, 0, 0)
                mobs[npc].append((spell,) + t + (chance or 100,))
    return mobs


def lua_num(v):
    if isinstance(v, float) and v.is_integer():
        v = int(v)
    return str(v)


def main():
    db_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_DB
    out_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.normpath(os.path.join(DEV, ".."))
    db = sqlite3.connect(db_path)
    client = load_client()

    raw = entries_from_spell_lists(db)
    # creature_spells donne les délais en secondes ; normaliser en nombres
    for npc in raw:
        raw[npc] = [(s, 0, sec(a * 1000), sec(b * 1000), sec(c * 1000), sec(d * 1000), ch)
                    for (s, _, a, b, c, d, ch) in raw[npc]]
    for npc, lst in entries_from_event_ai(db).items():
        raw.setdefault(npc, []).extend(lst)

    spells, cat_of = {}, {}
    mobs = {}
    for npc, lst in raw.items():
        keep, seen = [], set()
        for e in lst:
            spell = e[0]
            if spell not in cat_of:
                cat_of[spell] = classify(spell, client)
            if not cat_of[spell] or (spell, e[1]) in seen:
                continue
            seen.add((spell, e[1]))
            keep.append(e)
            if spell not in spells:
                spells[spell] = (cat_of[spell],) + spell_info(spell, client)
        if keep:
            keep.sort(key=lambda e: (CATS.index(cat_of[e[0]]), e[1]))
            mobs[npc] = tuple(keep)

    lists, index = [], {}
    mob_list = {}
    for npc in sorted(mobs):
        key = mobs[npc]
        if key not in index:
            lists.append(key)
            index[key] = len(lists)
        mob_list[npc] = index[key]

    lines = [HEADER, "local S = D.spells"]
    for spell in sorted(spells):
        cat, d, c = spells[spell]
        lines.append(f'S[{spell}] = {{ "{cat}", {lua_num(d)}, {lua_num(c)} }}')
    lines.append("\nlocal L = D.lists")
    for i, lst in enumerate(lists, 1):
        flat = ", ".join(lua_num(v) for e in lst for v in e)
        lines.append(f"L[{i}] = {{ {flat} }}")
    lines.append("\nlocal M = D.mobs")
    for npc in sorted(mob_list):
        lines.append(f"M[{npc}] = {mob_list[npc]}")
    path = os.path.join(out_dir, "MobControlsData.lua")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")

    counts = defaultdict(int)
    for cat, _, _ in spells.values():
        counts[cat] += 1
    print(f"{len(mob_list)} mobs, {len(lists)} listes, {len(spells)} sorts -> {path}")
    print("  " + ", ".join(f"{c} {counts[c]}" for c in CATS if counts[c]))
    print(f"  {os.path.getsize(path) // 1024} Ko")


if __name__ == "__main__":
    main()
