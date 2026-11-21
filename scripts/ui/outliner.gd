extends PanelContainer
## EU4-style outliner on the right edge: your wars, armies, fleets, sieges, buildings under
## construction, recruitment and colonies at a glance. Click a row to jump there. The header
## collapses it; main.gd hides it while a right-hand window (province, army...) is open.

signal army_clicked(id: int)
signal fleet_clicked(id: int)
signal province_clicked(id: int)
signal war_clicked(id: int)

const UI = preload("res://scripts/ui/ui_util.gd")
const Tokens = preload("res://ui/style/tokens.gd")
const WIDTH := 262.0
var max_h := 560.0   # set by main.gd so it stays clear of the army window

var collapsed = false
var _body: VBoxContainer
var _scroll: ScrollContainer
var _head: Button
var _dirty = true
var _t = 1.0   # build on the first frame


func _ready() -> void:
	custom_minimum_size.x = WIDTH
	theme_type_variation = "InkPanel"
	self_modulate = Color(1, 1, 1, 0.92)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	add_child(outer)
	_head = UI.button("", func(): collapsed = not collapsed; _dirty = true, "Show or hide the outliner")
	_head.theme_type_variation = "FlatButton"
	_head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_head.add_theme_font_override("font", Tokens.font("title"))
	_head.add_theme_font_size_override("font_size", 14)
	outer.add_child(_head)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 1)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	for s in [Game.armies_changed, Game.month_ticked, Game.war_changed, Game.date_changed]:
		s.connect(func(): _dirty = true)


func _process(delta: float) -> void:
	_t += delta
	if visible and _dirty and _t > 0.4 and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		refresh()


