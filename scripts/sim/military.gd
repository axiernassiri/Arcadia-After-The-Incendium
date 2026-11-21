extends RefCounted
## Armies, navies (Skyfall's are airships), generals, recruitment, movement, battles, sieges,
## blockades, attrition, reinforcement and rebel armies.

const BASE_MORALE := 2.5
const REGIMENT := 1000.0
const SIEGE_UNFORTIFIED_DAYS := 12.0
const REBEL_HOLD_DAYS := 180

var g: Node


func _init(game: Node) -> void:
	g = game


# ---------------------------------------------------------------- queries

func armies_of(tag: String) -> Array:
	var out: Array = []
	for id in g.armies:
		if g.armies[id]["owner"] == tag:
			out.append(g.armies[id])
	return out


func fleets_of(tag: String) -> Array:
	var out: Array = []
	for id in g.fleets:
		if g.fleets[id]["owner"] == tag:
			out.append(g.fleets[id])
	return out


func armies_at(pid: int) -> Array:
	var out: Array = []
	for id in g.armies:
		if int(g.armies[id]["location"]) == pid:
			out.append(g.armies[id])
	return out


func fleets_at(pid: int) -> Array:
	var out: Array = []
	for id in g.fleets:
		if int(g.fleets[id]["location"]) == pid:
			out.append(g.fleets[id])
	return out


func army_men(a: Dictionary) -> float:
	var m = 0.0
	for r in a["regiments"]:
		m += float(r["men"])
	return m


func regiment_count(tag: String) -> int:
	var c = 0
	for a in armies_of(tag):
		c += a["regiments"].size()
	for q in g.recruit_queue:
		if q["tag"] == tag and q["kind"] == "land":
			c += 1
	return c


func ship_count(tag: String) -> int:
	var c = 0
	for f in fleets_of(tag):
		c += f["ships"].size()
	for q in g.recruit_queue:
		if q["tag"] == tag and q["kind"] == "ship":
			c += 1
	return c


func transport_capacity(tag: String) -> int:
	var c = 0
	for f in fleets_of(tag):
		for s in f["ships"]:
			c += int(g.unit_data["ships"].get(s["type"], {}).get("capacity", 0))
	return c


func own_troops_in(tag: String, pid: int) -> int:
	var c = 0
	for a in armies_at(pid):
		if a["owner"] == tag:
			c += a["regiments"].size()
	return c


func rebels_near(pid: int) -> bool:
	for a in armies_at(pid):
		if a["owner"] == "REB":
			return true
	for n in g.provinces[pid]["connections"]:
		for a in armies_at(n):
			if a["owner"] == "REB":
				return true
	return false


func leader(tag: String, lid: int) -> Dictionary:
	if not g.nations.has(tag):
		return {}
	for l in g.nations[tag]["leaders"]:
		if int(l["id"]) == lid:
			return l
	return {}


func army_leader(a: Dictionary) -> Dictionary:
	if int(a.get("leader", -1)) < 0:
		return {}
	return leader(a["owner"], int(a["leader"]))


# ---------------------------------------------------------------- strength and costs

func max_morale(tag: String) -> float:
	if tag == "REB":
		return 2.0
	var slider = float(g.nations[tag]["maintenance"]["land"])
	return BASE_MORALE * (1.0 + g.mods.nat(tag, "land_morale")) * (0.5 + 0.5 * slider)


func max_naval_morale(tag: String) -> float:
	var slider = float(g.nations[tag]["maintenance"]["naval"])
	return BASE_MORALE * (1.0 + g.mods.nat(tag, "naval_morale")) * (0.5 + 0.5 * slider)


func unit_power(tag: String, utype: String, phase: String) -> float:
	var ud: Dictionary = g.unit_data["land"].get(utype, {})
	var base = float(ud.get(phase, 1.0))
	if tag == "REB":
		return base * 0.9
	var key: String = {"inf": "infantry_power", "cav": "cavalry_power", "art": "artillery_power"}.get(utype, "")
	var tech: int = int(g.nations[tag]["tech"][2])
	return base * (1.0 + g.mods.nat(tag, key)) * (1.0 + 0.06 * tech) * (1.0 + g.mods.nat(tag, "discipline"))


func army_strength(a: Dictionary) -> float:
	## Rough combat value, used by the AI and the UI.
	var s = 0.0
	var mm = max_morale(a["owner"])
	for r in a["regiments"]:
		var p = (unit_power(a["owner"], r["type"], "fire") + unit_power(a["owner"], r["type"], "shock")) * 0.5
		s += float(r["men"]) / REGIMENT * p * (0.4 + 0.6 * clampf(float(r["morale"]) / maxf(mm, 0.1), 0.0, 1.0))
	var l = army_leader(a)
	if not l.is_empty():
		s *= 1.0 + 0.05 * (int(l["fire"]) + int(l["shock"]))
	return s


func nation_strength(tag: String) -> float:
	var s = 0.0
	for a in armies_of(tag):
		s += army_strength(a)
	return s + float(g.nations[tag]["manpower"]) / 4000.0


func land_force_limit(tag: String) -> int:
	return 6 + int(g.nation_dev(tag) / 12.0) + int(g.mods.nat(tag, "land_force_limit"))


func naval_force_limit(tag: String) -> int:
	var coastal = 0
	for pid in g.owned(tag):
		if g.provinces[pid]["coastal"]:
			coastal += 1
	return 4 + int(coastal / 3.0) + int(g.mods.nat(tag, "naval_force_limit"))


func land_maintenance(tag: String) -> float:
	var regs = 0
	var cost = 0.0
	for a in armies_of(tag):
		for r in a["regiments"]:
			cost += float(g.unit_data["land"].get(r["type"], {}).get("maintenance", 0.2))
			regs += 1
	var fl = land_force_limit(tag)
	var over = 1.0 + maxf(0.0, float(regs - fl)) / maxf(1.0, float(fl))
	return cost * float(g.nations[tag]["maintenance"]["land"]) * maxf(0.2, 1.0 + g.mods.nat(tag, "land_maintenance_mod")) * over


