extends Node
## Builds the world (map + camera), the menus and the HUD, and wires them together.
## Screens: main menu -> Incendium intro -> nation select (over the live map) -> game.
##
## Automation flags (after `--` on the command line), used by tests and screenshots:
##   --nation=TAG          start immediately as that nation (skips the menus)
##   --select-screen       open on the nation select screen    --menu   stay on the main menu    --intro  the cutscene
##   --days=N              advance N days after starting (events answered with option 1)
##   --until-doomsday      advance until the Black Moon rises
##   --layer=sky  --mode=goods|trade|culture|...   --zoom=2.5  --focus="Province"  --at=x,y (a map point)
##   --select="Province"   select a province     --panel=economy|trade|tech|ideas|government|court|military|diplomacy|peoples|missions
##   --country=TAG         open a nation's diplomacy view      --war=TAG  declare war on TAG first
##   --army                select the player's first army   --group  select all of them    --entities  spawn entities at the portal and select them
##   --tab=cores           pick the Production panel's tab      --peace  open the peace screen for the first war
##   --keep-event          leave the last pending event on screen
##   --settings            open the settings window      --news  show a sample news popup
##   --howto  show the F1 guide   --warview  open the first war's overview   --search="text"  the Ctrl+F box   --preview="Province"  march preview (with --army)
##   --fleet-to="Province" --sail=N   send the first fleet there and sail N days   --node="Name"  open a trade node
##   --soak=SECONDS        play at full speed, clicking through every panel, then quit (UI stress test)
##   --screenshot=path.png save a screenshot after a few frames and quit

const UI = preload("res://scripts/ui/ui_util.gd")
const MapView = preload("res://scripts/map_view.gd")
const MapCamera = preload("res://scripts/map_camera.gd")
const Settings = preload("res://scripts/settings.gd")
const PANELS := ["court", "government", "economy", "production", "trade", "tech", "ideas", "military", "diplomacy", "peoples", "missions", "ledger", "ages"]
const PANEL_SCRIPTS := {
	"court": "res://scripts/ui/court_panel.gd", "government": "res://scripts/ui/government_panel.gd",
	"economy": "res://scripts/ui/economy_panel.gd", "production": "res://scripts/ui/production_panel.gd", "trade": "res://scripts/ui/trade_panel.gd",
	"tech": "res://scripts/ui/tech_panel.gd", "ideas": "res://scripts/ui/ideas_panel.gd",
	"military": "res://scripts/ui/military_panel.gd", "diplomacy": "res://scripts/ui/diplomacy_panel.gd",
	"peoples": "res://scripts/ui/peoples_panel.gd", "missions": "res://scripts/ui/missions_panel.gd",
	"ledger": "res://scripts/ui/ledger_panel.gd",
	"ages": "res://scripts/ui/ages_panel.gd",
}
const SHORTCUTS := {KEY_C: "court", KEY_G: "government", KEY_E: "economy", KEY_B: "production", KEY_T: "trade", KEY_R: "tech",
	KEY_I: "ideas", KEY_L: "military", KEY_O: "diplomacy", KEY_P: "peoples", KEY_M: "missions", KEY_J: "ledger", KEY_K: "ages"}
# Shift + the number row picks a map mode, in the order of the map-mode buttons
const MODE_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0, KEY_MINUS, KEY_EQUAL]

