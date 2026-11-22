extends PanelContainer
## Nation resources, date and speed controls along the top of the screen.

signal open_panel(name: String)
signal menu_pressed

const UI = preload("res://scripts/ui/ui_util.gd")
const Icons = preload("res://ui/style/icons.gd")
const Tokens = preload("res://ui/style/tokens.gd")
const POWER_ICONS := ["scroll", "quill", "helmet"]

var _row: HBoxContainer
var _name: Label
var _swatch: ColorRect
var _sanctum: Label
var _power: Array = []
var _stability: Label
var _manpower: Label
var _legit: Label
var _regs: Label
var _we: Label
var _doom: Label
var _war: Label
var _date: Label
var _speed: Label
var _pips: Array = []
var _pause: Button
var _last_speed = 2
var _dirty = true
var _t = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	theme_type_variation = "TopBarPanel"
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", Tokens.SP_4)
	add_child(_row)
	_swatch = UI.swatch(Color.GRAY, Vector2(6, 26))
	_name = UI.heading("", 17)
	_name.mouse_filter = Control.MOUSE_FILTER_PASS
	var nb = UI.row([_swatch, _name])
	nb.mouse_filter = Control.MOUSE_FILTER_PASS
	nb.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: open_panel.emit("court"))
	_row.add_child(nb)
	_row.add_child(VSeparator.new())
	_sanctum = _stat("economy", "sanctum", Tokens.GOLD)
	for i in 3:
		_power.append(_stat("tech", POWER_ICONS[i], Tokens.TEXT))
	_stability = _stat("court", "stability", Tokens.TEXT)
	_legit = _stat("court", "legitimacy", Tokens.TEXT)
	_manpower = _stat("military", "manpower", Tokens.TEXT)
	_regs = _stat("production", "swords", Tokens.TEXT)
	_we = _stat("diplomacy", "shield_broken", Tokens.BAD)
	var spacer = UI.spacer()
	_row.add_child(spacer)
	_war = UI.label("", 14, UI.BAD)
	_row.add_child(_war)
	_doom = UI.label("THE BLACK MOON HAS RISEN", 15, UI.DOOM)
	_doom.visible = false
	_row.add_child(_doom)
	# date and speed, EU4-style: the date, then pause and five speed pips
	var clock = HBoxContainer.new()
	clock.add_theme_constant_override("separation", Tokens.SP_1)
	clock.add_child(UI.icon("hourglass", 18, Tokens.TEXT_DIM))
	_date = UI.heading("", 16)
	_date.add_theme_color_override("font_color", Tokens.TEXT)
	_date.custom_minimum_size.x = 196
	_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock.add_child(_date)
	_row.add_child(clock)
	_pause = UI.icon_button("play", "", _toggle_pause, "Pause or play (Space)", 16)
	_pause.custom_minimum_size = Vector2(36, 30)
	_pause.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_row.add_child(_pause)
	var minus = UI.icon_button("minus", "", func(): Game.act("set_speed", [maxi(1, Game.speed - 1)]); refresh(), "Slower (1-5)", 12)
	minus.theme_type_variation = "FlatButton"
	minus.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_row.add_child(minus)
	var pips = HBoxContainer.new()
	pips.add_theme_constant_override("separation", 3)
	pips.tooltip_text = "Game speed (1-5)"
	pips.mouse_filter = Control.MOUSE_FILTER_PASS
	for i in 5:
		var pip = ColorRect.new()
		pip.custom_minimum_size = Vector2(6, 8 + i * 3)
		pip.size_flags_vertical = Control.SIZE_SHRINK_END
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pips.add_child(pip)
		_pips.append(pip)
	var pip_box = MarginContainer.new()
	pip_box.add_theme_constant_override("margin_bottom", 6)
	pip_box.add_child(pips)
	pip_box.tooltip_text = "Game speed (1-5)"
	_row.add_child(pip_box)
	_speed = UI.label("", 13, UI.GOLD)
	_speed.visible = false
	_row.add_child(_speed)
	var plus = UI.icon_button("plus", "", func(): Game.act("set_speed", [mini(5, maxi(1, Game.speed) + 1)]); refresh(), "Faster (1-5)", 12)
	plus.theme_type_variation = "FlatButton"
	plus.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_row.add_child(plus)
	var menu = UI.icon_button("menu", "", func(): menu_pressed.emit(), "Save, load, main menu (Esc)", 18)
	menu.custom_minimum_size = Vector2(36, 30)
	menu.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_row.add_child(menu)
	Game.date_changed.connect(func(): _dirty = true)
	Game.nation_changed.connect(func(_t): _dirty = true)
	Game.doomsday_changed.connect(func(a): _doom.visible = a)
	Game.war_changed.connect(func(): _dirty = true)
	refresh()


func _stat(panel: String, icon_name: String, tint: Color) -> Label:
	## An icon and a number; hovering shows the tooltip, clicking opens the panel.
	var box = HBoxContainer.new()
	box.add_theme_constant_override("separation", Tokens.SP_1 + 1)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(UI.icon(icon_name, 20, tint))
	var l = UI.label("", 15)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(l)
	box.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: open_panel.emit(panel))
	l.visibility_changed.connect(func(): box.visible = l.visible)
	_row.add_child(box)
	return l


