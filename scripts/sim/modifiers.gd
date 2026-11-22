extends RefCounted
## Modifiers: every bonus in the game is a named number (tax_mod, land_morale, unrest...) summed from
## the nation's government and reforms, technology, ideas, religion, buildings and timed modifiers.
## Systems read them with nat(tag, key) and loc(province_id, key). Results are cached per nation and
## dropped by invalidate(tag) whenever something that feeds them changes (Game.touch does this).

const LABELS := {
	"tax_mod": ["Tax income", true], "production_mod": ["Production income", true],
	"trade_power_mod": ["Trade power", true], "trade_efficiency": ["Trade efficiency", true],
	"manpower_mod": ["Manpower", true], "land_maintenance_mod": ["Army maintenance", true],
	"naval_maintenance_mod": ["Navy maintenance", true], "land_morale": ["Army morale", true],
	"naval_morale": ["Navy morale", true], "discipline": ["Discipline", true],
	"infantry_power": ["Infantry combat", true], "cavalry_power": ["Cavalry combat", true],
	"artillery_power": ["Artillery combat", true], "fort_defense": ["Fort defence", true],
	"siege_ability": ["Siege ability", true], "dev_cost_mod": ["Development cost", true],
	"tech_cost_mod": ["Technology cost", true], "idea_cost_mod": ["Idea cost", true],
	"core_cost_mod": ["Core-creation cost", true], "stability_cost_mod": ["Stability cost", true],
	"build_cost_mod": ["Construction cost", true], "build_time_mod": ["Construction time", true],
	"unrest": ["National unrest", false], "tolerance_own": ["Tolerance of the true faith", false],
	"tolerance_heathen": ["Tolerance of other faiths", false], "colonists": ["Colonists", false],
	"colonist_growth": ["Settlers a month", false], "merchants": ["Merchants", false],
	"diplomats": ["Diplomats", false], "missionaries": ["Missionaries", false],
	"missionary_strength": ["Missionary strength", true], "diplomatic_reputation": ["Diplomatic reputation", false],
	"improve_relations_mod": ["Improve relations", true], "interest_mod": ["Loan interest", true],
	"monthly_adm": ["Monthly %s power", false], "monthly_dip": ["Monthly %s power", false],
	"monthly_mil": ["Monthly %s power", false], "leader_fire": ["General fire", false],
	"leader_shock": ["General shock", false], "leader_maneuver": ["General manoeuvre", false],
	"leader_siege": ["General siege", false], "reinforce_speed": ["Reinforce speed", true],
	"land_force_limit": ["Army force limit", false], "naval_force_limit": ["Navy force limit", false],
	"accepted_cultures": ["Max accepted cultures", false], "doomsday_resistance": ["Doomsday resistance", true],
	"explore_cost_mod": ["Exploration cost", true], "legitimacy_gain": ["Legitimacy a year", false],
	"autonomy_gain": ["Autonomy growth", true], "local_autonomy_gain": ["Local autonomy growth", true],
	"local_mine_income": ["Mine", false],
	"local_tax_mod": ["Local tax", true], "local_production_mod": ["Local production", true],
	"local_trade_power": ["Local trade power", false], "local_unrest": ["Local unrest", false],
	"local_manpower_mod": ["Local manpower", true], "local_supply": ["Supply limit", false],
	"local_fort": ["Fort", false], "local_core_cost": ["Local core cost", true], "local_dev_cost": ["Local development cost", true],
}
## Keys where a negative value is good for the nation (shown green).
const LOWER_IS_BETTER := ["land_maintenance_mod", "naval_maintenance_mod", "dev_cost_mod", "tech_cost_mod",
	"idea_cost_mod", "core_cost_mod", "stability_cost_mod", "build_cost_mod", "build_time_mod", "unrest",
	"interest_mod", "local_unrest", "local_core_cost", "local_dev_cost", "explore_cost_mod", "autonomy_gain",
	"local_autonomy_gain"]

var g: Node
var _cache = {}          # tag -> {key: value}
var _sources = {}        # tag -> [[source name, {key: value}]] (for tooltips)


func _init(game: Node) -> void:
	g = game


