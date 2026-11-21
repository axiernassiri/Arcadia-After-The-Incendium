extends "res://scripts/ui/panel_base.gd"
## Diplomacy overview: every nation, your relations with it, and your wars.

signal country_selected(tag: String)
signal peace_requested(war_id: int)


func setup() -> void:
	set_title("Diplomacy")
	panel_width = 440.0
	Game.month_ticked.connect(mark_dirty)
	Game.war_changed.connect(mark_dirty)
	Game.nation_changed.connect(func(_t): mark_dirty())


func build() -> void:
	var tag = Game.player_tag
	var n: Dictionary = Game.nations[tag]
	text("Right-click any nation's province on the map (with no army selected) to open its diplomacy.", 12, UI.TEXT_DIM)
	add(UI.kv("Diplomats", "%d / %d" % [Game.dip.diplomats_used(tag), Game.dip.diplomats(tag)], "Each diplomat can improve relations with one nation."))
	var wars: Array = Game.dip.wars_of(tag)
	section("Wars (%d)" % wars.size())
	if wars.is_empty():
		text("At peace.", 12, UI.GOOD)
	for w in wars:
		var ws: float = Game.dip.score_for(w, tag)
		var side: String = Game.dip.war_side(w, tag)
		var other = "defenders" if side == "attackers" else "attackers"
		var c = UI.card(UI.BAD)
		var v = VBoxContainer.new()
		c.add_child(v)
		v.add_child(UI.label(w["name"], 15, UI.GOLD))
		v.add_child(UI.label("Casus belli: %s" % w["cb"].get("name", ""), 11, UI.TEXT_DIM))
		v.add_child(UI.label("Your side: %s" % _names(w[side]), 12, UI.GOOD, panel_width - 60))
		v.add_child(UI.label("Enemies: %s" % _names(w[other]), 12, UI.BAD, panel_width - 60))
		var bar = UI.bar(ws + 100.0, 200.0, 220.0, UI.GOOD if ws >= 0 else UI.BAD)
		bar.tooltip_text = "Occupations and battles. You need war score to make demands."
		v.add_child(UI.row([UI.label("War score %+d" % int(ws), 13, UI.GOOD if ws >= 0 else UI.BAD), bar]))
		v.add_child(UI.label("Battles %+d of the score, occupation the rest. Started %d months ago." % [
			int(float(w["battle_score"]) * (1 if side == "attackers" else -1)), int((Game.day_index - int(w["start"])) / 30)], 11, UI.TEXT_DIM))
		var lead: bool = w[side][0] == tag
		if lead:
			for ally in Game.dip.uncalled_allies(w, tag):
				var q: Dictionary = Game.dip.call_quote(w, tag, ally)
				var lines: PackedStringArray = []
				for r in q["reasons"]:
					lines.append("%s: %+d" % [r[0], int(r[1])])
				var why: String = q["why"]
				if why == "" and not q["accept"]:
					why = "%s won't join (%+d)." % [Game.nation_name(ally), int(q["score"])]
				elif why == "" and float(n["treasury"]) < float(q["price"]):
					why = "They want %d sanctum; you can't pay." % int(q["price"])
				v.add_child(UI.row([UI.label(Game.nation_name(ally), 12, UI.INFO), UI.spacer(),
					UI.label("wants %d sanctum" % int(q["price"]) if q["accept"] else "refuses", 11, UI.GOLD if q["accept"] else UI.BAD),
					UI.action("Call to arms", why, func(): Game.post(Game.dip.call_ally(w, tag, ally)); mark_dirty(),
						"Allies don't join on their own. They decide by what they think of you, the enemy and their own situation, and want sanctum in return.\n" + "\n".join(lines))]))
		v.add_child(UI.action("Negotiate peace", "" if lead or true else "", func(): peace_requested.emit(int(w["id"]))))
		add(c)
	_threats(tag)
	section("Nations")
	var tags: Array = []
	for t in Game.nations:
		if t != tag and Game.nations[t]["alive"]:
			tags.append(t)
	tags.sort_custom(func(a, b): return Game.nation_dev(a) > Game.nation_dev(b))
	for t in tags:
		var o: Dictionary = Game.nations[t]
		var flags: PackedStringArray = []
		var r: Dictionary = Game.dip.rel(tag, t)
		if Game.dip.at_war(tag, t):
			flags.append("AT WAR")
		if r["alliance"]:
			flags.append("ally")
		if r["marriage"]:
			flags.append("married")
		if o["overlord"] == tag:
			flags.append("your vassal")
		if n["overlord"] == t:
			flags.append("your overlord")
		if r["rival"]:
			flags.append("rival")
		if Game.dip.truce(tag, t):
			flags.append("truce")
		if r["improving"]:
			flags.append("improving")
		var op: float = Game.dip.opinion(t, tag)
		var b = UI.button("", func(): country_selected.emit(t))
		b.custom_minimum_size = Vector2(panel_width - 40, 46)
		var row = HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.add_theme_constant_override("separation", 8)
		b.add_child(row)
		var sw = UI.swatch(o["colour"], Vector2(14, 30))
		row.add_child(sw)
		var col = VBoxContainer.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(UI.label(o["name"], 14, UI.GOLD))
		col.add_child(UI.label("%d provinces, %d development   %s" % [Game.owned(t).size(), Game.nation_dev(t), ", ".join(flags)], 11, UI.TEXT_DIM))
		row.add_child(col)
		row.add_child(UI.spacer())
		row.add_child(UI.label("%+d" % int(op), 14, UI.GOOD if op >= 0 else UI.BAD))
		add(b)


func _names(tags: Array) -> String:
	var out: PackedStringArray = []
	for t in tags:
		out.append(Game.nation_name(t))
	return ", ".join(out)


func _threats(tag: String) -> void:
	## Aggressive expansion and coalitions, like EU4's "Threat" view.
	var wary: Array = []
	for t in Game.nations:
		if t != tag and Game.nations[t]["alive"]:
			var ae: float = Game.dip.aggressive_expansion(t, tag)
			if ae >= 10.0:
				wary.append([t, ae])
	var coal: Array = Game.dip.coalition_against(tag)
	if wary.is_empty() and coal.is_empty():
		return
	wary.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	section("Aggressive expansion")
	text("Taking land makes others wary. At %d a nation joins a coalition against you; it fades by %.1f a month." % [
		int(Game.dip.COALITION_JOIN), Game.dip.AE_DECAY], 12, UI.TEXT_DIM)
	if coal.size() > 0:
		var st: Array = Game.dip.coalition_strength(tag)
		var names: PackedStringArray = []
		for t in coal:
			names.append(Game.nations[t]["short"])
		text("Coalition against you (%d): %s. Their armies %d, yours %d." % [coal.size(), ", ".join(names), int(st[0]), int(st[1])], 13, UI.BAD)
	for x in wary.slice(0, 8):
		var t: String = x[0]
		var ae: float = x[1]
		var col: Color = UI.BAD if ae >= Game.dip.COALITION_JOIN else (UI.WARN if ae >= Game.dip.COALITION_LEAVE else UI.TEXT)
		add(UI.row([UI.label(Game.nation_name(t), 13), UI.spacer(), UI.bar(ae, 100.0, 120.0, col), UI.label("%d" % int(ae), 13, col)]))
