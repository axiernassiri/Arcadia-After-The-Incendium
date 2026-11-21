extends "res://scripts/ui/panel_base.gd"
## The Ledger (J), as in EU4: every nation side by side in a sortable table, and graphs of how they
## have grown since the Incendium (one point each 1 January, from Game.ledger_history).

const COLS := [
	["Nation", "name"], ["Prov.", "provinces"], ["Dev.", "dev"], ["Income", "income"], ["Treasury", "treasury"],
	["Regiments", "regs"], ["Ships", "ships"], ["Tech", "tech"], ["Stab.", "stability"], ["Opinion", "opinion"]]
const METRICS := [["Development", 1], ["Monthly income", 2], ["Regiments", 3], ["Provinces", 4]]

var mode = "table"
var sort_key = "dev"
var sort_desc = true
var metric = 1


func setup() -> void:
	set_title("Ledger")
	panel_width = 760.0
	max_height = 640.0
	Game.month_ticked.connect(mark_dirty)


func build() -> void:
	var tabs = HBoxContainer.new()
	for m in [["table", "Nations"], ["graph", "History"]]:
		var b = UI.button(m[1], func(): mode = m[0]; mark_dirty())
		b.toggle_mode = true
		b.button_pressed = mode == m[0]
		tabs.add_child(b)
	add(tabs)
	if mode == "table":
		_table()
	else:
		_graph()


func _rows() -> Array:
	var me: String = Game.player_tag
	var out: Array = []
	for t in Game.nations:
		var n: Dictionary = Game.nations[t]
		if not n["alive"] or t in ["REB", "ENT"]:
			continue
		var tech: int = int(n["tech"][0]) + int(n["tech"][1]) + int(n["tech"][2])
		out.append({"tag": t, "name": n["short"], "provinces": Game.owned(t).size(), "dev": Game.nation_dev(t),
			"income": float(n.get("last_income", 0.0)), "treasury": float(n["treasury"]), "regs": Game.mil.regiment_count(t),
			"ships": Game.mil.ship_count(t), "tech": tech, "stability": int(n["stability"]),
			"opinion": 999.0 if t == me else Game.dip.opinion(t, me)})
	var key: String = sort_key
	out.sort_custom(func(a, b):
		if a[key] is String:
			return (String(a[key]) < String(b[key])) != sort_desc
		return (float(a[key]) > float(b[key])) == sort_desc)
	return out


func _table() -> void:
	text("Click a column to sort. Opinion is what they think of you.", 12, UI.TEXT_DIM)
	var grid = GridContainer.new()
	grid.columns = COLS.size()
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 3)
	for c in COLS:
		var arrow := ("  ▼" if sort_desc else "  ▲") if sort_key == c[1] else ""
		var b = UI.button(c[0] + arrow, func():
			if sort_key == c[1]:
				sort_desc = not sort_desc
			else:
				sort_key = c[1]
				sort_desc = c[1] != "name"
			mark_dirty(), "Sort by " + String(c[0]).to_lower())
		b.theme_type_variation = "FlatButton"
		b.add_theme_font_size_override("font_size", 12)
		grid.add_child(b)
	for r in _rows():
		var mine: bool = r["tag"] == Game.player_tag
		var col: Color = UI.GOLD if mine else UI.TEXT
		var nm = UI.row([UI.swatch(Game.owner_colour(r["tag"]), Vector2(10, 12)), UI.label(r["name"], 13, col)], 6)
		nm.custom_minimum_size.x = 130
		grid.add_child(nm)
		for v in [str(r["provinces"]), str(r["dev"]), "%.1f" % r["income"], str(int(r["treasury"])), str(r["regs"]),
				str(r["ships"]), str(r["tech"]), "%+d" % r["stability"], "—" if mine else "%+d" % int(r["opinion"])]:
			var l = UI.label(v, 13, col)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(l)
	add(grid)


func _graph() -> void:
	var picks = HBoxContainer.new()
	for m in METRICS:
		var b = UI.button(m[0], func(): metric = m[1]; mark_dirty())
		b.toggle_mode = true
		b.button_pressed = metric == m[1]
		b.theme_type_variation = "FlatButton"
		picks.add_child(b)
	add(picks)
	var hist: Dictionary = Game.ledger_history
	var series: Array = []
	var y_max := 1.0
	var x_min := 1e9
	var x_max := -1e9
	for t in hist:
		if not Game.nations.has(t):
			continue
		var pts: Array = []
		for row in hist[t]:
			pts.append(Vector2(float(row[0]), float(row[metric])))
			y_max = maxf(y_max, float(row[metric]))
			x_min = minf(x_min, float(row[0]))
			x_max = maxf(x_max, float(row[0]))
		if pts.size() > 0:
			series.append([t, pts])
	if series.is_empty() or x_max <= x_min:
		text("The ledger records every nation each 1 January. Come back after the first new year.", 12, UI.TEXT_DIM)
		return
	var chart := Control.new()
	chart.custom_minimum_size = Vector2(panel_width - 40, 320)
	var me: String = Game.player_tag
	chart.draw.connect(func():
		var r := Rect2(Vector2(36, 6), chart.size - Vector2(44, 26))
		chart.draw_rect(Rect2(Vector2.ZERO, chart.size), Color(0.02, 0.02, 0.03, 0.85))
		var font: Font = Tokens.font("body")
		for i in 5:
			var yv := y_max * i / 4.0
			var yy := r.end.y - r.size.y * i / 4.0
			chart.draw_line(Vector2(r.position.x, yy), Vector2(r.end.x, yy), Color(1, 1, 1, 0.07))
			chart.draw_string(font, Vector2(2, yy + 4), "%d" % int(yv) if y_max >= 10 else "%.1f" % yv, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UI.TEXT_DIM)
		chart.draw_string(font, Vector2(r.position.x, chart.size.y - 4), str(int(x_min)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UI.TEXT_DIM)
		chart.draw_string(font, Vector2(r.end.x - 28, chart.size.y - 4), str(int(x_max)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UI.TEXT_DIM)
		for s in series:
			var pts := PackedVector2Array()
			for p in s[1]:
				pts.append(Vector2(r.position.x + (p.x - x_min) / (x_max - x_min) * r.size.x, r.end.y - p.y / y_max * r.size.y))
			var col: Color = Game.owner_colour(s[0])
			if pts.size() >= 2:
				chart.draw_polyline(pts, col, 3.0 if s[0] == me else 1.5, true)
			elif pts.size() == 1:
				chart.draw_circle(pts[0], 2.5, col))
	add(chart)
	# a legend, biggest first
	var legend = HFlowContainer.new()
	var tags: Array = series.map(func(s): return s[0])
	tags.sort_custom(func(a, b): return float(hist[a].back()[metric]) > float(hist[b].back()[metric]))
	for t in tags:
		legend.add_child(UI.row([UI.swatch(Game.owner_colour(t), Vector2(10, 10)), UI.label(Game.nations[t]["short"], 11,
			UI.GOLD if t == me else UI.TEXT_DIM)], 4))
	add(legend)
