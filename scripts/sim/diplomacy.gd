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
		"guarantee":
			if r.get("guarantee", false):
				return ""
			if at_war(from, to):
				return "You are at war."
			if g.nation_dev(to) > g.nation_dev(from):
				return "You can only guarantee weaker nations."
		"warn":
			if r.get("warned", false):
				return ""
			if at_war(from, to):
				return "You are at war."
		"support_rebels":
			if at_war(from, to):
				return "You are already at war: fight them instead."
			if float(n["treasury"]) < SUPPORT_REBELS_COST:
				return "Needs %d sanctum." % int(SUPPORT_REBELS_COST)
			if g.day_index - int(r.get("rebels_day", -9999)) < 365:
				return "Once a year."
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
	if action in PROPOSALS and g.is_human(from) and g.is_human(to) and from != to:
		return _propose(action, from, to)
	match action:
		"improve":
			r["improving"] = not r["improving"]
			g.touch(from)
			return ("A diplomat is improving relations with %s." if r["improving"] else "Recalled the diplomat from %s.") % nm
		"alliance":
			if g.is_human(to) or ai_accepts("alliance", from, to):
				set_both(from, to, "alliance", true)
				g.post("%s and %s are now allies." % [g.nation_name(from), nm], [from, to])
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
			if g.is_human(to) or ai_accepts("marriage", from, to):
				set_both(from, to, "marriage", true)
				g.post("A royal marriage between %s and %s." % [g.nation_name(from), nm], [from, to])
				g.touch(from)
				return "%s accepted the royal marriage." % nm
			return "%s declined the royal marriage." % nm
		"access":
			if g.is_human(to) or ai_accepts("access", from, to):
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
			if g.is_human(to) or ai_accepts("vassalize", from, to):
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
		"guarantee":
			r["guarantee"] = not r.get("guarantee", false)
			if r["guarantee"]:
				add_opinion(to, from, 25.0, "Guaranteed our independence", 0.0)
			else:
				add_opinion(to, from, -25.0, "Abandoned their guarantee", 0.5)
			g.touch(from)
			return ("You guarantee the independence of %s: you will join any war declared on them." if r["guarantee"] else "You no longer guarantee %s.") % nm
		"warn":
			r["warned"] = not r.get("warned", false)
			if r["warned"]:
				add_opinion(to, from, -20.0, "Warned us", 0.5)
			g.touch(from)
			return ("You warned %s: attack any of your neighbours and you will join the war." if r["warned"] else "You withdrew your warning to %s.") % nm
		"support_rebels":
			g.nations[from]["treasury"] = float(g.nations[from]["treasury"]) - SUPPORT_REBELS_COST
			r["rebels_day"] = g.day_index
			var restless: Array = g.owned(to).duplicate()
			restless.sort_custom(func(a, b): return float(g.provinces[a].get("unrest", 0.0)) > float(g.provinces[b].get("unrest", 0.0)))
			for pid in restless.slice(0, 3):
				g.provinces[pid]["rebel_progress"] = minf(100.0, float(g.provinces[pid]["rebel_progress"]) + 20.0)
				g.add_province_modifier(pid, "foreign_agitators", "Foreign agitators", {"local_unrest": 3}, 24)
			add_opinion(to, from, -40.0, "Supported rebels against us", 0.5)
			g.touch(from)
			g.touch(to)
			return "Your agents are arming the malcontents of %s (+3 unrest and more rebel support in three provinces, for two years)." % nm
	return ""


const SUPPORT_REBELS_COST := 60.0


func guarantors_of(tag: String) -> Array:
	var out: Array = []
	for t in g.nations:
		if t != tag and g.nations[t]["alive"] and g.nations[t]["relations"].has(tag) and g.nations[t]["relations"][tag].get("guarantee", false):
			out.append(t)
	return out


