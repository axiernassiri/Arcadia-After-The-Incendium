extends Control
## The in-game menu (Esc): resume, save, load, return to the main menu, quit.

signal resume
signal main_menu
signal loaded
signal settings_pressed

const UI = preload("res://scripts/ui/ui_util.gd")

var _box: VBoxContainer
var _name: LineEdit
var _msg: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var centre = CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.tex_box("panel.png", 12, 26, 22, true))
	centre.add_child(panel)
	_box = VBoxContainer.new()
	_box.custom_minimum_size.x = 420
	_box.add_theme_constant_override("separation", 8)
	panel.add_child(_box)
	visible = false


func open() -> void:
	visible = true
	Game.set_speed(0)
	refresh()


func refresh(msg: String = "") -> void:
	UI.clear(_box)
	_box.add_child(UI.heading("Menu", 24))
	_box.add_child(_big("Resume", func(): visible = false; resume.emit()))
	_box.add_child(HSeparator.new())
	_box.add_child(UI.label("Save game", 15, UI.GOLD))
	_name = LineEdit.new()
	_name.text = "%s %s" % [Game.nation_name(Game.player_tag), Game.date_string()]
	_name.custom_minimum_size.x = 400
	_box.add_child(_name)
	_box.add_child(_big("Save", _save))
	_box.add_child(HSeparator.new())
	_box.add_child(UI.label("Load game", 15, UI.GOLD))
	var saves: Array = Game.list_saves()
	if saves.is_empty():
		_box.add_child(UI.label("No saved games yet.", 13, UI.TEXT_DIM))
	for s in saves.slice(0, 8):
		var row = HBoxContainer.new()
		var b = UI.button("%s  -  %s, %s" % [s.get("name", s["file"]), s.get("nation", ""), s.get("date", "")], func(): _load(s["file"]))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(b)
		row.add_child(UI.button("Delete", func(): Game.delete_save(s["file"]); refresh()))
		_box.add_child(row)
	_box.add_child(HSeparator.new())
	_box.add_child(_big("Settings", func(): settings_pressed.emit()))
	_box.add_child(_big("Main menu", func(): visible = false; main_menu.emit()))
	_box.add_child(_big("Quit to desktop", func(): get_tree().quit()))
	_msg = UI.label(msg, 13, UI.GOOD)
	_box.add_child(_msg)


func _big(text: String, cb: Callable) -> Button:
	var b = UI.button(text, cb)
	b.custom_minimum_size = Vector2(400, 36)
	return b


func _save() -> void:
	var name = _name.text.strip_edges()
	if name == "":
		name = "save"
	var err = Game.save_game(name)
	refresh(err if err != "" else "Saved \"%s\"." % name)


func _load(slot: String) -> void:
	var err = Game.load_game(slot)
	if err != "":
		refresh(err)
		return
	visible = false
	loaded.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.pressed and event.keycode == KEY_ESCAPE:
		visible = false
		resume.emit()
		get_viewport().set_input_as_handled()
