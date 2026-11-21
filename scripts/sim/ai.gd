extends RefCounted
## Computer-controlled nations: spending power and sanctum, recruiting, diplomacy, declaring wars,
## making peace, and moving armies during wars and rebellions.

const IDEA_PLANS := {
	"MEN": ["economic", "offensive", "trade", "administrative", "quality", "expansion", "diplomatic"],
	"SKY": ["quality", "defensive", "religious", "trade", "offensive", "maritime", "economic"],
	"TRIBE": ["quantity", "administrative", "offensive", "economic", "expansion", "defensive", "trade"],
}

var g: Node


func _init(game: Node) -> void:
	g = game


func monthly(tag: String) -> void:
	var n: Dictionary = g.nations[tag]
	if not n["alive"] or g.owned(tag).is_empty():
		return
	var war = g.dip.at_war_any(tag)
	n["maintenance"]["land"] = 1.0 if war or _has_rebels(tag) else 0.6
	n["maintenance"]["naval"] = 1.0 if war else 0.5
	_spend_power(tag)
	_reforms(tag)
	_finances(tag)
	_military(tag, war)
	_colonise(tag)
	_religion(tag)
	_diplomacy(tag, war)
	_peace(tag)
	for m in g.missions_for(tag):
		if g.mission_state(tag, m) == "ready":
			g.claim_mission(tag, m["id"])


func _has_rebels(tag: String) -> bool:
	for a in g.armies.values():
		if a["owner"] == "REB" and a["rebel"].get("target", "") == tag:
			return true
	return false


# ---------------------------------------------------------------- power

func _spend_power(tag: String) -> void:
	var n: Dictionary = g.nations[tag]
	# technology first, starting with the cheapest track
	for track in ["mil", "adm", "dip"]:
		if g.prog.can_research(tag, track) == "" and int(n["power"][g.TRACKS.find(track)]) >= g.prog.tech_cost(tag, track):
			g.prog.research(tag, track)
	# a power type is saved for technology when that track has fallen behind the calendar
	var saving = [false, false, false]
	for i in 3:
		var nxt: Dictionary = g.prog.level_info(g.TRACKS[i], int(n["tech"][i]) + 1)
		saving[i] = not nxt.is_empty() and int(nxt.get("year", 9999)) <= g.year and int(n["power"][i]) < 900
	# ideas
	var plan: Array = IDEA_PLANS.get(n["ideas"], IDEA_PLANS["TRIBE"])
	for gid in plan:
		if g.prog.can_pick_group(tag, gid) == "":
			g.prog.pick_group(tag, gid)
			break
	for ig in n["idea_groups"]:
		var grp: Dictionary = g.idea_data["groups"][ig["id"]]
		var i: int = g.TRACKS.find(grp["type"])
		if not saving[i] and g.prog.can_take_idea(tag, ig["id"]) == "" and int(n["power"][i]) >= g.prog.idea_cost(tag) + 80:
			g.prog.take_idea(tag, ig["id"])
	# cores
	for pid in g.owned(tag):
		if (not saving[0] or g.pop.overextension(tag) > 60.0) and g.pop.can_core(tag, pid) == "":
			g.pop.make_core(tag, pid)
	# accept cultures of big chunks of land
	var counts = {}
	for pid in g.owned(tag):
		var c: String = g.provinces[pid]["culture"]
		if not g.pop.culture_accepted(tag, c):
			counts[c] = int(counts.get(c, 0)) + g.total_dev(pid)
	for c in counts:
		if not saving[1] and int(counts[c]) >= 20 and g.pop.can_accept_culture(tag, c) == "" and int(n["power"][1]) >= 200:
			g.pop.accept_culture(tag, c)
	# develop with what is left over, keeping a reserve for tech
	for k in 3:
		if int(n["power"][k]) < 350 or saving[k]:
			continue
		var best = -1
		var best_score = -1.0
		for pid in g.owned(tag):
			var cost = g.eco.develop_cost(tag, pid)
			var val = 1.0
			if k == 1:
				val = g.eco.price(g.provinces[pid]["goods"])
			var score = val / float(cost)
			if "capital" in g.provinces[pid]["flags"]:
				score *= 1.3
			if score > best_score:
				best_score = score
				best = pid
		if best >= 0:
			g.eco.develop(tag, best, k)
	# rebels brewing
	for pid in g.owned(tag):
		if float(g.provinces[pid]["rebel_progress"]) > 70.0 and g.pop.can_harsh(tag, pid) == "" and int(n["power"][2]) > 150:
			g.pop.harsh_treatment(tag, pid)