func naval_maintenance(tag: String) -> float:
	var ships = 0
	var cost = 0.0
	for f in fleets_of(tag):
		for s in f["ships"]:
			cost += float(g.unit_data["ships"].get(s["type"], {}).get("maintenance", 0.2))
			ships += 1
	var fl = naval_force_limit(tag)
	var over = 1.0 + maxf(0.0, float(ships - fl)) / maxf(1.0, float(fl))
	return cost * float(g.nations[tag]["maintenance"]["naval"]) * maxf(0.2, 1.0 + g.mods.nat(tag, "naval_maintenance_mod")) * over


func unit_name(tag: String, utype: String) -> String:
	if tag != "REB" and g.nations.has(tag):
		var eth: String = g.nations[tag]["ethnicity"]
		if eth in ["Human", "Angel"]:
			return g.unit_data.get("sky_names", {}).get(utype, utype)
		if g.nations[tag]["government"] == "boar_tribe":
			return g.unit_data.get("tribe_names", {}).get(utype, utype)
	return g.unit_data["land"].get(utype, {}).get("name", utype)


func ship_name(tag: String, stype: String) -> String:
	if g.nations.has(tag) and g.nations[tag]["ethnicity"] in ["Human", "Angel"]:
		return g.unit_data.get("airship_names", {}).get(stype, stype)
	return g.unit_data["ships"].get(stype, {}).get("name", stype)


# ---------------------------------------------------------------- recruitment

func can_recruit(tag: String, pid: int, utype: String) -> String:
	var p: Dictionary = g.provinces[pid]
	var n: Dictionary = g.nations[tag]
	var ud: Dictionary = g.unit_data["land"].get(utype, {})
	if ud.is_empty():
		return "Unknown unit."
	if p["owner"] != tag or p["controller"] != tag:
		return "Recruit in a province you own and control."
	if not g.prog.land_unit_unlocked(tag, utype):
		return "Needs military tech %d." % int(ud.get("tech", 1))
	if int(n["manpower"]) < int(ud.get("manpower", 1000)):
		return "Not enough manpower."
	if n["treasury"] < float(ud["cost"]):
		return "Needs %d sanctum." % int(ud["cost"])
	return ""


func recruit(tag: String, pid: int, utype: String) -> bool:
	if can_recruit(tag, pid, utype) != "":
		return false
	var ud: Dictionary = g.unit_data["land"][utype]
	var n: Dictionary = g.nations[tag]
	n["treasury"] -= float(ud["cost"])
	n["manpower"] = int(n["manpower"]) - int(ud.get("manpower", 1000))
	g.recruit_queue.append({"tag": tag, "pid": pid, "kind": "land", "type": utype, "done": g.day_index + 30 * int(ud.get("months", 1))})
	g.touch(tag)
	return true


func can_build_ship(tag: String, pid: int, stype: String) -> String:
	var p: Dictionary = g.provinces[pid]
	var sd: Dictionary = g.unit_data["ships"].get(stype, {})
	if sd.is_empty():
		return "Unknown ship."
	if p["owner"] != tag or p["controller"] != tag:
		return "Build ships in a province you own and control."
	if not p["coastal"]:
		return "Needs a coastal province."
	if not g.prog.ship_unlocked(tag, stype):
		return "Needs a higher diplomatic tech."
	if g.nations[tag]["treasury"] < float(sd["cost"]):
		return "Needs %d sanctum." % int(sd["cost"])
	return ""


func build_ship(tag: String, pid: int, stype: String) -> bool:
	if can_build_ship(tag, pid, stype) != "":
		return false
	var sd: Dictionary = g.unit_data["ships"][stype]
	g.nations[tag]["treasury"] -= float(sd["cost"])
	g.recruit_queue.append({"tag": tag, "pid": pid, "kind": "ship", "type": stype, "done": g.day_index + 30 * int(sd.get("months", 2))})
	g.touch(tag)
	return true


func _finish_queue() -> void:
	var keep: Array = []
	for q in g.recruit_queue:
		if int(q["done"]) > g.day_index:
			keep.append(q)
			continue
		var tag: String = q["tag"]
		if not g.nations.has(tag) or not g.nations[tag]["alive"] or g.provinces[q["pid"]]["owner"] != tag:
			continue
		if q["kind"] == "land":
			var target = {}
			for a in armies_at(q["pid"]):
				if a["owner"] == tag and a["path"].is_empty() and not a["in_battle"]:
					target = a
					break
			if target.is_empty():
				target = new_army(tag, q["pid"])
			target["regiments"].append({"type": q["type"], "men": REGIMENT, "morale": max_morale(tag)})
		else:
			var fleet = {}
			for f in fleets_at(q["pid"]):
				if f["owner"] == tag and f["path"].is_empty():
					fleet = f
					break
			if fleet.is_empty():
				fleet = new_fleet(tag, q["pid"])
			fleet["ships"].append({"type": q["type"], "hull": float(g.unit_data["ships"][q["type"]]["hull"])})
		g.armies_changed.emit()
		g.touch(tag)
	g.recruit_queue = keep


func new_army(tag: String, pid: int) -> Dictionary:
	g.next_id += 1
	var n: Dictionary = g.nations[tag]
	n["army_counter"] = int(n.get("army_counter", 0)) + 1
	var a = {"id": g.next_id, "owner": tag, "name": "%s Army %d" % [n["adjective"], n["army_counter"]],
		"location": pid, "regiments": [], "leader": -1, "path": [], "progress": 0.0, "hop_days": 0.0,
		"in_battle": false, "retreating": false, "rebel": {}, "held_days": 0}
	g.armies[g.next_id] = a
	return a


func new_fleet(tag: String, pid: int) -> Dictionary:
	g.next_id += 1
	var n: Dictionary = g.nations[tag]
	n["fleet_counter"] = int(n.get("fleet_counter", 0)) + 1
	var sky: bool = g.provinces[pid]["layer"] == "sky"
	var f = {"id": g.next_id, "owner": tag, "name": "%s %s %d" % [n["adjective"], "Air Fleet" if sky else "Fleet", n["fleet_counter"]],
		"location": pid, "ships": [], "path": [], "progress": 0.0, "hop_days": 0.0, "sky": sky, "leader": -1}
	g.fleets[g.next_id] = f
	return f


