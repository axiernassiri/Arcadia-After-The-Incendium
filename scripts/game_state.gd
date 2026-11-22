extends Node
## Arcadia game state (autoload "Game").
## Owns the calendar, the data, nations and provinces, events and missions, the Doomsday cycle and
## saving. The systems live in scripts/sim/ and are reached through Game.eco, Game.trade, Game.prog,
## Game.mil, Game.dip, Game.pop, Game.court, Game.mods and Game.ai. No UI code here: the UI listens
## to the signals and calls the action functions, so the whole simulation also runs headless.

signal date_changed
signal month_ticked
signal province_changed(id: int)
signal nation_changed(tag: String)
signal event_fired(instance: Dictionary)
signal message_posted(text: String)
signal major_news(title: String, text: String)   # things worth pausing for (see post())
signal doomsday_changed(active: bool)
signal game_started
signal armies_changed
signal war_changed
signal battle_report(report: Dictionary)   # a land battle the player fought in has ended
signal eschaton_warning                     # a year before the end: the red eye of J82wC4

const START_YEAR := 4289
const MONTH_NAMES := ["January", "February", "March", "April", "May", "June", "July",
	"August", "September", "October", "November", "December"]
const DAYS_PER_SECOND := [0.0, 2.0, 6.0, 15.0, 40.0, 120.0]  # speed 0 = paused
const DEV_KINDS := ["tax", "production", "manpower"]
const TRACKS := ["adm", "dip", "mil"]
const POWER_CAP := 999
const EVENT_FREQ_NATION := 0.6      # share of a nation-specific event's written monthly odds
const EVENT_FREQ_SHARED := 0.4      # ... and of an event shared by many nations ("all", "tribes"...)
const EVENT_COOLDOWN_DAYS := 365 * 5
const SAVE_DIR := "user://saves"
const SAVE_VERSION := 3   # 3: the whole world (331 provinces, 16 nations)
const OLDEST_SAVE := 2     # older versions are migrated on load (see _merge_world)

const Modifiers = preload("res://scripts/sim/modifiers.gd")
const Economy = preload("res://scripts/sim/economy.gd")
const Trade = preload("res://scripts/sim/trade.gd")
const Progression = preload("res://scripts/sim/progression.gd")
const Court = preload("res://scripts/sim/court.gd")
const Population = preload("res://scripts/sim/population.gd")
const Military = preload("res://scripts/sim/military.gd")
const Diplomacy = preload("res://scripts/sim/diplomacy.gd")
const AI = preload("res://scripts/sim/ai.gd")
const Sea = preload("res://scripts/sim/sea.gd")
const Standing = preload("res://scripts/sim/standing.gd")

# calendar
var year := START_YEAR
var month := 1
var day := 1
var day_index := 0
var speed := 0
var started := false
var player_tag := ""
var doomsday_active := false
var doomsday_count := 0

# data (read from data/*.json)
var goods := {}
var terrain_data := {}
var peoples := {}
var governments := {}
var reform_cost_per_tier := 40
var tech_data := {}
var tech_base_cost := 600
var tech_ahead_cost := 0.1
var tech_ahead_debuff := {}
var tech_debuff_years := 10
var end_year := 4789
var advisor_data := {}
var estate_data := {}
var age_data := {}
var decision_data: Array = []
var idea_data := {}
var building_data := {}
var unit_data := {}
var events := {}
var missions: Array = []
var cutscene := {}
var nation_defs := {}
var unowned_colour := Color("#b9b29b")
var fog_colour := Color("#2b3138")
var map_meta := {}          # layer -> map json (trade seats etc.)

# world state
var nations := {}           # tag -> Dictionary
var provinces := {}         # id(int) -> Dictionary
var province_ids_by_name := {}
var node_provinces := {}    # trade node -> [province ids]
var armies := {}            # id -> army
var fleets := {}            # id -> fleet
var battles: Array = []
var wars := {}              # id -> war
var recruit_queue: Array = []
var next_id := 0
var global_flags := {}
var pending_events: Array = []   # player events waiting for a choice (pause the game)
var scheduled: Array = []        # [{due, id, tag}]
var fired_once := {}             # "event_id|tag" -> day it last fired (true in old saves)
var log_lines: Array = []
var world_lines: Array = []      # news that doesn't touch the player (the log's "World news" view)
var ledger_history := {}         # tag -> [[year, development, monthly income, regiments, provinces]] each 1 January

var rng := RandomNumberGenerator.new()
var _accum := 0.0
var _doomsday_damage: Array = []  # [{id, index, amount}] reverted when time reverses
var _owned_cache := {}

# systems
var mods: Modifiers
var eco: Economy
var trade: Trade
var prog: Progression
var court: Court
var pop: Population
var mil: Military
var dip: Diplomacy
var sea: Sea
var ai: AI
var standing: Standing   # prestige, the Great Power ranking, estates


func _init() -> void:
	mods = Modifiers.new(self)
	eco = Economy.new(self)
	trade = Trade.new(self)
	prog = Progression.new(self)
	court = Court.new(self)
	pop = Population.new(self)
	mil = Military.new(self)
	dip = Diplomacy.new(self)
	ai = AI.new(self)
	standing = Standing.new(self)


func _ready() -> void:
	load_data()


# ---------------------------------------------------------------- data

func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Missing data file: " + path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed == null:
		push_error("Invalid JSON in " + path)
		return {}
	return parsed


func load_data() -> void:
	nation_defs = _read_json("res://data/nations.json")
	unowned_colour = Color(nation_defs.get("unowned_colour", "#b9b29b"))
	fog_colour = Color(nation_defs.get("fog_colour", "#2b3138"))
	goods = _read_json("res://data/goods.json").get("goods", {})
	terrain_data = _read_json("res://data/terrain.json").get("terrain", {})
	peoples = _read_json("res://data/peoples.json")
	decision_data = _read_json("res://data/decisions.json").get("decisions", [])
	var gov: Dictionary = _read_json("res://data/governments.json")
	governments = gov.get("governments", {})
	reform_cost_per_tier = int(gov.get("cost_per_tier", 40))
	var tech: Dictionary = _read_json("res://data/technology.json")
	tech_data = tech.get("tracks", {})
	tech_base_cost = int(tech.get("base_cost", 600))
	tech_ahead_cost = float(tech.get("ahead_cost_per_year", 0.1))
	tech_ahead_debuff = tech.get("ahead_debuff", {})
	tech_debuff_years = int(tech.get("debuff_years", 10))
	end_year = int(tech.get("end_year", 4789))
	advisor_data = _read_json("res://data/advisors.json")
	estate_data = _read_json("res://data/estates.json")
	age_data = _read_json("res://data/ages.json")
	idea_data = _read_json("res://data/ideas.json")
	building_data = _read_json("res://data/buildings.json").get("buildings", {})
	unit_data = _read_json("res://data/units.json")
	trade.load_data(_read_json("res://data/trade.json"))
	cutscene = _read_json("res://data/cutscene.json")
	events.clear()
	for e in _read_json("res://data/events.json").get("events", []):
		events[e["id"]] = e
	missions = _read_json("res://data/missions.json").get("missions", [])

	var geo := {}
	map_meta.clear()
	for layer in ["ground", "sky"]:
		var m: Dictionary = _read_json("res://map/%s_map.json" % layer)
		map_meta[layer] = m
		for k in m.get("provinces", {}):
			geo[int(k)] = m["provinces"][k]

	provinces.clear()
	province_ids_by_name.clear()
	node_provinces.clear()
	for p in _read_json("res://data/provinces.json").get("provinces", []):
		var id := int(p["id"])
		var gm: Dictionary = geo.get(id, {})
		var dev: Array = []
		for v in p.get("development", [1, 1, 1]):
			dev.append(int(v))
		var conn := {}
		for n in gm.get("neighbours", []):
			conn[int(n)] = "land"
		for n in gm.get("lanes", []):
			conn[int(n)] = "sea" if p.get("layer", "ground") == "ground" else "air"
		for n in p.get("links", []):
			conn[int(n)] = "waterfall"
		for n in p.get("straits", []):
			conn[int(n)] = "strait"   # walkable when the enemy doesn't hold the sea (EU4 straits)
		var c: Array = gm.get("centre", [0, 0])
		var owner: String = p["owner"] if p.get("owner") != null else ""
		var cores := {}
		if owner != "":
			cores[owner] = true
		var flags: Array = p.get("flags", [])
		provinces[id] = {
			"id": id, "name": p["name"], "region": p.get("region", ""), "layer": p.get("layer", "ground"),
			"owner": owner, "controller": owner, "cores": cores,
			"terrain": p.get("terrain", "grassland"), "goods": p.get("goods", "grain"), "dev": dev,
			"flags": flags, "connections": conn, "coastal": "coastal" in flags,
			"centre": Vector2(float(c[0]), float(c[1])), "area": int(gm.get("area", 0)),
			"culture": p.get("culture", ""), "religion": p.get("religion", ""), "ethnicity": p.get("ethnicity", ""),
			"trade_node": p.get("trade_node", ""), "buildings": [], "construction": {}, "modifiers": [],
			"unrest": 0.0, "rebel_progress": 0.0, "siege": {}, "colony": {}, "conversion": {}, "autonomy": 0.0,
		}
		province_ids_by_name[p["name"]] = id
		var tn: String = p.get("trade_node", "")
		if not node_provinces.has(tn):
			node_provinces[tn] = []
		node_provinces[tn].append(id)
	_mainland.clear()
	if sea == null:
		sea = Sea.new(self)
	sea.build()

	nations.clear()
	var defs: Dictionary = nation_defs.get("nations", {})
	for tag in defs:
		nations[tag] = _make_nation(tag, defs[tag])
	_owned_cache.clear()
	mods.invalidate()


