extends RefCounted
## Cultures, religions and ethnicities; cores and overextension; unrest and rebellions.

const REBEL_THRESHOLD := 100.0

var g: Node


func _init(game: Node) -> void:
	g = game


# ---------------------------------------------------------------- cultures and religions

func culture_group(culture: String) -> String:
	for gid in g.peoples["culture_groups"]:
		if culture in g.peoples["culture_groups"][gid]["cultures"]:
			return gid
	return ""


func culture_accepted(tag: String, culture: String) -> bool:
	var n: Dictionary = g.nations[tag]
	return culture == "" or culture == n["culture"] or culture in n["accepted_cultures"]


func max_accepted(tag: String) -> int:
	return 2 + int(g.mods.nat(tag, "accepted_cultures"))


func tolerance(tag: String, religion: String) -> float:
	if religion == g.nations[tag]["religion"]:
		return 2.0 + g.mods.nat(tag, "tolerance_own")
	return -1.0 + g.mods.nat(tag, "tolerance_heathen")


func can_accept_culture(tag: String, culture: String) -> String:
	var n: Dictionary = g.nations[tag]
	if culture_accepted(tag, culture):
		return "Already accepted."
	var extra = 0
	for c in n["accepted_cultures"]:
		if culture_group(c) != culture_group(n["culture"]):
			extra += 1
	if culture_group(culture) != culture_group(n["culture"]) and extra >= max_accepted(tag):
		return "No room for more accepted cultures outside your culture group (%d)." % max_accepted(tag)
	if n["power"][1] < 100:
		return "Needs 100 %s power." % n["power_names"][1]
	return ""


func accept_culture(tag: String, culture: String) -> bool:
	if can_accept_culture(tag, culture) != "":
		return false
	g.nations[tag]["power"][1] -= 100
	g.nations[tag]["accepted_cultures"].append(culture)
	g.touch(tag)
	return true


func culture_convert_cost(tag: String, pid: int) -> int:
	return 8 * g.total_dev(pid)


func can_convert_culture(tag: String, pid: int) -> String:
	var p: Dictionary = g.provinces[pid]
	if p["owner"] != tag:
		return "Not your province."
	if p["culture"] == g.nations[tag]["culture"]:
		return "Already of your culture."
	if not p["cores"].has(tag):
		return "Core the province first."
	var c = culture_convert_cost(tag, pid)
	if g.nations[tag]["power"][1] < c:
		return "Needs %d %s power." % [c, g.nations[tag]["power_names"][1]]
	return ""


func convert_culture(tag: String, pid: int) -> bool:
	if can_convert_culture(tag, pid) != "":
		return false
	g.nations[tag]["power"][1] -= culture_convert_cost(tag, pid)
	g.provinces[pid]["culture"] = g.nations[tag]["culture"]
	g.province_changed.emit(pid)
	g.touch(tag)
	return true


func missionaries(tag: String) -> int:
	return 1 + int(g.mods.nat(tag, "missionaries"))


func missionaries_used(tag: String) -> int:
	var c = 0
	for pid in g.provinces:
		if g.provinces[pid]["conversion"].get("tag", "") == tag:
			c += 1
	return c


func can_start_conversion(tag: String, pid: int) -> String:
	var p: Dictionary = g.provinces[pid]
	if p["owner"] != tag:
		return "Not your province."
	if p["religion"] == g.nations[tag]["religion"] or p["religion"] == "":
		return "Already of your faith."
	if p["conversion"].get("tag", "") == tag:
		return "A missionary is already here."
	if missionaries_used(tag) >= missionaries(tag):
		return "No free missionaries (%d)." % missionaries(tag)
	return ""


func start_conversion(tag: String, pid: int) -> bool:
	if can_start_conversion(tag, pid) != "":
		return false
	g.provinces[pid]["conversion"] = {"tag": tag, "progress": 0.0}
	g.province_changed.emit(pid)
	g.touch(tag)
	return true


func conversion_speed(tag: String, pid: int) -> float:
	return maxf(0.5, 4.0 + g.mods.nat(tag, "missionary_strength") * 100.0 - g.total_dev(pid) * 0.15
		- maxf(0.0, float(g.provinces[pid].get("unrest", 0.0))))


