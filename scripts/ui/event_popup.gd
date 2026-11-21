extends PanelContainer
## Shows the player's pending events one at a time. Time stays paused until each is answered.

const UI = preload("res://scripts/ui/ui_util.gd")
const WIDTH := 560.0

var _box: VBoxContainer
var _current: Dictionary = {}


func _ready() -> void:
	custom_minimum_size.x = WIDTH
	add_theme_stylebox_override("panel", UI.tex_box("panel.png", 12, 24, 20, true))
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	add_child(_box)
	visible = false
	Game.event_fired.connect(func(_inst): call_deferred("_show_next"))


func _show_next() -> void:
	if Game.pending_events.is_empty():
		visible = false
		_current = {}
		return
	if visible and Game.pending_events.has(_current):
		return
	_current = Game.pending_events[0]
	var e: Dictionary = _current["event"]
	var doom: bool = e.get("trigger", {}).get("special", "") == "doomsday"
	var war: bool = e.get("id", "") in ["call_to_arms", "peace_offer", "game_over"]
	var col: Color = UI.DOOM if doom else (UI.BAD if war else UI.GOLD)
	var icon_name: String = "moon" if doom else ("swords" if war else ("portal" if "entit" in e.get("id", "") else "seal"))
	UI.clear(_box)
	var medal = PanelContainer.new()
	var ring = UI.box(Color(0.04, 0.045, 0.06), col, 26, 8)
	ring.set_border_width_all(2)
	medal.add_theme_stylebox_override("panel", ring)
	medal.add_child(UI.icon(icon_name, 34, col))
	var titles = VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t = UI.heading(e.get("title", ""), 22)
	t.add_theme_color_override("font_color", col)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = WIDTH - 120
	titles.add_child(t)
	titles.add_child(UI.label(_current.get("date", Game.date_string()), 13, UI.TEXT_DIM))
	_box.add_child(UI.row([medal, titles], 14))
	_box.add_child(UI.divider())
	_box.add_child(UI.label(e.get("text", ""), 15, UI.TEXT, WIDTH - 48))
	var gap = Control.new()
	gap.custom_minimum_size.y = 4
	_box.add_child(gap)
	var opts: Array = e.get("options", [])
	for i in opts.size():
		var o: Dictionary = opts[i]
		var fx: String = Game.describe_effects(o.get("effects", []), _current["tag"])
		var b = UI.button(o.get("text", "OK"), _choose.bind(i), fx)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(WIDTH - 40, 34)
		_box.add_child(b)
		if fx != "":
			_box.add_child(UI.label("      " + fx, 12, UI.TEXT_DIM, WIDTH - 40))
	if not visible:
		modulate.a = 0.0
		create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_property(self, "modulate:a", 1.0, 0.3)
	visible = true
	reset_size()


func _process(_delta: float) -> void:
	if visible and not Game.pending_events.has(_current):
		_show_next()
	elif not visible and not Game.pending_events.is_empty():
		_show_next()


func _choose(i: int) -> void:
	var inst = _current
	visible = false
	Game.resolve_event(inst, i)
	call_deferred("_show_next")
