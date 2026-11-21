extends "res://scripts/ui/panel_base.gd"
## EU4-style war overview: the war score and where it comes from, everyone on each side, what each
## side occupies, and the battles fought so far. Opened from the outliner or the Diplomacy panel.

signal peace_requested(war_id: int)

var war_id = -1


func setup() -> void:
	set_title("War")
	panel_width = 440.0
	max_height = 640.0
	Game.war_changed.connect(mark_dirty)
	Game.month_ticked.connect(mark_dirty)
	Game.armies_changed.connect(mark_dirty)


func show_war(id: int) -> void:
	war_id = id
	visible = Game.wars.has(id)
	if visible:
		refresh_now()


func build() -> void:
	var w: Dictionary = Game.wars.get(war_id, {})
	var me: String = Game.player_tag
	if w.is_empty():
		set_title("War")
		text("This war is over.", 13, UI.TEXT_DIM)
		return
	set_title(w["name"])
	var side: String = Game.dip.war_side(w, me)
	if side == "":
		side = "attackers"
	var other := "defenders" if side == "attackers" else "attackers"
	var months := int((Game.day_index - int(w["start"])) / 30.0)
	text("Casus belli: %s  ·  started %s (%d months ago)" % [w["cb"].get("name", "None"), Game.date_from_index(int(w["start"])), months], 12, UI.TEXT_DIM)

	# war score
	var ws: float = Game.dip.score_for(w, me) if Game.dip.war_side(w, me) != "" else float(w["score"])
	var battle: float = float(w["battle_score"]) * (1.0 if side == "attackers" else -1.0)
	section("War score %+d%%" % int(ws))
	add(_score_bar(ws))
	add(UI.kv("From battles", "%+d%%" % int(battle), "Each won battle adds to the score by the losses inflicted (at most 40%)."))
	add(UI.kv("From occupation", "%+d%%" % int(ws - battle), "Enemy land held, weighted by development. Their capital counts extra."))

	# both sides
	section("Your side" if Game.dip.war_side(w, me) != "" else "Attackers")
	_side(w, side)
	section("Enemies" if Game.dip.war_side(w, me) != "" else "Defenders")
	_side(w, other)

	# occupations
	section("Occupations")
	var ours: Array = _occupied(w, other, side)
	var theirs: Array = _occupied(w, side, other)
	_occupation_line("We hold %d of their provinces" % ours.size(), ours, UI.GOOD)
	_occupation_line("They hold %d of ours" % theirs.size(), theirs, UI.BAD)

	# battles
	var battles: Array = w.get("battles", [])
	section("Battles (%d)" % battles.size())
	if battles.is_empty():
		text("No battles yet.", 12, UI.TEXT_DIM)
	for i in range(battles.size() - 1, maxi(-1, battles.size() - 11), -1):
		var b: Dictionary = battles[i]
		var we_won: bool = Game.dip.war_side(w, b["winner"]) == side
		add(UI.kv("%s  %s" % [b["date"], b["province"]], "%s  (%d / %d lost)%s" % ["won" if we_won else "lost",
			b["win_losses"] if we_won else b["lose_losses"], b["lose_losses"] if we_won else b["win_losses"], "  wiped" if b.get("wiped", false) else ""],
			"%s beat %s" % [Game.nation_name(b["winner"]), Game.nation_name(b["loser"])], UI.GOOD if we_won else UI.BAD))

	if Game.dip.war_side(w, me) != "":
		var peace = UI.button("Negotiate peace", func(): peace_requested.emit(int(w["id"])))
		peace.custom_minimum_size.x = panel_width - 40
		add(peace)


func _score_bar(ws: float) -> Control:
	## -100..100 with the middle marked: green to the right when winning, red to the left when losing.
	var c := Control.new()
	c.custom_minimum_size = Vector2(panel_width - 40, 14)
	c.draw.connect(func():
		var r := Rect2(Vector2.ZERO, c.size)
		c.draw_rect(r, Color(0.02, 0.02, 0.03, 0.9))
		var mid := r.size.x / 2.0
		var wv := clampf(ws, -100.0, 100.0) / 100.0 * mid
		if wv >= 0.0:
			c.draw_rect(Rect2(mid, 2, wv, r.size.y - 4), UI.GOOD)
		else:
			c.draw_rect(Rect2(mid + wv, 2, -wv, r.size.y - 4), UI.BAD)
		c.draw_line(Vector2(mid, 0), Vector2(mid, r.size.y), UI.TEXT, 1.0))
	return c


func _side(w: Dictionary, s: String) -> void:
	for t in w[s]:
		if not Game.nations.has(t):
			continue
		var lead := " (war leader)" if t == w[s][0] else ""
		var n: Dictionary = Game.nations[t]
		add(UI.row([UI.swatch(Game.owner_colour(t), Vector2(10, 14)), UI.label(Game.nation_name(t) + lead, 13), UI.spacer(),
			UI.label("%d dev  ·  army %d  ·  exhaustion %.1f" % [Game.nation_dev(t), int(Game.mil.nation_strength(t)), float(n["war_exhaustion"])], 11, UI.TEXT_DIM)], 6))


func _occupied(w: Dictionary, owners_side: String, holders_side: String) -> Array:
	var out: Array = []
	for t in w[owners_side]:
		for pid in Game.owned(t):
			if Game.provinces[pid]["controller"] in w[holders_side]:
				out.append(pid)
	return out


func _occupation_line(title: String, pids: Array, col: Color) -> void:
	text(title, 13, col)
	var names: PackedStringArray = []
	for pid in pids.slice(0, 8):
		names.append(Game.provinces[pid]["name"])
	if pids.size() > 8:
		names.append("and %d more" % (pids.size() - 8))
	if names.size() > 0:
		text("  " + ", ".join(names), 11, UI.TEXT_DIM)
