#!/usr/bin/env python3
"""Builds the Event Codex: every Menslosia and Skyfall event, when it can fire, what it needs,
what each choice does, and how events chain into each other.

    python3 tools/event_codex.py          -> docs/events.html (interactive) and docs/EVENTS.md

Re-run after editing data/events.json.
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NATIONS = {"MEN": "Menslosia", "SKY": "Skyfall"}
START, END = 4289, 4789
POWER = {"MEN": ["Lotus", "Accord", "Unity"], "SKY": ["Core", "Eden", "Wings"]}

data = json.load(open(os.path.join(ROOT, "data", "events.json")))
nations = json.load(open(os.path.join(ROOT, "data", "nations.json")))["nations"]
names = {k: v.get("short", k) for k, v in nations.items()}
names.update({"REB": "Rebels", "ENT": "Entities"})
EVENTS = [e for e in data["events"] if e.get("for") in NATIONS]
BY_ID = {e["id"]: e for e in data["events"]}


def nm(t):
    return names.get(t, t)


def cond(c):
    t = c.get("type", "")
    neg = c.get("negate", False)
    s = {
        "year_at_least": lambda: "from %s" % c["value"],
        "flag": lambda: "flag “%s”" % c["name"].replace("_", " "),
        "not_flag": lambda: "no flag “%s”" % c["name"].replace("_", " "),
        "owns": lambda: "owns %s" % c["province"],
        "owns_region": lambda: "owns all of %s" % c["region"],
        "explored": lambda: "has explored %s" % c["province"],
        "explored_count": lambda: "has explored %d %s provinces" % (c["at_least"], c.get("layer", "")),
        "tech_at_least": lambda: "%s tech %d" % (c["track"].upper(), c["at_least"]),
        "ideas_at_least": lambda: "%d ideas" % c["at_least"],
        "regiments_at_least": lambda: "%d regiments" % c["at_least"],
        "treasury_at_least": lambda: "%d sanctum" % c["at_least"],
        "stability_at_least": lambda: "stability %+d" % c["at_least"],
        "legitimacy_at_least": lambda: "legitimacy %d" % c["at_least"],
        "province_dev_at_least": lambda: "%s at %d development" % (c["province"], c["at_least"]),
        "provinces_owned_at_least": lambda: "%d provinces" % c["at_least"],
        "buildings_at_least": lambda: "%d %ss" % (c["at_least"], c["building"]),
        "battles_won_at_least": lambda: "%d battles won" % c["at_least"],
        "at_war": lambda: "at war",
        "not_at_war": lambda: "at peace",
        "nation_dead": lambda: "%s is gone" % nm(c["tag"]),
        "allied_with": lambda: "allied with %s" % nm(c["tag"]),
        "opinion_at_least": lambda: "%s's opinion %d" % (nm(c["tag"]), c["at_least"]),
        "mines_at_least": lambda: "%d mines" % c["at_least"],
        "portal_held_by_entities": lambda: "entities hold the portal",
        "subdued": lambda: "%s conquered or a subject" % nm(c["tag"]),
        "province_has_building": lambda: "a %s in %s" % (c["building"], c["province"]),
        "owns_mainland": lambda: "land on the Arcadian continent",
        "is_tag": lambda: "is %s" % nm(c["tag"]),
    }.get(t, lambda: t.replace("_", " "))()
    if neg:
        return "not: " + s
    return s


def eff(e, tag):
    t = e.get("type", "")
    a = e.get("amount", 0)
    pn = POWER.get(tag, ["adm", "dip", "mil"])
    if t == "add_power":
        return "%+d %s" % (a, pn[int(e.get("index", 0))])
    if t == "add_treasury":
        return "%+d sanctum" % a
    if t == "add_stability":
        return "%+d stability" % a
    if t == "add_legitimacy":
        return "%+d legitimacy" % a
    if t == "add_manpower":
        return "%+d manpower" % a
    if t == "add_army_tradition":
        return "%+d army tradition" % a
    if t == "add_reform_progress":
        return "%+d reform progress" % a
    if t == "add_autonomy":
        return "%+d autonomy everywhere" % a
    if t == "add_opinion":
        return "%+d opinion with %s" % (a, nm(e.get("target", "")))
    if t == "add_modifier":
        mods = ", ".join("%s %s" % (k.replace("_", " "), ("%+d%%" % round(v * 100)) if abs(v) < 1 and k not in ("unrest", "monthly_adm", "monthly_dip", "monthly_mil", "merchants", "leader_maneuver", "naval_force_limit") else "%+g" % v)
                         for k, v in e.get("modifiers", {}).items())
        m = int(e.get("months", -1))
        dur = "" if m < 0 else (" for %d years" % (m // 12) if m >= 12 else " for %d months" % m)
        return "“%s”: %s%s" % (e.get("name", ""), mods, dur)
    if t == "set_flag":
        return "sets flag “%s”" % e["name"].replace("_", " ")
    if t == "clear_flag":
        return "clears flag “%s”" % e["name"].replace("_", " ")
    if t == "fire_event":
        tgt = BY_ID.get(e["id"], {}).get("title", e["id"])
        d = int(e.get("delay_days", 0))
        return "leads to “%s”%s" % (tgt, " after %d days" % d if d else "")
    if t == "add_claim":
        return "claims on %s" % (nm(e["tag"]) if "tag" in e else e.get("province", ""))
    if t == "reveal":
        return "reveals %s" % e["province"]
    if t == "add_dev":
        return "%+d development in %s" % (a, e["province"])
    if t == "declare_war":
        return "declares war on %s" % nm(e.get("target", ""))
    if t == "price_shock":
        return "%s prices ×%s" % (e["goods"].replace("_", " "), e["factor"])
    if t == "spawn_leader":
        return "a new general"
    return t.replace("_", " ")


def timing(e):
    trig = e.get("trigger", {})
    lo, hi = START, END
    for c in trig.get("conditions", []):
        if c.get("type") == "year_at_least" and not c.get("negate"):
            lo = max(lo, int(c["value"]))
    yw = trig.get("years")
    if yw:
        if int(yw[0]) > 0:
            lo = max(lo, int(yw[0]))
        if int(yw[1]) > 0:
            hi = min(hi, int(yw[1]))
    if "date" in trig:
        y = int(trig["date"][:4])
        lo = hi = y
    sp = trig.get("special", "")
    kind, how = "random", ""
    if sp == "fired_by_effect":
        kind, how = "chained", "Fired by another event"
    elif sp:
        kind, how = "special", {"doomsday": "When the Black Moon rises (29 February of leap years)"}.get(sp, sp)
    elif "date" in trig:
        kind, how = "date", "On %s" % trig["date"]
    elif "mtth_months" in trig:
        m = trig["mtth_months"]
        how = "Mean time to happen: %s months" % m
        for mm in trig.get("mtth_modifiers", []):
            f = mm["factor"]
            how += "; ×%s if %s" % (f, " and ".join(cond(c) for c in mm["conditions"]))
    elif "monthly_chance" in trig:
        how = "%.1f%% chance a month" % (100 * float(trig["monthly_chance"]))
    return kind, how, lo, hi


rows = []
for e in EVENTS:
    kind, how, lo, hi = timing(e)
    tag = e["for"]
    opts = [{"text": o.get("text", ""), "effects": [eff(x, tag) for x in o.get("effects", [])]} for o in e.get("options", [])]
    kids, sets, needs = [], set(), set()
    for o in e.get("options", []):
        for x in o.get("effects", []):
            if x["type"] == "fire_event":
                kids.append(x["id"])
            if x["type"] == "set_flag":
                sets.add(x["name"])
    for c in e.get("trigger", {}).get("conditions", []):
        if c.get("type") == "flag":
            needs.add(c["name"])
    rows.append({"id": e["id"], "nation": tag, "title": e.get("title", e["id"]), "text": e.get("text", ""),
                 "once": bool(e.get("once")), "kind": kind, "how": how, "lo": lo, "hi": hi,
                 "conds": [cond(c) for c in e.get("trigger", {}).get("conditions", [])],
                 "options": opts, "kids": kids, "sets": sorted(sets), "needs": sorted(needs)})

# links: chains (fire_event) and flags one event sets that another needs
links = []
by = {r["id"]: r for r in rows}
for r in rows:
    for k in r["kids"]:
        if k in by:
            links.append({"from": r["id"], "to": k, "why": "leads to"})
    for f in r["sets"]:
        for q in rows:
            if f in q["needs"] and q["id"] != r["id"]:
                links.append({"from": r["id"], "to": q["id"], "why": "unlocks (flag “%s”)" % f.replace("_", " ")})

os.makedirs(os.path.join(ROOT, "docs"), exist_ok=True)
# ------------------------------------------------------------------ markdown
md = ["# Arcadia event codex", "",
      "Every Menslosia and Skyfall event: when it can fire, what it needs, and what each choice does. "
      "Generated from `data/events.json` by `tools/event_codex.py`.", ""]
for tag, label in NATIONS.items():
    rs = sorted([r for r in rows if r["nation"] == tag], key=lambda r: (r["lo"], r["title"]))
    md += ["## %s (%d events)" % (label, len(rs)), ""]
    for r in rs:
        when = ("%d" % r["lo"]) if r["lo"] == r["hi"] else ("%d–%s" % (r["lo"], "" if r["hi"] >= END else r["hi"]))
        md.append("### %s%s" % (r["title"], " (once)" if r["once"] else ""))
        md.append("`%s` · years %s · %s" % (r["id"], when if r["kind"] != "chained" else "via a chain", r["how"]))
        if r["conds"]:
            md.append("- Needs: " + "; ".join(r["conds"]))
        for o in r["options"]:
            md.append("- **%s** %s" % (o["text"], ", ".join(o["effects"])))
        md.append("")
md += ["## Chains", ""] + ["- %s → %s (%s)" % (by[l["from"]]["title"], by[l["to"]]["title"], l["why"]) for l in links]
open(os.path.join(ROOT, "docs", "EVENTS.md"), "w").write("\n".join(md) + "\n")

# ------------------------------------------------------------------ html
tpl = open(os.path.join(ROOT, "tools", "event_codex_template.html")).read()
payload = json.dumps({"rows": rows, "links": links, "start": START, "end": END}, ensure_ascii=False).replace("</", "<\\/")
open(os.path.join(ROOT, "docs", "events.html"), "w").write(tpl.replace("/*DATA*/null", payload))
print("wrote docs/events.html and docs/EVENTS.md: %d events, %d links" % (len(rows), len(links)))
