extends SceneTree
## AI soak: plays DAYS days (default 5500) with PT as the player (default MEN) and prints every nation.
## Run: PT=SKY DAYS=11000 godot --headless --path . -s tests/ai_soak.gd
func _initialize() -> void:
	var game: Node = root.get_node_or_null("Game")
	if game == null:
		game = load("res://scripts/game_state.gd").new()
		game.name = "Game"
		root.add_child(game)
	
	game.load_data()
	
	game.new_game(OS.get_environment("PT") if OS.get_environment("PT") != "" else "MEN")
	printerr("provinces ", game.provinces.size(), " nations ", game.nations.keys(), " armies ", game.armies.size(), " fleets ", game.fleets.size())
	for i in int(OS.get_environment("DAYS")) if OS.get_environment("DAYS") != "" else 5500:
		while game.is_blocked():
			game.resolve_event(game.pending_events[0], 0)
		game.advance_day()
	printerr(game.date_string())
	for t in game.nations:
		var n = game.nations[t]
		printerr(t, " alive=", n["alive"], " prov=", game.owned(t).size(), " dev=", game.nation_dev(t), " sanctum=", int(n["treasury"]), " loans=", n["loans"].size(), " tech=", n["tech"], " regs=", game.mil.regiment_count(t), " ideas=", game.prog.ideas_taken(t), " reforms=", n["reforms"].size())
	printerr("wars ", game.wars.size(), " battles ", game.battles.size())
	printerr("budget MEN ", game.eco.budget("MEN"))
	printerr("trade ", game.trade.income)
	for l in game.log_lines.slice(-15):
		printerr("  ", l)
	quit()
