extends RefCounted
## Diplomacy and war: opinions and relations, alliances, royal marriages, military access, rivals,
## claims, vassals, casus belli, war declarations with calls to arms, war score, peace deals.

const TRUCE_DAYS := 1825
const IMPROVE_PER_MONTH := 3.0
const IMPROVE_CAP := 100.0

var g: Node
var _war_pairs = {}     # "A|B" -> war id (both orders)
var _side_pairs = {}    # "A|B" -> true when A and B fight on the same side


func _init(game: Node) -> void:
	g = game


# ---------------------------------------------------------------- relations storage

func rel(a: String, b: String) -> Dictionary:
	var n: Dictionary = g.nations[a]
	if not n["relations"].has(b):
		n["relations"][b] = {"opinion": 0.0, "mods": [], "alliance": false, "marriage": false, "access": false,
			"rival": false, "truce_until": -1, "improving": false}
	return n["relations"][b]


func set_both(a: String, b: String, key: String, value: Variant) -> void:
	rel(a, b)[key] = value
	rel(b, a)[key] = value


func add_opinion(a: String, b: String, value: float, name: String, decay: float = 1.0) -> void:
	## a's opinion of b changes by value; decays by `decay` a month toward zero.
	if not g.nations.has(a) or not g.nations.has(b) or a == b:
		return
	var r = rel(a, b)
	for m in r["mods"]:
		if m["name"] == name:
			m["value"] = clampf(float(m["value"]) + value, -200.0, 200.0)
			return
	r["mods"].append({"name": name, "value": value, "decay": decay})


func opinion_breakdown(a: String, b: String) -> Array:
	var out: Array = []
	if not g.nations.has(a) or not g.nations.has(b):
		return out
	var r = rel(a, b)
	if float(r["opinion"]) != 0.0:
		out.append(["Base relations", float(r["opinion"])])
	for m in r["mods"]:
		out.append([m["name"], float(m["value"])])
	if r["alliance"]:
		out.append(["Alliance", 25.0])
	if r["marriage"]:
		out.append(["Royal marriage", 15.0])
	if g.nations[a]["religion"] == g.nations[b]["religion"]:
		out.append(["Same faith", 10.0])
	else:
		out.append(["Different faith", -10.0])
	if g.pop.culture_group(g.nations[a]["culture"]) == g.pop.culture_group(g.nations[b]["culture"]):
		out.append(["Same culture group", 10.0])
	if r["rival"] or rel(b, a)["rival"]:
		out.append(["Rivals", -50.0])
	if at_war(a, b):
		out.append(["At war", -100.0])
	if g.nations[a]["overlord"] == b:
		out.append(["Our overlord", 10.0])
	var rep = g.mods.nat(b, "diplomatic_reputation")
	if rep != 0.0:
		out.append(["Their reputation", rep * 5.0])
	return out


func opinion(a: String, b: String) -> float:
	var t = 0.0
	for x in opinion_breakdown(a, b):
		t += float(x[1])
	return clampf(t, -200.0, 200.0)


func allied(a: String, b: String) -> bool:
	if a == b:
		return true
	if not g.nations.has(a) or not g.nations.has(b):
		return false
	if rel(a, b)["alliance"]:
		return true
	if g.nations[a]["overlord"] == b or g.nations[b]["overlord"] == a:
		return true
	return _side_pairs.has(a + "|" + b)


func has_access(a: String, b: String) -> bool:
	## May a's armies march through b's land?
	return allied(a, b) or rel(b, a)["access"]


func at_war(a: String, b: String) -> bool:
	return _war_pairs.has(a + "|" + b)


func at_war_any(a: String) -> bool:
	for w in g.wars.values():
		if a in w["attackers"] or a in w["defenders"]:
			return true
	return false


func wars_of(a: String) -> Array:
	var out: Array = []
	for w in g.wars.values():
		if a in w["attackers"] or a in w["defenders"]:
			out.append(w)
	return out


func rebuild_pairs() -> void:
	_war_pairs.clear()
	_side_pairs.clear()
	for w in g.wars.values():
		for x in w["attackers"]:
			for y in w["defenders"]:
				_war_pairs[x + "|" + y] = w["id"]
				_war_pairs[y + "|" + x] = w["id"]
		for side in [w["attackers"], w["defenders"]]:
			for x in side:
				for y in side:
					if x != y:
						_side_pairs[x + "|" + y] = true