var map: MapView
var camera: MapCamera
var hud: CanvasLayer
var root_ui: Control
var top_bar
var tab_bar
var panels := {}
var open_name := ""
var province_panel
var army_panel
var country_panel
var trade_node_panel
var peace_panel
var event_popup
var map_controls
var log_panel
var alerts
var help_overlay
var main_menu
var intro
var nation_select
var game_menu
var settings_panel
var news_popup
var outliner
var war_panel
var battle_report
var search_box
var eschaton_eye
var hover_label: Label
var state := "menu"
var args := {}


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.05, 0.07, 0.09))
	_parse_args()
	Settings.apply(get_tree())
	Game.setup_world()
	map = MapView.new()
	add_child(map)
	map.ignore_mouse = args.has("screenshot")   # screenshots must not depend on where the cursor is
	camera = MapCamera.new()
	camera.bounds = Rect2(Vector2.ZERO, map.map_size)
	camera.focus = map.map_size / 2.0   # fit_bounds shows the whole world, centred
	add_child(camera)  # after the map so it sees input first
	camera.zoom_changed.connect(map.set_camera_zoom)
	camera.wrap_width = map.wrap_width()   # the world loops east-west
	map.set_camera_zoom(camera.zoom.x)

	hud = CanvasLayer.new()
	hud.layer = 2   # above the map overlay (names, counters) on layer 1
	add_child(hud)
	root_ui = Control.new()
	root_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ui.theme = UI.build_theme()
	root_ui.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # icons are rasterised at 2x
	hud.add_child(root_ui)
	top_bar = _add("res://scripts/ui/top_bar.gd")
	tab_bar = _add("res://scripts/ui/tab_bar.gd")
	map_controls = _add("res://scripts/ui/map_controls.gd")
	log_panel = _add("res://scripts/ui/log_panel.gd")
	alerts = _add("res://scripts/ui/alerts.gd")
	for k in PANELS:
		panels[k] = _add(PANEL_SCRIPTS[k])
		panels[k].closed.connect(func(): if open_name == k: open_name = ""; tab_bar.set_active(""))
	province_panel = _add("res://scripts/ui/province_panel.gd")
	army_panel = _add("res://scripts/ui/army_panel.gd")
	country_panel = _add("res://scripts/ui/country_panel.gd")
	trade_node_panel = _add("res://scripts/ui/trade_node_panel.gd")
	peace_panel = _add("res://scripts/ui/peace_panel.gd")
	nation_select = _add("res://scripts/ui/nation_select.gd")
	event_popup = _add("res://scripts/ui/event_popup.gd")
	outliner = _add("res://scripts/ui/outliner.gd")
	outliner.army_clicked.connect(func(id): _select_army(id); _focus_unit(id, true))
	outliner.fleet_clicked.connect(func(id): _select_fleet(id); _focus_unit(id, false))
	outliner.province_clicked.connect(focus_province)
	outliner.war_clicked.connect(_open_war)
	news_popup = _add("res://scripts/ui/news_popup.gd")
	news_popup.paused_changed.connect(func(): top_bar.refresh())
	war_panel = _add("res://scripts/ui/war_panel.gd")
	war_panel.peace_requested.connect(_open_peace)
	battle_report = _add("res://scripts/ui/battle_report.gd")
	battle_report.province_clicked.connect(focus_province)
	search_box = _add("res://scripts/ui/search_box.gd")
	search_box.province_chosen.connect(focus_province)
	search_box.nation_chosen.connect(func(t):
		var cap: int = Game.capital_of(t)
		if cap >= 0:
			map.set_layer(Game.provinces[cap]["layer"])
			camera.position = Game.provinces[cap]["centre"]
		_open_country(t))
	hover_label = UI.label("", 13, UI.TEXT)
	hover_label.add_theme_stylebox_override("normal", UI.tex_box("tooltip.png", 6, 10, 6, true))
	hover_label.visible = false
	hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ui.add_child(hover_label)
	intro = _add("res://scripts/ui/intro.gd")
	main_menu = _add("res://scripts/ui/main_menu.gd")
	game_menu = _add("res://scripts/ui/game_menu.gd")
	help_overlay = _add("res://scripts/ui/help_overlay.gd")
	settings_panel = _add("res://scripts/ui/settings_panel.gd")
	main_menu.settings_pressed.connect(settings_panel.open)
	game_menu.settings_pressed.connect(settings_panel.open)
	eschaton_eye = _add("res://scripts/ui/eschaton_eye.gd")   # last, so it covers everything
	alerts.open_panel.connect(open_panel)
	alerts.go_to_province.connect(focus_province)
	alerts.open_peace.connect(_open_peace)
	panels["production"].go_to_province.connect(focus_province)

	map.province_clicked.connect(_on_province_clicked)
	map.province_right_clicked.connect(_on_right_click)
	map.province_hovered.connect(_on_province_hovered)
	map.army_clicked.connect(_select_army)
	map.army_shift_clicked.connect(_toggle_in_group)
	map.box_selected.connect(_select_group)
	army_panel.group_changed.connect(_select_group)
	map.fleet_clicked.connect(_select_fleet)
	map.layer_changed.connect(func(l):
		map_controls.set_state(map.mode, l)
		camera.bounds = Rect2(Vector2.ZERO, map.map_size)   # each layer has its own size
		camera.wrap_width = map.wrap_width()                # the world loops, the sky doesn't
		camera.position = camera.position.clamp(camera.bounds.position, camera.bounds.end))
	province_panel.go_to_province.connect(focus_province)
	province_panel.country_clicked.connect(_open_country)
	province_panel.army_clicked.connect(_select_army)
	province_panel.closed.connect(func(): map.select(-1))
	army_panel.deselected.connect(func(): map.select_army(-1); map.select_fleet(-1))
	panels["military"].army_selected.connect(func(id): _select_army(id); _focus_unit(id, true))
	panels["military"].fleet_selected.connect(func(id): _select_fleet(id); _focus_unit(id, false))
	panels["diplomacy"].country_selected.connect(_open_country)
	panels["diplomacy"].peace_requested.connect(_open_peace)
	panels["diplomacy"].war_selected.connect(_open_war)
	country_panel.peace_requested.connect(_open_peace)
	trade_node_panel.node_closed.connect(func(): map.select_node(""))
	trade_node_panel.go_to_province.connect(focus_province)
	panels["trade"].node_selected.connect(_open_trade_node)
	map_controls.mode_selected.connect(func(m):
		map.set_mode(m)
		map_controls.set_state(m, map.layer)
		if m != "trade":
			trade_node_panel.visible = false)
	map_controls.layer_selected.connect(map.set_layer)
	top_bar.open_panel.connect(open_panel)
	top_bar.menu_pressed.connect(func(): game_menu.open())
	tab_bar.open_panel.connect(open_panel)
	main_menu.new_game_pressed.connect(func(): _set_state("intro"); intro.play())
	main_menu.load_pressed.connect(_load)
	intro.finished.connect(_open_select)
	nation_select.nation_chosen.connect(start_game)
	nation_select.back_pressed.connect(func(): _set_state("menu"))
	nation_select.nation_focused.connect(_focus_nation)
	game_menu.main_menu.connect(_to_main_menu)
	game_menu.loaded.connect(_after_load)
	Game.month_ticked.connect(_update_badges)
	Game.month_ticked.connect(_autosave)
	Game.war_changed.connect(_update_music)
	Game.game_started.connect(_update_music)
	Game.doomsday_changed.connect(func(on): if on and state == "game": UI.sfx("doom"))
	_update_music()
	Game.month_ticked.connect(func(): _set_corruption(Game.eschaton_corruption()))
	Game.nation_changed.connect(func(_t): _update_badges())
	_set_state("menu")

	if args.has("nation"):
		start_game(args["nation"])
		_run_automation()
	elif args.has("intro"):
		_set_state("intro")
		intro.play()
	elif args.has("select-screen"):
		_open_select()
	if args.has("soak"):
		get_tree().create_timer(float(args["soak"])).timeout.connect(func():
			print("soak finished at ", Game.date_string())
			if args.has("screenshot"):
				get_viewport().get_texture().get_image().save_png(args["screenshot"])
			get_tree().quit())
	elif args.has("screenshot"):
		_screenshot_after_frames(args["screenshot"])