func _honour_guarantees(w: Dictionary, attacker: String, target: String) -> void:
	## EU4: guarantors defend the target; a nation that warned the attacker defends its neighbour.
	var joiners: Array = guarantors_of(target)
	for t in g.nations:
		if t == attacker or t == target or not g.nations[t]["alive"]:
			continue
		if g.nations[t]["relations"].has(attacker) and g.nations[t]["relations"][attacker].get("warned", false) and borders(t, target):
			joiners.append(t)
	for t in joiners:
		if allied(t, attacker) or war_side(w, t) != "":
			continue
		_join(w, t, "defenders")
		if war_side(w, t) == "defenders":
			g.post("%s honours its word and joins %s against %s." % [g.nation_name(t), g.nation_name(target), g.nation_name(attacker)],
				[t, target, attacker], "", true)


const PROPOSALS := {"alliance": "an alliance", "marriage": "a royal marriage", "access": "military access", "vassalize": "that you become their vassal"}


func _propose(action: String, from: String, to: String) -> String:
	## Multiplayer: one player's offer to another is an event they answer, not an AI's dice roll.
	g.fire_dynamic_event({"id": "proposal_" + action, "title": "A Proposal from %s" % g.nation_name(from),
		"text": "%s proposes %s." % [g.nation_name(from), PROPOSALS[action]],
		"options": [{"text": "Accept.", "effects": [{"type": "accept_proposal", "action": action, "from": from}]},
			{"text": "Decline.", "effects": [{"type": "decline_proposal", "action": action, "from": from}]}]}, to)
	return "Your proposal is on its way to %s." % g.nation_name(to)


func accept_proposal(action: String, from: String, to: String) -> void:
	## `to` accepted `from`'s proposal (see _propose).
	if not (g.nations.has(from) and g.nations.has(to)) or not g.nations[from]["alive"] or not g.nations[to]["alive"]:
		return
	match action:
		"alliance":
			set_both(from, to, "alliance", true)
			g.post("%s and %s are now allies." % [g.nation_name(from), g.nation_name(to)], [from, to])
		"marriage":
			set_both(from, to, "marriage", true)
			g.post("A royal marriage between %s and %s." % [g.nation_name(from), g.nation_name(to)], [from, to])
		"access":
			rel(to, from)["access"] = true
			g.tell(from, "%s grants you military access." % g.nation_name(to))
		"vassalize":
			make_vassal(from, to)
	rebuild_pairs()
	g.touch(from)
	g.touch(to)


func propose_peace(war_id: int, me: String, target: String, demands: Array, mode: String) -> String:
	## The peace window's buttons. mode: "demand" (me takes `demands` from target), "give" (me hands
	## `demands` to target) or "force" (target is fully occupied and has no say). Returns "" when the
	## war ends (or the offer is sent to another player), else why it was refused.
	var w: Dictionary = g.wars.get(war_id, {})
	if w.is_empty() or war_side(w, me) == "" or war_side(w, target) == "" or war_side(w, me) == war_side(w, target):
		return "No such war."
	var ds: Array = demands.duplicate(true)
	if ds.is_empty():
		ds = [{"type": "white"}]
	match mode:
		"force":
			if not (fully_occupied(w, me, target) and target == enemy_leader(w, me)) or peace_cost(w, me, target, demands) > 100.0:
				return "You can't force these terms."
			add_opinion(target, me, -25.0, "Enforced peace on us", 0.5)
			enforce_peace(w, me, target, ds)
			return ""
		"give":
			if g.is_human(target) and target != me:
				g.fire_dynamic_event({"id": "peace_offer", "title": "Peace Offer",
					"text": "%s offers peace in %s.\nThey give: %s." % [g.nation_name(me), w["name"], ", ".join(PackedStringArray(ds.map(describe_demand)))],
					"options": [{"text": "Accept.", "effects": [{"type": "accept_peace", "war": war_id, "demander": target, "target": me, "demands": ds}]},
						{"text": "Refuse.", "effects": []}]}, target)
				g.tell(me, "Your offer is on its way to %s." % g.nation_name(target))
				return ""
			if give_acceptance(w, target, peace_cost(w, target, me, demands))[0]:
				enforce_peace(w, target, me, ds)
				return ""
			return "%s refused." % g.nation_name(target)
		_:
			if g.is_human(target) and target != me:
				offer_peace(w, me, target, ds)
				g.tell(me, "Your demands are on their way to %s." % g.nation_name(target))
				return ""
			if peace_acceptance(w, me, target, demands)[0]:
				enforce_peace(w, me, target, ds)
				return ""
			return "%s refused your terms." % g.nation_name(target)


