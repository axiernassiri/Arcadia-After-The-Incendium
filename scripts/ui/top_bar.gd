extends PanelContainer
## Nation resources, date and speed controls along the top of the screen.

signal open_panel(name: String)
signal menu_pressed

const UI = preload("res://scripts/ui/ui_util.gd")

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
var _pause: Button
var _last_speed = 2
var _dirty = true
var _t = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	add_theme_stylebox_override("panel", UI.box(UI.BG_DARK, UI.BORDER, 0, 8))
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 16)
	add_child(_row)
	_swatch = UI.swatch(Color.GRAY, Vector2(18, 18))
	_name = UI.label("", 16, UI.GOLD)
	_name.mouse_filter = Control.MOUSE_FILTER_PASS
	var nb = UI.row([_swatch, _name])
	nb.mouse_filter = Control.MOUSE_FILTER_PASS
	nb.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: open_panel.emit("court"))
	_row.add_child(nb)
	_sanctum = _stat("economy")
	for i in 3:
		_power.append(_stat("tech"))
	_stability = _stat("court")
	_legit = _stat("court")
	_manpower = _stat("military")
	_regs = _stat("production")
	_we = _stat("diplomacy")
	var spacer = UI.spacer()
	_row.add_child(spacer)
	_war = UI.label("", 14, UI.BAD)
	_row.add_child(_war)
	_doom = UI.label("THE BLACK MOON HAS RISEN", 15, UI.DOOM)
	_doom.visible = false
	_row.add_child(_doom)
	_date = UI.label("", 16, UI.TEXT)
	_date.custom_minimum_size.x = 170
	_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_row.add_child(_date)
	_pause = UI.button("Play", _toggle_pause, "Space")
	_pause.custom_minimum_size.x = 64
	_row.add_child(_pause)
	_row.add_child(UI.button("-", func(): Game.set_speed(maxi(1, Game.speed - 1)); refresh(), "Slower (1-5)"))
	_speed = UI.label("", 14, UI.GOLD)
	_speed.custom_minimum_size.x = 58
	_row.add_child(_speed)
	_row.add_child(UI.button("+", func(): Game.set_speed(mini(5, maxi(1, Game.speed) + 1)); refresh(), "Faster (1-5)"))
	_row.add_child(UI.button("Menu", func(): menu_pressed.emit(), "Save, load, main menu (Esc)"))
	Game.date_changed.connect(func(): _dirty = true)
	Game.nation_changed.connect(func(_t): _dirty = true)
	Game.doomsday_changed.connect(func(a): _doom.visible = a)
	Game.war_changed.connect(func(): _dirty = true)
	refresh()


func _stat(panel: String) -> Label:
	var l = UI.label("", 14)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: open_panel.emit(panel))
	_row.add_child(l)
	return l


func _toggle_pause() -> void:
	Game.set_speed(0 if Game.speed > 0 else maxi(1, _last_speed))
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
	_pause.text = "Pause" if Game.speed > 0 else "Play"
	_speed.text = "Speed %d" % maxi(1, Game.speed if Game.speed > 0 else _last_speed)
	var n: Dictionary = Game.player()
	if n.is_empty():
		return
	var tag = Game.player_tag
	_swatch.color = n["colour"]
	_name.text = n["short"]
	_name.tooltip_text = "%s\n%s\nClick for the court." % [n["name"], Game.court.describe(n["ruler"], n["power_names"])]
	var b: Dictionary = Game.eco.budget(tag)
	_sanctum.text = "Sanctum %s (%s)" % [UI.money(n["treasury"]), UI.signed(b["balance"])]
	_sanctum.add_theme_color_override("font_color", UI.BAD if float(n["treasury"]) < 0.0 else UI.GOLD)
	_sanctum.tooltip_text = "Sanctum, per month:\n  Tax %s\n  Production %s\n  Trade %s\n  Expenses %s\nLoans: %d\nClick for the economy." % [
		UI.signed(b["tax"]), UI.signed(b["production"]), UI.signed(b["trade"]), UI.signed(-b["expenses"]), n["loans"].size()]
	var gain = Game.power_gain(tag)
	var kinds = ["administrative: develops tax, cores, admin tech, stability",
		"diplomatic: develops production, explores, dip tech, cultures", "military: develops manpower, generals, mil tech"]
	for i in 3:
		_power[i].text = "%s %d (+%d)" % [n["power_names"][i], int(n["power"][i]), int(gain[i])]
		_power[i].tooltip_text = "%s power (%s)\n+%d a month (3 base + ruler skill %d + modifiers)\nClick for technology." % [
			n["power_names"][i], kinds[i], int(gain[i]), Game.court.ruler_stat(tag, i)]
	var st: int = n["stability"]
	_stability.text = "Stability %+d" % st
	_stability.add_theme_color_override("font_color", UI.GOOD if st > 0 else (UI.BAD if st < 0 else UI.TEXT))
	_stability.tooltip_text = "Stability (-3 to +3). Each point: +5% tax and -1 unrest everywhere.\nClick for the court."
	_manpower.text = "Manpower %dk/%dk" % [int(n["manpower"] / 1000), int(int(n["max_manpower"]) / 1000)]
	_manpower.tooltip_text = "Soldiers available to recruit and reinforce. Refills over ten years.\nRegiments: %d of %d force limit\nClick for the military." % [
		Game.mil.regiment_count(tag), Game.mil.land_force_limit(tag)]
	var leg = float(n.get("legitimacy", 50.0))
	var lname: String = Game.court.legitimacy_name(tag)
	_legit.text = "%s %d" % ["Legit." if lname == "Legitimacy" else ("Trad." if lname.begins_with("Rep") else ("Devot." if lname == "Devotion" else "Cohes.")), int(leg)]
	_legit.add_theme_color_override("font_color", UI.BAD if leg < 50.0 else (UI.GOOD if leg >= 80.0 else UI.TEXT))
	_legit.tooltip_text = "%s %d (%+.1f a year). Low values cost power and stir unrest.\nClick for the court." % [lname, int(leg), Game.court.legitimacy_gain(tag)]
	var regs: int = Game.mil.regiment_count(tag)
	var fl: int = Game.mil.land_force_limit(tag)
	_regs.text = "Army %d/%d" % [regs, fl]
	_regs.add_theme_color_override("font_color", UI.BAD if regs > fl else UI.TEXT)
	_regs.tooltip_text = "Regiments / force limit. You can't recruit past the force limit (+50% in wartime).\nClick for production."
	var we = float(n["war_exhaustion"])
	_we.text = "War exh. %.1f" % we if we > 0.05 else ""
	_we.tooltip_text = "War exhaustion: +%.1f unrest in every province. Fades in peacetime." % (we * 0.5)
	var wars = Game.dip.wars_of(tag)
	_war.text = "AT WAR (%d)" % wars.size() if wars.size() > 0 else ""
	if wars.size() > 0:
		var lines: PackedStringArray = []
		for w in wars:
			lines.append("%s: war score %+d" % [w["name"], int(Game.dip.score_for(w, tag))])
		_war.tooltip_text = "\n".join(lines)
		_war.mouse_filter = Control.MOUSE_FILTER_PASS
