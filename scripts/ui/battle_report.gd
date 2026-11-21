extends PanelContainer
## EU4-style battle result: who fought, the generals, the losses and the terrain. Pops up after every
## land battle the player fights in, does not pause, and closes itself after a few seconds (or on click).

signal province_clicked(id: int)

const UI = preload("res://scripts/ui/ui_util.gd")
const Tokens = preload("res://ui/style/tokens.gd")
const WIDTH := 400.0
const SHOW_SECONDS := 12.0

var _box: VBoxContainer
var _left := 0.0
var _pid := -1


func _ready() -> void:
	custom_minimum_size.x = WIDTH
	add_theme_stylebox_override("panel", UI.tex_box("panel.png", 12, 18, 14, true))
	mouse_filter = Control.MOUSE_FILTER_STOP
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	add_child(_box)
	visible = false
	Game.battle_report.connect(show_report)


func _process(delta: float) -> void:
	if visible and not get_global_rect().has_point(get_global_mouse_position()):
		_left -= delta
		if _left <= 0.0:
			visible = false


func show_report(r: Dictionary) -> void:
	_pid = int(r["pid"])
	var won: bool = Game.player_tag in r["winners"]
	UI.clear(_box)
	var col: Color = UI.GOOD if won else UI.BAD
	var head = UI.heading(("Victory at %s" if won else "Defeat at %s") % r["province"], 19)
	head.add_theme_color_override("font_color", col)
	var close = UI.icon_button("close", "", func(): visible = false, "Close", 12)
	close.theme_type_variation = "FlatButton"
	_box.add_child(UI.row([UI.icon("battle", 20, col), head, UI.spacer(), close], 8))
	_box.add_child(UI.label("%s  ·  %s  ·  %d days%s" % [r["date"], r["terrain"], int(r["days"]),
		"  ·  the loser was wiped out" if r.get("wiped", false) else ""], 12, UI.TEXT_DIM))
	_box.add_child(UI.divider())
	var cols = HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	cols.add_child(_side("Winners", r["winners"], r["win_generals"], float(r["win_men"]), float(r["win_losses"]), UI.GOOD))
	cols.add_child(VSeparator.new())
	cols.add_child(_side("Losers", r["losers"], r["lose_generals"], float(r["lose_men"]), float(r["lose_losses"]), UI.BAD))
	_box.add_child(cols)
	var go = UI.button("Go to %s" % r["province"], func(): province_clicked.emit(_pid); visible = false)
	go.theme_type_variation = "FlatButton"
	_box.add_child(go)
	_left = SHOW_SECONDS
	visible = true
	reset_size()


func _side(title: String, tags: Array, generals: Array, men: float, losses: float, col: Color) -> VBoxContainer:
	var v = VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	v.add_child(UI.label(title, 13, col))
	for t in tags:
		var nm: String = Game.nations[t]["short"] if Game.nations.has(t) else ("Rebels" if t == "REB" else "Entities")
		v.add_child(UI.row([UI.swatch(Game.owner_colour(t), Vector2(10, 10)), UI.label(nm, 13)], 6))
	for gname in generals:
		v.add_child(UI.label("General " + String(gname), 11, UI.TEXT_DIM, WIDTH / 2.0 - 30.0))
	if generals.is_empty():
		v.add_child(UI.label("No general", 11, Tokens.TEXT_FAINT))
	v.add_child(UI.kv("Losses", "%d" % int(losses), "", UI.BAD))
	v.add_child(UI.kv("Left standing", "%d" % int(men)))
	return v
