extends "res://scripts/ui/panel_base.gd"
## The selected army or fleet: regiments, morale, general, orders.

signal deselected
signal group_changed(ids: Array)   # ask main.gd to change the selection (e.g. one army out of a group)

var army = -1
var fleet = -1
var group: Array = []   # several of your armies selected at once (shift-click or shift-drag)


func setup() -> void:
	set_title("Army")
	panel_width = 340.0
	max_height = 420.0
	Game.armies_changed.connect(mark_dirty)
	Game.date_changed.connect(mark_dirty)


func show_army(id: int) -> void:
	group = []
	army = id
	fleet = -1
	visible = id >= 0
	if visible:
		refresh_now()


func show_fleet(id: int) -> void:
	group = []
	fleet = id
	army = -1
	visible = id >= 0
	if visible:
		refresh_now()


func close() -> void:
	group = []
	army = -1
	fleet = -1
	super.close()
	deselected.emit()


func build() -> void:
	group = group.filter(func(x): return Game.armies.has(x))
	if group.size() > 1:
		_build_group()
	elif army >= 0:
		_build_army()
	elif fleet >= 0:
		_build_fleet()


func _build_army() -> void:
	var a: Dictionary = Game.armies.get(army, {})
	if a.is_empty():
		text("This army is gone.", 13, UI.TEXT_DIM)
		return
	var tag: String = a["owner"]
	var mine: bool = tag == Game.player_tag
	set_title(a["name"])
	var owner_col: Color = Game.owner_colour(tag)
	add(UI.row([UI.swatch(owner_col), UI.label(Game.nation_name(tag), 14, UI.GOLD)]))
	if tag == "ENT":
		text("Things from beyond the Doomsday Portal. They answer to no one, fight anyone in Skyfall except VAGA, and slowly fade away (2% of their number a month).", 12, UI.DOOM)
	if tag == "REB":
		var rb: Dictionary = a["rebel"]
		text("%s rising against %s from %s." % [Game.peoples.get("rebels", {}).get(rb.get("type", ""), {}).get("name", "Rebels"),
			Game.nation_name(rb.get("target", "")), rb.get("home_name", "")], 12, UI.BAD)
		text(Game.peoples.get("rebels", {}).get(rb.get("type", ""), {}).get("text", ""), 11, UI.TEXT_DIM)
	var loc: Dictionary = Game.provinces[int(a["location"])]
	var where = "At %s" % loc["name"]
	if a["in_battle"]:
		where += ", in battle!"
	elif a["retreating"]:
		where += ", retreating"
	elif not a["path"].is_empty():
		var dest: Dictionary = Game.provinces[int(a["path"][a["path"].size() - 1])]
		where += ", marching to %s (%d step(s))" % [dest["name"], a["path"].size()]
	text(where, 13)
	if not loc["siege"].is_empty() and loc["siege"]["tag"] == tag:
		add(UI.row([UI.label("Siege of %s" % loc["name"], 12), UI.bar(float(loc["siege"]["progress"]), 100.0, 140.0, UI.GOLD)]))
	var counts = {}
	var men = 0.0
	var morale = 0.0
	for r in a["regiments"]:
		counts[r["type"]] = int(counts.get(r["type"], 0)) + 1
		men += float(r["men"])
		morale += float(r["morale"])
	var mm: float = Game.mil.max_morale(tag)
	morale /= maxf(1.0, float(a["regiments"].size()))
	section("%d regiments, %d men" % [a["regiments"].size(), int(men)])
	for k in counts:
		add(UI.kv(Game.mil.unit_name(tag, k), str(counts[k])))
	add(UI.row([UI.label("Morale %.2f / %.2f" % [morale, mm], 12), UI.bar(morale, mm, 140.0, UI.GOOD)]))
	add(UI.row([UI.label("Strength", 12), UI.bar(men, a["regiments"].size() * 1000.0, 140.0, UI.GOLD)]))
	add(UI.kv("Combat value", "%.1f" % Game.mil.army_strength(a)))
	var l: Dictionary = Game.mil.army_leader(a)
	if not l.is_empty():
		add(UI.kv("General", "%s (%d/%d/%d/%d)" % [l["name"], int(l["fire"]), int(l["shock"]), int(l["maneuver"]), int(l["siege"])],
			"Fire / shock / manoeuvre / siege pips"))
	if not mine:
		return
	section("Orders")
	text("Right-click a province to march there. Armies need enough transport ships to cross the sea.", 11, UI.TEXT_DIM)
	var ob = OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.add_item("No general", -1)
	var sel = 0
	var i = 1
	for ld in Game.nations[tag]["leaders"]:
		if ld["kind"] != "general":
			continue
		var busy = int(ld["army"]) >= 0 and int(ld["army"]) != army and Game.armies.has(int(ld["army"]))
		ob.add_item("%s (%d/%d/%d/%d)%s" % [ld["name"], int(ld["fire"]), int(ld["shock"]), int(ld["maneuver"]), int(ld["siege"]), " - busy" if busy else ""], int(ld["id"]))
		if int(ld["id"]) == int(a["leader"]):
			sel = i
		i += 1
	ob.select(sel)
	ob.item_selected.connect(func(idx): Game.mil.assign_leader(army, ob.get_item_id(idx)))
	add(UI.row([UI.label("General:", 13), ob]))
	var row = HBoxContainer.new()
	row.add_child(UI.action("Stop", "" if not a["path"].is_empty() and not a["retreating"] else "Not moving.", func(): a["path"] = []; Game.armies_changed.emit()))
	row.add_child(UI.action("Split", "" if a["regiments"].size() >= 2 and not a["in_battle"] else "Needs 2 regiments, not in battle.",
		func(): Game.mil.split_army(army)))
	var others: Array = []
	for x in Game.mil.armies_at(int(a["location"])):
		if x["owner"] == tag and int(x["id"]) != army and not x["in_battle"]:
			others.append(int(x["id"]))
	row.add_child(UI.action("Merge", "" if others.size() > 0 and not a["in_battle"] else "No other army of yours here.",
		func(): Game.mil.merge_armies([army] + others)))
	row.add_child(UI.action("Disband", "" if not a["in_battle"] else "In battle.", func(): Game.mil.disband_army(army); close()))
	add(row)


