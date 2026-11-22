extends Control
## Settings window (from the main menu or the Esc menu): display, autosave and message options.

signal closed

const UI = preload("res://scripts/ui/ui_util.gd")
const Settings = preload("res://scripts/settings.gd")

var _box: VBoxContainer


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
	_box.custom_minimum_size.x = 460
	_box.add_theme_constant_override("separation", 10)
	panel.add_child(_box)
	visible = false


func open() -> void:
	visible = true
	refresh()


func close() -> void:
	visible = false
	closed.emit()


func refresh() -> void:
	UI.clear(_box)
	_box.add_child(UI.heading("Settings", 24))
	_box.add_child(UI.divider())

	_box.add_child(UI.heading("Display", 15))
	_box.add_child(_check("Fullscreen", "fullscreen", true))
	var scale_row := HBoxContainer.new()
	var scale_lbl = UI.label("Interface size  %d%%" % int(round(float(Settings.get_value("ui_scale")) * 100)), 14)
	scale_lbl.custom_minimum_size.x = 170
	scale_row.add_child(scale_lbl)
	var s := HSlider.new()
	s.min_value = 0.8
	s.max_value = 1.5
	s.step = 0.05
	s.value = float(Settings.get_value("ui_scale"))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.tooltip_text = "Makes every window, label and button bigger or smaller. Larger helps on high-resolution screens."
	s.value_changed.connect(func(v): scale_lbl.text = "Interface size  %d%%" % int(round(v * 100)))
	s.drag_ended.connect(func(_changed):
		Settings.set_value("ui_scale", s.value)
		Settings.apply(get_tree()))
	scale_row.add_child(s)
	_box.add_child(scale_row)

	_box.add_child(UI.heading("Sound", 15))
	_box.add_child(_volume("Master volume", "master_volume"))
	_box.add_child(_volume("Music", "music_volume"))
	_box.add_child(_volume("Effects", "sfx_volume"))
	_box.add_child(UI.heading("Game", 15))
	_box.add_child(_check("Pause on important news (wars, peace, bankruptcy)", "pause_on_news", false))
	_box.add_child(_check("Pan the map when the mouse touches the screen edge", "edge_scroll", false))
	var auto := OptionButton.new()
	var choices := ["off", "monthly", "yearly"]
	for c in choices:
		auto.add_item({"off": "Never", "monthly": "Every month", "yearly": "Every year (1 January)"}[c])
	auto.selected = maxi(0, choices.find(String(Settings.get_value("autosave"))))
	auto.item_selected.connect(func(i): Settings.set_value("autosave", choices[i]))
	auto.tooltip_text = "Autosaves rotate between %d slots and show up under Continue and Load." % Settings.AUTOSAVE_SLOTS
	_box.add_child(UI.row([UI.label("Autosave", 14), UI.spacer(), auto]))

	_box.add_child(UI.divider())
	var done = UI.button("Done", close)
	done.custom_minimum_size = Vector2(440, 36)
	_box.add_child(done)


func _check(text: String, key: String, display: bool) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = bool(Settings.get_value(key))
	c.toggled.connect(func(on):
		Settings.set_value(key, on)
		if display:
			Settings.apply(get_tree()))
	return c


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _volume(title: String, key: String) -> HBoxContainer:
	## A 0-100% slider for one of the Sound autoload's buses; changes are heard at once.
	var row := HBoxContainer.new()
	var lbl = UI.label("%s  %d%%" % [title, int(round(float(Settings.get_value(key)) * 100))], 14)
	lbl.custom_minimum_size.x = 170
	row.add_child(lbl)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(Settings.get_value(key))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(v):
		lbl.text = "%s  %d%%" % [title, int(round(v * 100))]
		Settings.set_value(key, v)
		var snd = get_tree().root.get_node_or_null("Sound")
		if snd != null:
			snd.apply_volume())
	row.add_child(s)
	return row
