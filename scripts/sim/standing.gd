extends RefCounted
## A nation's standing, like EU4: prestige, the Great Power ranking, and its three estates
## (data/estates.json) with their loyalty, influence and privileges. Old saves without these fields get
## the defaults the first time they are read.

const PRESTIGE_DECAY := 0.05      # a year, toward zero
const GREAT_POWERS := 5
const SUPPORT_COOLDOWN := 3650    # days: call on each estate once every ten years
const DISRUPT_COOLDOWN := 730

var g: Node
var ranking: Array = []           # tags, best first (recomputed monthly)


func _init(game: Node) -> void:
	g = game


# ---------------------------------------------------------------- prestige and great powers

func prestige(tag: String) -> float:
	return float(g.nations.get(tag, {}).get("prestige", 0.0))


func add_prestige(tag: String, amount: float) -> void:
	if not g.nations.has(tag) or g.mil.special(tag):
		return
	g.nations[tag]["prestige"] = clampf(prestige(tag) + amount, -100.0, 100.0)
	g.mods.invalidate(tag)


func power_score(tag: String) -> float:
	## What the Great Power ranking sorts by: development, prestige and army.
	return float(g.nation_dev(tag)) + prestige(tag) * 0.5 + float(g.mil.regiment_count(tag)) * 2.0


func update_ranking() -> void:
	var tags: Array = []
	for t in g.nations:
		if g.nations[t]["alive"] and not g.mil.special(t):
			tags.append(t)
	tags.sort_custom(func(a, b): return power_score(a) > power_score(b))
	ranking = tags


func rank(tag: String) -> int:
	## 1-based place in the ranking (0 if unranked).
	if ranking.is_empty():
		update_ranking()
	return ranking.find(tag) + 1


func is_great_power(tag: String) -> bool:
	var r := rank(tag)
	return r >= 1 and r <= GREAT_POWERS


# ---------------------------------------------------------------- estates

func estate_defs() -> Dictionary:
	return g.estate_data.get("estates", {})


func estates(tag: String) -> Dictionary:
	var n: Dictionary = g.nations[tag]
	if not n.has("estates"):
		var e := {}
		for k in estate_defs():
			e[k] = {"loyalty": 50.0, "privilege": false, "support_day": -SUPPORT_COOLDOWN, "low_months": 0}
		n["estates"] = e
		n["estate_disrupt_day"] = -DISRUPT_COOLDOWN
	return n["estates"]


func influence(tag: String, key: String) -> float:
	return 20.0 + (35.0 if estates(tag)[key]["privilege"] else 0.0)


func loyalty(tag: String, key: String) -> float:
	return float(estates(tag)[key]["loyalty"])


func estate_modifier_sources(tag: String) -> Array:
	## [name, modifiers] pairs for modifiers.gd: loyal bonuses, disloyal penalties, granted privileges.
	var out: Array = []
	if not g.nations.has(tag) or g.mil.special(tag):
		return out
	var defs := estate_defs()
	for k in defs:
		var d: Dictionary = defs[k]
		var e: Dictionary = estates(tag)[k]
		var loy := float(e["loyalty"])
		if loy >= 60.0:
			out.append(["%s (loyal)" % d["name"], d.get("bonus", {})])
		elif loy < 30.0:
			out.append(["%s (disloyal)" % d["name"], d.get("malus", {})])
		if e["privilege"]:
			out.append(["Privilege: %s" % d["privilege"]["name"], d["privilege"].get("modifiers", {})])
	return out


func can_grant(tag: String, key: String) -> String:
	if estates(tag)[key]["privilege"]:
		return "Already granted."
	return ""


func grant(tag: String, key: String) -> bool:
	if can_grant(tag, key) != "":
		return false
	var e: Dictionary = estates(tag)[key]
	e["privilege"] = true
	e["loyalty"] = minf(100.0, float(e["loyalty"]) + 15.0)
	g.mods.invalidate(tag)
	g.touch(tag)
	return true