func give_acceptance(w: Dictionary, target: String, cost: float) -> Array:
	## Would `target` take what we offer them? [accepts, total, [[reason, value]...]]
	var their: float = score_for(w, target)
	var reasons: Array = [["What you offer", cost], ["Their war score", -maxf(0.0, their)]]
	var we = float(g.nations[target]["war_exhaustion"])
	if we > 0.0:
		reasons.append(["Their war exhaustion", we * 1.5])
	reasons.append(["Willing to end it", 5.0])
	var total = 0.0
	for r in reasons:
		total += float(r[1])
	return [total >= 0.0, total, reasons]


# ---------------------------------------------------------------- selling provinces

const SALE_PRICE_PER_DEV := 15.0


func sale_price(pid: int) -> int:
	return int(g.total_dev(pid) * SALE_PRICE_PER_DEV)


func sellable(seller: String, buyer: String) -> Array:
	## The seller's provinces next to the buyer's land that could be sold to them, smallest first.
	var out: Array = []
	for pid in g.owned(seller):
		if can_sell(seller, buyer, pid) == "":
			out.append(pid)
	out.sort_custom(func(a, b): return g.total_dev(a) < g.total_dev(b))
	return out


func can_sell(seller: String, buyer: String, pid: int) -> String:
	if seller == buyer or not g.nations.has(buyer) or not g.nations[buyer]["alive"] or not g.provinces.has(pid):
		return "Not possible."
	var p: Dictionary = g.provinces[pid]
	if p["owner"] != seller:
		return "Not your province."
	if pid == g.capital_of(seller):
		return "You can't sell your capital."
	if p["controller"] != seller or not p["siege"].is_empty():
		return "It is occupied or under siege."
	if at_war(seller, buyer):
		return "You are at war."
	if g.owned(seller).size() <= 1:
		return "It is all you have."
	for nb in p["connections"]:
		if g.provinces[nb]["owner"] == buyer:
			return ""
	return "It must border their land."


func sale_acceptance(seller: String, buyer: String, pid: int) -> Array:
	## [score, [[reason, value]]]: an AI buyer says yes above 0.
	var rs: Array = []
	var p: Dictionary = g.provinces[pid]
	var price := sale_price(pid)
	rs.append(["Opinion of you", opinion(buyer, seller) / 5.0])
	rs.append(["Base reluctance", -5.0])
	if float(g.nations[buyer]["treasury"]) < price:
		rs.append(["Can't afford %d sanctum" % price, -1000.0])
	elif float(g.nations[buyer]["treasury"]) >= price * 3.0:
		rs.append(["Has money to spare", 10.0])
	if p["culture"] == g.nations[buyer]["culture"]:
		rs.append(["Their own people live there", 20.0])
	elif g.pop.culture_group(p["culture"]) == g.pop.culture_group(g.nations[buyer]["culture"]):
		rs.append(["Kindred people live there", 8.0])
	if p["religion"] == g.nations[buyer]["religion"]:
		rs.append(["Their faith", 5.0])
	if rel(buyer, seller)["rival"]:
		rs.append(["Rivals", -1000.0])
	var total := 0.0
	for r in rs:
		total += float(r[1])
	return [total, rs]


func sell_province(seller: String, buyer: String, pid: int) -> String:
	## Offer a province for its price. An AI buyer answers at once; a player gets an offer.
	var why := can_sell(seller, buyer, pid)
	if why != "":
		return why
	var price := sale_price(pid)
	var nm: String = g.provinces[pid]["name"]
	if g.is_human(buyer):
		g.fire_dynamic_event({"id": "province_sale", "title": "A Province for Sale",
			"text": "%s offers to sell us %s (%d development) for %d sanctum." % [g.nation_name(seller), nm, g.total_dev(pid), price],
			"options": [{"text": "Buy it.", "effects": [{"type": "accept_sale", "from": seller, "pid": pid, "price": price}]},
				{"text": "No, thank you.", "effects": [{"type": "decline_proposal", "action": "sale", "from": seller}]}]}, buyer)
		return "Your offer is on its way to %s." % g.nation_name(buyer)
	if float(sale_acceptance(seller, buyer, pid)[0]) <= 0.0:
		return "%s doesn't want %s at that price." % [g.nation_name(buyer), nm]
	return complete_sale(seller, buyer, pid, price)