func refresh() -> void:
	_dirty = false
	_t = 0.0
	_head.text = ("▸  " if collapsed else "▾  ") + "Outliner"
	UI.clear(_body)
	_scroll.visible = not collapsed
	if collapsed or Game.player_tag == "" or not Game.nations.has(Game.player_tag):
		_scroll.custom_minimum_size.y = 0
		reset_size()
		return
	var tag: String = Game.player_tag

	var wars: Array = Game.dip.wars_of(tag)
	if wars.size() > 0:
		_section("Wars", "swords")
		for w in wars:
			var sc: float = Game.dip.score_for(w, tag)
			_row(String(w["name"]), "%+d%%" % int(sc), UI.GOOD if sc > 0 else (UI.BAD if sc < 0 else UI.TEXT_DIM),
				func(): war_clicked.emit(int(w["id"])), "War score %+d%%. Click for the peace screen." % int(sc))

	var armies: Array = Game.mil.armies_of(tag)
	_section("Armies (%d)" % armies.size(), "helmet")
	for a in armies:
		var where: String = Game.provinces[int(a["location"])]["name"]
		var col: Color = UI.TEXT
		var state := where
		if a.get("in_battle", false):
			state = "fighting at " + where
			col = UI.BAD
		elif a.get("retreating", false):
			state = "retreating"
			col = UI.WARN
		elif not a["path"].is_empty():
			state = "→ " + String(Game.provinces[int(a["path"][a["path"].size() - 1])]["name"])
			col = UI.INFO
		elif not Game.provinces[int(a["location"])]["siege"].is_empty() and Game.provinces[int(a["location"])]["siege"].get("tag", "") == tag:
			state = "besieging " + where
			col = UI.WARN
		var morale := 0.0
		for r in a["regiments"]:
			morale += float(r.get("morale", 0.0))
		var max_m := maxf(0.01, Game.mil.max_morale(tag) * a["regiments"].size())
		var tip := "%s: %d regiments, %.1fk men, morale %d%%\n%s\nClick to select" % [a["name"], a["regiments"].size(),
			Game.mil.army_men(a) / 1000.0, int(100.0 * morale / max_m), state]
		_row("%.1fk  %s" % [Game.mil.army_men(a) / 1000.0, _short(String(a["name"]))], state, col, func(): army_clicked.emit(int(a["id"])), tip)

	var fleets: Array = Game.mil.fleets_of(tag)
	if fleets.size() > 0:
		_section("Fleets (%d)" % fleets.size(), "anchor")
		for f in fleets:
			var where: String = Game.provinces[int(f["location"])]["name"]
			var state := where if f["path"].is_empty() else "→ " + String(Game.provinces[int(f["path"][f["path"].size() - 1])]["name"])
			_row("%d ships  %s" % [f["ships"].size(), _short(String(f["name"]))], state, UI.TEXT if f["path"].is_empty() else UI.INFO,
				func(): fleet_clicked.emit(int(f["id"])), "%s at %s. Click to select." % [f["name"], where])

	var sieges: Array = []
	for pid in Game.provinces:
		var p: Dictionary = Game.provinces[pid]
		if not p["siege"].is_empty() and (p["siege"].get("tag", "") == tag or p["owner"] == tag):
			sieges.append(pid)
	if sieges.size() > 0:
		_section("Sieges", "fort")
		for pid in sieges:
			var p: Dictionary = Game.provinces[pid]
			var ours: bool = p["siege"].get("tag", "") == tag
			_row(String(p["name"]), "%d%%" % int(p["siege"].get("progress", 0)), UI.GOOD if ours else UI.BAD,
				func(): province_clicked.emit(int(pid)), ("We are besieging %s." if ours else "%s is under siege!") % p["name"])

	var builds: Array = []
	var colonies: Array = []
	for pid in Game.owned(tag):
		if not Game.provinces[pid]["construction"].is_empty():
			builds.append(pid)
	for pid in Game.provinces:
		if Game.provinces[pid]["colony"].get("tag", "") == tag:
			colonies.append(pid)
	if builds.size() > 0:
		_section("Construction (%d)" % builds.size(), "hammer")
		for pid in builds:
			var c: Dictionary = Game.provinces[pid]["construction"]
			var days := maxi(0, int(c.get("done", 0)) - Game.day_index)
			_row(String(Game.building_data.get(c["id"], {}).get("name", c["id"])), "%s, %dd" % [Game.provinces[pid]["name"], days], UI.TEXT_DIM,
				func(): province_clicked.emit(int(pid)), "Done in %d days." % days)
	var queue: Array = []
	for q in Game.recruit_queue:
		if q["tag"] == tag:
			queue.append(q)
	if queue.size() > 0:
		_section("Recruiting (%d)" % queue.size(), "person")
		for q in queue:
			var nm: String = Game.mil.unit_name(tag, q["type"]) if q["kind"] == "land" else Game.mil.ship_name(tag, q["type"])
			var days := maxi(0, int(q["done"]) - Game.day_index)
			_row(nm, "%s, %dd" % [Game.provinces[int(q["pid"])]["name"], days], UI.TEXT_DIM,
				func(): province_clicked.emit(int(q["pid"])), "Ready in %d days." % days)
	if colonies.size() > 0:
		_section("Colonies", "flag")
		for pid in colonies:
			_row(String(Game.provinces[pid]["name"]), "%d settlers" % int(Game.provinces[pid]["colony"].get("settlers", 0)), UI.TEXT_DIM,
				func(): province_clicked.emit(int(pid)), "Colony growing.")

	await get_tree().process_frame
	if is_instance_valid(_body):
		_scroll.custom_minimum_size.y = minf(_body.get_combined_minimum_size().y + 2.0, max_h)
		reset_size()


func _short(s: String) -> String:
	return s if s.length() <= 18 else s.substr(0, 17) + "…"


func _section(title: String, icon_name: String) -> void:
	var h = UI.row([UI.icon(icon_name, 13, UI.GOLD), UI.label(title, 12, UI.GOLD)], 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _body.get_child_count() > 0:
		var gap = Control.new()
		gap.custom_minimum_size.y = 4
		_body.add_child(gap)
	_body.add_child(h)


func _row(left: String, right: String, right_col: Color, cb: Callable, tip: String) -> void:
	var b = UI.button("", cb, tip)
	b.theme_type_variation = "FlatButton"
	b.custom_minimum_size = Vector2(WIDTH - 24, 22)
	var h = HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 6
	h.offset_right = -6
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l = UI.label(left, 12, UI.TEXT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	l.custom_minimum_size.x = 40
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var r = UI.label(right, 12, right_col)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r.size_flags_horizontal = Control.SIZE_SHRINK_END
	h.add_child(l)
	h.add_child(r)
	b.add_child(h)
	_body.add_child(b)
