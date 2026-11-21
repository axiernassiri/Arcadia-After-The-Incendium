extends Node2D
## Draws the two province layers (ground and sky), recolours them per map mode, handles picking
## (provinces, armies, fleets) and draws names, nation labels, armies, fleets, battles and sieges.

signal province_clicked(id: int)
signal province_right_clicked(id: int)
signal province_hovered(id: int)
signal army_clicked(id: int)
signal army_shift_clicked(id: int)   # shift-click: add to or remove from the selection
signal box_selected(ids: Array)       # shift-drag: armies inside the box
signal fleet_clicked(id: int)
signal layer_changed(layer: String)

const Tokens = preload("res://ui/style/tokens.gd")
const Icons = preload("res://ui/style/icons.gd")
const LAYERS := ["ground", "sky"]
const PALETTE_WIDTH := 1024
const MODES := ["political", "development", "goods", "trade", "region", "culture", "religion", "ethnicity", "autonomy",
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
var group: Array = []          # every selected army (selected_army is the first)
var _box_from := Vector2.INF   # screen position where a shift-drag selection box started
var _box_to := Vector2.ZERO
# where the selected army would march if you right-clicked the hovered province (EU4's path preview)
var _preview_pts: Array = []    # map-space points: the army's position, then each province on the way
var _preview_text := ""
var _preview_ok := true
var selected_fleet := -1
var map_size := Vector2(2000, 1092)
var camera_zoom := 1.0
var show_all := false        # nation picker: no fog
var selected_node := ""      # trade map mode: the node being inspected

var _sprites := {}          # layer -> Sprite2D
var _index_images := {}     # layer -> Image (for picking)
var _palette_img: Image
var _palette_tex: ImageTexture
var _overlay: CanvasLayer
var _labels: Node2D
var _units: Node2D
var _xf := Transform2D()
var _screen := Rect2()
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
		mat.set_shader_parameter("paper_tex", load("res://assets/ui/map_paper.png"))
		s.material = mat
		s.visible = (l == layer)
		add_child(s)
		_sprites[l] = s
	_overlay = CanvasLayer.new()
	_overlay.layer = 1
	add_child(_overlay)
	var vignette = TextureRect.new()
	vignette.texture = load("res://assets/ui/vignette.png")
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.modulate = Color(1, 1, 1, 0.55)
	vignette.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_overlay.add_child(vignette)
	_labels = Node2D.new()
	_labels.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_labels.draw.connect(_draw_labels)
	_overlay.add_child(_labels)
	_units = Node2D.new()
	_units.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_units.draw.connect(_draw_units)
	_overlay.add_child(_units)
	_build_colour_tables()
	_set_clear_colour()
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
	mat.set_shader_parameter("zoom", camera_zoom)
	# the overlay is drawn in screen pixels, so it must follow the camera
	var xf := get_viewport().get_canvas_transform() * get_global_transform()
	var scr := get_viewport().get_visible_rect()
	if xf != _xf or scr != _screen:
		_xf = xf
		_screen = scr
		_labels.queue_redraw()
		_units.queue_redraw()


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
			var nc: Color = _node_colours.get(p["trade_node"], Color.GRAY)
			if selected_node != "" and p["trade_node"] != selected_node:
				return nc.darkened(0.55).lerp(Color(0.3, 0.3, 0.3), 0.4)
			return nc
		"autonomy":
			if owner == "":
				return Game.unowned_colour.darkened(0.3)
			var aut := Game.eco.autonomy(id) / 100.0
			if Game.provinces[id].get("coring", {}).size() > 0 or not p["cores"].has(owner):
				aut = maxf(aut, 0.5)
			return Color(0.22, 0.42, 0.85).lerp(Color(0.92, 0.88, 0.55), minf(aut * 2.0, 1.0)).lerp(Color(0.85, 0.3, 0.2), maxf(aut * 2.0 - 1.0, 0.0))
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
	if m != "trade":
		selected_node = ""
	refresh()


func select_node(node: String) -> void:
	selected_node = node
	refresh()
	_labels.queue_redraw()


func _set_clear_colour() -> void:
	## Past the map's edge, keep showing the open sea (or open sky) instead of a black void.
	RenderingServer.set_default_clear_color(Color(0.118, 0.285, 0.505) if layer == "ground" else Color(0.56, 0.68, 0.88))


func set_layer(l: String) -> void:
	if l == layer:
		return
	layer = l
	for k in _sprites:
		_sprites[k].visible = (k == l)
	_set_clear_colour()
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
	group = [id] if id >= 0 else []
	selected_fleet = -1
	if id < 0:
		_preview_text = ""
	_units.queue_redraw()


func set_group(ids: Array) -> void:
	group = ids.duplicate()
	selected_army = int(ids[0]) if ids.size() > 0 else -1
	selected_fleet = -1
	_units.queue_redraw()


func select_fleet(id: int) -> void:
	selected_fleet = id
	selected_army = -1
	group = []
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
	var local := _xf * to_local(global_pos)   # hit boxes are in screen pixels
	for i in range(_hits.size() - 1, -1, -1):
		if (_hits[i]["rect"] as Rect2).has_point(local):
			return _hits[i]
	return {}


func _ui_has_mouse() -> bool:
	return get_viewport().gui_get_hovered_control() != null


func _mouse_screen() -> Vector2:
	return _xf * to_local(get_global_mouse_position())


func _box_input(event: InputEvent) -> bool:
	## Shift + left-drag draws a selection box; armies whose counters it touches get selected.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.shift_pressed and not _ui_has_mouse():
			_box_from = _mouse_screen()
			_box_to = _box_from
			return false   # a plain shift-click still reaches the click handler on release
		if not event.pressed and _box_from != Vector2.INF:
			var r := Rect2(_box_from, Vector2.ZERO).expand(_mouse_screen())
			_box_from = Vector2.INF
			_units.queue_redraw()
			if r.size.length() < 8.0:
				return false
			var ids: Array = []
			for h in _hits:
				if h["kind"] == "army" and r.intersects(h["rect"]) and not ids.has(h["id"]):
					ids.append(h["id"])
			box_selected.emit(ids)
			get_viewport().set_input_as_handled()
			return true
	elif event is InputEventMouseMotion and _box_from != Vector2.INF:
		_box_to = _mouse_screen()
		_units.queue_redraw()
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not Game.started and not show_all:
		return
	if _box_input(event):
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
					if event.shift_pressed:
						army_shift_clicked.emit(hit["id"])
					else:
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
# Everything below is drawn on a screen-space layer (_overlay), not on the map itself: positions are
# converted with the camera transform and rounded to whole pixels, and fonts are drawn at whole-pixel
# sizes. Drawing them in map space and shrinking the font by the zoom (the old way) rasterised tiny
# glyphs and then magnified them, which is why names and army boxes looked soft when zoomed in.

func _sp(p: Vector2) -> Vector2:
	return (_xf * p).round()


func _on_screen(p: Vector2, margin: float = 80.0) -> bool:
	return _screen.grow(margin).has_point(p)


func _text(ci: CanvasItem, font: Font, centre: Vector2, text: String, size: int, col: Color, outline: int = 3,
		outline_col: Color = Color(0.03, 0.03, 0.04, 0.85)) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := Vector2(round(centre.x - w / 2.0), round(centre.y + size * 0.35))
	if outline > 0:
		ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, outline_col)
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _icon(ci: CanvasItem, name: String, centre: Vector2, px: int, tint: Color, shadow: bool = true) -> void:
	var t: Texture2D = Icons.tex(name, px)
	var r := Rect2((centre - Vector2(px, px) / 2.0).round(), Vector2(px, px))
	if shadow:
		ci.draw_texture_rect(t, Rect2(r.position + Vector2(1, 1), r.size), false, Color(0, 0, 0, 0.7))
	ci.draw_texture_rect(t, r, false, tint)


