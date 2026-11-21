extends RefCounted
## Technology (three tracks), idea groups and national ideas, and government reforms.

var g: Node


func _init(game: Node) -> void:
	g = game


# ---------------------------------------------------------------- technology

func level_info(track: String, level: int) -> Dictionary:
	for t in g.tech_data.get(track, []):
		if int(t["level"]) == level:
			return t
	return {}


func max_level(track: String) -> int:
	return g.tech_data.get(track, []).size()


func tech_cost(tag: String, track: String) -> int:
	var lvl: int = int(g.nations[tag]["tech"][g.TRACKS.find(track)]) + 1
	var info = level_info(track, lvl)
	var cost = float(g.tech_base_cost + g.tech_per_level * lvl)
	var mult = 1.0 + g.mods.nat(tag, "tech_cost_mod")
	var early = int(info.get("year", g.year)) - g.year
	if early > 0:
		mult += 0.05 * early
	return maxi(20, int(round(cost * maxf(0.3, mult))))


func can_research(tag: String, track: String) -> String:
	var i: int = g.TRACKS.find(track)
	var n: Dictionary = g.nations[tag]
	if int(n["tech"][i]) >= max_level(track):
		return "All %s technology researched." % track
	var c = tech_cost(tag, track)
	if n["power"][i] < c:
		return "Needs %d %s power." % [c, n["power_names"][i]]
	return ""


func research(tag: String, track: String) -> bool:
	if can_research(tag, track) != "":
		return false
	var i: int = g.TRACKS.find(track)
	var n: Dictionary = g.nations[tag]
	n["power"][i] -= tech_cost(tag, track)
	n["tech"][i] += 1
	if tag == g.player_tag:
		g.post("Researched %s: %s." % [track.to_upper(), level_info(track, n["tech"][i]).get("name", "")])
	g.touch(tag)
	return true


func unlock_text(info: Dictionary, tag: String) -> String:
	var parts: PackedStringArray = []
	if info.has("modifiers"):
		parts.append(g.mods.describe(info["modifiers"], g.nations[tag]["power_names"]))
	for b in info.get("buildings", []):
		parts.append("Building: " + g.building_data.get(b, {}).get("name", b))
	for s in info.get("ships", []):
		parts.append("Ship: " + g.unit_data["ships"].get(s, {}).get("name", s))
	if info.has("units"):
		parts.append("Land units: " + String(info["units"]))
	if info.get("idea_slot", false):
		parts.append("+1 idea slot")
	if info.has("fort_level"):
		parts.append("Forts level %d" % int(info["fort_level"]))
	return "; ".join(parts)


func fort_tech_level(tag: String) -> int:
	var lvl = 0
	var mil: int = int(g.nations[tag]["tech"][2])
	for t in g.tech_data.get("mil", []):
		if int(t["level"]) <= mil and t.has("fort_level"):
			lvl = maxi(lvl, int(t["fort_level"]))
	return maxi(1, lvl)


func unit_tier_name(tag: String) -> String:
	var mil: int = int(g.nations[tag]["tech"][2])
	var name = "Militia"
	for t in g.tech_data.get("mil", []):
		if int(t["level"]) <= mil and t.has("units"):
			name = t["units"]
	return name


func ship_unlocked(tag: String, ship: String) -> bool:
	var dip: int = int(g.nations[tag]["tech"][1])
	for t in g.tech_data.get("dip", []):
		if int(t["level"]) <= dip and ship in t.get("ships", []):
			return true
	return false


func land_unit_unlocked(tag: String, utype: String) -> bool:
	return int(g.nations[tag]["tech"][2]) >= int(g.unit_data["land"][utype].get("tech", 1))


# ---------------------------------------------------------------- ideas

func idea_slots(tag: String) -> int:
	var adm: int = int(g.nations[tag]["tech"][0])
	var slots = 0
	for t in g.tech_data.get("adm", []):
		if int(t["level"]) <= adm and t.get("idea_slot", false):
			slots += 1
	return slots


func ideas_taken(tag: String) -> int:
	var c = 0
	for ig in g.nations[tag]["idea_groups"]:
		c += int(ig["taken"])
	return c


