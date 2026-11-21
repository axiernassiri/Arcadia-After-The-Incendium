extends RefCounted
## The economy, in sanctum: tax, production and trade income; army, navy, fort, administration,
## colony and interest expenses; loans and bankruptcy; market prices; development; buildings;
## colonisation of empty land.

const LOAN_RATE := 0.05          # yearly interest
const MAX_LOANS := 10
const COLONY_COST := 80.0
const COLONY_UPKEEP := 1.5
const TAX_PER_DEV := 0.75          # sanctum a year per tax development
const GOODS_PER_DEV := 0.15        # goods a year per production development
const EARLY_ERA_END := 4339        # until then provinces drift toward autonomy
const AUTONOMY_DRIFT_CAP := 60.0
const MISSIONARY_UPKEEP := 0.5

var g: Node
var market = {}                 # goods -> {"mult": float, "history": [float], "baseline": float}
var history = {}                # tag -> [treasury at each month end] (last 36)


func _init(game: Node) -> void:
	g = game


func reset() -> void:
	market.clear()
	history.clear()
	var supply = world_supply()
	for k in g.goods:
		market[k] = {"mult": 1.0, "history": [], "baseline": maxf(float(supply.get(k, 0.0)), 0.5)}


# ---------------------------------------------------------------- prices and goods

func price(goods_id: String) -> float:
	var base = float(g.goods.get(goods_id, {}).get("price", 0.0))
	return base * float(market.get(goods_id, {}).get("mult", 1.0))


func goods_produced(pid: int) -> float:
	var p: Dictionary = g.provinces[pid]
	if p["owner"] == "":
		return 0.0
	return GOODS_PER_DEV * float(p["dev"][1]) * (1.0 + g.mods.loc(pid, "local_production_mod"))


func goods_value(pid: int) -> float:
	## Yearly value of the goods a province makes (also its trade value).
	return goods_produced(pid) * price(g.provinces[pid]["goods"])


func world_supply() -> Dictionary:
	var s = {}
	for pid in g.provinces:
		var k: String = g.provinces[pid]["goods"]
		s[k] = float(s.get(k, 0.0)) + goods_produced(pid)
	return s


func update_prices() -> void:
	var supply = world_supply()
	for k in market:
		var m: Dictionary = market[k]
		var vol = float(g.goods.get(k, {}).get("volatility", 0.04))
		var target = clampf(pow(float(m["baseline"]) / maxf(float(supply.get(k, 0.0)), 0.25), 0.25), 0.6, 1.6)
		var mult = float(m["mult"])
		mult += (target - mult) * 0.08 + g.rng.randfn(0.0, vol)
		m["mult"] = clampf(mult, 0.4, 2.5)
		m["history"].append(price(k))
		if m["history"].size() > 36:
			m["history"].pop_front()


func shock_price(goods_id: String, factor: float) -> void:
	if market.has(goods_id):
		market[goods_id]["mult"] = clampf(float(market[goods_id]["mult"]) * factor, 0.4, 2.5)


# ---------------------------------------------------------------- province output

func core_factor(tag: String, pid: int) -> float:
	return 1.0 if g.provinces[pid]["cores"].has(tag) else 0.35


func occupation_factor(pid: int) -> float:
	var p: Dictionary = g.provinces[pid]
	if p["controller"] != p["owner"]:
		return 0.0
	if g.mil.is_blockaded(pid):
		return 0.5
	return 1.0


func province_tax(pid: int) -> float:
	## Yearly tax.
	var p: Dictionary = g.provinces[pid]
	var tag: String = p["owner"]
	if tag == "":
		return 0.0
	var mult = 1.0 + g.mods.nat(tag, "tax_mod") + g.mods.loc(pid, "local_tax_mod")
	mult -= 0.02 * maxf(0.0, float(p.get("unrest", 0.0)))
	return maxf(0.0, TAX_PER_DEV * float(p["dev"][0]) * mult * core_factor(tag, pid) * occupation_factor(pid) * autonomy_factor(pid))


func province_production(pid: int) -> float:
	## Yearly production income.
	var p: Dictionary = g.provinces[pid]
	var tag: String = p["owner"]
	if tag == "":
		return 0.0
	var mult = 1.0 + g.mods.nat(tag, "production_mod")
	return maxf(0.0, goods_value(pid) * mult * core_factor(tag, pid) * occupation_factor(pid) * autonomy_factor(pid))