func _add(script_path: String) -> Control:
	var node: Control = load(script_path).new()
	root_ui.add_child(node)
	return node


# ---------------------------------------------------------------- screens

func _set_state(s: String) -> void:
	state = s
	_update_music()
	var in_game := s == "game"
	for c in [top_bar, tab_bar, map_controls, log_panel, alerts, outliner]:
		c.visible = in_game
	if not in_game:
		help_overlay.visible = false
	if not in_game:
		_close_all()
	main_menu.visible = s == "menu"
	if s == "menu":
		main_menu.refresh()
	nation_select.visible = s == "select"
	if s != "intro":
		intro.visible = false
	map.show_all = s != "game"
	map.refresh()


func _open_select() -> void:
	Game.setup_world()
	Game.started = false
	map.set_layer("ground")
	map.set_mode("political")
	_set_state("select")
	camera.fit_bounds()
	nation_select.open()   # after fit_bounds, so it doesn't undo the focus on the first nation


func _set_corruption(amount: float) -> void:
	map.set_corruption(amount)


func _focus_nation(tag: String) -> void:
	var cap: int = Game.capital_of(tag)
	if cap < 0:
		return
	map.set_layer(Game.provinces[cap]["layer"])
	map.select(cap)
	# centre the capital in the part of the screen the nation-select window doesn't cover
	var covered: float = nation_select.position.x + nation_select.size.x if nation_select.visible else 0.0
	camera.position = Game.provinces[cap]["centre"] + Vector2(-covered / 2.0 / camera.zoom.x, 0)


func start_game(tag: String) -> void:
	Game.new_game(tag)
	_set_state("game")
	_after_start()


func _after_start() -> void:
	_set_corruption(Game.eschaton_corruption())   # a loaded game near the end is already corrupted
	var cap: int = Game.capital_of(Game.player_tag)
	map.set_layer(Game.provinces[cap]["layer"] if cap >= 0 else "ground")
	map.set_mode("political")
	map_controls.set_state(map.mode, map.layer)
	map.select(-1)
	camera.fit_bounds()
	if cap >= 0:
		camera.zoom = Vector2(1.3, 1.3)
		map.set_camera_zoom(1.3)
		camera.position = Game.provinces[cap]["centre"]
	map.refresh()
	top_bar.refresh()
	log_panel.refresh()
	alerts.refresh()
	_update_badges()


func _load(slot: String) -> void:
	var err := Game.load_game(slot)
	if err != "":
		Game.post(err)
		return
	_after_load()


func _after_load() -> void:
	news_popup.clear()
	_set_state("game")
	_after_start()


func _update_music() -> void:
	## War music while the player is at war, otherwise the calm theme (menus too).
	var snd = get_tree().root.get_node_or_null("Sound")
	if snd == null:
		return
	var at_war: bool = state == "game" and Game.player_tag != "" and Game.nations.has(Game.player_tag) and Game.dip.at_war_any(Game.player_tag)
	snd.music("war" if at_war else "peace")


