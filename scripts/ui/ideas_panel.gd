extends "res://scripts/ui/panel_base.gd"
## Ideas: national ideas (unlocked by taking generic ideas) and idea groups in idea slots.


func setup() -> void:
	set_title("Ideas")
	panel_width = 440.0
	Game.month_ticked.connect(mark_dirty)
	Game.nation_changed.connect(func(t): if t == Game.player_tag: mark_dirty())


func build() -> void:
	var tag = Game.player_tag
	var n: Dictionary = Game.nations[tag]
	var natl: Dictionary = Game.idea_data["national"].get(n["ideas"], {})
	var unlocked: int = Game.prog.national_ideas_unlocked(tag)
	section(natl.get("name", "National ideas"))
	text("Every 3 ideas you adopt from idea groups unlock the next national idea. (%d of 7)" % unlocked, 12, UI.TEXT_DIM)
	add(UI.label("Traditions", 13, UI.GOLD))
	add(UI.mod_box(natl.get("traditions", {}), n["power_names"], panel_width - 40))
	var ideas: Array = natl.get("ideas", [])
	for i in ideas.size():
		var it: Array = ideas[i]
		var have = i < unlocked
		add(UI.label(("%d. " % (i + 1)) + String(it[0]), 13, UI.TEXT if have else UI.TEXT_DIM))
		if it.size() > 2:
			add(UI.label("    " + String(it[2]), 11, UI.TEXT_DIM, panel_width - 50))
		var mb = UI.mod_box(it[1], n["power_names"], panel_width - 40)
		mb.modulate.a = 1.0 if have else 0.5
		add(mb)
	add(UI.label("Ambition" + (" (unlocked)" if unlocked >= ideas.size() else ""), 13, UI.GOLD if unlocked >= ideas.size() else UI.TEXT_DIM))
	add(UI.mod_box(natl.get("ambition", {}), n["power_names"], panel_width - 40))

	var slots: int = Game.prog.idea_slots(tag)
	section("Idea groups (%d of %d slots)" % [n["idea_groups"].size(), slots])
	text("Idea cost: %d power. More slots come with administrative technology." % Game.prog.idea_cost(tag), 12, UI.TEXT_DIM)
	for ig in n["idea_groups"]:
		var grp: Dictionary = Game.idea_data["groups"][ig["id"]]
		var i_pow: int = Game.TRACKS.find(grp["type"])
		var c = UI.card()
		var v = VBoxContainer.new()
		c.add_child(v)
		v.add_child(UI.row([UI.label(grp["name"], 15, UI.GOLD), UI.spacer(), UI.label("%d / 7 (%s)" % [int(ig["taken"]), n["power_names"][i_pow]], 12)]))
		for k in grp["ideas"].size():
			var idea: Array = grp["ideas"][k]
			var done = k < int(ig["taken"])
			var lines = UI.mod_lines(idea[1], n["power_names"])
			v.add_child(UI.label(("[x] " if done else "[ ] ") + String(idea[0]) + ": " + String(lines[0][0]), 12, UI.GOOD if done else UI.TEXT_DIM, panel_width - 60))
		v.add_child(UI.label("Bonus when complete: " + Game.mods.describe(grp.get("bonus", {}), n["power_names"]), 11, UI.TEXT_DIM, panel_width - 60))
		if int(ig["taken"]) < grp["ideas"].size():
			v.add_child(UI.action("Adopt %s (%d %s)" % [grp["ideas"][int(ig["taken"])][0], Game.prog.idea_cost(tag), n["power_names"][i_pow]],
				Game.prog.can_take_idea(tag, ig["id"]), func(): Game.prog.take_idea(tag, ig["id"]); mark_dirty()))
		add(c)
	if n["idea_groups"].size() < slots:
		section("Choose an idea group")
		for gid in Game.idea_data["groups"]:
			var taken = false
			for ig in n["idea_groups"]:
				if ig["id"] == gid:
					taken = true
			if taken:
				continue
			var grp: Dictionary = Game.idea_data["groups"][gid]
			var first: Array = grp["ideas"][0]
			var tip = "%s ideas (%s power)\nFirst idea: %s\nBonus: %s" % [grp["name"], grp["type"], first[0], Game.mods.describe(grp.get("bonus", {}), n["power_names"])]
			add(UI.row([UI.action("Pick %s" % grp["name"], Game.prog.can_pick_group(tag, gid), func(): Game.prog.pick_group(tag, gid); mark_dirty(), tip),
				UI.label(grp["type"].to_upper(), 11, UI.TEXT_DIM)]))
	elif slots == 0:
		text("No idea slots yet: research administrative tech 2.", 12, UI.BAD)