func _make_nation(tag: String, d: Dictionary) -> Dictionary:
	var flags := {}
	for f in d.get("flags", []):
		flags[f] = true
	var tech: Array = []
	for v in d.get("tech", [1, 1, 1]):
		tech.append(int(v))
	var ruler: Dictionary = d.get("ruler", {}).duplicate()
	for k in ["adm", "dip", "mil", "age"]:
		if ruler.has(k):
			ruler[k] = int(ruler[k])
	var heir: Dictionary = d.get("heir", {}).duplicate()
	for k in ["adm", "dip", "mil", "age"]:
		if heir.has(k):
			heir[k] = int(heir[k])
	return {
		"tag": tag, "name": d["name"], "short": d.get("short", d["name"]),
		"adjective": d.get("adjective", d["name"]), "colour": Color(d.get("colour", "#888888")),
		"government": d.get("government", "boar_tribe"), "reforms": [], "reform_progress": 20.0,
		"ideas": d.get("ideas", "TRIBE"), "idea_groups": [],
		"culture": d.get("culture", ""), "accepted_cultures": d.get("accepted_cultures", []).duplicate(),
		"religion": d.get("religion", ""), "ethnicity": d.get("ethnicity", ""),
		"ruler": ruler, "heir": heir, "ruler_names": d.get("ruler_names", []),
		"power": [50, 50, 50], "power_names": d.get("power_names", ["Admin", "Diplo", "Military"]),
		"treasury": float(d.get("treasury", 100)), "manpower": int(d.get("manpower", 10000)), "max_manpower": 0,
		"stability": 0, "war_exhaustion": 0.0, "army_tradition": 10.0,
		"tech": tech, "flags": flags, "relations": {}, "claims": {}, "subjects": [], "overlord": "",
		"explored": {}, "missions_done": {}, "ai": true, "alive": true, "blurb": d.get("blurb", ""),
		"known_layers": d.get("known_layers", []), "known_extra": d.get("known_extra", []),
		"modifiers": [], "loans": [], "maintenance": {"land": 1.0, "naval": 1.0}, "merchants": {},
		"leaders": [], "capital_name": d.get("capital", ""), "capital_id": -1,
		"playable": d.get("playable", true), "difficulty": d.get("difficulty", ""),
		"last_income": 0.0, "last_balance": 0.0, "battles_won": 0,
		"legitimacy": float(d.get("legitimacy", 70)), "advisors": {"adm": {}, "dip": {}, "mil": {}}, "elected_day": 0,
		"known_regions": d.get("known_regions", []),
	}


func setup_world(seed_value: int = 4289) -> void:
	## A fresh world from the data files, with no player yet (used by the nation picker too).
	load_data()
	rng.seed = seed_value
	year = START_YEAR
	month = 1
	day = 1
	day_index = 0
	speed = 0
	doomsday_active = false
	doomsday_count = 0
	armies.clear()
	fleets.clear()
	battles.clear()
	wars.clear()
	recruit_queue.clear()
	next_id = 0
	global_flags.clear()
	pending_events.clear()
	scheduled.clear()
	fired_once.clear()
	log_lines.clear()
	world_lines.clear()
	ledger_history.clear()
	_doomsday_damage.clear()
	player_tag = ""
	var defs: Dictionary = nation_defs.get("nations", {})
	for tag in nations:
		var n: Dictionary = nations[tag]
		var d: Dictionary = defs[tag]
		n["capital_id"] = int(province_ids_by_name.get(n["capital_name"], -1))
		if n["capital_id"] < 0 or provinces[n["capital_id"]]["owner"] != tag:
			n["capital_id"] = _biggest_province(tag)
		if n["capital_id"] < 0:
			n["alive"] = false
			continue
		var cap: Dictionary = provinces[n["capital_id"]]
		if not "capital" in cap["flags"]:
			cap["flags"].append("capital")
		for rkey in d.get("relations", {}):
			var rd: Dictionary = d["relations"][rkey]
			if nations.has(rkey):
				dip.rel(tag, rkey)["opinion"] = float(rd.get("opinion", 0))
				if rd.get("alliance", false):
					dip.set_both(tag, rkey, "alliance", true)
				if rd.get("rival", false):
					dip.rel(tag, rkey)["rival"] = true
				if int(rd.get("truce_years", 0)) > 0:
					dip.set_both(tag, rkey, "truce_until", day_index + 365 * int(rd["truce_years"]))
		for pid in provinces:
			if provinces[pid]["culture"] in d.get("claims_cultures", []) and provinces[pid]["owner"] != tag and provinces[pid]["owner"] != "":
				n["claims"][pid] = true
		for key in ["army", "army2"]:
			if d.has(key):
				var ad: Dictionary = d[key]
				var loc := int(province_ids_by_name.get(ad.get("location", ""), -1))
				if loc < 0 or provinces[loc]["owner"] != tag:
					loc = n["capital_id"]
				mil.spawn_army(tag, loc, int(ad.get("inf", 0)), int(ad.get("cav", 0)), int(ad.get("art", 0)))
		if d.has("fleet"):
			var fd: Dictionary = d["fleet"]
			var floc := int(province_ids_by_name.get(fd.get("location", ""), -1))
			if floc < 0 or not provinces[floc]["coastal"] or provinces[floc]["owner"] != tag:
				floc = _nearest_coastal(tag, n["capital_id"])
			if floc >= 0:
				var counts := {}
				for k in ["heavy", "light", "transport"]:
					if fd.has(k):
						counts[k] = int(fd[k])
				mil.spawn_fleet(tag, floc, counts)
		for pid in provinces:
			var p: Dictionary = provinces[pid]
			var visible_land: bool = not ("hidden" in p["flags"])
			var known: bool = (p["layer"] in n["known_layers"] and visible_land) \
				or (p["region"] in n["known_regions"] and visible_land) \
				or p["name"] in n["known_extra"] or p["owner"] == tag
			if known:
				n["explored"][pid] = true
		for pid in owned(tag):
			for nb in provinces[pid]["connections"]:
				if not "hidden" in provinces[nb]["flags"]:
					n["explored"][nb] = true
		n["max_manpower"] = eco.max_manpower(tag)
		n["elected_day"] = -rng.randi_range(0, 3 * 365)
		court.refill_pool(tag)
		for pid in owned(tag):
			provinces[pid]["autonomy"] = 0.0 if pid == n["capital_id"] else float(rng.randi_range(0, 3) * 5)
		_place_forts(tag)
	# Menslosia's mainland forts: the capital has one; give Unity its walls
	dip.rebuild_pairs()
	mods.invalidate()
	eco.reset()
	trade.monthly()
	for tag in nations:
		if nations[tag]["alive"]:
			pop.monthly()
			break


func _place_forts(tag: String) -> void:
	## Forts scattered across every realm: the capital, then the richest provinces at least two steps
	## from another fort, about one fort for every six provinces.
	var mine: Array = owned(tag).duplicate()
	mine.sort_custom(func(a, b): return total_dev(a) > total_dev(b))
	var want: int = maxi(1, int(mine.size() / 6.0 + 0.5))
	var forts: Array = []
	var cap := capital_of(tag)
	if cap >= 0:
		forts.append(cap)
	for pid in mine:
		if forts.size() >= want:
			break
		if pid in forts:
			continue
		var near := false
		for f in forts:
			if provinces[f]["connections"].has(pid):
				near = true
			for nb in provinces[f]["connections"]:
				if provinces[nb]["connections"].has(pid):
					near = true
		if not near:
			forts.append(pid)
	for f in forts:
		if not provinces[f]["buildings"].has("fort"):
			provinces[f]["buildings"].append("fort")