func _autosave() -> void:
	## Monthly or yearly autosave into a few rotating slots ("Autosave 1".."Autosave N").
	## Skipped during automation runs (tests, soak, screenshots) so they don't litter user://.
	if state != "game" or not args.is_empty() or Game.player_tag == "":
		return
	var mode := String(Settings.get_value("autosave"))
	if mode == "off" or (mode == "yearly" and Game.month != 1):
		return
	var n: int = Game.year * 12 + Game.month
	if mode == "yearly":
		n = Game.year
	Game.save_game("Autosave %d" % (n % Settings.AUTOSAVE_SLOTS + 1), true)


func _to_main_menu() -> void:
	news_popup.clear()
	Game.set_speed(0)
	Game.started = false
	Game.setup_world()
	_set_state("menu")
	camera.fit_bounds()


# ---------------------------------------------------------------- panels

func open_panel(name: String) -> void:
	if name == "help":
		help_overlay.visible = not help_overlay.visible
		return
	if state != "game" or not panels.has(name):
		return
	if open_name == name and panels[name].visible:
		panels[name].visible = false
		open_name = ""
		tab_bar.set_active("")
		return
	for k in panels:
		panels[k].visible = k == name
	open_name = name
	tab_bar.set_active(name)


func _close_all() -> void:
	for k in panels:
		panels[k].visible = false
	open_name = ""
	tab_bar.set_active("")
	province_panel.visible = false
	army_panel.visible = false
	country_panel.visible = false
	peace_panel.visible = false
	war_panel.visible = false


func _open_war(war_id: int) -> void:
	## The war overview, on the right where the province window goes.
	province_panel.visible = false
	country_panel.visible = false
	trade_node_panel.visible = false
	war_panel.show_war(war_id)


func _open_country(tag: String) -> void:
	if tag == "" or not Game.nations.has(tag):
		return
	peace_panel.visible = false
	country_panel.show_nation(tag)


func _open_peace(war_id: int) -> void:
	country_panel.visible = false
	war_panel.visible = false
	peace_panel.open_war(war_id)


func _update_badges() -> void:
	if state != "game":
		return
	var c: int = panels["missions"].ready_count()
	tab_bar.set_badge("missions", "(%d!)" % c if c > 0 else "")
	var wars: Array = Game.dip.wars_of(Game.player_tag)
	tab_bar.set_badge("diplomacy", "(war)" if wars.size() > 0 else "")


func focus_province(id: int) -> void:
	if not Game.provinces.has(id):
		return
	map.set_layer(Game.provinces[id]["layer"])
	map.select(id)
	camera.position = Game.provinces[id]["centre"]
	province_panel.show_province(id)


func _focus_unit(id: int, is_army: bool) -> void:
	var u: Dictionary = Game.armies.get(id, {}) if is_army else Game.fleets.get(id, {})
	if u.is_empty():
		return
	var pid: int = int(u["location"])
	map.set_layer(Game.provinces[pid]["layer"])
	camera.position = Game.provinces[pid]["centre"]


# ---------------------------------------------------------------- map input

func _on_province_clicked(id: int) -> void:
	if state == "select":
		if id > 0 and Game.provinces[id]["owner"] != "":
			nation_select.pick(Game.provinces[id]["owner"])
		return
	if state != "game":
		return
	map.select_army(-1)
	army_panel.visible = false
	if map.mode == "trade" and id > 0 and Game.provinces[id]["trade_node"] != "":
		_open_trade_node(Game.provinces[id]["trade_node"])   # EU4: the trade map mode is about nodes
		return
	province_panel.show_province(id if id > 0 else -1)


func _open_trade_node(node: String) -> void:
	if map.mode != "trade":
		map.set_mode("trade")
		map_controls.set_state("trade", map.layer)
	map.select_node(node)
	province_panel.visible = false
	trade_node_panel.show_node(node)


