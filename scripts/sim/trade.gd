extends RefCounted
## Trade nodes, EU4-style. Each month every node's value (the goods made in its provinces plus what
## flows in from upstream) is split by trade power. Nations collecting there take their share as
## income; the rest flows downstream (merchants steering it add a bonus). Nobody collects at the end
## node except the nations there, so steering trade toward your home node is how you grow rich.

var g: Node
var nodes = {}          # name -> definition from data/trade.json
var order: Array = []    # upstream first
var upstream = {}       # name -> [names flowing in]
var state = {}          # name -> {local, incoming, value, outgoing, power: {tag: tp}, collected: {tag: amount}}
var income = {}         # tag -> monthly trade income
var home_bonus = 0.1
var away_penalty = 0.5
var steer_bonus = 0.1


func _init(game: Node) -> void:
	g = game


func load_data(d: Dictionary) -> void:
	nodes = d.get("nodes", {})
	home_bonus = float(d.get("home_bonus", 0.1))
	away_penalty = float(d.get("collect_away_penalty", 0.5))
	steer_bonus = float(d.get("steer_bonus", 0.1))
	upstream.clear()
	for k in nodes:
		upstream[k] = []
	for k in nodes:
		for dn in nodes[k].get("downstream", []):
			upstream[dn].append(k)
	# order: repeatedly take nodes whose upstream are all done
	order.clear()
	var done = {}
	var guard = 0
	while order.size() < nodes.size() and guard < 100:
		guard += 1
		for k in nodes:
			if done.has(k):
				continue
			var ok = true
			for u in upstream[k]:
				if not done.has(u):
					ok = false
			if ok:
				order.append(k)
				done[k] = true


func home_node(tag: String) -> String:
	var cap: int = g.capital_of(tag)
	return g.provinces[cap]["trade_node"] if cap >= 0 else ""


func merchants(tag: String) -> int:
	var base = 1 if g.nations[tag]["government"] == "boar_tribe" else 2
	return base + int(g.mods.nat(tag, "merchants"))


func merchants_used(tag: String) -> int:
	return g.nations[tag]["merchants"].size()


func collects(tag: String, node: String) -> bool:
	return node == home_node(tag) or g.nations[tag]["merchants"].get(node, "") == "collect"


func province_trade_power(pid: int) -> float:
	var p: Dictionary = g.provinces[pid]
	if p["owner"] == "" or p["controller"] != p["owner"]:
		return 0.0
	return (0.2 * g.total_dev(pid) + g.mods.loc(pid, "local_trade_power")) * g.eco.autonomy_factor(pid)


func power_in(tag: String, node: String) -> float:
	var tp = 0.0
	for pid in g.node_provinces.get(node, []):
		if g.provinces[pid]["owner"] == tag:
			tp += province_trade_power(pid)
	tp += g.mil.trade_protection(tag, node)
	var m: String = g.nations[tag]["merchants"].get(node, "")
	if m != "":
		tp += 2.0
	if tp <= 0.0:
		return 0.0
	var mult = 1.0 + g.mods.nat(tag, "trade_power_mod")
	if node == home_node(tag):
		mult += home_bonus
	elif m == "collect":
		mult *= away_penalty
	return tp * maxf(0.1, mult)


func monthly() -> void:
	state.clear()
	income.clear()
	var incoming = {}
	for k in nodes:
		incoming[k] = 0.0
	for k in order:
		var local = 0.0
		for pid in g.node_provinces.get(k, []):
			local += g.eco.goods_value(pid) / 12.0
		local = local * float(nodes[k].get("value_mult", 1.0)) + float(nodes[k].get("base_value", 0.0))
		var value: float = local + float(incoming[k])
		var power = {}
		var total = 0.0
		for tag in g.nations:
			if not g.nations[tag]["alive"]:
				continue
			var tp = power_in(tag, k)
			if tp > 0.0:
				power[tag] = tp
				total += tp
		var collected = {}
		var outgoing = 0.0
		if total <= 0.0:
			outgoing = value
		else:
			for tag in power:
				var share: float = power[tag] / total
				if collects(tag, k):
					var amt: float = value * share * (1.0 + g.mods.nat(tag, "trade_efficiency"))
					collected[tag] = amt
					income[tag] = float(income.get(tag, 0.0)) + amt
				else:
					var bonus = steer_bonus if g.nations[tag]["merchants"].get(k, "") == "steer" else 0.0
					outgoing += value * share * (1.0 + bonus)
		var down: Array = nodes[k].get("downstream", [])
		for dn in down:
			incoming[dn] = float(incoming[dn]) + outgoing / float(down.size())
		state[k] = {"local": local, "incoming": incoming[k], "value": value, "outgoing": outgoing if not down.is_empty() else 0.0,
			"power": power, "total_power": total, "collected": collected}


func share(tag: String, node: String) -> float:
	var s: Dictionary = state.get(node, {})
	var total = float(s.get("total_power", 0.0))
	if total <= 0.0:
		return 0.0
	return float(s.get("power", {}).get(tag, 0.0)) / total


func can_send(tag: String, node: String, mode: String) -> String:
	var n: Dictionary = g.nations[tag]
	if node == home_node(tag) and mode == "collect":
		return "You already collect in your home node."
	if not n["merchants"].has(node) and merchants_used(tag) >= merchants(tag):
		return "No free merchants (%d)." % merchants(tag)
	if mode == "steer" and nodes[node].get("downstream", []).is_empty():
		return "Nothing to steer: this is the end node."
	var present = false
	for pid in g.node_provinces.get(node, []):
		if g.provinces[pid]["owner"] == tag or g.is_connected_to_owned(tag, pid):
			present = true
			break
	if not present:
		return "You need a province in or next to this node."
	return ""


func send_merchant(tag: String, node: String, mode: String) -> bool:
	if can_send(tag, node, mode) != "":
		return false
	g.nations[tag]["merchants"][node] = mode
	g.touch(tag)
	return true


func recall_merchant(tag: String, node: String) -> void:
	g.nations[tag]["merchants"].erase(node)
	g.touch(tag)
