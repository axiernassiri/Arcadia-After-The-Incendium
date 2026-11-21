extends Node2D
## Draws the two province layers (ground and sky), recolours them per map mode, handles picking
## (provinces, armies, fleets) and draws names, nation labels, armies, fleets, battles and sieges.

signal province_clicked(id: int)
signal province_right_clicked(id: int)
signal province_hovered(id: int)
signal army_clicked(id: int)
signal fleet_clicked(id: int)
signal layer_changed(layer: String)

const LAYERS := ["ground", "sky"]
const PALETTE_WIDTH := 1024
const MODES := ["political", "development", "goods", "trade", "region", "culture", "religion", "ethnicity",
	"unrest", "diplomacy", "terrain"]
const TERRAIN_COLOURS := {
	"grassland": Color(0.62, 0.72, 0.45), "farmland": Color(0.85, 0.78, 0.40), "forest": Color(0.30, 0.52, 0.30),
	"hills": Color(0.62, 0.55, 0.40), "mountains": Color(0.50, 0.47, 0.46), "tundra": Color(0.88, 0.92, 0.95),
	"drylands": Color(0.80, 0.62, 0.40), "jungle": Color(0.20, 0.45, 0.25), "coast": Color(0.75, 0.75, 0.55),
	"volcanic": Color(0.40, 0.28, 0.26), "anomalous": Color(0.62, 0.45, 0.75), "fortress": Color(0.55, 0.55, 0.58),
	"skyland": Color(0.92, 0.90, 0.80), "wasteland": Color(0.55, 0.50, 0.45),
}
const NODE_COLOURS := [Color("#e0a050"), Color("#50a0e0"), Color("#a060d0"), Color("#60c080"), Color("#d06070"),
	Color("#c0c050"), Color("#70d0d0"), Color("#e080c0")]

var layer := "ground"
var mode := "political"
var selected := -1
var hovered := -1
var selected_army := -1
var selected_fleet := -1
var map_size := Vector2(2000, 1092)
var camera_zoom := 1.0
var show_all := false        # nation picker: no fog

var _sprites := {}          # layer -> Sprite2D
var _index_images := {}     # layer -> Image (for picking)
var _palette_img: Image
var _palette_tex: ImageTexture
var _labels: Node2D
var _units: Node2D
var _region_colours := {}
var _node_colours := {}
var _hits: Array = []       # [{rect: Rect2, kind, id}] in map coords
var _owner_keys := {}


func _ready() -> void:
	_palette_img = Image.create(PALETTE_WIDTH, 3, false, Image.FORMAT_RGBA8)
	_palette_tex = ImageTexture.create_from_image(_palette_img)
	var shader: Shader = load("res://shaders/map.gdshader")
	for l in LAYERS:
		var index_tex: Texture2D = load("res://map/%s_index.png" % l)
		var terrain_tex: Texture2D = load("res://map/%s_terrain.png" % l)
		_index_images[l] = index_tex.get_image()
		if _index_images[l].is_compressed():
			_index_images[l].decompress()
		map_size = Vector2(_index_images[l].get_width(), _index_images[l].get_height())
		var s := Sprite2D.new()
		s.centered = false
		s.texture = terrain_tex
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("index_tex", index_tex)
		mat.set_shader_parameter("terrain_tex", terrain_tex)
		mat.set_shader_parameter("palette_tex", _palette_tex)
		mat.set_shader_parameter("map_size", map_size)
		s.material = mat
		s.visible = (l == layer)
		add_child(s)
		_sprites[l] = s
	_labels = Node2D.new()
	_labels.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_labels.draw.connect(_draw_labels)
	add_child(_labels)
	_units = Node2D.new()
	_units.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_units.draw.connect(_draw_units)
	add_child(_units)
	_build_colour_tables()
	Game.province_changed.connect(func(_id): _queue_refresh())
	Game.game_started.connect(func(): _build_colour_tables(); refresh())
	Game.doomsday_changed.connect(_on_doomsday)
	Game.armies_changed.connect(func(): _units.queue_redraw())
	Game.date_changed.connect(func(): _units.queue_redraw())
	Game.war_changed.connect(_queue_refresh)
	Game.month_ticked.connect(_queue_refresh)
	refresh()


