extends "res://scripts/ui/panel_base.gd"
## Cultures, religions and ethnicities in your realm: accepted cultures, missionaries, conversion.


func setup() -> void:
	set_title("Peoples")
	panel_width = 440.0
	Game.month_ticked.connect(mark_dirty)
	Game.nation_changed.connect(func(t): if t == Game.player_tag: mark_dirty())


func build() -> void:
	var tag = Game.player_tag
	var n: Dictionary = Game.nations[tag]
	var rel: Dictionary = Game.peoples["religions"].get(n["religion"], {})
	add(UI.kv("State religion", n["religion"], rel.get("text", "")))
	if rel.has("modifiers"):
		add(UI.mod_box(rel["modifiers"], n["power_names"], panel_width - 40))
	add(UI.kv("Primary culture", "%s (%s group)" % [n["culture"], Game.pop.culture_group(n["culture"])]))
	var eth: Dictionary = Game.peoples["ethnicities"].get(n["ethnicity"], {})
	add(UI.kv("People", n["ethnicity"], eth.get("text", "")))
	add(UI.kv("Tolerance of the true faith", "%+.1f" % Game.pop.tolerance(tag, n["religion"])))
	add(UI.kv("Tolerance of other faiths", "%+.1f" % Game.pop.tolerance(tag, "other"), "Provinces of other faiths get 3 unrest minus this (plus 1)."))
	text("Map modes Culture, Religion and Ethnicity show these across Arcadia.", 11, UI.TEXT_DIM)

	var cultures = {}
	var religions = {}
	var peoples = {}
	for pid in Game.owned(tag):
		var p: Dictionary = Game.provinces[pid]
		cultures[p["culture"]] = int(cultures.get(p["culture"], 0)) + Game.total_dev(pid)
		religions[p["religion"]] = int(religions.get(p["religion"], 0)) + Game.total_dev(pid)
		peoples[p["ethnicity"]] = int(peoples.get(p["ethnicity"], 0)) + Game.total_dev(pid)
	section("Cultures in your realm (development)")
	for c in cultures:
		var acc: bool = Game.pop.culture_accepted(tag, c)
		var row = UI.row([UI.swatch(Color(Game.peoples["cultures"].get(c, {}).get("colour", "#888888")), Vector2(12, 12)),
			UI.label("%s (%s)" % [c, Game.pop.culture_group(c)], 13, UI.TEXT if acc else UI.BAD), UI.spacer(), UI.label(str(cultures[c]), 13)])
		add(row)
		if not acc:
			add(UI.action("   Accept %s culture (100 %s)" % [c, n["power_names"][1]], Game.pop.can_accept_culture(tag, c),
				func(): Game.pop.accept_culture(tag, c); mark_dirty(), "Accepted cultures cause no unrest."))
	text("Accepted: %s" % (", ".join(n["accepted_cultures"]) if n["accepted_cultures"].size() > 0 else "none"), 12, UI.TEXT_DIM)
	section("Faiths in your realm (development)")
	for r in religions:
		add(UI.row([UI.swatch(Color(Game.peoples["religions"].get(r, {}).get("colour", "#888888")), Vector2(12, 12)),
			UI.label(r if r != "" else "none", 13, UI.TEXT if r == n["religion"] else UI.BAD), UI.spacer(), UI.label(str(religions[r]), 13)]))
	section("Peoples in your realm (development)")
	for e in peoples:
		add(UI.row([UI.swatch(Color(Game.peoples["ethnicities"].get(e, {}).get("colour", "#888888")), Vector2(12, 12)),
			UI.label(e if e != "" else "none", 13), UI.spacer(), UI.label(str(peoples[e]), 13)]))
	section("Missionaries (%d / %d)" % [Game.pop.missionaries_used(tag), Game.pop.missionaries(tag)])
	var any = false
	for pid in Game.owned(tag):
		var p: Dictionary = Game.provinces[pid]
		if p["religion"] == n["religion"] or p["religion"] == "":
			continue
		any = true
		if p["conversion"].get("tag", "") == tag:
			add(UI.row([UI.label(p["name"], 13), UI.spacer(), UI.bar(float(p["conversion"]["progress"]), 100.0, 120.0, UI.INFO),
				UI.label("%.1f a month" % Game.pop.conversion_speed(tag, pid), 11, UI.TEXT_DIM)]))
		else:
			add(UI.row([UI.label("%s (%s)" % [p["name"], p["religion"]], 13), UI.spacer(),
				UI.action("Send missionary", Game.pop.can_start_conversion(tag, pid), func(): Game.pop.start_conversion(tag, pid); mark_dirty())]))
	if not any:
		text("Every province follows the %s." % n["religion"], 12, UI.GOOD)