func national_ideas_unlocked(tag: String) -> int:
	return mini(7, int(ideas_taken(tag) / 3))


func idea_cost(tag: String) -> int:
	return maxi(20, int(round(float(g.idea_data.get("idea_cost", 150)) * maxf(0.3, 1.0 + g.mods.nat(tag, "idea_cost_mod")))))


func can_pick_group(tag: String, gid: String) -> String:
	var n: Dictionary = g.nations[tag]
	for ig in n["idea_groups"]:
		if ig["id"] == gid:
			return "Already chosen."
	if n["idea_groups"].size() >= idea_slots(tag):
		return "No free idea slot. More slots come with administrative technology."
	return ""


func pick_group(tag: String, gid: String) -> bool:
	if can_pick_group(tag, gid) != "":
		return false
	g.nations[tag]["idea_groups"].append({"id": gid, "taken": 0})
	g.touch(tag)
	return true


func can_take_idea(tag: String, gid: String) -> String:
	var grp: Dictionary = g.idea_data["groups"].get(gid, {})
	var i: int = g.TRACKS.find(grp.get("type", "adm"))
	for ig in g.nations[tag]["idea_groups"]:
		if ig["id"] == gid:
			if int(ig["taken"]) >= grp["ideas"].size():
				return "Group complete."
			var c = idea_cost(tag)
			if g.nations[tag]["power"][i] < c:
				return "Needs %d %s power." % [c, g.nations[tag]["power_names"][i]]
			return ""
	return "Pick this group first."


func take_idea(tag: String, gid: String) -> bool:
	if can_take_idea(tag, gid) != "":
		return false
	var grp: Dictionary = g.idea_data["groups"][gid]
	var i: int = g.TRACKS.find(grp["type"])
	g.nations[tag]["power"][i] -= idea_cost(tag)
	for ig in g.nations[tag]["idea_groups"]:
		if ig["id"] == gid:
			ig["taken"] = int(ig["taken"]) + 1
			if tag == g.player_tag:
				g.post("Adopted the idea: %s." % grp["ideas"][int(ig["taken"]) - 1][0])
	g.touch(tag)
	return true


# ---------------------------------------------------------------- government reforms

func government(tag: String) -> Dictionary:
	return g.governments.get(g.nations[tag]["government"], {})


func reform_cost(tier: int) -> int:
	return g.reform_cost_per_tier * (tier + 1)


func can_enact(tag: String, tier: int, rid: String) -> String:
	var n: Dictionary = g.nations[tag]
	var tiers: Array = government(tag).get("tiers", [])
	if tier >= tiers.size():
		return "No such tier."
	if tier > n["reforms"].size():
		return "Enact a reform in the tier before first."
	if tier < n["reforms"].size() and n["reforms"][tier] == rid:
		return "Already enacted."
	var cost = reform_cost(tier)
	if tier < n["reforms"].size():
		cost = int(cost / 2)
	if float(n["reform_progress"]) < cost:
		return "Needs %d reform progress." % cost
	return ""


func enact(tag: String, tier: int, rid: String) -> bool:
	if can_enact(tag, tier, rid) != "":
		return false
	var n: Dictionary = g.nations[tag]
	var cost = reform_cost(tier)
	if tier < n["reforms"].size():
		n["reforms"][tier] = rid
		cost = int(cost / 2)
	else:
		n["reforms"].append(rid)
	n["reform_progress"] = float(n["reform_progress"]) - cost
	if tag == g.player_tag:
		g.post("Government reform enacted: %s." % reform_name(tag, rid))
	g.touch(tag)
	return true


func reform_name(tag: String, rid: String) -> String:
	for t in government(tag).get("tiers", []):
		for r in t["reforms"]:
			if r["id"] == rid:
				return r["name"]
	return rid


func reform_gain(tag: String) -> float:
	return 0.6 + g.nation_dev(tag) / 300.0


func monthly(tag: String) -> void:
	var n: Dictionary = g.nations[tag]
	n["reform_progress"] = minf(500.0, float(n["reform_progress"]) + reform_gain(tag))