func _build_colour_tables() -> void:
	_region_colours.clear()
	var i := 0
	for id in Game.provinces:
		var r: String = Game.provinces[id]["region"]
		if not _region_colours.has(r):
			_region_colours[r] = Color.from_hsv(fmod(0.13 + i * 0.381966, 1.0), 0.45, 0.85)
			i += 1
	_node_colours.clear()
	var j := 0
	for k in Game.trade.order:
		_node_colours[k] = NODE_COLOURS[j % NODE_COLOURS.size()]
		j += 1
	_owner_keys.clear()
	var k := 1
	for tag in Game.nations:
		_owner_keys[tag] = float(k) / 255.0
		k += 1


var _refresh_queued := false


func _queue_refresh() -> void:
	if not _refresh_queued:
		_refresh_queued = true
		call_deferred("_do_refresh")


func _do_refresh() -> void:
	_refresh_queued = false
	refresh()


func _process(_delta: float) -> void:
	var mat: ShaderMaterial = _sprites[layer].material
	mat.set_shader_parameter("border_width", clampf(1.0 / camera_zoom, 0.35, 1.5))


# ---------------------------------------------------------------- colours

func explored(id: int) -> bool:
	return show_all or Game.is_explored_by_player(id)


func province_colour(id: int) -> Color:
	var p: Dictionary = Game.provinces[id]
	if not explored(id):
		return Game.fog_colour
	var owner: String = p["owner"]
	match mode:
		"development":
			if owner == "":
				return Game.unowned_colour.darkened(0.25)
			var t := clampf((Game.total_dev(id) - 3.0) / 22.0, 0.0, 1.0)
			return Color(0.75, 0.2, 0.2).lerp(Color(0.95, 0.85, 0.3), minf(t * 2.0, 1.0)).lerp(
				Color(0.25, 0.75, 0.35), maxf(t * 2.0 - 1.0, 0.0))
		"goods":
			return Color(Game.goods.get(p["goods"], {}).get("colour", "#777777"))
		"trade":
			return _node_colours.get(p["trade_node"], Color.GRAY)
		"region":
			return _region_colours.get(p["region"], Color.GRAY)
		"culture":
			if p["culture"] == "":
				return Game.unowned_colour.darkened(0.3)
			return Color(Game.peoples["cultures"].get(p["culture"], {}).get("colour", "#888888"))
		"religion":
			if p["religion"] == "":
				return Game.unowned_colour.darkened(0.3)
			return Color(Game.peoples["religions"].get(p["religion"], {}).get("colour", "#888888"))
		"ethnicity":
			if p["ethnicity"] == "":
				return Game.unowned_colour.darkened(0.3)
			return Color(Game.peoples["ethnicities"].get(p["ethnicity"], {}).get("colour", "#888888"))
		"unrest":
			if owner == "":
				return Game.unowned_colour.darkened(0.3)
			var u := float(p.get("unrest", 0.0))
			if float(p["rebel_progress"]) > 0.0 and u > 0.0:
				return Color(0.9, 0.25, 0.2).lerp(Color(0.6, 0.0, 0.0), clampf(float(p["rebel_progress"]) / 100.0, 0.0, 1.0))
			return Color(0.3, 0.7, 0.35).lerp(Color(0.95, 0.85, 0.3), clampf((u + 3.0) / 6.0, 0.0, 1.0))
		"diplomacy":
			return _diplo_colour(owner)
		"terrain":
			return TERRAIN_COLOURS.get(p["terrain"], Color.GRAY)
	if owner == "":
		return Game.unowned_colour
	return Game.nations[owner]["colour"]