func _draw_labels() -> void:
	var font: Font = Tokens.font("map_label")
	var nation_font: Font = Tokens.font("map_nation")
	var z := camera_zoom
	var show_names := z >= 1.6 or layer == "sky"
	if mode in ["political", "diplomacy"]:
		var markers := _marker_rects()
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
				var size := int(clampf(sqrt(weight) / 8.0 * z, 0.0, 76.0))
				if size < 13:
					continue
				var c := _sp(sum / weight)
				if not _on_screen(c, 400.0):
					continue
				c = _clear_spot(c, nation_font, Game.nations[tag]["short"].to_upper(), size, markers)
				var alpha := 0.62 if not show_names else 0.30
				_text(_labels, nation_font, c, Game.nations[tag]["short"].to_upper(), size, Color(1, 0.98, 0.92, alpha),
					maxi(2, size / 9), Color(0.05, 0.04, 0.03, alpha * 0.7))
	if Game.doomsday_active:
		var mc := _sp(Vector2(map_size.x - 160, 150))
		var r := 78.0 * z
		for i in 6:
			_labels.draw_circle(mc, r + (2.0 + i * 12.0) * z, Color(0.55, 0.2, 0.85, 0.10))
		_labels.draw_circle(mc, r, Color(0.02, 0.0, 0.04))
		_text(_labels, Tokens.font("title"), mc + Vector2(0, r + 26), "THE BLACK MOON", 18, Color(0.85, 0.6, 1.0))
	if mode == "trade":
		_draw_trade(z)
	if layer == "ground":
		_draw_straits()
	var name_size := 13 if z < 2.4 else (14 if z < 3.6 else 16)
	for id in Game.provinces:
		var p: Dictionary = Game.provinces[id]
		if p["layer"] != layer:
			continue
		var c := _sp(p["centre"])
		if not _on_screen(c):
			continue
		if not explored(id):
			_text(_labels, font, c, "?", 16, Color(1, 1, 1, 0.45), 2)
			continue
		var top := c + Vector2(0, -15)
		var ix := 0.0
		var marks: Array = []
		if "capital" in p["flags"] and p["owner"] != "" and Game.capital_of(p["owner"]) == id:
			marks.append(["star", Tokens.GOLD])
		if "doomsday_portal" in p["flags"]:
			marks.append(["portal", Color(0.8, 0.45, 1.0) if not Game.doomsday_active else Color(1, 0.3, 0.35)])
		if "waterfall_top" in p["flags"] or "waterfall_base" in p["flags"]:
			marks.append(["waterfall", Color(0.65, 0.88, 1.0)])
		if p["buildings"].has("fort"):
			marks.append(["fort", Color(0.86, 0.86, 0.9)])
		ix = -(marks.size() - 1) * 8.0
		for m in marks:
			_icon(_labels, m[0], top + Vector2(ix, 0), 15, m[1])
			ix += 16.0
		if show_names or id == selected:
			_text(_labels, font, c + Vector2(0, 5), p["name"], name_size, Color(1, 0.98, 0.94, 0.97), 3)
		if not p["siege"].is_empty():
			var bw := 36.0
			var bp := (c + Vector2(-bw / 2.0, 16)).round()
			var prog := clampf(float(p["siege"]["progress"]) / 100.0, 0.0, 1.0)
			_labels.draw_rect(Rect2(bp - Vector2(1, 1), Vector2(bw + 2, 7)), Color(0.02, 0.02, 0.03, 0.9))
			_labels.draw_rect(Rect2(bp, Vector2(round(bw * prog), 5)), Tokens.WARN)
			_icon(_labels, "fort", bp + Vector2(-9, 2), 13, Tokens.WARN)


