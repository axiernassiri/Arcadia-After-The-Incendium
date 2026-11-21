extends PanelContainer
## Ctrl+F: find a province or a nation by name and jump to it. Enter picks the first match.

signal province_chosen(id: int)
signal nation_chosen(tag: String)

const UI = preload("res://scripts/ui/ui_util.gd")
const WIDTH := 380.0
const MAX_RESULTS := 9

var _edit: LineEdit
var _list: VBoxContainer
var _first: Callable


func _ready() -> void:
	custom_minimum_size.x = WIDTH
	add_theme_stylebox_override("panel", UI.tex_box("panel.png", 12, 16, 12, true))
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	add_child(v)
	_edit = LineEdit.new()
	_edit.placeholder_text = "Find a province or nation…"
	_edit.clear_button_enabled = true
	_edit.text_changed.connect(func(_t): _refresh())
	_edit.text_submitted.connect(func(_t): if _first.is_valid(): _first.call())
	v.add_child(_edit)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 1)
	v.add_child(_list)
	visible = false


func open() -> void:
	visible = true
	_edit.text = ""
	_refresh()
	_edit.grab_focus()


func close() -> void:
	visible = false
	_edit.release_focus()


func _refresh() -> void:
	UI.clear(_list)
	_first = Callable()
	var q: String = _edit.text.strip_edges().to_lower()
	if q.length() < 1:
		_list.add_child(UI.label("Type a name. Enter jumps to the first match, Esc closes.", 12, UI.TEXT_DIM))
		reset_size()
		return
	var hits: Array = []   # [score, kind, key, label]
	for t in Game.nations:
		var n: Dictionary = Game.nations[t]
		if not n["alive"] or t in ["REB", "ENT"]:
			continue
		for nm in [String(n["short"]), String(n["name"])]:
			var at: int = String(nm).to_lower().find(q)
			if at >= 0:
				hits.append([at, "nation", t, "%s  (nation, %d provinces)" % [n["name"], Game.owned(t).size()]])
				break
	for pid in Game.provinces:
		var p: Dictionary = Game.provinces[pid]
		if not Game.is_explored_by_player(pid):
			continue
		var at := String(p["name"]).to_lower().find(q)
		if at >= 0:
			var owner: String = Game.nations[p["owner"]]["short"] if Game.nations.has(p["owner"]) else "uninhabited"
			hits.append([at + 0.5, "province", pid, "%s  (%s, %s)" % [p["name"], owner, "Skyfall" if p["layer"] == "sky" else "mainland"]])
	hits.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	if hits.is_empty():
		_list.add_child(UI.label("Nothing called that (unexplored places are hidden).", 12, UI.TEXT_DIM))
	for h in hits.slice(0, MAX_RESULTS):
		var cb: Callable
		if h[1] == "nation":
			cb = func(): nation_chosen.emit(h[2]); close()
		else:
			cb = func(): province_chosen.emit(int(h[2])); close()
		if not _first.is_valid():
			_first = cb
		var b = UI.button(h[3], cb)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.theme_type_variation = "FlatButton"
		b.custom_minimum_size.x = WIDTH - 32
		_list.add_child(b)
	reset_size()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# Esc while typing: the LineEdit has focus, so catch it before it is consumed
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _edit.has_focus():
		close()
		get_viewport().set_input_as_handled()
