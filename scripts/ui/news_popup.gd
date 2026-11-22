extends PanelContainer
## EU4-style message popup for big news that concerns the player (a war declared on you, a peace
## forced on you, bankruptcy). Pauses the game when "Pause on important news" is on.

signal paused_changed

const UI = preload("res://scripts/ui/ui_util.gd")
const Settings = preload("res://scripts/settings.gd")
const WIDTH := 440.0

var _queue: Array = []   # [[title, text]]
var _box: VBoxContainer


func _ready() -> void:
	custom_minimum_size.x = WIDTH
	add_theme_stylebox_override("panel", UI.tex_box("panel.png", 12, 22, 18, true))
	mouse_filter = Control.MOUSE_FILTER_STOP
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	add_child(_box)
	visible = false
	Game.major_news.connect(_on_news)


func _on_news(title: String, text: String) -> void:
	_queue.append([title, text])
	UI.sfx("war" if title in ["War Declared", "Coalition War"] else "event")
	if Settings.get_value("pause_on_news"):
		Game.set_speed(0)
		paused_changed.emit()
	if not visible:
		_show_next()


func clear() -> void:
	_queue.clear()
	visible = false


func _show_next() -> void:
	if _queue.is_empty():
		visible = false
		return
	var item: Array = _queue.pop_front()
	UI.clear(_box)
	var bad: bool = item[0] in ["War Declared", "Bankruptcy"]
	var col: Color = UI.BAD if bad else UI.GOLD
	var head = UI.heading(item[0], 20)
	head.add_theme_color_override("font_color", col)
	var more := " (%d more)" % _queue.size() if _queue.size() > 0 else ""
	_box.add_child(UI.row([UI.icon("swords" if bad else "seal", 22, col), head, UI.spacer(),
		UI.label(Game.date_string() + more, 12, UI.TEXT_DIM)], 10))
	_box.add_child(UI.divider())
	_box.add_child(UI.label(item[1], 14, UI.TEXT, WIDTH - 44))
	var ok = UI.button("OK", _show_next, "Close (the game stays paused: press Space to play)")
	ok.custom_minimum_size = Vector2(WIDTH - 44, 32)
	_box.add_child(ok)
	visible = true
	reset_size()