func complete_sale(seller: String, buyer: String, pid: int, price: int) -> String:
	## The buyer pays and the province changes hands (checked again: things change while an offer waits).
	if can_sell(seller, buyer, pid) != "":
		return "The sale of %s fell through." % g.provinces[pid]["name"]
	if float(g.nations[buyer]["treasury"]) < price:
		return "%s can't pay %d sanctum." % [g.nation_name(buyer), price]
	var nm: String = g.provinces[pid]["name"]
	g.nations[buyer]["treasury"] = float(g.nations[buyer]["treasury"]) - price
	g.nations[seller]["treasury"] = float(g.nations[seller]["treasury"]) + price
	g.set_province_owner(pid, buyer)
	g.provinces[pid]["cores"].erase(seller)
	add_opinion(buyer, seller, 15.0, "Sold us land", 0.5)
	g.post("%s sells %s to %s for %d sanctum." % [g.nation_name(seller), nm, g.nation_name(buyer), price], [seller, buyer])
	rebuild_pairs()
	g.touch(seller)
	g.touch(buyer)
	return "%s bought %s for %d sanctum." % [g.nation_name(buyer), nm, price]


func make_vassal(overlord: String, vassal: String) -> void:
	g.nations[vassal]["overlord"] = overlord
	if not g.nations[overlord]["subjects"].has(vassal):
		g.nations[overlord]["subjects"].append(vassal)
	set_both(overlord, vassal, "alliance", false)
	g.post("%s is now a vassal of %s." % [g.nation_name(vassal), g.nation_name(overlord)], [vassal, overlord], "", true)
	g.touch(overlord)
	g.touch(vassal)


func annex(by: String, target: String) -> void:
	for pid in g.owned(target):
		g.set_province_owner(pid, by)
		g.provinces[pid]["cores"][by] = true
	g.kill_nation(target)
	g.post("%s has been annexed by %s." % [g.nation_name(target), g.nation_name(by)], [target, by], "", true)


# ---------------------------------------------------------------- casus belli and war

func casus_belli(a: String, b: String) -> Array:
	var out: Array = []
	if g.global_flags.has("great_war") and ((a == "MEN" and b == "SKY") or (a == "SKY" and b == "MEN")):
		out.append({"id": "great_war", "name": "The Great War for Arcadia", "mult": 0.6})
	if g.court.gov_type(b) in ["tribe", "horde"] and not (g.court.gov_type(a) in ["tribe", "horde"]) and borders(a, b):
		out.append({"id": "tribal_conquest", "name": "Tribal Conquest", "mult": 0.6})
	if a == "SKY" and b == "BLM" or a == "BLM" and b == "SKY":
		out.append({"id": "holy_war", "name": "War against VAGA", "mult": 0.6})
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
	if a == b or not g.nations.has(b) or not g.nations[b]["alive"]:
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
	g.post("%s declares war on %s: %s." % [g.nation_name(a), g.nation_name(b), w["name"]], [a, b], "War Declared" if g.is_human(b) else "", true)
	# subjects and overlords join, allies are called
	for s in g.nations[a]["subjects"]:
		_join(w, s, "attackers")
	for s in g.nations[b]["subjects"]:
		_join(w, s, "defenders")
	if g.nations[b]["overlord"] != "":
		_join(w, g.nations[b]["overlord"], "defenders")
	# allies are not called automatically: the war leader has to ask them, and pay their price
	if g.nations[b]["ai"]:
		ai_call_allies(w, b)
	_honour_guarantees(w, a, b)
	if g.is_human(b) and allies_of(b).size() > 0:
		g.tell(b, "Call your allies to arms from the Diplomacy panel: they won't join by themselves.")
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
		"coalition": return "Coalition against %s" % g.nation_name(target)
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


