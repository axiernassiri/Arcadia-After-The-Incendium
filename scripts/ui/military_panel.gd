extends "res://scripts/ui/panel_base.gd"
## Military overview: force limits, armies, fleets, generals and units in training.

signal army_selected(id: int)
signal fleet_selected(id: int)


func setup() -> void:
	set_title("Military")
	panel_width = 430.0
	Game.month_ticked.connect(mark_dirty)
	Game.armies_changed.connect(mark_dirty)
	Game.nation_changed.connect(func(t): if t == Game.player_tag: mark_dirty())


func build() -> void:
	var tag = Game.player_tag
	var n: Dictionary = Game.nations[tag]
	text("Select a province you own to recruit there. Click an army on the map to select it, then right-click a province to move.", 12, UI.TEXT_DIM)
	add(UI.kv("Regiments", "%d / %d force limit" % [Game.mil.regiment_count(tag), Game.mil.land_force_limit(tag)],
		"Going over the force limit makes every regiment cost more."))
	add(UI.kv("Ships", "%d / %d force limit" % [Game.mil.ship_count(tag), Game.mil.naval_force_limit(tag)]))
	add(UI.kv("Transport capacity", "%d regiments" % Game.mil.transport_capacity(tag), "Armies can cross a sea lane when your fleets can carry all their regiments."))
	add(UI.kv("Manpower", "%d / %d" % [int(n["manpower"]), int(n["max_manpower"])]))
	add(UI.kv("Maximum morale", "%.2f" % Game.mil.max_morale(tag), "2.5 x (1 + morale modifiers), lowered by low maintenance.\n" + Game.mods.breakdown(tag, ["land_morale"])))
	add(UI.kv("Discipline", "%+d%%" % int(Game.mods.nat(tag, "discipline") * 100), "Every regiment deals and takes damage by this much.\n" + Game.mods.breakdown(tag, ["discipline"])))
	add(UI.kv("Land units", Game.prog.unit_tier_name(tag)))
	section("Armies")
	var armies: Array = Game.mil.armies_of(tag)
	if armies.is_empty():
		text("No armies.", 12, UI.TEXT_DIM)
	for a in armies:
		var men: float = Game.mil.army_men(a)
		var where: String = Game.provinces[int(a["location"])]["name"]
		var status = ""
		if a["in_battle"]:
			status = " - IN BATTLE"
		elif a["retreating"]:
			status = " - retreating"
		elif not a["path"].is_empty():
			status = " - to %s" % Game.provinces[int(a["path"][a["path"].size() - 1])]["name"]
		var l: Dictionary = Game.mil.army_leader(a)
		var b = UI.button("%s: %d regiments, %.1fk men at %s%s%s" % [a["name"], a["regiments"].size(), men / 1000.0, where, status,
			("\n   led by %s" % l["name"]) if not l.is_empty() else ""], func(): army_selected.emit(int(a["id"])))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.x = panel_width - 40
		add(b)
	section("Fleets")
	var fleets: Array = Game.mil.fleets_of(tag)
	if fleets.is_empty():
		text("No fleets.", 12, UI.TEXT_DIM)
	for f in fleets:
		var counts = {}
		for s in f["ships"]:
			counts[s["type"]] = int(counts.get(s["type"], 0)) + 1
		var parts: PackedStringArray = []
		for k in counts:
			parts.append("%d %s" % [counts[k], Game.mil.ship_name(tag, k)])
		var b2 = UI.button("%s at %s: %s" % [f["name"], Game.provinces[int(f["location"])]["name"], ", ".join(parts)], func(): fleet_selected.emit(int(f["id"])))
		b2.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b2.custom_minimum_size.x = panel_width - 40
		add(b2)
	section("Generals")
	for l in n["leaders"]:
		var army_name = "unassigned"
		if int(l["army"]) >= 0 and Game.armies.has(int(l["army"])):
			army_name = Game.armies[int(l["army"])]["name"]
		add(UI.kv(l["name"], "fire %d  shock %d  manoeuvre %d  siege %d" % [int(l["fire"]), int(l["shock"]), int(l["maneuver"]), int(l["siege"])],
			"Leading: %s" % army_name))
	add(UI.action("Recruit a general (%d %s)" % [Game.mil.leader_cost(), n["power_names"][2]], Game.mil.can_recruit_leader(tag),
		func(): Game.act("mil.recruit_leader", [tag]); mark_dirty(), "Better generals come with more army tradition."))
	var queue: Array = []
	for q in Game.recruit_queue:
		if q["tag"] == tag:
			queue.append(q)
	if queue.size() > 0:
		section("In training")
		for q in queue:
			var nm: String = Game.mil.unit_name(tag, q["type"]) if q["kind"] == "land" else Game.mil.ship_name(tag, q["type"])
			add(UI.kv("%s in %s" % [nm, Game.provinces[int(q["pid"])]["name"]], "%d days" % maxi(0, int(q["done"]) - Game.day_index)))
