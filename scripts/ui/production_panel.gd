extends "res://scripts/ui/panel_base.gd"
## Production (B): every province you own in one list, like EU4's macro-builder. Build buildings,
## raise regiments (including your nation's special regiments) and lay down ships without hunting
## for provinces on the map.

signal go_to_province(id: int)

var mode = "buildings"
var only_affordable = false


func setup() -> void:
	set_title("Production")
	panel_width = 600.0
	max_height = 640.0
	Game.month_ticked.connect(mark_dirty)
	Game.nation_changed.connect(func(t): if t == Game.player_tag: mark_dirty())


func _short(name: String) -> String:
	return name.split(" ")[0] if name.length() > 11 else name


func build() -> void:
	var tag: String = Game.player_tag
	var n: Dictionary = Game.nations[tag]
	var tabs := HBoxContainer.new()
	for m in [["buildings", "Buildings"], ["army", "Regiments"], ["navy", "Ships"], ["cores", "Cores"]]:
		var b = UI.button(m[1], func(): mode = m[0]; mark_dirty())
		b.add_theme_color_override("font_color", UI.GOLD if mode == m[0] else UI.TEXT)
		tabs.add_child(b)
	tabs.add_child(UI.spacer())
	var cb := CheckBox.new()
	cb.text = "Only what I can afford"
	cb.button_pressed = only_affordable
	cb.toggled.connect(func(on): only_affordable = on; mark_dirty())
	tabs.add_child(cb)
	add(tabs)
	var at_war: bool = Game.dip.at_war_any(tag)
	var fl: int = Game.mil.land_force_limit(tag)
	add(UI.row([UI.label("Treasury %s" % UI.money(float(n["treasury"])), 13, UI.GOLD),
		UI.label("Manpower %d" % int(n["manpower"]), 13),
		UI.tip_label("Regiments %d / %d" % [Game.mil.regiment_count(tag), fl],
			"Force limit: you can't raise regiments past it (+50% while at war). Grows with development and military tech.", 13,
			UI.BAD if Game.mil.regiment_count(tag) >= fl else UI.TEXT),
		UI.label("Ships %d / %d" % [Game.mil.ship_count(tag), Game.mil.naval_force_limit(tag)], 13)], 14))
	var ids: Array = Game.owned(tag)
	ids.sort_custom(func(a, b): return Game.total_dev(a) > Game.total_dev(b))
	match mode:
		"buildings": _buildings(tag, ids)
		"army": _army(tag, ids, at_war)
		"navy": _navy(tag, ids)
		"cores": _cores(tag, ids)


func _province_button(pid: int, extra: String = "") -> Button:
	var p: Dictionary = Game.provinces[pid]
	var b = UI.button("%s (%d)%s" % [p["name"], Game.total_dev(pid), extra], func(): go_to_province.emit(pid), "Show on the map")
	b.custom_minimum_size.x = 170
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	return b


func _buildings(tag: String, ids: Array) -> void:
	text("Each province has a few building slots. Costs are in sanctum; the button shows why if you can't build.", 11, UI.TEXT_DIM)
	for pid in ids:
		var p: Dictionary = Game.provinces[pid]
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 4)
		row.add_child(_province_button(pid, "  %d/%d" % [Game.eco.used_slots(pid), Game.eco.build_slots(pid)]))
		if not p["construction"].is_empty():
			row.add_child(UI.label("building %s..." % Game.building_data[p["construction"]["id"]]["name"], 12, UI.INFO))
		else:
			var any := false
			for bid in Game.building_data:
				if p["buildings"].has(bid):
					continue
				var why: String = Game.eco.can_build(tag, pid, bid)
				if why != "" and not why.begins_with("Needs %d" % Game.eco.building_cost(tag, bid)):
					continue
				if why != "" and only_affordable:
					continue
				var bd: Dictionary = Game.building_data[bid]
				var b = UI.action("%s %d" % [_short(bd["name"]), Game.eco.building_cost(tag, bid)], why,
					func(): Game.eco.build(tag, pid, bid); mark_dirty(), "%s\n%d months." % [bd.get("text", ""), Game.eco.building_months(tag, bid)])
				row.add_child(b)
				any = true
			if not any:
				row.add_child(UI.label("nothing to build", 11, UI.TEXT_DIM))
		add(row)