func _marker_rects() -> Array:
	## Screen rects of the capital/fort icons and army counters above province centres, which a
	## nation's name should not be printed across.
	var out: Array = []
	var with_army := {}
	for aid in Game.armies:
		with_army[int(Game.armies[aid]["location"])] = true
	for id in Game.provinces:
		var p: Dictionary = Game.provinces[id]
		if p["layer"] != layer or not explored(id):
			continue
		var c := _sp(p["centre"])
		if id == selected:   # its name is drawn under the centre
			out.append(Rect2(c + Vector2(-50, -4), Vector2(100, 20)))
		if with_army.has(id):   # army counter (drawn 40px above the centre) plus the icons under it
			out.append(Rect2(c + Vector2(-36, -54), Vector2(72, 48)))
		elif p["buildings"].has("fort") or "capital" in p["flags"] or "doomsday_portal" in p["flags"]:
			out.append(Rect2(c + Vector2(-26, -24), Vector2(52, 18)))
	return out


func _clear_spot(c: Vector2, font: Font, text: String, size: int, markers: Array) -> Vector2:
	## Try the centre, then a little below and above it, and keep the first spot no marker overlaps.
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	for dy in [0.0, 0.7, -0.7, 1.2, -1.2]:
		var at: Vector2 = c + Vector2(0, round(dy * size))
		var r := Rect2(at.x - w / 2.0, at.y - size * 0.4, w, size * 0.8)
		var hit := false
		for m in markers:
			if r.intersects(m):
				hit = true
				break
		if not hit:
			return at
	return c


