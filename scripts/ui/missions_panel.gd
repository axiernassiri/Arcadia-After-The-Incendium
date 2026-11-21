extends "res://scripts/ui/panel_base.gd"
## The mission tree, EU4-style: columns of missions, arrows from each mission to the ones it unlocks.

const CARD := Vector2(176, 124)
const GAP := Vector2(16, 26)
const STATUS_TEXT := {"ready": "Ready to claim!", "open": "In progress", "locked": "Locked", "done": "Completed"}


func setup() -> void:
	set_title("Missions")
	panel_width = 5 * (CARD.x + GAP.x) + 40.0
	max_height = 620.0
	Game.month_ticked.connect(mark_dirty)
	Game.nation_changed.connect(func(t): if t == Game.player_tag: mark_dirty())


func ready_count() -> int:
	var c = 0
	if Game.player_tag == "":
		return 0
	for m in Game.missions_for(Game.player_tag):
		if Game.mission_state(Game.player_tag, m) == "ready":
			c += 1
	return c


func _pos(m: Dictionary) -> Vector2:
	return Vector2(int(m.get("column", 0)) * (CARD.x + GAP.x), int(m.get("row", 0)) * (CARD.y + GAP.y))


func build() -> void:
	var tag = Game.player_tag
	var ms: Array = Game.missions_for(tag)
	var done = 0
	for m in ms:
		if Game.mission_state(tag, m) == "done":
			done += 1
	text("%d of %d missions completed. Hover a mission to see what it needs and gives." % [done, ms.size()], 12, UI.TEXT_DIM)
	var canvas = Control.new()
	var size = Vector2.ZERO
	var by_id = {}
	for m in ms:
		by_id[m["id"]] = m
		size = size.max(_pos(m) + CARD)
	canvas.custom_minimum_size = size + Vector2(4, 4)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(func():
		for m in ms:
			for r in m.get("requires", []):
				if not by_id.has(r):
					continue
				var a: Vector2 = _pos(by_id[r]) + Vector2(CARD.x / 2.0, CARD.y)
				var b: Vector2 = _pos(m) + Vector2(CARD.x / 2.0, 0)
				var col = UI.GOOD if Game.nations[tag]["missions_done"].has(r) else Color(0.45, 0.42, 0.35)
				var mid = Vector2(b.x, a.y + GAP.y / 2.0)
				canvas.draw_polyline(PackedVector2Array([a, Vector2(a.x, mid.y), mid, b]), col, 2.0)
				canvas.draw_colored_polygon(PackedVector2Array([b, b + Vector2(-5, -7), b + Vector2(5, -7)]), col))
	for m in ms:
		var status: String = Game.mission_state(tag, m)
		var col: Color = {"ready": UI.GOOD, "open": UI.BORDER, "locked": Color(0.3, 0.3, 0.3), "done": Color(0.35, 0.55, 0.35)}[status]
		var card = PanelContainer.new()
		card.add_theme_stylebox_override("panel", UI.box(Color(0.12, 0.14, 0.17) if status != "done" else Color(0.12, 0.17, 0.13), col, 5, 6))
		card.position = _pos(m)
		card.custom_minimum_size = CARD
		card.size = CARD
		card.mouse_filter = Control.MOUSE_FILTER_PASS
		var v = VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		card.add_child(v)
		var t = UI.label(m["title"], 13, UI.GOLD if status != "locked" else UI.TEXT_DIM, CARD.x - 14)
		v.add_child(t)
		v.add_child(UI.label(STATUS_TEXT[status], 11, col if status != "locked" else UI.TEXT_DIM))
		var lines: PackedStringArray = [m.get("text", ""), ""]
		var met = 0
		for c in m.get("conditions", []):
			var ok: bool = Game.check_condition(c, tag)
			if ok:
				met += 1
			lines.append(("[done] " if ok else "[needs] ") + Game.describe_condition(c))
		var fx: String = Game.describe_effects(m.get("rewards", []), tag)
		if fx != "":
			lines.append("")
			lines.append("Reward: " + fx)
		var req: PackedStringArray = []
		for r in m.get("requires", []):
			req.append(by_id.get(r, {}).get("title", r))
		if req.size() > 0:
			lines.append("After: " + ", ".join(req))
		card.tooltip_text = "\n".join(lines)
		if status in ["open", "ready"]:
			v.add_child(UI.label("%d / %d goals" % [met, m.get("conditions", []).size()], 11, UI.TEXT))
		if status == "ready":
			v.add_child(UI.button("Claim reward", func(): Game.claim_mission(tag, m["id"]); mark_dirty()))
		elif fx != "" and status != "done":
			v.add_child(UI.label(fx, 10, UI.TEXT_DIM, CARD.x - 14))
		canvas.add_child(card)
	add(canvas)