func call_quote(w: Dictionary, caller: String, ally: String) -> Dictionary:
	## What `ally` says if `caller` calls it into the war, and what it wants in return.
	var out = {"why": "", "accept": false, "score": 0.0, "reasons": [], "price": 0}
	var side = war_side(w, caller)
	if side == "":
		out["why"] = "You aren't in this war."
		return out
	if ally in w["attackers"] or ally in w["defenders"]:
		out["why"] = "Already in the war."
		return out
	if not rel(caller, ally)["alliance"] and g.nations[ally]["overlord"] != caller:
		out["why"] = "Not your ally."
		return out
	var enemy: String = enemy_leader(w, caller)
	var rs: Array = []
	rs.append(["Opinion of you", opinion(ally, caller) / 3.0])
	rs.append(["Base reluctance", -10.0])
	if g.nations[ally]["overlord"] == caller:
		rs.append(["You are their overlord", 60.0])
	if rel(ally, enemy)["alliance"]:
		rs.append(["Allied to the enemy", -1000.0])
	if truce(ally, enemy):
		rs.append(["Truce with the enemy", -1000.0])
	if rel(ally, enemy)["rival"]:
		rs.append(["The enemy is their rival", 30.0])
	var op_enemy = opinion(ally, enemy)
	if op_enemy < -50.0:
		rs.append(["They hate the enemy", 15.0])
	elif op_enemy > 50.0:
		rs.append(["They like the enemy", -20.0])
	if at_war_any(ally):
		rs.append(["Already fighting another war", -50.0])
	var ratio = g.mil.nation_strength(ally) / maxf(0.5, g.mil.nation_strength(enemy))
	rs.append(["Their army against the enemy's", clampf((ratio - 1.0) * 15.0, -40.0, 15.0)])
	var near = borders(ally, enemy)
	rs.append(["Borders the enemy" if near else "Far from the enemy", 5.0 if near else -10.0])
	if rel(ally, caller)["marriage"]:
		rs.append(["Royal marriage", 10.0])
	if float(g.nations[ally]["war_exhaustion"]) > 0.0:
		rs.append(["War exhaustion", -float(g.nations[ally]["war_exhaustion"]) * 3.0])
	if int(g.nations[ally]["stability"]) < 0:
		rs.append(["Unstable at home", int(g.nations[ally]["stability"]) * 5.0])
	var total = 0.0
	for r in rs:
		total += float(r[1])
	out["reasons"] = rs
	out["score"] = total
	out["accept"] = total > 0.0
	# what they want: sanctum, more if they barely agree and if their army is big
	var regs = g.mil.regiment_count(ally)
	var price = 30.0 + regs * 15.0 + g.nation_dev(ally) * 0.5
	if total > 40.0:
		price *= 0.6
	if g.nations[ally]["overlord"] == caller:
		price = 0.0
	out["price"] = int(round(price / 5.0) * 5.0)
	return out


func call_ally(w: Dictionary, caller: String, ally: String) -> String:
	## The caller asks; if the ally agrees, the caller pays its price and it joins.
	var q = call_quote(w, caller, ally)
	if q["why"] != "":
		return q["why"]
	if not q["accept"]:
		add_opinion(caller, ally, -10.0, "Refused our call to arms", 1.0)
		return "%s refused to join the war." % g.nation_name(ally)
	if g.is_human(ally):
		g.fire_dynamic_event({
			"id": "call_to_arms", "title": "Call to Arms",
			"text": "%s asks us to join %s against %s. In return they offer %d sanctum." % [g.nation_name(caller), w["name"],
				g.nation_name(enemy_leader(w, caller)), int(q["price"])],
			"options": [
				{"text": "Join the war and take the payment.", "effects": [{"type": "join_war", "war": w["id"], "side": war_side(w, caller), "payer": caller, "price": int(q["price"])}]},
				{"text": "Refuse. (Our ally won't like it.)", "effects": [{"type": "refuse_call", "caller": caller}]}]}, ally)
		return "Asked %s to join." % g.nation_name(ally)
	if float(g.nations[caller]["treasury"]) < float(q["price"]):
		return "%s will join for %d sanctum, but you can't pay." % [g.nation_name(ally), int(q["price"])]
	g.nations[caller]["treasury"] -= float(q["price"])
	g.nations[ally]["treasury"] += float(q["price"])
	_join(w, ally, war_side(w, caller))
	add_opinion(ally, caller, 10.0, "Paid for our help", 0.5)
	g.post("%s joins %s on the side of %s (paid %d sanctum)." % [g.nation_name(ally), w["name"], g.nation_name(caller), int(q["price"])], [ally, caller])
	g.war_changed.emit()
	g.touch(caller)
	return "%s joins the war." % g.nation_name(ally)