func _on_right_click(id: int) -> void:
	if state != "game":
		return
	if map.group.size() > 1:
		var failed: PackedStringArray = []
		for aid in map.group:
			if Game.armies.has(aid) and Game.armies[aid]["owner"] == Game.player_tag and not Game.mil.move_army(aid, id):
				failed.append(Game.armies[aid]["name"])
		if failed.size() > 0:
			Game.post("Can't reach %s: %s." % [Game.provinces[id]["name"], ", ".join(failed)])
		army_panel.mark_dirty()
		return
	if map.selected_army >= 0 and Game.armies.has(map.selected_army) and Game.armies[map.selected_army]["owner"] == Game.player_tag:
		if not Game.mil.move_army(map.selected_army, id):
			var sel_army: Dictionary = Game.armies[map.selected_army]
			var mask_why: String = _mask_block(sel_army, id)
			if mask_why != "":
				Game.post("%s can't go to %s. %s" % [sel_army["name"], Game.provinces[id]["name"], mask_why])
			elif Game.mil.zoc_blocked(sel_army, id):
				Game.post("%s can't march past an enemy fort to reach %s: besiege the fort first, or go around (zone of control)." % [
					sel_army["name"], Game.provinces[id]["name"]])
			else:
				Game.post("%s can't reach %s (no path, no military access, or not enough transports)." % [
					sel_army["name"], Game.provinces[id]["name"]])
		army_panel.mark_dirty()
		return
	if map.selected_fleet >= 0 and Game.fleets.has(map.selected_fleet) and Game.fleets[map.selected_fleet]["owner"] == Game.player_tag:
		if not Game.mil.move_fleet(map.selected_fleet, id):
			Game.post("The fleet can't sail to %s: fleets only go to coastal provinces they can reach." % Game.provinces[id]["name"])
		army_panel.mark_dirty()
		return
	var owner: String = Game.provinces[id]["owner"]
	if owner != "" and Game.is_explored_by_player(id):
		_open_country(owner)


func _select_army(id: int) -> void:
	if state != "game" or not Game.armies.has(id):
		return
	map.select_army(id)
	army_panel.show_army(id)


func _mask_block(a: Dictionary, dest: int) -> String:
	## The oxygen-mask reason, when the march would take an army into air it can't breathe.
	return Game.mil.layer_block_reason(String(a["owner"]), dest)


func _toggle_in_group(id: int) -> void:
	## Shift-click: add one of your armies to the selection, or take it out again.
	if state != "game" or not Game.armies.has(id) or Game.armies[id]["owner"] != Game.player_tag:
		_select_army(id)
		return
	var ids: Array = map.group.filter(func(x): return Game.armies.has(x) and Game.armies[x]["owner"] == Game.player_tag)
	if ids.has(id):
		ids.erase(id)
	else:
		ids.append(id)
	_select_group(ids)


func _select_group(ids: Array) -> void:
	var mine: Array = ids.filter(func(x): return Game.armies.has(x) and Game.armies[x]["owner"] == Game.player_tag)
	if mine.is_empty():
		if ids.size() > 0:
			_select_army(int(ids[0]))   # only foreign armies in the box: show the first
		else:
			army_panel.close()
		return
	if mine.size() == 1:
		_select_army(int(mine[0]))
		return
	map.set_group(mine)
	army_panel.show_group(mine)


func _select_fleet(id: int) -> void:
	if state != "game" or not Game.fleets.has(id):
		return
	map.select_fleet(id)
	army_panel.show_fleet(id)


func _hover_details(id: int) -> String:
	## The extra line EU4 puts in its province tooltip: fort, armies here, siege, unrest, core status.
	var p: Dictionary = Game.provinces[id]
	var bits: PackedStringArray = []
	if p["buildings"].has("fort"):
		bits.append("Fort")
	var men := {}
	for a in Game.mil.armies_at(id):
		var n := 0.0
		for r in a["regiments"]:
			n += float(r["men"])
		men[a["owner"]] = float(men.get(a["owner"], 0.0)) + n
	for o in men:
		bits.append("%s army %.1fk" % [Game.nations[o]["short"] if Game.nations.has(o) else ("Rebels" if o == "REB" else "Entities"), men[o] / 1000.0])
	if not p["siege"].is_empty():
		bits.append("Siege %d%%" % int(p["siege"].get("progress", 0)))
	if p["owner"] != "" and p["owner"] == Game.player_tag:
		var u := float(p.get("unrest", 0.0))
		if u > 0.0:
			bits.append("Unrest %+.1f" % u)
		if not p["cores"].has(p["owner"]):
			bits.append("Not a core")
		if float(p.get("autonomy", 0.0)) >= 1.0:
			bits.append("Autonomy %d%%" % int(Game.eco.autonomy(id)))
	return "  ·  ".join(bits)


func _update_march_preview(id: int) -> void:
	## With one of your armies selected, hovering a province shows the route, the days it takes and
	## whether the army will starve on the way (EU4's movement preview).
	var aid: int = map.selected_army
	if state != "game" or id <= 0 or aid < 0 or not Game.armies.has(aid) or Game.armies[aid]["owner"] != Game.player_tag \
			or int(Game.armies[aid]["location"]) == id or Game.provinces[id]["layer"] != map.layer:
		map.set_preview([], "", true)
		return
	var a: Dictionary = Game.armies[aid]
	var path: Array = Game.mil.find_path(a, id)
	if path.is_empty():
		var why := _mask_block(a, id)
		if why == "":
			why = "Blocked by an enemy fort (zone of control)" if Game.mil.zoc_blocked(a, id) else "Can't get there"
		map.set_preview([Game.provinces[id]["centre"]], why, false)
		return
	var days := 0.0
	var prev: int = int(a["location"])
	var starving := 0
	var regs := 0
	for aid2 in map.group:
		if Game.armies.has(aid2):
			regs += Game.armies[aid2]["regiments"].size()
	regs = maxi(regs, a["regiments"].size())
	var pts: Array = [Game.provinces[prev]["centre"]]
	for step in path:
		days += Game.mil.edge_days(a, prev, int(step))
		if Game.provinces[int(step)]["layer"] == map.layer:
			pts.append(Game.provinces[int(step)]["centre"])
		if float(regs) > Game.mil.supply_limit(int(step)):
			starving += 1
		prev = int(step)
	var text := "%d days" % int(ceil(days))
	if starving > 0:
		text += "  ·  attrition in %d province%s" % [starving, "" if starving == 1 else "s"]
	map.set_preview(pts, text, true)


