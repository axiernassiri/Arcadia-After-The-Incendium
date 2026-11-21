extends "res://scripts/ui/panel_base.gd"
## Details and actions for the selected province: development, buildings, recruiting, unrest,
## cores, culture and faith, colonies and exploration.

signal go_to_province(id: int)
signal country_clicked(tag: String)
signal army_clicked(id: int)

const FLAG_NOTES := {
	"capital": "Capital of the nation.",
	"doomsday_portal": "The Doomsday Portal. Its barrier falls every leap year on 29 February, when the Black Moon rises.",
	"core": "The Core: it keeps Skyfall aloft and powers Skyfallin society.",
	"waterfall_top": "The Holy Waterfall of Eden: the only way between Skyfall and the mainland.",
	"waterfall_base": "Where the Holy Waterfall of Eden reaches the mainland.",
	"unity_base": "Unity: Menslosia's military island, guarding both nations against entities.",
	"staircase": "A Staircase to Nowhere. Those who go down end up in the Backrooms, and never come back up.",
	"mist": "The Center of Midrea, hidden behind the White Haze. Light scatters through the clouds here.",
	"hidden": "Hidden behind the White Haze. Satellites can't see past these mountains.",
	"observatory": "Menslosia's Space Observatory.",
	"volcano": "A volcano. Yellowstone fuelled the Incendium and now lies dormant.",
}

var province = -1


func setup() -> void:
	set_title("Province")
	panel_width = 360.0
	max_height = 640.0
	Game.province_changed.connect(func(id): if id == province: mark_dirty())
	Game.nation_changed.connect(func(_t): mark_dirty())
	Game.month_ticked.connect(mark_dirty)
	Game.armies_changed.connect(mark_dirty)


func show_province(id: int) -> void:
	province = id
	visible = id > 0
	if visible:
		refresh_now()