func _diplo_colour(owner: String) -> Color:
	var me := Game.player_tag
	if owner == "":
		return Game.unowned_colour.darkened(0.2)
	if owner == me:
		return Color(0.25, 0.55, 0.95)
	if me == "" or not Game.nations.has(me):
		return Game.nations[owner]["colour"]
	if Game.dip.at_war(me, owner):
		return Color(0.85, 0.15, 0.15)
	if Game.nations[owner]["overlord"] == me:
		return Color(0.45, 0.75, 0.95)
	if Game.dip.rel(me, owner)["alliance"]:
		return Color(0.3, 0.8, 0.35)
	if Game.dip.rel(me, owner)["rival"]:
		return Color(0.9, 0.5, 0.2)
	var op := Game.dip.opinion(owner, me)
	return Color(0.55, 0.55, 0.5).lerp(Color(0.6, 0.8, 0.5) if op > 0 else Color(0.75, 0.45, 0.4), clampf(absf(op) / 100.0, 0.0, 1.0))


func refresh() -> void:
	for id in Game.provinces:
		if id >= PALETTE_WIDTH:
			push_error("Province id %d exceeds palette width" % id)
			continue
		var p: Dictionary = Game.provinces[id]
		var c := province_colour(id)
		var fogged := not explored(id)
		c.a = 0.92 if fogged else 0.78
		_palette_img.set_pixel(id, 0, c)
		var key := 0.98 if fogged else float(_owner_keys.get(p["owner"], 0.0))
		_palette_img.set_pixel(id, 1, Color(key, 0, 0, 1))
		var stripe := Color(0, 0, 0, 0)
		if not fogged and mode in ["political", "diplomacy"]:
			if p["owner"] != "" and p["controller"] != p["owner"]:
				stripe = Color(0.1, 0.1, 0.1, 0.85) if p["controller"] == "REB" else (Color(0.55, 0.2, 0.9, 0.9) if p["controller"] == "ENT" else Game.nations.get(p["controller"], {}).get("colour", Color.BLACK))
				stripe.a = 0.85
			elif not p["colony"].is_empty() and Game.nations.has(p["colony"]["tag"]):
				stripe = Game.nations[p["colony"]["tag"]]["colour"]
				stripe.a = clampf(float(p["colony"]["settlers"]) / 1000.0, 0.3, 0.9)
		_palette_img.set_pixel(id, 2, stripe)
	_palette_tex.update(_palette_img)
	_labels.queue_redraw()
	_units.queue_redraw()


func set_mode(m: String) -> void:
	mode = m
	refresh()


func set_layer(l: String) -> void:
	if l == layer:
		return
	layer = l
	for k in _sprites:
		_sprites[k].visible = (k == l)
	if selected >= 0 and Game.provinces.has(selected) and Game.provinces[selected]["layer"] != l:
		select(-1)
	_labels.queue_redraw()
	_units.queue_redraw()
	layer_changed.emit(l)


func select(id: int) -> void:
	selected = id
	for k in _sprites:
		_sprites[k].material.set_shader_parameter("selected_id", id)
	_labels.queue_redraw()


func select_army(id: int) -> void:
	selected_army = id
	selected_fleet = -1
	_units.queue_redraw()


func select_fleet(id: int) -> void:
	selected_fleet = id
	selected_army = -1
	_units.queue_redraw()


func _on_doomsday(active: bool) -> void:
	for k in _sprites:
		_sprites[k].material.set_shader_parameter("doomsday", 1.0 if active else 0.0)
	_labels.queue_redraw()


# ---------------------------------------------------------------- picking

func province_at(global_pos: Vector2) -> int:
	var local := to_local(global_pos)
	var img: Image = _index_images[layer]
	var x := int(local.x)
	var y := int(local.y)
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return 0
	var c := img.get_pixel(x, y)
	return int(round(c.r * 255.0)) + int(round(c.g * 255.0)) * 256


func _unit_at(global_pos: Vector2) -> Dictionary:
	var local := to_local(global_pos)
	for i in range(_hits.size() - 1, -1, -1):
		if (_hits[i]["rect"] as Rect2).has_point(local):
			return _hits[i]
	return {}


func _ui_has_mouse() -> bool:
	return get_viewport().gui_get_hovered_control() != null


