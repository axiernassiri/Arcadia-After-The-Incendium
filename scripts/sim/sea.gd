extends RefCounted
## Sea lanes: fleets sail through open water (and Skyfall's airships through open sky), never over land.
## The map has no sea zones, so at load we lay a grid over each layer's province index image, keep the
## cells that are water (index 0), give every coastal province a "port" cell on its shore, and route
## fleets between ports with A*. Routes are smoothed (straight runs wherever the water allows) and cached.

const STEP := 12            # grid spacing in map pixels
const SPEED := 22.0         # map pixels a fleet sails in a day

var g: Node
var _grid = {}             # layer -> {"w": cols, "h": rows, "water": PackedByteArray, "img": Image}
var _ports = {}            # pid -> Vector2i cell
var _routes = {}           # "a-b" -> {"points": PackedVector2Array, "length": float}


func _init(game: Node) -> void:
	g = game


func build() -> void:
	_grid.clear()
	_ports.clear()
	_routes.clear()
	for layer in ["ground", "sky"]:
		var tex: Texture2D = load("res://map/%s_index.png" % layer)
		if tex == null:
			continue
		var img: Image = tex.get_image()
		if img.is_compressed():
			img.decompress()
		var cols = img.get_width() / STEP
		var rows = img.get_height() / STEP
		var water = PackedByteArray()
		water.resize(cols * rows)
		for y in rows:
			for x in cols:
				water[y * cols + x] = 1 if _is_water(img, Vector2(x * STEP + STEP / 2, y * STEP + STEP / 2)) else 0
		_grid[layer] = {"w": cols, "h": rows, "water": water, "img": img}
		# ports: the shore cell nearest each coastal province's centre
		var shore = {}
		for y in rows:
			for x in cols:
				if water[y * cols + x] == 0:
					continue
				var c = Vector2(x * STEP + STEP / 2, y * STEP + STEP / 2)
				for k in 12:
					var a = TAU * k / 12.0
					var pid = _id_at(img, c + Vector2(cos(a), sin(a)) * STEP * 1.1)
					if pid > 0:
						if not shore.has(pid):
							shore[pid] = []
						if not shore[pid].has(Vector2i(x, y)):
							shore[pid].append(Vector2i(x, y))
		for pid in g.provinces:
			var p: Dictionary = g.provinces[pid]
			if p["layer"] != layer or not p["coastal"]:
				continue
			var cells: Array = shore.get(pid, [])
			var best = Vector2i(-1, -1)
			var best_d = INF
			for cell in cells:
				var d = (_centre(cell) as Vector2).distance_squared_to(p["centre"])
				if d < best_d:
					best_d = d
					best = cell
			if best.x < 0:
				best = _nearest_water(layer, p["centre"])
			if best.x >= 0:
				_ports[pid] = best


func _id_at(img: Image, pos: Vector2) -> int:
	var x = int(pos.x)
	var y = int(pos.y)
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return -1
	var c = img.get_pixel(x, y)
	return int(round(c.r * 255.0)) + int(round(c.g * 255.0)) * 256


func _is_water(img: Image, pos: Vector2) -> bool:
	return _id_at(img, pos) == 0


func _centre(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * STEP + STEP / 2, cell.y * STEP + STEP / 2)


func _water(layer: String, cell: Vector2i) -> bool:
	var gr: Dictionary = _grid[layer]
	if cell.x < 0 or cell.y < 0 or cell.x >= int(gr["w"]) or cell.y >= int(gr["h"]):
		return false
	return gr["water"][cell.y * int(gr["w"]) + cell.x] == 1


func _nearest_water(layer: String, pos: Vector2) -> Vector2i:
	var start = Vector2i(int(pos.x) / STEP, int(pos.y) / STEP)
	for r in 40:
		var best = Vector2i(-1, -1)
		var best_d = INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c = start + Vector2i(dx, dy)
				if _water(layer, c):
					var d = _centre(c).distance_squared_to(pos)
					if d < best_d:
						best_d = d
						best = c
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


func has_port(pid: int) -> bool:
	return _ports.has(pid)


func port_point(pid: int) -> Vector2:
	return _centre(_ports[pid]) if _ports.has(pid) else g.provinces[pid]["centre"]


