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
	check(game.nations.size() == 6, "6 nations: %s" % [game.nations.keys()])
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
	for t in ["SNT", "SAL", "DRF", "CRL"]:
		check(game.owned(t).size() > 0 and game.nations[t]["government"] == "boar_tribe", "native tribe %s holds %d provinces" % [t, game.owned(t).size()])
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
	days(200)
	check(game.provinces[cap]["buildings"].has("market"), "the marketplace is finished")
	# technology, ideas, reforms
	men["power"] = [999, 999, 999]
	var lvl: int = men["tech"][0]
	check(game.prog.research("MEN", "adm") and men["tech"][0] == lvl + 1, "research administrative tech")
	check(game.prog.pick_group("MEN", "economic"), "pick the Economic idea group")
	for i in 3:
		game.prog.take_idea("MEN", "economic")
	check(game.prog.national_ideas_unlocked("MEN") == 1, "3 ideas unlock the first national idea")
	var tiers: Array = game.prog.government("MEN")["tiers"]
	men["reform_progress"] = 100.0
	check(game.prog.enact("MEN", 0, tiers[0]["reforms"][2]["id"]) and game.mods.nat("MEN", "tax_mod") > 0.15, "enact a reform: tax modifier now %.2f" % game.mods.nat("MEN", "tax_mod"))
	# trade and prices
	game.monthly_tick()
	check(float(game.trade.income.get("MEN", 0.0)) > 0.0, "Menslosia earns trade income (%.1f)" % float(game.trade.income.get("MEN", 0.0)))
	check(game.trade.send_merchant("MEN", "Eurome", "steer"), "send a merchant to steer trade from Eurome")
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
	while game.year < 4293:
		if game.month == 2 and game.day == 28 and game.year == 4292:
			for id in game.provinces:
				dev_before[id] = game.provinces[id]["dev"].duplicate()
		days(1)
		if game.doomsday_active and game.nation_dev("MEN") < men_dev_before - 0:
			hit_men = true
	check("4292-02-29" in doom_dates, "Doomsday on 29 February 4292")
	check(dev_before == dev_after, "time reversal restored every province")
	check(not hit_men and men_events.is_empty(), "the Black Moon left Menslosia alone (no troops in Skyfall)")
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
	check(not w.is_empty() and game.dip.at_war("MEN", "SNT"), "Menslosia declares war on the Snowtusk Clans")
	check(w["cb"]["id"] == "tribal_conquest", "with the Tribal Conquest casus belli")
	var battles := 0
	game.message_posted.connect(func(t): if "Battle of" in t: battles += 1)
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
		if p["owner"] != "" and p["controller"] != p["owner"] and p["controller"] != "REB" and not game.dip.at_war(p["owner"], p["controller"]):
			occupied += 1
	check(occupied == 0, "no province is left occupied after the peace")

	# ---------------------------------------------------------------- a long AI game
	game.new_game("SKY")
	game.nations["SKY"]["ai"] = true
	days(365 * 12)
	var alive := 0
	for t in game.nations:
		if game.nations[t]["alive"]:
			alive += 1
	check(game.year >= 4300, "12 years of AI play ran to %s" % game.date_string())
	check(game.nations["MEN"]["tech"][0] > 3 and game.prog.ideas_taken("MEN") > 0, "the AI researched tech %s and took %d ideas" % [game.nations["MEN"]["tech"], game.prog.ideas_taken("MEN")])
	check(game.nations["MEN"]["reforms"].size() > 0, "the AI enacted %d reforms" % game.nations["MEN"]["reforms"].size())
	var built := 0
	for id in game.owned("MEN"):
		built += game.provinces[id]["buildings"].size()
	check(built > 0, "the AI built %d buildings" % built)
	check(game.nations["MEN"]["missions_done"].size() > 0, "the AI completed missions: %s" % [game.nations["MEN"]["missions_done"].keys()])
	print("Final: %s. Menslosia %d provinces (%d dev), Skyfall %d, tribes alive %d" % [game.date_string(),
		game.owned("MEN").size(), game.nation_dev("MEN"), game.owned("SKY").size(), alive - 2])
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)