func borders(a: String, b: String) -> bool:
	for pid in g.owned(a):
		for nb in g.provinces[pid]["connections"]:
			if g.provinces[nb]["owner"] == b:
				return true
	return false


func diplomats(tag: String) -> int:
	return 2 + int(g.mods.nat(tag, "diplomats"))


func diplomats_used(tag: String) -> int:
	var c = 0
	for b in g.nations[tag]["relations"]:
		if g.nations[tag]["relations"][b].get("improving", false):
			c += 1
	return c


func allies_of(a: String) -> Array:
	var out: Array = []
	for b in g.nations[a]["relations"]:
		if g.nations.has(b) and g.nations[b]["alive"] and g.nations[a]["relations"][b]["alliance"]:
			out.append(b)
	return out


func truce(a: String, b: String) -> bool:
	return int(rel(a, b)["truce_until"]) > g.day_index


# ---------------------------------------------------------------- acceptance

func _strength_ratio(a: String, b: String) -> float:
	return g.mil.nation_strength(a) / maxf(0.5, g.mil.nation_strength(b))


func acceptance(action: String, from: String, to: String) -> Array:
	## [score, [[reason, value]]]: the AI of `to` says yes when the score is above 0.
	var rs: Array = []
	var op = opinion(to, from)
	match action:
		"alliance":
			rs.append(["Opinion of you", op / 4.0])
			rs.append(["Base reluctance", -10.0])
			var ratio = _strength_ratio(from, to)
			rs.append(["Your military strength", clampf((ratio - 1.0) * 10.0, -20.0, 20.0)])
			for e in g.nations:
				if g.nations[e]["alive"] and e != from and e != to and (rel(to, e)["rival"] or opinion(to, e) < -50) and opinion(from, e) < 0:
					rs.append(["Common enemy: %s" % g.nation_name(e), 15.0])
					break
			if at_war_any(from):
				rs.append(["You are at war", -25.0])
			if rel(to, from)["rival"]:
				rs.append(["Rivals", -1000.0])
			if allies_of(to).size() >= 3:
				rs.append(["Has enough allies", -30.0])
		"marriage":
			rs.append(["Opinion of you", op / 4.0])
			rs.append(["Base", 5.0])
			if g.nations[from]["ethnicity"] != g.nations[to]["ethnicity"]:
				rs.append(["Different peoples", -15.0])
			if rel(to, from)["rival"]:
				rs.append(["Rivals", -1000.0])
		"access":
			rs.append(["Opinion of you", op / 5.0])
			rs.append(["Base", 5.0])
			var ratio2 = _strength_ratio(from, to)
			if ratio2 > 2.0:
				rs.append(["Fears your army", -15.0])
			if rel(to, from)["rival"]:
				rs.append(["Rivals", -1000.0])
		"vassalize":
			rs.append(["Opinion of you", op / 3.0])
			rs.append(["Base reluctance", -30.0])
			var ratio3 = _strength_ratio(from, to)
			rs.append(["Your military strength", clampf((ratio3 - 2.0) * 8.0, -30.0, 40.0)])
			rs.append(["Their size", -g.nation_dev(to) * 0.4])
			if g.nations[to]["overlord"] != "":
				rs.append(["Already a subject", -1000.0])
			if not borders(from, to):
				rs.append(["Not neighbours", -20.0])
		"peace":
			pass
	var total = 0.0
	for r in rs:
		total += float(r[1])
	return [total, rs]


func ai_accepts(action: String, from: String, to: String) -> bool:
	return float(acceptance(action, from, to)[0]) > 0.0


# ---------------------------------------------------------------- actions

