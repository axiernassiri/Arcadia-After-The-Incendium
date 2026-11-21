extends PanelContainer
## The last few messages, bottom centre. Click to see more.

const UI = preload("res://scripts/ui/ui_util.gd")

var _box: VBoxContainer
var lines = 5
var _dirty = true


func _ready() -> void:
	custom_minimum_size.x = 600
	theme_type_variation = "InkPanel"
	self_modulate = Color(1, 1, 1, 0.88)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Click to show more or fewer messages."
	gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		lines = 16 if lines == 5 else 5
		_dirty = true)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 2)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	Game.message_posted.connect(func(_t): _dirty = true)
	refresh()


func _process(_d: float) -> void:
	if _dirty:
		refresh()


func refresh() -> void:
	_dirty = false
	UI.clear(_box)
	var shown: Array = Game.log_lines.slice(maxi(0, Game.log_lines.size() - lines))
	for i in shown.size():
		var newest = i == shown.size() - 1
		var t: String = shown[i]
		var col = UI.DOOM if ("BLACK MOON" in t or "Time reverses" in t) else (UI.TEXT if newest else UI.TEXT_DIM)
		if "war on" in t or "Battle" in t or "risen" in t:
			col = UI.BAD if not newest else UI.BAD.lightened(0.2)
		var l = UI.label(t, 13, col, 580)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_box.add_child(l)
	reset_size()