func _reforms(tag: String) -> void:
	var n: Dictionary = g.nations[tag]
	var tiers: Array = g.prog.government(tag).get("tiers", [])
	var t: int = n["reforms"].size()
	if t < tiers.size():
		var opts: Array = tiers[t]["reforms"]
		var pick: Dictionary = opts[g.rng.randi_range(0, opts.size() - 1)]
		if g.prog.can_enact(tag, t, pick["id"]) == "":
			g.prog.enact(tag, t, pick["id"])


# ---------------------------------------------------------------- money

func _finances(tag: String) -> void:
	var n: Dictionary = g.nations[tag]
	if not n["loans"].is_empty() and float(n["treasury"]) > float(n["loans"][0]) + 80.0:
		g.eco.repay_loan(tag)
	if float(n["treasury"]) < 150.0 or g.dip.at_war_any(tag):
		return
	var builds = 1 + int(float(n["treasury"]) / 400.0)
	for i in mini(builds, 6):
		if not _build_one(tag):
			break


func _build_one(tag: String) -> bool:
	var n: Dictionary = g.nations[tag]
	var best_pid = -1
	var best_bid = ""
	var best_val = 0.0
	for pid in g.owned(tag):
		var p: Dictionary = g.provinces[pid]
		for bid in ["temple", "workshop", "market", "trade_depot", "barracks", "courthouse", "dock", "granary"]:
			if g.eco.can_build(tag, pid, bid) != "":
				continue
			var val = 0.0
			match bid:
				"temple": val = float(p["dev"][0]) * 0.4
				"workshop": val = g.eco.goods_value(pid) * 0.5
				"market": val = 0.6 + g.eco.goods_value(pid) * 0.1
				"trade_depot": val = 1.0
				"barracks": val = float(p["dev"][2]) * 0.3
				"courthouse": val = 1.5 if float(p.get("unrest", 0.0)) > 1.0 else 0.2
				"dock": val = 0.3
				"granary": val = 0.3
			val /= float(g.eco.building_cost(tag, bid))
			if val > best_val:
				best_val = val
				best_pid = pid
				best_bid = bid
	if best_pid >= 0 and float(n["treasury"]) > g.eco.building_cost(tag, best_bid) + 100.0:
		return g.eco.build(tag, best_pid, best_bid)
	return false


# ---------------------------------------------------------------- military

func _military(tag: String, war: bool) -> void:
	var n: Dictionary = g.nations[tag]
	var fl = g.mil.land_force_limit(tag)
	var regs = g.mil.regiment_count(tag)
	var target = int(fl * (1.0 if war else 0.8))
	var cap: int = g.capital_of(tag)
	var spots: Array = []
	for pid in g.owned(tag):
		if g.provinces[pid]["controller"] == tag:
			spots.append(pid)
	spots.sort_custom(func(x, y): return int(g.provinces[x]["dev"][2]) > int(g.provinces[y]["dev"][2]))
	spots = spots.slice(0, 6)
	var spot = cap if spots.is_empty() else spots[g.rng.randi_range(0, spots.size() - 1)]
	var guard = 0
	while regs < target and guard < 4 and spot >= 0:
		guard += 1
		var t = "inf"
		if regs % 4 == 3 and g.prog.land_unit_unlocked(tag, "art"):
			t = "art"
		elif regs % 5 == 4:
			t = "cav"
		if float(n["treasury"]) < 40.0 and not war:
			break
		if not g.mil.recruit(tag, spot, t):
			break
		regs += 1
	# a general for every army
	for a in g.mil.armies_of(tag):
		if int(a["leader"]) < 0 and a["regiments"].size() >= 4:
			var free = {}
			for l in n["leaders"]:
				if int(l["army"]) < 0 and l["kind"] == "general":
					free = l
			if free.is_empty() and g.mil.can_recruit_leader(tag) == "" and int(n["power"][2]) > 150:
				free = g.mil.recruit_leader(tag)
			if not free.is_empty():
				g.mil.assign_leader(a["id"], free["id"])


