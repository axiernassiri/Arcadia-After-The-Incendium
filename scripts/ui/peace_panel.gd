extends "res://scripts/ui/panel_base.gd"
## Peace negotiation: pick an enemy, then demand provinces, sanctum, vassalage or annexation (or offer
## them concessions if you're losing). Shows the cost in war score and whether they'll accept.

var war_id = -1
var target = ""
var give = false
var demands: Array = []
var _msg = ""


func setup() -> void:
	set_title("Peace Negotiation")
	panel_width = 460.0
	max_height = 620.0
	Game.war_changed.connect(func(): if not Game.wars.has(war_id): visible = false)
	Game.month_ticked.connect(mark_dirty)


func open_war(id: int) -> void:
	war_id = id
	var w: Dictionary = Game.wars.get(id, {})
	if w.is_empty():
		return
	target = Game.dip.enemy_leader(w, Game.player_tag)
	demands = []
	give = false
	_msg = ""
	visible = true
	mark_dirty()


func build() -> void:
	var w: Dictionary = Game.wars.get(war_id, {})
	if w.is_empty():
		text("This war is over.", 13)
		return
	var me = Game.player_tag
	var ws: float = Game.dip.score_for(w, me)
	add(UI.heading(w["name"], 16))
	add(UI.row([UI.label("Your war score %+d" % int(ws), 15, UI.GOOD if ws >= 0 else UI.BAD), UI.bar(ws + 100.0, 200.0, 200.0, UI.GOOD if ws >= 0 else UI.BAD)]))
	var side: String = Game.dip.war_side(w, me)
	var other = "defenders" if side == "attackers" else "attackers"
	var tr = HBoxContainer.new()
	tr.add_child(UI.label("Negotiate with:", 13))
	for t in w[other]:
		var b = UI.button(Game.nation_name(t), func(): target = t; demands = []; mark_dirty())
		b.toggle_mode = true
		b.button_pressed = t == target
		tr.add_child(b)
	add(tr)
	if target != w[other][0]:
		text("A separate peace takes only this nation out of the war.", 11, UI.TEXT_DIM)
	var mode = HBoxContainer.new()
	var b1 = UI.button("Make demands", func(): give = false; demands = []; mark_dirty())
	b1.toggle_mode = true
	b1.button_pressed = not give
	var b2 = UI.button("Offer concessions", func(): give = true; demands = []; mark_dirty())
	b2.toggle_mode = true
	b2.button_pressed = give
	mode.add_child(b1)
	mode.add_child(b2)
	add(mode)
	var demander: String = target if give else me
	var loser: String = me if give else target
	section("Provinces" if not give else "Provinces you give")
	var pids: Array = Game.owned(loser).duplicate()
	pids.sort_custom(func(a, b): return Game.total_dev(a) > Game.total_dev(b))
	for pid in pids:
		var d = {"type": "province", "pid": pid}
		var on = _has(d)
		var p: Dictionary = Game.provinces[pid]
		var occ = " (occupied)" if Game.dip.war_side(w, p["controller"]) == Game.dip.war_side(w, demander) else ""
		var cost: float = Game.dip.peace_cost(w, demander, loser, [d])
		var why: String = Game.dip.can_demand(w, demander, loser, d)
		var cb = CheckBox.new()
		cb.text = "%s, %d dev%s: %d%%" % [p["name"], Game.total_dev(pid), occ, int(cost)]
		cb.button_pressed = on
		cb.disabled = why != ""
		cb.tooltip_text = why
		cb.focus_mode = Control.FOCUS_NONE
		cb.toggled.connect(func(v): _toggle(d, v))
		add(cb)
	section("Other terms")
	var gold_row = HBoxContainer.new()
	gold_row.add_child(UI.label("Sanctum (share of a year's income):", 13))
	var payer: String = me if give else loser
	for pct in [0, 10, 25, 50, 100]:
		var gb = UI.button("%d%%" % pct if pct > 0 else "none", func(): _set_gold(pct))
		gb.toggle_mode = true
		gb.button_pressed = _gold() == pct
		gb.tooltip_text = "%d sanctum from %s." % [Game.dip.gold_amount(payer, pct / 100.0), Game.nation_name(payer)] if pct > 0 else "No payment."
		gold_row.add_child(gb)
	add(gold_row)
	if not give:
		for t in ["vassalize", "annex"]:
			var d2 = {"type": t}
			var cb2 = CheckBox.new()
			cb2.text = ("Become our vassal" if t == "vassalize" else "Annex them completely") + ": %d%%" % int(Game.dip.peace_cost(w, demander, loser, [d2]))
			cb2.button_pressed = _has(d2)
			var why2: String = Game.dip.can_demand(w, demander, loser, d2)
			cb2.disabled = why2 != ""
			cb2.tooltip_text = why2
			cb2.focus_mode = Control.FOCUS_NONE
			cb2.toggled.connect(func(v): _toggle(d2, v))
			add(cb2)
	section("Their answer")
	var cost_all: float = Game.dip.peace_cost(w, demander, loser, demands)
	add(UI.kv("Cost of these terms", "%d%%" % int(cost_all)))
	if not give:
		var ae: Array = Game.dip.ae_preview(w, me, target, demands)
		if float(ae[0]) > 0.0:
			var mine := Game.dip.aggressive_expansion(String(ae[1]), me)
			add(UI.kv("Aggressive expansion", "up to %d (%s)" % [int(ae[0]), Game.nations[ae[1]]["short"]],
				"Other nations will resent this land grab, most of all your neighbours and those who share the victim's faith or culture.\n%s would go from %d to %d. At %d they join a coalition against you." % [
					Game.nation_name(ae[1]), int(mine), int(mine + float(ae[0])), int(Game.dip.COALITION_JOIN)],
				UI.BAD if mine + float(ae[0]) >= Game.dip.COALITION_JOIN else UI.WARN))
	var acc: Array
	if give:
		acc = _give_acceptance(w, cost_all)
	else:
		acc = Game.dip.peace_acceptance(w, me, target, demands)
	for r in acc[2]:
		add(UI.kv("  " + String(r[0]), "%+d" % int(r[1]), "", UI.GOOD if float(r[1]) >= 0 else UI.BAD))
	if Game.is_human(target):
		add(UI.label("%s is played by a person: they decide when your offer arrives." % Game.nation_name(target), 14, UI.GOLD, 380))
	else:
		add(UI.label("They will %s." % ("ACCEPT" if acc[0] else "REFUSE"), 15, UI.GOOD if acc[0] else UI.BAD))
	var label = "Offer white peace" if demands.is_empty() else ("Offer these concessions" if give else "Send peace demands")
	add(UI.button(label, _send))
	if not give and Game.dip.fully_occupied(w, me, target) and target == Game.dip.enemy_leader(w, me):
		text("Every province of %s is occupied. You can force these terms on them; they have no say." % Game.nation_name(target), 12, UI.GOLD)
		add(UI.action("Enforce peace", "" if cost_all <= 100.0 else "Terms cost more than 100%.", _enforce,
			"Impose the terms without asking. Costs no extra, but they will hate you."))
	if _msg != "":
		text(_msg, 13, UI.GOLD)


