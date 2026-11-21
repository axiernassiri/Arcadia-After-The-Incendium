extends Control
## The opening: the Incendium cutscene (from data/cutscene.json).

signal finished

const UI = preload("res://scripts/ui/ui_util.gd")

var _beat = 0
var _card: VBoxContainer
var _year: Label
var _heading: Label
var _text: Label
var _progress: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg = ColorRect.new()
	bg.color = Color(0.04, 0.035, 0.04)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var glow = ColorRect.new()  # a dim ember glow behind the text
	glow.color = Color(0.35, 0.12, 0.05, 0.18)
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(glow)
	var centre = CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	_card = VBoxContainer.new()
	_card.custom_minimum_size.x = 760
	_card.add_theme_constant_override("separation", 14)
	centre.add_child(_card)
	visible = false


func play() -> void:
	visible = true
	UI.clear(_card)
	var cs: Dictionary = Game.cutscene
	var title = UI.label(cs.get("title", "The Incendium").to_upper(), 40, Color(0.95, 0.45, 0.25))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.add_child(title)
	var by = UI.label(cs.get("narrator", ""), 14, UI.TEXT_DIM)
	by.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.add_child(by)
	_card.add_child(HSeparator.new())
	_year = UI.label("", 30, UI.GOLD)
	_year.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.add_child(_year)
	_heading = UI.label("", 22, UI.TEXT)
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.add_child(_heading)
	_text = UI.label("", 18, UI.TEXT, 760)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.custom_minimum_size.y = 120
	_card.add_child(_text)
	_progress = UI.label("", 12, UI.TEXT_DIM)
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.add_child(_progress)
	var buttons = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	buttons.add_child(UI.button("Skip intro", _finish, "Esc"))
	buttons.add_child(UI.button("Continue", next_beat, "Space or Enter"))
	_card.add_child(buttons)
	_beat = 0
	_show_beat()


func _show_beat() -> void:
	var beats: Array = Game.cutscene.get("beats", [])
	if _beat >= beats.size():
		_finish()
		return
	var b: Dictionary = beats[_beat]
	_year.text = b.get("year", "")
	_heading.text = b.get("heading", "")
	_text.text = b.get("text", "")
	_progress.text = "%d / %d" % [_beat + 1, beats.size()]
	for l in [_year, _heading, _text]:
		l.modulate.a = 0.0
		var tw = create_tween()
		tw.tween_property(l, "modulate:a", 1.0, 0.6)


func next_beat() -> void:
	_beat += 1
	_show_beat()


func _finish() -> void:
	visible = false
	finished.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.pressed:
		return
	if event.keycode in [KEY_SPACE, KEY_ENTER]:
		next_beat()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE:
		_finish()
		get_viewport().set_input_as_handled()