func _colonise(tag: String) -> void:
	if g.eco.colonists_used(tag) >= g.eco.colonists(tag):
		return
	for pid in g.provinces:
		if g.eco.can_colonize(tag, pid) == "" and float(g.nations[tag]["treasury"]) > 80.0:
			g.eco.colonize(tag, pid)
			return
	# explore toward unknown land
	var n: Dictionary = g.nations[tag]
	for pid in g.provinces:
		if g.can_explore(tag, pid) == "" and int(n["power"][1]) > g.explore_cost(tag, pid) + 150:
			if tag == "MEN" and g.provinces[pid]["layer"] == "sky" and g.dip.opinion("SKY", "MEN") > 0.0 and g.rng.randf() < 0.8:
				continue
			g.explore(tag, pid)
			return


func _religion(tag: String) -> void:
	for pid in g.owned(tag):
		if g.pop.can_start_conversion(tag, pid) == "":
			g.pop.start_conversion(tag, pid)
			return


# ---------------------------------------------------------------- diplomacy

func _diplomacy(tag: String, war: bool) -> void:
	var n: Dictionary = g.nations[tag]
	var tribe: bool = n["government"] == "boar_tribe"
	# tribes band together against the pigs
	for other in g.nations:
		if other == tag or not g.nations[other]["alive"]:
			continue
		if tribe and g.nations[other]["government"] == "boar_tribe" and g.dip.can_act("alliance", tag, other) == "" \
				and g.rng.randf() < 0.08 and g.dip.ai_accepts("alliance", tag, other):
			g.dip.act("alliance", tag, other)
		if g.dip.diplomats_used(tag) < g.dip.diplomats(tag) and g.dip.opinion(other, tag) < 50.0 \
				and (g.dip.rel(tag, other)["alliance"] or g.dip.borders(tag, other)) and not g.dip.at_war(tag, other) \
				and not g.dip.rel(tag, other)["improving"] and g.rng.randf() < 0.2:
			g.dip.act("improve", tag, other)
	if war or tribe:
		return
	if int(n["stability"]) < 0 or float(n["treasury"]) < 0.0 or float(n["war_exhaustion"]) > 3.0:
		return
	# conquest of weak neighbours with a cause
	if g.rng.randf() > 0.06:
		return
	var best = ""
	var best_ratio = 0.0
	for other in g.nations:
		if other == tag or not g.nations[other]["alive"] or g.dip.can_declare(tag, other) != "":
			continue
		var cb = g.dip.best_cb(tag, other)
		if cb.is_empty():
			continue
		if cb["id"] == "great_war":
			continue   # the Great War starts only through its events
		var enemy_str = g.mil.nation_strength(other)
		for al in g.dip.allies_of(other):
			enemy_str += g.mil.nation_strength(al)
		var ratio = g.mil.nation_strength(tag) / maxf(0.5, enemy_str)
		if ratio > best_ratio:
			best_ratio = ratio
			best = other
	if best != "" and best_ratio >= 2.0:
		g.dip.declare_war(tag, best)


func _peace(tag: String) -> void:
	for w in g.dip.wars_of(tag):
		var side: String = g.dip.war_side(w, tag)
		if w[side][0] != tag:
			continue
		var enemy: String = g.dip.enemy_leader(w, tag)
		var ws = g.dip.score_for(w, tag)
		var months = (g.day_index - int(w["start"])) / 30.0
		var demands = _pick_demands(w, tag, enemy, ws)
		if enemy == g.player_tag:
			# occasionally offer the player terms
			if ws >= 25.0 and g.rng.randf() < 0.15 and not demands.is_empty():
				g.dip.offer_peace(w, tag, enemy, demands)
			elif months > 30.0 and absf(ws) < 15.0 and g.rng.randf() < 0.1:
				g.dip.offer_peace(w, tag, enemy, [{"type": "white"}])
			continue
		if ws >= 20.0 and not demands.is_empty():
			if g.dip.offer_peace(w, tag, enemy, demands):
				return
		if months > 48.0 and g.rng.randf() < 0.2:
			g.dip.enforce_peace(w, tag, enemy, [{"type": "white"}])
			return


