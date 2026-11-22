extends "res://scripts/ui/panel_base.gd"
## One trade node, as in EU4's trade map mode: where its value comes from and goes, who holds trade
## power there, and your merchant there. Opened by clicking a province in the Trade map mode.

signal node_closed
signal go_to_province(id: int)

var node_name = ""


func setup() -> void:
	set_title("Trade node")
	panel_width = 400.0
	max_height = 620.0
	Game.month_ticked.connect(mark_dirty)
	Game.nation_changed.connect(func(t): if t == Game.player_tag: mark_dirty())
	closed.connect(func(): node_closed.emit())


func show_node(name: String) -> void:
	node_name = name
	set_title(name)
	visible = true
	mark_dirty()


func build() -> void:
	if not Game.trade.nodes.has(node_name):
		text("No trade node here.", 13, UI.TEXT_DIM)
		return
	var tag: String = Game.player_tag
	var s: Dictionary = Game.trade.state.get(node_name, {})
	var nd: Dictionary = Game.trade.nodes[node_name]
	text(nd.get("text", ""), 12, UI.TEXT_DIM)
	var home: String = Game.trade.home_node(tag)
	if node_name == home:
		add(UI.label("Your home node: you always collect here, with +%d%% trade power." % int(Game.trade.home_bonus * 100), 12, UI.GOLD, panel_width - 40))
	# value
	section("Value")
	add(UI.kv("Made in the node", "%.2f" % float(s.get("local", 0.0)),
		"Goods produced by the node's provinces, a month%s." % (" (worth %d%% more here)" % int((float(nd.get("value_mult", 1.0)) - 1.0) * 100) if float(nd.get("value_mult", 1.0)) > 1.0 else "")))
	for u in Game.trade.upstream.get(node_name, []):
		var us: Dictionary = Game.trade.state.get(u, {})
		var share_out: float = float(us.get("outgoing", 0.0)) / maxf(1.0, float(Game.trade.nodes[u].get("downstream", []).size()))
		add(UI.kv("  from %s" % u, "%.2f" % share_out, "Value flowing in from upstream: whatever no one collected there."))
	add(UI.kv("Total value", "%.2f a month" % float(s.get("value", 0.0)), "", UI.GOLD))
	var down: Array = nd.get("downstream", [])
	if down.is_empty():
		text("An end node: everything here is collected, none flows on.", 11, UI.TEXT_DIM)
	else:
		add(UI.kv("Flows on to", ", ".join(PackedStringArray(down)) + " (%.2f)" % float(s.get("outgoing", 0.0)),
			"Value not collected here flows downstream, raised by every merchant steering it."))
	# trade power
	section("Trade power")
	var power: Dictionary = s.get("power", {})
	var total: float = float(s.get("total_power", 0.0))
	var tags: Array = power.keys()
	tags.sort_custom(func(a, b): return float(power[a]) > float(power[b]))
	if tags.is_empty():
		text("No one holds trade power here: all of its value flows on.", 12, UI.TEXT_DIM)
	for t in tags.slice(0, 8):
		var share: float = float(power[t]) / maxf(total, 0.001)
		var doing: String = "collects" if Game.trade.collects(t, node_name) else ("steers" if Game.nations[t]["merchants"].get(node_name, "") == "steer" else "passes it on")
		var row = UI.row([UI.swatch(Game.owner_colour(t), Vector2(10, 16)),
			UI.label(Game.nation_name(t), 13, UI.GOLD if t == tag else UI.TEXT), UI.spacer(),
			UI.label(doing, 11, UI.TEXT_DIM), UI.bar(share, 1.0, 90.0, Game.owner_colour(t), 8.0), UI.label("%d%%" % int(share * 100), 12)], 6)
		add(row)
	# your position
	section("You")
	var mine: String = Game.nations[tag]["merchants"].get(node_name, "")
	var my_share: float = Game.trade.share(tag, node_name)
	var collected: float = float(s.get("collected", {}).get(tag, 0.0))
	add(UI.kv("Your trade power", "%.1f (%d%%)" % [Game.trade.power_in(tag, node_name), int(my_share * 100)]))
	add(UI.kv("Your income here", "%.2f a month" % collected, "", UI.GOOD if collected > 0.0 else UI.TEXT))
	add(UI.kv("Merchants free", "%d / %d" % [Game.trade.merchants(tag) - Game.trade.merchants_used(tag), Game.trade.merchants(tag)]))
	if node_name != home:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		if mine == "":
			row.add_child(UI.icon_button("coins", "Collect here", func(): Game.act("trade.send_merchant", [tag, node_name, "collect"]); mark_dirty(),
				"Send a merchant to take your share of this node's value as income (with half trade power away from home).", 16))
			row.add_child(UI.icon_button("trade", "Steer downstream", func(): Game.act("trade.send_merchant", [tag, node_name, "steer"]); mark_dirty(),
				"Send a merchant to push your share of the value downstream, +%d%%, toward your home node." % int(Game.trade.steer_bonus * 100), 16))
			for b in row.get_children():
				var why: String = Game.trade.can_send(tag, node_name, "collect" if "Collect" in b.text else "steer")
				b.disabled = why != ""
				if why != "":
					b.tooltip_text = why
		else:
			row.add_child(UI.label("Your merchant is %s." % ("collecting" if mine == "collect" else "steering trade downstream"), 12, UI.INFO))
			row.add_child(UI.button("Recall", func(): Game.act("trade.recall_merchant", [tag, node_name]); mark_dirty()))
		add(row)
	# provinces
	section("Biggest trade centres")
	var pids: Array = Game.node_provinces.get(node_name, []).duplicate()
	pids.sort_custom(func(a, b): return Game.trade.province_trade_power(a) > Game.trade.province_trade_power(b))
	for pid in pids.slice(0, 5):
		var p: Dictionary = Game.provinces[pid]
		if Game.trade.province_trade_power(pid) <= 0.0:
			continue
		var b = UI.button("%s (%s)  %.1f power" % [p["name"], Game.nation_name(p["owner"]), Game.trade.province_trade_power(pid)], func(): go_to_province.emit(pid))
		b.theme_type_variation = "FlatButton"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		add(b)