func _biggest_province(tag: String) -> int:
	var best := -1
	for pid in provinces:
		if provinces[pid]["owner"] == tag and (best < 0 or total_dev(pid) > total_dev(best)):
			best = pid
	return best


func _nearest_coastal(tag: String, from: int) -> int:
	var best := -1
	var bd := INF
	for pid in owned(tag):
		if provinces[pid]["coastal"]:
			var d: float = (provinces[pid]["centre"] as Vector2).distance_to(provinces[from]["centre"])
			if d < bd:
				bd = d
				best = pid
	return best


func new_game(tag: String, seed_value: int = 4289) -> void:
	setup_world(seed_value)
	player_tag = tag
	for t in nations:
		nations[t]["ai"] = (t != tag)
	started = true
	post("%s, %s. The Arcadian Era begins." % [date_string(), nations[tag]["short"] if nations.has(tag) else "Observer"])
	record_ledger()
	game_started.emit()
	date_changed.emit()


# ---------------------------------------------------------------- ownership helpers

func owned(tag: String) -> Array:
	if not _owned_cache.has(tag):
		var out: Array = []
		for id in provinces:
			if provinces[id]["owner"] == tag:
				out.append(id)
		_owned_cache[tag] = out
	return _owned_cache[tag]


func owned_provinces(tag: String) -> Array:
	return owned(tag)


func set_province_owner(pid: int, tag: String) -> void:
	var p: Dictionary = provinces[pid]
	var old: String = p["owner"]
	p["owner"] = tag
	p["controller"] = tag
	p["siege"] = {}
	p["construction"] = {}
	p["conversion"] = {}
	p["colony"] = {}
	p["coring"] = {}
	_owned_cache.clear()
	if old != "" and nations.has(old):
		if nations[old]["capital_id"] == pid:
			nations[old]["capital_id"] = _biggest_province(old)
		if owned(old).is_empty():
			kill_nation(old)
		mods.invalidate(old)
	if tag != "" and nations.has(tag):
		nations[tag]["explored"][pid] = true
		mods.invalidate(tag)
	province_changed.emit(pid)


func kill_nation(tag: String) -> void:
	var n: Dictionary = nations[tag]
	if not n["alive"]:
		return
	n["alive"] = false
	for a in mil.armies_of(tag):
		armies.erase(a["id"])
	for f in mil.fleets_of(tag):
		fleets.erase(f["id"])
	dip.end_war_with(tag)
	for other in nations:
		if nations[other]["relations"].has(tag):
			nations[other]["relations"][tag]["alliance"] = false
			nations[other]["relations"][tag]["improving"] = false
		nations[other]["subjects"].erase(tag)
	n["subjects"].clear()
	n["overlord"] = ""
	post("%s is no more." % n["name"], [tag], "", true)
	if tag == player_tag:
		fire_dynamic_event({"id": "game_over", "title": "The End of %s" % n["name"],
			"text": "Our last province has fallen. You can keep watching the world, or load a save from the menu.",
			"options": [{"text": "So it ends.", "effects": []}]}, tag)
	armies_changed.emit()


func revive_nation(tag: String) -> void:
	var d: Dictionary = nation_defs["nations"].get(tag, {})
	var keep_explored: Dictionary = nations[tag]["explored"]
	nations[tag] = _make_nation(tag, d)
	nations[tag]["explored"] = keep_explored
	nations[tag]["ai"] = tag != player_tag


func capital_of(tag: String) -> int:
	if not nations.has(tag):
		return -1
	var c: int = int(nations[tag]["capital_id"])
	if c >= 0 and provinces[c]["owner"] == tag:
		return c
	c = _biggest_province(tag)
	nations[tag]["capital_id"] = c
	return c


func total_dev(id: int) -> int:
	var d: Array = provinces[id]["dev"]
	return int(d[0]) + int(d[1]) + int(d[2])


func nation_dev(tag: String) -> int:
	var t := 0
	for pid in owned(tag):
		t += total_dev(pid)
	return t


# ---------------------------------------------------------------- decisions

func decision(id: String) -> Dictionary:
	for d in decision_data:
		if d["id"] == id:
			return d
	return {}


func decisions_for(tag: String) -> Array:
	## Decisions this nation can see (their 'potential' conditions hold).
	var out: Array = []
	if not nations.has(tag):
		return out
	for d in decision_data:
		var ok = true
		for c in d.get("potential", []):
			if not check_condition(c, tag):
				ok = false
				break
		if ok:
			out.append(d)
	return out


func decision_cost_text(tag: String, d: Dictionary) -> String:
	var parts: PackedStringArray = []
	var pw: Array = d.get("cost", {}).get("power", [0, 0, 0])
	for i in 3:
		if int(pw[i]) > 0:
			parts.append("%d %s" % [int(pw[i]), nations[tag]["power_names"][i]])
	if int(d.get("cost", {}).get("treasury", 0)) > 0:
		parts.append("%d sanctum" % int(d["cost"]["treasury"]))
	return ", ".join(parts)


func can_take_decision(tag: String, id: String) -> String:
	var d: Dictionary = decision(id)
	if d.is_empty() or not decisions_for(tag).has(d):
		return "Not available."
	for c in d.get("allow", []):
		if not check_condition(c, tag):
			return "Needs: %s." % describe_condition(c)
	var n: Dictionary = nations[tag]
	var pw: Array = d.get("cost", {}).get("power", [0, 0, 0])
	for i in 3:
		if int(n["power"][i]) < int(pw[i]):
			return "Needs %d %s power." % [int(pw[i]), n["power_names"][i]]
	if float(n["treasury"]) < float(d.get("cost", {}).get("treasury", 0)):
		return "Needs %d sanctum." % int(d["cost"]["treasury"])
	return ""


func take_decision(tag: String, id: String) -> bool:
	if can_take_decision(tag, id) != "":
		return false
	var d: Dictionary = decision(id)
	var n: Dictionary = nations[tag]
	var pw: Array = d.get("cost", {}).get("power", [0, 0, 0])
	for i in 3:
		n["power"][i] = int(n["power"][i]) - int(pw[i])
	n["treasury"] = float(n["treasury"]) - float(d.get("cost", {}).get("treasury", 0))
	apply_effects(d.get("effects", []), tag)
	if tag == player_tag:
		post("Decision taken: %s." % d["name"])
	touch(tag)
	nation_changed.emit(tag)
	return true


var _mainland := {}


func is_mainland(pid: int) -> bool:
	## The Arcadian continent: every province joined by land to Mentos. Offshore islands
	## (the archipelagos, Equator Isle) and Skyfall are not part of it.
	if _mainland.is_empty():
		var start := int(province_ids_by_name.get("Mentos", -1))
		if start < 0:
			return false
		_mainland[start] = true
		var todo: Array = [start]
		while not todo.is_empty():
			var c: int = todo.pop_back()
			for nb in provinces[c]["connections"]:
				if provinces[c]["connections"][nb] == "land" and not _mainland.has(nb):
					_mainland[nb] = true
					todo.append(nb)
	return _mainland.has(pid)


func owns_mainland(tag: String) -> bool:
	for pid in owned(tag):
		if is_mainland(pid):
			return true
	return false


func owner_colour(tag: String) -> Color:
	## Colour for any owner of armies or land, including rebels and the entities (which are not nations).
	match tag:
		"REB":
			return Color(0.2, 0.2, 0.22)
		"ENT":
			return Color(0.42, 0.12, 0.7)
	return nations[tag]["colour"] if nations.has(tag) else Color(0.4, 0.4, 0.4)


func nation_name(tag: String) -> String:
	if tag == "REB":
		return "Rebels"
	if tag == "ENT":
		return "Entities"
	return nations[tag]["short"] if nations.has(tag) else tag


func touch(tag: String) -> void:
	mods.invalidate(tag)
	nation_changed.emit(tag)


func is_connected_to_owned(tag: String, id: int) -> bool:
	for n in provinces[id]["connections"]:
		if provinces.has(n) and provinces[n]["owner"] == tag:
			return true
	return false


func is_connected_to_explored(tag: String, id: int) -> bool:
	for n in provinces[id]["connections"]:
		if nations[tag]["explored"].has(n):
			return true
	return false


func add_nation_modifier(tag: String, id: String, name: String, m: Dictionary, months: int = -1) -> void:
	var n: Dictionary = nations[tag]
	n["modifiers"] = n["modifiers"].filter(func(x): return x.get("id", "") != id)
	n["modifiers"].append({"id": id, "name": name, "mods": m, "until": day_index + months * 30 if months > 0 else -1})
	touch(tag)


func add_province_modifier(pid: int, id: String, name: String, m: Dictionary, months: int = -1) -> void:
	var p: Dictionary = provinces[pid]
	p["modifiers"] = p["modifiers"].filter(func(x): return x.get("id", "") != id)
	p["modifiers"].append({"id": id, "name": name, "mods": m, "until": day_index + months * 30 if months > 0 else -1})
	province_changed.emit(pid)