func _pick_demands(w: Dictionary, tag: String, enemy: String, ws: float) -> Array:
	var all_occ = true
	for pid in g.owned(enemy):
		if g.dip.war_side(w, g.provinces[pid]["controller"]) != g.dip.war_side(w, tag):
			all_occ = false
	if all_occ and g.dip.peace_cost(w, tag, enemy, [{"type": "annex"}]) <= ws:
		return [{"type": "annex"}]
	var cands: Array = []
	for pid in g.owned(enemy):
		var near = false
		for nb in g.provinces[pid]["connections"]:
			if g.provinces[nb]["owner"] == tag:
				near = true
		if near or g.provinces[pid]["controller"] == tag:
			cands.append(pid)
	cands.sort_custom(func(x, y): return g.total_dev(x) > g.total_dev(y))
	var out: Array = []
	for pid in cands:
		var trial = out + [{"type": "province", "pid": pid}]
		if g.dip.peace_cost(w, tag, enemy, trial) <= ws:
			out = trial
	return out


# ---------------------------------------------------------------- armies

func hops(from: int, tag: String, limit: int) -> Dictionary:
	## Province -> number of steps away, through provinces this nation may enter.
	var dist = {from: 0}
	var frontier = [from]
	for step in limit:
		var nxt: Array = []
		for c in frontier:
			for nb in g.provinces[c]["connections"]:
				if dist.has(nb):
					continue
				if not g.mil.can_enter(tag, nb):
					continue
				dist[nb] = step + 1
				nxt.append(nb)
		frontier = nxt
	return dist


func armies_tick() -> void:
	## Every few days: move AI armies toward enemies, sieges or rebels.
	for tag in g.nations:
		var n: Dictionary = g.nations[tag]
		if not n["alive"] or not n["ai"]:
			continue
		var war = g.dip.at_war_any(tag)
		var rebels = _has_rebels(tag)
		var mine = g.mil.armies_of(tag)
		# merge idle armies standing together
		var by_loc = {}
		for a in mine:
			if a["path"].is_empty() and not a["in_battle"] and not a["retreating"]:
				var k: int = int(a["location"])
				if not by_loc.has(k):
					by_loc[k] = []
				by_loc[k].append(a["id"])
		if war or rebels:
			for k in by_loc:
				if by_loc[k].size() > 1:
					var total = 0
					for aid in by_loc[k]:
						total += g.armies[aid]["regiments"].size()
					if total <= g.mil.supply_limit(k) * 2:
						g.mil.merge_armies(by_loc[k])
		if not war and not rebels:
			continue
		for a in g.mil.armies_of(tag):
			if a["in_battle"] or a["retreating"] or not a["path"].is_empty():
				continue
			_army_orders(tag, a)


func _army_orders(tag: String, a: Dictionary) -> void:
	var here: int = int(a["location"])
	var dist = hops(here, tag, 12)
	var my_str = g.mil.army_strength(a)
	var best_target = -1
	var best_score = -INF
	var danger = false
	for other in g.armies.values():
		if not g.mil.armies_hostile(a, other):
			continue
		var op: int = int(other["location"])
		if not dist.has(op):
			continue
		var their = g.mil.army_strength(other)
		if their > my_str * 1.4 and int(dist[op]) <= 2:
			danger = true
		if my_str >= their * 1.15:
			var s = 30.0 - float(dist[op]) * 3.0 + their
			if g.provinces[op]["owner"] == tag:
				s += 15.0
			if s > best_score:
				best_score = s
				best_target = op
	if danger and best_target < 0:
		var cap: int = g.capital_of(tag)
		if cap >= 0 and cap != here:
			g.mil.move_army(a["id"], cap)
		return
	for pid in dist:
		if not g.mil.controller_hostile(a, pid):
			continue
		var fort = g.eco.fort_level(pid)
		if fort > 0 and g.mil.army_men(a) < fort * 1500.0:
			continue
		var s = 20.0 - float(dist[pid]) * 2.5 - fort * 6.0 + g.total_dev(pid) * 0.3
		if g.provinces[pid]["owner"] == tag:
			s += 12.0   # liberate our own land first
		if g.capital_of(g.provinces[pid]["owner"]) == pid:
			s += 6.0
		if s > best_score:
			best_score = s
			best_target = pid
	if best_target >= 0 and best_target != here:
		g.mil.move_army(a["id"], best_target)