func _unhandled_input(event: InputEvent) -> void:
	if not Game.started and not show_all:
		return
	if event is InputEventMouseMotion:
		if _ui_has_mouse():
			if hovered != 0:
				hovered = 0
				_sprites[layer].material.set_shader_parameter("hovered_id", 0)
				province_hovered.emit(0)
			return
		var id := province_at(get_global_mouse_position())
		if id != hovered:
			hovered = id
			_sprites[layer].material.set_shader_parameter("hovered_id", id)
			province_hovered.emit(id)
	elif event is InputEventMouseButton and not event.pressed:
		if event.has_meta("dragged") or _ui_has_mouse():
			return
		var pos := get_global_mouse_position()
		if event.button_index == MOUSE_BUTTON_LEFT:
			var hit := _unit_at(pos)
			if not hit.is_empty():
				if hit["kind"] == "army":
					army_clicked.emit(hit["id"])
				else:
					fleet_clicked.emit(hit["id"])
				get_viewport().set_input_as_handled()
				return
			var id := province_at(pos)
			select(id if id > 0 else -1)
			province_clicked.emit(id)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			var rid := province_at(pos)
			if rid > 0:
				province_right_clicked.emit(rid)


# ---------------------------------------------------------------- labels and markers

func _draw_labels() -> void:
	var font: Font = ThemeDB.fallback_font
	var s := 1.0 / camera_zoom   # keeps text a constant size on screen
	if mode in ["political", "diplomacy"]:
		for tag in Game.nations:
			if not Game.nations[tag]["alive"]:
				continue
			var sum := Vector2.ZERO
			var weight := 0.0
			for id in Game.owned(tag):
				var p: Dictionary = Game.provinces[id]
				if p["layer"] == layer and explored(id):
					sum += p["centre"] * p["area"]
					weight += p["area"]
			if weight > 9000:
				var text: String = Game.nations[tag]["short"].to_upper()
				var size := int(clampf(sqrt(weight) / 8.0, 16, 84))
				var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
				var pos: Vector2 = sum / weight + Vector2(-w / 2.0, size * 0.35)
				_labels.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0, 0, 0, 0.35))
				_labels.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, 0.55))
	var show_names := camera_zoom >= 1.6 or layer == "sky"
	if Game.doomsday_active:
		var mc := Vector2(map_size.x - 160, 150)
		for i in 6:
			_labels.draw_circle(mc, 80.0 + i * 12.0, Color(0.55, 0.2, 0.85, 0.10))
		_labels.draw_circle(mc, 78.0, Color(0.02, 0.0, 0.04))
		_draw_text(font, mc + Vector2(0, 120), "THE BLACK MOON", int(maxf(14.0, 18 * s)), Color(0.85, 0.6, 1.0))
	if mode == "trade":
		var seats: Dictionary = Game.map_meta.get("ground", {}).get("trade_seats", {})
		for k in seats:
			if (k == "Skyfall") != (layer == "sky"):
				continue
			var c := Vector2(float(seats[k][0]), float(seats[k][1]))
			_draw_star(c, 12.0 * s, Color(1, 0.9, 0.3))
			_draw_text(font, c + Vector2(0, 22 * s), k, int(maxf(9.0, 13 * s)), Color(1, 0.95, 0.7))
	for id in Game.provinces:
		var p: Dictionary = Game.provinces[id]
		if p["layer"] != layer:
			continue
		var c: Vector2 = p["centre"]
		if not explored(id):
			_draw_text(font, c, "?", int(16 * s), Color(1, 1, 1, 0.5))
			continue
		var marker_r := 5.0 * s
		if "capital" in p["flags"] and p["owner"] != "" and Game.capital_of(p["owner"]) == id:
			_draw_star(c + Vector2(0, -10 * s), marker_r * 1.4, Color(1, 0.9, 0.4))
		if "doomsday_portal" in p["flags"]:
			var col := Color(0.75, 0.3, 1.0) if not Game.doomsday_active else Color(1, 0.2, 0.3)
			_labels.draw_circle(c + Vector2(0, -12 * s), marker_r * 1.6, col)
			_labels.draw_circle(c + Vector2(0, -12 * s), marker_r * 0.8, Color(0.05, 0.0, 0.1))
		if "waterfall_top" in p["flags"] or "waterfall_base" in p["flags"]:
			var w0 := c + Vector2(-4 * s, -18 * s)
			_labels.draw_line(w0, w0 + Vector2(0, 12 * s), Color(0.6, 0.85, 1.0), 2.5 * s)
			_labels.draw_line(w0 + Vector2(4 * s, 0), w0 + Vector2(4 * s, 12 * s), Color(0.6, 0.85, 1.0), 2.5 * s)
		if p["buildings"].has("fort"):
			var fr := Rect2(c + Vector2(8 * s, -16 * s), Vector2(8 * s, 8 * s))
			_labels.draw_rect(fr, Color(0.75, 0.75, 0.8))
			_labels.draw_rect(fr, Color(0, 0, 0, 0.8), false, 1.0 * s)
		if show_names or id == selected:
			_draw_text(font, c + Vector2(0, 6 * s), p["name"], int(maxf(7.0, 11.0 * s)), Color(1, 1, 1, 0.95))
		if not p["siege"].is_empty():
			var bw := 30.0 * s
			var bp := c + Vector2(-bw / 2.0, 14 * s)
			_labels.draw_rect(Rect2(bp, Vector2(bw, 4 * s)), Color(0, 0, 0, 0.8))
			_labels.draw_rect(Rect2(bp, Vector2(bw * clampf(float(p["siege"]["progress"]) / 100.0, 0.0, 1.0), 4 * s)), Color(1, 0.8, 0.2))