# ---------------------------------------------------------------- cores and overextension

func core_cost(tag: String, pid: int) -> int:
	var mult = 1.0 + g.mods.nat(tag, "core_cost_mod") + g.mods.loc(pid, "local_core_cost")
	return maxi(5, int(round(6.0 * g.total_dev(pid) * maxf(0.2, mult))))


func can_core(tag: String, pid: int) -> String:
	var p: Dictionary = g.provinces[pid]
	if p["owner"] != tag:
		return "Not your province."
	if p["cores"].has(tag):
		return "Already a core."
	if p["controller"] != tag:
		return "The province is occupied."
	var c = core_cost(tag, pid)
	if g.nations[tag]["power"][0] < c:
		return "Needs %d %s power." % [c, g.nations[tag]["power_names"][0]]
	return ""


func make_core(tag: String, pid: int) -> bool:
	if can_core(tag, pid) != "":
		return false
	g.nations[tag]["power"][0] -= core_cost(tag, pid)
	g.provinces[pid]["cores"][tag] = true
	g.province_changed.emit(pid)
	g.touch(tag)
	return true


func overextension(tag: String) -> float:
	var uncored = 0.0
	for pid in g.owned(tag):
		if not g.provinces[pid]["cores"].has(tag):
			uncored += g.total_dev(pid)
	return uncored


# ---------------------------------------------------------------- unrest

func unrest_breakdown(pid: int) -> Array:
	## [[reason, value]]
	var p: Dictionary = g.provinces[pid]
	var tag: String = p["owner"]
	var out: Array = []
	if tag == "":
		return out
	var n: Dictionary = g.nations[tag]
	if not culture_accepted(tag, p["culture"]):
		out.append(["%s culture is not accepted" % p["culture"], 2.0])
		if culture_group(p["culture"]) != culture_group(n["culture"]):
			out.append(["Foreign culture group", 1.0])
	if p["ethnicity"] != "" and p["ethnicity"] != n["ethnicity"] and \
			g.peoples["ethnicities"].get(p["ethnicity"], {}).get("breathes", "") != g.peoples["ethnicities"].get(n["ethnicity"], {}).get("breathes", ""):
		out.append(["%s ethnicity under foreign rule" % p["ethnicity"], 1.0])
	if p["religion"] != "" and p["religion"] != n["religion"]:
		out.append(["%s faith" % p["religion"], 3.0 - maxf(0.0, tolerance(tag, p["religion"]) + 1.0)])
	elif p["religion"] == n["religion"]:
		out.append(["True faith tolerance", -tolerance(tag, p["religion"]) * 0.5])
	if not p["cores"].has(tag):
		out.append(["Not a core", 2.0])
	var oe = overextension(tag)
	if oe > 0.0:
		out.append(["Overextension (%d uncored development)" % int(oe), oe / 25.0])
	var we = float(n["war_exhaustion"])
	if we > 0.0:
		out.append(["War exhaustion", we * 0.5])
	var nu = g.mods.nat(tag, "unrest")
	if nu != 0.0:
		out.append(["National modifiers (incl. stability)", nu])
	var lu = g.mods.loc(pid, "local_unrest")
	if lu != 0.0:
		out.append(["Local modifiers", lu])
	if g.mil.own_troops_in(tag, pid) > 0:
		out.append(["Troops present", -1.0])
	return out


func compute_unrest(pid: int) -> float:
	var total = 0.0
	for r in unrest_breakdown(pid):
		total += float(r[1])
	return total


func can_harsh(tag: String, pid: int) -> String:
	var p: Dictionary = g.provinces[pid]
	if p["owner"] != tag:
		return "Not your province."
	if float(p["rebel_progress"]) <= 0.0:
		return "No rebels are organising here."
	var c = harsh_cost(pid)
	if g.nations[tag]["power"][2] < c:
		return "Needs %d %s power." % [c, g.nations[tag]["power_names"][2]]
	return ""


func harsh_cost(pid: int) -> int:
	return 4 * g.total_dev(pid)


