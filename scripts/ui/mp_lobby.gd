extends PanelContainer
## The multiplayer window (EU4's lobby): host a game or join one with its code, then everyone picks
## a nation and chats while the host gets ready to start. A player can also join a game that is
## already running: they pick a nation still played by the AI and take it over.

signal back_pressed
signal nation_focused(tag: String)

const UI = preload("res://scripts/ui/ui_util.gd")
const Settings = preload("res://scripts/settings.gd")
const WIDTH := 640.0

var _box: VBoxContainer
var _name_edit: LineEdit
var _code_edit: LineEdit
var _chat_edit: LineEdit
var _chat_lines: Array = []
var _status := ""
var _connecting := false
var _list_h := 360.0
var _net_status := ""


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.tex_box("panel.png", 12, 18, 16, true))
	mouse_filter = Control.MOUSE_FILTER_STOP
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	_box.custom_minimum_size.x = WIDTH
	add_child(_box)
	visible = false
	Net.lobby_changed.connect(func(): _connecting = false; if visible: refresh())
	Net.join_failed.connect(func(why): _connecting = false; _status = why; if visible: refresh())
	Net.chat_received.connect(_on_chat)
	Net.ended.connect(_on_ended)
	Net.status_changed.connect(func(t): _net_status = t; if visible: refresh())


func _on_ended(reason: String) -> void:
	_chat_lines.clear()
	if reason != "":
		_status = reason
	if visible:
		refresh()


func open(status: String = "") -> void:
	visible = true
	_status = status
	refresh()


func fit_height(viewport_h: float) -> void:
	var h := clampf(viewport_h - 420.0, 120.0, 360.0)
	if absf(h - _list_h) > 1.0:
		_list_h = h
		if visible:
			refresh()


func _player_name() -> String:
	var n := String(Settings.get_value("player_name"))
	return n if n != "" else Net.my_name


func refresh() -> void:
	UI.clear(_box)
	_chat_edit = null
	if not Net.online():
		_build_start()
	else:
		_build_lobby()
	reset_size()


# ---------------------------------------------------------------- host or join

func _build_start() -> void:
	_box.add_child(UI.heading("Multiplayer", 24))
	_box.add_child(UI.label("One player hosts and gets a join code. Everyone else types that code to join. The host's computer runs the world; you all play in it at the same time.", 13, UI.TEXT_DIM, WIDTH))
	_box.add_child(UI.divider())
	_name_edit = LineEdit.new()
	_name_edit.text = _player_name()
	_name_edit.max_length = 24
	_name_edit.custom_minimum_size.x = 260
	_name_edit.placeholder_text = "Your name"
	_box.add_child(UI.row([_fixed(UI.label("Your name", 14), 120), _name_edit]))
	_box.add_child(UI.heading("Host a game"))
	_box.add_child(UI.label("Opens a game on this computer and gives you a code to share.", 12, UI.TEXT_DIM, WIDTH))
	var host_b = UI.button("Host a game", _host)
	host_b.custom_minimum_size = Vector2(200, 38)
	_box.add_child(host_b)
	_box.add_child(UI.heading("Join a game"))
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "paste the host's code"
	_code_edit.max_length = 80
	_code_edit.custom_minimum_size.x = 300
	_code_edit.text_submitted.connect(func(_t): _join())
	var join_b = UI.button("Join" if not _connecting else "Connecting...", _join)
	join_b.disabled = _connecting
	join_b.custom_minimum_size = Vector2(120, 34)
	_box.add_child(UI.row([_fixed(UI.label("Join code", 14), 120), _code_edit, join_b]))
	_box.add_child(UI.label("No router setup needed. Testing on one computer? In the Godot editor, Debug > Customize Run Instances runs two copies: host in one, join with the code in the other.", 12, UI.TEXT_DIM, WIDTH))
	if _status != "":
		_box.add_child(UI.label(_status, 13, UI.BAD, WIDTH))
	var buttons = HBoxContainer.new()
	buttons.add_child(UI.button("Back", func(): back_pressed.emit()))
	_box.add_child(buttons)


func _fixed(c: Control, w: float) -> Control:
	c.custom_minimum_size.x = w
	return c


func _save_name() -> void:
	if _name_edit != null:
		Settings.set_value("player_name", _name_edit.text.strip_edges())


func _host() -> void:
	_save_name()
	_status = ""
	var err: String = await Net.host(_player_name())
	_status = err
	refresh()


func _join() -> void:
	_save_name()
	var err := Net.join(_code_edit.text, _player_name())
	_status = err
	_connecting = err == ""
	refresh()


# ---------------------------------------------------------------- the lobby