func spawn_army(tag: String, pid: int, inf: int, cav: int, art: int) -> Dictionary:
	var a = new_army(tag, pid)
	for i in inf:
		a["regiments"].append({"type": "inf", "men": REGIMENT, "morale": max_morale(tag)})
	for i in cav:
		a["regiments"].append({"type": "cav", "men": REGIMENT, "morale": max_morale(tag)})
	for i in art:
		a["regiments"].append({"type": "art", "men": REGIMENT, "morale": max_morale(tag)})
	return a


func spawn_fleet(tag: String, pid: int, counts: Dictionary) -> Dictionary:
	var f = new_fleet(tag, pid)
	for k in counts:
		for i in int(counts[k]):
			f["ships"].append({"type": k, "hull": float(g.unit_data["ships"][k]["hull"])})
	return f


func disband_army(id: int) -> void:
	if not g.armies.has(id):
		return
	var a: Dictionary = g.armies[id]
	if a["owner"] != "REB" and g.nations.has(a["owner"]):
		var back = 0.0
		for r in a["regiments"]:
			back += float(r["men"]) * 0.5
		g.nations[a["owner"]]["manpower"] = int(g.nations[a["owner"]]["manpower"]) + int(back)
		var l = army_leader(a)
		if not l.is_empty():
			l["army"] = -1
	g.armies.erase(id)
	g.armies_changed.emit()


func disband_fleet(id: int) -> void:
	g.fleets.erase(id)
	g.armies_changed.emit()


func merge_armies(ids: Array) -> void:
	if ids.size() < 2:
		return
	var first: Dictionary = g.armies[ids[0]]
	for i in range(1, ids.size()):
		var other: Dictionary = g.armies.get(ids[i], {})
		if other.is_empty() or other["owner"] != first["owner"] or int(other["location"]) != int(first["location"]) or other["in_battle"]:
			continue
		first["regiments"].append_array(other["regiments"])
		if int(first["leader"]) < 0 and int(other["leader"]) >= 0:
			first["leader"] = other["leader"]
			army_leader(first)["army"] = first["id"]
		else:
			var l = army_leader(other)
			if not l.is_empty():
				l["army"] = -1
		g.armies.erase(ids[i])
	first["path"] = []
	g.armies_changed.emit()


func split_army(id: int) -> Dictionary:
	var a: Dictionary = g.armies.get(id, {})
	if a.is_empty() or a["regiments"].size() < 2 or a["in_battle"]:
		return {}
	var b = new_army(a["owner"], int(a["location"]))
	var half = int(a["regiments"].size() / 2)
	for i in half:
		b["regiments"].append(a["regiments"].pop_back())
	g.armies_changed.emit()
	return b


# ---------------------------------------------------------------- leaders

func leader_cost() -> int:
	return 50


func can_recruit_leader(tag: String) -> String:
	if g.nations[tag]["power"][2] < leader_cost():
		return "Needs %d %s power." % [leader_cost(), g.nations[tag]["power_names"][2]]
	return ""


func recruit_leader(tag: String, kind: String = "general") -> Dictionary:
	if can_recruit_leader(tag) != "":
		return {}
	var n: Dictionary = g.nations[tag]
	n["power"][2] -= leader_cost()
	var pips = 2 + g.rng.randi_range(0, 3) + int(float(n["army_tradition"]) / 20.0)
	var stats = [0, 0, 0, 0]
	for i in pips:
		var k = g.rng.randi_range(0, 3)
		if k == 3 and stats[3] >= 2:
			k = g.rng.randi_range(0, 2)
		stats[k] = mini(6, stats[k] + 1)
	g.next_id += 1
	var names: Array = n.get("ruler_names", ["General"])
	var l = {"id": g.next_id, "name": "%s %s" % ["General" if kind == "general" else "Admiral", names[g.rng.randi_range(0, names.size() - 1)]],
		"fire": stats[0], "shock": stats[1], "maneuver": stats[2], "siege": stats[3], "kind": kind, "army": -1}
	n["leaders"].append(l)
	if tag == g.player_tag:
		g.post("New %s: %s (%d / %d / %d / %d)." % [kind, l["name"], stats[0], stats[1], stats[2], stats[3]])
	g.touch(tag)
	return l


func assign_leader(army_id: int, lid: int) -> void:
	var a: Dictionary = g.armies.get(army_id, {})
	if a.is_empty():
		return
	var old = army_leader(a)
	if not old.is_empty():
		old["army"] = -1
	a["leader"] = -1
	var l = leader(a["owner"], lid)
	if l.is_empty():
		g.armies_changed.emit()
		return
	if int(l["army"]) >= 0 and g.armies.has(int(l["army"])):
		g.armies[int(l["army"])]["leader"] = -1
	l["army"] = army_id
	a["leader"] = lid
	g.armies_changed.emit()


func leader_pips(a: Dictionary, key: String) -> int:
	var l = army_leader(a)
	var v = 0
	if not l.is_empty():
		v = int(l.get(key, 0))
	if a["owner"] != "REB" and g.nations.has(a["owner"]):
		v += int(g.mods.nat(a["owner"], "leader_" + key))
		if not l.is_empty() or key != "siege":
			pass
	return v


# ---------------------------------------------------------------- access and hostility

func hostile(a: String, b: String) -> bool:
	if a == b:
		return false
	if a == "REB" or b == "REB":
		return true   # refined per army by rebel_hostile
	return g.dip.at_war(a, b)


func armies_hostile(x: Dictionary, y: Dictionary) -> bool:
	if x["owner"] == y["owner"]:
		return false
	if x["owner"] == "REB":
		return _rebel_hostile(x, y["owner"])
	if y["owner"] == "REB":
		return _rebel_hostile(y, x["owner"])
	return g.dip.at_war(x["owner"], y["owner"])


func _rebel_hostile(reb: Dictionary, tag: String) -> bool:
	var target: String = reb["rebel"].get("target", "")
	return tag == target or g.dip.allied(tag, target)


