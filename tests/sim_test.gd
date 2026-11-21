extends SceneTree
## Headless simulation test.
## Run: godot --headless --path . -s tests/sim_test.gd
## Checks the map, the economy, buildings, tech, ideas, reforms, trade, prices, the Black Moon rule,
## war and peace, rebels, rulers, colonies, and that a save loads back exactly.

var failures := 0
var game: Node


func check(cond: bool, what: String) -> void:
	if cond:
		print("  PASS  ", what)
	else:
		print("  FAIL  ", what)
		failures += 1


func days(n: int) -> void:
	for i in n:
		while game.is_blocked():
			game.resolve_event(game.pending_events[0], 0)
		game.advance_day()


func pop_group(t: String) -> String:
	return game.pop.culture_group(game.nations[t]["culture"])


func pid(name: String) -> int:
	return int(game.province_ids_by_name.get(name, -1))


func _initialize() -> void:
	game = root.get_node_or_null("Game")
	if game == null:
		game = load("res://scripts/game_state.gd").new()
		game.name = "Game"
		root.add_child(game)
	game.load_data()  # the autoload's _ready has not run yet inside _initialize
	print("Arcadia simulation test")

	# ---------------------------------------------------------------- the world
	check(game.provinces.size() >= 120, "%d provinces loaded" % game.provinces.size())
	check(game.nations.size() == 13, "13 nations: %s" % [game.nations.keys()])
	var dev_of := {}
	for id in game.provinces:
		var o: String = game.provinces[id]["owner"]
		if o != "":
			dev_of[o] = int(dev_of.get(o, 0)) + game.total_dev(id)
	check(int(dev_of["MEN"]) > int(dev_of["SKY"]) and int(dev_of["MEN"]) < 2.5 * int(dev_of["SKY"]), "Menslosia is the biggest but not overwhelming (%d dev vs Skyfall %d)" % [dev_of["MEN"], dev_of["SKY"]])
	check(game.provinces[pid("Equator Isle")]["connections"].get(pid("Holy Waterfall of Eden"), "") == "waterfall", "the Holy Waterfall reaches the ground at Equator Isle")
	var mines := 0
	for id in game.provinces:
		if "mine_site" in game.provinces[id]["flags"]:
			mines += 1
	check(mines >= 10, "%d sanctum mine sites" % mines)
	check(game.events.size() >= 55, "%d events" % game.events.size())
	var start: int = pid("Mentos")
	var seen := {start: true}
	var frontier := [start]
	while frontier.size() > 0:
		var id: int = frontier.pop_back()
		for n in game.provinces[id]["connections"]:
			if not seen.has(n):
				seen[n] = true
				frontier.append(n)
	check(seen.size() == game.provinces.size(), "every province reachable from Mentos (%d/%d)" % [seen.size(), game.provinces.size()])
	var regions := {}
	for id in game.provinces:
		regions[game.provinces[id]["region"]] = true
	for r in ["Mentos", "Sylvania", "Midrea", "Eurome", "Western Archipelago", "Southwest Island", "Southern Isles", "Skyfall"]:
		check(regions.has(r), "region %s exists" % r)
	var goods_used := {}
	for id in game.provinces:
		goods_used[game.provinces[id]["goods"]] = true
	check(goods_used.size() >= 20, "%d different trade goods in use" % goods_used.size())

	game.new_game("MEN")
	var men: Dictionary = game.nations["MEN"]
	for t in ["SNT", "SAL", "DRF", "CRL", "CDH"]:
		check(game.owned(t).size() > 0 and pop_group(t) == "Wild Boar", "boar nation %s (%s) holds %d provinces" % [t, game.court.gov_type(t), game.owned(t).size()])
	check(game.court.gov_type("SNT") == "horde" and game.court.gov_type("BAY") == "republic" and game.court.gov_type("BLM") == "theocracy", "tribes are hordes, kingdoms, republics and a cult")
	check(game.owned("BLM").size() >= 4 and game.provinces[game.capital_of("BLM")]["layer"] == "sky", "the Order of the Black Moon holds its sky islands")
	var forts := 0
	for id in game.owned("MEN"):
		if game.provinces[id]["buildings"].has("fort"):
			forts += 1
	check(forts >= 3, "forts are scattered across Menslosia (%d)" % forts)
	check(game.check_condition({"type": "explored_count", "layer": "ground", "at_least": 10}, "SKY"), "Skyfall starts knowing part of the mainland")
	check(game.mil.armies_of("MEN").size() == 2 and game.mil.fleets_of("MEN").size() == 1, "Menslosia starts with 2 armies and a fleet")

	# ---------------------------------------------------------------- economy
	var b: Dictionary = game.eco.budget("MEN")
	check(b["income"] > 0.0 and b["expenses"] > 0.0 and b["army"] > 0.0, "budget has income %.1f and expenses %.1f (army %.1f)" % [b["income"], b["expenses"], b["army"]])
	var t0: float = men["treasury"]
	check(game.eco.take_loan("MEN") and men["loans"].size() == 1 and men["treasury"] > t0, "take a loan")
	check(game.eco.repay_loan("MEN") and men["loans"].is_empty(), "repay the loan")
	# terrain changes development cost
	var flat := -1
	var rough := -1
	for id in game.owned("MEN"):
		var p: Dictionary = game.provinces[id]
		if game.total_dev(id) == 9 or game.total_dev(id) <= 9:
			if p["terrain"] == "farmland" and flat < 0:
				flat = id
			if p["terrain"] in ["mountains", "hills", "tundra"] and rough < 0:
				rough = id
	if flat >= 0 and rough >= 0:
		var df: int = game.eco.develop_cost("MEN", flat)
		var dr: int = game.eco.develop_cost("MEN", rough)
		check(dr > df, "development costs more in %s (%d) than %s (%d)" % [game.provinces[rough]["terrain"], dr, game.provinces[flat]["terrain"], df])
	# building
	men["treasury"] += 500.0
	var cap: int = game.capital_of("MEN")
	check(game.eco.build("MEN", cap, "market"), "start building a marketplace in Mentos")
	days(300)
	check(game.provinces[cap]["buildings"].has("market"), "the marketplace is finished")
	# mines
	var site := -1
	for id in game.owned("MEN"):
		if "mine_site" in game.provinces[id]["flags"]:
			site = id
			break
	if site >= 0:
		men["treasury"] += 500.0
		game.provinces[site]["construction"] = {}
		var why_mine: String = game.eco.can_build("MEN", site, "mine")
		check(game.eco.build("MEN", site, "mine"), "dig a mine at %s %s" % [game.provinces[site]["name"], why_mine])
		days(400)
		check(game.eco.mine_income(site) > 0.0, "the mine brings in %.1f sanctum a month" % game.eco.mine_income(site))
	check(game.eco.can_build("MEN", cap, "mine") != "" or "mine_site" in game.provinces[cap]["flags"], "no mines off mine sites")
	# technology, ideas, reforms
	var lvl: int = men["tech"][0]
	var ahead: int = game.prog.years_ahead("MEN", "adm")
	check(ahead > 0 and game.prog.tech_cost("MEN", "adm") > game.tech_base_cost, "researching early costs more (%d years ahead: %d)" % [ahead, game.prog.tech_cost("MEN", "adm")])
	men["power"] = [5000, 5000, 5000]
	check(game.prog.research("MEN", "adm") and men["tech"][0] == lvl + 1, "research administrative tech")
	var debuff := false
	for m in men["modifiers"]:
		if String(m.get("id", "")).begins_with("ahead_"):
			debuff = true
	check(debuff, "ahead-of-time penalty applied")
	check(game.prog.pick_group("MEN", "green_power"), "pick the Green Power idea group")
	men["power"] = [5000, 5000, 5000]
	for i in 3:
		game.prog.take_idea("MEN", "green_power")
	check(game.prog.national_ideas_unlocked("MEN") == 1, "3 ideas unlock the first national idea")
	var tiers: Array = game.prog.government("MEN")["tiers"]
	men["reform_progress"] = 100.0
	check(game.prog.enact("MEN", 0, tiers[0]["reforms"][2]["id"]) and game.mods.nat("MEN", "tax_mod") > 0.15, "enact a reform: tax modifier now %.2f" % game.mods.nat("MEN", "tax_mod"))
	# trade and prices
	game.monthly_tick()
	check(float(game.trade.income.get("MEN", 0.0)) > 0.0, "Menslosia earns trade income (%.1f)" % float(game.trade.income.get("MEN", 0.0)))
	var steer_node := ""
	for nd in game.trade.nodes:
		if game.trade.can_send("MEN", nd, "steer") == "":
			steer_node = nd
			break
	check(steer_node != "" and game.trade.send_merchant("MEN", steer_node, "steer"), "send a merchant to steer trade from %s" % steer_node)
	# advisors, legitimacy, autonomy
	men["treasury"] += 2000.0
	game.court.refill_pool("MEN")
	var cand: Dictionary = men["advisor_pool"][0]
	check(game.court.hire("MEN", int(cand["id"])) and not men["advisors"][cand["power"]].is_empty(), "hire an advisor")
	check(game.court.salaries("MEN") > 0.0, "advisors draw a salary (%.1f)" % game.court.salaries("MEN"))
	check(float(men["legitimacy"]) > 0.0, "Menslosia has legitimacy %d" % int(men["legitimacy"]))
	var far := -1
	for id in game.owned("MEN"):
		if id != cap and game.provinces[id]["cores"].has("MEN"):
			far = id
	var a0: float = game.eco.autonomy(far)
	for i in 12:
		game.eco.monthly_autonomy()
	check(game.eco.autonomy(far) > a0, "provinces drift towards autonomy early on (%.1f -> %.1f)" % [a0, game.eco.autonomy(far)])
	var tax_hi: float = game.eco.province_tax(far)
	game.provinces[far]["autonomy"] = 0.0
	check(game.eco.province_tax(far) > tax_hi, "autonomy cuts tax")
	# force limit
	var fl: int = game.mil.land_force_limit("MEN")
	var extra: Dictionary = game.mil.spawn_army("MEN", cap, fl, 0, 0)
	check(game.mil.can_recruit("MEN", cap, "inf").begins_with("At your force limit"), "no recruiting past the force limit (%d)" % fl)
	game.mil.disband_army(extra["id"])
	check(game.mil.can_recruit("SKY", game.capital_of("SKY"), "unity_guard").begins_with("Only"), "special regiments belong to their nation")
	days(730)
	var moved := 0
	for k in game.goods:
		if absf(game.eco.price(k) - float(game.goods[k]["price"])) > 0.01:
			moved += 1
	check(moved >= 10, "%d goods prices moved from their base price" % moved)

	# ---------------------------------------------------------------- the Black Moon
	var doom_dates: Array = []
	var dev_before := {}
	var dev_after := {}
	var men_events := []
	game.event_fired.connect(func(inst): if inst["event"].get("id", "") == "doomsday_men": men_events.append(1))
	game.doomsday_changed.connect(func(active):
		if active:
			doom_dates.append(game.date_key())
		elif dev_after.is_empty():
			for id in game.provinces:
				dev_after[id] = game.provinces[id]["dev"].duplicate())
	var men_dev_before: int = game.nation_dev("MEN")
	var hit_men := false
	var doom_year: int = game.year + 1
	while not game.is_leap(doom_year):
		doom_year += 1
	while game.year <= doom_year:
		if game.month == 2 and game.day == 28 and game.year == doom_year:
			for id in game.provinces:
				dev_before[id] = game.provinces[id]["dev"].duplicate()
		days(1)
		if game.doomsday_active and game.nation_dev("MEN") < men_dev_before - 0:
			hit_men = true
	check(("%d-02-29" % doom_year) in doom_dates, "Doomsday on 29 February %d" % doom_year)
	check(dev_before == dev_after, "time reversal restored every province")
	check(not hit_men and men_events.is_empty(), "the Black Moon left Menslosia alone (no troops in Skyfall)")
	var portal: int = game.portal_id()
	var ent: Dictionary = game.mil.spawn_entities(portal, 6)
	check(not ent.is_empty() and ent["owner"] == "ENT" and game.mil.hostile("ENT", "SKY"), "entities from beyond are hostile to Skyfall")
	game.armies.erase(ent["id"])
	var landing: Dictionary = game.mil.spawn_army("MEN", pid("Holy Waterfall of Eden"), 2, 0, 0)
	check(game.in_skyfall("MEN"), "with an army on the Holy Waterfall, Menslosia counts as in Skyfall")
	game.mil.disband_army(landing["id"])
	check(not game.in_skyfall("MEN"), "and not after it leaves")

	# ---------------------------------------------------------------- rulers
	men["heir"] = {"name": "Test Heir", "adm": 4, "dip": 4, "mil": 4, "age": 20, "dynasty": "Test"}
	game.court.ruler_dies("MEN")
	check(men["ruler"]["name"] == "Test Heir" and men["heir"].is_empty(), "the heir inherits when the ruler dies")
	game.court.ruler_dies("MEN")
	check(men["ruler"].get("regency", false), "with no heir, a regency council rules")

	# ---------------------------------------------------------------- rebels
	var reb_pid: int = game.owned("MEN")[5]
	game.provinces[reb_pid]["rebel_progress"] = 99.0
	game.add_province_modifier(reb_pid, "test_unrest", "Test unrest", {"local_unrest": 10}, 12)
	var armies_before: int = game.armies.size()
	game.pop.monthly()
	var rebels := 0
	for a in game.armies.values():
		if a["owner"] == "REB":
			rebels += 1
	check(rebels >= 1 and game.armies.size() > armies_before, "rebels rise when progress reaches 100")

	# ---------------------------------------------------------------- colonies
	var col := -1
	for id in game.provinces:
		if game.provinces[id]["owner"] == "" and game.provinces[id]["layer"] == "ground" and game.eco.can_colonize("MEN", id) == "":
			col = id
			break
	if col >= 0:
		check(game.eco.colonize("MEN", col), "send colonists to %s" % game.provinces[col]["name"])
		for i in 14:
			game.eco.monthly_colonies()
		check(game.provinces[col]["owner"] == "MEN", "the colony grows into a province")
	else:
		print("  note  no colonisable province next to Menslosia")
	check(game.eco.can_colonize("MEN", pid("Eden's Crown")) != "", "Menslosia cannot settle the skylands")

	# ---------------------------------------------------------------- save and load
	var err: String = game.save_game("test_roundtrip")
	check(err == "", "save the game")
	var date_saved: String = game.date_key()
	var treasury_saved: float = men["treasury"]
	var owners_saved := {}
	for id in game.provinces:
		owners_saved[id] = game.provinces[id]["owner"]
	days(90)
	err = game.load_game("test_roundtrip")
	men = game.nations["MEN"]
	var same := true
	for id in game.provinces:
		if game.provinces[id]["owner"] != owners_saved[id]:
			same = false
	check(err == "" and game.date_key() == date_saved and absf(men["treasury"] - treasury_saved) < 0.01 and same, "loading restores the date, treasury and map")
	game.delete_save("test_roundtrip")

	# ---------------------------------------------------------------- war and peace (the AI plays Menslosia)
	men["ai"] = true
	for a in game.armies.values().duplicate():
		if a["owner"] == "REB":
			game.armies.erase(a["id"])
	var snt_start: int = game.owned("SNT").size()
	var w: Dictionary = game.dip.declare_war("MEN", "SNT")
	check(not w.is_empty() and game.dip.at_war("MEN", "SNT"), "Menslosia declares war on the Snowtusk Horde")
	for ally in game.dip.allies_of("SNT"):
		if not (ally in w["defenders"]):
			print("  note  %s did not join on its own: allies must be called" % ally)
	var q: Dictionary = game.dip.call_quote(w, "MEN", "SKY") if game.dip.allied("MEN", "SKY") else {}
	if not q.is_empty():
		check(q.has("price") and q.has("reasons"), "a call to arms comes with reasons and a price (%d sanctum)" % int(q["price"]))
	check(not game.dip.fully_occupied(w, "MEN", "SNT"), "the horde is not fully occupied at the start")
	check(w["cb"]["id"] == "tribal_conquest", "with the Tribal Conquest casus belli")
	var battles := 0
	game.message_posted.connect(func(t):
		if "Battle of" in t:
			battles += 1
		if "peace" in t.to_lower() or "Snowtusk" in t:
			print("  log   ", t))
	var guard := 0
	while game.dip.at_war("MEN", "SNT") and guard < 1500:
		days(1)
		guard += 1
	check(not game.dip.at_war("MEN", "SNT"), "the war ended after %d days" % guard)
	var snt_end: int = game.owned("SNT").size() if game.nations["SNT"]["alive"] else 0
	check(snt_end < snt_start, "Menslosia took Snowtusk land (%d -> %d provinces)" % [snt_start, snt_end])
	check(game.dip.truce("MEN", "SNT") or not game.nations["SNT"]["alive"], "a truce follows the peace")
	var occupied := 0
	for id in game.provinces:
		var p: Dictionary = game.provinces[id]
		if p["owner"] != "" and p["controller"] != p["owner"] and p["controller"] != "REB" and p["controller"] != "ENT" and not game.dip.at_war(p["owner"], p["controller"]):
			print("  note  %s owned by %s held by %s" % [p["name"], p["owner"], p["controller"]])
			occupied += 1
	check(occupied == 0, "no province is left occupied after the peace")

	# ---------------------------------------------------------------- blueprint 3: war rules, coring, autonomy, decisions
	game.new_game("MEN")
	men = game.nations["MEN"]
	var stab_ok = true
	for t in game.nations:
		if int(game.nations[t]["stability"]) != 0:
			stab_ok = false
	check(stab_ok, "every nation starts at 0 stability")
	check(game.prog.reform_gain("MEN") < 1.0, "reforms come slowly (%.2f progress a month)" % game.prog.reform_gain("MEN"))
	# sieges: a level-1 fort holds a lone army for months
	var fort_pid = -1
	for id in game.owned("SNT"):
		if game.provinces[id]["buildings"].has("fort"):
			fort_pid = id
			break
	var besiegers: Dictionary = game.mil.spawn_army("MEN", fort_pid, 3, 0, 0)
	var siege_days = 100.0 / game.mil.siege_rate([besiegers], fort_pid)
	check(siege_days >= 80.0, "a fort holds 3 regiments without artillery for about %d days" % int(siege_days))
	var with_art: Dictionary = game.mil.spawn_army("MEN", fort_pid, 3, 0, 4)
	check(100.0 / game.mil.siege_rate([with_art], fort_pid) < siege_days, "artillery speeds sieges up")
	game.armies.erase(besiegers["id"])
	game.armies.erase(with_art["id"])
	# zone of control
	var zw: Dictionary = game.dip.declare_war("MEN", "SNT")
	check(game.mil.in_zoc("MEN", fort_pid), "a hostile fort's own province is in its zone of control")
	var cache = {}
	var zoc_count = 0
	for nb in game.provinces[fort_pid]["connections"]:
		if game.provinces[fort_pid]["connections"][nb] == "land" and game.mil.in_zoc("MEN", nb, cache):
			zoc_count += 1
	check(zoc_count > 0, "the fort controls %d neighbouring provinces" % zoc_count)
	# find a move the zone forbids: from a controlled province to somewhere far from the return province
	var blocked_move = false
	var fort_ok = true
	for z in game.provinces[fort_pid]["connections"]:
		if not game.mil.in_zoc("MEN", z, cache) or game.mil.hostile_fort("MEN", z):
			continue
		for r in game.provinces[z]["connections"]:
			if game.mil.in_zoc("MEN", r, cache):
				continue
			if not game.mil.zoc_step_ok("MEN", z, fort_pid, r, r, cache):
				fort_ok = false
			for y in game.provinces[z]["connections"]:
				if y != r and not game.mil.zoc_step_ok("MEN", z, y, r, r, cache):
					blocked_move = true
	check(fort_ok, "an army in a zone of control may always march on the fort")
	check(blocked_move, "a zone of control forbids marching past the fort")
	# EU4 stack wipes and overruns
	var here: int = game.owned("SNT")[0]
	var big: Dictionary = game.mil.spawn_army("MEN", here, 20, 0, 0)
	var tiny: Dictionary = game.mil.spawn_army("SNT", here, 1, 0, 0)
	days(1)
	check(not game.armies.has(tiny["id"]), "an army ten times bigger overruns the small one without a battle")
	var mp_before: int = int(game.nations["SNT"]["manpower"])
	var a1: Dictionary = game.mil.spawn_army("MEN", here, 6, 0, 0)
	var a2: Dictionary = game.mil.spawn_army("SNT", here, 2, 0, 0)
	game.mil._end_battle({"pid": here, "att": [a1["id"]], "def": [a2["id"]], "day": 6, "losses": [0.0, 0.0]}, [a1["id"]], [a2["id"]])
	check(not game.armies.has(a2["id"]), "routed in the first 12 days while outnumbered 2:1: stack-wiped")
	check(int(game.nations["SNT"]["manpower"]) > mp_before, "half the wiped army's men return to the manpower pool")
	var a3: Dictionary = game.mil.spawn_army("SNT", here, 2, 0, 0)
	game.mil._end_battle({"pid": here, "att": [a1["id"]], "def": [a3["id"]], "day": 20, "losses": [0.0, 0.0]}, [a1["id"]], [a3["id"]])
	check(game.armies.has(a3["id"]) and game.armies[a3["id"]]["retreating"], "routed after a long fight: the army retreats instead")
	for x in [big, a1, a3]:
		game.armies.erase(x["id"])
	# occupied land next to its owner's fort reverts after a month
	var nb_free = -1
	for nb in game.provinces[fort_pid]["connections"]:
		var qp: Dictionary = game.provinces[nb]
		if game.provinces[fort_pid]["connections"][nb] == "land" and qp["owner"] == "SNT" and not qp["buildings"].has("fort"):
			nb_free = nb
			break
	if nb_free >= 0:
		game.provinces[nb_free]["controller"] = "MEN"
		days(32)
		check(game.provinces[nb_free]["controller"] == "SNT", "occupied %s went back to Snowtusk: its fort still holds" % game.provinces[nb_free]["name"])
	game.dip.enforce_peace(zw, "MEN", "SNT", [{"type": "white"}])
	# coring takes time
	var target = -1
	for id in game.owned("SNT"):
		target = id
		break
	game.set_province_owner(target, "MEN")
	men["power"] = [999, 999, 999]
	check(game.pop.make_core("MEN", target) and not game.provinces[target]["cores"].has("MEN"), "coring starts but takes time")
	check(game.pop.can_core("MEN", target).begins_with("Being made a core"), "a province being cored says how long is left")
	days(30 * game.pop.CORE_MONTHS + 35)
	check(game.provinces[target]["cores"].has("MEN"), "after %d months it is a core" % game.pop.CORE_MONTHS)
	# autonomy: free to change, five-year cooldown, drift until the decision
	var auto_p = -1
	for id in game.owned("MEN"):
		if id != game.capital_of("MEN") and game.provinces[id]["cores"].has("MEN") and game.eco.autonomy(id) >= 25.0:
			auto_p = id
			break
	if auto_p < 0:
		auto_p = game.owned("MEN")[1]
		game.provinces[auto_p]["autonomy"] = 40.0
	var adm_before: int = int(men["power"][0])
	check(game.eco.change_autonomy("MEN", auto_p, true) and int(men["power"][0]) == adm_before, "lowering autonomy is free")
	check(game.eco.can_change_autonomy("MEN", auto_p, false) != "", "but the province can't be changed again soon")
	check(game.eco.autonomy_drift("MEN", auto_p) > 0.0 and game.eco.autonomy_drift("MEN", auto_p) < 0.2, "autonomy drifts slowly (%.2f a month)" % game.eco.autonomy_drift("MEN", auto_p))
	check(game.can_take_decision("MEN", "centralise_realm") != "", "Centralise the Realm isn't available in the first 50 years")
	var real_year: int = game.year
	game.year = 4340
	men["stability"] = 1
	men["power"] = [999, 999, 999]
	check(game.take_decision("MEN", "centralise_realm"), "after 50 years Menslosia can Centralise the Realm")
	check(game.eco.autonomy_drift("MEN", auto_p) == 0.0, "and autonomy stops drifting")
	game.year = real_year
	# Skyfall
	check(game.mods.nat("SKY", "dev_cost_mod") <= -0.25, "Skyfall develops cheaply while it keeps to the sky")
	game.trade.monthly()
	var sky_raw = 0.0
	for id in game.node_provinces.get("Skyfall", []):
		sky_raw += game.eco.goods_value(id) / 12.0
	check(float(game.trade.state["Skyfall"]["local"]) > sky_raw * 1.5, "the Skyfall trade node is worth more (%.2f vs %.2f)" % [float(game.trade.state["Skyfall"]["local"]), sky_raw])
	check(game.owner_colour("ENT") != Color(), "entities have a colour (their army window no longer crashes)")
	var ent_army: Dictionary = game.mil.spawn_entities(game.portal_id(), 3)
	check(game.mil.edge_days(ent_army, pid("Holy Waterfall of Eden"), pid("Equator Isle")) < 0.0, "entities can't climb down the waterfall to the mainland")
	game.armies.erase(ent_army["id"])

	# ---------------------------------------------------------------- blueprint 4: straits, sea lanes, events, missions
	game.new_game("SYL")
	var z4_curl: int = pid("Curl Isle")
	var z4_elder: int = pid("Elderwood")
	check(game.provinces[z4_curl]["connections"].get(z4_elder, "") == "strait", "Curl Isle and Elderwood are joined by a strait")
	var z4_walker: Dictionary = game.mil.spawn_army("SYL", z4_elder, 2, 0, 0)
	check(game.mil.edge_days(z4_walker, z4_elder, z4_curl) > 0.0, "an army can walk across the strait without ships")
	var z4_sw: Dictionary = game.dip.declare_war("SYL", "BAY")
	var z4_blockers: Dictionary = game.mil.spawn_fleet("BAY", z4_curl, {"heavy": 3})
	check(game.mil.strait_blocked("SYL", z4_elder, z4_curl) and game.mil.edge_days(z4_walker, z4_elder, z4_curl) < 0.0, "an enemy z4_fleet holding the water blocks the strait")
	var z4_mine_fleet: Dictionary = game.mil.spawn_fleet("SYL", z4_elder, {"heavy": 14})
	check(not game.mil.strait_blocked("SYL", z4_elder, z4_curl), "a stronger fleet of our own reopens it")
	for x in [z4_blockers, z4_mine_fleet]:
		game.fleets.erase(x["id"])
	game.armies.erase(z4_walker["id"])
	game.dip.enforce_peace(z4_sw, "SYL", "BAY", [{"type": "white"}])
	# fleets sail through water, never over land
	var z4_coast: Array = []
	for id in game.provinces:
		if game.provinces[id]["coastal"] and game.provinces[id]["layer"] == "ground":
			z4_coast.append(id)
	var z4_a0: int = z4_coast[0]
	var z4_b0: int = z4_coast[z4_coast.size() - 1]
	var z4_r: Dictionary = game.sea.route(z4_a0, z4_b0)
	var z4_dry = 0
	if not z4_r.is_empty():
		var z4_pts: PackedVector2Array = z4_r["points"]
		for i in range(1, z4_pts.size()):
			for k in 20:
				var z4_q: Vector2 = z4_pts[i - 1].lerp(z4_pts[i], k / 20.0)
				if not game.sea._is_water(game.sea._grid["ground"]["img"], z4_q):
					z4_dry += 1
	check(not z4_r.is_empty() and z4_dry == 0, "a fleet's route from %s to %s stays on the water (%d points)" % [game.provinces[z4_a0]["name"], game.provinces[z4_b0]["name"], z4_r.get("points", []).size()])
	var z4_fleet: Dictionary = game.mil.fleets_of("SYL")[0] if game.mil.fleets_of("SYL").size() > 0 else game.mil.spawn_fleet("SYL", z4_elder, {"light": 1})
	var z4_target_port: int = z4_coast[0] if int(z4_fleet["location"]) != z4_coast[0] else z4_coast[1]
	check(game.mil.move_fleet(int(z4_fleet["id"]), z4_target_port) and float(z4_fleet["hop_days"]) >= 1.0, "a fleet sets sail (%d days)" % int(z4_fleet["hop_days"]))
	# autonomy
	var z4_ap: int = game.owned("SYL")[1]
	game.provinces[z4_ap]["autonomy"] = 50.0
	game.eco.change_autonomy("SYL", z4_ap, true)
	check(game.mods.loc(z4_ap, "local_unrest") >= 5.0, "lowering autonomy raises unrest by 5")
	# event timing
	var z4_ev: Dictionary = game.events["men_pig_lord_jubilee"]
	game.year = 4300
	check(not game.in_year_window(z4_ev["trigger"]), "the Jubilee can't happen before 4314")
	game.year = 4315
	check(game.in_year_window(z4_ev["trigger"]), "but can in 4315")
	var z4_drills: Dictionary = game.events["men_unity_drills"]
	var z4_peace_chance: float = game.event_monthly_chance(z4_drills, "MEN")
	check(z4_peace_chance > 0.0 and z4_peace_chance < 0.05, "mean time to happen gives a small monthly chance (%.3f)" % z4_peace_chance)
	game.year = 4289
	var z4_once_count = 0
	for eid in game.events:
		if game.events[eid].get("once", false):
			z4_once_count += 1
	check(z4_once_count >= 40, "%d events fire only once" % z4_once_count)
	var z4_men_sky = 0
	for eid in game.events:
		if game.events[eid]["for"] in ["MEN", "SKY"]:
			z4_men_sky += 1
	check(z4_men_sky >= 70, "%d events for Menslosia and Skyfall" % z4_men_sky)
	# missions fit the map: none is done at the start
	for t in ["MEN", "SKY"]:
		game.new_game(t)
		var z4_done_at_start = 0
		for m in game.missions_for(t):
			if game.mission_state(t, m) in ["ready", "done"]:
				z4_done_at_start += 1
		check(z4_done_at_start == 0 and game.missions_for(t).size() >= 20, "%s has %d missions, none complete at the start" % [t, game.missions_for(t).size()])

	# ---------------------------------------------------------------- message filters
	game.new_game("MEN")
	var mf_far: Array = []
	for t in game.nations:
		if t != "MEN" and game.nations[t]["alive"] and not game.concerns_player([t], true):
			mf_far.append(t)
	check(mf_far.size() >= 2, "some nations are far from Menslosia: %s" % [mf_far])
	if mf_far.size() >= 2:
		var mf_world: int = game.world_lines.size()
		var mf_log: int = game.log_lines.size()
		game.post("test: far-away news", [mf_far[0], mf_far[1]])
		check(game.world_lines.size() == mf_world + 1 and game.log_lines.size() == mf_log, "news between far-off nations goes to the world news, not the log")
	game.post("test: our news", ["MEN"])
	check(game.log_lines.back() == "test: our news", "news about the player goes to the log")

	# ---------------------------------------------------------------- aggressive expansion and coalitions
	var ae_w: Dictionary = game.dip.declare_war("MEN", "SNT")
	check(not ae_w.is_empty(), "Menslosia declares war on Snowtusk")
	var ae_take: Array = game.owned("SNT").slice(0, 2)
	var ae_demands: Array = []
	for p in ae_take:
		ae_demands.append({"type": "province", "pid": p})
	var ae_prev: Array = game.dip.ae_preview(ae_w, "MEN", "SNT", ae_demands)
	check(float(ae_prev[0]) > 0.0, "the peace screen previews aggressive expansion (up to %.0f with %s)" % [float(ae_prev[0]), ae_prev[1]])
	game.dip.enforce_peace(ae_w, "MEN", "SNT", ae_demands)
	var ae_near := ""
	var ae_far := ""
	for t in game.nations:
		if t in ["MEN", "SNT"] or not game.nations[t]["alive"]:
			continue
		if ae_near == "" and game.dip.borders(t, "MEN"):
			ae_near = t
		if ae_far == "" and not game.dip.borders(t, "MEN") and not game.dip.borders(t, "SNT"):
			ae_far = t
	var ae_n: float = game.dip.aggressive_expansion(ae_near, "MEN")
	var ae_f: float = game.dip.aggressive_expansion(ae_far, "MEN") if ae_far != "" else 0.0
	check(ae_n > 0.0, "taking Snowtusk land gives %s %.1f aggressive expansion toward Menslosia" % [ae_near, ae_n])
	check(ae_far == "" or ae_f < ae_n, "far-off %s minds less (%.1f)" % [ae_far, ae_f])
	game.dip.monthly()
	check(game.dip.aggressive_expansion(ae_near, "MEN") < ae_n, "aggressive expansion fades every month")
	# push every non-allied nation over the edge and watch the coalition form
	for t in game.nations:
		if t != "MEN" and game.nations[t]["alive"] and not game.dip.rel(t, "MEN")["alliance"]:
			game.dip.add_opinion(t, "MEN", -90.0, game.dip.AE_NAME, game.dip.AE_DECAY)
	game.dip.update_coalitions()
	var ae_coal: Array = game.dip.coalition_against("MEN")
	check(ae_coal.size() >= 3, "a coalition of %d forms against Menslosia" % ae_coal.size())
	check(not ae_coal.has("SKY"), "Menslosia's ally Skyfall stays out of it")
	game.nations["MEN"]["coalition_since"] = game.day_index - 400
	var ae_st: Array = game.dip.coalition_strength("MEN")
	game.dip.update_coalitions()
	var ae_cw := false
	for wid in game.wars:
		if game.wars[wid]["cb"].get("id", "") == "coalition" and "MEN" in game.wars[wid]["defenders"]:
			ae_cw = game.wars[wid]["attackers"].size() >= 2
	if float(ae_st[0]) >= float(ae_st[1]) * 0.8:
		check(ae_cw, "after a year the coalition declares war (strength %d against %d)" % [int(ae_st[0]), int(ae_st[1])])
	else:
		check(not ae_cw, "a coalition weaker than its target waits (strength %d against %d)" % [int(ae_st[0]), int(ae_st[1])])

	# ---------------------------------------------------------------- a long AI game
	game.new_game("SKY")
	game.nations["SKY"]["ai"] = true
	days(365 * 12)
	var alive := 0
	for t in game.nations:
		if game.nations[t]["alive"]:
			alive += 1
	check(game.year >= 4300, "12 years of AI play ran to %s" % game.date_string())
	var ideas := 0
	for t in game.nations:
		ideas += game.prog.ideas_taken(t)
	check(ideas > 5, "the AIs took %d ideas" % ideas)
	check(game.nations["MEN"]["reforms"].size() > 0, "the AI enacted %d reforms" % game.nations["MEN"]["reforms"].size())
	var built := 0
	for id in game.owned("MEN"):
		built += game.provinces[id]["buildings"].size()
	check(built > 0, "the AI built %d buildings" % built)
	var missions := 0
	var loans := 0
	for t in game.nations:
		missions += game.nations[t]["missions_done"].size()
		loans += game.nations[t]["loans"].size()
	check(missions > 3, "the AIs completed %d missions" % missions)
	check(loans < game.nations.size() * 2, "the AIs are not drowning in debt (%d loans)" % loans)
	print("Final: %s. Menslosia %d provinces (%d dev), Skyfall %d, tribes alive %d" % [game.date_string(),
		game.owned("MEN").size(), game.nation_dev("MEN"), game.owned("SKY").size(), alive - 2])
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)