func can_revoke(tag: String, key: String) -> String:
	if not estates(tag)[key]["privilege"]:
		return "They hold no privilege."
	if int(g.nations[tag]["power"][0]) < 50:
		return "Needs 50 %s." % g.nations[tag]["power_names"][0]
	return ""


func revoke(tag: String, key: String) -> bool:
	if can_revoke(tag, key) != "":
		return false
	var e: Dictionary = estates(tag)[key]
	e["privilege"] = false
	e["loyalty"] = maxf(0.0, float(e["loyalty"]) - 20.0)
	g.nations[tag]["power"][0] = int(g.nations[tag]["power"][0]) - 50
	g.mods.invalidate(tag)
	g.touch(tag)
	return true


func can_call(tag: String, key: String) -> String:
	var e: Dictionary = estates(tag)[key]
	var wait: int = int(e["support_day"]) + SUPPORT_COOLDOWN - g.day_index
	if wait > 0:
		return "They answered recently: again in %d years." % int(ceil(wait / 365.0))
	if float(e["loyalty"]) < 40.0:
		return "They won't help while their loyalty is under 40."
	return ""


func call_support(tag: String, key: String) -> bool:
	if can_call(tag, key) != "":
		return false
	var d: Dictionary = estate_defs()[key]["support"]
	var n: Dictionary = g.nations[tag]
	var e: Dictionary = estates(tag)[key]
	if d.has("stability"):
		n["stability"] = mini(3, int(n["stability"]) + int(d["stability"]))
	if d.has("income_months"):
		n["treasury"] = float(n["treasury"]) + maxf(5.0, float(n.get("last_income", 0.0))) * float(d["income_months"])
	if d.has("manpower_share"):
		n["manpower"] = int(n["manpower"]) + int(g.eco.max_manpower(tag) * float(d["manpower_share"]))
	e["support_day"] = g.day_index
	e["loyalty"] = maxf(0.0, float(e["loyalty"]) - 15.0)
	g.mods.invalidate(tag)
	g.touch(tag)
	return true


# ---------------------------------------------------------------- monthly

func monthly() -> void:
	for tag in g.nations:
		var n: Dictionary = g.nations[tag]
		if not n["alive"] or g.mil.special(tag):
			continue
		# prestige fades toward zero
		var p := prestige(tag)
		if p != 0.0:
			n["prestige"] = p * (1.0 - PRESTIGE_DECAY / 12.0)
		# estates drift toward their resting loyalty
		for k in estates(tag):
			var e: Dictionary = estates(tag)[k]
			var target := 50.0 + (15.0 if e["privilege"] else 0.0) + float(n["stability"]) * 3.0
			var loy := float(e["loyalty"])
			e["loyalty"] = loy + clampf(target - loy, -1.0, 1.0)
			if influence(tag, k) >= 50.0 and float(e["loyalty"]) < 30.0:
				e["low_months"] = int(e.get("low_months", 0)) + 1
			else:
				e["low_months"] = 0
			if int(e["low_months"]) >= 6 and g.day_index - int(n.get("estate_disrupt_day", -DISRUPT_COOLDOWN)) >= DISRUPT_COOLDOWN:
				n["estate_disrupt_day"] = g.day_index
				n["stability"] = maxi(-3, int(n["stability"]) - 1)
				g.post("%s: %s, powerful and angry, throw the realm into disorder (stability -1)." % [n["short"], estate_defs()[k]["name"]],
					[tag], "Estate Unrest" if tag == g.player_tag else "")
		if n["ai"]:
			_ai(tag)
		if not g.age_data.is_empty():
			_monthly_age(tag)
	if not g.age_data.is_empty():
		_check_new_age()
	update_ranking()
	g.mods.invalidate()