func controller_hostile(a: Dictionary, pid: int) -> bool:
	## True if this army should besiege the province.
	var p: Dictionary = g.provinces[pid]
	var ctrl: String = p["controller"]
	var tag: String = a["owner"]
	if p["owner"] == "":
		return false
	if tag == "REB":
		return p["owner"] == a["rebel"].get("target", "") and ctrl != "REB"
	if ctrl == tag:
		return false
	if ctrl == "REB":
		return p["owner"] == tag or g.dip.allied(tag, p["owner"])
	if g.dip.at_war(tag, ctrl):
		return true
	# liberating our own or an ally's occupied province
	if (p["owner"] == tag or g.dip.allied(tag, p["owner"])) and g.dip.at_war(tag, ctrl):
		return true
	return false


func can_enter(tag: String, pid: int) -> bool:
	var p: Dictionary = g.provinces[pid]
	var owner: String = p["owner"]
	if tag == "REB" or owner == "" or owner == tag:
		return true
	if g.dip.at_war(tag, owner) or g.dip.at_war(tag, p["controller"]):
		return true
	return g.dip.has_access(tag, owner)


func edge_days(a: Dictionary, from: int, to: int) -> float:
	## Days to march from one province to the next, or -1 if impossible.
	var via: String = g.provinces[from]["connections"].get(to, "")
	var tag: String = a["owner"]
	if via == "":
		return -1.0
	if not can_enter(tag, to):
		return -1.0
	var terr = float(g.terrain_data.get(g.provinces[to]["terrain"], {}).get("move", 1.0))
	var base = 8.0 * terr
	match via:
		"sea":
			if tag != "REB" and transport_capacity(tag) < a["regiments"].size():
				return -1.0
			return base * 1.5
		"waterfall":
			return 14.0
		"air":
			var flies: bool = tag != "REB" and g.nations[tag]["ethnicity"] in ["Human", "Angel"]
			return 6.0 if flies else 14.0
	return base


func find_path(a: Dictionary, dest: int) -> Array:
	## Dijkstra by days. Returns the provinces to walk through (excluding the start), or [] if none.
	var start: int = int(a["location"])
	if start == dest:
		return []
	var dist = {start: 0.0}
	var prev = {}
	var open = [start]
	var done = {}
	while not open.is_empty():
		var best = 0
		for i in open.size():
			if float(dist[open[i]]) < float(dist[open[best]]):
				best = i
		var cur: int = open[best]
		open.remove_at(best)
		if cur == dest:
			break
		done[cur] = true
		for nb in g.provinces[cur]["connections"]:
			if done.has(nb):
				continue
			var d = edge_days(a, cur, nb)
			if d < 0.0:
				continue
			var nd: float = float(dist[cur]) + d
			if not dist.has(nb) or nd < float(dist[nb]):
				dist[nb] = nd
				prev[nb] = cur
				if not open.has(nb):
					open.append(nb)
	if not prev.has(dest):
		return []
	var path: Array = []
	var c = dest
	while c != start:
		path.push_front(c)
		c = prev[c]
	return path


func move_army(id: int, dest: int) -> bool:
	var a: Dictionary = g.armies.get(id, {})
	if a.is_empty() or a["in_battle"] or a["retreating"]:
		return false
	var path = find_path(a, dest)
	if path.is_empty():
		return false
	a["path"] = path
	a["progress"] = 0.0
	a["hop_days"] = edge_days(a, int(a["location"]), int(path[0]))
	g.armies_changed.emit()
	return true


func fleet_edge(f: Dictionary, from: int, to: int) -> float:
	var via: String = g.provinces[from]["connections"].get(to, "")
	var pt: Dictionary = g.provinces[to]
	if via == "" or not pt["coastal"] or pt["layer"] != g.provinces[from]["layer"]:
		return -1.0
	if via in ["sea", "air"]:
		return 5.0
	if via == "land":
		return 4.0
	return -1.0


func fleet_path(f: Dictionary, dest: int) -> Array:
	var start: int = int(f["location"])
	var dist = {start: 0.0}
	var prev = {}
	var open = [start]
	while not open.is_empty():
		var best = 0
		for i in open.size():
			if float(dist[open[i]]) < float(dist[open[best]]):
				best = i
		var cur: int = open[best]
		open.remove_at(best)
		if cur == dest:
			break
		for nb in g.provinces[cur]["connections"]:
			var d = fleet_edge(f, cur, nb)
			if d < 0.0:
				continue
			var nd: float = float(dist[cur]) + d
			if not dist.has(nb) or nd < float(dist[nb]):
				dist[nb] = nd
				prev[nb] = cur
				open.append(nb)
	if not prev.has(dest):
		return []
	var path: Array = []
	var c = dest
	while c != start:
		path.push_front(c)
		c = prev[c]
	return path


func move_fleet(id: int, dest: int) -> bool:
	var f: Dictionary = g.fleets.get(id, {})
	if f.is_empty():
		return false
	var path = fleet_path(f, dest)
	if path.is_empty():
		return false
	f["path"] = path
	f["progress"] = 0.0
	f["hop_days"] = fleet_edge(f, int(f["location"]), int(path[0]))
	g.armies_changed.emit()
	return true


# ---------------------------------------------------------------- daily

func daily() -> void:
	_finish_queue()
	var changed = false
	for id in g.armies.keys():
		if not g.armies.has(id):
			continue
		var a: Dictionary = g.armies[id]
		if a["in_battle"] or a["path"].is_empty():
			continue
		a["progress"] = float(a["progress"]) + 1.0
		if float(a["progress"]) >= float(a["hop_days"]):
			var nxt: int = int(a["path"].pop_front())
			a["location"] = nxt
			a["progress"] = 0.0
			changed = true
			if a["path"].is_empty():
				a["retreating"] = false
				a["hop_days"] = 0.0
			else:
				var d = edge_days(a, nxt, int(a["path"][0]))
				if d < 0.0:
					a["path"] = []
					a["retreating"] = false
				else:
					a["hop_days"] = d
	for id in g.fleets.keys():
		var f: Dictionary = g.fleets[id]
		if f["path"].is_empty():
			continue
		f["progress"] = float(f["progress"]) + 1.0
		if float(f["progress"]) >= float(f["hop_days"]):
			var nxt: int = int(f["path"].pop_front())
			f["location"] = nxt
			f["progress"] = 0.0
			changed = true
			if not f["path"].is_empty():
				f["hop_days"] = maxf(1.0, fleet_edge(f, nxt, int(f["path"][0])))
	_start_battles()
	_fight_battles()
	_naval_battles()
	_sieges()
	if g.day % 5 == 0:
		_rebel_ai()
	if changed:
		g.armies_changed.emit()


