extends RefCounted
## Rulers and heirs. Rulers age and die; heirs are born and inherit. With no heir a regency council
## rules (weak stats) until one is found. Ageless rulers (Napoleon) never age or die.

var g: Node


func _init(game: Node) -> void:
	g = game


func random_person(tag: String, age: int, quality: float = 0.0) -> Dictionary:
	var n: Dictionary = g.nations[tag]
	var names: Array = n.get("ruler_names", ["Heir"])
	var stats: Array = []
	for i in 3:
		stats.append(clampi(int(round(g.rng.randfn(2.5 + quality, 1.4))), 0, 6))
	var nm: String = names[g.rng.randi_range(0, names.size() - 1)] if names.size() > 0 else "Heir"
	var dyn: String = n["ruler"].get("dynasty", n["short"])
	return {"name": nm, "adm": stats[0], "dip": stats[1], "mil": stats[2], "age": age, "dynasty": dyn}


func ruler_stat(tag: String, i: int) -> int:
	var r: Dictionary = g.nations[tag]["ruler"]
	if r.get("regency", false):
		return 1
	return int(r.get(["adm", "dip", "mil"][i], 2))


func power_gain(tag: String) -> Array:
	var n: Dictionary = g.nations[tag]
	var out: Array = []
	var leg_pen = 1 if float(n.get("legitimacy", 50.0)) < 25.0 else 0
	for i in 3:
		var key: String = ["monthly_adm", "monthly_dip", "monthly_mil"][i]
		var adv: Dictionary = n.get("advisors", {}).get(g.TRACKS[i], {})
		var adv_skill = int(adv.get("skill", 0)) if not adv.is_empty() else 0
		out.append(maxi(1, 3 + ruler_stat(tag, i) + adv_skill + int(g.mods.nat(tag, key)) - leg_pen))
	return out


func gov_type(tag: String) -> String:
	return g.governments.get(g.nations[tag]["government"], {}).get("type", "monarchy")


func legitimacy_name(tag: String) -> String:
	match gov_type(tag):
		"republic": return "Republican tradition"
		"theocracy": return "Devotion"
		"horde", "tribe": return "Clan cohesion"
	return "Legitimacy"


func legitimacy_gain(tag: String) -> float:
	## Per year.
	var n: Dictionary = g.nations[tag]
	var gain = 1.0 + g.mods.nat(tag, "legitimacy_gain")
	if n["ruler"].get("regency", false):
		gain -= 2.0
	if int(n["stability"]) < 0:
		gain += float(n["stability"])
	return gain


func add_legitimacy(tag: String, amount: float) -> void:
	var n: Dictionary = g.nations[tag]
	n["legitimacy"] = clampf(float(n.get("legitimacy", 50.0)) + amount, 0.0, 100.0)


func monthly(tag: String) -> void:
	var n: Dictionary = g.nations[tag]
	add_legitimacy(tag, legitimacy_gain(tag) / 12.0)
	_advisors_monthly(tag)
	var gt = gov_type(tag)
	if gt == "republic":
		var term = int(g.governments.get(n["government"], {}).get("term_years", 4))
		if g.day_index - int(n.get("elected_day", 0)) >= term * 365:
			election(tag)
		return
	var r: Dictionary = n["ruler"]
	if g.month == 1:
		if not r.get("ageless", false):
			r["age"] = int(r.get("age", 30)) + 1
		if not n["heir"].is_empty():
			n["heir"]["age"] = int(n["heir"].get("age", 0)) + 1
	if r.get("regency", false):
		if not n["heir"].is_empty() and int(n["heir"]["age"]) >= 15:
			succeed(tag, "came of age")
		elif n["heir"].is_empty() and g.rng.randf() < 0.04:
			n["heir"] = random_person(tag, g.rng.randi_range(0, 4))
			if tag == g.player_tag:
				g.post("An heir has been found for the regency council: %s." % n["heir"]["name"])
		return
	if not r.get("ageless", false):
		var age = int(r.get("age", 30))
		var p = 0.0006 + maxf(0.0, age - 45.0) * 0.0005
		if g.rng.randf() < p:
			ruler_dies(tag)
			return
	if n["heir"].is_empty() and not r.get("ageless", false) and g.rng.randf() < 0.012:
		n["heir"] = random_person(tag, 0)
		if tag == g.player_tag:
			g.fire_event("heir_born", tag)
	elif not n["heir"].is_empty() and int(n["heir"]["age"]) < 15 and g.rng.randf() < 0.0008:
		var who: String = n["heir"]["name"]
		n["heir"] = {}
		if tag == g.player_tag:
			g.post("Tragedy: the heir %s has died." % who)