func invalidate(tag: String = "") -> void:
	if tag == "":
		_cache.clear()
		_sources.clear()
	else:
		_cache.erase(tag)
		_sources.erase(tag)


func nat(tag: String, key: String) -> float:
	if not _cache.has(tag):
		_build(tag)
	return float(_cache.get(tag, {}).get(key, 0.0))


func sources(tag: String) -> Array:
	if not _sources.has(tag):
		_build(tag)
	return _sources.get(tag, [])


func breakdown(tag: String, keys: Array, percent: bool = true) -> String:
	## "Where does this number come from": one line per named source that changes any of `keys`,
	## then the total. Used for the EU4-style breakdown tooltips.
	var lines: PackedStringArray = []
	var total := 0.0
	for s in sources(tag):
		var v := 0.0
		for k in keys:
			v += float(s[1].get(k, 0.0))
		if absf(v) > 0.0001:
			total += v
			lines.append(("  %s: %+d%%" % [s[0], int(round(v * 100.0))]) if percent else ("  %s: %+.2f" % [s[0], v]))
	if lines.is_empty():
		return "No modifiers."
	lines.append(("Total: %+d%%" % int(round(total * 100.0))) if percent else ("Total: %+.2f" % total))
	return "\n".join(lines)


func _add(out: Dictionary, mods: Dictionary) -> void:
	for k in mods:
		out[k] = float(out.get(k, 0.0)) + float(mods[k])


func _build(tag: String) -> void:
	var n: Dictionary = g.nations.get(tag, {})
	var out = {}
	var src: Array = []
	if n.is_empty():
		_cache[tag] = out
		_sources[tag] = src
		return
	# government and reforms
	var gov: Dictionary = g.governments.get(n["government"], {})
	if gov.has("modifiers"):
		src.append([gov.get("name", "Government"), gov["modifiers"]])
	var tiers: Array = gov.get("tiers", [])
	for i in n["reforms"].size():
		if i < tiers.size():
			for r in tiers[i]["reforms"]:
				if r["id"] == n["reforms"][i]:
					src.append(["Reform: " + r["name"], r.get("modifiers", {})])
	# technology
	for track in ["adm", "dip", "mil"]:
		var lvl: int = int(n["tech"][g.TRACKS.find(track)])
		var tm = {}
		for t in g.tech_data.get(track, []):
			if int(t["level"]) <= lvl and t.has("modifiers"):
				_add(tm, t["modifiers"])
		if not tm.is_empty():
			src.append(["%s technology" % track.capitalize(), tm])
	# ideas
	var taken = 0
	for ig in n["idea_groups"]:
		var grp: Dictionary = g.idea_data["groups"].get(ig["id"], {})
		var gm = {}
		for i in mini(int(ig["taken"]), grp.get("ideas", []).size()):
			_add(gm, grp["ideas"][i][1])
		if int(ig["taken"]) >= grp.get("ideas", []).size() and grp.has("bonus"):
			_add(gm, grp["bonus"])
		taken += int(ig["taken"])
		if not gm.is_empty():
			src.append([grp.get("name", ig["id"]) + " ideas", gm])
	var natl: Dictionary = g.idea_data["national"].get(n["ideas"], {})
	if not natl.is_empty():
		var nm = {}
		_add(nm, natl.get("traditions", {}))
		var unlocked: int = g.prog.national_ideas_unlocked(tag)
		for i in unlocked:
			_add(nm, natl["ideas"][i][1])
		if unlocked >= natl["ideas"].size():
			_add(nm, natl.get("ambition", {}))
		src.append([natl.get("name", "National ideas"), nm])
	# religion
	var rel: Dictionary = g.peoples["religions"].get(n["religion"], {})
	if rel.has("modifiers"):
		src.append([n["religion"], rel["modifiers"]])
	# nation-wide effects of buildings
	var bm = {}
	for id in g.owned(tag):
		for b in g.provinces[id]["buildings"]:
			var bd: Dictionary = g.building_data.get(b, {})
			for k in bd.get("modifiers", {}):
				if not String(k).begins_with("local_"):
					bm[k] = float(bm.get(k, 0.0)) + float(bd["modifiers"][k])
	if not bm.is_empty():
		src.append(["Buildings", bm])
	# advisors
	for k in n.get("advisors", {}):
		var adv: Dictionary = n["advisors"][k]
		if not adv.is_empty():
			var at: Dictionary = g.advisor_data.get("types", {}).get(adv["type"], {})
			src.append(["Advisor: %s (skill %d)" % [at.get("name", adv["type"]), int(adv["skill"])], at.get("modifiers", {})])
	# legitimacy
	var leg: float = float(n.get("legitimacy", 50.0))
	if leg < 50.0:
		src.append(["Low legitimacy (%d)" % int(leg), {"unrest": (50.0 - leg) / 20.0, "tax_mod": -(50.0 - leg) / 250.0}])
	elif leg >= 90.0:
		src.append(["High legitimacy (%d)" % int(leg), {"unrest": -1.0}])
	# Skyfall, while it keeps to the sky
	if tag == "SKY" and not g.owns_mainland(tag):
		src.append(["Isolation of Eden (no land on the Arcadian continent)", {"dev_cost_mod": -0.25, "tax_mod": 0.10, "production_mod": 0.10}])
	# stability
	var st: int = int(n["stability"])
	if st != 0:
		src.append(["Stability %+d" % st, {"tax_mod": 0.05 * st, "unrest": -1.0 * st}])
	# prestige, Great Power status and the estates (scripts/sim/standing.gd)
	var pr: float = float(n.get("prestige", 0.0))
	if absf(pr) >= 1.0:
		src.append(["Prestige %+d" % int(pr), {"land_morale": pr / 1000.0, "diplomatic_reputation": pr / 50.0}])
	if g.standing != null and g.standing.ranking.has(tag) and g.standing.is_great_power(tag):
		src.append(["Great Power (#%d)" % g.standing.rank(tag), {"diplomatic_reputation": 1.0, "land_force_limit": 2}])
	if g.standing != null and not g.estate_data.is_empty():
		src.append_array(g.standing.estate_modifier_sources(tag))
	if g.standing != null and not g.age_data.is_empty():
		src.append_array(g.standing.age_modifier_sources(tag))
	# timed and event modifiers
	for m in n["modifiers"]:
		src.append([m.get("name", m.get("id", "Modifier")), m.get("mods", {})])
	for s in src:
		_add(out, s[1])
	_cache[tag] = out
	_sources[tag] = src