# ---------------------------------------------------------------- battles

func _start_battles() -> void:
	var seen = {}
	for id in g.armies:
		var a: Dictionary = g.armies[id]
		var pid: int = int(a["location"])
		if seen.has(pid) or a["in_battle"] or a["retreating"]:
			continue
		var here = armies_at(pid)
		if here.size() < 2:
			continue
		var side_a: Array = []
		var side_b: Array = []
		for x in here:
			if x["in_battle"] or x["retreating"]:
				continue
			if side_a.is_empty():
				side_a.append(x)
			elif armies_hostile(side_a[0], x):
				side_b.append(x)
			elif side_b.is_empty() or not armies_hostile(side_b[0], x):
				side_a.append(x)
		if side_b.is_empty():
			continue
		seen[pid] = true
		# the defender is whoever controls the province, otherwise whoever stood still
		var att = side_b
		var def = side_a
		var ctrl: String = g.provinces[pid]["controller"]
		for x in side_b:
			if x["owner"] == ctrl or (x["path"].is_empty() and not side_a[0]["path"].is_empty()):
				att = side_a
				def = side_b
				break
		var battle = {"pid": pid, "att": [], "def": [], "day": 0, "losses": [0.0, 0.0]}
		for x in att:
			x["in_battle"] = true
			x["path"] = []
			battle["att"].append(x["id"])
		for x in def:
			x["in_battle"] = true
			x["path"] = []
			battle["def"].append(x["id"])
		g.battles.append(battle)
		var involved = _side_tags(battle["att"]) + _side_tags(battle["def"])
		if g.player_tag in involved:
			g.post("Battle of %s has begun!" % g.provinces[pid]["name"])


func _side_tags(ids: Array) -> Array:
	var out: Array = []
	for i in ids:
		if g.armies.has(i) and not out.has(g.armies[i]["owner"]):
			out.append(g.armies[i]["owner"])
	return out


func _side_men(ids: Array) -> float:
	var m = 0.0
	for i in ids:
		if g.armies.has(i):
			m += army_men(g.armies[i])
	return m


func _side_morale(ids: Array) -> float:
	## Average morale as a fraction of max.
	var tot = 0.0
	var cnt = 0.0
	for i in ids:
		if not g.armies.has(i):
			continue
		var a: Dictionary = g.armies[i]
		var mm = max_morale(a["owner"])
		for r in a["regiments"]:
			tot += clampf(float(r["morale"]) / maxf(mm, 0.01), 0.0, 1.0) * float(r["men"])
			cnt += float(r["men"])
	return tot / cnt if cnt > 0.0 else 0.0


func _best_pips(ids: Array, key: String) -> int:
	var best = 0
	for i in ids:
		if g.armies.has(i):
			best = maxi(best, leader_pips(g.armies[i], key))
	return best


func _side_damage(ids: Array, phase: String, roll: int) -> float:
	var dmg = 0.0
	for i in ids:
		if not g.armies.has(i):
			continue
		var a: Dictionary = g.armies[i]
		var mm = max_morale(a["owner"])
		for r in a["regiments"]:
			var p = unit_power(a["owner"], r["type"], phase)
			if r["type"] == "art" and phase == "shock":
				p *= 0.5
			var morale_f = 0.5 + 0.5 * clampf(float(r["morale"]) / maxf(mm, 0.01), 0.0, 1.0)
			dmg += float(r["men"]) / REGIMENT * p * float(5 + maxi(roll, 0)) * 7.0 * morale_f
	return dmg


func _apply_losses(ids: Array, casualties: float, morale_frac: float) -> void:
	var total = _side_men(ids)
	if total <= 0.0:
		return
	for i in ids:
		if not g.armies.has(i):
			continue
		var a: Dictionary = g.armies[i]
		var mm = max_morale(a["owner"])
		for r in a["regiments"]:
			var share = float(r["men"]) / total
			r["men"] = maxf(0.0, float(r["men"]) - casualties * share)
			r["morale"] = maxf(0.0, float(r["morale"]) - morale_frac * mm)


func _fight_battles() -> void:
	var still: Array = []
	for b in g.battles:
		var att: Array = []
		var def: Array = []
		for i in b["att"]:
			if g.armies.has(i):
				att.append(i)
		for i in b["def"]:
			if g.armies.has(i):
				def.append(i)
		b["att"] = att
		b["def"] = def
		if att.is_empty() or def.is_empty():
			_end_battle(b, att if def.is_empty() else def, def if def.is_empty() else att)
			continue
		b["day"] = int(b["day"]) + 1
		var phase = "fire" if (int((int(b["day"]) - 1) / 3) % 2 == 0) else "shock"
		var terr = int(g.terrain_data.get(g.provinces[b["pid"]]["terrain"], {}).get("defence", 0))
		var roll_a = g.rng.randi_range(0, 9) + _best_pips(att, phase) - terr - maxi(0, _best_pips(def, "maneuver") - _best_pips(att, "maneuver"))
		var roll_d = g.rng.randi_range(0, 9) + _best_pips(def, phase)
		var men_a = _side_men(att)
		var men_d = _side_men(def)
		var dmg_to_d = _side_damage(att, phase, roll_a)
		var dmg_to_a = _side_damage(def, phase, roll_d)
		var fort_def = 0.0
		_apply_losses(def, dmg_to_d, dmg_to_d / maxf(men_d, 1.0) * 2.4 + 0.03)
		_apply_losses(att, dmg_to_a, dmg_to_a / maxf(men_a, 1.0) * 2.4 + 0.03 + fort_def)
		b["losses"][0] = float(b["losses"][0]) + minf(dmg_to_a, men_a)
		b["losses"][1] = float(b["losses"][1]) + minf(dmg_to_d, men_d)
		var ma = _side_morale(att)
		var md = _side_morale(def)
		var broken_a = ma <= 0.03 or _side_men(att) < 100.0
		var broken_d = md <= 0.03 or _side_men(def) < 100.0
		if int(b["day"]) >= 25 and not broken_a and not broken_d:
			broken_a = ma < md
			broken_d = not broken_a
		if broken_a or broken_d:
			if broken_d and not broken_a:
				_end_battle(b, att, def)
			elif broken_a and not broken_d:
				_end_battle(b, def, att)
			else:
				_end_battle(b, def, att)   # both broke: the defender holds the field
			continue
		still.append(b)
	g.battles = still