# ---------------------------------------------------------------- calendar

static func is_leap(y: int) -> bool:
	return (y % 4 == 0 and y % 100 != 0) or y % 400 == 0


static func days_in_month(y: int, m: int) -> int:
	if m == 2:
		return 29 if is_leap(y) else 28
	return 30 if m in [4, 6, 9, 11] else 31


func date_string() -> String:
	return "%d %s %d" % [day, MONTH_NAMES[month - 1], year]


func date_key() -> String:
	return "%04d-%02d-%02d" % [year, month, day]


func date_from_index(idx: int) -> String:
	## Approximate calendar date for a future day index (used for truces).
	var y := year
	var m := month
	var d := day
	var left := idx - day_index
	while left > 0:
		var dim := days_in_month(y, m)
		if d + left <= dim:
			d += left
			left = 0
		else:
			left -= dim - d + 1
			d = 1
			m += 1
			if m > 12:
				m = 1
				y += 1
	return "%d %s %d" % [d, MONTH_NAMES[m - 1], y]


func is_blocked() -> bool:
	return not pending_events.is_empty()


func set_speed(s: int) -> void:
	speed = clampi(s, 0, 5)


func _process(delta: float) -> void:
	if not started or speed == 0 or is_blocked():
		return
	_accum += delta * DAYS_PER_SECOND[speed]
	var steps := 0
	while _accum >= 1.0 and steps < 10 and not is_blocked():
		_accum -= 1.0
		advance_day()
		steps += 1
	if is_blocked():
		_accum = 0.0


func advance_day() -> void:
	if doomsday_active:
		end_doomsday()
	day += 1
	day_index += 1
	if day > days_in_month(year, month):
		day = 1
		month += 1
		if month > 12:
			month = 1
			year += 1
		monthly_tick()
	mil.daily()
	eco.daily_construction()
	if day_index % 5 == 0:
		ai.armies_tick()
	if month == 2 and day == 29:
		start_doomsday()
	_run_scheduled()
	_check_date_events()
	date_changed.emit()


func monthly_tick() -> void:
	mods.invalidate()
	for tag in nations:
		nations[tag]["modifiers"] = mods.expire(nations[tag]["modifiers"])
	for pid in provinces:
		if not provinces[pid]["modifiers"].is_empty():
			provinces[pid]["modifiers"] = mods.expire(provinces[pid]["modifiers"])
	mods.invalidate()
	trade.monthly()
	for tag in nations:
		var n: Dictionary = nations[tag]
		if not n["alive"]:
			continue
		eco.monthly(tag)
		var gain := court.power_gain(tag)
		for i in 3:
			n["power"][i] = mini(int(n["power"][i]) + int(gain[i]), POWER_CAP)
		prog.monthly(tag)
		court.monthly(tag)
	pop.monthly()
	eco.monthly_autonomy()
	pop.monthly_cores()
	mil.monthly()
	dip.monthly()
	standing.monthly()
	eco.monthly_colonies()
	eco.update_prices()
	for tag in nations:
		if nations[tag]["alive"] and nations[tag]["ai"]:
			ai.monthly(tag)
	_check_monthly_events()
	_entity_pressure()
	# a year before the end, the watchers on J82wC4 send their warning (the UI flashes the red eye)
	if year == end_year - 1 and not global_flags.has("eschaton_warned"):
		global_flags["eschaton_warned"] = true
		post("Something vast opens its eye beyond the edge of the world. The stars are going out, one by one.")
		eschaton_warning.emit()
	if year >= end_year and not global_flags.has("game_over"):
		global_flags["game_over"] = true
		speed = 0
		if player_tag != "":
			fire_dynamic_event({"id": "end_of_era", "title": "The Eschaton",
				"text": "It is %d, five hundred years after the Incendium. Dark energy pulls every atom away from every other: the universe has lived through all its years and gives itself back to the Void. Whatever %s built is recycled into what comes next. Somewhere, the nation on J82wC4 already escaped." % [year, nation_name(player_tag)],
				"options": [{"text": "Keep playing in the last light.", "effects": []}]}, player_tag)
	mods.invalidate()
	if month == 1:
		record_ledger()
	month_ticked.emit()
	for tag in nations:
		nation_changed.emit(tag)


func power_gain(tag: String) -> Array:
	return court.power_gain(tag)


# ---------------------------------------------------------------- exploration

func explore_cost(tag: String, id: int) -> int:
	var base := 70.0 if "hidden" in provinces[id]["flags"] else 40.0
	return maxi(5, int(round(base * maxf(0.2, 1.0 + mods.nat(tag, "explore_cost_mod")))))


func can_explore(tag: String, id: int) -> String:
	var n: Dictionary = nations[tag]
	if n["explored"].has(id):
		return "Already explored."
	if not is_connected_to_explored(tag, id):
		return "Must border a province you have explored."
	var c := explore_cost(tag, id)
	if n["power"][1] < c:
		return "Needs %d %s power." % [c, n["power_names"][1]]
	return ""


func explore(tag: String, id: int) -> bool:
	if can_explore(tag, id) != "":
		return false
	var n: Dictionary = nations[tag]
	n["power"][1] -= explore_cost(tag, id)
	n["explored"][id] = true
	var p: Dictionary = provinces[id]
	if tag != "SKY" and p["layer"] == "sky" and nations.has("SKY"):
		dip.add_opinion("SKY", tag, -5.0, "Mapped our islands", 0.25)  # Skyfall forbids mapping and cameras
	if tag == player_tag:
		post("Explorers have mapped %s." % p["name"])
	province_changed.emit(id)
	touch(tag)
	return true


# kept for older callers
func develop_cost(id: int) -> int:
	return eco.develop_cost(provinces[id]["owner"] if provinces[id]["owner"] != "" else player_tag, id)


func can_develop(tag: String, id: int, kind: int) -> String:
	return eco.can_develop(tag, id, kind)


func develop(tag: String, id: int, kind: int) -> bool:
	return eco.develop(tag, id, kind)


func colonize_cost(_tag: String, _id: int) -> Array:
	return [int(eco.COLONY_COST), 0]


func can_colonize(tag: String, id: int) -> String:
	return eco.can_colonize(tag, id)


func colonize(tag: String, id: int) -> bool:
	return eco.colonize(tag, id)


func add_opinion(of_tag: String, toward: String, amount: int) -> void:
	dip.add_opinion(of_tag, toward, float(amount), "Events", 0.5)


# ---------------------------------------------------------------- doomsday

func portal_id() -> int:
	for id in provinces:
		if "doomsday_portal" in provinces[id]["flags"]:
			return id
	return -1


func in_skyfall(tag: String) -> bool:
	## The Black Moon only touches nations with land or armies in Skyfall.
	for pid in owned(tag):
		if provinces[pid]["layer"] == "sky":
			return true
	for a in mil.armies_of(tag):
		if provinces[int(a["location"])]["layer"] == "sky":
			return true
	return false


func start_doomsday() -> void:
	doomsday_active = true
	doomsday_count += 1
	_doomsday_damage.clear()
	var hit := {}
	var portal := portal_id()
	if portal >= 0:
		hit[portal] = true
		for n in provinces[portal]["connections"]:
			if provinces[n]["layer"] == "sky":
				hit[n] = true
	var affected: Array = []
	for tag in nations:
		if nations[tag]["alive"] and in_skyfall(tag):
			affected.append(tag)
			var theirs: Array = []
			for pid in owned(tag):
				if provinces[pid]["layer"] == "sky":
					theirs.append(pid)
			for i in 3:
				if theirs.size() > 0:
					hit[theirs[rng.randi_range(0, theirs.size() - 1)]] = true
	for id in hit:
		var owner: String = provinces[id]["owner"]
		var resist := mods.nat(owner, "doomsday_resistance") if owner != "" else 0.0
		for k in 3:
			if provinces[id]["dev"][k] > 1 and rng.randf() >= clampf(resist, 0.0, 0.9):
				provinces[id]["dev"][k] -= 1
				_doomsday_damage.append({"id": id, "index": k, "amount": 1})
		province_changed.emit(id)
	post("29 February %d: THE BLACK MOON RISES. The Doomsday Barrier has fallen." % year)
	# sometimes something comes through, and time reversing does not send it back
	var chance := minf(0.7, 0.3 + 0.05 * doomsday_count + (0.1 if nations.has("BLM") and nations["BLM"]["alive"] else 0.0))
	if portal >= 0 and rng.randf() < chance:
		var regs := mini(18, 6 + doomsday_count)
		mil.spawn_entities(portal, regs)
		global_flags["entities_came"] = true
		post("ENTITIES POUR THROUGH THE PORTAL: %d regiments of things from beyond are loose in Skyfall!" % regs)
		for tag in affected:
			fire_event("entity_invasion", tag)
	if player_tag != "" and not (player_tag in affected):
		post("The anomalies stay in Skyfall. %s has no one there, so the Black Moon passes us by." % nation_name(player_tag))
	doomsday_changed.emit(true)
	for tag in affected:
		for eid in events:
			var e: Dictionary = events[eid]
			if e.get("trigger", {}).get("special", "") == "doomsday" and _event_applies(e, tag) \
					and check_conditions(e.get("trigger", {}).get("conditions", []), tag):
				fire_event(eid, tag)


