extends Control
## Title screen: new game, continue, load, quit.

signal new_game_pressed
signal load_pressed(slot: String)

const UI = preload("res://scripts/ui/ui_util.gd")

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
	map.modulate = Color(1, 1, 1, 0.22)
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(map)
	var centre = CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	_box = VBoxContainer.new()
	_box.custom_minimum_size.x = 440
	_box.add_theme_constant_override("separation", 12)
	centre.add_child(_box)
	refresh()


func refresh() -> void:
	UI.clear(_box)
	var title = UI.label("ARCADIA", 64, UI.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(title)
	var sub = UI.label("The First World, after the Incendium", 18, UI.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(sub)
	_box.add_child(HSeparator.new())
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
	_box.add_child(_big("Quit", func(): get_tree().quit()))
	var v = UI.label("Prototype. Map traced from the Holy Empire of Menslosia lore map.", 11, UI.TEXT_DIM)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(v)


func _big(text: String, cb: Callable) -> Button:
	var b = UI.button(text, cb)
	b.custom_minimum_size = Vector2(440, 44)
	b.add_theme_font_size_override("font_size", 18)
	return b