func ai_call_allies(w: Dictionary, caller: String) -> void:
	for ally in allies_of(caller):
		var q = call_quote(w, caller, ally)
		if q["why"] == "" and q["accept"] and float(g.nations[caller]["treasury"]) >= float(q["price"]):
			call_ally(w, caller, ally)


func uncalled_allies(w: Dictionary, caller: String) -> Array:
	var out: Array = []
	for ally in allies_of(caller):
		if not (ally in w["attackers"] or ally in w["defenders"]):
			out.append(ally)
	for s2 in g.nations[caller]["subjects"]:
		if not (s2 in w["attackers"] or s2 in w["defenders"]) and not out.has(s2):
			out.append(s2)
	return out


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
				cost += float(d.get("pct", 0.25)) * 40.0 * 100.0 / maxf(30.0, float(g.nation_dev(target)) + 20.0) / 2.0
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
	reasons.append(["Cost of the demands", -cost * 1.15])
	reasons.append(["Refuses to give in", -15.0])
	var we = float(g.nations[target]["war_exhaustion"])
	if we > 0.0:
		reasons.append(["Their war exhaustion", we])
	var months = (g.day_index - int(w["start"])) / 30.0
	if months > 36.0:
		reasons.append(["Long war", minf(10.0, (months - 36.0) / 6.0)])
	var their_str = g.mil.nation_strength(target)
	var my_str = g.mil.nation_strength(demander)
	if their_str > my_str:
		reasons.append(["Their army is stronger", -10.0])
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


func fully_occupied(w: Dictionary, demander: String, target: String) -> bool:
	## Every province of the target is held by the demander's side: peace can be enforced.
	var owned: Array = g.owned(target)
	if owned.is_empty():
		return false
	var side = war_side(w, demander)
	for pid in owned:
		if war_side(w, g.provinces[pid]["controller"]) != side:
			return false
	return true


func gold_amount(target: String, pct: float) -> int:
	return int(pct * maxf(0.0, float(g.nations[target].get("last_income", 0.0))) * 12.0)


func offer_peace(w: Dictionary, demander: String, target: String, demands: Array) -> bool:
	## The demander proposes; an AI target answers at once, the player gets an event.
	if g.is_human(target):
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
		"gold": return "%d%% of a year's income" % int(float(d.get("pct", 0.25)) * 100.0)
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
	var ae_dev := _ae_dev(demands, target, demander)   # before any land moves
	var ae_mult := _ae_cb_mult(w, demander)
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
				var want = float(d.get("pct", 0.25)) * maxf(0.0, float(g.nations[target].get("last_income", 0.0))) * 12.0
				var amt = minf(want, maxf(0.0, float(g.nations[target]["treasury"])) + want * 0.5)
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
	g.post("Peace in %s: %s %s." % [w["name"], g.nation_name(target), "gives " + ", ".join(parts) if parts.size() > 0 else "makes a white peace"], [demander, target], "Peace" if g.is_human(target) or not g.is_human(demander) else "")
	if ae_dev > 0.0:
		add_aggressive_expansion(demander, target, ae_dev, ae_mult)
	if parts.size() > 0:   # a won peace brings prestige; giving in costs it
		g.standing.add_prestige(demander, minf(25.0, 5.0 + ae_dev * 0.4))
		g.standing.add_prestige(target, -10.0)
	# a coalition that wins its war has done its job: it disbands and its members forgive
	if w["cb"].get("id", "") == "coalition" and war_side(w, demander) == "attackers" and target == w["defenders"][0] and parts.size() > 0:
		disband_coalition(target, w["attackers"])
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
	update_coalitions()