func harsh_treatment(tag: String, pid: int) -> bool:
	if can_harsh(tag, pid) != "":
		return false
	g.nations[tag]["power"][2] -= harsh_cost(pid)
	g.provinces[pid]["rebel_progress"] = maxf(0.0, float(g.provinces[pid]["rebel_progress"]) - 60.0)
	g.province_changed.emit(pid)
	g.touch(tag)
	return true


func rebel_type(pid: int) -> String:
	var p: Dictionary = g.provinces[pid]
	var tag: String = p["owner"]
	if p["religion"] != g.nations[tag]["religion"] and p["religion"] != "":
		return "zealots"
	if not culture_accepted(tag, p["culture"]):
		return "separatists"
	return "peasants"


func monthly() -> void:
	for pid in g.provinces:
		var p: Dictionary = g.provinces[pid]
		if p["owner"] == "":
			p["unrest"] = 0.0
			p["rebel_progress"] = 0.0
			continue
		var u = compute_unrest(pid)
		p["unrest"] = u
		var prog = float(p["rebel_progress"])
		if u > 0.0:
			prog += u * 1.5
		else:
			prog = maxf(0.0, prog - 6.0)
		if prog >= REBEL_THRESHOLD and p["controller"] == p["owner"] and not g.mil.rebels_near(pid):
			prog = 0.0
			g.mil.spawn_rebels(pid, rebel_type(pid))
		p["rebel_progress"] = prog
		# religious conversion
		var conv: Dictionary = p["conversion"]
		if not conv.is_empty():
			var tag: String = conv["tag"]
			if p["owner"] != tag or p["religion"] == g.nations[tag]["religion"]:
				p["conversion"] = {}
			else:
				conv["progress"] = float(conv["progress"]) + conversion_speed(tag, pid)
				if float(conv["progress"]) >= 100.0:
					p["religion"] = g.nations[tag]["religion"]
					p["conversion"] = {}
					if tag == g.player_tag:
						g.post("%s has converted to the %s." % [p["name"], p["religion"]])
					g.province_changed.emit(pid)


func enforce_rebel_demands(faction: Dictionary, pids: Array) -> void:
	## Rebels held their home province long enough: give them what they want.
	var target: String = faction.get("target", "")
	if not g.nations.has(target):
		return
	var n: Dictionary = g.nations[target]
	match faction.get("type", "peasants"):
		"separatists":
			var culture: String = faction.get("culture", "")
			var free_tag = ""
			for t in g.nations:
				if g.nations[t]["culture"] == culture and t != target:
					free_tag = t
			if free_tag != "":
				if not g.nations[free_tag]["alive"]:
					g.revive_nation(free_tag)
				for pid in pids:
					if g.provinces[pid]["owner"] == target:
						g.set_province_owner(pid, free_tag)
						g.provinces[pid]["cores"][free_tag] = true
				g.post("Separatists have broken away from %s: %s is free again." % [n["short"], g.nations[free_tag]["short"]])
			else:
				for pid in pids:
					g.add_province_modifier(pid, "rebel_autonomy", "Separatist autonomy", {"local_tax_mod": -0.5,
						"local_unrest": -3}, 120)
				n["stability"] = maxi(-3, int(n["stability"]) - 1)
				g.post("%s grants the separatists of %s wide autonomy." % [n["short"], faction.get("home_name", "the province")])
		"zealots":
			for pid in pids:
				g.provinces[pid]["religion"] = faction.get("religion", g.provinces[pid]["religion"])
			g.post("Zealots have forced %s to follow the %s." % [faction.get("home_name", "the province"), faction.get("religion", "")])
		_:
			n["stability"] = maxi(-3, int(n["stability"]) - 1)
			n["treasury"] = maxf(0.0, float(n["treasury"]) * 0.85)
			for pid in pids:
				g.add_province_modifier(pid, "peasant_concessions", "Peasant concessions", {"local_tax_mod": -0.25,
					"local_unrest": -2}, 60)
			g.post("Peasant rebels have won concessions from %s." % n["short"])
	for pid in pids:
		g.provinces[pid]["rebel_progress"] = 0.0
		if g.provinces[pid]["controller"] == "REB":
			g.provinces[pid]["controller"] = g.provinces[pid]["owner"]
		g.province_changed.emit(pid)
	g.touch(target)