func _draw_text(font: Font, centre: Vector2, text: String, size: int, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := centre + Vector2(-w / 2.0, size * 0.35)
	_labels.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(2, size / 4), Color(0, 0, 0, 0.75))
	_labels.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _draw_star(c: Vector2, r: float, col: Color, target: CanvasItem = null) -> void:
	var ci: CanvasItem = target if target != null else _labels
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + i * PI / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	ci.draw_colored_polygon(pts, col)
	pts.append(pts[0])
	ci.draw_polyline(pts, Color(0, 0, 0, 0.6), 1.0)


func _unit_pos(loc: int, path: Array, progress: float, hop: float) -> Vector2:
	var a: Vector2 = Game.provinces[loc]["centre"]
	if path.is_empty() or hop <= 0.0:
		return a
	var b: Vector2 = Game.provinces[int(path[0])]["centre"]
	if Game.provinces[int(path[0])]["layer"] != Game.provinces[loc]["layer"]:
		return a
	return a.lerp(b, clampf(progress / hop, 0.0, 1.0))


func _draw_units() -> void:
	_hits.clear()
	var font: Font = ThemeDB.fallback_font
	var s := clampf(1.0 / camera_zoom, 0.35, 2.0)
	var stack := {}
	# battles
	for b in Game.battles:
		var pid: int = int(b["pid"])
		if Game.provinces[pid]["layer"] != layer or not explored(pid):
			continue
		var c: Vector2 = Game.provinces[pid]["centre"] + Vector2(0, -30 * s)
		_units.draw_circle(c, 11 * s, Color(0.1, 0.0, 0.0, 0.85))
		_units.draw_line(c + Vector2(-7, -7) * s, c + Vector2(7, 7) * s, Color(1, 0.3, 0.2), 3 * s)
		_units.draw_line(c + Vector2(7, -7) * s, c + Vector2(-7, 7) * s, Color(1, 0.3, 0.2), 3 * s)
	# armies
	for id in Game.armies:
		var a: Dictionary = Game.armies[id]
		var loc: int = int(a["location"])
		if Game.provinces[loc]["layer"] != layer:
			continue
		if not explored(loc) and a["owner"] != Game.player_tag:
			continue
		var base := _unit_pos(loc, a["path"], float(a["progress"]), float(a["hop_days"]))
		var n: int = int(stack.get(loc, 0))
		stack[loc] = n + 1
		var pos := base + Vector2(0, -22 * s - n * 20 * s)
		var col: Color = Color(0.15, 0.15, 0.15) if a["owner"] == "REB" else (Color(0.45, 0.1, 0.75) if a["owner"] == "ENT" else Game.nations[a["owner"]]["colour"])
		var men := 0.0
		for r in a["regiments"]:
			men += float(r["men"])
		var text := "%.1fk" % (men / 1000.0)
		var fs := int(maxf(7.0, 11.0 * s))
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var rect := Rect2(pos - Vector2(tw / 2.0 + 6 * s, 8 * s), Vector2(tw + 12 * s, 16 * s))
		var sel: bool = int(id) == selected_army
		if sel and not a["path"].is_empty():
			var pts := PackedVector2Array([base])
			for step in a["path"]:
				if Game.provinces[int(step)]["layer"] == layer:
					pts.append(Game.provinces[int(step)]["centre"])
			if pts.size() > 1:
				_units.draw_polyline(pts, Color(1, 1, 1, 0.85), 2.5 * s)
				_units.draw_circle(pts[pts.size() - 1], 5 * s, Color(1, 1, 1, 0.9))
		_units.draw_rect(rect.grow(2 * s), Color(1, 1, 0.6) if sel else Color(0, 0, 0, 0.85))
		_units.draw_rect(rect, col.darkened(0.15))
		var morale := _army_morale(a)
		_units.draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - 3 * s), Vector2(rect.size.x * morale, 3 * s)), Color(0.4, 1.0, 0.4))
		var tc := Color.WHITE if col.get_luminance() < 0.6 else Color.BLACK
		_units.draw_string(font, Vector2(rect.position.x + 6 * s, rect.position.y + 12 * s), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tc)
		if a["owner"] == "REB":
			_units.draw_rect(rect, Color(1, 0.2, 0.2), false, 1.5 * s)
		_hits.append({"rect": rect.grow(3 * s), "kind": "army", "id": int(id)})
	# fleets
	for id in Game.fleets:
		var f: Dictionary = Game.fleets[id]
		var loc: int = int(f["location"])
		if Game.provinces[loc]["layer"] != layer:
			continue
		if not explored(loc) and f["owner"] != Game.player_tag:
			continue
		var base := _unit_pos(loc, f["path"], float(f["progress"]), float(f["hop_days"]))
		var pos := base + Vector2(24 * s, 14 * s)
		var col: Color = Game.nations[f["owner"]]["colour"]
		var sel: bool = int(id) == selected_fleet
		var hull := PackedVector2Array([pos + Vector2(-12, -2) * s, pos + Vector2(12, -2) * s, pos + Vector2(8, 6) * s, pos + Vector2(-8, 6) * s])
		var sail := PackedVector2Array([pos + Vector2(-1, -14) * s, pos + Vector2(-1, -3) * s, pos + Vector2(8, -3) * s])
		if sel and not f["path"].is_empty():
			var pts := PackedVector2Array([base])
			for step in f["path"]:
				pts.append(Game.provinces[int(step)]["centre"])
			_units.draw_polyline(pts, Color(0.6, 0.85, 1.0, 0.9), 2.5 * s)
		_units.draw_colored_polygon(hull, col.darkened(0.2))
		_units.draw_colored_polygon(sail, Color(0.95, 0.95, 0.9))
		hull.append(hull[0])
		_units.draw_polyline(hull, Color(1, 1, 0.6) if sel else Color(0, 0, 0, 0.9), 1.5 * s)
		var fs := int(maxf(7.0, 10.0 * s))
		_units.draw_string_outline(font, pos + Vector2(13, 4) * s, str(f["ships"].size()), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color.BLACK)
		_units.draw_string(font, pos + Vector2(13, 4) * s, str(f["ships"].size()), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		_hits.append({"rect": Rect2(pos - Vector2(13, 15) * s, Vector2(34, 22) * s), "kind": "fleet", "id": int(id)})


func _army_morale(a: Dictionary) -> float:
	var mm := Game.mil.max_morale(a["owner"])
	var t := 0.0
	var c := 0.0
	for r in a["regiments"]:
		t += float(r["morale"])
		c += 1.0
	return clampf(t / maxf(c, 1.0) / maxf(mm, 0.01), 0.0, 1.0)


func set_camera_zoom(z: float) -> void:
	if absf(z - camera_zoom) > 0.001:
		camera_zoom = z
		_labels.queue_redraw()
		_units.queue_redraw()