func _seat(node: String) -> Vector2:
	var seats: Dictionary = Game.map_meta.get("ground", {}).get("trade_seats", {})
	if not seats.has(node):
		return Vector2.INF
	return Vector2(float(seats[node][0]), float(seats[node][1]))


func _arrow(a: Vector2, b: Vector2, width: float, col: Color) -> void:
	## A curved flow arrow in screen space, EU4-style.
	var d := b - a
	if d.length() < 30.0:
		return
	var n := Vector2(-d.y, d.x).normalized() * d.length() * 0.06
	var pts := PackedVector2Array()
	for i in 21:
		var t := float(i) / 20.0
		var q := a.lerp(b, t) + n * 4.0 * t * (1.0 - t)
		pts.append(q)
	# stop short of the seat so the head doesn't hide the label
	pts = pts.slice(2, pts.size() - 2)
	_labels.draw_polyline(pts, Color(0, 0, 0, 0.55), width + 3.0, true)
	_labels.draw_polyline(pts, col, width, true)
	var tip := pts[pts.size() - 1]
	var dir := (tip - pts[pts.size() - 3]).normalized()
	var side := Vector2(-dir.y, dir.x)
	var hw := width * 1.4 + 4.0
	var head := PackedVector2Array([tip + dir * hw * 1.3, tip + side * hw, tip - side * hw])
	_labels.draw_colored_polygon(head, Color(0, 0, 0, 0.55))
	var head2 := PackedVector2Array([tip + dir * (hw * 1.3 - 2.0), tip + side * (hw - 2.0), tip - side * (hw - 2.0)])
	_labels.draw_colored_polygon(head2, col)


func _draw_trade(z: float) -> void:
	var tag: String = Game.player_tag
	var biggest := 0.1
	for k in Game.trade.state:
		biggest = maxf(biggest, float(Game.trade.state[k].get("outgoing", 0.0)))
	# flows
	for k in Game.trade.order:
		var from := _seat(k)
		var flow: float = float(Game.trade.state.get(k, {}).get("outgoing", 0.0))
		for dn in Game.trade.nodes[k].get("downstream", []):
			var to := _seat(dn)
			if from == Vector2.INF or to == Vector2.INF:
				continue
			var w := 2.0 + 7.0 * clampf(flow / biggest, 0.0, 1.0)
			var col := Color(1.0, 0.9, 0.55, 0.9) if selected_node in ["", k, dn] else Color(1.0, 0.9, 0.55, 0.3)
			if k == "Skyfall":
				# Skyfall's trade comes down the Holy Waterfall
				if layer == "sky":
					var top := _province_with_flag("waterfall_top")
					if top >= 0:
						_arrow(_sp(from), _sp(Game.provinces[top]["centre"]), w, col)
						_text(_labels, Tokens.font("medium"), _sp(Game.provinces[top]["centre"]) + Vector2(0, 26), "down to %s" % dn, 12, Tokens.GOLD_HI)
				else:
					var base := _province_with_flag("waterfall_base")
					if base >= 0:
						_arrow(_sp(Game.provinces[base]["centre"]), _sp(to), w, col)
				continue
			if layer == "ground":
				_arrow(_sp(from), _sp(to), w, col)
	# seats
	for k in Game.trade.nodes:
		var c0 := _seat(k)
		if c0 == Vector2.INF or (k == "Skyfall") != (layer == "sky"):
			continue
		var c := _sp(c0)
		var s: Dictionary = Game.trade.state.get(k, {})
		var share := Game.trade.share(tag, k) if tag != "" else 0.0
		var sel = k == selected_node
		_labels.draw_circle(c, 15.0, Color(0, 0, 0, 0.6))
		_labels.draw_circle(c, 13.0, Color(0.12, 0.1, 0.06))
		if share > 0.0:
			_labels.draw_arc(c, 13.0, -PI / 2.0, -PI / 2.0 + TAU * share, 32, Tokens.GOOD, 3.0, true)
		_labels.draw_arc(c, 15.0, 0, TAU, 32, Tokens.GOLD_HI if sel else Tokens.BORDER, 1.5, true)
		var mine: String = Game.nations[tag]["merchants"].get(k, "") if tag != "" else ""
		var icon := "coins" if (mine == "collect" or (tag != "" and k == Game.trade.home_node(tag))) else ("trade" if mine == "steer" else "star")
		_icon(_labels, icon, c, 16, Tokens.GOLD_HI if mine != "" or k == Game.trade.home_node(tag) else Tokens.GOLD, false)
		_text(_labels, Tokens.font("title"), c + Vector2(0, 28), k, 14, Tokens.GOLD_HI)
		_text(_labels, Tokens.font("bold"), c + Vector2(0, 44), "%.1f  ·  you %d%%" % [float(s.get("value", 0.0)), int(share * 100)], 12, Tokens.TEXT)


