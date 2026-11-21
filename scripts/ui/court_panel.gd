extends "res://scripts/ui/panel_base.gd"
## The court: ruler and heir, stability, war exhaustion, army tradition, and every modifier in effect.


func setup() -> void:
	set_title("Court")
	panel_width = 430.0
	Game.month_ticked.connect(mark_dirty)
	Game.nation_changed.connect(func(t): if t == Game.player_tag: mark_dirty())


func _person(label: String, p: Dictionary, names: Array) -> void:
	var c = UI.card()
	var v = VBoxContainer.new()
	c.add_child(v)
	if p.is_empty():
		v.add_child(UI.label("%s: none" % label, 14, UI.TEXT_DIM))
		add(c)
		return
	var age = "ageless" if p.get("ageless", false) else "age %d" % int(p.get("age", 0))
	v.add_child(UI.label(label, 12, UI.TEXT_DIM))
	v.add_child(UI.row([UI.label("%s %s" % [p.get("name", "?"), p.get("dynasty", "")], 16, UI.GOLD), UI.spacer(), UI.label(age, 12, UI.TEXT_DIM)]))
	if p.get("regency", false):
		v.add_child(UI.label("A regency council rules until an heir comes of age. Weak stats.", 12, UI.BAD, panel_width - 60))
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	for i in 3:
		var val: int = int(p.get(["adm", "dip", "mil"][i], 0))
		row.add_child(UI.tip_label("%s %d" % [names[i], val], "Adds %d to monthly %s power while ruling." % [val, names[i]], 14))
	v.add_child(row)
	add(c)


func build() -> void:
	var tag = Game.player_tag
	var n: Dictionary = Game.nations[tag]
	var names: Array = n["power_names"]
	add(UI.row([UI.swatch(n["colour"], Vector2(20, 20)), UI.label(n["name"], 18, UI.GOLD)]))
	text("%s %s. Capital: %s." % [Game.prog.government(tag).get("name", ""), n["ruler"].get("dynasty", ""),
		Game.provinces[Game.capital_of(tag)]["name"] if Game.capital_of(tag) >= 0 else "none"], 12, UI.TEXT_DIM)
	_person("Ruler", n["ruler"], names)
	if not n["ruler"].get("ageless", false) or not n["heir"].is_empty():
		_person("Heir", n["heir"], names)
	else:
		text("No heir: the King is ageless and will not die of old age.", 12, UI.TEXT_DIM)
	var leg = float(n.get("legitimacy", 50.0))
	var lname: String = Game.court.legitimacy_name(tag)
	add(UI.row([UI.tip_label("%s %d" % [lname, int(leg)], "%s %+.1f a year.\nBelow 50: less power and more unrest. Below 25: -1 to every monthly power.\nAbove 80: bonus power and calmer provinces.%s" % [
		lname, Game.court.legitimacy_gain(tag), "\nA republic elects a new leader every %d years." % int(Game.prog.government(tag).get("term_years", 4)) if Game.court.gov_type(tag) == "republic" else ""], 15,
		UI.BAD if leg < 50.0 else (UI.GOOD if leg >= 80.0 else UI.TEXT)), UI.bar(leg, 100.0, 140.0, UI.BAD if leg < 50.0 else UI.GOLD)]))
	_advisors(tag, names)
	section("Stability")
	add(UI.row([UI.label("Stability %+d" % int(n["stability"]), 16, UI.GOOD if int(n["stability"]) > 0 else UI.TEXT), UI.spacer(),
		UI.action("Raise (%d %s)" % [Game.court.stability_cost(tag), names[0]], Game.court.can_raise_stability(tag),
			func(): Game.court.raise_stability(tag); mark_dirty())]))
	text("Each point of stability: +5% tax and -1 unrest everywhere. Declaring war without a cause costs 2.", 11, UI.TEXT_DIM)
	section("War")
	add(UI.row([UI.label("War exhaustion %.1f" % float(n["war_exhaustion"]), 14, UI.BAD if float(n["war_exhaustion"]) > 2 else UI.TEXT), UI.spacer(),
		UI.action("Reduce (50 %s)" % names[1], Game.court.can_reduce_we(tag), func(): Game.court.reduce_we(tag); mark_dirty())]))
	add(UI.kv("Army tradition", "%d" % int(n["army_tradition"]), "Won battles raise it. Higher tradition gives better generals."))
	add(UI.kv("Battles won", str(int(n.get("battles_won", 0)))))
	section("Modifiers in effect")
	for s in Game.mods.sources(tag):
		var mods: Dictionary = s[1]
		if mods.is_empty():
			continue
		add(UI.label(String(s[0]), 13, UI.GOLD))
		add(UI.mod_box(mods, names, panel_width - 40))
	var timed: Array = n["modifiers"]
	for m in timed:
		if int(m.get("until", -1)) > 0:
			text("%s ends around %s." % [m.get("name", ""), Game.date_from_index(int(m["until"]))], 11, UI.TEXT_DIM)


func _advisors(tag: String, names: Array) -> void:
	var n: Dictionary = Game.nations[tag]
	section("Council of advisors  (%.1f a month in salaries)" % Game.court.salaries(tag))
	text("One advisor for each kind of power. Each adds their skill to that power every month, plus their own bonus.", 11, UI.TEXT_DIM)
	for i in 3:
		var power: String = Game.TRACKS[i]
		var a: Dictionary = n.get("advisors", {}).get(power, {})
		var c = UI.card()
		var v = VBoxContainer.new()
		c.add_child(v)
		if a.is_empty():
			v.add_child(UI.label("%s seat: empty" % names[i], 13, UI.TEXT_DIM))
		else:
			var at: Dictionary = Game.advisor_data["types"].get(a["type"], {})
			v.add_child(UI.row([UI.label("%s: %s" % [names[i], a["name"]], 13, UI.GOLD), UI.spacer(),
				UI.label("%s, skill %d" % [at.get("name", a["type"]), int(a["skill"])], 12),
				UI.button("Dismiss", func(): Game.court.dismiss(tag, power); mark_dirty(), "Free the seat. The salary stops.")]))
			v.add_child(UI.label("+%d %s a month · %s · %.1f sanctum a month" % [int(a["skill"]), names[i], Game.mods.describe(at.get("modifiers", {})),
				Game.court.advisor_salary(tag, int(a["skill"]))], 11, UI.TEXT_DIM, panel_width - 70))
		var cands = HFlowContainer.new()
		for cand in n.get("advisor_pool", []):
			if cand["power"] != power:
				continue
			var ct: Dictionary = Game.advisor_data["types"].get(cand["type"], {})
			cands.add_child(UI.action("%s %d (%d)" % [ct.get("name", cand["type"]), int(cand["skill"]), Game.court.advisor_cost(tag, int(cand["skill"]))],
				Game.court.can_hire(tag, int(cand["id"])), func(): Game.court.hire(tag, int(cand["id"])); mark_dirty(),
				"%s\n%s\nSalary %.1f a month. Hiring replaces the current advisor." % [cand["name"], Game.mods.describe(ct.get("modifiers", {})), Game.court.advisor_salary(tag, int(cand["skill"]))]))
		v.add_child(cands)
		add(c)