func _entity_pressure() -> void:
	## While entities hold the Doomsday Portal, the sky islands around it suffer.
	var portal := portal_id()
	if portal < 0 or provinces[portal]["controller"] != "ENT":
		return
	for nb in provinces[portal]["connections"]:
		if provinces[nb]["owner"] != "" and provinces[nb]["owner"] != "BLM":
			add_province_modifier(nb, "entity_incursion", "Entity incursion", {"local_unrest": 3, "local_production_mod": -0.5}, 3)
	if rng.randf() < 0.15:
		mil.spawn_entities(portal, 2 + rng.randi_range(0, 2))
		post("More entities crawl out of the occupied portal.")


func end_doomsday() -> void:
	doomsday_active = false
	for d in _doomsday_damage:
		provinces[d["id"]]["dev"][d["index"]] += d["amount"]
		province_changed.emit(d["id"])
	_doomsday_damage.clear()
	for tag in nations:
		if in_skyfall(tag):
			nations[tag]["flags"]["survived_doomsday"] = true
	post("Time reverses. The anomalies' damage is undone, but every choice is remembered.")
	doomsday_changed.emit(false)


# ---------------------------------------------------------------- events

func _event_applies(e: Dictionary, tag: String) -> bool:
	if not nations.has(tag) or not nations[tag]["alive"]:
		return false
	var f: String = e.get("for", "all")
	if f == "all":
		return true
	var gt: String = court.gov_type(tag)
	if f == "tribes":
		return gt == "tribe" or gt == "horde"
	if f == "republics":
		return gt == "republic"
	if f == "monarchies":
		return gt == "monarchy"
	if f == "pig_states":
		return tag != "MEN" and pop.culture_group(nations[tag]["culture"]) == "Porcine"
	if f == "others":
		return tag != "MEN" and tag != "SKY"
	if f == "player":
		return tag == player_tag
	return f == tag


func _check_date_events() -> void:
	var key := date_key()
	for eid in events:
		var e: Dictionary = events[eid]
		if e.get("trigger", {}).get("date", "") == key:
			for tag in nations:
				if e.get("once", false) and fired_once.has(eid + "|" + tag):
					continue
				if _event_applies(e, tag) and check_conditions(e.get("trigger", {}).get("conditions", []), tag):
					fire_event(eid, tag)


func in_year_window(trig: Dictionary) -> bool:
	## "years": [from, to] limits an event to those years (inclusive). Either end can be 0 for open.
	if not trig.has("years"):
		return true
	var yw: Array = trig["years"]
	return (int(yw[0]) <= 0 or year >= int(yw[0])) and (int(yw[1]) <= 0 or year <= int(yw[1]))


func event_mtth(e: Dictionary, tag: String) -> float:
	## Mean time to happen in months (EU4): the base, multiplied by every modifier whose conditions hold.
	var trig: Dictionary = e.get("trigger", {})
	var m := float(trig.get("mtth_months", 0.0))
	for mm in trig.get("mtth_modifiers", []):
		if check_conditions(mm.get("conditions", []), tag):
			m *= float(mm.get("factor", 1.0))
	return maxf(m, 0.5)


func event_monthly_chance(e: Dictionary, tag: String) -> float:
	## The chance a random event fires this month. Scaled down so events stay special: events written
	## for one nation keep EVENT_FREQ_NATION of their written odds, shared ones ("all", "tribes",
	## "republics"...) only EVENT_FREQ_SHARED.
	var trig: Dictionary = e.get("trigger", {})
	var base := 0.0
	if trig.has("monthly_chance"):
		base = float(trig["monthly_chance"])
	elif trig.has("mtth_months"):
		base = 1.0 - exp(-1.0 / event_mtth(e, tag))
	var nation_specific: bool = nations.has(String(e.get("for", "all")))
	return base * (EVENT_FREQ_NATION if nation_specific else EVENT_FREQ_SHARED)


func event_on_cooldown(eid: String, tag: String) -> bool:
	## A repeatable event can't come back for the same nation within EVENT_COOLDOWN_DAYS.
	## (fired_once keeps the day each event last fired; old saves stored `true` there.)
	var last: Variant = fired_once.get(eid + "|" + tag, null)
	return (last is int or last is float) and day_index - int(last) < EVENT_COOLDOWN_DAYS


func _check_monthly_events() -> void:
	for eid in events:
		var e: Dictionary = events[eid]
		var trig: Dictionary = e.get("trigger", {})
		if not trig.has("monthly_chance") and not trig.has("mtth_months"):
			continue
		if not in_year_window(trig):
			continue
		for tag in nations:
			if not _event_applies(e, tag):
				continue
			if e.get("once", false) and fired_once.has(eid + "|" + tag):
				continue
			if event_on_cooldown(eid, tag):
				continue
			if not check_conditions(trig.get("conditions", []), tag):
				continue
			if rng.randf() < event_monthly_chance(e, tag):
				fire_event(eid, tag)


func _run_scheduled() -> void:
	var still: Array = []
	for s in scheduled:
		if s["due"] <= day_index:
			fire_event(s["id"], s["tag"])
		else:
			still.append(s)
	scheduled = still


func fire_event(eid: String, tag: String) -> void:
	if not events.has(eid) or not nations.has(tag) or not nations[tag]["alive"]:
		return
	fired_once[eid + "|" + tag] = day_index   # when it last fired: "once" events and the cooldown use this
	_fire(events[eid], tag)


func fire_dynamic_event(e: Dictionary, tag: String) -> void:
	## An event built in code (peace offers, calls to arms).
	if not nations.has(tag):
		return
	_fire(e, tag)


func _fire(e: Dictionary, tag: String) -> void:
	var inst := {"event": e, "tag": tag, "date": date_string()}
	if nations[tag]["ai"]:
		resolve_event(inst, _ai_pick_option(e))
	else:
		pending_events.append(inst)
		event_fired.emit(inst)


func _ai_pick_option(e: Dictionary) -> int:
	var best := 0
	var best_w := -1.0
	var opts: Array = e.get("options", [])
	for i in opts.size():
		var w := float(opts[i].get("ai_weight", 1.0)) * rng.randf_range(0.5, 1.5)
		if w > best_w:
			best_w = w
			best = i
	return best


func resolve_event(inst: Dictionary, option_index: int) -> void:
	var opts: Array = inst["event"].get("options", [])
	pending_events.erase(inst)
	if option_index >= 0 and option_index < opts.size():
		apply_effects(opts[option_index].get("effects", []), inst["tag"])
	touch(inst["tag"])


func describe_effects(effects: Array, tag: String) -> String:
	var parts: PackedStringArray = []
	var n: Dictionary = nations.get(tag, {})
	for e in effects:
		var amt := int(e.get("amount", 0))
		var sgn := "+" if amt >= 0 else ""
		match e.get("type", ""):
			"add_power":
				parts.append("%s%d %s" % [sgn, amt, n.get("power_names", ["", "", ""])[int(e.get("index", 0))]])
			"add_treasury":
				parts.append("%s%d sanctum" % [sgn, amt])
			"add_stability":
				parts.append("%s%d stability" % [sgn, amt])
			"add_manpower":
				parts.append("%s%d manpower" % [sgn, amt])
			"add_opinion":
				var t: String = e.get("target", "")
				parts.append("%s%d opinion with %s" % [sgn, amt, nation_name(t)])
			"add_dev":
				parts.append("%s%d %s development in %s" % [sgn, amt, DEV_KINDS[int(e.get("index", 0))], e.get("province", "")])
			"reveal":
				parts.append("reveals %s" % e.get("province", ""))
			"add_modifier":
				var months := int(e.get("months", -1))
				parts.append("%s: %s%s" % [e.get("name", "Modifier"), mods.describe(e.get("modifiers", {}), n.get("power_names", [])),
					" for %d years" % int(months / 12) if months >= 12 else (" for %d months" % months if months > 0 else "")])
			"add_war_exhaustion":
				parts.append("%+d war exhaustion" % amt)
			"add_army_tradition":
				parts.append("%+d army tradition" % amt)
			"add_reform_progress":
				parts.append("%+d reform progress" % amt)
			"add_legitimacy":
				parts.append("%+d %s" % [amt, court.legitimacy_name(tag).to_lower() if nations.has(tag) else "legitimacy"])
			"add_autonomy":
				parts.append("%+d autonomy in every province" % amt)
			"spawn_entities":
				parts.append("%d regiments of entities appear at the portal" % amt)
			"declare_war":
				parts.append("declares war on %s" % nation_name(e.get("target", "")))
			"add_claim":
				parts.append("claims on all of %s" % nation_name(e["tag"]) if e.has("tag") else "claim on %s" % e.get("province", ""))
			"spawn_leader":
				parts.append("a new general")
			"set_flag", "clear_flag", "fire_event", "message", "join_war", "refuse_call", "accept_peace":
				pass
			"add_core":
				parts.append("core on %s" % e.get("province", ""))
			"price_shock":
				parts.append("%s prices x%.1f" % [goods.get(e.get("goods", ""), {}).get("name", e.get("goods", "")), float(e.get("factor", 1.0))])
	return ", ".join(parts)