func province_manpower(pid: int) -> float:
	## Men a year (max manpower contribution).
	var p: Dictionary = g.provinces[pid]
	var tag: String = p["owner"]
	if tag == "":
		return 0.0
	var mult = 1.0 + g.mods.nat(tag, "manpower_mod") + g.mods.loc(pid, "local_manpower_mod")
	return float(p["dev"][2]) * 200.0 * maxf(0.1, mult) * core_factor(tag, pid) * (1.0 - 0.75 * autonomy(pid) / 100.0)


func max_manpower(tag: String) -> int:
	var t = 3000.0
	for pid in g.owned(tag):
		t += province_manpower(pid)
	return int(t)


# ---------------------------------------------------------------- monthly budget

func budget(tag: String) -> Dictionary:
	## Monthly income and expenses, itemised.
	var n: Dictionary = g.nations[tag]
	var tax = 0.0
	var prod = 0.0
	var dev = 0
	var forts = 0.0
	var owned: Array = g.owned(tag)
	for pid in owned:
		tax += province_tax(pid)
		prod += province_production(pid)
		dev += g.total_dev(pid)
		for b in g.provinces[pid]["buildings"]:
			if b == "fort" and pid == g.capital_of(tag):
				continue   # the capital's walls are paid for
			forts += float(g.building_data.get(b, {}).get("upkeep", 0.0))
	tax /= 12.0
	prod /= 12.0
	var trade = float(g.trade.income.get(tag, 0.0))
	var subjects = 0.0
	for s in n["subjects"]:
		if g.nations.has(s) and g.nations[s]["alive"]:
			subjects += 0.10 * float(g.nations[s].get("last_income", 0.0))
	var army = g.mil.land_maintenance(tag)
	var navy = g.mil.naval_maintenance(tag)
	var admin = 0.008 * dev
	var mines = 0.0
	for pid in owned:
		mines += mine_income(pid)
	var advisors = g.court.salaries(tag)
	var colonies = 0.0
	var missions_cost = 0.0
	for pid in g.provinces:
		var p: Dictionary = g.provinces[pid]
		if p["colony"].get("tag", "") == tag:
			colonies += COLONY_UPKEEP
		if p["conversion"].get("tag", "") == tag:
			missions_cost += MISSIONARY_UPKEEP
	var interest = 0.0
	var rate = loan_rate(tag)
	for l in n["loans"]:
		interest += float(l) * rate / 12.0
	var overlord = 0.0
	if n["overlord"] != "":
		overlord = 0.10 * (tax + prod + trade)
	var income = tax + prod + trade + subjects + mines
	var expenses = army + navy + forts + admin + colonies + missions_cost + interest + overlord + advisors
	return {
		"tax": tax, "production": prod, "trade": trade, "subjects": subjects, "mines": mines, "advisors": advisors, "income": income,
		"army": army, "navy": navy, "forts": forts, "admin": admin, "colonies": colonies,
		"missionaries": missions_cost, "interest": interest, "overlord": overlord, "expenses": expenses,
		"balance": income - expenses,
	}


func loan_rate(tag: String) -> float:
	return maxf(0.005, LOAN_RATE + g.mods.nat(tag, "interest_mod"))


func loan_size(tag: String) -> int:
	return int(round((50.0 + g.nation_dev(tag) * 0.4) / 10.0) * 10.0)


func take_loan(tag: String) -> bool:
	var n: Dictionary = g.nations[tag]
	if n["loans"].size() >= MAX_LOANS:
		return false
	var amount = loan_size(tag)
	n["loans"].append(amount)
	n["treasury"] += amount
	if tag == g.player_tag:
		g.post("Took a loan of %d sanctum at %.1f%% a year." % [amount, loan_rate(tag) * 100.0])
	g.touch(tag)
	return true


func repay_loan(tag: String) -> bool:
	var n: Dictionary = g.nations[tag]
	if n["loans"].is_empty() or n["treasury"] < float(n["loans"][0]):
		return false
	n["treasury"] -= float(n["loans"][0])
	n["loans"].pop_front()
	g.touch(tag)
	return true


func monthly(tag: String) -> void:
	var n: Dictionary = g.nations[tag]
	var b = budget(tag)
	n["treasury"] += b["balance"]
	n["last_income"] = b["income"]
	n["last_balance"] = b["balance"]
	if n["overlord"] != "" and g.nations.has(n["overlord"]):
		g.nations[n["overlord"]]["treasury"] += b["overlord"]
	if n["treasury"] < 0.0:
		if n["loans"].size() >= MAX_LOANS:
			bankruptcy(tag)
		else:
			while n["treasury"] < 0.0 and n["loans"].size() < MAX_LOANS:
				take_loan(tag)
	# manpower regrows over about ten years
	var mx = max_manpower(tag)
	n["max_manpower"] = mx
	n["manpower"] = mini(int(n["manpower"]) + int(mx / 120.0), mx)
	if not history.has(tag):
		history[tag] = []
	history[tag].append(n["treasury"])
	if history[tag].size() > 36:
		history[tag].pop_front()