func _ai(tag: String) -> void:
	var n: Dictionary = g.nations[tag]
	for k in estates(tag):
		var loy := loyalty(tag, k)
		if loy < 35.0 and can_grant(tag, k) == "":
			grant(tag, k)
		elif can_call(tag, k) == "" and loy > 60.0:
			var d: Dictionary = estate_defs()[k]["support"]
			var need: bool = (d.has("stability") and int(n["stability"]) < 0) or (d.has("income_months") and float(n["treasury"]) < 0.0) \
				or (d.has("manpower_share") and int(n["manpower"]) < g.eco.max_manpower(tag) / 5)
			if need:
				call_support(tag, k)


# ---------------------------------------------------------------- ages (data/ages.json)

func ages() -> Array:
	return g.age_data.get("ages", [])


func current_age() -> Dictionary:
	for a in ages():
		if g.year >= int(a["start"]) and g.year < int(a["end"]):
			return a
	return ages().back() if ages().size() > 0 else {}


func splendor(tag: String) -> float:
	return float(g.nations.get(tag, {}).get("splendor", 0.0))


func objective_done(tag: String, age_id: String, obj_id: String) -> bool:
	return g.nations[tag].get("age_objectives", {}).has(age_id + "|" + obj_id)


func ability_taken(tag: String, age_id: String, ab_id: String) -> bool:
	return g.nations[tag].get("age_abilities", {}).has(age_id + "|" + ab_id)


func can_take_ability(tag: String, ab_id: String) -> String:
	var age := current_age()
	if age.is_empty():
		return "No age."
	if ability_taken(tag, age["id"], ab_id):
		return "Already taken this age."
	var cost := float(g.age_data.get("ability_cost", 600))
	if splendor(tag) < cost:
		return "Needs %d splendor (you have %d)." % [int(cost), int(splendor(tag))]
	return ""


func take_ability(tag: String, ab_id: String) -> bool:
	if can_take_ability(tag, ab_id) != "":
		return false
	var n: Dictionary = g.nations[tag]
	n["splendor"] = splendor(tag) - float(g.age_data.get("ability_cost", 600))
	if not n.has("age_abilities"):
		n["age_abilities"] = {}
	n["age_abilities"][current_age()["id"] + "|" + ab_id] = true
	g.mods.invalidate(tag)
	g.touch(tag)
	return true


func age_modifier_sources(tag: String) -> Array:
	## Abilities of the current age (they lapse when it ends).
	var out: Array = []
	var age := current_age()
	if age.is_empty() or not g.nations.has(tag):
		return out
	for ab in age.get("abilities", []):
		if ability_taken(tag, age["id"], ab["id"]):
			out.append(["%s: %s" % [age["name"], ab["name"]], ab.get("modifiers", {})])
	return out


func _monthly_age(tag: String) -> void:
	var n: Dictionary = g.nations[tag]
	var age := current_age()
	if age.is_empty():
		return
	var gain := float(g.age_data.get("monthly_splendor", 2))
	if is_great_power(tag):
		gain += float(g.age_data.get("great_power_bonus", 1))
	n["splendor"] = splendor(tag) + gain
	if not n.has("age_objectives"):
		n["age_objectives"] = {}
	for o in age.get("objectives", []):
		var key: String = age["id"] + "|" + o["id"]
		if n["age_objectives"].has(key):
			continue
		if g.check_conditions(o.get("conditions", []), tag):
			n["age_objectives"][key] = true
			n["splendor"] = splendor(tag) + float(g.age_data.get("objective_splendor", 200))
			if tag == g.player_tag:
				g.post("%s objective fulfilled: %s (+%d splendor)." % [age["name"], o["name"], int(g.age_data.get("objective_splendor", 200))])
	if n["ai"]:
		for ab in age.get("abilities", []):
			if take_ability(tag, ab["id"]):
				break


func _check_new_age() -> void:
	var age := current_age()
	if age.is_empty():
		return
	if g.global_flags.get("age", "") != age["id"]:
		var first: bool = not g.global_flags.has("age")
		g.global_flags["age"] = age["id"]
		if not first:
			g.post("%s begins. %s" % [age["name"], age.get("text", "")], [], "A New Age")
		g.mods.invalidate()