func apply_effects(effects: Array, tag: String) -> void:
	for e in effects:
		var target: String = e.get("target", "THIS")
		var t: String = tag if target == "THIS" else target
		var n: Dictionary = nations.get(tag, {})
		var amt := int(e.get("amount", 0))
		match e.get("type", ""):
			"add_power":
				var i := int(e.get("index", 0))
				n["power"][i] = clampi(int(n["power"][i]) + amt, 0, POWER_CAP)
			"add_treasury":
				n["treasury"] = maxf(0.0, n["treasury"] + amt)
			"add_stability":
				n["stability"] = clampi(int(n["stability"]) + amt, -3, 3)
			"add_manpower":
				n["manpower"] = maxi(0, int(n["manpower"]) + amt)
			"add_opinion":
				if nations.has(t) and t != tag:
					dip.add_opinion(tag, t, float(amt), e.get("reason", "Events"), 0.5)
					dip.add_opinion(t, tag, float(amt), e.get("reason", "Events"), 0.5)
			"set_flag":
				if e.get("scope", "nation") == "global":
					global_flags[e["name"]] = true
				else:
					n["flags"][e["name"]] = true
			"clear_flag":
				global_flags.erase(e["name"])
				n["flags"].erase(e["name"])
				if String(e["name"]).begins_with("allied_") and nations.has(String(e["name"]).substr(7)):
					dip.set_both(tag, String(e["name"]).substr(7), "alliance", false)
			"add_dev":
				var id := int(province_ids_by_name.get(e.get("province", ""), -1))
				if id >= 0:
					var k := int(e.get("index", 0))
					provinces[id]["dev"][k] = maxi(1, int(provinces[id]["dev"][k]) + amt)
					province_changed.emit(id)
			"reveal":
				var rid := int(province_ids_by_name.get(e.get("province", ""), -1))
				if rid >= 0:
					n["explored"][rid] = true
					province_changed.emit(rid)
			"fire_event":
				scheduled.append({"due": day_index + int(e.get("delay_days", 0)), "id": e["id"], "tag": t})
			"message":
				post(e.get("text", ""), [t])
			"add_modifier":
				add_nation_modifier(t, e.get("id", e.get("name", "mod")), e.get("name", "Modifier"), e.get("modifiers", {}), int(e.get("months", -1)))
			"add_war_exhaustion":
				n["war_exhaustion"] = clampf(float(n["war_exhaustion"]) + amt, 0.0, 20.0)
			"add_army_tradition":
				n["army_tradition"] = clampf(float(n["army_tradition"]) + amt, 0.0, 100.0)
			"add_reform_progress":
				n["reform_progress"] = maxf(0.0, float(n["reform_progress"]) + amt)
			"declare_war":
				if nations.has(t) and nations[t]["alive"] and t != tag:
					dip.declare_war(tag, t)
			"add_claim":
				if e.has("tag"):
					for cpid in owned_provinces(String(e["tag"])):
						n["claims"][cpid] = true
				else:
					var cid := int(province_ids_by_name.get(e.get("province", ""), -1))
					if cid >= 0:
						n["claims"][cid] = true
			"add_core":
				var coid := int(province_ids_by_name.get(e.get("province", ""), -1))
				if coid >= 0 and provinces[coid]["owner"] == tag:
					provinces[coid]["cores"][tag] = true
			"spawn_leader":
				n["power"][2] = int(n["power"][2]) + mil.leader_cost()
				mil.recruit_leader(tag)
			"price_shock":
				eco.shock_price(e.get("goods", ""), float(e.get("factor", 1.0)))
			"join_war":
				var w: Dictionary = wars.get(int(e.get("war", -1)), {})
				if not w.is_empty():
					dip._join(w, tag, e.get("side", "attackers"))
					var payer: String = e.get("payer", "")
					if nations.has(payer) and int(e.get("price", 0)) > 0:
						var pay := minf(float(e["price"]), maxf(0.0, float(nations[payer]["treasury"])))
						nations[payer]["treasury"] -= pay
						n["treasury"] += pay
					war_changed.emit()
			"add_legitimacy":
				court.add_legitimacy(tag, float(amt))
			"spawn_entities":
				var portal := portal_id()
				if portal >= 0:
					mil.spawn_entities(portal, maxi(1, amt))
			"add_autonomy":
				for pid in owned(tag):
					if capital_of(tag) != pid:
						provinces[pid]["autonomy"] = clampf(float(provinces[pid]["autonomy"]) + amt, eco.min_autonomy(tag, pid), 100.0)
			"refuse_call":
				var caller: String = e.get("caller", "")
				if nations.has(caller):
					dip.set_both(tag, caller, "alliance", false)
					dip.add_opinion(caller, tag, -50.0, "Refused our call to arms", 1.0)
			"accept_peace":
				var pw: Dictionary = wars.get(int(e.get("war", -1)), {})
				if not pw.is_empty():
					dip.enforce_peace(pw, e.get("demander", ""), e.get("target", tag), e.get("demands", []))
			_:
				push_warning("Unknown effect type: %s" % e.get("type", "?"))
	if nations.has(tag):
		touch(tag)


# ---------------------------------------------------------------- conditions & missions

func check_conditions(conds: Array, tag: String) -> bool:
	for c in conds:
		if not check_condition(c, tag):
			return false
	return true