func can_act(action: String, from: String, to: String) -> String:
	if from == to or not g.nations.has(to) or not g.nations[to]["alive"]:
		return "Not possible."
	var r = rel(from, to)
	var n: Dictionary = g.nations[from]
	match action:
		"improve":
			if r["improving"]:
				return ""
			if diplomats_used(from) >= diplomats(from):
				return "No free diplomats (%d)." % diplomats(from)
		"alliance":
			if r["alliance"]:
				return "Already allied."
			if at_war(from, to):
				return "You are at war."
		"break_alliance":
			if not r["alliance"]:
				return "Not allied."
		"marriage":
			if r["marriage"]:
				return "Already married."
			if at_war(from, to):
				return "You are at war."
		"access":
			if rel(to, from)["access"]:
				return "You already have military access."
			if at_war(from, to):
				return "You are at war."
		"insult":
			if n["power"][1] < 10:
				return "Needs 10 %s power." % n["power_names"][1]
		"rival":
			if r["rival"]:
				return ""
			var count = 0
			for b in n["relations"]:
				if n["relations"][b]["rival"]:
					count += 1
			if count >= 3:
				return "At most three rivals."
		"claim":
			if n["power"][1] < 25:
				return "Needs 25 %s power." % n["power_names"][1]
			if not borders(from, to):
				return "You must border them."
		"vassalize":
			if g.nations[to]["overlord"] != "":
				return "Already a subject."
			if at_war(from, to):
				return "You are at war."
		"integrate":
			if g.nations[to]["overlord"] != from:
				return "Not your subject."
			var cost = integrate_cost(to)
			if n["power"][1] < cost:
				return "Needs %d %s power." % [cost, n["power_names"][1]]
		"war":
			return can_declare(from, to)
	return ""


func integrate_cost(vassal: String) -> int:
	return 6 * int(g.nation_dev(vassal))


func act(action: String, from: String, to: String) -> String:
	## Performs a diplomatic action. Returns a message for the player.
	var why = can_act(action, from, to)
	if why != "":
		return why
	var r = rel(from, to)
	var nm: String = g.nation_name(to)
	match action:
		"improve":
			r["improving"] = not r["improving"]
			g.touch(from)
			return ("A diplomat is improving relations with %s." if r["improving"] else "Recalled the diplomat from %s.") % nm
		"alliance":
			if to == g.player_tag or ai_accepts("alliance", from, to):
				set_both(from, to, "alliance", true)
				g.post("%s and %s are now allies." % [g.nation_name(from), nm])
				g.touch(from)
				return "%s accepted the alliance." % nm
			add_opinion(to, from, -5.0, "Rejected proposal", 1.0)
			return "%s declined the alliance." % nm
		"break_alliance":
			set_both(from, to, "alliance", false)
			add_opinion(to, from, -40.0, "Broke our alliance", 1.0)
			g.touch(from)
			return "Alliance with %s broken." % nm
		"marriage":
			if to == g.player_tag or ai_accepts("marriage", from, to):
				set_both(from, to, "marriage", true)
				g.post("A royal marriage between %s and %s." % [g.nation_name(from), nm])
				g.touch(from)
				return "%s accepted the royal marriage." % nm
			return "%s declined the royal marriage." % nm
		"access":
			if to == g.player_tag or ai_accepts("access", from, to):
				rel(to, from)["access"] = true
				g.touch(from)
				return "%s grants you military access." % nm
			return "%s refused military access." % nm
		"insult":
			g.nations[from]["power"][1] -= 10
			add_opinion(to, from, -50.0, "Insulted", 1.0)
			g.touch(from)
			return "You insulted %s." % nm
		"rival":
			r["rival"] = not r["rival"]
			add_opinion(to, from, -25.0 if r["rival"] else 10.0, "Declared rival" if r["rival"] else "Ended rivalry", 0.5)
			g.touch(from)
			return ("%s is now your rival." if r["rival"] else "%s is no longer your rival.") % nm
		"claim":
			var best = -1
			for pid in g.owned(to):
				if g.nations[from]["claims"].has(pid):
					continue
				for nb in g.provinces[pid]["connections"]:
					if g.provinces[nb]["owner"] == from and (best < 0 or g.total_dev(pid) > g.total_dev(best)):
						best = pid
			if best < 0:
				return "Nothing left to claim."
			g.nations[from]["power"][1] -= 25
			g.nations[from]["claims"][best] = true
			add_opinion(to, from, -20.0, "Claims our land", 0.5)
			g.touch(from)
			return "Your scribes fabricated a claim on %s." % g.provinces[best]["name"]
		"vassalize":
			if to == g.player_tag or ai_accepts("vassalize", from, to):
				make_vassal(from, to)
				return "%s is now your vassal." % nm
			return "%s refused to become your vassal." % nm
		"integrate":
			g.nations[from]["power"][1] -= integrate_cost(to)
			annex(from, to)
			return "%s has been integrated." % nm
		"war":
			declare_war(from, to)
			return "You declared war on %s." % nm
	return ""