func _give_acceptance(w: Dictionary, cost: float) -> Array:
	return Game.dip.give_acceptance(w, target, cost)


func _send() -> void:
	if not Game.wars.has(war_id):
		return
	_msg = String(Game.act("dip.propose_peace", [war_id, Game.player_tag, target, demands.duplicate(true), "give" if give else "demand"]))
	if _msg == "":
		visible = false
	mark_dirty()


func _enforce() -> void:
	if not Game.wars.has(war_id):
		return
	Game.act("dip.propose_peace", [war_id, Game.player_tag, target, demands.duplicate(true), "force"])
	visible = false


func _has(d: Dictionary) -> bool:
	for x in demands:
		if x.get("type", "") == d["type"] and int(x.get("pid", -1)) == int(d.get("pid", -1)):
			return true
	return false


func _toggle(d: Dictionary, on: bool) -> void:
	demands = demands.filter(func(x): return not (x.get("type", "") == d["type"] and int(x.get("pid", -1)) == int(d.get("pid", -1))))
	if on:
		demands.append(d)
	mark_dirty()


func _gold() -> int:
	for x in demands:
		if x.get("type", "") == "gold":
			return int(round(float(x.get("pct", 0.0)) * 100.0))
	return 0


func _set_gold(pct: int) -> void:
	demands = demands.filter(func(x): return x.get("type", "") != "gold")
	if pct > 0:
		demands.append({"type": "gold", "pct": pct / 100.0})
	mark_dirty()