func check_condition(c: Dictionary, tag: String) -> bool:
	if bool(c.get("negate", false)):
		var c2 := c.duplicate()
		c2.erase("negate")
		return not check_condition(c2, tag)
	var n: Dictionary = nations[tag]
	match c.get("type", ""):
		"year_at_least":
			return year >= int(c["value"])
		"flag":
			return n["flags"].has(c["name"]) or (c.get("scope", "") == "global" and global_flags.has(c["name"]))
		"not_flag":
			if c.get("scope", "") == "global":
				return not global_flags.has(c["name"])
			return not n["flags"].has(c["name"])
		"explored":
			return n["explored"].has(int(province_ids_by_name.get(c["province"], -1)))
		"explored_count":
			var count := 0
			for id in n["explored"]:
				if provinces[id]["layer"] == c.get("layer", provinces[id]["layer"]) and provinces[id]["owner"] != tag:
					count += 1
			return count >= int(c["at_least"])
		"owns":
			var oid := int(province_ids_by_name.get(c["province"], -1))
			return oid >= 0 and provinces[oid]["owner"] == tag
		"province_dev_at_least":
			var pid := int(province_ids_by_name.get(c["province"], -1))
			return pid >= 0 and provinces[pid]["owner"] == tag and total_dev(pid) >= int(c["at_least"])
		"region_dev_at_least":
			var total := 0
			for id in owned(tag):
				if provinces[id]["region"] == c["region"]:
					total += total_dev(id)
			return total >= int(c["at_least"])
		"owns_region":
			for id in provinces:
				if provinces[id]["region"] == c["region"] and provinces[id]["owner"] != tag:
					return false
			return true
		"provinces_owned_at_least":
			return owned(tag).size() >= int(c["at_least"])
		"layer_provinces_owned_at_least":
			var lc := 0
			for id in owned(tag):
				if provinces[id]["layer"] == c["layer"]:
					lc += 1
			return lc >= int(c["at_least"])
		"power_at_least":
			return int(n["power"][int(c["index"])]) >= int(c["at_least"])
		"tech_at_least":
			return int(n["tech"][TRACKS.find(c["track"])]) >= int(c["at_least"])
		"ideas_at_least":
			return prog.ideas_taken(tag) >= int(c["at_least"])
		"reforms_at_least":
			return n["reforms"].size() >= int(c["at_least"])
		"buildings_at_least":
			var bc := 0
			for id in owned(tag):
				if c.get("building", "") == "" :
					bc += provinces[id]["buildings"].size()
				elif provinces[id]["buildings"].has(c["building"]):
					bc += 1
			return bc >= int(c["at_least"])
		"regiments_at_least":
			return mil.regiment_count(tag) >= int(c["at_least"])
		"ships_at_least":
			return mil.ship_count(tag) >= int(c["at_least"])
		"treasury_at_least":
			return float(n["treasury"]) >= float(c["at_least"])
		"stability_at_least":
			return int(n["stability"]) >= int(c["at_least"])
		"total_dev_at_least":
			return nation_dev(tag) >= int(c["at_least"])
		"trade_income_at_least":
			return float(trade.income.get(tag, 0.0)) >= float(c["at_least"])
		"trade_share_at_least":
			return trade.share(tag, c["node"]) >= float(c["at_least"])
		"battles_won_at_least":
			return int(n.get("battles_won", 0)) >= int(c["at_least"])
		"at_war":
			return dip.at_war_any(tag)
		"not_at_war":
			return not dip.at_war_any(tag)
		"nation_dead":
			return not nations.has(c["tag"]) or not nations[c["tag"]]["alive"]
		"subjects_at_least":
			return n["subjects"].size() >= int(c["at_least"])
		"subdued":
			## conquered (gone) or made our subject
			var st: String = c["tag"]
			return not nations.has(st) or not nations[st]["alive"] or nations[st]["overlord"] == tag
		"province_has_building":
			var pb := int(province_ids_by_name.get(c["province"], -1))
			return pb >= 0 and provinces[pb]["owner"] == tag and provinces[pb]["buildings"].has(c["building"])
		"owns_mainland":
			return owns_mainland(tag)
		"allied_with":
			return nations.has(c["tag"]) and dip.rel(tag, c["tag"])["alliance"]
		"opinion_at_least":
			return nations.has(c["tag"]) and dip.opinion(c["tag"], tag) >= float(c["at_least"])
		"in_skyfall":
			return in_skyfall(tag)
		"is_tag":
			return tag == c["tag"]
		"culture_provinces_at_least":
			var cc := 0
			for id in owned(tag):
				if provinces[id]["culture"] == n["culture"]:
					cc += 1
			return cc >= int(c["at_least"])
		"religion_provinces_at_least":
			var rc := 0
			for id in owned(tag):
				if provinces[id]["religion"] == n["religion"]:
					rc += 1
			return rc >= int(c["at_least"])
		"has_reform":
			return c["id"] in n["reforms"]
		"legitimacy_at_least":
			return float(n.get("legitimacy", 0.0)) >= float(c["at_least"])
		"has_advisors_at_least":
			var ac := 0
			for k in n.get("advisors", {}):
				if not n["advisors"][k].is_empty():
					ac += 1
			return ac >= int(c["at_least"])
		"mines_at_least":
			var mc := 0
			for id in owned(tag):
				if provinces[id]["buildings"].has("mine"):
					mc += 1
			return mc >= int(c["at_least"])
		"portal_held_by_entities":
			return portal_id() >= 0 and provinces[portal_id()]["controller"] == "ENT"
		"gov_type":
			return court.gov_type(tag) == c["value"]
		"no_loans":
			return n["loans"].is_empty()
	push_warning("Unknown condition type: %s" % c.get("type", "?"))
	return false


func describe_condition(c: Dictionary) -> String:
	var tag := player_tag
	match c.get("type", ""):
		"flag": return "Flag: %s" % c["name"].replace("_", " ")
		"explored": return "Explore %s" % c["province"]
		"owns": return "Own %s" % c["province"]
		"owns_region": return "Own all of %s" % c["region"]
		"province_dev_at_least": return "%s at %d development" % [c["province"], int(c["at_least"])]
		"region_dev_at_least": return "%s region at %d development" % [c["region"], int(c["at_least"])]
		"provinces_owned_at_least": return "Own %d provinces" % int(c["at_least"])
		"layer_provinces_owned_at_least": return "Own %d %s province(s)" % [int(c["at_least"]), "Skyfall" if c["layer"] == "sky" else "mainland"]
		"power_at_least":
			var pn: String = nations[tag]["power_names"][int(c["index"])] if nations.has(tag) else "power"
			return "%d %s power" % [int(c["at_least"]), pn]
		"year_at_least": return "Year %d" % int(c["value"])
		"tech_at_least": return "%s tech %d" % [String(c["track"]).to_upper(), int(c["at_least"])]
		"ideas_at_least": return "%d ideas adopted" % int(c["at_least"])
		"reforms_at_least": return "%d government reforms" % int(c["at_least"])
		"buildings_at_least":
			if c.get("building", "") == "":
				return "%d buildings" % int(c["at_least"])
			return "%d x %s" % [int(c["at_least"]), building_data.get(c["building"], {}).get("name", c["building"])]
		"regiments_at_least": return "%d regiments" % int(c["at_least"])
		"ships_at_least": return "%d ships" % int(c["at_least"])
		"treasury_at_least": return "%d sanctum in the treasury" % int(c["at_least"])
		"stability_at_least": return "Stability %+d" % int(c["at_least"])
		"total_dev_at_least": return "%d total development" % int(c["at_least"])
		"trade_income_at_least": return "%.1f trade income a month" % float(c["at_least"])
		"trade_share_at_least": return "%d%% of trade power in %s" % [int(float(c["at_least"]) * 100), c["node"]]
		"battles_won_at_least": return "Win %d battles" % int(c["at_least"])
		"not_at_war": return "Be at peace"
		"at_war": return "Be at war"
		"nation_dead": return "%s no longer exists" % nation_name(c["tag"])
		"subjects_at_least": return "%d vassal(s)" % int(c["at_least"])
		"subdued": return "%s conquered or made your subject" % nation_name(c["tag"])
		"province_has_building": return "A %s in %s" % [building_data.get(c["building"], {}).get("name", c["building"]).to_lower(), c["province"]]
		"owns_mainland": return "Land on the Arcadian continent"
		"allied_with": return "Allied with %s" % nation_name(c["tag"])
		"opinion_at_least": return "%s's opinion of you at %d" % [nation_name(c["tag"]), int(c["at_least"])]
		"in_skyfall": return "Have land or armies in Skyfall"
		"culture_provinces_at_least": return "%d provinces of your culture" % int(c["at_least"])
		"religion_provinces_at_least": return "%d provinces of your faith" % int(c["at_least"])
		"has_reform": return "Reform: %s" % prog.reform_name(tag, c["id"]) if tag != "" else c["id"]
		"no_loans": return "No loans"
		"legitimacy_at_least": return "Legitimacy %d" % int(c["at_least"])
		"has_advisors_at_least": return "%d advisors employed" % int(c["at_least"])
		"mines_at_least": return "%d mines" % int(c["at_least"])
		"portal_held_by_entities": return "Entities hold the Doomsday Portal"
		"gov_type": return "Government: %s" % c["value"]
	return str(c)


func missions_for(tag: String) -> Array:
	var key: String = tag
	var has_own := false
	for m in missions:
		if m.get("nation", "") == tag:
			has_own = true
			break
	if not has_own:
		# the boars have their tribal tree, the pig states that broke from the Empire theirs; nations of
		# the far side of the world get a tree about finding their place in it
		var group: String = pop.culture_group(nations[tag]["culture"]) if nations.has(tag) else ""
		key = "TRIBE" if group == "Wild Boar" else ("STATE" if group == "Porcine" else "FARWORLD")
	var out: Array = []
	for m in missions:
		if m.get("nation", "") == key:
			out.append(m)
	return out


func mission_state(tag: String, m: Dictionary) -> String:
	## "done", "locked", "ready" or "open"
	var n: Dictionary = nations[tag]
	if n["missions_done"].has(m["id"]):
		return "done"
	for r in m.get("requires", []):
		if not n["missions_done"].has(r):
			return "locked"
	return "ready" if check_conditions(m.get("conditions", []), tag) else "open"


func claim_mission(tag: String, mission_id: String) -> bool:
	for m in missions_for(tag):
		if m["id"] == mission_id and mission_state(tag, m) == "ready":
			nations[tag]["missions_done"][mission_id] = true
			apply_effects(m.get("rewards", []), tag)
			standing.add_prestige(tag, 5.0)
			if tag == player_tag or nations[tag]["government"] != "boar_tribe":
				post("%s completes the mission: %s." % [nations[tag]["short"], m["title"]], [tag])
			touch(tag)
			return true
	return false


# ---------------------------------------------------------------- saving