func _on_province_hovered(id: int) -> void:
	_update_march_preview(id)
	if id <= 0 or not Game.provinces.has(id) or state not in ["game", "select"]:
		hover_label.visible = false
		return
	var p: Dictionary = Game.provinces[id]
	if map.explored(id):
		var owner: String = Game.nation_name(p["owner"]) if p["owner"] != "" else "Uninhabited"
		var extra := ""
		if p["owner"] != "" and p["controller"] != p["owner"]:
			extra = "  ·  occupied by %s" % Game.nation_name(p["controller"])
		var line2 := "%s  ·  %s  ·  dev %d" % [Game.terrain_data.get(p["terrain"], {}).get("name", ""), Game.goods.get(p["goods"], {}).get("name", ""), Game.total_dev(id)]
		match map.mode:
			"culture": line2 = "%s culture (%s)" % [p["culture"], Game.pop.culture_group(p["culture"])]
			"religion": line2 = p["religion"]
			"ethnicity": line2 = p["ethnicity"]
			"trade": line2 = "%s trade node: %.1f value (click to open)" % [p["trade_node"], float(Game.trade.state.get(p["trade_node"], {}).get("value", 0.0))]
			"autonomy":
				if p["owner"] != "":
					line2 = "Autonomy %d%%%s" % [int(Game.eco.autonomy(id)), "" if p["cores"].has(p["owner"]) else " (not a core)"]
			"unrest": line2 = "Unrest %+.1f, rebels %d%%" % [float(p.get("unrest", 0.0)), int(p["rebel_progress"])]
			"region": line2 = p["region"]
		hover_label.text = "%s  ·  %s%s\n%s" % [p["name"], owner, extra, line2]
		if state == "game":
			var info := _hover_details(id)
			if info != "":
				hover_label.text += "\n" + info
	else:
		hover_label.text = "Unexplored"
	hover_label.visible = true
	hover_label.reset_size()


var _soak_t := 0.0
var _soak_step := 0


func _soak(delta: float) -> void:
	_soak_t += delta
	while Game.is_blocked():
		Game.resolve_event(Game.pending_events[0], Game.rng.randi_range(0, Game.pending_events[0]["event"].get("options", [1]).size() - 1))
	if _soak_t < 0.7:
		return
	_soak_t = 0.0
	_soak_step += 1
	Game.set_speed(5)
	var k: String = PANELS[_soak_step % PANELS.size()]
	open_panel(k)
	var ids: Array = Game.owned(Game.player_tag)
	if ids.size() > 0:
		focus_province(ids[_soak_step % ids.size()])
	var mine: Array = Game.mil.armies_of(Game.player_tag)
	if mine.size() > 0:
		_select_army(int(mine[0]["id"]))
	var tags: Array = Game.nations.keys()
	_open_country(tags[_soak_step % tags.size()])
	map.set_mode(map.MODES[_soak_step % map.MODES.size()])
	if _soak_step % 7 == 0:
		var wars: Array = Game.dip.wars_of(Game.player_tag)
		if wars.size() > 0:
			_open_peace(int(wars[0]["id"]))
	if _soak_step % 9 == 0:
		map.set_layer("sky" if map.layer == "ground" else "ground")


func _process(delta: float) -> void:
	if args.has("soak") and state == "game":
		_soak(delta)
	_layout()
	if hover_label.visible:
		var mp := get_viewport().get_mouse_position() + Vector2(16, 18)
		var vp := get_viewport().get_visible_rect().size
		hover_label.position = Vector2(minf(mp.x, vp.x - hover_label.size.x - 4), minf(mp.y, vp.y - hover_label.size.y - 4))