func _province_with_flag(flag: String) -> int:
	for id in Game.provinces:
		if flag in Game.provinces[id]["flags"]:
			return id
	return -1


func _draw_straits() -> void:
	for id in Game.provinces:
		var p: Dictionary = Game.provinces[id]
		for nb in p["connections"]:
			if p["connections"][nb] != "strait" or nb < id:
				continue
			var a := _sp(p["centre"])
			var b := _sp(Game.provinces[nb]["centre"])
			if not (_on_screen(a) or _on_screen(b)):
				continue
			var blocked: bool = Game.player_tag != "" and Game.mil.strait_blocked(Game.player_tag, id, nb)
			var col := Color(0.95, 0.35, 0.3, 0.9) if blocked else Color(1.0, 0.95, 0.8, 0.85)
			var seg := 7.0
			var total := a.distance_to(b)
			var dir := (b - a) / maxf(total, 1.0)
			var t := 14.0
			while t < total - 14.0:
				var e := minf(t + seg, total - 14.0)
				_labels.draw_line(a + dir * t, a + dir * e, Color(0, 0, 0, 0.6), 4.5, true)
				_labels.draw_line(a + dir * t, a + dir * e, col, 2.5, true)
				t += seg * 2.0


func _draw_star(c: Vector2, r: float, col: Color, target: CanvasItem = null) -> void:
	var ci: CanvasItem = target if target != null else _labels
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + i * PI / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	ci.draw_colored_polygon(pts, col)
	pts.append(pts[0])
	ci.draw_polyline(pts, Color(0, 0, 0, 0.6), 1.0, true)


func _unit_pos(loc: int, path: Array, progress: float, hop: float) -> Vector2:
	var a: Vector2 = Game.provinces[loc]["centre"]
	if path.is_empty() or hop <= 0.0:
		return a
	var b: Vector2 = Game.provinces[int(path[0])]["centre"]
	if Game.provinces[int(path[0])]["layer"] != Game.provinces[loc]["layer"]:
		return a
	return a.lerp(b, clampf(progress / hop, 0.0, 1.0))