func make_vassal(overlord: String, vassal: String) -> void:
	g.nations[vassal]["overlord"] = overlord
	if not g.nations[overlord]["subjects"].has(vassal):
		g.nations[overlord]["subjects"].append(vassal)
	set_both(overlord, vassal, "alliance", false)
	g.post("%s is now a vassal of %s." % [g.nation_name(vassal), g.nation_name(overlord)])
	g.touch(overlord)
	g.touch(vassal)


func annex(by: String, target: String) -> void:
	for pid in g.owned(target):
		g.set_province_owner(pid, by)
		g.provinces[pid]["cores"][by] = true
	g.kill_nation(target)
	g.post("%s has been annexed by %s." % [g.nation_name(target), g.nation_name(by)])


# ---------------------------------------------------------------- casus belli and war

func casus_belli(a: String, b: String) -> Array:
	var out: Array = []
	if g.global_flags.has("great_war") and ((a == "MEN" and b == "SKY") or (a == "SKY" and b == "MEN")):
		out.append({"id": "great_war", "name": "The Great War for Arcadia", "mult": 0.6})
	if g.nations[b]["government"] == "boar_tribe" and g.nations[a]["government"] != "boar_tribe" and borders(a, b):
		out.append({"id": "tribal_conquest", "name": "Tribal Conquest", "mult": 0.6})
	for pid in g.owned(b):
		if g.nations[a]["claims"].has(pid) or g.provinces[pid]["cores"].has(a):
			out.append({"id": "claim", "name": "Reconquest of Claims", "mult": 0.75})
			break
	if rel(a, b)["rival"]:
		out.append({"id": "rivalry", "name": "Humiliate Rival", "mult": 1.0})
	return out


func best_cb(a: String, b: String) -> Dictionary:
	var best = {}
	for cb in casus_belli(a, b):
		if best.is_empty() or float(cb["mult"]) < float(best["mult"]):
			best = cb
	return best


func can_declare(a: String, b: String) -> String:
	if a == b or not g.nations[b]["alive"]:
		return "Not possible."
	if at_war(a, b):
		return "Already at war."
	if allied(a, b) and not _side_pairs.has(a + "|" + b) and rel(a, b)["alliance"]:
		return "Break your alliance first."
	if g.nations[a]["overlord"] == b or g.nations[b]["overlord"] == a:
		return "You can't fight your overlord or subject this way."
	if truce(a, b):
		return "Truce until %s." % g.date_from_index(int(rel(a, b)["truce_until"]))
	return ""


func declare_war(a: String, b: String, cb: Dictionary = {}) -> Dictionary:
	if can_declare(a, b) != "":
		return {}
	if cb.is_empty():
		cb = best_cb(a, b)
	if cb.is_empty():
		cb = {"id": "none", "name": "No Casus Belli", "mult": 1.25}
		g.nations[a]["stability"] = maxi(-3, int(g.nations[a]["stability"]) - 2)
		for t in g.nations:
			if t != a and g.nations[t]["alive"]:
				add_opinion(t, a, -15.0, "Declared war without cause", 0.5)
	g.next_id += 1
	var w = {"id": g.next_id, "name": "%s %s" % [g.nations[a]["adjective"], _war_title(cb, b)],
		"attackers": [a], "defenders": [b], "cb": cb, "start": g.day_index, "score": 0.0, "battle_score": 0.0}
	g.wars[w["id"]] = w
	add_opinion(b, a, -100.0, "Declared war on us", 0.5)
	set_both(a, b, "improving", false)
	rel(b, a)["access"] = false
	rel(a, b)["access"] = false
	rebuild_pairs()
	g.post("%s declares war on %s: %s." % [g.nation_name(a), g.nation_name(b), w["name"]])
	# subjects and overlords join, allies are called
	for s in g.nations[a]["subjects"]:
		_join(w, s, "attackers")
	for s in g.nations[b]["subjects"]:
		_join(w, s, "defenders")
	if g.nations[b]["overlord"] != "":
		_join(w, g.nations[b]["overlord"], "defenders")
	for ally in allies_of(b):
		call_to_arms(w, b, ally, "defenders")
	for ally in allies_of(a):
		call_to_arms(w, a, ally, "attackers")
	rebuild_pairs()
	g.war_changed.emit()
	g.touch(a)
	g.touch(b)
	return w