# ---------------------------------------------------------------- aggressive expansion and coalitions
# EU4-style brakes on snowballing. Taking land in a peace deal gives every other nation an
# "Aggressive expansion" opinion of the taker (stronger next door, and among those who share the
# victim's faith or culture group). Enough of it and they band together into a coalition, which
# declares war once it is big enough.

const AE_NAME := "Aggressive expansion"
const AE_PER_DEV := 1.0        # per point of development taken, before the casus belli and distance
const AE_CORE_FACTOR := 0.5    # retaking your own cores causes half the outrage
const AE_DECAY := 0.5          # a month
const AE_FAR := 0.35           # nations that border neither side feel this much of it
const COALITION_JOIN := 50.0   # AE at which a nation joins a coalition
const COALITION_LEAVE := 25.0
const COALITION_MIN_DEV := 60  # nobody forms a coalition against a small realm
const COALITION_MIN_MEMBERS := 3
const COALITION_MONTHS := 12   # how long a coalition holds together before it declares war


func aggressive_expansion(of: String, toward: String) -> float:
	## How much aggressive expansion `of` holds against `toward` (a positive number).
	if not g.nations.has(of) or not g.nations.has(toward) or of == toward:
		return 0.0
	for m in rel(of, toward)["mods"]:
		if m["name"] == AE_NAME:
			return maxf(0.0, -float(m["value"]))
	return 0.0


func ae_amounts(taker: String, victim: String, dev: float, cb_mult: float) -> Dictionary:
	## tag -> AE each other nation would get if `taker` took `dev` development from `victim`.
	var out := {}
	if dev <= 0.0:
		return out
	var vic: Dictionary = g.nations.get(victim, {})
	for t in g.nations:
		var n: Dictionary = g.nations[t]
		if t == taker or t == victim or not n["alive"] or t in ["REB", "ENT"]:
			continue
		if n["overlord"] == taker:
			continue
		var f := 1.0 if (borders(t, taker) or borders(t, victim)) else AE_FAR
		if not vic.is_empty():
			if n["religion"] == vic["religion"]:
				f *= 1.25
			if g.pop.culture_group(n["culture"]) == g.pop.culture_group(vic["culture"]):
				f *= 1.25
		out[t] = dev * AE_PER_DEV * cb_mult * f
	return out


func ae_preview(w: Dictionary, demander: String, target: String, demands: Array) -> Array:
	## [worst AE any nation would get, that nation] for a peace deal, for the peace screen.
	var dev := _ae_dev(demands, target, demander)
	var amounts := ae_amounts(demander, target, dev, _ae_cb_mult(w, demander))
	var worst := 0.0
	var who := ""
	for t in amounts:
		if float(amounts[t]) > worst:
			worst = float(amounts[t])
			who = t
	return [worst, who]


func _ae_dev(demands: Array, target: String, demander: String) -> float:
	## Development that counts toward aggressive expansion. Land that is already the demander's core
	## counts half (AE_CORE_FACTOR): taking back what was yours angers people less.
	var dev := 0.0
	for d in demands:
		match d.get("type", ""):
			"province": dev += _ae_province_dev(int(d["pid"]), demander)
			"annex":
				for pid in g.owned(target):
					dev += _ae_province_dev(pid, demander)
			"vassalize": dev += float(g.nation_dev(target)) * 0.5
	return dev


func _ae_province_dev(pid: int, demander: String) -> float:
	var dev := float(g.total_dev(pid))
	return dev * AE_CORE_FACTOR if g.provinces[pid]["cores"].has(demander) else dev


func _ae_cb_mult(w: Dictionary, demander: String) -> float:
	# a good casus belli (claims, tribal conquest) causes less outrage, like EU4's CB AE modifiers
	if war_side(w, demander) != "attackers":
		return 0.75
	return clampf(float(w["cb"].get("mult", 1.0)) * 1.25, 0.6, 1.5)


