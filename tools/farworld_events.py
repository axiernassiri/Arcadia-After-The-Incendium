"""Adds the far world's own events to data/events.json (run once; running it again replaces them).

Combustion Ayam, SILK, Oceania, the Satian Union, Fuarland, Stellaris and the Llama Nation each get
their own events, a few chains between neighbours (Ayam teaches the Satians, Fuarland eyes the Llama
highlands, Stellarin spies in Fuarland), and two events shared by the whole far world ("farworld").
Usage: python tools/farworld_events.py
"""
import json
from pathlib import Path

PATH = Path(__file__).resolve().parent.parent / "data" / "events.json"
TAG = "farworld_v1"   # marks the events this script owns, so a re-run replaces them


def pw(i, n): return {"type": "add_power", "index": i, "amount": n}
def gold(n): return {"type": "add_treasury", "amount": n}
def stab(n): return {"type": "add_stability", "amount": n}
def men(n): return {"type": "add_manpower", "amount": n}
def op(tag, n): return {"type": "add_opinion", "target": tag, "amount": n}
def flag(name, glob=False): return {"type": "set_flag", "name": name, **({"scope": "global"} if glob else {})}
def fire(eid, tag, days=0): return {"type": "fire_event", "id": eid, "target": tag, "delay_days": days}
def mod(mid, name, mods, months=-1): return {"type": "add_modifier", "id": mid, "name": name, "modifiers": mods, "months": months}
def dev(prov, i, n): return {"type": "add_dev", "province": prov, "index": i, "amount": n}
def trad(n): return {"type": "add_army_tradition", "amount": n}
def legit(n): return {"type": "add_legitimacy", "amount": n}
def year(y): return {"type": "year_at_least", "value": y}
def alive(tag): return {"type": "nation_dead", "tag": tag, "negate": True}
def noflag(name, glob=False): return {"type": "not_flag", "name": name, **({"scope": "global"} if glob else {})}
def hasflag(name, glob=False): return {"type": "flag", "name": name, **({"scope": "global"} if glob else {})}


def opt(text, effects, ai=None):
    o = {"text": text, "effects": effects}
    if ai is not None:
        o["ai_weight"] = ai
    return o


def ev(eid, for_, title, text, options, chance=None, conditions=None, once=False, chained=False, date=None):
    if chained:
        trig = {"special": "fired_by_effect"}
    elif date:
        trig = {"date": date}
    else:
        trig = {"monthly_chance": chance}
        if conditions:
            trig["conditions"] = conditions
    e = {"id": eid, "for": for_, "trigger": trig, "title": title, "text": text, "options": options, "_set": TAG}
    if once:
        e["once"] = True
    return e