func _war_title(cb: Dictionary, target: String) -> String:
	match cb.get("id", ""):
		"great_war": return "Great War for Arcadia"
		"tribal_conquest": return "Conquest of %s" % g.nation_name(target)
		"claim": return "Reconquest of %s" % g.nation_name(target)
		"rivalry": return "Humiliation of %s" % g.nation_name(target)
	return "War against %s" % g.nation_name(target)


func _join(w: Dictionary, tag: String, side: String) -> void:
	if not g.nations.has(tag) or not g.nations[tag]["alive"]:
		return
	if tag in w["attackers"] or tag in w["defenders"]:
		return
	var other = "defenders" if side == "attackers" else "attackers"
	for x in w[other]:
		if rel(tag, x)["alliance"] or g.nations[tag]["overlord"] == x:
			return
	w[side].append(tag)
	rebuild_pairs()


func call_to_arms(w: Dictionary, caller: String, ally: String, side: String) -> void:
	if ally in w["attackers"] or ally in w["defenders"]:
		return
	var enemy: String = w["defenders"][0] if side == "attackers" else w["attackers"][0]
	if rel(ally, enemy)["alliance"] or truce(ally, enemy):
		return
	if ally == g.player_tag:
		g.fire_dynamic_event({
			"id": "call_to_arms", "title": "Call to Arms",
			"text": "%s has called us to join %s against %s." % [g.nation_name(caller), w["name"], g.nation_name(enemy)],
			"options": [
				{"text": "Honour the alliance.", "effects": [{"type": "join_war", "war": w["id"], "side": side}]},
				{"text": "Refuse. (The alliance ends.)", "effects": [{"type": "refuse_call", "caller": caller}]}]}, ally)
		return
	if opinion(ally, caller) >= 0.0 and not at_war_any(ally) or ally in g.nations[caller]["subjects"]:
		_join(w, ally, side)
		g.post("%s joins the war on the side of %s." % [g.nation_name(ally), g.nation_name(caller)])
	else:
		set_both(ally, caller, "alliance", false)
		add_opinion(caller, ally, -50.0, "Refused our call to arms", 1.0)
		g.post("%s refused the call to arms from %s." % [g.nation_name(ally), g.nation_name(caller)])


func war_side(w: Dictionary, tag: String) -> String:
	if tag in w["attackers"]:
		return "attackers"
	if tag in w["defenders"]:
		return "defenders"
	return ""


func score_for(w: Dictionary, tag: String) -> float:
	return float(w["score"]) if war_side(w, tag) == "attackers" else -float(w["score"])


func enemy_leader(w: Dictionary, tag: String) -> String:
	return w["defenders"][0] if war_side(w, tag) == "attackers" else w["attackers"][0]


func battle_result(winner: String, loser: String, loser_losses: float, winner_losses: float) -> void:
	for w in g.wars.values():
		var ws = war_side(w, winner)
		var ls = war_side(w, loser)
		if ws == "" or ls == "" or ws == ls:
			continue
		var amt = clampf((loser_losses - winner_losses * 0.5) / 1000.0 * 1.5, 0.5, 10.0)
		w["battle_score"] = clampf(float(w["battle_score"]) + (amt if ws == "attackers" else -amt), -40.0, 40.0)
	update_war_scores()


func update_war_scores() -> void:
	for w in g.wars.values():
		var occ = 0.0
		for side in ["attackers", "defenders"]:
			var other = "defenders" if side == "attackers" else "attackers"
			var total = 0.0
			var taken = 0.0
			for t in w[side]:
				for pid in g.owned(t):
					var d = float(g.total_dev(pid))
					total += d
					var c: String = g.provinces[pid]["controller"]
					if c in w[other]:
						taken += d
						if g.capital_of(t) == pid and t == w[side][0]:
							taken += d * 0.5
			var part = 0.0 if total <= 0.0 else clampf(taken / total * 100.0, 0.0, 100.0)
			occ += part if side == "defenders" else -part
		w["score"] = clampf(occ * 0.85 + float(w["battle_score"]), -100.0, 100.0)


# ---------------------------------------------------------------- peace