func add_aggressive_expansion(taker: String, victim: String, dev: float, cb_mult: float) -> void:
	var amounts := ae_amounts(taker, victim, dev, cb_mult)
	for t in amounts:
		add_opinion(t, taker, -float(amounts[t]), AE_NAME, AE_DECAY)


func coalition_against(tag: String) -> Array:
	return g.nations.get(tag, {}).get("coalition", [])


func update_coalitions() -> void:
	## Monthly: nations join and leave coalitions, and a coalition that is big enough declares war.
	for x in g.nations:
		var n: Dictionary = g.nations[x]
		if not n["alive"] or x in ["REB", "ENT"]:
			if n.has("coalition"):
				n["coalition"] = []
			continue
		var members: Array = n.get("coalition", []).duplicate()
		var big: bool = g.nation_dev(x) >= COALITION_MIN_DEV
		for t in g.nations:
			if t == x or t in ["REB", "ENT"] or g.is_human(t):
				continue   # the player decides for themselves (EU4 lets you refuse to join)
			var tn: Dictionary = g.nations[t]
			var ae := aggressive_expansion(t, x)
			var can_be: bool = big and tn["alive"] and tn["overlord"] != x and not rel(t, x)["alliance"] and tn["overlord"] == ""
			if t in members:
				if not can_be or ae < COALITION_LEAVE:
					members.erase(t)
					g.tell(x, "%s has left the coalition against us." % g.nation_name(t))
			elif can_be and ae >= COALITION_JOIN:
				members.append(t)
				g.post("%s joins the coalition against %s." % [g.nation_name(t), g.nation_name(x)], [t, x], "Coalition" if g.is_human(x) else "")
		n["coalition"] = members
		if members.size() < COALITION_MIN_MEMBERS:
			n.erase("coalition_since")
			continue
		if not n.has("coalition_since"):
			n["coalition_since"] = g.day_index
		if g.day_index - int(n["coalition_since"]) < COALITION_MONTHS * 30:
			continue
		_maybe_coalition_war(x, members)


func coalition_strength(x: String) -> Array:
	## [coalition army strength, target's own strength]
	var theirs := 0.0
	for t in coalition_against(x):
		theirs += g.mil.nation_strength(t)
	return [theirs, g.mil.nation_strength(x)]


func _maybe_coalition_war(x: String, members: Array) -> void:
	var free: Array = members.filter(func(t): return not at_war(t, x) and not truce(t, x) and not at_war_any(t))
	if free.size() < COALITION_MIN_MEMBERS:
		return
	var st := coalition_strength(x)
	if float(st[0]) < float(st[1]) * 0.8:
		return
	free.sort_custom(func(a, b): return g.nation_dev(a) > g.nation_dev(b))
	var leader: String = free[0]
	var w := declare_war(leader, x, {"id": "coalition", "name": "Coalition", "mult": 0.75})
	if w.is_empty():
		return
	for t in free.slice(1):
		_join(w, t, "attackers")
	g.nations[x]["coalition_since"] = g.day_index   # no second war from the same coalition right away
	g.post("A coalition of %d nations led by %s marches against %s!" % [free.size(), g.nation_name(leader), g.nation_name(x)],
		[leader, x], "Coalition War" if g.is_human(x) else "", true)
	rebuild_pairs()
	g.war_changed.emit()


func disband_coalition(target: String, winners: Array) -> void:
	## After a coalition beats its target: the coalition breaks up and everyone in it (and anyone who
	## fought on its side) drops their aggressive expansion toward the target, so it doesn't re-form
	## the moment the truce ends.
	if not g.nations.has(target):
		return
	var members: Array = coalition_against(target).duplicate()
	for t in winners:
		if not members.has(t):
			members.append(t)
	for t in members:
		if g.nations.has(t) and g.nations[t]["relations"].has(target):
			var r: Dictionary = rel(t, target)
			r["mods"] = r["mods"].filter(func(m): return m["name"] != AE_NAME)
	g.nations[target]["coalition"] = []
	g.nations[target].erase("coalition_since")
	g.post("The coalition against %s has won its war and disbands." % g.nation_name(target), [target] + members)
