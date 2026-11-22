extends "res://scripts/ui/panel_base.gd"
## Economy: monthly budget in sanctum, maintenance sliders, loans, the treasury over time and buildings.


func setup() -> void:
	set_title("Economy")
	Game.month_ticked.connect(mark_dirty)
	Game.nation_changed.connect(func(t): if t == Game.player_tag: mark_dirty())


func build() -> void:
	var tag = Game.player_tag
	var n: Dictionary = Game.nations[tag]
	var b: Dictionary = Game.eco.budget(tag)
	add(UI.row([UI.heading("Treasury", 18), UI.spacer(), UI.label("%s sanctum" % UI.money(n["treasury"]), 18, UI.GOLD)]))
	var bal: float = b["balance"]
	add(UI.kv("Monthly balance", UI.signed(bal, 2), "", UI.GOOD if bal >= 0.0 else UI.BAD))
	section("Income (per month)")
	add(UI.kv("Taxes", "%.2f" % b["tax"], "Tax development x (1 + tax modifiers) / 12. Uncored and occupied provinces pay less or nothing.\nTax modifiers:\n" + Game.mods.breakdown(tag, ["tax_mod"])))
	add(UI.kv("Production", "%.2f" % b["production"], "Goods made x their market price x (1 + production modifiers) / 12.\nProduction modifiers:\n" + Game.mods.breakdown(tag, ["production_mod"])))
	add(UI.kv("Trade", "%.2f" % b["trade"], "What your merchants collect in trade nodes. See the Trade panel.\nTrade efficiency:\n" + Game.mods.breakdown(tag, ["trade_efficiency"])))
	if float(b["subjects"]) > 0.0:
		add(UI.kv("Vassals", "%.2f" % b["subjects"]))
	add(UI.kv("Total income", "%.2f" % b["income"], "", UI.GOOD))
	section("Expenses (per month)")
	add(UI.kv("Army maintenance", "%.2f" % b["army"], "Each regiment's upkeep x the army slider. Over the force limit costs more.\nMaintenance modifiers:\n" + Game.mods.breakdown(tag, ["land_maintenance_mod"])))
	add(UI.kv("Navy maintenance", "%.2f" % b["navy"], "Maintenance modifiers:\n" + Game.mods.breakdown(tag, ["naval_maintenance_mod"])))
	add(UI.kv("Fort upkeep", "%.2f" % b["forts"]))
	add(UI.kv("Administration", "%.2f" % b["admin"], "1.2% of your total development a month."))
	if float(b["colonies"]) > 0.0:
		add(UI.kv("Colonies", "%.2f" % b["colonies"]))
	if float(b["missionaries"]) > 0.0:
		add(UI.kv("Missionaries", "%.2f" % b["missionaries"]))
	if float(b["interest"]) > 0.0:
		add(UI.kv("Loan interest", "%.2f" % b["interest"], "", UI.BAD))
	if float(b["overlord"]) > 0.0:
		add(UI.kv("Tribute to overlord", "%.2f" % b["overlord"], "", UI.BAD))
	add(UI.kv("Total expenses", "%.2f" % b["expenses"], "", UI.BAD))

	section("Maintenance")
	for key in ["land", "naval"]:
		var sl = HSlider.new()
		sl.min_value = 0.5
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = float(n["maintenance"][key])
		sl.custom_minimum_size = Vector2(180, 18)
		sl.focus_mode = Control.FOCUS_NONE
		sl.tooltip_text = "Lower maintenance saves sanctum, but lowers morale and slows reinforcement."
		sl.value_changed.connect(func(v): Game.act("set_maintenance", [tag, key, v]))
		var lbl = UI.label("%s %d%%" % ["Army" if key == "land" else "Navy", int(float(n["maintenance"][key]) * 100)], 13)
		lbl.custom_minimum_size.x = 120
		add(UI.row([lbl, sl]))

	section("Loans")
	var rate: float = Game.eco.loan_rate(tag)
	text("%d loan(s), %d sanctum owed at %.1f%% a year. Running out of money takes loans automatically; with %d loans the realm goes bankrupt." % [
		n["loans"].size(), int(_sum(n["loans"])), rate * 100.0, Game.eco.MAX_LOANS], 12, UI.TEXT_DIM)
	add(UI.row([
		UI.action("Take a loan (+%d)" % Game.eco.loan_size(tag), "" if n["loans"].size() < Game.eco.MAX_LOANS else "Too many loans.",
			func(): Game.act("eco.take_loan", [tag]); mark_dirty()),
		UI.action("Repay one", "" if not n["loans"].is_empty() and float(n["treasury"]) >= float(n["loans"][0]) else "Nothing to repay, or not enough sanctum.",
			func(): Game.act("eco.repay_loan", [tag]); mark_dirty())]))

	var hist: Array = Game.eco.history.get(tag, [])
	if hist.size() >= 2:
		section("Treasury over the last %d months" % hist.size())
		add(_chart(hist, panel_width - 40.0, 90.0))

	section("Buildings")
	var counts = {}
	var building: Array = []
	for pid in Game.owned(tag):
		var p: Dictionary = Game.provinces[pid]
		for bid in p["buildings"]:
			counts[bid] = int(counts.get(bid, 0)) + 1
		if not p["construction"].is_empty():
			building.append([p["name"], p["construction"]])
	if counts.is_empty():
		text("No buildings yet. Select a province you own to build.", 12, UI.TEXT_DIM)
	for bid in counts:
		add(UI.kv(Game.building_data[bid]["name"], str(counts[bid]), Game.building_data[bid].get("text", "")))
	for c in building:
		var left: int = maxi(0, int((int(c[1]["done"]) - Game.day_index) / 30))
		add(UI.kv("Building %s in %s" % [Game.building_data[c[1]["id"]]["name"], c[0]], "%d months" % left, "", UI.INFO))


func _sum(a: Array) -> float:
	var t = 0.0
	for x in a:
		t += float(x)
	return t


func _chart(data: Array, w: float, h: float) -> Control:
	var c = Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var lo = 0.0
		var hi = 1.0
		for v in data:
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
		c.draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), Color(0.05, 0.06, 0.08))
		var zero_y = h - (0.0 - lo) / (hi - lo) * h
		c.draw_line(Vector2(0, zero_y), Vector2(w, zero_y), Color(1, 1, 1, 0.2), 1.0)
		var pts = PackedVector2Array()
		for i in data.size():
			pts.append(Vector2(i * w / float(data.size() - 1), h - (float(data[i]) - lo) / (hi - lo) * h))
		c.draw_polyline(pts, UI.GOLD, 2.0)
		var font: Font = ThemeDB.fallback_font
		c.draw_string(font, Vector2(4, 14), UI.money(hi), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UI.TEXT_DIM)
		c.draw_string(font, Vector2(4, h - 4), UI.money(lo), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UI.TEXT_DIM))
	return c