func bankruptcy(tag: String) -> void:
	var n: Dictionary = g.nations[tag]
	n["loans"].clear()
	n["treasury"] = 0.0
	n["stability"] = maxi(-3, int(n["stability"]) - 3)
	g.add_nation_modifier(tag, "bankruptcy", "Bankruptcy", {"tax_mod": -0.25, "production_mod": -0.25,
		"land_morale": -0.25, "unrest": 2}, 60)
	g.post("%s has gone BANKRUPT. All loans are cancelled, but the realm is in chaos for five years." % n["short"])


# ---------------------------------------------------------------- development

func develop_cost(tag: String, pid: int) -> int:
	var p: Dictionary = g.provinces[pid]
	var terr = float(g.terrain_data.get(p["terrain"], {}).get("dev_cost", 0.0))
	var mods = 1.0 + terr + g.mods.nat(tag, "dev_cost_mod") + g.mods.loc(pid, "local_dev_cost")
	var scale = 1.0 + maxf(0.0, g.total_dev(pid) - 9.0) * 0.04
	return maxi(10, int(round(50.0 * maxf(0.3, mods) * scale)))


func dev_cost_breakdown(tag: String, pid: int) -> String:
	var p: Dictionary = g.provinces[pid]
	var terr = float(g.terrain_data.get(p["terrain"], {}).get("dev_cost", 0.0))
	var lines: PackedStringArray = ["Base cost 50"]
	if terr != 0.0:
		lines.append("%s terrain %+d%%" % [g.terrain_data[p["terrain"]]["name"], int(round(terr * 100))])
	var nm = g.mods.nat(tag, "dev_cost_mod")
	if nm != 0.0:
		lines.append("National modifiers %+d%%" % int(round(nm * 100)))
	var over = maxf(0.0, g.total_dev(pid) - 9.0) * 0.04
	if over > 0.0:
		lines.append("Already developed: %+d%%" % int(round(over * 100)))
	return "\n".join(lines)


func can_develop(tag: String, pid: int, kind: int) -> String:
	var p: Dictionary = g.provinces[pid]
	if p["owner"] != tag:
		return "You don't own this province."
	if p["controller"] != tag:
		return "The province is occupied."
	var cost = develop_cost(tag, pid)
	if g.nations[tag]["power"][kind] < cost:
		return "Needs %d %s power." % [cost, g.nations[tag]["power_names"][kind]]
	return ""


func develop(tag: String, pid: int, kind: int) -> bool:
	if can_develop(tag, pid, kind) != "":
		return false
	g.nations[tag]["power"][kind] -= develop_cost(tag, pid)
	g.provinces[pid]["dev"][kind] += 1
	g.province_changed.emit(pid)
	g.touch(tag)
	return true


# ---------------------------------------------------------------- buildings

func build_slots(pid: int) -> int:
	var p: Dictionary = g.provinces[pid]
	return int(g.terrain_data.get(p["terrain"], {}).get("build_slots", 2)) + int(g.total_dev(pid) / 10)


func used_slots(pid: int) -> int:
	var p: Dictionary = g.provinces[pid]
	return p["buildings"].size() + (1 if not p["construction"].is_empty() else 0)


func building_cost(tag: String, bid: String) -> int:
	var base = float(g.building_data[bid]["cost"])
	return int(round(base * maxf(0.3, 1.0 + g.mods.nat(tag, "build_cost_mod"))))


func building_months(tag: String, bid: String) -> int:
	var base = float(g.building_data[bid]["months"])
	return maxi(1, int(round(base * maxf(0.3, 1.0 + g.mods.nat(tag, "build_time_mod")))))


func can_build(tag: String, pid: int, bid: String) -> String:
	var p: Dictionary = g.provinces[pid]
	var bd: Dictionary = g.building_data.get(bid, {})
	if bd.is_empty():
		return "Unknown building."
	if p["owner"] != tag:
		return "You don't own this province."
	if p["controller"] != tag:
		return "The province is occupied."
	if p["buildings"].has(bid):
		return "Already built."
	if p["construction"].get("id", "") == bid:
		return "Under construction."
	if not p["construction"].is_empty():
		return "Already building something here."
	var tech: Array = bd.get("tech", ["adm", 0])
	if g.nations[tag]["tech"][g.TRACKS.find(tech[0])] < int(tech[1]):
		return "Needs %s tech %d." % [tech[0], int(tech[1])]
	if bd.get("requires", "") == "coastal" and not p["coastal"]:
		return "Needs a coastal province."
	if bd.get("requires", "") == "mine_site" and not ("mine_site" in p["flags"]):
		return "Mines can only be dug on mine sites (ore, copper, gems, crystals, salt, sulfur, marble)."
	if used_slots(pid) >= build_slots(pid):
		return "No free building slots (%d)." % build_slots(pid)
	var cost = building_cost(tag, bid)
	if g.nations[tag]["treasury"] < cost:
		return "Needs %d sanctum." % cost
	return ""


