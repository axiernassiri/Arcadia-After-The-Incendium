extends "res://scripts/ui/panel_base.gd"
## Government reforms, EU4-style: one reform per tier, paid with reform progress.


func setup() -> void:
	set_title("Government")
	panel_width = 460.0
	Game.month_ticked.connect(mark_dirty)
	Game.nation_changed.connect(func(t): if t == Game.player_tag: mark_dirty())


func build() -> void:
	var tag = Game.player_tag
	var n: Dictionary = Game.nations[tag]
	var gov: Dictionary = Game.prog.government(tag)
	add(UI.row([UI.heading(gov.get("name", "Government"), 18), UI.spacer(), UI.label(gov.get("rank", ""), 13, UI.TEXT_DIM)]))
	text(gov.get("text", ""), 12, UI.TEXT_DIM)
	if gov.has("modifiers"):
		add(UI.mod_box(gov["modifiers"], n["power_names"], panel_width - 40))
	var prog = float(n["reform_progress"])
	add(UI.kv("Reform progress", "%.1f (+%.2f a month)" % [prog, Game.prog.reform_gain(tag)],
		"Builds up every month, faster with more development. Spend it to enact reforms."))
	var decisions: Array = Game.decisions_for(tag)
	if decisions.size() > 0:
		section("Decisions")
		for d in decisions:
			var why: String = Game.can_take_decision(tag, d["id"])
			var c = UI.card(UI.GOLD if why == "" else Color(), 8)
			var v = VBoxContainer.new()
			c.add_child(v)
			v.add_child(UI.row([UI.icon(d.get("icon", "scroll"), 20, UI.GOLD if why == "" else UI.TEXT_DIM), UI.heading(d["name"], 15)]))
			v.add_child(UI.label(d.get("text", ""), 12, UI.TEXT, panel_width - 70))
			var req: PackedStringArray = []
			for cond in d.get("allow", []):
				req.append(("✓ " if Game.check_condition(cond, tag) else "✗ ") + Game.describe_condition(cond))
			v.add_child(UI.label("Requires: " + ",  ".join(req), 11, UI.TEXT_DIM, panel_width - 70))
			var fx: String = Game.describe_effects(d.get("effects", []), tag)
			if fx != "":
				v.add_child(UI.label("Effects: " + fx, 11, UI.GOOD, panel_width - 70))
			var cost: String = Game.decision_cost_text(tag, d)
			v.add_child(UI.action("Take decision" + (" (%s)" % cost if cost != "" else ""), why,
				func(): Game.take_decision(tag, d["id"]); mark_dirty()))
			add(c)
	var tiers: Array = gov.get("tiers", [])
	for t in tiers.size():
		var tier: Dictionary = tiers[t]
		var chosen: String = n["reforms"][t] if t < n["reforms"].size() else ""
		var cost: int = Game.prog.reform_cost(t)
		section("Tier %d: %s" % [t + 1, tier["name"]])
		if t > n["reforms"].size():
			text("Enact a reform in the tier above first.", 12, UI.TEXT_DIM)
			continue
		for r in tier["reforms"]:
			var is_on: bool = r["id"] == chosen
			var c = UI.card(UI.GOOD if is_on else UI.BORDER, 6)
			var v = VBoxContainer.new()
			c.add_child(v)
			v.add_child(UI.row([UI.label(r["name"], 14, UI.GOLD if is_on else UI.TEXT), UI.spacer(), UI.label("Enacted" if is_on else "", 12, UI.GOOD)]))
			v.add_child(UI.label(r.get("text", ""), 11, UI.TEXT_DIM, panel_width - 60))
			v.add_child(UI.mod_box(r.get("modifiers", {}), n["power_names"], panel_width - 60))
			if not is_on:
				var price = cost if chosen == "" else int(cost / 2)
				v.add_child(UI.action(("Enact" if chosen == "" else "Switch to this") + " (%d progress)" % price,
					Game.prog.can_enact(tag, t, r["id"]), func(): Game.prog.enact(tag, t, r["id"]); mark_dirty()))
			add(c)