func _layout() -> void:
	## Panels are placed here rather than with anchors, so every panel can simply size to its content.
	var vp := get_viewport().get_visible_rect().size
	var top: float = top_bar.size.y + 8.0 if top_bar.visible else 8.0
	tab_bar.position = Vector2(8, top)
	alerts.position = Vector2(tab_bar.size.x + 16.0 + (panels[open_name].size.x + 8.0 if open_name != "" and panels[open_name].visible else 0.0), top)
	help_overlay.fit_height(vp.y)
	help_overlay.position = ((vp - help_overlay.size) / 2.0).round()
	map_controls.position = Vector2(8, vp.y - map_controls.size.y - 8)
	log_panel.position = Vector2(clampf((vp.x - log_panel.size.x) / 2.0, map_controls.size.x + 16, vp.x), vp.y - log_panel.size.y - 8)
	var left_x: float = tab_bar.size.x + 16.0
	# left-hand windows stop above the map-mode controls so those stay clickable while a window is open
	var avail_h: float = vp.y - top - map_controls.size.y - 16.0
	for k in panels:
		var p = panels[k]
		p.max_height = maxf(240.0, avail_h)
		p.position = Vector2(left_x, top)
	province_panel.max_height = maxf(200.0, vp.y - top - 90.0 - (army_panel.size.y + 10.0 if army_panel.visible else 0.0))
	province_panel.position = Vector2(vp.x - province_panel.size.x - 8, top)
	army_panel.position = Vector2(vp.x - army_panel.size.x - 8, vp.y - army_panel.size.y - 8)
	country_panel.max_height = maxf(200.0, vp.y - top - 120.0)
	country_panel.position = Vector2(vp.x - province_panel.size.x - country_panel.size.x - 20 if province_panel.visible else vp.x - country_panel.size.x - 8, top)
	trade_node_panel.max_height = maxf(200.0, vp.y - top - 120.0)
	trade_node_panel.position = Vector2(vp.x - trade_node_panel.size.x - 8, top)
	peace_panel.max_height = maxf(200.0, vp.y - top - 120.0)
	peace_panel.position = ((vp - peace_panel.size) / 2.0).round()
	nation_select.fit_height(vp.y)
	nation_select.position = Vector2(16, maxf(8.0, (vp.y - nation_select.size.y) / 2.0))
	event_popup.position = ((vp - event_popup.size) / 2.0).round()
	var right_busy: bool = province_panel.visible or country_panel.visible or trade_node_panel.visible or peace_panel.visible or war_panel.visible
	outliner.visible = state == "game" and not right_busy
	outliner.max_h = maxf(120.0, (army_panel.position.y if army_panel.visible else vp.y - 8.0) - top - 60.0)
	outliner.position = Vector2(vp.x - outliner.size.x - 8, top)
	news_popup.position = Vector2(round((vp.x - news_popup.size.x) / 2.0), top + 40.0)
	war_panel.max_height = maxf(200.0, (army_panel.position.y - 10.0 if army_panel.visible else vp.y - 8.0) - top)
	war_panel.position = Vector2(vp.x - war_panel.size.x - 8, top)
	search_box.position = Vector2(round((vp.x - search_box.size.x) / 2.0), top + 8.0)
	# the battle report sits bottom-right, above the army window when that is open
	var br_bottom: float = (army_panel.position.y - 8.0) if army_panel.visible else (vp.y - 8.0)
	battle_report.position = Vector2(vp.x - battle_report.size.x - 8, br_bottom - battle_report.size.y)


func _unhandled_key_input(event: InputEvent) -> void:
	if state != "game" or not event.pressed or event.echo or game_menu.visible:
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if event.shift_pressed and MODE_KEYS.has(event.keycode):
		var modes: Array = map_controls.MODE_LABELS.keys()
		var mi: int = MODE_KEYS.find(event.keycode)
		if mi < modes.size():
			map.set_mode(modes[mi])
			map_controls.set_state(modes[mi], map.layer)
		get_viewport().set_input_as_handled()
		return
	if event.ctrl_pressed and event.keycode == KEY_F:
		search_box.open()
		get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_SPACE:
			top_bar._toggle_pause()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			Game.set_speed(event.keycode - KEY_0)
			top_bar.refresh()
		KEY_TAB:
			map.set_layer("sky" if map.layer == "ground" else "ground")
		KEY_ESCAPE:
			if help_overlay.visible:
				help_overlay.visible = false
			elif army_panel.visible:
				army_panel.close()
			elif trade_node_panel.visible:
				trade_node_panel.close()
			elif war_panel.visible:
				war_panel.close()
			elif peace_panel.visible or country_panel.visible:
				peace_panel.visible = false
				country_panel.visible = false
			elif open_name != "" or province_panel.visible:
				_close_all()
				map.select(-1)
			else:
				game_menu.open()
		KEY_HOME:
			camera.fit_bounds()
		KEY_F1:
			help_overlay.visible = not help_overlay.visible
		_:
			if SHORTCUTS.has(event.keycode):
				open_panel(SHORTCUTS[event.keycode])
			else:
				return
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- automation

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = a.trim_prefix("--")
		if "=" in s:
			args[s.get_slice("=", 0)] = s.get_slice("=", 1)
		else:
			args[s] = true