func _end_battle(b: Dictionary, winners: Array, losers: Array) -> void:
	var pid: int = int(b["pid"])
	var win_tags = _side_tags(winners)
	var lose_tags = _side_tags(losers)
	var win_men = _side_men(winners)
	var lose_men = _side_men(losers)
	var att_won = false
	for i in winners:
		if i in b["att"]:
			att_won = true
	var lw: float = float(b["losses"][0] if att_won else b["losses"][1])   # winner losses
	var ll: float = float(b["losses"][1] if att_won else b["losses"][0])   # loser losses
	for i in winners:
		if g.armies.has(i):
			g.armies[i]["in_battle"] = false
	var wiped = lose_men * 6.0 < win_men or lose_men < 300.0
	for i in losers:
		if not g.armies.has(i):
			continue
		var a: Dictionary = g.armies[i]
		a["in_battle"] = false
		if wiped:
			var l = army_leader(a)
			if not l.is_empty():
				g.nations[a["owner"]]["leaders"].erase(l)
			g.armies.erase(i)
		else:
			_retreat(a)
	# leaders can fall
	for i in winners + losers:
		if g.armies.has(i) and g.rng.randf() < 0.03:
			var l = army_leader(g.armies[i])
			if not l.is_empty():
				g.nations[g.armies[i]["owner"]]["leaders"].erase(l)
				g.armies[i]["leader"] = -1
				if g.armies[i]["owner"] == g.player_tag:
					g.post("%s fell at the Battle of %s." % [l["name"], g.provinces[pid]["name"]])
	for t in win_tags:
		if g.nations.has(t):
			g.nations[t]["army_tradition"] = minf(100.0, float(g.nations[t]["army_tradition"]) + minf(10.0, ll / 1000.0))
			g.nations[t]["battles_won"] = int(g.nations[t].get("battles_won", 0)) + 1
	for t in lose_tags:
		if g.nations.has(t):
			g.nations[t]["war_exhaustion"] = minf(20.0, float(g.nations[t]["war_exhaustion"]) + ll / 5000.0)
	for t in win_tags:
		if g.nations.has(t):
			g.nations[t]["war_exhaustion"] = minf(20.0, float(g.nations[t]["war_exhaustion"]) + lw / 8000.0)
	if not win_tags.is_empty() and not lose_tags.is_empty():
		g.dip.battle_result(win_tags[0], lose_tags[0], ll, lw)
	var names_w: PackedStringArray = []
	for t in win_tags:
		names_w.append(g.nation_name(t))
	var names_l: PackedStringArray = []
	for t in lose_tags:
		names_l.append(g.nation_name(t))
	var text = "Battle of %s: %s beat %s (%d against %d losses)%s." % [g.provinces[pid]["name"], ", ".join(names_w),
		", ".join(names_l), int(lw), int(ll), ", wiping them out" if wiped else ""]
	if g.player_tag in win_tags or g.player_tag in lose_tags:
		g.post(text)
	g.armies_changed.emit()


func _retreat(a: Dictionary) -> void:
	var tag: String = a["owner"]
	var start: int = int(a["location"])
	var best = -1
	var seen = {start: true}
	var frontier = [start]
	while not frontier.is_empty() and best < 0:
		var nxt: Array = []
		for c in frontier:
			for nb in g.provinces[c]["connections"]:
				if seen.has(nb) or edge_days(a, c, nb) < 0.0:
					continue
				seen[nb] = true
				var p: Dictionary = g.provinces[nb]
				var friendly: bool = (p["controller"] == tag) or (tag != "REB" and (g.dip.allied(tag, p["controller"]) or p["owner"] == ""))
				if tag == "REB":
					friendly = p["controller"] == "REB" or p["owner"] == a["rebel"].get("target", "")
				var safe = true
				for x in armies_at(nb):
					if armies_hostile(a, x):
						safe = false
				if friendly and safe:
					best = nb
					break
				nxt.append(nb)
			if best >= 0:
				break
		frontier = nxt
	if best < 0:
		g.armies.erase(a["id"])
		return
	a["path"] = find_path(a, best)
	if a["path"].is_empty():
		a["path"] = [best]
	a["retreating"] = true
	a["progress"] = 0.0
	a["hop_days"] = maxf(1.0, edge_days(a, start, int(a["path"][0])))
	for r in a["regiments"]:
		r["morale"] = 0.0
	a["regiments"] = a["regiments"].filter(func(r): return float(r["men"]) >= 50.0)
	if a["regiments"].is_empty():
		g.armies.erase(a["id"])


# ---------------------------------------------------------------- navies

func is_blockaded(pid: int) -> bool:
	var p: Dictionary = g.provinces[pid]
	if not p["coastal"] or p["owner"] == "":
		return false
	for f in fleets_at(pid):
		if f["path"].is_empty() and g.dip.at_war(f["owner"], p["owner"]):
			return true
	return false


func trade_protection(tag: String, node: String) -> float:
	var tp = 0.0
	for f in fleets_of(tag):
		if g.provinces[int(f["location"])]["trade_node"] == node:
			for s in f["ships"]:
				tp += float(g.unit_data["ships"].get(s["type"], {}).get("trade", 0.0))
	return tp


