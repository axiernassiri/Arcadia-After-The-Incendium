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
	_estates(tag, n)
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


func _estates(tag: String, n: Dictionary) -> void:
	## EU4-style estates: loyalty, influence, a privilege to grant or revoke, and support to call on.
	section("Estates")
	text("Loyal estates (60+) help the realm, disloyal ones (under 30) hurt it, and an estate with a privilege (50+ influence) that stays disloyal for half a year throws the realm into disorder.", 11, UI.TEXT_DIM)
	var defs: Dictionary = Game.standing.estate_defs()
	for k in defs:
		var d: Dictionary = defs[k]
		var e: Dictionary = Game.standing.estates(tag)[k]
		var loy: float = float(e["loyalty"])
		var inf: float = Game.standing.influence(tag, k)
		var col: Color = UI.GOOD if loy >= 60.0 else (UI.BAD if loy < 30.0 else UI.GOLD)
		var c = UI.card(col, 6)
		var v = VBoxContainer.new()
		c.add_child(v)
		v.add_child(UI.row([UI.icon(d.get("icon", "person"), 18, col), UI.heading(d["name"], 15), UI.spacer(),
			UI.label("influence %d" % int(inf), 12, UI.TEXT_DIM)]))
		v.add_child(UI.label(d.get("text", ""), 11, UI.TEXT_DIM, panel_width - 70))
		v.add_child(UI.row([UI.label("Loyalty %d" % int(loy), 13, col), UI.bar(loy, 100.0, 180.0, col)]))
		var effect: Dictionary = d.get("bonus", {}) if loy >= 60.0 else (d.get("malus", {}) if loy < 30.0 else {})
		if not effect.is_empty():
			v.add_child(UI.mod_box(effect, n["power_names"], panel_width - 70))
		var priv: Dictionary = d["privilege"]
		var held: bool = e["privilege"]
		v.add_child(UI.label("Privilege: %s%s — %s" % [priv["name"], " (granted)" if held else "",
			Game.mods.describe(priv.get("modifiers", {}), n["power_names"])], 11, UI.GOOD if held else UI.TEXT, panel_width - 70))
		var sup: Dictionary = d["support"]
		var toggle := func():
			if held:
				Game.standing.revoke(tag, k)
			else:
				Game.standing.grant(tag, k)
			mark_dirty()
		var why: String = Game.standing.can_revoke(tag, k) if held else Game.standing.can_grant(tag, k)
		var tip: String = ("Revoking: -20 loyalty, costs 50 %s." % n["power_names"][0]) if held else "+15 loyalty and +35 influence; the crown gets the privilege's bonus too."
		var row = UI.row([
			UI.action("Revoke privilege" if held else "Grant privilege", why, toggle, tip),
			UI.action(sup["name"], Game.standing.can_call(tag, k), func(): Game.standing.call_support(tag, k); mark_dirty(),
				"%s Costs 15 loyalty. Once every ten years." % sup.get("text", ""))])
		v.add_child(row)
		add(c)
