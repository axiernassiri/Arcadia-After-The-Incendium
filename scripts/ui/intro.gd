extends Control
## The opening: the Incendium cutscene (from data/cutscene.json).

signal finished

const UI = preload("res://scripts/ui/ui_util.gd")
const Tokens = preload("res://ui/style/tokens.gd")

var _beat = 0
var _card: VBoxContainer
var _year: Label
var _heading: Label
var _text: Label
var _progress: Label
var _glow: TextureRect
var _t := 0.0


func _process(delta: float) -> void:
	if not visible or _glow == null:
		return
	_t += delta
	_glow.pivot_offset = _glow.size / 2.0
	_glow.rotation = _t * 0.02
	_glow.modulate.a = 0.09 + 0.04 * sin(_t * 0.9)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg = ColorRect.new()
	bg.color = Color(0.04, 0.035, 0.04)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var glow = TextureRect.new()  # the burning world: a slow-pulsing ember sun behind the text
	glow.texture = load("res://assets/ui/emblem.png")
	glow.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	glow.custom_minimum_size = Vector2(720, 720)
	glow.position = -glow.custom_minimum_size / 2.0
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glow.modulate = Color(1.0, 0.45, 0.2, 0.10)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)
	_glow = glow
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
	_card = VBoxContainer.new()
	_card.custom_minimum_size.x = 760
	_card.add_theme_constant_override("separation", 14)
	centre.add_child(_card)
	visible = false


func play() -> void:
	visible = true
	UI.clear(_card)
	var cs: Dictionary = Game.cutscene
	var title = UI.heading(cs.get("title", "The Incendium").to_upper(), 42)
	title.add_theme_color_override("font_color", Color(0.98, 0.52, 0.28))
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.add_child(title)
	var by = UI.label(cs.get("narrator", ""), 14, UI.TEXT_DIM)
	by.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.add_child(by)
	_card.add_child(UI.divider())
	_year = UI.heading("", 30)
	_year.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.add_child(_year)
	_heading = UI.heading("", 20)
	_heading.add_theme_color_override("font_color", Tokens.TEXT)
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.add_child(_heading)
	_text = UI.label("", 19, UI.TEXT, 760)
	_text.add_theme_font_override("font", Tokens.font("body"))
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.custom_minimum_size.y = 120
	_card.add_child(_text)
	_progress = UI.label("", 12, UI.TEXT_DIM)
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.add_child(_progress)
	var buttons = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	var skip = UI.button("Skip intro", _finish, "Esc")
	skip.theme_type_variation = "FlatButton"
	buttons.add_child(skip)
	var cont = UI.button("Continue", next_beat, "Space or Enter")
	cont.custom_minimum_size = Vector2(180, 40)
	cont.add_theme_font_override("font", Tokens.font("title"))
	buttons.add_child(cont)
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