func route(a: int, b: int) -> Dictionary:
	## {"points": PackedVector2Array from a's shore to b's shore, "length": map pixels}, or {} if no water route.
	if a == b:
		return {"points": PackedVector2Array([port_point(a)]), "length": 0.0}
	var key = "%d-%d" % [a, b]
	if _routes.has(key):
		return _routes[key]
	var out = {}
	var layer: String = g.provinces[a]["layer"]
	if _ports.has(a) and _ports.has(b) and layer == g.provinces[b]["layer"] and _grid.has(layer):
		var cells = _astar(layer, _ports[a], _ports[b])
		if not cells.is_empty():
			var pts = _smooth(layer, cells)
			var length = 0.0
			for i in range(1, pts.size()):
				length += pts[i - 1].distance_to(pts[i])
			out = {"points": pts, "length": length}
	_routes[key] = out
	var back = {}
	if not out.is_empty():
		var rev = out["points"].duplicate()
		rev.reverse()
		back = {"points": rev, "length": out["length"]}
	_routes["%d-%d" % [b, a]] = back
	return out


func days(a: int, b: int) -> float:
	var r = route(a, b)
	if r.is_empty():
		return -1.0
	return maxf(1.0, float(r["length"]) / SPEED)


func point_along(points: PackedVector2Array, frac: float) -> Vector2:
	## The point a fraction of the way along a route.
	if points.is_empty():
		return Vector2.ZERO
	if points.size() == 1 or frac <= 0.0:
		return points[0]
	var total = 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	var want = total * clampf(frac, 0.0, 1.0)
	for i in range(1, points.size()):
		var seg = points[i - 1].distance_to(points[i])
		if want <= seg and seg > 0.0:
			return points[i - 1].lerp(points[i], want / seg)
		want -= seg
	return points[points.size() - 1]


const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]


func _astar(layer: String, from: Vector2i, to: Vector2i) -> Array:
	var gr: Dictionary = _grid[layer]
	var w: int = gr["w"]
	var start = from.y * w + from.x
	var goal = to.y * w + to.x
	var cost = {start: 0.0}
	var back = {}
	var heap: Array = [[0.0, start]]
	var found = false
	while not heap.is_empty():
		var top: Array = g.mil._heap_pop(heap)
		var cur: int = top[1]
		if cur == goal:
			found = true
			break
		var cc = Vector2i(cur % w, cur / w)
		var base: float = cost[cur]
		for d in DIRS:
			var n: Vector2i = cc + d
			if not _water(layer, n):
				continue
			if d.x != 0 and d.y != 0 and (not _water(layer, cc + Vector2i(d.x, 0)) or not _water(layer, cc + Vector2i(0, d.y))):
				continue   # no cutting corners across land
			var ni = n.y * w + n.x
			var nc = base + (1.41421 if d.x != 0 and d.y != 0 else 1.0)
			if nc < float(cost.get(ni, INF)):
				cost[ni] = nc
				back[ni] = cur
				var hx = float(absi(n.x - to.x))
				var hy = float(absi(n.y - to.y))
				g.mil._heap_push(heap, [nc + maxf(hx, hy) + 0.41421 * minf(hx, hy), ni])
	if not found:
		return []
	var out: Array = []
	var c = goal
	while c != start:
		out.push_front(Vector2i(c % w, c / w))
		c = back[c]
	out.push_front(from)
	return out


func _clear_line(layer: String, a: Vector2, b: Vector2) -> bool:
	var img: Image = _grid[layer]["img"]
	var n = int(a.distance_to(b) / 5.0) + 1
	for i in range(n + 1):
		var p = a.lerp(b, float(i) / float(n))
		if not _is_water(img, p):
			return false
		# keep a little clearance from the shore
		for o in [Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3)]:
			if not _is_water(img, p + o):
				return false
	return true


func _smooth(layer: String, cells: Array) -> PackedVector2Array:
	var pts = PackedVector2Array()
	for c in cells:
		pts.append(_centre(c))
	if pts.size() <= 2:
		return pts
	var out = PackedVector2Array([pts[0]])
	var i = 0
	while i < pts.size() - 1:
		var j = i + 1
		while j + 1 < pts.size() and _clear_line(layer, pts[i], pts[j + 1]):
			j += 1
		out.append(pts[j])
		i = j
	return out
