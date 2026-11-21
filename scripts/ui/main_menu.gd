extends Control
## Title screen: new game, continue, load, quit.

signal new_game_pressed
signal load_pressed(slot: String)
signal settings_pressed

const UI = preload("res://scripts/ui/ui_util.gd")
const Tokens = preload("res://ui/style/tokens.gd")

var _box: VBoxContainer
var _saves_box: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg = ColorRect.new()
	bg.color = Color(0.035, 0.035, 0.05)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var map = TextureRect.new()
	map.texture = load("res://map/ground_terrain.png")
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map.modulate = Color(0.85, 0.75, 0.6, 0.28)
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(map)
	var vig = TextureRect.new()
	vig.texture = load("res://assets/ui/vignette.png")
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vig)
	var centre = CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	centre.add_child(col)
	var emblem = TextureRect.new()
	emblem.texture = load("res://assets/ui/emblem.png")
	emblem.custom_minimum_size = Vector2(150, 150)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(emblem)
	_emblem = emblem
	var title = UI.heading("ARCADIA", 72)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	var tf = FontVariation.new()
	tf.base_font = Tokens.font("title")
	tf.spacing_glyph = 10
	title.add_theme_font_override("font", tf)
	col.add_child(title)
	var sub = UI.heading("THE FIRST WORLD, AFTER THE INCENDIUM", 15)
	sub.add_theme_color_override("font_color", Tokens.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	var gap = Control.new()
	gap.custom_minimum_size.y = 8
	col.add_child(gap)
	col.add_child(UI.divider())
	var gap2 = Control.new()
	gap2.custom_minimum_size.y = 18
	col.add_child(gap2)
	var frame = PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UI.tex_box("panel.png", 12, 22, 20, true))
	col.add_child(frame)
	_box = VBoxContainer.new()
	_box.custom_minimum_size.x = 400
	_box.add_theme_constant_override("separation", 10)
	frame.add_child(_box)
	var foot = UI.label("Map traced from the Holy Empire of Menslosia lore map", 12, Tokens.TEXT_FAINT)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.custom_minimum_size.y = 34
	foot.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	col.add_child(foot)
	refresh()


var _emblem: TextureRect
var _t := 0.0


func _process(delta: float) -> void:
	if not visible or _emblem == null:
		return
	_t += delta
	_emblem.pivot_offset = _emblem.size / 2.0
	_emblem.rotation = sin(_t * 0.25) * 0.04   # a slow sway, like a hanging banner
	_emblem.modulate = Color(1, 1, 1, 0.92 + 0.08 * sin(_t * 0.8))


func refresh() -> void:
	UI.clear(_box)
	var saves: Array = Game.list_saves()
	if saves.size() > 0:
		var latest: Dictionary = saves[0]
		_box.add_child(_big("Continue: %s, %s" % [latest.get("nation", ""), latest.get("date", "")], func(): load_pressed.emit(latest["file"])))
	_box.add_child(_big("New Game", func(): new_game_pressed.emit()))
	_box.add_child(_big("Load Game", func(): _saves_box.visible = not _saves_box.visible))
	_saves_box = VBoxContainer.new()
	_saves_box.visible = false
	_saves_box.add_theme_constant_override("separation", 4)
	if saves.is_empty():
		_saves_box.add_child(UI.label("No saved games yet.", 13, UI.TEXT_DIM))
	for s in saves:
		var row = HBoxContainer.new()
		var b = UI.button("%s  -  %s, %s" % [s.get("name", s["file"]), s.get("nation", ""), s.get("date", "")], func(): load_pressed.emit(s["file"]))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(b)
		row.add_child(UI.button("Delete", func(): Game.delete_save(s["file"]); refresh()))
		_saves_box.add_child(row)
	_box.add_child(_saves_box)
	_box.add_child(_big("Settings", func(): settings_pressed.emit()))
	_box.add_child(_big("Quit", func(): get_tree().quit()))


func _big(text: String, cb: Callable) -> Button:
	var b = UI.button(text, cb)
	b.custom_minimum_size = Vector2(400, 46)
	b.add_theme_font_override("font", Tokens.font("title"))
	b.add_theme_font_size_override("font_size", 17)
	return b