func build() -> void:
	if province <= 0 or not Game.provinces.has(province):
		visible = false
		return
	var p: Dictionary = Game.provinces[province]
	var tag = Game.player_tag
	var n: Dictionary = Game.player()
	set_title(p["name"])
	var where = "%s · %s · %s trade node" % [p["region"], "Skyfall" if p["layer"] == "sky" else "Mainland", p["trade_node"]]
	text(where, 12, UI.TEXT_DIM)
	var explored: bool = Game.is_explored_by_player(province)
	if not explored:
		text("Unexplored. Your maps show nothing but mist here.", 13)
		add(UI.action("Explore (%d %s)" % [Game.explore_cost(tag, province), n["power_names"][1]], Game.can_explore(tag, province),
			func(): Game.explore(tag, province)))
		_links(p)
		return
	var owner: String = p["owner"]
	if owner != "":
		var on: Dictionary = Game.nations[owner]
		var ob = UI.button(on["name"], func(): country_clicked.emit(owner), "Open their diplomacy (or right-click their land)")
		add(UI.row([UI.swatch(on["colour"]), ob]))
		if p["controller"] != owner:
			add(UI.label("Occupied by %s" % Game.nation_name(p["controller"]), 13, UI.BAD))
		var cores: PackedStringArray = []
		for c in p["cores"]:
			cores.append(Game.nation_name(c))
		text("Cores: %s" % (", ".join(cores) if cores.size() > 0 else "none"), 11, UI.TEXT_DIM)
	else:
		add(UI.row([UI.swatch(Game.unowned_colour), UI.label("Uninhabited land", 14)]))
	var terr: Dictionary = Game.terrain_data.get(p["terrain"], {})
	add(UI.kv("Terrain", terr.get("name", p["terrain"]), "Development cost %+d%%, defender +%d, supply %d, %d building slots" % [
		int(float(terr.get("dev_cost", 0)) * 100), int(terr.get("defence", 0)), int(terr.get("supply", 5)), int(terr.get("build_slots", 2))]))
	add(UI.kv("Trade goods", "%s (price %.2f)" % [Game.goods.get(p["goods"], {}).get("name", p["goods"]), Game.eco.price(p["goods"])]))
	if p["culture"] != "":
		var bad_c: bool = owner != "" and not Game.pop.culture_accepted(owner, p["culture"])
		add(UI.kv("Culture", p["culture"], "", UI.BAD if bad_c else UI.TEXT))
		add(UI.kv("Faith", p["religion"], "", UI.BAD if owner != "" and p["religion"] != Game.nations[owner]["religion"] else UI.TEXT))
		add(UI.kv("People", p["ethnicity"]))

	# development
	section("Development %d" % Game.total_dev(province))
	var mine: bool = owner == tag
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	var cost: int = Game.eco.develop_cost(tag, province) if mine else 0
	for k in 3:
		grid.add_child(UI.label(Game.DEV_KINDS[k].capitalize(), 14))
		grid.add_child(UI.label(str(p["dev"][k]), 16, UI.GOLD))
		if mine:
			var power_name: String = n["power_names"][k]
			var why: String = Game.eco.can_develop(tag, province, k)
			var b = UI.action("+1  (%d %s)" % [cost, power_name], why, func(): Game.eco.develop(tag, province, k),
				"Spend %d %s power.\n%s" % [cost, power_name, Game.eco.dev_cost_breakdown(tag, province)])
			grid.add_child(b)
		else:
			grid.add_child(Control.new())
	add(grid)
	if owner != "":
		add(UI.kv("Tax / production a year", "%.1f / %.1f" % [Game.eco.province_tax(province), Game.eco.province_production(province)]))
		add(UI.kv("Manpower a year", "%d" % int(Game.eco.province_manpower(province))))
		add(UI.kv("Trade power", "%.1f" % Game.trade.province_trade_power(province)))

	# unrest and rebels
	if owner != "":
		var u = float(p.get("unrest", 0.0))
		var lines: PackedStringArray = []
		for r in Game.pop.unrest_breakdown(province):
			lines.append("%s: %+.1f" % [r[0], float(r[1])])
		add(UI.tip_label("Unrest %+.1f" % u, "\n".join(lines) if lines.size() > 0 else "No causes.", 14, UI.BAD if u > 0 else UI.GOOD))
		if float(p["rebel_progress"]) > 0.0:
			add(UI.row([UI.label("Rebels organising", 12, UI.BAD), UI.bar(float(p["rebel_progress"]), 100.0, 140.0, UI.BAD)]))
			if mine:
				add(UI.action("Harsh treatment (%d %s)" % [Game.pop.harsh_cost(province), n["power_names"][2]], Game.pop.can_harsh(tag, province),
					func(): Game.pop.harsh_treatment(tag, province)))
	if mine:
		if not p["cores"].has(tag):
			add(UI.action("Make core (%d %s)" % [Game.pop.core_cost(tag, province), n["power_names"][0]], Game.pop.can_core(tag, province),
				func(): Game.pop.make_core(tag, province), "Uncored provinces pay a third of their taxes and cause overextension."))
		if p["culture"] != n["culture"]:
			add(UI.action("Convert culture (%d %s)" % [Game.pop.culture_convert_cost(tag, province), n["power_names"][1]],
				Game.pop.can_convert_culture(tag, province), func(): Game.pop.convert_culture(tag, province)))
		if p["religion"] != n["religion"] and p["religion"] != "":
			if p["conversion"].get("tag", "") == tag:
				add(UI.row([UI.label("Missionary at work", 12, UI.INFO), UI.bar(float(p["conversion"]["progress"]), 100.0, 140.0, UI.INFO)]))
			else:
				add(UI.action("Send missionary", Game.pop.can_start_conversion(tag, province), func(): Game.pop.start_conversion(tag, province)))

	# buildings
	if owner != "":
		section("Buildings (%d / %d slots)" % [Game.eco.used_slots(province), Game.eco.build_slots(province)])
		for bid in p["buildings"]:
			add(UI.kv(Game.building_data[bid]["name"], "built", Game.building_data[bid].get("text", ""), UI.GOOD))
		if not p["construction"].is_empty():
			var c: Dictionary = p["construction"]
			var total = float(int(c["done"]) - int(c.get("start", Game.day_index)))
			var done = float(Game.day_index - int(c.get("start", Game.day_index)))
			add(UI.row([UI.label("Building %s" % Game.building_data[c["id"]]["name"], 12, UI.INFO), UI.bar(done, maxf(total, 1.0), 120.0, UI.INFO)]))
			if mine:
				add(UI.button("Cancel (refund half)", func(): Game.eco.cancel_build(tag, province)))
		if mine and p["construction"].is_empty():
			for bid in Game.building_data:
				if p["buildings"].has(bid):
					continue
				var why: String = Game.eco.can_build(tag, province, bid)
				if why.begins_with("Needs a coastal") or why.begins_with("Needs adm tech") and false:
					continue
				var bd: Dictionary = Game.building_data[bid]
				var b = UI.action("Build %s (%d)" % [bd["name"], Game.eco.building_cost(tag, bid)], why,
					func(): Game.eco.build(tag, province, bid),
					"%s\n%d months." % [bd.get("text", ""), Game.eco.building_months(tag, bid)])
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				add(b)

	# military
	if mine and p["controller"] == tag:
		section("Recruit")
		var rr = HBoxContainer.new()
		for ut in ["inf", "cav", "art"]:
			var ud: Dictionary = Game.unit_data["land"][ut]
			rr.add_child(UI.action("%s (%d)" % [Game.mil.unit_name(tag, ut), int(ud["cost"])], Game.mil.can_recruit(tag, province, ut),
				func(): Game.mil.recruit(tag, province, ut), "1,000 men, %d sanctum, %.2f a month upkeep, %d month(s) to train." % [
					int(ud["cost"]), float(ud["maintenance"]), int(ud.get("months", 1))]))
		add(rr)
		if p["coastal"]:
			var sr = HBoxContainer.new()
			for st in ["light", "heavy", "transport"]:
				var sd: Dictionary = Game.unit_data["ships"][st]
				sr.add_child(UI.action("%s (%d)" % [Game.mil.ship_name(tag, st), int(sd["cost"])], Game.mil.can_build_ship(tag, province, st),
					func(): Game.mil.build_ship(tag, province, st), "Guns %.1f, carries %d regiments, %.0f trade power." % [
						float(sd["guns"]), int(sd["capacity"]), float(sd["trade"])]))
			add(sr)
	var here: Array = Game.mil.armies_at(province)
	if here.size() > 0:
		section("Armies here")
		for a in here:
			if a["owner"] != tag and not Game.is_explored_by_player(province):
				continue
			add(UI.button("%s (%s): %d regiments" % [a["name"], Game.nation_name(a["owner"]), a["regiments"].size()],
				func(): army_clicked.emit(int(a["id"]))))
	if not p["siege"].is_empty():
		add(UI.row([UI.label("Siege by %s" % Game.nation_name(p["siege"]["tag"]), 12, UI.BAD),
			UI.bar(float(p["siege"]["progress"]), 100.0, 120.0, UI.GOLD)]))
	add(UI.kv("Fort level", str(Game.eco.fort_level(province))))

	# colonisation
	if owner == "":
		section("Colonisation")
		if not p["colony"].is_empty():
			add(UI.row([UI.label("%s colonists" % Game.nation_name(p["colony"]["tag"]), 12, UI.INFO),
				UI.bar(float(p["colony"]["settlers"]), 1000.0, 140.0, UI.INFO)]))
		else:
			add(UI.action("Send colonists (%d sanctum)" % int(Game.eco.COLONY_COST), Game.eco.can_colonize(tag, province),
				func(): Game.eco.colonize(tag, province), "Settlers grow each month; at 1,000 the colony becomes your province."))

	var notes: PackedStringArray = []
	for f in p["flags"]:
		if FLAG_NOTES.has(f) and not (f == "hidden" and not "mist" in p["flags"]):
			notes.append(FLAG_NOTES[f])
	if Game.doomsday_active and "doomsday_portal" in p["flags"]:
		notes.append("The barrier is DOWN. Anomalies are pouring out.")
	for m in p["modifiers"]:
		notes.append("%s: %s" % [m.get("name", ""), Game.mods.describe(m.get("mods", {}))])
	if notes.size() > 0:
		section("Notes")
		for t in notes:
			text(t, 12, UI.DOOM if "Doomsday" in t or "DOWN" in t else UI.TEXT)
	_links(p)


func _links(p: Dictionary) -> void:
	for nb in p["connections"]:
		if p["connections"][nb] == "waterfall":
			var up: bool = Game.provinces[nb]["layer"] == "sky"
			add(UI.button("Climb the Holy Waterfall to Skyfall" if up else "Descend the waterfall to the mainland",
				func(): go_to_province.emit(nb)))
	var names: PackedStringArray = []
	for nb in p["connections"]:
		var via: String = p["connections"][nb]
		var nm: String = Game.provinces[nb]["name"] if Game.is_explored_by_player(nb) else "unexplored"
		names.append(nm + ("" if via == "land" else " (%s)" % via))
	text("Borders: " + ", ".join(names), 11, UI.TEXT_DIM)