func _toggle_pause() -> void:
	Game.act("set_speed", [0 if Game.speed > 0 else maxi(1, _last_speed)])
	refresh()


func _process(delta: float) -> void:
	_t += delta
	if _dirty and _t > 0.15:
		refresh()


func refresh() -> void:
	_dirty = false
	_t = 0.0
	if Game.speed > 0:
		_last_speed = Game.speed
	_date.text = Game.date_string()
	_pause.icon = Icons.tex("pause" if Game.speed > 0 else "play", 16)
	var spd = maxi(1, Game.speed if Game.speed > 0 else _last_speed)
	_speed.text = "Speed %d" % spd
	for i in 5:
		_pips[i].color = (Tokens.GOLD if Game.speed > 0 else Tokens.TEXT_DIM) if i < spd else Color(1, 1, 1, 0.12)
	_date.add_theme_color_override("font_color", Tokens.TEXT if Game.speed > 0 else Tokens.TEXT_DIM)
	var n: Dictionary = Game.player()
	if n.is_empty():
		return
	var tag = Game.player_tag
	_swatch.color = n["colour"]
	_name.text = n["short"]
	_name.tooltip_text = "%s\n%s\nClick for the court." % [n["name"], Game.court.describe(n["ruler"], n["power_names"])]
	var b: Dictionary = Game.eco.budget(tag)
	_sanctum.text = "%s  %s" % [UI.money(n["treasury"]), UI.signed(b["balance"])]
	_sanctum.add_theme_color_override("font_color", UI.BAD if float(n["treasury"]) < 0.0 else UI.GOLD)
	_sanctum.tooltip_text = "Sanctum, per month:\n  Tax %s\n  Production %s\n  Trade %s\n  Expenses %s\nLoans: %d\nClick for the economy." % [
		UI.signed(b["tax"]), UI.signed(b["production"]), UI.signed(b["trade"]), UI.signed(-b["expenses"]), n["loans"].size()]
	var gain = Game.power_gain(tag)
	var kinds = ["administrative: develops tax, cores, admin tech, stability",
		"diplomatic: develops production, explores, dip tech, cultures", "military: develops manpower, generals, mil tech"]
	for i in 3:
		_power[i].text = "%d" % int(n["power"][i])
		_power[i].tooltip_text = "%s %d  (+%d a month)\n" % [n["power_names"][i], int(n["power"][i]), int(gain[i])] + "%s power (%s)\n+%d a month (3 base + ruler skill %d + modifiers)\nClick for technology." % [
			n["power_names"][i], kinds[i], int(gain[i]), Game.court.ruler_stat(tag, i)]
	var st: int = n["stability"]
	_stability.text = "%+d" % st
	_stability.add_theme_color_override("font_color", UI.GOOD if st > 0 else (UI.BAD if st < 0 else UI.TEXT))
	_stability.tooltip_text = "Stability %+d\n" % st + "Stability (-3 to +3). Each point: +5% tax and -1 unrest everywhere.\nClick for the court."
	_manpower.text = "%.1fk" % (float(n["manpower"]) / 1000.0)
	_manpower.tooltip_text = ("Manpower %d / %d\n" % [int(n["manpower"]), int(n["max_manpower"])]) + "Soldiers available to recruit and reinforce. Refills over ten years.\nRegiments: %d of %d force limit\nClick for the military." % [
		Game.mil.regiment_count(tag), Game.mil.land_force_limit(tag)]
	var leg = float(n.get("legitimacy", 50.0))
	var lname: String = Game.court.legitimacy_name(tag)
	_legit.text = "%d" % int(leg)
	_legit.add_theme_color_override("font_color", UI.BAD if leg < 50.0 else (UI.GOOD if leg >= 80.0 else UI.TEXT))
	_legit.tooltip_text = "%s %d (%+.1f a year). Low values cost power and stir unrest.\nClick for the court." % [lname, int(leg), Game.court.legitimacy_gain(tag)]
	var regs: int = Game.mil.regiment_count(tag)
	var fl: int = Game.mil.land_force_limit(tag)
	_regs.text = "%d/%d" % [regs, fl]
	_regs.add_theme_color_override("font_color", UI.BAD if regs > fl else UI.TEXT)
	_regs.tooltip_text = "Army %d regiments, force limit %d\n" % [regs, fl] + "Regiments / force limit. You can't recruit past the force limit (+50% in wartime).\nClick for production."
	var we = float(n["war_exhaustion"])
	_we.text = "%.1f" % we
	_we.visible = we > 0.05
	_we.tooltip_text = "War exhaustion %.1f: +%.1f unrest in every province. Fades in peacetime." % [we, we * 0.5]
	var wars = Game.dip.wars_of(tag)
	_war.text = "AT WAR (%d)" % wars.size() if wars.size() > 0 else ""
	if wars.size() > 0:
		var lines: PackedStringArray = []
		for w in wars:
			lines.append("%s: war score %+d" % [w["name"], int(Game.dip.score_for(w, tag))])
		_war.tooltip_text = "\n".join(lines)
		_war.mouse_filter = Control.MOUSE_FILTER_PASS
	for l in [_sanctum, _stability, _legit, _manpower, _regs, _we] + _power:
		l.get_parent().tooltip_text = l.tooltip_text
