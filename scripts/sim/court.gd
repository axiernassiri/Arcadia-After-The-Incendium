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
	var out: Array = []
	for i in 3:
		var key: String = ["monthly_adm", "monthly_dip", "monthly_mil"][i]
		out.append(3 + ruler_stat(tag, i) + int(g.mods.nat(tag, key)))
	return out


func monthly(tag: String) -> void:
	var n: Dictionary = g.nations[tag]
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


func ruler_dies(tag: String) -> void:
	var n: Dictionary = g.nations[tag]
	var old: String = n["ruler"].get("name", "The ruler")
	g.post("%s: %s has died at %d." % [n["short"], old, int(n["ruler"].get("age", 0))])
	if n["heir"].is_empty():
		n["ruler"] = {"name": "Regency Council", "adm": 1, "dip": 1, "mil": 1, "age": 0, "regency": true,
			"dynasty": n["ruler"].get("dynasty", "")}
		n["stability"] = maxi(-3, int(n["stability"]) - 1)
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