func _counter(ci: CanvasItem, centre: Vector2, icon_name: String, text: String, col: Color, morale: float, sel: bool,
		hostile: bool) -> Rect2:
	## An EU4-style unit counter: dark icon cell, nation-coloured strength, morale bar underneath.
	var font: Font = Tokens.font("map_label")
	var fs := 13
	var tw := ceilf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var h := 20.0
	var icon_w := 20.0
	var w := icon_w + tw + 12.0
	var r := Rect2((centre - Vector2(w, h) / 2.0).round(), Vector2(w, h))
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0, 0, 0, 0)
	shadow.shadow_color = Color(Tokens.GOLD_HI, 0.55) if sel else Color(0, 0, 0, 0.55)
	shadow.shadow_size = 6 if sel else 3
	shadow.shadow_offset = Vector2(0, 0) if sel else Vector2(1, 2)
	shadow.set_corner_radius_all(4)
	ci.draw_style_box(shadow, r)
	var body := StyleBoxFlat.new()
	body.bg_color = col
	body.set_corner_radius_all(4)
	body.border_color = Tokens.GOLD_HI if sel else (Color(1.0, 0.35, 0.3) if hostile else Tokens.INK)
	body.set_border_width_all(2 if sel or hostile else 1)
	ci.draw_style_box(body, r)
	var cell := StyleBoxFlat.new()
	cell.bg_color = Color(0.07, 0.075, 0.09)
	cell.corner_radius_top_left = 3
	cell.corner_radius_bottom_left = 3
	var inset := 2.0 if sel or hostile else 1.0
	ci.draw_style_box(cell, Rect2(r.position + Vector2(inset, inset), Vector2(icon_w - inset, h - inset * 2)))
	_icon(ci, icon_name, r.position + Vector2(icon_w / 2.0 + 0.5, h / 2.0), 14, Tokens.TEXT, false)
	# a light sheen on the coloured part so flat nation colours read as a token, not a sticker
	ci.draw_rect(Rect2(r.position + Vector2(icon_w, inset), Vector2(w - icon_w - inset, 1)), Color(1, 1, 1, 0.22))
	var tc := Color.WHITE if col.get_luminance() < 0.62 else Color(0.06, 0.06, 0.07)
	var oc := Color(0, 0, 0, 0.55) if tc == Color.WHITE else Color(1, 1, 1, 0.35)
	var tp := Vector2(r.position.x + icon_w + 6.0, r.position.y + 15.0)
	ci.draw_string_outline(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 2, oc)
	ci.draw_string(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tc)
	if morale >= 0.0:
		var mb := Rect2(Vector2(r.position.x + 2, r.end.y + 1), Vector2(w - 4, 4))
		ci.draw_rect(mb, Color(0.02, 0.02, 0.03, 0.9))
		var mc := Color(0.45, 0.9, 0.4) if morale > 0.5 else (Tokens.WARN if morale > 0.25 else Tokens.BAD)
		ci.draw_rect(Rect2(mb.position + Vector2(1, 1), Vector2(round((mb.size.x - 2) * morale), 2)), mc)
	return r