func _build_lobby() -> void:
	var host := Net.is_host()
	var mine: String = Net.me().get("tag", "")
	_box.add_child(UI.heading("Multiplayer Lobby" + ("  -  game in progress" if Net.in_game else ""), 24))
	if Net.players.is_empty():
		_box.add_child(UI.label(_net_status if _net_status != "" else "Connecting to the host...", 14, UI.TEXT_DIM, WIDTH))
		_box.add_child(UI.row([UI.button("Cancel", func(): Net.leave(); refresh())]))
		return
	# the join codes
	var code_l = UI.label(Net.code, 20, UI.GOLD)
	var copy = UI.button("Copy", func(): DisplayServer.clipboard_set(Net.code); _status = "Code copied: paste it to your friends."; refresh())
	_box.add_child(UI.row([UI.label("Join code:", 14), code_l, copy], 12))
	if host:
		if Net.internet_error == "":
			_box.add_child(UI.label("Share this code: it works from anywhere, with no router setup. (The game's matchmaker introduces the computers, and passes the game along itself if a router won't let them talk directly.)", 12, UI.TEXT_DIM, WIDTH))
			var lan = UI.button("Copy", func(): DisplayServer.clipboard_set(Net.lan_code); _status = "Home-network code copied."; refresh())
			_box.add_child(UI.row([UI.label("Same computer or home network (faster):  " + Net.lan_code, 12, UI.TEXT_DIM), lan]))
		else:
			_box.add_child(UI.label("Only this computer and your home network can join: " + Net.internet_error, 12, UI.WARN, WIDTH))
	_box.add_child(UI.divider())
	var cols = HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	_box.add_child(cols)
	# left: nations
	var left = VBoxContainer.new()
	left.custom_minimum_size.x = 300
	left.add_child(UI.heading("Nations"))
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(300, _list_h)
	left.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 3)
	scroll.add_child(list)
	var taken := Net.taken()
	var tags: Array = Game.nations.keys()
	tags.sort_custom(func(a, b): return Game.nation_dev(a) > Game.nation_dev(b))
	for t in tags:
		var n: Dictionary = Game.nations[t]
		if not n["playable"] or not n["alive"]:
			continue
		var who: String = taken.get(t, "")
		var b = UI.button("", func(): _pick(t))
		b.toggle_mode = true
		b.button_pressed = t == mine
		b.disabled = (who != "" and t != mine) or (Net.in_game and mine != "")
		b.custom_minimum_size = Vector2(286, 30)
		var row = HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 8
		row.offset_right = -8
		row.add_theme_constant_override("separation", 8)
		row.add_child(UI.swatch(n["colour"], Vector2(12, 18)))
		row.add_child(UI.label(n["short"], 14, UI.GOLD if t == mine else UI.TEXT))
		row.add_child(UI.spacer())
		row.add_child(UI.label(who if who != "" else n["difficulty"], 12, UI.GOOD if who != "" else UI.TEXT_DIM))
		b.add_child(row)
		list.add_child(b)
	cols.add_child(left)
	# right: players and chat
	var right = VBoxContainer.new()
	right.custom_minimum_size.x = WIDTH - 314
	right.add_theme_constant_override("separation", 6)
	right.add_child(UI.heading("Players (%d)" % Net.players.size()))
	var ids: Array = Net.players.keys()
	ids.sort()
	for id in ids:
		var p: Dictionary = Net.players[id]
		var nation: String = Game.nation_name(p["tag"]) if p["tag"] != "" else "choosing..."
		right.add_child(UI.label("%s%s  -  %s" % [p["name"], " (host)" if int(id) == 1 else (" (you)" if int(id) == Net.my_id() else ""), nation], 13,
			UI.GOLD if int(id) == Net.my_id() else UI.TEXT, WIDTH - 320))
	right.add_child(UI.heading("Chat"))
	var chat_scroll = ScrollContainer.new()
	chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	chat_scroll.custom_minimum_size = Vector2(WIDTH - 320, maxf(80.0, _list_h - 40.0 - 22.0 * ids.size()))
	var chat_box = VBoxContainer.new()
	chat_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for line in _chat_lines:
		chat_box.add_child(UI.label(line, 12, UI.TEXT if not line.begins_with("* ") else UI.TEXT_DIM, WIDTH - 340))
	chat_scroll.add_child(chat_box)
	right.add_child(chat_scroll)
	chat_scroll.ready.connect(func(): chat_scroll.set_deferred("scroll_vertical", 100000))
	_chat_edit = LineEdit.new()
	_chat_edit.placeholder_text = "Say something (Enter to send)"
	_chat_edit.max_length = 200
	_chat_edit.text_submitted.connect(func(t): Net.send_chat(t); _chat_edit.text = "")
	right.add_child(_chat_edit)
	cols.add_child(right)
	if _status != "":
		_box.add_child(UI.label(_status, 13, UI.GOLD, WIDTH))
	# buttons
	var buttons = HBoxContainer.new()
	buttons.add_child(UI.button("Leave", func(): Net.leave(); refresh()))
	buttons.add_child(UI.spacer())
	if host and not Net.in_game:
		var start = UI.action("Start the game", "" if mine != "" else "Pick your nation first.", _start)
		start.custom_minimum_size = Vector2(200, 40)
		buttons.add_child(start)
	elif not host and not Net.in_game:
		buttons.add_child(UI.label("Waiting for the host to start...", 14, UI.TEXT_DIM))
	elif not host and mine == "":
		buttons.add_child(UI.label("The game is under way: pick a nation to take it over from the AI.", 13, UI.GOLD))
	_box.add_child(buttons)


func _pick(tag: String) -> void:
	nation_focused.emit(tag)
	var mine: String = Net.me().get("tag", "")
	Net.pick("" if tag == mine and not Net.in_game else tag)


func _start() -> void:
	var why := Net.start()
	if why != "":
		_status = why
		refresh()


func _on_chat(who: String, text: String) -> void:
	_chat_lines.append(("* " + text) if who == "" else "%s: %s" % [who, text])
	if _chat_lines.size() > 60:
		_chat_lines.pop_front()
	if visible and Net.online():
		var had_focus := _chat_edit != null and _chat_edit.has_focus()
		var draft := _chat_edit.text if _chat_edit != null else ""
		refresh()
		if _chat_edit != null:
			_chat_edit.text = draft
			if had_focus:
				_chat_edit.grab_focus()