func election(tag: String) -> void:
	var n: Dictionary = g.nations[tag]
	var old: Dictionary = n["ruler"]
	var re_elect = g.rng.randf() < 0.3 and int(old.get("age", 50)) < 70
	if not re_elect:
		n["ruler"] = random_person(tag, g.rng.randi_range(35, 60), 0.3)
		n["ruler"]["dynasty"] = String(g.nations[tag]["ruler_names"][g.rng.randi_range(0, maxi(0, n["ruler_names"].size() - 1))]) if n["ruler_names"].size() > 0 else ""
	n["elected_day"] = g.day_index
	add_legitimacy(tag, 10.0 if re_elect else 5.0)
	if re_elect:
		g.post("%s: %s is re-elected." % [n["short"], old.get("name", "")])
	else:
		g.post("%s: %s is elected to lead the %s." % [n["short"], n["ruler"]["name"], g.governments.get(n["government"], {}).get("rank", "republic").to_lower()])
	if tag == g.player_tag:
		g.fire_event("republic_election", tag)
	g.touch(tag)


func ruler_dies(tag: String) -> void:
	var n: Dictionary = g.nations[tag]
	var old: String = n["ruler"].get("name", "The ruler")
	g.post("%s: %s has died at %d." % [n["short"], old, int(n["ruler"].get("age", 0))])
	if gov_type(tag) in ["republic", "theocracy"]:
		n["ruler"] = random_person(tag, g.rng.randi_range(30, 55), 0.3)
		n["elected_day"] = g.day_index
		add_legitimacy(tag, -10.0)
		g.post("%s chooses %s as its new leader." % [n["short"], n["ruler"]["name"]])
		g.touch(tag)
		return
	add_legitimacy(tag, -10.0)
	if n["heir"].is_empty():
		n["ruler"] = {"name": "Regency Council", "adm": 1, "dip": 1, "mil": 1, "age": 0, "regency": true,
			"dynasty": n["ruler"].get("dynasty", "")}
		n["stability"] = maxi(-3, int(n["stability"]) - 1)
		n["legitimacy"] = minf(float(n["legitimacy"]), 40.0)
		if tag == g.player_tag:
			g.fire_event("regency_council", tag)
	elif int(n["heir"].get("age", 0)) < 15:
		n["ruler"] = {"name": "Regency Council", "adm": 1, "dip": 1, "mil": 1, "age": 0, "regency": true,
			"dynasty": n["ruler"].get("dynasty", "")}
		g.post("%s is too young to rule; a regency council governs until they come of age." % n["heir"]["name"])
	else:
		succeed(tag, "succeeded")
	g.touch(tag)


func succeed(tag: String, how: String) -> void:
	var n: Dictionary = g.nations[tag]
	if n["heir"].is_empty():
		return
	n["ruler"] = n["heir"]
	n["heir"] = {}
	n["legitimacy"] = clampf(50.0 + 5.0 * (int(n["ruler"].get("adm", 2)) + int(n["ruler"].get("dip", 2))), 40.0, 90.0)
	g.post("%s: %s has %s to the throne." % [n["short"], n["ruler"]["name"], how])
	if tag == g.player_tag:
		g.fire_event("new_ruler", tag)
	g.touch(tag)


func describe(p: Dictionary, power_names: Array) -> String:
	if p.is_empty():
		return "None"
	if p.get("regency", false):
		return "Regency Council (1 / 1 / 1)"
	var age = "ageless" if p.get("ageless", false) else "age %d" % int(p.get("age", 0))
	return "%s %s (%s): %s %d, %s %d, %s %d" % [p.get("name", "?"), p.get("dynasty", ""), age,
		power_names[0], int(p.get("adm", 0)), power_names[1], int(p.get("dip", 0)), power_names[2], int(p.get("mil", 0))]


# ---------------------------------------------------------------- stability and war exhaustion

func stability_cost(tag: String) -> int:
	var st: int = int(g.nations[tag]["stability"])
	return maxi(20, int(round((100.0 + maxi(0, st) * 25.0) * maxf(0.3, 1.0 + g.mods.nat(tag, "stability_cost_mod")))))


func can_raise_stability(tag: String) -> String:
	var n: Dictionary = g.nations[tag]
	if int(n["stability"]) >= 3:
		return "Stability is already at its highest."
	var c = stability_cost(tag)
	if int(n["power"][0]) < c:
		return "Needs %d %s power." % [c, n["power_names"][0]]
	return ""


func raise_stability(tag: String) -> bool:
	if can_raise_stability(tag) != "":
		return false
	var n: Dictionary = g.nations[tag]
	n["power"][0] -= stability_cost(tag)
	n["stability"] = int(n["stability"]) + 1
	g.touch(tag)
	return true