func _answer_events(keep_last: bool) -> void:
	while Game.is_blocked():
		if keep_last and Game.pending_events.size() == 1:
			return
		Game.resolve_event(Game.pending_events[0], 0)


func _run_automation() -> void:
	var keep := args.has("keep-event")
	if args.has("war"):
		var why: String = Game.dip.can_declare(Game.player_tag, args["war"])
		if why != "":
			print("--war: ", why)
			Game.post("Can't declare war: " + why)
		else:
			Game.dip.declare_war(Game.player_tag, args["war"])
	var days := int(args.get("days", "0"))
	for i in days:
		_answer_events(false)
		Game.advance_day()
	if args.has("until-doomsday"):
		var guard := 0
		while not Game.doomsday_active and guard < 3000:
			_answer_events(false)
			Game.advance_day()
			guard += 1
	_answer_events(keep)
	if args.has("layer"):
		map.set_layer(args["layer"])
	if args.has("mode"):
		map.set_mode(args["mode"])
		map_controls.set_state(args["mode"], map.layer)
	if args.has("zoom"):
		var z := float(args["zoom"])
		camera.zoom = Vector2(z, z)
		map.set_camera_zoom(z)
	if args.has("focus"):
		camera.position = Game.provinces[int(Game.province_ids_by_name[args["focus"]])]["centre"]
	if args.has("at"):   # --at=x,y: centre the camera on a map point (0,0 is where all four seams meet)
		var xy: PackedStringArray = String(args["at"]).split(",")
		camera.position = Vector2(float(xy[0]), float(xy[1]))
	if args.has("select"):
		var id := int(Game.province_ids_by_name.get(args["select"], -1))
		map.set_layer(Game.provinces[id]["layer"])
		map.select(id)
		province_panel.show_province(id)
	if args.has("panel"):
		open_panel(args["panel"])
	if args.has("country"):
		_open_country(args["country"])
	if args.has("fleet-to"):
		var fl: Array = Game.mil.fleets_of(Game.player_tag)
		if fl.size() > 0:
			Game.mil.move_fleet(int(fl[0]["id"]), int(Game.province_ids_by_name.get(args["fleet-to"], -1)))
			for i in int(args.get("sail", "0")):
				while Game.is_blocked():
					Game.resolve_event(Game.pending_events[0], 0)
				Game.advance_day()
			_select_fleet(int(fl[0]["id"]))
	if args.has("node"):
		_open_trade_node(args["node"])
	if args.has("tab"):
		var pp = panels.get("ledger" if args.get("panel", "") == "ledger" else "production")
		if pp:
			pp.mode = args["tab"]
			pp.mark_dirty()
	if args.has("entities"):
		var ent: Dictionary = Game.mil.spawn_entities(Game.portal_id(), 8)
		if not ent.is_empty():
			_select_army(int(ent["id"]))
	if args.has("settings"):
		settings_panel.open()
	if args.has("news"):
		Game.major_news.emit("War Declared", "Snowtusk declares war on Menslosia: Snowtusk Conquest of Menslosia.")
	if args.has("eschaton"):   # jump to half a year before the end and flash the eye
		Game.year = Game.end_year - 1
		Game.month = 7
		_set_corruption(Game.eschaton_corruption())
		if str(args["eschaton"]) != "map":   # --eschaton=map: just the corrupted map, no eye
			eschaton_eye.flash()
	if args.has("howto"):
		help_overlay.visible = true
	if args.has("warview"):
		var ww: Array = Game.dip.wars_of(Game.player_tag)
		if ww.size() > 0:
			_open_war(int(ww[0]["id"]))
	if args.has("search"):
		search_box.open()
		search_box._edit.text = String(args["search"])
		search_box._refresh()
	if args.has("preview"):   # --army --preview="Province": show the march preview to that province
		call_deferred("_update_march_preview", int(Game.province_ids_by_name.get(args["preview"], -1)))   # after --army
	if args.has("group"):
		var ids: Array = []
		for a in Game.mil.armies_of(Game.player_tag):
			ids.append(int(a["id"]))
		_select_group(ids)
	if args.has("army"):
		var mine: Array = Game.mil.armies_of(Game.player_tag)
		if mine.size() > 0:
			_select_army(int(mine[0]["id"]))
	if args.has("peace"):
		var wars: Array = Game.dip.wars_of(Game.player_tag)
		if wars.size() > 0:
			_open_peace(int(wars[0]["id"]))
	top_bar.refresh()
	log_panel.refresh()
	alerts.refresh()
	_update_badges()
	if Game.is_blocked():
		event_popup._show_next()


func _screenshot_after_frames(path: String) -> void:
	get_viewport().gui_disable_input = true   # no tooltips from wherever the cursor happens to be
	for i in 30:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("screenshot saved: ", path)
	get_tree().quit()
