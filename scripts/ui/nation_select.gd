extends PanelContainer
## Country selector over the live map: every nation of the First World, with its ruler, government,
## peoples, strengths, national ideas and difficulty. Click a nation in the list or on the map.

signal nation_chosen(tag: String)
signal back_pressed
signal nation_focused(tag: String)

const UI = preload("res://scripts/ui/ui_util.gd")
const WIDTH := 430.0
const LIST_WIDTH := 230.0

var selected = "MEN"
var _list: VBoxContainer
var _detail: VBoxContainer
var _scroll: ScrollContainer
var _list_scroll: ScrollContainer


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.tex_box("panel.png", 12, 18, 16, true))
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	v.add_child(UI.heading("Choose your Nation", 24))
	v.add_child(UI.label("1 January 4289. The Arcadian Era begins. Click a nation below or on the map.", 13, UI.TEXT_DIM, LIST_WIDTH + WIDTH))
	var cols = HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	v.add_child(cols)
	_list_scroll = ScrollContainer.new()
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.custom_minimum_size = Vector2(LIST_WIDTH, 400)
	cols.add_child(_list_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_scroll.add_child(_list)
	cols.add_child(VSeparator.new())
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(WIDTH - 28, 400)
	cols.add_child(_scroll)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 6)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_detail)
	var buttons = HBoxContainer.new()
	buttons.add_child(UI.button("Back", func(): back_pressed.emit()))
	buttons.add_child(UI.spacer())
	var start = UI.button("Start the game", func(): nation_chosen.emit(selected))
	start.custom_minimum_size = Vector2(200, 40)
	start.add_theme_font_size_override("font_size", 17)
	start.add_theme_font_override("font", load("res://ui/style/tokens.gd").font("title"))
	buttons.add_child(start)
	v.add_child(buttons)
	visible = false


func fit_height(viewport_h: float) -> void:
	## Keep the whole panel (and the Start button) on screen whatever the window size.
	var h = clampf(viewport_h - 200.0, 160.0, 640.0)
	if absf(_scroll.custom_minimum_size.y - h) > 1.0:
		_scroll.custom_minimum_size.y = h
		_list_scroll.custom_minimum_size.y = h
		reset_size()


func open() -> void:
	visible = true
	refresh()


func pick(tag: String) -> void:
	if Game.nations.has(tag) and Game.nations[tag]["playable"] and Game.nations[tag]["alive"]:
		selected = tag
		refresh()
		nation_focused.emit(tag)


func refresh() -> void:
	UI.clear(_list)
	var tags: Array = Game.nations.keys()
	tags.sort_custom(func(a, b): return Game.nation_dev(a) > Game.nation_dev(b))
	for t in tags:
		var n: Dictionary = Game.nations[t]
		if not n["playable"] or not n["alive"]:
			continue
		var b = UI.button("", func(): pick(t))
		b.toggle_mode = true
		b.button_pressed = t == selected
		b.custom_minimum_size = Vector2(LIST_WIDTH - 14, 34)
		var row = HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 8
		row.offset_right = -8
		row.add_theme_constant_override("separation", 8)
		row.add_child(UI.swatch(n["colour"], Vector2(14, 20)))
		var nm = UI.label(n["short"], 15, UI.GOLD if t == selected else UI.TEXT)
		row.add_child(nm)
		row.add_child(UI.spacer())
		row.add_child(UI.label(n["difficulty"], 12, _diff_colour(n["difficulty"])))
		b.add_child(row)
		_list.add_child(b)
	_build_detail()


func _diff_colour(d: String) -> Color:
	match d:
		"Easy": return UI.GOOD
		"Normal": return UI.GOLD
		"Hard": return Color(0.95, 0.6, 0.3)
	return UI.BAD