func _army(tag: String, ids: Array, at_war: bool) -> void:
	var types: Array = []
	for ut in Game.unit_data["land"]:
		var ud: Dictionary = Game.unit_data["land"][ut]
		if ud.has("nations") and not (tag in ud["nations"]):
			continue
		if ud.has("gov") and not (Game.court.gov_type(tag) in ud["gov"]):
			continue
		types.append(ut)
	var legend := VBoxContainer.new()
	for ut in types:
		var ud: Dictionary = Game.unit_data["land"][ut]
		var special := ud.has("nations") or ud.has("gov")
		legend.add_child(UI.tip_label("%s%s: %d sanctum, %.2f a month%s" % ["* " if special else "", Game.mil.unit_name(tag, ut), int(ud["cost"]), float(ud["maintenance"]),
			"" if Game.prog.land_unit_unlocked(tag, ut) else "  (needs mil tech %d)" % int(ud.get("tech", 1))],
			ud.get("text", ""), 12, UI.GOLD if special else UI.TEXT))
	add(legend)
	text("* special regiments only your nation can raise.", 11, UI.TEXT_DIM)
	for pid in ids:
		if Game.provinces[pid]["controller"] != tag:
			continue
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 4)
		row.add_child(_province_button(pid, "  mp %d" % int(Game.eco.province_manpower(pid))))
		for ut in types:
			var why: String = Game.mil.can_recruit(tag, pid, ut)
			if why.begins_with("Needs military tech"):
				continue
			if why != "" and only_affordable:
				continue
			row.add_child(UI.action(_short(Game.mil.unit_name(tag, ut)), why, func(): Game.mil.recruit(tag, pid, ut); mark_dirty()))
		add(row)


func _navy(tag: String, ids: Array) -> void:
	var any := false
	for pid in ids:
		if not Game.provinces[pid]["coastal"] or Game.provinces[pid]["controller"] != tag:
			continue
		any = true
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 4)
		row.add_child(_province_button(pid))
		for st in Game.unit_data["ships"]:
			var why: String = Game.mil.can_build_ship(tag, pid, st)
			if why != "" and only_affordable:
				continue
			var sd: Dictionary = Game.unit_data["ships"][st]
			row.add_child(UI.action("%s %d" % [_short(Game.mil.ship_name(tag, st)), int(sd["cost"])], why,
				func(): Game.mil.build_ship(tag, pid, st); mark_dirty()))
		add(row)
	if not any:
		text("You have no coastal provinces to build ships in.", 12, UI.TEXT_DIM)


func _cores(tag: String, ids: Array) -> void:
	var n: Dictionary = Game.nations[tag]
	var oe: float = Game.pop.overextension(tag)
	add(UI.kv("Overextension", "%d uncored development" % int(oe),
		"Uncored land pays a third of its taxes, sits at 50% autonomy or more, and every point of overextension adds unrest and costs relations.", UI.BAD if oe > 0.0 else UI.TEXT))
	text("Pay %s power and the province becomes a core after %d months. Occupied provinces can't be cored." % [n["power_names"][0], Game.pop.CORE_MONTHS], 11, UI.TEXT_DIM)
	var any := false
	for pid in ids:
		if Game.provinces[pid]["cores"].has(tag):
			continue
		any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(_province_button(pid))
		var left: int = Game.pop.coring_left(pid)
		if left >= 0:
			row.add_child(UI.bar(float(Game.pop.CORE_MONTHS - left), float(Game.pop.CORE_MONTHS), 150.0, UI.INFO))
			row.add_child(UI.label("%d month(s) left" % left, 12, UI.INFO))
		else:
			row.add_child(UI.action("Make core (%d %s)" % [Game.pop.core_cost(tag, pid), n["power_names"][0]], Game.pop.can_core(tag, pid),
				func(): Game.pop.make_core(tag, pid); mark_dirty()))
		add(row)
	if not any:
		text("Every province you own is a core.", 12, UI.GOOD)