func peace_cost(w: Dictionary, demander: String, target: String, demands: Array) -> float:
	var mult = float(w["cb"].get("mult", 1.0)) if war_side(w, demander) == "attackers" else 1.0
	var cost = 0.0
	for d in demands:
		match d.get("type", ""):
			"province":
				var pid: int = int(d["pid"])
				var p: Dictionary = g.provinces[pid]
				var c = float(g.total_dev(pid)) * 1.2 * mult
				if war_side(w, p["controller"]) != war_side(w, demander):
					c *= 1.5
				cost += c
			"gold":
				cost += float(d["amount"]) / (10.0 + 0.05 * g.nation_dev(target))
			"vassalize":
				cost += float(g.nation_dev(target)) * 0.7
			"annex":
				cost += float(g.nation_dev(target)) * 1.1 * mult
	if g.nation_dev(target) > 0:
		cost = cost * 100.0 / maxf(30.0, float(g.nation_dev(target)) + 20.0)
	return minf(cost, 100.0 if demands.size() > 0 else 0.0)


func peace_acceptance(w: Dictionary, demander: String, target: String, demands: Array) -> Array:
	## [accepts, score, reasons] from the target AI's point of view.
	var ws = score_for(w, demander)
	var cost = peace_cost(w, demander, target, demands)
	var reasons: Array = []
	reasons.append(["War score", ws])
	reasons.append(["Cost of the demands", -cost])
	var we = float(g.nations[target]["war_exhaustion"])
	if we > 0.0:
		reasons.append(["Their war exhaustion", we * 1.5])
	var months = (g.day_index - int(w["start"])) / 30.0
	if months > 24.0:
		reasons.append(["Long war", minf(15.0, (months - 24.0) / 4.0)])
	if demands.is_empty() or (demands.size() == 1 and demands[0].get("type", "") == "white"):
		reasons.append(["White peace", 5.0])
	var total = 0.0
	for r in reasons:
		total += float(r[1])
	return [total >= 0.0, total, reasons]


func can_demand(w: Dictionary, demander: String, target: String, d: Dictionary) -> String:
	match d.get("type", ""):
		"province":
			var p: Dictionary = g.provinces[int(d["pid"])]
			if war_side(w, p["owner"]) != war_side(w, target):
				return "Not theirs."
			if p["owner"] != target and target != enemy_leader(w, demander):
				return "Only from the nation you make peace with."
		"annex":
			for pid in g.owned(target):
				if war_side(w, g.provinces[pid]["controller"]) != war_side(w, demander):
					return "Occupy all their provinces first."
		"vassalize":
			if g.nations[target]["overlord"] != "":
				return "Already a subject."
	return ""


func offer_peace(w: Dictionary, demander: String, target: String, demands: Array) -> bool:
	## The demander proposes; an AI target answers at once, the player gets an event.
	if target == g.player_tag:
		var parts: PackedStringArray = []
		for d in demands:
			parts.append(describe_demand(d))
		g.fire_dynamic_event({"id": "peace_offer", "title": "Peace Offer",
			"text": "%s offers peace in %s.\nTerms: %s." % [g.nation_name(demander), w["name"], ", ".join(parts) if parts.size() > 0 else "white peace"],
			"options": [{"text": "Accept.", "effects": [{"type": "accept_peace", "war": w["id"], "demander": demander, "target": target, "demands": demands}]},
				{"text": "Refuse.", "effects": []}]}, target)
		return false
	if bool(peace_acceptance(w, demander, target, demands)[0]):
		enforce_peace(w, demander, target, demands)
		return true
	return false


func describe_demand(d: Dictionary) -> String:
	match d.get("type", ""):
		"province": return g.provinces[int(d["pid"])]["name"]
		"gold": return "%d sanctum" % int(d["amount"])
		"vassalize": return "become a vassal"
		"annex": return "full annexation"
		"white": return "white peace"
	return "?"