func build(tag: String, pid: int, bid: String) -> bool:
	if can_build(tag, pid, bid) != "":
		return false
	g.nations[tag]["treasury"] -= building_cost(tag, bid)
	g.provinces[pid]["construction"] = {"id": bid, "done": g.day_index + 30 * building_months(tag, bid),
		"start": g.day_index}
	g.province_changed.emit(pid)
	g.touch(tag)
	return true


func cancel_build(tag: String, pid: int) -> void:
	var p: Dictionary = g.provinces[pid]
	if p["owner"] == tag and not p["construction"].is_empty():
		g.nations[tag]["treasury"] += building_cost(tag, p["construction"]["id"]) * 0.5
		p["construction"] = {}
		g.province_changed.emit(pid)
		g.touch(tag)


func daily_construction() -> void:
	for pid in g.provinces:
		var p: Dictionary = g.provinces[pid]
		if p["construction"].is_empty():
			continue
		if int(p["construction"]["done"]) <= g.day_index:
			var bid: String = p["construction"]["id"]
			p["construction"] = {}
			if p["owner"] != "" and not p["buildings"].has(bid):
				p["buildings"].append(bid)
				if p["owner"] == g.player_tag:
					g.post("%s finished in %s." % [g.building_data[bid]["name"], p["name"]])
				g.province_changed.emit(pid)
				g.touch(p["owner"])


func fort_level(pid: int) -> int:
	var p: Dictionary = g.provinces[pid]
	var lvl = 0
	if p["buildings"].has("fort") and p["owner"] != "":
		lvl = maxi(1, g.prog.fort_tech_level(p["owner"]))
	if "capital" in p["flags"] or (p["owner"] != "" and g.capital_of(p["owner"]) == pid):
		lvl = maxi(lvl, 1)
	if "unity_base" in p["flags"] or "doomsday_portal" in p["flags"]:
		lvl += 1
	return lvl


# ---------------------------------------------------------------- colonisation

func colonists(tag: String) -> int:
	var base = 0 if g.nations[tag]["government"] == "boar_tribe" else 1
	return base + int(g.mods.nat(tag, "colonists"))


func colonists_used(tag: String) -> int:
	var c = 0
	for pid in g.provinces:
		if g.provinces[pid]["colony"].get("tag", "") == tag:
			c += 1
	return c


func breathes(tag: String, pid: int) -> String:
	## "" if the nation's people can live in this province, otherwise why not.
	var eth: String = g.nations[tag]["ethnicity"]
	var air: String = g.peoples["ethnicities"].get(eth, {}).get("breathes", "ground")
	var layer: String = g.provinces[pid]["layer"]
	if air == "sky" and layer == "ground" and not g.nations[tag]["flags"].has("breathing_masks"):
		return "Skyfallins can't breathe the mainland air without masks."
	if air == "ground" and layer == "sky":
		return "Only Skyfallins can live on the skylands."
	return ""


func can_colonize(tag: String, pid: int) -> String:
	var p: Dictionary = g.provinces[pid]
	var n: Dictionary = g.nations[tag]
	if p["owner"] != "":
		return "Already owned."
	if not p["colony"].is_empty():
		return "Already being settled." if p["colony"]["tag"] != tag else "Your colonists are already here."
	if not n["explored"].has(pid):
		return "Explore it first."
	if not g.is_connected_to_owned(tag, pid):
		return "Must border one of your provinces (by land or sea)."
	var why = breathes(tag, pid)
	if why != "":
		return why
	if colonists_used(tag) >= colonists(tag):
		return "No free colonists (%d)." % colonists(tag)
	if n["treasury"] < COLONY_COST:
		return "Needs %d sanctum." % int(COLONY_COST)
	return ""


func colonize(tag: String, pid: int) -> bool:
	if can_colonize(tag, pid) != "":
		return false
	g.nations[tag]["treasury"] -= COLONY_COST
	g.provinces[pid]["colony"] = {"tag": tag, "settlers": 0.0}
	if tag == g.player_tag:
		g.post("Colonists set out for %s." % g.provinces[pid]["name"])
	g.province_changed.emit(pid)
	g.touch(tag)
	return true