func _naval_battles() -> void:
	var done = {}
	for id in g.fleets.keys():
		if not g.fleets.has(id):
			continue
		var f: Dictionary = g.fleets[id]
		var pid: int = int(f["location"])
		if done.has(pid):
			continue
		var here = fleets_at(pid)
		var side_a: Array = [f]
		var side_b: Array = []
		for x in here:
			if x == f:
				continue
			if g.dip.at_war(f["owner"], x["owner"]):
				side_b.append(x)
			elif not g.dip.at_war(x["owner"], f["owner"]):
				side_a.append(x)
		if side_b.is_empty():
			continue
		done[pid] = true
		var ga = _guns(side_a)
		var gb = _guns(side_b)
		_hit_ships(side_b, ga * float(g.rng.randi_range(3, 9)) * 0.06)
		_hit_ships(side_a, gb * float(g.rng.randi_range(3, 9)) * 0.06)
		for x in side_a + side_b:
			x["ships"] = x["ships"].filter(func(s): return float(s["hull"]) > 0.0)
			if x["ships"].is_empty():
				g.fleets.erase(x["id"])
		if _guns(side_a) < 0.3 * gb or _guns(side_b) < 0.3 * ga:
			var losers = side_a if _guns(side_a) < _guns(side_b) else side_b
			for x in losers:
				if g.fleets.has(x["id"]):
					_fleet_retreat(x)
			if f["owner"] == g.player_tag or side_b[0]["owner"] == g.player_tag:
				g.post("Naval battle at %s." % g.provinces[pid]["name"])
		g.armies_changed.emit()


func _guns(fs: Array) -> float:
	var t = 0.0
	for f in fs:
		if not g.fleets.has(f["id"]):
			continue
		var morale = 1.0 + g.mods.nat(f["owner"], "naval_morale")
		for s in f["ships"]:
			t += float(g.unit_data["ships"].get(s["type"], {}).get("guns", 1.0)) * morale
	return t


func _hit_ships(fs: Array, dmg: float) -> void:
	var ships: Array = []
	for f in fs:
		if g.fleets.has(f["id"]):
			ships.append_array(f["ships"])
	if ships.is_empty():
		return
	for i in int(ceil(dmg)):
		var s: Dictionary = ships[g.rng.randi_range(0, ships.size() - 1)]
		s["hull"] = float(s["hull"]) - minf(1.0, dmg - i)


func _fleet_retreat(f: Dictionary) -> void:
	var cap: int = g.capital_of(f["owner"])
	var best = -1
	var best_d = INF
	for pid in g.owned(f["owner"]):
		var p: Dictionary = g.provinces[pid]
		if p["coastal"] and p["layer"] == g.provinces[int(f["location"])]["layer"] and pid != int(f["location"]):
			var d: float = (p["centre"] as Vector2).distance_to(g.provinces[int(f["location"])]["centre"])
			if d < best_d:
				best_d = d
				best = pid
	if best < 0:
		best = cap
	if best < 0:
		g.fleets.erase(f["id"])
		return
	var path = fleet_path(f, best)
	f["path"] = path
	f["progress"] = 0.0
	f["hop_days"] = 5.0
	if path.is_empty():
		f["location"] = best


# ---------------------------------------------------------------- sieges

func siege_rate(ids: Array, pid: int) -> float:
	var fort = g.eco.fort_level(pid)
	var men = 0.0
	var art = 0
	var siege_pips = 0
	var tag = ""
	for a in ids:
		men += army_men(a)
		tag = a["owner"]
		siege_pips = maxi(siege_pips, leader_pips(a, "siege"))
		for r in a["regiments"]:
			if r["type"] == "art":
				art += 1
	if fort <= 0:
		return 100.0 / SIEGE_UNFORTIFIED_DAYS if men >= 1000.0 else 0.0
	if men < fort * 1500.0:
		return 0.0
	var ability = 0.0 if tag == "REB" else g.mods.nat(tag, "siege_ability")
	var defence = 0.0
	var owner: String = g.provinces[pid]["owner"]
	if owner != "":
		defence = g.mods.nat(owner, "fort_defense")
	var blockade = 1.0 if is_blockaded(pid) else 0.0
	return (1.0 + art * 0.8 + siege_pips * 0.6 + ability * 10.0 + blockade) / (fort * (1.0 + defence)) * 2.0


func _sieges() -> void:
	var by_pid = {}
	for id in g.armies:
		var a: Dictionary = g.armies[id]
		if a["in_battle"] or a["retreating"] or not a["path"].is_empty():
			continue
		var pid: int = int(a["location"])
		if controller_hostile(a, pid):
			if not by_pid.has(pid):
				by_pid[pid] = []
			by_pid[pid].append(a)
	for pid in g.provinces:
		var p: Dictionary = g.provinces[pid]
		if not by_pid.has(pid):
			if not p["siege"].is_empty():
				p["siege"] = {}
			continue
		var group: Array = by_pid[pid]
		var tag: String = group[0]["owner"]
		if p["siege"].get("tag", "") != tag:
			p["siege"] = {"tag": tag, "progress": 0.0}
		p["siege"]["progress"] = float(p["siege"]["progress"]) + siege_rate(group, pid)
		if float(p["siege"]["progress"]) >= 100.0:
			p["siege"] = {}
			var new_ctrl = tag
			if tag != "REB" and (p["owner"] == tag or (g.dip.allied(tag, p["owner"]) and not g.dip.at_war(tag, p["owner"]))):
				new_ctrl = p["owner"]
			var old: String = p["controller"]
			p["controller"] = new_ctrl
			if tag == "REB":
				group[0]["held_days"] = 0
			var who = g.nation_name(tag) if tag != "REB" else group[0]["name"]
			if g.player_tag in [p["owner"], tag, old]:
				g.post("%s %s %s." % [who, "liberated" if new_ctrl == p["owner"] else "occupied", p["name"]])
			g.province_changed.emit(pid)
			g.dip.update_war_scores()


# ---------------------------------------------------------------- rebels