EVENTS = [
    # ------------------------------------------------------------ Combustion Ayam
    ev("aym_everburning_engine", "AYM", "The Everburning Engine",
       "In the workshops of Ayam Prime a young hen has built an engine that runs for a week on a single scoop of fuel. The other inventors are already arguing about who thought of it first.",
       [opt("Keep it secret. Ayam's lead is Ayam's.", [mod("aym_engine_secret", "The Everburning Engine", {"tech_cost_mod": -0.10, "production_mod": 0.05}, 240)], 1.5),
        opt("Share the drawings with the Satian Union.", [pw(1, 60), op("SAT", 30), fire("sat_ayam_teachers", "SAT", 30)], 1.0)],
       chance=0.03, conditions=[year(4291), {"type": "tech_at_least", "track": "adm", "at_least": 3}], once=True),
    ev("aym_kiln_fire", "AYM", "Fire in the Kilns of Pyrespire",
       "A kiln in Pyrespire has burst, and the fire has jumped from roof to roof along the workshop streets. The chickens are fast, but the flames are faster.",
       [opt("Pay whatever it takes to rebuild.", [gold(-60), stab(1)], 1.0),
        opt("Rebuild slowly, from what's left.", [dev("Pyrespire", 1, -1)], 1.0)],
       chance=0.02),
    ev("aym_mainland_horizon", "AYM", "The Mainland on the Horizon",
       "Our longest-range airship has come home with sketches of a great land to the north, full of pigs and their walled cities. Menslosia, they call the biggest of their realms.",
       [opt("Send envoys and trade engines for grain.", [op("MEN", 25), pw(1, 40)], 1.2),
        opt("Build a fleet worthy of the open sea.", [mod("aym_blue_water", "Blue-Water Fleet", {"naval_morale": 0.10, "naval_force_limit": 4}, 300)], 1.0),
        opt("Let them come to us, if they ever can.", [stab(1)], 0.6)],
       chance=0.04, conditions=[year(4292)], once=True),
    ev("aym_flame_festival", "AYM", "The Festival of the Eternal Flame",
       "Once in a generation the high kiln of the Combustion Creed is opened and every household lights a lamp from it. The ring-isle glows all night.",
       [opt("Light the lamps.", [stab(1), legit(5)], 1.0),
        opt("Light the lamps, and the forges too.", [gold(-40), mod("aym_festival_forges", "Festival Forges", {"build_cost_mod": -0.15}, 60)], 1.0)],
       chance=0.015, conditions=[{"type": "stability_at_least", "at_least": 0}]),
    ev("aym_satian_rivalry", "AYM", "Satian Ambitions",
       "Our envoys report that the Satian assembly now talks openly of 'catching up with the chickens'. Some of our council find this charming. Some do not.",
       [opt("Charming. Offer them a trade pact.", [op("SAT", 20), gold(30)], 1.2),
        opt("Remind them who built their ships.", [op("SAT", -25), pw(2, 30)], 0.5)],
       chance=0.02, conditions=[year(4300), alive("SAT")], once=True),

    # ------------------------------------------------------------ Satian Union
    ev("sat_ayam_teachers", "SAT", "Teachers from Ayam",
       "A ship from Combustion Ayam has docked at Satia carrying a crate of drawings and three very confident engineers. They offer to teach our workshops how their engines work.",
       [opt("Welcome them. We have a lot to learn.", [mod("sat_ayam_lessons", "Lessons from Ayam", {"tech_cost_mod": -0.10, "production_mod": 0.05}, 240), op("AYM", 20)], 1.5),
        opt("Thank them, and learn it our own way.", [stab(1), pw(0, 50)], 0.6)],
       chained=True),
    ev("sat_tidewheel_turns", "SAT", "The Tidewheel Turns",
       "The priests of the Tidewheel say the great tide of the century has come in. Fishing boats come home so full they sit low in the water.",
       [opt("Sell the catch abroad.", [gold(50)], 1.0),
        opt("Feed the islands first.", [stab(1), men(1000)], 1.0)],
       chance=0.02),
    ev("sat_assembly_quarrel", "SAT", "A Quarrel in the Island Assembly",
       "The delegates of Storm Rock and Tide Cay have come to blows over who pays for the new harbour. The assembly hall has been closed until tempers cool.",
       [opt("Storm Rock pays: it gets the harbour.", [gold(-30), dev("Storm Rock", 1, 1)], 1.0),
        opt("Everyone pays a little, and nobody is happy.", [stab(-1), pw(0, 40)], 0.8),
        opt("Shelve the harbour.", [stab(1)], 1.0)],
       chance=0.02),
    ev("sat_pelari_settlers", "SAT", "Settlers for Pelari",
       "Fishing families from the crowded towns ask the assembly to help them settle the empty shores of Pelari, across the strait.",
       [opt("Give them boats and seed.", [gold(-40), mod("sat_pelari_drive", "The Pelari Drive", {"colonist_growth": 0.5, "colonists": 1}, 120)], 1.5),
        opt("Our islands come first.", [stab(1)], 0.5)],
       chance=0.05, conditions=[year(4290)], once=True),
    ev("sat_storm_season", "SAT", "Storm Season",
       "The storms have come early this year and two villages on Mist Key have been washed into the sea.",
       [opt("Rebuild them.", [gold(-40)], 1.0),
        opt("Move the families inland.", [dev("Mist Key", 0, -1), stab(1)], 1.0)],
       chance=0.015),

    # ------------------------------------------------------------ Oceania
    ev("oce_surface_dwellers", "OCE", "The Surface Dwellers",
       "Our scouts have climbed into the bright dry world above the waves and come back gasping. Up there, they say, live creatures who drown in air too thin to hold them and breathe nothing at all.",
       [opt("Study them from below.", [pw(1, 50)], 1.2),
        opt("They are dangerous. Ready the guard.", [mod("oce_wary", "Wary of the Surface", {"fort_defense": 0.20, "land_morale": 0.05}, 240)], 1.0)],
       chance=0.05, conditions=[year(4290)], once=True),
    ev("oce_mask_workshops", "OCE", "The Mask Workshops",
       "The artisans of the Fathom Vault have made a mask that holds water against the face, so an Oceanian can walk on land for days. The first volunteers are terrified.",
       [opt("Arm the legions with them.", [mod("oce_masked_legions", "Masked Legions", {"land_morale": 0.10}, -1), trad(10)], 1.2),
        opt("Sell them to merchants first.", [gold(80)], 0.8)],
       chance=0.04, conditions=[{"type": "tech_at_least", "track": "mil", "at_least": 3}], once=True),
    ev("oce_pearl_glut", "OCE", "A Glut of Pearls",
       "The oyster beds of the Abyss Garden have never been richer. Pearls are piling up in the vaults faster than we can sell them.",
       [opt("Flood the market.", [gold(100), {"type": "price_shock", "goods": "pearls", "factor": 0.7}], 1.0),
        opt("Hoard them: their worth is in being rare.", [mod("oce_pearl_hoard", "Pearl Hoard", {"interest_mod": -0.25}, 120)], 1.0)],
       chance=0.02),
    ev("oce_leviathan_stirs", "OCE", "The Leviathan Stirs",
       "Something vast has turned over in the trench beneath the Leviathan Throne. The water has gone cold, and the shoals have fled.",
       [opt("Make the old offerings.", [gold(-50), stab(1)], 1.0),
        opt("Hunt it.", [men(-2000), trad(15), pw(2, 40)], 0.7)],
       chance=0.012),
    ev("oce_sunken_ruins", "OCE", "Ruins Older Than the Sea",
       "Divers in the Sunken Garden have found streets and towers under the silt, older than Oceania. The carvings show creatures with lungs, staring up at the stars.",
       [opt("Bring the carvings to our scholars.", [pw(0, 60), pw(1, 30)], 1.2),
        opt("Seal the ruins. Some things are better left drowned.", [stab(1)], 0.8)],
       chance=0.03, conditions=[year(4295)], once=True),

    # ------------------------------------------------------------ Fuarland
    ev("fua_council_of_winter", "FUA", "The Council of Winter",
       "The High Throne has called the lords of Fuarland to Fuar Hold. The talk is of the Llama highlands to the south-west: rich pasture, held by herders who have never seen a real army.",
       [opt("Fabricate our claims on the highlands.", [{"type": "add_claim", "tag": "LLA"}, op("LLA", -40), flag("fua_highland_claims")], 1.5),
        opt("Not yet. Build first.", [pw(0, 50)], 0.5)],
       chance=0.04, conditions=[year(4290), alive("LLA"), {"type": "not_at_war"}], once=True),
    ev("fua_long_winter", "FUA", "The Long Winter",
       "The snow has not melted in Lumvale since autumn. The granaries are emptying and the herds are thin.",
       [opt("Open the royal granaries.", [gold(-50)], 1.0),
        opt("The army eats first.", [stab(-1)], 0.7),
        opt("Send the young men south to forage.", [men(-1500), trad(5)], 0.7)],
       chance=0.02),
    ev("fua_stellarin_spies", "FUA", "Spies from Stellaris",
       "Guards at Fuar Hold have caught two Stellarins with a telescope and a very detailed map of our fortresses.",
       [opt("Hang them from the walls.", [op("STE", -30), stab(1)], 1.0),
        opt("Trade them back for their star charts.", [pw(0, 60), op("STE", 10)], 0.8)],
       chance=0.015, conditions=[alive("STE")]),
    ev("fua_hearthfire_rite", "FUA", "The Rite of the Hearthfires",
       "On the longest night every hall in Fuarland keeps its hearthfire burning for the warriors who have died. This year there are more fires than anyone can remember.",
       [opt("Honour the dead.", [trad(10), stab(1)], 1.0),
        opt("Honour the dead, and recruit the living.", [men(2000), stab(-1)], 0.8)],
       chance=0.015),
    ev("fua_highlands_won", "FUA", "The Highlands Are Ours",
       "The banners of the High Throne fly over Highpasture. What the old songs promised has come to pass: the Llama Nation bows to Fuarland.",
       [opt("Let the songs be sung again.", [mod("fua_highland_lords", "Lords of the Highlands", {"cavalry_power": 0.15, "manpower_mod": 0.10}, -1), stab(1)])],
       chance=0.2, conditions=[{"type": "subdued", "tag": "LLA"}], once=True),

    # ------------------------------------------------------------ Stellaris
    ev("ste_comet", "STE", "A Comet over Stellara",
       "A comet with a tail like a torn banner hangs over the observatory. The First Astronomer must say what it means, and the whole city is waiting.",
       [opt("It is a road: the stars are opening.", [stab(1), legit(5)], 1.0),
        opt("It is a warning: look to our defences.", [mod("ste_comet_warning", "The Comet's Warning", {"fort_defense": 0.15, "land_morale": 0.05}, 120)], 1.0),
        opt("It is a comet. Measure it.", [pw(0, 60)], 1.0)],
       chance=0.008),
    ev("ste_conclave_debate", "STE", "The Conclave Divided",
       "Half the conclave wants to build the greatest telescope ever made. The other half wants to fix the roads.",
       [opt("The telescope.", [pw(0, 40), gold(-40)], 1.0),
        opt("The roads.", [mod("ste_new_roads", "Roads of Stellaris", {"trade_efficiency": 0.05}, 120)], 1.0)],
       chance=0.02),
    ev("ste_northern_shadow", "STE", "The Northern Shadow",
       "Fuarland's levies are drilling in the snow, and its lords have been heard toasting the 'end of the star-gazers'.",
       [opt("Seek the friendship of SILK.", [op("SLK", 30), pw(1, 30)], 1.2),
        opt("Raise walls and watchtowers.", [gold(-50), mod("ste_watchtowers", "Watchtowers of Stellaris", {"fort_defense": 0.25}, 240)], 1.0),
        opt("Let them toast. The stars are on our side.", [stab(1)], 0.4)],
       chance=0.04, conditions=[year(4291), alive("FUA")], once=True),
    ev("ste_great_star_map", "STE", "The Great Star Map",
       "After forty years of nights, the observatory has finished its map of the heavens. Sailors, scholars and soothsayers are queueing at the door.",
       [opt("Print it for every captain.", [mod("ste_star_map", "The Great Star Map", {"explore_cost_mod": -0.33, "naval_morale": 0.05}, -1)], 1.2),
        opt("Keep it in the conclave's library.", [pw(0, 80)], 0.8)],
       chance=0.03, conditions=[{"type": "ideas_at_least", "at_least": 2}], once=True),
    ev("ste_eclipse", "STE", "Eclipse",
       "The sun has gone dark at noon. The astronomers predicted it to the minute, but the farmers are terrified all the same.",
       [opt("Explain it to them, slowly.", [pw(0, 30)], 1.0),
        opt("Let them believe we did it.", [legit(10), stab(1)], 1.0)],
       chance=0.01),

    # ------------------------------------------------------------ Llama Nation
    ev("lla_border_drums", "LLA", "Drums on the Northern Passes",
       "Herders coming down from the passes say the drums of Fuarland can be heard at night. The High Throne has never forgotten the old songs about our highlands.",
       [opt("Ask SILK for help.", [op("SLK", 30), pw(1, 25)], 1.2),
        opt("Fortify the passes.", [gold(-40), mod("lla_fortified_passes", "Fortified Passes", {"fort_defense": 0.25, "land_morale": 0.05}, 240)], 1.0),
        opt("Call up every herd.", [men(3000), stab(-1)], 0.8)],
       chance=0.04, conditions=[year(4291), alive("FUA")], once=True),
    ev("lla_spit_incident", "LLA", "The Lead Llama Spits",
       "During a state visit, the Lead Llama spat squarely in the face of a foreign envoy. Witnesses agree he had it coming. Diplomats do not.",
       [opt("Apologise, through gritted teeth.", [pw(1, -25)], 1.0),
        opt("Refuse. Llamas do not apologise.", [stab(1), op("FUA", -15)], 1.0)],
       chance=0.015),
    ev("lla_caravan_season", "LLA", "The Caravan Season",
       "The great caravans of the Yellow Road are gathering at Highpasture, and SILK's merchant houses want every llama we can spare.",
       [opt("Hire out the herds.", [gold(60), op("SLK", 10)], 1.0),
        opt("Keep the herds home this year.", [men(1500)], 0.6)],
       chance=0.025),
    ev("lla_stampede", "LLA", "Stampede!",
       "Something spooked the herds of Halkeld, and ten thousand llamas went over the fields at once. Nobody has found out what.",
       [opt("Replant the fields.", [gold(-30)], 1.0),
        opt("Turn it into cavalry drills.", [trad(10), dev("Halkeld", 0, -1)], 0.8)],
       chance=0.015),
    ev("lla_prophecy_broken", "LLA", "The Prophecy Broken",
       "Fuarland is no more a threat to the highlands. The old songs said it would swallow us. The old songs were wrong.",
       [opt("Write new songs.", [mod("lla_prophecy_broken", "The Prophecy Broken", {"land_morale": 0.10, "unrest": -1}, -1), stab(2)])],
       chance=0.2, conditions=[{"type": "subdued", "tag": "FUA"}], once=True),

    # ------------------------------------------------------------ SILK
    ev("slk_caravan_raided", "SLK", "A Caravan Raided",
       "Bandits fell on a silk caravan in the hills east of Fenvale. The drivers escaped; the silk did not.",
       [opt("Hire guards for every caravan.", [gold(-30), mod("slk_caravan_guards", "Caravan Guards", {"trade_efficiency": 0.05}, 60)], 1.0),
        opt("Write it off.", [gold(-15)], 1.0)],
       chance=0.025),
    ev("slk_yellow_road", "SLK", "Extending the Yellow Road",
       "The merchant houses propose paving the Yellow Road from Silkgate to the far coasts: the greatest road the continent has ever seen.",
       [opt("Pave it.", [gold(-120), mod("slk_paved_road", "The Paved Yellow Road", {"trade_efficiency": 0.10, "trade_power_mod": 0.10}, -1)], 1.2),
        opt("Too costly. Patch the potholes.", [gold(-20)], 0.8)],
       chance=0.03, conditions=[year(4295), {"type": "treasury_at_least", "at_least": 150}], once=True),
    ev("slk_merchant_houses", "SLK", "The Merchant Houses Quarrel",
       "The House of Ithmar and the House of Sarholm both claim the right to ship this year's dye harvest. Each has bribed half the council.",
       [opt("Ithmar: the old house.", [pw(0, 30), stab(-1)], 1.0),
        opt("Sarholm: the new money.", [gold(50), stab(-1)], 1.0),
        opt("Split the harvest between them.", [stab(1)], 1.0)],
       chance=0.02),
    ev("slk_fuar_tariff", "SLK", "Fuarland's Tariff",
       "Envoys from the High Throne demand a tariff on every caravan that crosses the northern passes. Their soldiers wait at the border while we decide.",
       [opt("Pay. Trade must flow.", [gold(-60), op("FUA", 25)], 1.0),
        opt("Refuse, and reroute the caravans.", [op("FUA", -30), mod("slk_rerouted", "Rerouted Caravans", {"trade_efficiency": -0.05}, 36)], 0.8)],
       chance=0.03, conditions=[year(4292), alive("FUA")], once=True),
    ev("slk_mainland_traders", "SLK", "Traders from Across the Sea",
       "A battered ship has limped into port carrying pigs from a land called Menslosia, with truffles and wine to trade. They have never heard of silk.",
       [opt("Show them what silk is.", [gold(60), op("MEN", 20)], 1.2),
        opt("Learn their language and their markets.", [pw(1, 50)], 1.0)],
       chance=0.03, conditions=[year(4296)], once=True),

    # ------------------------------------------------------------ the whole far world
    ev("far_ships_from_beyond", "farworld", "Ships from the Other Side of the World",
       "Sailors are telling stories in every port: of a great land beyond the edge of our maps, full of pigs, walled cities and sky islands hanging over a waterfall.",
       [opt("Fit out an expedition.", [gold(-40), pw(1, 50)], 1.2),
        opt("Sailors' stories.", [stab(1)], 0.6)],
       chance=0.03, conditions=[year(4294)], once=True),
    ev("far_starfall", "farworld", "Starfall",
       "A shower of falling stars lit the whole southern sky for three nights. Every faith of the far world has its own explanation, and each is sure of it.",
       [opt("A blessing.", [stab(1)], 1.0),
        opt("Gather the stones that fell.", [gold(40), pw(0, 20)], 1.0)],
       chance=0.006),
]


def main() -> None:
    data = json.loads(PATH.read_text(encoding="utf-8"))
    keep = [e for e in data["events"] if not (isinstance(e, dict) and e.get("_set") == TAG)]
    ids = {e["id"] for e in keep if isinstance(e, dict)}
    for e in EVENTS:
        assert e["id"] not in ids, "duplicate event id " + e["id"]
    data["events"] = keep + EVENTS
    if "'farworld'" not in data["_note"]:
        data["_note"] = data["_note"].replace("'others' (everyone but Menslosia and Skyfall)",
            "'others' (everyone but Menslosia and Skyfall), 'farworld' (the nations of the far world: Combustion Ayam, Terra Incognito, Oceania, the Satian Islands)")
    PATH.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print("%d far-world events written (%d events in all)" % (len(EVENTS), len(data["events"])))


if __name__ == "__main__":
    main()