func colony_growth(tag: String, pid: int) -> float:
	var terr = float(g.terrain_data.get(g.provinces[pid]["terrain"], {}).get("dev_cost", 0.0))
	return maxf(10.0, (90.0 + g.mods.nat(tag, "colonist_growth")) * (1.0 - terr * 0.5))


func monthly_colonies() -> void:
	for pid in g.provinces:
		var p: Dictionary = g.provinces[pid]
		if p["colony"].is_empty():
			continue
		var tag: String = p["colony"]["tag"]
		if not g.nations.has(tag) or not g.nations[tag]["alive"] or p["owner"] != "":
			p["colony"] = {}
			continue
		p["colony"]["settlers"] = float(p["colony"]["settlers"]) + colony_growth(tag, pid)
		if float(p["colony"]["settlers"]) >= 1000.0:
			var n: Dictionary = g.nations[tag]
			p["colony"] = {}
			g.set_province_owner(pid, tag)
			p["cores"][tag] = true
			p["culture"] = n["culture"]
			p["religion"] = n["religion"]
			p["ethnicity"] = n["ethnicity"]
			g.post("%s: the colony of %s is now a full province." % [n["short"], p["name"]])
		g.province_changed.emit(pid)


# ---------------------------------------------------------------- mines

func mine_income(pid: int) -> float:
	## Sanctum a month from a mine (before its upkeep).
	var p: Dictionary = g.provinces[pid]
	if not p["buildings"].has("mine") or p["owner"] == "":
		return 0.0
	return (1.5 + 0.25 * g.total_dev(pid)) * occupation_factor(pid) * autonomy_factor(pid)


# ---------------------------------------------------------------- autonomy

func autonomy(pid: int) -> float:
	return float(g.provinces[pid].get("autonomy", 0.0))


func autonomy_factor(pid: int) -> float:
	return 1.0 - autonomy(pid) / 100.0


func min_autonomy(tag: String, pid: int) -> float:
	return 0.0 if g.provinces[pid]["cores"].has(tag) else 50.0


func autonomy_drift(tag: String, pid: int) -> float:
	## Autonomy points a month: in the early Arcadian era, provinces slowly slip from the centre.
	if g.year >= EARLY_ERA_END or g.capital_of(tag) == pid:
		return 0.0
	var mult = 1.0 + g.mods.nat(tag, "autonomy_gain") + g.mods.loc(pid, "local_autonomy_gain")
	return maxf(0.0, 0.25 * mult)


func monthly_autonomy() -> void:
	for pid in g.provinces:
		var p: Dictionary = g.provinces[pid]
		var tag: String = p["owner"]
		if tag == "":
			p["autonomy"] = 0.0
			continue
		var a = autonomy(pid)
		if a < AUTONOMY_DRIFT_CAP:
			a = minf(AUTONOMY_DRIFT_CAP, a + autonomy_drift(tag, pid))
		p["autonomy"] = maxf(a, min_autonomy(tag, pid))


func lower_autonomy_cost(pid: int) -> int:
	return 2 * g.total_dev(pid)


func can_change_autonomy(tag: String, pid: int, down: bool) -> String:
	var p: Dictionary = g.provinces[pid]
	if p["owner"] != tag:
		return "Not your province."
	for m in p["modifiers"]:
		if m.get("id", "") == "autonomy_changed":
			return "Autonomy was changed recently."
	if down:
		if autonomy(pid) - 25.0 < min_autonomy(tag, pid) - 0.01:
			return "Can't go lower (uncored provinces stay at 50%)."
		if int(g.nations[tag]["power"][0]) < lower_autonomy_cost(pid):
			return "Needs %d %s power." % [lower_autonomy_cost(pid), g.nations[tag]["power_names"][0]]
	elif autonomy(pid) >= 100.0:
		return "Already fully autonomous."
	return ""


func change_autonomy(tag: String, pid: int, down: bool) -> bool:
	if can_change_autonomy(tag, pid, down) != "":
		return false
	var p: Dictionary = g.provinces[pid]
	if down:
		g.nations[tag]["power"][0] -= lower_autonomy_cost(pid)
		p["autonomy"] = maxf(min_autonomy(tag, pid), autonomy(pid) - 25.0)
		g.add_province_modifier(pid, "autonomy_changed", "Autonomy lowered", {"local_unrest": 4}, 12)
	else:
		p["autonomy"] = minf(100.0, autonomy(pid) + 25.0)
		g.add_province_modifier(pid, "autonomy_changed", "Autonomy granted", {"local_unrest": -3}, 12)
	g.touch(tag)
	return true