func loc(pid: int, key: String) -> float:
	## Province-level value: its buildings plus its own timed modifiers.
	var p: Dictionary = g.provinces[pid]
	var v = 0.0
	for b in p["buildings"]:
		v += float(g.building_data.get(b, {}).get("modifiers", {}).get(key, 0.0))
	for m in p["modifiers"]:
		v += float(m.get("mods", {}).get(key, 0.0))
	return v


func expire(list: Array) -> Array:
	## Drops timed modifiers whose time is up. Returns the kept ones.
	var out: Array = []
	for m in list:
		if int(m.get("until", -1)) < 0 or int(m["until"]) > g.day_index:
			out.append(m)
	return out


static func describe(mods: Dictionary, power_names: Array = []) -> String:
	var parts: PackedStringArray = []
	for k in mods:
		parts.append(describe_one(k, float(mods[k]), power_names))
	return ", ".join(parts)


static func describe_one(k: String, v: float, power_names: Array = []) -> String:
	var info: Array = LABELS.get(k, [k.replace("_", " ").capitalize(), false])
	var label: String = info[0]
	if "%s" in label:
		var idx: int = ["monthly_adm", "monthly_dip", "monthly_mil"].find(k)
		label = label % (power_names[idx] if idx >= 0 and power_names.size() > idx else ["admin", "diplo", "military"][maxi(idx, 0)])
	if info[1]:
		return "%s %+d%%" % [label, int(round(v * 100.0))]
	if absf(v - round(v)) < 0.001:
		return "%s %+d" % [label, int(round(v))]
	return "%s %+.1f" % [label, v]


static func is_good(k: String, v: float) -> bool:
	return (v < 0.0) if k in LOWER_IS_BETTER else (v > 0.0)