func spawn_rebels(pid: int, rtype: String) -> void:
	var p: Dictionary = g.provinces[pid]
	var regs = clampi(int(g.total_dev(pid) / 4) + 1, 1, 8)
	var tag = "REB"
	g.next_id += 1
	var label: String = g.peoples.get("rebels", {}).get(rtype, {}).get("name", "Rebels")
	var nm = "%s %s" % [p["culture"] if rtype == "separatists" else p["name"], label]
	var a = {"id": g.next_id, "owner": tag, "name": nm, "location": pid, "regiments": [], "leader": -1, "path": [],
		"progress": 0.0, "hop_days": 0.0, "in_battle": false, "retreating": false, "held_days": 0,
		"rebel": {"type": rtype, "target": p["owner"], "culture": p["culture"], "religion": p["religion"],
			"home": pid, "home_name": p["name"]}}
	for i in regs:
		a["regiments"].append({"type": "inf" if i % 4 != 3 else "cav", "men": REGIMENT, "morale": 2.0})
	g.armies[g.next_id] = a
	g.post("%s have risen in %s! (%d regiments)" % [nm, p["name"], regs])
	if p["owner"] == g.player_tag:
		g.fire_event("rebels_rise", g.player_tag)
	g.armies_changed.emit()


func _rebel_ai() -> void:
	for id in g.armies.keys():
		if not g.armies.has(id):
			continue
		var a: Dictionary = g.armies[id]
		if a["owner"] != "REB" or a["in_battle"] or a["retreating"]:
			continue
		var target: String = a["rebel"].get("target", "")
		if not g.nations.has(target) or not g.nations[target]["alive"]:
			g.armies.erase(id)
			continue
		var home: int = int(a["rebel"]["home"])
		var hp: Dictionary = g.provinces[home]
		if hp["owner"] != target:
			g.armies.erase(id)
			continue
		if hp["controller"] == "REB" and int(a["location"]) == home:
			a["held_days"] = int(a["held_days"]) + 5
			if int(a["held_days"]) >= REBEL_HOLD_DAYS:
				var pids: Array = []
				for pid in g.provinces:
					var p: Dictionary = g.provinces[pid]
					if p["owner"] == target and p["controller"] == "REB":
						pids.append(pid)
				g.pop.enforce_rebel_demands(a["rebel"], pids)
				g.armies.erase(id)
			continue
		if not a["path"].is_empty():
			continue
		if hp["controller"] != "REB":
			if int(a["location"]) != home:
				move_army(id, home)
			continue
		# home is held: spread to a neighbour of the same people
		if int(a["location"]) == home and g.rng.randf() < 0.3:
			for nb in hp["connections"]:
				var q: Dictionary = g.provinces[nb]
				if q["owner"] == target and q["controller"] != "REB" and q["culture"] == hp["culture"]:
					var b = split_army(id)
					if not b.is_empty():
						b["owner"] = "REB"
						b["rebel"] = a["rebel"].duplicate()
						b["name"] = a["name"]
						move_army(b["id"], nb)
					break


# ---------------------------------------------------------------- monthly

func supply_limit(pid: int) -> float:
	## Regiments a province can feed before attrition sets in.
	var p: Dictionary = g.provinces[pid]
	return float(g.terrain_data.get(p["terrain"], {}).get("supply", 5)) + g.total_dev(pid) / 5.0 + g.mods.loc(pid, "local_supply")


func monthly() -> void:
	for id in g.armies.keys():
		if not g.armies.has(id):
			continue
		var a: Dictionary = g.armies[id]
		var tag: String = a["owner"]
		var pid: int = int(a["location"])
		var p: Dictionary = g.provinces[pid]
		# attrition
		var supply = supply_limit(pid)
		var regs = a["regiments"].size()
		var loss = 0.0
		if regs > supply:
			loss += 0.05 * (regs - supply) / float(regs)
		if tag != "REB" and p["owner"] != "" and g.dip.at_war(tag, p["owner"]):
			loss += 0.01
		if p["layer"] == "ground" and tag != "REB" and g.nations[tag]["ethnicity"] in ["Human", "Angel"] and not g.nations[tag]["flags"].has("breathing_masks"):
			loss += 0.04   # Skyfallins without masks suffocate below the clouds
		if loss > 0.0:
			for r in a["regiments"]:
				r["men"] = float(r["men"]) * (1.0 - loss)
		if tag == "REB" or a["in_battle"]:
			continue
		# reinforce and recover morale at home or with friends
		var friendly: bool = p["controller"] == tag or g.dip.allied(tag, p["controller"]) or p["owner"] == ""
		var n: Dictionary = g.nations[tag]
		var mm = max_morale(tag)
		for r in a["regiments"]:
			r["morale"] = minf(mm, float(r["morale"]) + mm * 0.15)
			if friendly and float(r["men"]) < REGIMENT:
				var want = minf(REGIMENT - float(r["men"]), REGIMENT * 0.1 * (1.0 + g.mods.nat(tag, "reinforce_speed")) * float(n["maintenance"]["land"]))
				var take = minf(want, float(n["manpower"]))
				r["men"] = float(r["men"]) + take
				n["manpower"] = int(n["manpower"]) - int(take)
		a["regiments"] = a["regiments"].filter(func(r): return float(r["men"]) >= 50.0)
		if a["regiments"].is_empty():
			disband_army(id)
	for tag in g.nations:
		var n: Dictionary = g.nations[tag]
		n["army_tradition"] = float(n["army_tradition"]) * 0.995
	# fleets repair in port
	for id in g.fleets:
		var f: Dictionary = g.fleets[id]
		var p: Dictionary = g.provinces[int(f["location"])]
		if p["owner"] == f["owner"] and f["path"].is_empty():
			for s in f["ships"]:
				var mx = float(g.unit_data["ships"].get(s["type"], {}).get("hull", 1.0))
				s["hull"] = minf(mx, float(s["hull"]) + mx * 0.2)


func evict(tag: String) -> void:
	## After peace: armies standing where they may no longer go walk home.
	var cap: int = g.capital_of(tag)
	for a in armies_of(tag):
		var pid: int = int(a["location"])
		if not can_enter(tag, pid) and cap >= 0:
			a["location"] = cap
			a["path"] = []
			a["in_battle"] = false
	g.armies_changed.emit()
