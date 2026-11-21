extends "res://scripts/ui/panel_base.gd"
## Trade: nodes, your share of trade power, merchants, and market prices.


signal node_selected(node: String)


func setup() -> void:
	set_title("Trade")
	panel_width = 440.0
	Game.month_ticked.connect(mark_dirty)
	Game.nation_changed.connect(func(t): if t == Game.player_tag: mark_dirty())


func build() -> void:
	var tag = Game.player_tag
	var home: String = Game.trade.home_node(tag)
	add(UI.kv("Trade income", "%.2f sanctum a month" % float(Game.trade.income.get(tag, 0.0)), "", UI.GOLD))
	add(UI.kv("Home node", home, "You always collect here, with a %d%% trade power bonus." % int(Game.trade.home_bonus * 100)))
	add(UI.kv("Merchants", "%d / %d" % [Game.trade.merchants_used(tag), Game.trade.merchants(tag)],
		"Send merchants to collect in other nodes (half trade power there) or to steer trade downstream toward your home node (+10% value)."))
	add(UI.kv("Trade efficiency", "%+d%%" % int(Game.mods.nat(tag, "trade_efficiency") * 100)))
	text("Value made in each node flows downstream unless someone collects it. In the Trade map mode, click any province to open its node.", 12, UI.TEXT_DIM)
	for k in Game.trade.order:
		var s: Dictionary = Game.trade.state.get(k, {})
		var share: float = Game.trade.share(tag, k)
		var mine: String = Game.nations[tag]["merchants"].get(k, "")
		var c = UI.card(UI.GOLD if k == home else UI.BORDER)
		var v = VBoxContainer.new()
		c.add_child(v)
		var down: Array = Game.trade.nodes[k].get("downstream", [])
		var open_b = UI.icon_button("map", "", func(): node_selected.emit(k), "Show this node on the trade map", 14)
		open_b.theme_type_variation = "FlatButton"
		v.add_child(UI.row([UI.heading(k, 15), open_b, UI.spacer(), UI.label("%.1f value" % float(s.get("value", 0.0)), 13)]))
		v.add_child(UI.label("Flows to: %s" % (", ".join(down) if down.size() > 0 else "nowhere (end node)"), 11, UI.TEXT_DIM))
		var bar = UI.bar(share, 1.0, 200.0, UI.GOOD)
		v.add_child(UI.row([UI.label("Your power %d%%" % int(share * 100), 12), bar]))
		var top = _top_holders(s.get("power", {}), float(s.get("total_power", 0.0)))
		if top != "":
			v.add_child(UI.label(top, 11, UI.TEXT_DIM, panel_width - 60))
		var collected = float(s.get("collected", {}).get(tag, 0.0))
		var status = "collecting %.2f" % collected if Game.trade.collects(tag, k) else ("steering" if mine == "steer" else "not collecting")
		v.add_child(UI.label("You: " + status, 12, UI.GOOD if collected > 0.0 else UI.TEXT_DIM))
		if k != home:
			var row = HBoxContainer.new()
			if mine == "":
				row.add_child(UI.action("Collect", Game.trade.can_send(tag, k, "collect"), func(): Game.trade.send_merchant(tag, k, "collect"); mark_dirty()))
				row.add_child(UI.action("Steer", Game.trade.can_send(tag, k, "steer"), func(): Game.trade.send_merchant(tag, k, "steer"); mark_dirty()))
			else:
				row.add_child(UI.button("Recall merchant (%s)" % mine, func(): Game.trade.recall_merchant(tag, k); mark_dirty()))
			v.add_child(row)
		add(c)
	section("Market prices")
	var keys: Array = Game.goods.keys()
	keys.sort_custom(func(a, b): return Game.eco.price(a) > Game.eco.price(b))
	var grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	for k in keys:
		var hist: Array = Game.eco.market.get(k, {}).get("history", [])
		var p: float = Game.eco.price(k)
		var trend = ""
		var col = UI.TEXT
		if hist.size() >= 2:
			var d = float(hist[hist.size() - 1]) - float(hist[maxi(0, hist.size() - 7)])
			trend = "up" if d > 0.05 else ("down" if d < -0.05 else "")
			col = UI.GOOD if d > 0.05 else (UI.BAD if d < -0.05 else UI.TEXT)
		grid.add_child(UI.swatch(Color(Game.goods[k].get("colour", "#888888")), Vector2(12, 12)))
		grid.add_child(UI.label(Game.goods[k].get("name", k), 12))
		grid.add_child(UI.label("%.2f" % p, 12, col))
		grid.add_child(UI.label(trend, 11, col))
	add(grid)


func _top_holders(power: Dictionary, total: float) -> String:
	if total <= 0.0:
		return ""
	var tags: Array = power.keys()
	tags.sort_custom(func(a, b): return float(power[a]) > float(power[b]))
	var parts: PackedStringArray = []
	for i in mini(3, tags.size()):
		parts.append("%s %d%%" % [Game.nation_name(tags[i]), int(float(power[tags[i]]) / total * 100)])
	return "Trade power: " + ", ".join(parts)
