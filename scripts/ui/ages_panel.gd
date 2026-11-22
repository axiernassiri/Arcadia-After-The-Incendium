extends "res://scripts/ui/panel_base.gd"
## Ages (K), like EU4: the current age, its objectives (each worth splendor once), and the abilities
## splendor buys for the rest of the age. The other ages are listed below.


func setup() -> void:
	set_title("Ages")
	panel_width = 460.0
	Game.month_ticked.connect(mark_dirty)


func build() -> void:
	var tag: String = Game.player_tag
	var n: Dictionary = Game.nations[tag]
	var age: Dictionary = Game.standing.current_age()
	if age.is_empty():
		text("No ages defined.", 12, UI.TEXT_DIM)
		return
	add(UI.row([UI.heading(age["name"], 19), UI.spacer(), UI.label("%d to %d" % [int(age["start"]), int(age["end"])], 13, UI.TEXT_DIM)]))
	text(age.get("text", ""), 12, UI.TEXT_DIM)
	var left: int = int(age["end"]) - Game.year
	add(UI.kv("Years left", str(left)))
	var gain: float = float(Game.age_data.get("monthly_splendor", 2)) + (float(Game.age_data.get("great_power_bonus", 1)) if Game.standing.is_great_power(tag) else 0.0)
	add(UI.kv("Splendor", "%d  (+%d a month)" % [int(Game.standing.splendor(tag)), int(gain)],
		"Earned every month (more as a Great Power) and from each objective of the age you fulfil. Spend it on abilities.", UI.GOLD))

	section("Objectives (+%d splendor each)" % int(Game.age_data.get("objective_splendor", 200)))
	for o in age.get("objectives", []):
		var done: bool = Game.standing.objective_done(tag, age["id"], o["id"])
		var req: PackedStringArray = []
		for c in o.get("conditions", []):
			req.append(("✓ " if Game.check_condition(c, tag) else "✗ ") + Game.describe_condition(c))
		add(UI.row([UI.label("✓" if done else "•", 14, UI.GOOD if done else UI.TEXT_DIM), UI.label(o["name"], 14, UI.GOOD if done else UI.TEXT),
			UI.spacer(), UI.label(",  ".join(req), 11, UI.TEXT_DIM)], 8))

	section("Abilities (%d splendor, until the age ends)" % int(Game.age_data.get("ability_cost", 600)))
	for ab in age.get("abilities", []):
		var taken: bool = Game.standing.ability_taken(tag, age["id"], ab["id"])
		var c = UI.card(UI.GOOD if taken else UI.BORDER, 6)
		var v = VBoxContainer.new()
		c.add_child(v)
		v.add_child(UI.row([UI.label(ab["name"], 14, UI.GOLD if taken else UI.TEXT), UI.spacer(), UI.label("Active" if taken else "", 12, UI.GOOD)]))
		v.add_child(UI.mod_box(ab.get("modifiers", {}), n["power_names"], panel_width - 60))
		if not taken:
			v.add_child(UI.action("Take (%d splendor)" % int(Game.age_data.get("ability_cost", 600)), Game.standing.can_take_ability(tag, ab["id"]),
				func(): Game.standing.take_ability(tag, ab["id"]); mark_dirty()))
		add(c)

	section("The ages of Arcadia")
	for a in Game.standing.ages():
		var now: bool = a["id"] == age["id"]
		add(UI.kv(a["name"], "%d to %d%s" % [int(a["start"]), int(a["end"]), "  (now)" if now else ""], a.get("text", ""),
			UI.GOLD if now else (UI.TEXT_DIM if Game.year >= int(a["end"]) else UI.TEXT)))