func enforce_peace(w: Dictionary, demander: String, target: String, demands: Array) -> void:
	if not g.wars.has(w["id"]) or war_side(w, target) == "" or war_side(w, demander) == "":
		return
	# who leaves the war is settled before any land moves: losing the last province ends a nation
	var tside = war_side(w, target)
	var leaving: Array = w[tside].duplicate() if w[tside][0] == target else [target]
	var parts: PackedStringArray = []
	for d in demands:
		match d.get("type", ""):
			"province":
				var pid: int = int(d["pid"])
				var p: Dictionary = g.provinces[pid]
				g.set_province_owner(pid, demander)
				g.nations[demander]["claims"].erase(pid)
				g.add_province_modifier(pid, "recent_conquest", "Recently conquered", {"local_unrest": 2}, 60)
				parts.append(p["name"])
			"gold":
				var amt = minf(float(d["amount"]), maxf(0.0, float(g.nations[target]["treasury"])))
				g.nations[target]["treasury"] -= amt
				g.nations[demander]["treasury"] += amt
				parts.append("%d sanctum" % int(amt))
			"vassalize":
				make_vassal(demander, target)
				parts.append("vassalisation")
			"annex":
				parts.append("annexation")
	var annexing = false
	for d in demands:
		if d.get("type", "") == "annex":
			annexing = true
	g.post("Peace in %s: %s %s." % [w["name"], g.nation_name(target), "gives " + ", ".join(parts) if parts.size() > 0 else "makes a white peace"])
	# the target's side leaves the war (whole war ends if the target leads it)
	if g.wars.has(w["id"]):
		leaving = leaving.filter(func(t): return war_side(w, t) != "")
		_leave_war(w, leaving, demander)
	if annexing and g.nations[target]["alive"]:
		annex(demander, target)
	g.war_changed.emit()


func _leave_war(w: Dictionary, leaving: Array, demander: String) -> void:
	var dside = war_side(w, demander)
	for t in leaving:
		for e in w[dside]:
			set_both(t, e, "truce_until", g.day_index + TRUCE_DAYS)
		w["attackers"].erase(t)
		w["defenders"].erase(t)
	if w["attackers"].is_empty() or w["defenders"].is_empty():
		var everyone: Array = w["attackers"] + w["defenders"] + leaving
		g.wars.erase(w["id"])
		rebuild_pairs()
		_restore_control(everyone)
		for t in everyone:
			if g.nations.has(t):
				g.mil.evict(t)
				g.touch(t)
	else:
		rebuild_pairs()
		_restore_control(leaving)
		for t in leaving:
			g.mil.evict(t)
			g.touch(t)
	update_war_scores()


func _restore_control(tags: Array) -> void:
	for pid in g.provinces:
		var p: Dictionary = g.provinces[pid]
		if p["owner"] == "" or p["controller"] == p["owner"] or p["controller"] == "REB":
			continue
		if (p["owner"] in tags or p["controller"] in tags) and not at_war(p["owner"], p["controller"]):
			p["controller"] = p["owner"]
			p["siege"] = {}
			g.province_changed.emit(pid)


func end_war_with(tag: String) -> void:
	## A nation died: drop it from every war.
	for w in g.wars.values().duplicate():
		if tag in w["attackers"] or tag in w["defenders"]:
			var other: String = enemy_leader(w, tag) if (w["attackers"].size() > 0 and w["defenders"].size() > 0) else ""
			_leave_war(w, [tag], other if other != "" else tag)
	rebuild_pairs()


# ---------------------------------------------------------------- monthly

func monthly() -> void:
	for a in g.nations:
		var n: Dictionary = g.nations[a]
		if not n["alive"]:
			continue
		for b in n["relations"]:
			var r: Dictionary = n["relations"][b]
			if r.get("improving", false):
				var gain = IMPROVE_PER_MONTH * (1.0 + g.mods.nat(a, "improve_relations_mod"))
				var cur = 0.0
				if g.nations.has(b):
					for m in rel(b, a)["mods"]:
						if m["name"] == "Improved relations":
							cur = float(m["value"])
				if cur < IMPROVE_CAP and g.nations.has(b):
					add_opinion(b, a, minf(gain, IMPROVE_CAP - cur), "Improved relations", 0.0)
			var keep: Array = []
			for m in r["mods"]:
				var v = float(m["value"])
				var dec = float(m.get("decay", 1.0))
				if m["name"] == "Improved relations" and not (g.nations.has(b) and rel(b, a).get("improving", false)):
					dec = 0.5
				if dec > 0.0:
					v = v - dec if v > 0.0 else v + dec
					if absf(v) < dec:
						v = 0.0
				m["value"] = v
				if v != 0.0:
					keep.append(m)
			r["mods"] = keep
		# war exhaustion fades in peace
		if not at_war_any(a):
			n["war_exhaustion"] = maxf(0.0, float(n["war_exhaustion"]) - 0.25)
		else:
			n["war_exhaustion"] = minf(20.0, float(n["war_exhaustion"]) + 0.05)
	update_war_scores()