func _build_detail() -> void:
	UI.clear(_detail)
	var n: Dictionary = Game.nations[selected]
	var w = WIDTH - 50
	_detail.add_child(UI.swatch(n["colour"], Vector2(w, 5)))
	_detail.add_child(UI.heading(n["name"], 20))
	var gov: Dictionary = Game.governments.get(n["government"], {})
	_detail.add_child(UI.label("%s (%s)" % [gov.get("name", ""), gov.get("rank", "")], 13, UI.TEXT_DIM))
	_detail.add_child(UI.label(n["blurb"], 13, UI.TEXT, w))
	_detail.add_child(UI.heading("Ruler"))
	_detail.add_child(UI.label(Game.court.describe(n["ruler"], n["power_names"]), 12, UI.TEXT, w))
	if not n["heir"].is_empty():
		_detail.add_child(UI.label("Heir: " + Game.court.describe(n["heir"], n["power_names"]), 12, UI.TEXT_DIM, w))
	_detail.add_child(UI.heading("Realm"))
	_detail.add_child(UI.kv("Provinces", "%d (%d development)" % [Game.owned(selected).size(), Game.nation_dev(selected)]))
	_detail.add_child(UI.kv("Capital", Game.provinces[Game.capital_of(selected)]["name"] if Game.capital_of(selected) >= 0 else "-"))
	_detail.add_child(UI.kv("Army", "%d regiments" % Game.mil.regiment_count(selected)))
	_detail.add_child(UI.kv("Fleet", "%d %s" % [Game.mil.ship_count(selected), "airships" if n["ethnicity"] in ["Human", "Angel"] else "ships"]))
	_detail.add_child(UI.kv("Treasury", "%d sanctum" % int(n["treasury"])))
	_detail.add_child(UI.kv("Technology", "%d / %d / %d" % [int(n["tech"][0]), int(n["tech"][1]), int(n["tech"][2])]))
	_detail.add_child(UI.kv("Power types", "%s / %s / %s" % n["power_names"]))
	_detail.add_child(UI.kv("Culture", "%s (%s)" % [n["culture"], Game.pop.culture_group(n["culture"])]))
	_detail.add_child(UI.kv("Faith", n["religion"]))
	_detail.add_child(UI.kv("People", n["ethnicity"]))
	var allies: PackedStringArray = []
	for a in Game.dip.allies_of(selected):
		allies.append(Game.nation_name(a))
	_detail.add_child(UI.kv("Allies", ", ".join(allies) if allies.size() > 0 else "none"))
	var natl: Dictionary = Game.idea_data["national"].get(n["ideas"], {})
	_detail.add_child(UI.heading(natl.get("name", "Ideas")))
	_detail.add_child(UI.label("Traditions:", 12, UI.TEXT_DIM))
	_detail.add_child(UI.mod_box(natl.get("traditions", {}), n["power_names"], w))
	var names: PackedStringArray = []
	for it in natl.get("ideas", []):
		names.append(it[0])
	_detail.add_child(UI.label("Ideas: " + ", ".join(names), 12, UI.TEXT, w))
	_detail.add_child(UI.heading("Things to know"))
	for t in _notes(selected):
		_detail.add_child(UI.label("- " + t, 12, UI.TEXT, w))


func _notes(tag: String) -> Array:
	match tag:
		"MEN":
			return ["The Black Moon can't touch you unless you land in Skyfall.",
				"Snowtusk boars hold the northeast of Mentos; Saltjaw, Driftboar and Coralsnout tribes hold the islands. Tribal Conquest gives you a reason to war with them.",
				"Allied with Skyfall. Exploring Skyfall annoys them: they forbid cameras."]
		"SKY":
			return ["Every leap year the Black Moon damages your islands, and time reverses the next day.",
				"Your people can't breathe the mainland air without masks: units there suffer, and you can't settle there until you have them.",
				"Your fleets are airships and stay among the sky islands. The Holy Waterfall is the only way down."]
		"BLM":
			return ["Skyfall wants you gone. A 12-year truce holds at the start: use it.",
				"Few troops and little sanctum, but your zealots fight harder than anyone.",
				"When entities seize the Doomsday Portal, your faith grows stronger."]
	if Game.pop.culture_group(Game.nations[tag]["culture"]) == "Porcine":
		return ["You broke away from the Holy Empire during the Incendium. Menslosia claims your land and wants it back.",
			"Find allies, build forts, and call your allies when war comes: they won't join on their own."]
	return ["A boar nation. The pigs of Menslosia want your land: find allies among the other boars.",
		"Hordes and tribes can raise Boar Raiders and reform their government over time."]