func _path_line(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	if pts.size() < 2:
		return
	ci.draw_polyline(pts, Color(0, 0, 0, 0.6), 5.0, true)
	ci.draw_polyline(pts, col, 2.5, true)
	var end := pts[pts.size() - 1]
	ci.draw_circle(end, 6.0, Color(0, 0, 0, 0.6))
	ci.draw_circle(end, 4.5, col)


func _draw_units() -> void:
	_hits.clear()
	var stack := {}
	# battles
	for b in Game.battles:
		var pid: int = int(b["pid"])
		if Game.provinces[pid]["layer"] != layer or not explored(pid):
			continue
		var c := _sp(Game.provinces[pid]["centre"]) + Vector2(0, -66)
		_units.draw_circle(c, 14.0, Color(0, 0, 0, 0.55))
		_units.draw_circle(c, 12.0, Color(0.35, 0.05, 0.03))
		_units.draw_arc(c, 12.0, 0, TAU, 32, Color(1, 0.45, 0.3), 1.5, true)
		_icon(_units, "battle", c, 18, Color(1, 0.85, 0.7), false)
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
		var sbase := _sp(base)
		var pos := sbase + Vector2(0, -40 - n * 27)
		if not _on_screen(pos):
			continue
		var owner: String = a["owner"]
		var col: Color = Game.owner_colour(owner)
		var men := 0.0
		var cav := 0
		for r in a["regiments"]:
			men += float(r["men"])
			if Game.mil.unit_category(String(r["type"])) == "cav":
				cav += 1
		var icon_name := "flame" if owner == "REB" else ("portal" if owner == "ENT" else ("horseshoe" if cav * 2 > a["regiments"].size() else "helmet"))
		var sel: bool = int(id) == selected_army or group.has(int(id))
		if sel and not a["path"].is_empty():
			var pts := PackedVector2Array([sbase])
			for step in a["path"]:
				if Game.provinces[int(step)]["layer"] == layer:
					pts.append(_sp(Game.provinces[int(step)]["centre"]))
			_path_line(_units, pts, Color(1, 0.97, 0.88))
		var hostile := owner in ["REB", "ENT"] or (Game.player_tag != "" and Game.dip.at_war(Game.player_tag, owner))
		var rect := _counter(_units, pos, icon_name, "%.1fk" % (men / 1000.0), col, _army_morale(a), sel, hostile)
		_hits.append({"rect": rect.grow(3), "kind": "army", "id": int(id)})
	# fleets
	for id in Game.fleets:
		var f: Dictionary = Game.fleets[id]
		var loc: int = int(f["location"])
		if Game.provinces[loc]["layer"] != layer:
			continue
		if not explored(loc) and f["owner"] != Game.player_tag:
			continue
		# fleets sit on the water at their port and sail along sea lanes
		var route_pts := PackedVector2Array()
		var base: Vector2 = Game.sea.port_point(loc)
		if not f["path"].is_empty():
			var r: Dictionary = Game.sea.route(int(f.get("from", loc)), int(f["path"][0]))
			if not r.is_empty():
				route_pts = r["points"]
				base = Game.sea.point_along(route_pts, float(f["progress"]) / maxf(float(f["hop_days"]), 1.0))
		var sbase := _sp(base)
		var skey := "sea%d" % loc if f["path"].is_empty() else "f%d" % int(id)
		var n: int = int(stack.get(skey, 0))
		stack[skey] = n + 1
		var pos := sbase + Vector2(0, -14 - n * 27)
		if not _on_screen(pos):
			continue
		var sel: bool = int(id) == selected_fleet
		if sel and route_pts.size() > 1:
			var pts := PackedVector2Array()
			var frac := float(f["progress"]) / maxf(float(f["hop_days"]), 1.0)
			pts.append(sbase)
			# the rest of the route from where the fleet is now
			var total := 0.0
			for i in range(1, route_pts.size()):
				total += route_pts[i - 1].distance_to(route_pts[i])
			var run := 0.0
			for i in range(1, route_pts.size()):
				run += route_pts[i - 1].distance_to(route_pts[i])
				if run / maxf(total, 1.0) > frac:
					pts.append(_sp(route_pts[i]))
			_path_line(_units, pts, Color(0.65, 0.88, 1.0))
		var hostile := Game.player_tag != "" and Game.dip.at_war(Game.player_tag, f["owner"])
		var rect := _counter(_units, pos, "ship", str(f["ships"].size()), Game.nations[f["owner"]]["colour"], -1.0, sel, hostile)
		_hits.append({"rect": rect.grow(3), "kind": "fleet", "id": int(id)})
	# the march preview: a faint path and how long it takes
	if _preview_text != "":
		var col := Color(1, 0.97, 0.88, 0.8) if _preview_ok else Color(1, 0.4, 0.35, 0.8)
		var end := Vector2.ZERO
		if _preview_pts.size() >= 2:
			var pts := PackedVector2Array()
			for p in _preview_pts:
				pts.append(_sp(p))
			_units.draw_polyline(pts, Color(0, 0, 0, 0.35), 4.0, true)
			_units.draw_polyline(pts, col, 2.0, true)
			end = pts[pts.size() - 1]
		elif _preview_pts.size() == 1:
			end = _sp(_preview_pts[0])
		if _preview_pts.size() > 0:
			_text(_units, Tokens.font("bold"), end + Vector2(0, 24), _preview_text, 14, Tokens.GOLD_HI if _preview_ok else Color(1, 0.55, 0.5), 4, Color(0.02, 0.02, 0.03, 0.95))
	# the shift-drag selection box
	if _box_from != Vector2.INF:
		var br := Rect2(_box_from, Vector2.ZERO).expand(_box_to)
		_units.draw_rect(br, Color(Tokens.GOLD_HI, 0.10))
		_units.draw_rect(br, Color(Tokens.GOLD_HI, 0.85), false, 1.5)


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


func set_preview(points: Array, text: String, ok: bool) -> void:
	## Show (or, with no text, hide) the march preview for the selected army.
	if text == _preview_text and points.size() == _preview_pts.size() and ok == _preview_ok:
		return
	_preview_pts = points
	_preview_text = text
	_preview_ok = ok
	_units.queue_redraw()