func can_reduce_we(tag: String) -> String:
	var n: Dictionary = g.nations[tag]
	if float(n["war_exhaustion"]) < 0.1:
		return "No war exhaustion."
	if int(n["power"][1]) < 50:
		return "Needs 50 %s power." % n["power_names"][1]
	return ""


func reduce_we(tag: String) -> bool:
	if can_reduce_we(tag) != "":
		return false
	var n: Dictionary = g.nations[tag]
	n["power"][1] -= 50
	n["war_exhaustion"] = maxf(0.0, float(n["war_exhaustion"]) - 2.0)
	g.touch(tag)
	return true


# ---------------------------------------------------------------- advisors

func advisor_cost(tag: String, skill: int) -> int:
	var scale = 1.0 + g.nation_dev(tag) / 200.0
	return int(round(float(g.advisor_data.get("hire_cost", 40)) * skill * skill * scale))


func advisor_salary(tag: String, skill: int) -> float:
	var scale = 1.0 + g.nation_dev(tag) / 300.0
	return float(g.advisor_data.get("salary", 0.6)) * skill * skill * scale


func salaries(tag: String) -> float:
	var t = 0.0
	for k in g.nations[tag].get("advisors", {}):
		var a: Dictionary = g.nations[tag]["advisors"][k]
		if not a.is_empty():
			t += advisor_salary(tag, int(a["skill"]))
	return t


func _new_candidate(tag: String, power: String) -> Dictionary:
	var types: Array = []
	for k in g.advisor_data.get("types", {}):
		if g.advisor_data["types"][k]["power"] == power:
			types.append(k)
	var n: Dictionary = g.nations[tag]
	var names: Array = n.get("ruler_names", ["Advisor"])
	var roll = g.rng.randf()
	var skill = 3 if roll > 0.88 else (2 if roll > 0.55 else 1)
	g.next_id += 1
	return {"id": g.next_id, "type": types[g.rng.randi_range(0, types.size() - 1)], "skill": skill, "power": power,
		"name": "%s %s" % [names[g.rng.randi_range(0, names.size() - 1)] if names.size() > 0 else "Advisor", ["the Elder", "of the Sty", "the Wise", "Truffleseeker", "Ironsnout", "the Younger", "of the Haze", "Brightmud"][g.rng.randi_range(0, 7)]]}


func refill_pool(tag: String) -> void:
	var n: Dictionary = g.nations[tag]
	if not n.has("advisor_pool"):
		n["advisor_pool"] = []
	for power in g.TRACKS:
		var count = 0
		for c in n["advisor_pool"]:
			if c["power"] == power:
				count += 1
		while count < int(g.advisor_data.get("candidates_per_type", 3)):
			n["advisor_pool"].append(_new_candidate(tag, power))
			count += 1


func _advisors_monthly(tag: String) -> void:
	var n: Dictionary = g.nations[tag]
	if not n.has("advisor_pool"):
		refill_pool(tag)
	if g.rng.randf() < 0.08 and n["advisor_pool"].size() > 0:
		n["advisor_pool"].remove_at(g.rng.randi_range(0, n["advisor_pool"].size() - 1))
		refill_pool(tag)
	for k in n.get("advisors", {}):
		var a: Dictionary = n["advisors"][k]
		if not a.is_empty() and g.rng.randf() < 0.004:
			if tag == g.player_tag:
				g.post("Your advisor %s has retired." % a["name"])
			n["advisors"][k] = {}


func can_hire(tag: String, cand_id: int) -> String:
	var n: Dictionary = g.nations[tag]
	for c in n.get("advisor_pool", []):
		if int(c["id"]) == cand_id:
			var cost = advisor_cost(tag, int(c["skill"]))
			if float(n["treasury"]) < cost:
				return "Needs %d sanctum." % cost
			return ""
	return "No such candidate."


func hire(tag: String, cand_id: int) -> bool:
	if can_hire(tag, cand_id) != "":
		return false
	var n: Dictionary = g.nations[tag]
	for c in n["advisor_pool"]:
		if int(c["id"]) == cand_id:
			n["treasury"] -= advisor_cost(tag, int(c["skill"]))
			n["advisors"][c["power"]] = c
			n["advisor_pool"].erase(c)
			refill_pool(tag)
			if tag == g.player_tag:
				g.post("Hired %s, %s (skill %d)." % [c["name"], g.advisor_data["types"][c["type"]]["name"], int(c["skill"])])
			g.touch(tag)
			return true
	return false


func dismiss(tag: String, power: String) -> void:
	g.nations[tag]["advisors"][power] = {}
	g.touch(tag)
