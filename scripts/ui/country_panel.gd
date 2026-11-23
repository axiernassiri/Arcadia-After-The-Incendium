extends "res://scripts/ui/panel_base.gd"
## One nation's diplomacy view: who they are, how they see you, their friends and enemies, and the
## diplomatic actions you can take. Opens on right-click.

signal peace_requested(war_id: int)

var tag = ""
var _msg = ""


func setup() -> void:
	set_title("Diplomacy")
	panel_width = 440.0
	max_height = 640.0
	Game.month_ticked.connect(mark_dirty)
	Game.war_changed.connect(mark_dirty)
	Game.nation_changed.connect(func(_t): mark_dirty())


func show_nation(t: String) -> void:
	tag = t
	_msg = ""
	visible = true
	mark_dirty()


func build() -> void:
	if not Game.nations.has(tag):
		return
	var me = Game.player_tag
	var o: Dictionary = Game.nations[tag]
	set_title(o["short"])
	add(UI.row([UI.swatch(o["colour"], Vector2(22, 22)), UI.heading(o["name"], 18)]))
	if not o["alive"]:
		text("This nation no longer exists.", 13, UI.BAD)
		return
	var gov: Dictionary = Game.governments.get(o["government"], {})
	text("%s (%s). Capital: %s." % [gov.get("name", ""), gov.get("rank", ""),
		Game.provinces[Game.capital_of(tag)]["name"] if Game.capital_of(tag) >= 0 else "-"], 12, UI.TEXT_DIM)
	add(UI.kv("Ruler", Game.court.describe(o["ruler"], o["power_names"])))
	if not o["heir"].is_empty():
		add(UI.kv("Heir", Game.court.describe(o["heir"], o["power_names"])))
	add(UI.kv("Provinces / development", "%d / %d" % [Game.owned(tag).size(), Game.nation_dev(tag)]))
	add(UI.kv("Army", "%d regiments, strength %.0f" % [Game.mil.regiment_count(tag), Game.mil.nation_strength(tag)]))
	add(UI.kv("Technology", "%d / %d / %d" % [int(o["tech"][0]), int(o["tech"][1]), int(o["tech"][2])]))
	add(UI.kv("Culture / faith / people", "%s / %s / %s" % [o["culture"], o["religion"], o["ethnicity"]]))
	if o["playable"] and o["difficulty"] != "":
		add(UI.kv("Difficulty to play", o["difficulty"]))
	if tag == me:
		_their_relations(o)
		return
	section("Relations with you")
	var op: float = Game.dip.opinion(tag, me)
	var lines: PackedStringArray = []
	for r in Game.dip.opinion_breakdown(tag, me):
		lines.append("%s: %+d" % [r[0], int(r[1])])
	var opl = UI.tip_label("Their opinion of you: %+d" % int(op), "\n".join(lines), 14, UI.GOOD if op >= 0 else UI.BAD)
	add(opl)
	add(UI.label("Your opinion of them: %+d" % int(Game.dip.opinion(me, tag)), 12, UI.TEXT_DIM))
	var r: Dictionary = Game.dip.rel(me, tag)
	var status: PackedStringArray = []
	if Game.dip.at_war(me, tag):
		status.append("at war")
	if r["alliance"]:
		status.append("allied")
	if r["marriage"]:
		status.append("royal marriage")
	if Game.dip.rel(tag, me)["access"]:
		status.append("you have military access")
	if r["rival"]:
		status.append("your rival")
	if Game.dip.truce(me, tag):
		status.append("truce until " + Game.date_from_index(int(r["truce_until"])))
	if o["overlord"] == me:
		status.append("your vassal")
	if status.size() > 0:
		text(", ".join(status).capitalize(), 12, UI.INFO)
	var claims = 0
	for pid in Game.owned(tag):
		if Game.nations[me]["claims"].has(pid):
			claims += 1
	if claims > 0:
		text("You have claims on %d of their provinces." % claims, 12, UI.TEXT_DIM)
	if _msg != "":
		text(_msg, 13, UI.GOLD)
	section("Actions")
	_act("improve", "Stop improving relations" if r["improving"] else "Improve relations (diplomat)", "", "+3 opinion a month, up to +100.")
	if r["alliance"]:
		_act("break_alliance", "Break alliance", "")
	else:
		_act("alliance", "Form alliance", "alliance")
	if not r["marriage"]:
		_act("marriage", "Royal marriage", "marriage")
	if not Game.dip.rel(tag, me)["access"]:
		_act("access", "Request military access", "access")
	_act("rival", "End rivalry" if r["rival"] else "Declare rival", "", "Rivals hate each other. Gives a casus belli to humiliate them.")
	_act("claim", "Fabricate a claim (25 %s)" % Game.nations[me]["power_names"][1], "", "A claim gives a casus belli and makes that province cheaper in peace deals.")
	_act("insult", "Insult (10 %s)" % Game.nations[me]["power_names"][1], "", "-50 opinion.")
	_act("guarantee", "Revoke guarantee" if r.get("guarantee", false) else "Guarantee independence", "",
		"You will join any war declared on them. They like you for it (+25 opinion).")
	_act("warn", "Withdraw warning" if r.get("warned", false) else "Warn", "",
		"If they declare war on any of your neighbours, you join the war against them. They won't like it (-20 opinion).")
	_act("support_rebels", "Support rebels (%d sanctum)" % int(Game.dip.SUPPORT_REBELS_COST), "",
		"Arm the malcontents in their three most restless provinces: +3 unrest and more rebel support for two years. -40 opinion. Once a year.")
	_sell_options(me)
	var gs: Array = Game.dip.guarantors_of(tag)
	if gs.size() > 0:
		var gn: PackedStringArray = []
		for t2 in gs:
			gn.append(Game.nations[t2]["short"])
		text("Guaranteed by: " + ", ".join(gn), 12, UI.INFO)
	if o["overlord"] == me:
		_act("integrate", "Integrate vassal (%d %s)" % [Game.dip.integrate_cost(tag), Game.nations[me]["power_names"][1]], "")
	elif o["overlord"] == "":
		_act("vassalize", "Demand vassalage", "vassalize")
	section("War")
	if Game.dip.at_war(me, tag):
		var w_id: int = int(Game.dip._war_pairs.get(me + "|" + tag, -1))
		add(UI.button("Negotiate peace", func(): peace_requested.emit(w_id)))
	else:
		var cbs: Array = Game.dip.casus_belli(me, tag)
		if cbs.is_empty():
			text("No casus belli. Declaring war anyway costs 2 stability and angers everyone.", 12, UI.BAD)
		else:
			var names: PackedStringArray = []
			for cb in cbs:
				names.append(cb["name"])
			text("Casus belli: " + ", ".join(names), 12, UI.GOOD)
		var allies: Array = Game.dip.allies_of(tag)
		if allies.size() > 0:
			var an: PackedStringArray = []
			for a in allies:
				an.append(Game.nation_name(a))
			text("Their allies will be called in: " + ", ".join(an), 12, UI.BAD)
		_act("war", "Declare war", "", "Starts a war. Your allies are called in.")
	_their_relations(o)


