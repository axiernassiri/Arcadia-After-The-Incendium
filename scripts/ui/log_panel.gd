extends PanelContainer
## The last few messages, bottom centre. "Realm" shows news about you, your allies, enemies and
## neighbours; "World" shows everything else (EU4-style message filtering). Click the text to
## show more or fewer lines.

const UI = preload("res://scripts/ui/ui_util.gd")
const Tokens = preload("res://ui/style/tokens.gd")

var _box: VBoxContainer
var _realm_btn: Button
var _world_btn: Button
var lines = 5
var world = false
var _dirty = true


func _ready() -> void:
	custom_minimum_size.x = 600
	theme_type_variation = "InkPanel"
	self_modulate = Color(1, 1, 1, 0.88)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 2)
	add_child(outer)
	_realm_btn = _tab("Realm", false, "News about you, your allies, enemies and neighbours")
	_world_btn = _tab("World", true, "Everything else happening in Arcadia")
	var more = UI.label("click to show more", 11, Tokens.TEXT_FAINT)
	more.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(UI.row([_realm_btn, _world_btn, UI.spacer(), more], 4))
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 2)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(_box)
	tooltip_text = "Click to show more or fewer messages."
	gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		lines = 16 if lines == 5 else 5
		_dirty = true)
	Game.message_posted.connect(func(_t): _dirty = true)
	refresh()


func _tab(text: String, is_world: bool, tip: String) -> Button:
	var b = UI.button(text, func(): world = is_world; _dirty = true, tip)
	b.theme_type_variation = "FlatButton"
	b.toggle_mode = true
	b.add_theme_font_size_override("font_size", 12)
	b.custom_minimum_size = Vector2(54, 20)
	return b


var _world_seen = ""


func _process(_d: float) -> void:
	if world:
		var key: String = "%d|%s" % [Game.world_lines.size(), Game.world_lines.back() if not Game.world_lines.is_empty() else ""]
		if key != _world_seen:   # the list is capped at 80, so the size alone stops changing
			_world_seen = key
			_dirty = true
	if _dirty:
		refresh()


static func line_colour(t: String, newest: bool) -> Color:
	if "BLACK MOON" in t or "Time reverses" in t:
		return UI.DOOM
	if "war on" in t or "Battle" in t or "risen" in t or "BANKRUPT" in t or "occupied" in t:
		return UI.BAD.lightened(0.2) if newest else UI.BAD
	if "Peace" in t or "allies" in t or "marriage" in t or "liberated" in t:
		return UI.GOOD if newest else UI.GOOD.darkened(0.15)
	return UI.TEXT if newest else UI.TEXT_DIM


func refresh() -> void:
	_dirty = false
	_realm_btn.set_pressed_no_signal(not world)
	_world_btn.set_pressed_no_signal(world)
	UI.clear(_box)
	var src: Array = Game.world_lines if world else Game.log_lines
	var shown: Array = src.slice(maxi(0, src.size() - lines))
	if shown.is_empty():
		var l = UI.label("Nothing yet.", 13, Tokens.TEXT_FAINT)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_box.add_child(l)
	for i in shown.size():
		var t: String = shown[i]
		var l = UI.label(t, 13, line_colour(t, i == shown.size() - 1), 580)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_box.add_child(l)
	reset_size()
