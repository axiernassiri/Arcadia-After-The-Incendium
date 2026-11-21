extends "res://scripts/ui/panel_base.gd"
## Technology: three tracks, paid with the matching power.


func setup() -> void:
	set_title("Technology")
	panel_width = 440.0
	Game.month_ticked.connect(mark_dirty)
	Game.nation_changed.connect(func(t): if t == Game.player_tag: mark_dirty())


func build() -> void:
	var tag = Game.player_tag
	var n: Dictionary = Game.nations[tag]
	var tl = text("Each level costs power of its type. Researching before a level's year costs 5%% more per year early. Tech cost modifier: %+d%%." % int(Game.mods.nat(tag, "tech_cost_mod") * 100), 12, UI.TEXT_DIM)
	tl.tooltip_text = "Technology cost:\n" + Game.mods.breakdown(tag, ["tech_cost_mod"])
	tl.mouse_filter = Control.MOUSE_FILTER_PASS
	var labels = ["Administrative", "Diplomatic", "Military"]
	for i in 3:
		var track: String = Game.TRACKS[i]
		var lvl: int = int(n["tech"][i])
		section("%s (%s) - level %d" % [labels[i], n["power_names"][i], lvl])
		var cur: Dictionary = Game.prog.level_info(track, lvl)
		if not cur.is_empty():
			text("Current: %s" % cur.get("name", ""), 12, UI.TEXT_DIM)
		var nxt: Dictionary = Game.prog.level_info(track, lvl + 1)
		if nxt.is_empty():
			text("All researched.", 13, UI.GOOD)
			continue
		var cost: int = Game.prog.tech_cost(tag, track)
		var c = UI.card()
		var v = VBoxContainer.new()
		c.add_child(v)
		v.add_child(UI.row([UI.label("Next: %s" % nxt.get("name", ""), 15, UI.GOLD), UI.spacer(), UI.label("year %d" % int(nxt.get("year", 0)), 12, UI.TEXT_DIM)]))
		if nxt.has("text"):
			v.add_child(UI.label(nxt["text"], 12, UI.TEXT_DIM, panel_width - 60))
		v.add_child(UI.label(Game.prog.unlock_text(nxt, tag), 12, UI.GOOD, panel_width - 60))
		v.add_child(UI.row([UI.bar(float(n["power"][i]), float(cost), 180.0), UI.label("%d / %d" % [int(n["power"][i]), cost], 12)]))
		v.add_child(UI.action("Research (%d %s)" % [cost, n["power_names"][i]], Game.prog.can_research(tag, track),
			func(): Game.prog.research(tag, track); mark_dirty()))
		add(c)
		var later: PackedStringArray = []
		for k in range(lvl + 2, mini(lvl + 5, Game.prog.max_level(track) + 1)):
			later.append("%d %s" % [k, Game.prog.level_info(track, k).get("name", "")])
		if later.size() > 0:
			text("Later: " + ", ".join(later), 11, UI.TEXT_DIM)
	section("What you have")
	text("Land units: %s. Forts: level %d. Idea slots: %d." % [Game.prog.unit_tier_name(tag), Game.prog.fort_tech_level(tag), Game.prog.idea_slots(tag)], 12)
