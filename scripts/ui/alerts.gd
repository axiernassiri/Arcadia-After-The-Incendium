extends HBoxContainer
## EU4-style alert icons under the top bar: things you can do now (green), things going wrong (red).
## Hover for details, click to jump to the right panel.

signal open_panel(name: String)
signal go_to_province(id: int)
signal open_peace(war_id: int)

const UI = preload("res://scripts/ui/ui_util.gd")

var _dirty = true
var _since = 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Game.month_ticked.connect(func(): _dirty = true)
	Game.nation_changed.connect(func(t): if t == Game.player_tag: _dirty = true)


func _process(delta: float) -> void:
	_since += delta
	if visible and _dirty and _since > 0.3 and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		refresh()


func compute() -> Array:
	## [[short text, tooltip, colour, callable]]. Also used by the tests.
	var tag: String = Game.player_tag
	var out: Array = []
	if tag == "" or not Game.nations.has(tag) or not Game.nations[tag]["alive"]:
		return out
	var n: Dictionary = Game.nations[tag]
	var names: Array = n["power_names"]
	for i in 3:
		var track: String = Game.TRACKS[i]
		if Game.prog.can_research(tag, track) == "":
			var ahead: int = Game.prog.years_ahead(tag, track)
			out.append(["Tech", "You can research %s technology %d (%d %s).%s" % [names[i], int(n["tech"][i]) + 1, Game.prog.tech_cost(tag, track), names[i],
				"\nIt is %d years ahead of its time: it costs more and gives a temporary penalty." % ahead if ahead > 0 else ""], UI.GOOD, func(): open_panel.emit("tech")])
			break
	if n["idea_groups"].size() < Game.prog.idea_slots(tag):
		out.append(["Ideas", "You have a free idea group slot. Pick an idea group.", UI.GOOD, func(): open_panel.emit("ideas")])
	else:
		for ig in n["idea_groups"]:
			if Game.prog.can_take_idea(tag, ig["id"]) == "":
				out.append(["Idea", "You can adopt the next idea in %s." % Game.idea_data["groups"][ig["id"]]["name"], UI.GOOD, func(): open_panel.emit("ideas")])
				break
	var tiers: Array = Game.prog.government(tag).get("tiers", [])
	var next_tier: int = n["reforms"].size()
	if next_tier < tiers.size():
		for r in tiers[next_tier].get("reforms", []):
			if Game.prog.can_enact(tag, next_tier, r["id"]) == "":
				out.append(["Reform", "You can enact a new government reform.", UI.GOOD, func(): open_panel.emit("government")])
				break
	var ready := 0
	for m in Game.missions_for(tag):
		if Game.mission_state(tag, m) == "ready":
			ready += 1
	if ready > 0:
		out.append(["Mission", "%d mission(s) ready to complete." % ready, UI.GOOD, func(): open_panel.emit("missions")])
	var empty_seats := 0
	for power in Game.TRACKS:
		if n.get("advisors", {}).get(power, {}).is_empty():
			empty_seats += 1
	if empty_seats > 0 and float(n["treasury"]) >= Game.court.advisor_cost(tag, 1) * 2:
		out.append(["Advisor", "%d empty seat(s) on your council. Hire advisors in the Court." % empty_seats, UI.GOOD, func(): open_panel.emit("court")])
	for w in Game.dip.wars_of(tag):
		var side: String = Game.dip.war_side(w, tag)
		var leader: String = w["attackers"][0] if side == "attackers" else w["defenders"][0]
		if leader != tag:
			continue
		var target: String = Game.dip.enemy_leader(w, tag)
		if Game.dip.fully_occupied(w, tag, target):
			out.append(["Enforce", "%s is fully occupied. You can enforce peace on them." % Game.nation_name(target), UI.GOLD, func(): open_peace.emit(int(w["id"]))])
		var uncalled: Array = Game.dip.uncalled_allies(w, tag)
		if uncalled.size() > 0:
			out.append(["Allies", "Allies not yet called into the %s: %s. Call them from the Diplomacy panel." % [w.get("name", "war"),
				", ".join(PackedStringArray(uncalled.map(func(t): return Game.nation_name(t))))], UI.INFO, func(): open_panel.emit("diplomacy")])
	# problems
	var b: Dictionary = Game.eco.budget(tag)
	if float(b["balance"]) < 0.0:
		out.append(["Deficit", "You lose %.1f sanctum a month. Cut the army, forts or advisors, or build markets." % -float(b["balance"]), UI.BAD, func(): open_panel.emit("economy")])
	if n["loans"].size() > 0:
		out.append(["Loans", "%d loan(s) outstanding. Interest eats your income." % n["loans"].size(), UI.BAD, func(): open_panel.emit("economy")])
	if float(n.get("legitimacy", 50.0)) < 50.0:
		out.append(["Legit.", "%s is %d. Below 50 the realm is restless; below 25 you lose power each month." % [Game.court.legitimacy_name(tag), int(n["legitimacy"])], UI.BAD, func(): open_panel.emit("court")])
	if int(n["stability"]) < 0:
		out.append(["Stab.", "Stability is %d. Raise it in the Court." % int(n["stability"]), UI.BAD, func(): open_panel.emit("court")])
	var regs: int = Game.mil.regiment_count(tag)
	var fl: int = Game.mil.land_force_limit(tag)
	if regs > fl:
		out.append(["Limit", "%d regiments, force limit %d. You can't recruit more%s." % [regs, fl, " beyond +50% in wartime" if Game.dip.at_war_any(tag) else ""], UI.BAD, func(): open_panel.emit("production")])
	if int(n["manpower"]) < Game.eco.max_manpower(tag) / 10:
		out.append(["Men", "Manpower is almost gone (%d)." % int(n["manpower"]), UI.BAD, func(): open_panel.emit("military")])
	if float(n["war_exhaustion"]) >= 5.0:
		out.append(["Weary", "War exhaustion %.1f: unrest is rising. Make peace." % float(n["war_exhaustion"]), UI.BAD, func(): open_panel.emit("diplomacy")])
	var worst := -1
	var worst_p := 0.0
	for pid in Game.owned(tag):
		var rp := float(Game.provinces[pid]["rebel_progress"])
		if rp > worst_p:
			worst_p = rp
			worst = pid
	if worst >= 0 and worst_p >= 50.0:
		out.append(["Rebels", "Rebels in %s are %d%% organised." % [Game.provinces[worst]["name"], int(worst_p)], UI.BAD, func(): go_to_province.emit(worst)])
	var portal: int = Game.portal_id()
	if portal >= 0 and Game.provinces[portal]["controller"] == "ENT":
		out.append(["Portal", "Entities from beyond hold the Doomsday Portal and raid Skyfall.", UI.DOOM, func(): go_to_province.emit(portal)])
	return out


func refresh() -> void:
	_dirty = false
	_since = 0.0
	UI.clear(self)
	for a in compute():
		var b := Button.new()
		b.text = a[0]
		b.tooltip_text = a[1]
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_color_override("font_color", a[2])
		b.add_theme_stylebox_override("normal", UI.box(UI.BG_DARK, a[2], 10, 4))
		b.add_theme_stylebox_override("hover", UI.box(UI.BG_CARD, a[2], 10, 4))
		b.pressed.connect(a[3])
		add_child(b)
	reset_size()