func _sell_options(me: String) -> void:
	## Sell them one of our provinces next to their land (EU4's "sell province").
	var pids: Array = Game.dip.sellable(me, tag)
	if pids.is_empty():
		return
	section("Sell land")
	var human: bool = Game.is_human(tag)
	for pid in pids.slice(0, 3):
		var price: int = Game.dip.sale_price(pid)
		var acc: Array = Game.dip.sale_acceptance(me, tag, pid)
		var parts: PackedStringArray = []
		for r in acc[1]:
			parts.append("%s: %+d" % [r[0], int(r[1])])
		var tip: String
		if human:
			tip = "%s is played by a person: they decide." % Game.nation_name(tag)
		else:
			tip = "They buy when the total is above 0.\n" + "\n".join(parts) + "\nTotal: %+d" % int(acc[0])
		var extra := "  (their choice)" if human else ("  (likely yes)" if float(acc[0]) > 0.0 else "  (likely no)")
		var b = UI.action("Sell %s (%d dev) for %d sanctum%s" % [Game.provinces[pid]["name"], Game.total_dev(pid), price, extra], "",
			func(): _msg = String(Game.act("dip.sell_province", [me, tag, pid])); mark_dirty(), tip)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.x = panel_width - 40
		add(b)


func _act(action: String, label: String, accept_key: String, tip: String = "") -> void:
	var me = Game.player_tag
	var why: String = Game.dip.can_act(action, me, tag)
	var extra = ""
	if accept_key != "" and why == "" and Game.is_human(tag):
		tip = "%s is played by a person: they get your offer and answer it themselves." % Game.nation_name(tag)
		extra = "  (their choice)"
	elif accept_key != "" and why == "":
		var acc: Array = Game.dip.acceptance(accept_key, me, tag)
		var parts: PackedStringArray = []
		for r in acc[1]:
			parts.append("%s: %+d" % [r[0], int(r[1])])
		tip = "They accept when the total is above 0.\n" + "\n".join(parts) + "\nTotal: %+d" % int(acc[0])
		extra = "  (likely yes)" if float(acc[0]) > 0.0 else "  (likely no)"
	var b = UI.action(label + extra, why, func(): _msg = Game.act("dip.act", [action, me, tag]); mark_dirty(), tip)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.x = panel_width - 40
	add(b)


func _their_relations(o: Dictionary) -> void:
	section("Their diplomacy")
	var allies: Array = Game.dip.allies_of(tag)
	var parts: PackedStringArray = []
	for a in allies:
		parts.append(Game.nation_name(a))
	add(UI.kv("Allies", ", ".join(parts) if parts.size() > 0 else "none"))
	var subs: PackedStringArray = []
	for s in o["subjects"]:
		subs.append(Game.nation_name(s))
	add(UI.kv("Vassals", ", ".join(subs) if subs.size() > 0 else "none"))
	if o["overlord"] != "":
		add(UI.kv("Overlord", Game.nation_name(o["overlord"])))
	var rivals: PackedStringArray = []
	for b in o["relations"]:
		if o["relations"][b]["rival"]:
			rivals.append(Game.nation_name(b))
	add(UI.kv("Rivals", ", ".join(rivals) if rivals.size() > 0 else "none"))
	for w in Game.dip.wars_of(tag):
		add(UI.kv("At war", w["name"], "", UI.BAD))
	section("Opinions of other nations")
	for t in Game.nations:
		if t == tag or not Game.nations[t]["alive"]:
			continue
		var op: float = Game.dip.opinion(tag, t)
		add(UI.kv(Game.nation_name(t), "%+d" % int(op), "", UI.GOOD if op >= 0 else UI.BAD))