func _state() -> Dictionary:
	return {
		"version": SAVE_VERSION, "year": year, "month": month, "day": day, "day_index": day_index,
		"player_tag": player_tag, "doomsday_active": doomsday_active, "doomsday_count": doomsday_count,
		"doomsday_damage": _doomsday_damage, "nations": nations, "provinces": provinces, "armies": armies,
		"fleets": fleets, "battles": battles, "wars": wars, "recruit_queue": recruit_queue, "next_id": next_id,
		"global_flags": global_flags, "pending_events": pending_events, "scheduled": scheduled,
		"fired_once": fired_once, "log_lines": log_lines, "world_lines": world_lines, "ledger_history": ledger_history, "rng_state": rng.state, "rng_seed": rng.seed,
		"market": eco.market, "history": eco.history, "trade_state": trade.state, "trade_income": trade.income,
	}


func save_game(slot: String, quiet: bool = false) -> String:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := "%s/%s.save" % [SAVE_DIR, slot.validate_filename()]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "Could not write %s." % path
	var meta := {"name": slot, "nation": nation_name(player_tag), "tag": player_tag, "date": date_string(),
		"saved": Time.get_datetime_string_from_system(false, true)}
	f.store_var(meta)
	f.store_var(_state())
	f.close()
	if not quiet:
		post("Game saved: %s." % slot)
	return ""


func list_saves() -> Array:
	var out: Array = []
	var d := DirAccess.open(SAVE_DIR)
	if d == null:
		return out
	for fn in d.get_files():
		if not fn.ends_with(".save"):
			continue
		var f := FileAccess.open("%s/%s" % [SAVE_DIR, fn], FileAccess.READ)
		if f == null:
			continue
		var meta: Variant = f.get_var()
		if meta is Dictionary:
			meta["file"] = fn.get_basename()
			meta["modified"] = FileAccess.get_modified_time("%s/%s" % [SAVE_DIR, fn])
			out.append(meta)
	out.sort_custom(func(a, b): return int(a["modified"]) > int(b["modified"]))
	return out


func delete_save(slot: String) -> void:
	DirAccess.remove_absolute("%s/%s.save" % [SAVE_DIR, slot])


func load_game(slot: String) -> String:
	var path := "%s/%s.save" % [SAVE_DIR, slot]
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "Save not found."
	f.get_var()
	var s: Variant = f.get_var()
	f.close()
	if not (s is Dictionary):
		return "This save is damaged."
	var ver := int(s.get("version", 0))
	if ver > SAVE_VERSION:
		return "This save is from a newer version of the game."
	if ver < OLDEST_SAVE:
		return "This save is too old to load (version %d; this game reads %d to %d)." % [ver, OLDEST_SAVE, SAVE_VERSION]
	# a fresh world from the current data: its map geometry always wins, and the save takes whatever
	# it lacks (provinces and nations added since it was made) from it
	setup_world()
	var fresh_provinces := provinces
	var fresh_nations := nations
	var fresh_tags: Array = nations.keys()
	year = s["year"]
	month = s["month"]
	day = s["day"]
	day_index = s["day_index"]
	player_tag = s["player_tag"]
	doomsday_active = s["doomsday_active"]
	doomsday_count = s["doomsday_count"]
	_doomsday_damage = s["doomsday_damage"]
	nations = s["nations"]
	provinces = s["provinces"]
	armies = s["armies"]
	fleets = s["fleets"]
	battles = s["battles"]
	wars = s["wars"]
	recruit_queue = s["recruit_queue"]
	next_id = s["next_id"]
	global_flags = s["global_flags"]
	pending_events = s["pending_events"]
	scheduled = s["scheduled"]
	fired_once = s["fired_once"]
	log_lines = s["log_lines"]
	world_lines = s.get("world_lines", [])
	ledger_history = s.get("ledger_history", {})
	rng.seed = s["rng_seed"]
	rng.state = s["rng_state"]
	eco.market = s["market"]
	eco.history = s["history"]
	trade.state = s["trade_state"]
	trade.income = s["trade_income"]
	_merge_world(fresh_provinces, fresh_nations, fresh_tags, ver)
	speed = 0
	_owned_cache.clear()
	mods.invalidate()
	dip.rebuild_pairs()
	started = true
	post("Loaded %s." % slot)
	game_started.emit()
	date_changed.emit()
	doomsday_changed.emit(doomsday_active)
	armies_changed.emit()
	return ""


const GEOMETRY_KEYS := ["centre", "area", "connections", "coastal", "layer"]


func _merge_world(fresh_provinces: Dictionary, fresh_nations: Dictionary, fresh_tags: Array, ver: int) -> void:
	## Bring a loaded save up to date with the current map and data (save migration).
	## Province geometry (centres, borders, sea lanes) always comes from the current map files.
	## Provinces the save doesn't know are added as they start. A nation the save doesn't know (the new
	## world's, for a save from before the world map; the Satian Union, added later) joins with its
	## starting army and fleet, and takes its home provinces if nobody has claimed them in the meantime.
	var added := false
	for id in fresh_provinces:
		if provinces.has(id):
			for k in GEOMETRY_KEYS:
				provinces[id][k] = fresh_provinces[id][k]
		else:
			provinces[id] = fresh_provinces[id]
	var defs: Dictionary = nation_defs.get("nations", {})
	for tag in fresh_tags:
		if nations.has(tag):
			continue
		added = true
		nations[tag] = fresh_nations[tag]
		for id in fresh_provinces:
			if fresh_provinces[id]["owner"] == tag and provinces[id]["owner"] == "" and provinces[id].get("colony", {}).is_empty():
				provinces[id] = fresh_provinces[id]
		_owned_cache.clear()
		var d: Dictionary = defs.get(tag, {})
		var ad: Dictionary = d.get("army", {})
		var apid := int(province_ids_by_name.get(ad.get("location", ""), -1))
		if apid >= 0:
			mil.spawn_army(tag, apid, int(ad.get("inf", 2)), int(ad.get("cav", 0)), int(ad.get("art", 0)))
		var fd: Dictionary = d.get("fleet", {})
		var fpid := int(province_ids_by_name.get(fd.get("location", ""), -1))
		if fpid >= 0:
			var counts := {}
			for k in ["heavy", "light", "transport"]:
				if fd.has(k):
					counts[k] = int(fd[k])
			mil.spawn_fleet(tag, fpid, counts)
		post("%s joins the world." % nations[tag]["name"], [tag])
	if added:
		trade.monthly()   # new trade nodes and new traders


# ---------------------------------------------------------------- misc

func post(text: String, tags: Array = [], major: String = "", near: bool = false) -> void:
	## Log a message. `tags` are the nations it is about: if none of them matter to the player
	## (themselves, allies, subjects, overlord, enemies, neighbours), it goes to the world news
	## instead of the main log, like EU4's message filters. `major` (a short title) asks the UI to
	## pause and show a popup when the news names the player directly. Neighbours only count when
	## `near` is set (wars, vassals, annexations), so AI alliances next door stay in the world news.
	if not tags.is_empty() and not concerns_player(tags, near):
		world_lines.append(text)
		if world_lines.size() > 80:
			world_lines.pop_front()
		return
	log_lines.append(text)
	if log_lines.size() > 80:
		log_lines.pop_front()
	message_posted.emit(text)
	if major != "" and started and (tags.is_empty() or player_tag in tags):
		major_news.emit(major, text)


func eschaton_corruption() -> float:
	## How far the world has decayed toward the Eschaton: nothing until the last year, then a quarter
	## at once (with the eye) rising to all of it. Worked out from the date, so loading a save gets it right.
	if year < end_year - 1:
		return 0.0
	if year >= end_year:
		return 1.0
	return 0.25 + 0.75 * float(month - 1) / 12.0


func record_ledger() -> void:
	## A yearly snapshot of every nation for the Ledger's graphs (EU4's ledger history).
	for t in nations:
		if not nations[t]["alive"] or t in ["REB", "ENT"]:
			continue
		if not ledger_history.has(t):
			ledger_history[t] = []
		var rows: Array = ledger_history[t]
		if not rows.is_empty() and int(rows.back()[0]) == year:
			rows.pop_back()
		rows.append([year, nation_dev(t), snappedf(float(nations[t].get("last_income", 0.0)), 0.01), mil.regiment_count(t), owned(t).size()])


func concerns_player(tags: Array, near: bool = false) -> bool:
	if player_tag == "" or not nations.has(player_tag) or player_tag in tags:
		return true
	for t in tags:
		if nations.has(t) and (dip.allied(player_tag, t) or dip.at_war(player_tag, t) or (near and dip.borders(player_tag, t))):
			return true
	return false


func player() -> Dictionary:
	return nations.get(player_tag, {})


func is_explored_by_player(id: int) -> bool:
	if player_tag == "" or not nations.has(player_tag):
		return true
	return nations[player_tag]["explored"].has(id)