func _build_fleet() -> void:
	var f: Dictionary = Game.fleets.get(fleet, {})
	if f.is_empty():
		text("This fleet is gone.", 13, UI.TEXT_DIM)
		return
	var tag: String = f["owner"]
	set_title(f["name"])
	add(UI.row([UI.swatch(Game.owner_colour(tag)), UI.label(Game.nation_name(tag), 14, UI.GOLD)]))
	var where = "At %s" % Game.provinces[int(f["location"])]["name"]
	if not f["path"].is_empty():
		where += ", sailing to %s" % Game.provinces[int(f["path"][f["path"].size() - 1])]["name"]
	text(where, 13)
	var counts = {}
	var hull = 0.0
	var hull_max = 0.0
	for s in f["ships"]:
		counts[s["type"]] = int(counts.get(s["type"], 0)) + 1
		hull += float(s["hull"])
		hull_max += float(Game.unit_data["ships"].get(s["type"], {}).get("hull", 1.0))
	section("%d ships" % f["ships"].size())
	for k in counts:
		add(UI.kv(Game.mil.ship_name(tag, k), str(counts[k])))
	add(UI.row([UI.label("Hulls", 12), UI.bar(hull, hull_max, 140.0, UI.INFO)]))
	text("Light ships add trade power in the node they sit in. Enemy coasts with your fleet are blockaded.", 11, UI.TEXT_DIM)
	if tag != Game.player_tag:
		return
	section("Orders")
	text("Right-click a coastal province to sail there.%s" % (" Airships stay among the sky islands." if f.get("sky", false) else ""), 11, UI.TEXT_DIM)
	var row = HBoxContainer.new()
	row.add_child(UI.action("Stop", "" if not f["path"].is_empty() else "Not moving.", func(): f["path"] = []; Game.armies_changed.emit()))
	row.add_child(UI.button("Disband", func(): Game.mil.disband_fleet(fleet); close()))
	add(row)


func show_group(ids: Array) -> void:
	group = ids.duplicate()
	army = int(ids[0]) if ids.size() > 0 else -1
	fleet = -1
	visible = ids.size() > 0
	if visible:
		refresh_now()


func _build_group() -> void:
	## Several armies selected: totals, one row each, and orders for all of them (EU4's multi-select).
	set_title("%d armies selected" % group.size())
	var men := 0.0
	var regs := 0
	var where := {}
	var fighting := false
	for id in group:
		var a: Dictionary = Game.armies[id]
		men += Game.mil.army_men(a)
		regs += a["regiments"].size()
		where[int(a["location"])] = true
		fighting = fighting or a["in_battle"]
	text("%d regiments, %.1fk men. Right-click a province to send them all there." % [regs, men / 1000.0], 13)
	section("Armies")
	for id in group:
		var a: Dictionary = Game.armies[id]
		var loc: String = Game.provinces[int(a["location"])]["name"]
		var b = UI.button("%s: %.1fk at %s" % [a["name"], Game.mil.army_men(a) / 1000.0, loc], func(): group_changed.emit([id]),
			"Select only this army")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.x = panel_width - 40
		add(b)
	section("Orders")
	var why := ""
	if where.size() > 1:
		why = "They must all stand in the same province to merge."
	elif fighting:
		why = "Not while one of them is in battle."
	var ids: Array = group.duplicate()
	var merge = UI.action("Merge all", why, func():
		Game.mil.merge_armies(ids)
		group_changed.emit([ids[0]]), "Join every selected army into one.")
	var stop = UI.button("Stop all", func():
		for id in ids:
			if Game.armies.has(id) and not Game.armies[id]["retreating"]:
				Game.armies[id]["path"] = []
		Game.armies_changed.emit(), "Cancel every march order.")
	add(UI.row([merge, stop]))
