extends Node
## Multiplayer, EU4-style: one player hosts and gets a join code; the others type the code to join.
## The host's computer runs the world. Everyone else sends what they do (move an army, take a loan,
## answer an event...) to the host, which checks it is really theirs to do, runs it, and sends the
## world back a few times a second.
##
## The code holds the host's address, port and a random key, so nobody joins without it. It works
## between copies of the game on one computer (in the Godot editor: Debug > Customize Run Instances,
## run 2 or more), across a home network, and over the internet when the host's router forwards the
## port to their computer.

signal lobby_changed
signal chat_received(who: String, text: String)
signal began                     # the game has started for us (or we joined one already running)
signal ended(reason: String)     # we left, or the host did
signal join_failed(reason: String)

const PORT := 7351
const PORTS_TO_TRY := 8
const MAX_PLAYERS := 16
const PROTOCOL := 1
const SNAPSHOT_EVERY := 0.25    # seconds between world updates to the clients (when something changed)
const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"   # Crockford's base 32: no I, L, O or U
const CODE_FILE := "user://last_join_code.txt"          # for test runs (--join=auto)

enum { OFFLINE, HOST, CLIENT }

## What a player may ask the host to do, and how the host checks it is theirs:
## [kind, argument index]. "tag": that argument is their nation. "army"/"fleet": their army or fleet
## id. "armies": a list of their army ids. "event": one of their pending events. "any": anyone.
const ACTIONS := {
	"set_speed": ["any", 0],
	"resolve_event": ["event", 0],
	"explore": ["tag", 0], "take_decision": ["tag", 0], "claim_mission": ["tag", 0], "set_maintenance": ["tag", 0],
	"eco.develop": ["tag", 0], "eco.build": ["tag", 0], "eco.cancel_build": ["tag", 0], "eco.colonize": ["tag", 0],
	"eco.change_autonomy": ["tag", 0], "eco.take_loan": ["tag", 0], "eco.repay_loan": ["tag", 0],
	"pop.make_core": ["tag", 0], "pop.start_conversion": ["tag", 0], "pop.harsh_treatment": ["tag", 0],
	"pop.convert_culture": ["tag", 0], "pop.accept_culture": ["tag", 0],
	"prog.research": ["tag", 0], "prog.take_idea": ["tag", 0], "prog.pick_group": ["tag", 0], "prog.enact": ["tag", 0],
	"court.raise_stability": ["tag", 0], "court.reduce_we": ["tag", 0], "court.hire": ["tag", 0], "court.dismiss": ["tag", 0],
	"standing.take_ability": ["tag", 0], "standing.grant": ["tag", 0], "standing.revoke": ["tag", 0], "standing.call_support": ["tag", 0],
	"trade.send_merchant": ["tag", 0], "trade.recall_merchant": ["tag", 0],
	"mil.recruit": ["tag", 0], "mil.build_ship": ["tag", 0], "mil.recruit_leader": ["tag", 0],
	"mil.move_army": ["army", 0], "mil.split_army": ["army", 0], "mil.disband_army": ["army", 0], "mil.stop_army": ["army", 0],
	"mil.assign_leader": ["army", 0], "mil.merge_armies": ["armies", 0],
	"mil.move_fleet": ["fleet", 0], "mil.disband_fleet": ["fleet", 0],
	"dip.act": ["tag", 1], "dip.call_ally": ["tag", 1], "dip.propose_peace": ["tag", 1],
}
## What a client's call returns at once (the host's real answer arrives as a message).
const CLIENT_RESULT := {"dip.act": "", "dip.call_ally": "", "dip.propose_peace": "", "mil.split_army": {}}

var mode := OFFLINE
var code := ""
var port := PORT
var address := ""
var players := {}        # peer id -> {"name": String, "tag": String}
var in_game := false     # the host has started the game
var my_name := ""
var last_error := ""
var _key := 0
var _dirty := false
var _since := 0.0
var _join_key := 0
var _auth_names := {}


func _ready() -> void:
	my_name = OS.get_environment("USERNAME") if OS.get_environment("USERNAME") != "" else "Player"
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): print("[net] connected to the host"))
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	var mp := multiplayer as SceneMultiplayer
	mp.peer_authenticating.connect(_on_authenticating)
	mp.peer_authentication_failed.connect(func(id): print("[net] authentication failed for ", id))


func online() -> bool:
	return mode != OFFLINE


func is_host() -> bool:
	return mode == HOST


func is_client() -> bool:
	return mode == CLIENT


func my_id() -> int:
	return multiplayer.get_unique_id() if online() else 1


func me() -> Dictionary:
	return players.get(my_id(), {})


func tag_owner(tag: String) -> int:
	for id in players:
		if players[id]["tag"] == tag:
			return id
	return 0


# ---------------------------------------------------------------- join codes

static func make_code(ip: String, p: int, key: int) -> String:
	## 4 address bytes, 2 port bytes and a 2-byte key, written as 13 base-32 characters.
	var bytes: Array = []
	for x in ip.split("."):
		bytes.append(int(x) & 255)
	bytes.append_array([(p >> 8) & 255, p & 255, (key >> 8) & 255, key & 255])
	var bits := "0"   # 65 bits make 13 characters of 5
	for b in bytes:
		for i in range(7, -1, -1):
			bits += "1" if (b >> i) & 1 else "0"
	var out := ""
	for c in 13:
		out += ALPHABET[bits.substr(c * 5, 5).bin_to_int()]
	return "%s-%s-%s" % [out.substr(0, 4), out.substr(4, 4), out.substr(8)]


static func read_code(text: String) -> Dictionary:
	## {ip, port, key}, or {} if it isn't a code. Forgiving about dashes, spaces, case and look-alikes.
	var s := text.strip_edges().to_upper().replace("-", "").replace(" ", "")
	s = s.replace("O", "0").replace("I", "1").replace("L", "1")
	if s.length() != 13:
		return {}
	var bits := ""
	for ch in s:
		var v := ALPHABET.find(ch)
		if v < 0:
			return {}
		var five := ""
		for i in range(4, -1, -1):
			five += "1" if (v >> i) & 1 else "0"
		bits += five
	if bits[0] != "0":
		return {}
	var bytes: Array = []
	for i in 8:
		bytes.append(bits.substr(1 + i * 8, 8).bin_to_int())
	var p: int = (bytes[4] << 8) | bytes[5]
	if p == 0:
		return {}
	return {"ip": "%d.%d.%d.%d" % [bytes[0], bytes[1], bytes[2], bytes[3]], "port": p, "key": (bytes[6] << 8) | bytes[7]}


static func lan_address() -> String:
	## This computer's address on the home network (what other computers there can reach).
	var best := ""
	for a in IP.get_local_addresses():
		if a.count(".") != 3 or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		if a.begins_with("192.168.") or a.begins_with("10."):
			return a
		if best == "":
			best = a
	return best if best != "" else "127.0.0.1"


func code_for(ip: String) -> String:
	## Host: the same game's code with another address (the public one, for players over the internet).
	return make_code(ip, port, _key) if mode == HOST else ""


# ---------------------------------------------------------------- hosting and joining

func host(player_name: String) -> String:
	## Opens a game for others to join. Returns "" or what went wrong.
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := ERR_CANT_CREATE
	for i in PORTS_TO_TRY:   # a second copy of the game on this computer hosts on the next port
		err = peer.create_server(PORT + i, MAX_PLAYERS)
		if err == OK:
			port = PORT + i
			break
	if err != OK:
		last_error = "Could not open a network port (%d-%d): %s." % [PORT, PORT + PORTS_TO_TRY - 1, error_string(err)]
		return last_error
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_key = rng.randi_range(1, 65535)
	_set_auth()
	multiplayer.multiplayer_peer = peer
	mode = HOST
	my_name = _clean_name(player_name)
	players = {1: {"name": my_name, "tag": ""}}
	in_game = false
	address = lan_address()
	code = make_code(address, port, _key)
	var f := FileAccess.open(CODE_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(code)
	print("[net] hosting on port %d, join code %s" % [port, code])
	lobby_changed.emit()
	return ""


func join(join_code: String, player_name: String) -> String:
	## Connects to a host from their join code. Returns "" if the attempt started; the result
	## arrives as lobby_changed (in), or join_failed.
	var c := read_code(join_code)
	if c.is_empty():
		last_error = "That isn't a join code. It looks like ABCD-EFGH-JKMNP (13 letters and numbers)."
		return last_error
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(c["ip"], c["port"])
	if err != OK:
		last_error = "Could not start connecting: %s." % error_string(err)
		return last_error
	_join_key = c["key"]
	my_name = _clean_name(player_name)
	_set_auth()
	multiplayer.multiplayer_peer = peer
	mode = CLIENT
	address = c["ip"]
	port = c["port"]
	code = join_code.strip_edges().to_upper()
	players = {}
	in_game = false
	print("[net] joining %s:%d" % [c["ip"], c["port"]])
	return ""


func leave(reason: String = "") -> void:
	var was := mode
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	(multiplayer as SceneMultiplayer).auth_callback = Callable()
	mode = OFFLINE
	players = {}
	in_game = false
	code = ""
	if Game.humans.size() > 0:
		Game.humans = {}
		for t in Game.nations:
			Game.nations[t]["ai"] = not Game.is_human(t)
	if was != OFFLINE:
		ended.emit(reason)
		lobby_changed.emit()


func _clean_name(s: String) -> String:
	s = s.strip_edges().substr(0, 24)
	return s if s != "" else "Player"


func _set_auth() -> void:
	var mp := multiplayer as SceneMultiplayer
	mp.auth_callback = _on_auth
	mp.auth_timeout = 5.0


func _on_authenticating(id: int) -> void:
	## Both ends: the client sends its key and name; the host waits for that.
	if mode == CLIENT and id == 1:
		var hello := {"key": _join_key, "protocol": PROTOCOL, "name": my_name}
		(multiplayer as SceneMultiplayer).send_auth(1, var_to_bytes(hello))


func _on_auth(id: int, data: PackedByteArray) -> void:
	var mp := multiplayer as SceneMultiplayer
	if mode == HOST:
		var hello: Variant = bytes_to_var(data)
		var why := ""
		if not (hello is Dictionary) or int(hello.get("key", -1)) != _key:
			why = "Wrong join code."
		elif int(hello.get("protocol", 0)) != PROTOCOL:
			why = "The host is running a different version of the game."
		elif players.size() >= MAX_PLAYERS:
			why = "The game is full."
		if why != "":
			print("[net] refused peer ", id, ": ", why)
			mp.send_auth(id, var_to_bytes({"ok": false, "why": why}))
			return
		_auth_names[id] = _clean_name(String(hello.get("name", "Player")))
		mp.send_auth(id, var_to_bytes({"ok": true}))
		mp.complete_auth(id)
	elif mode == CLIENT and id == 1:
		var r: Variant = bytes_to_var(data)
		if r is Dictionary and r.get("ok", false):
			mp.complete_auth(1)
		else:
			var why: String = r.get("why", "The host refused.") if r is Dictionary else "The host refused."
			last_error = why
			leave()
			join_failed.emit(why)


func _on_peer_connected(id: int) -> void:
	print("[net] peer connected ", id)
	if mode != HOST:
		return
	players[id] = {"name": _auth_names.get(id, "Player"), "tag": ""}
	_auth_names.erase(id)
	_send_lobby()
	_say("%s joined." % players[id]["name"])


func _on_peer_disconnected(id: int) -> void:
	print("[net] peer disconnected ", id)
	if mode != HOST or not players.has(id):
		return
	var p: Dictionary = players[id]
	players.erase(id)
	var tag: String = p["tag"]
	if tag != "" and in_game and Game.nations.has(tag):
		Game.humans.erase(tag)
		Game.nations[tag]["ai"] = true
		_host_post("%s has left the game. The AI takes over %s." % [p["name"], Game.nation_name(tag)])
		mark_dirty()
	_send_lobby()
	_say("%s left." % p["name"])


func _on_connection_failed() -> void:
	last_error = "Could not reach the host at %s:%d. Check the code; from another network the host must forward port %d on their router." % [address, port, port]
	leave()
	join_failed.emit(last_error)


func _on_server_disconnected() -> void:
	leave("The host closed the game.")


func _host_post(text: String) -> void:
	## A message from the host to everyone's log.
	Game._sim_depth += 1
	Game.post(text)
	Game._sim_depth -= 1


func _say(text: String) -> void:
	## A line in everyone's chat from the game itself.
	if mode == HOST:
		_r_chat.rpc("", text)
		_r_chat("", text)


# ---------------------------------------------------------------- the lobby

func pick(tag: String) -> void:
	## Choose (or with "" give up) a nation. Clients ask the host.
	if mode == CLIENT:
		_r_pick.rpc_id(1, tag)
	elif mode == HOST:
		var why := _assign(1, tag)
		if why != "":
			chat_received.emit("", why)


func _assign(id: int, tag: String) -> String:
	if not players.has(id):
		return "Not in this game."
	if tag != "":
		if not Game.nations.has(tag) or not Game.nations[tag]["playable"] or not Game.nations[tag]["alive"]:
			return "You can't play that nation."
		var holder := tag_owner(tag)
		if holder != 0 and holder != id:
			return "%s is already taken by %s." % [Game.nation_name(tag), players[holder]["name"]]
	if in_game and players[id]["tag"] != "":
		return "You already play %s." % Game.nation_name(players[id]["tag"])
	players[id]["tag"] = tag
	if in_game and tag != "" and id != 1:
		# joining a game already under way: their nation stops being the AI's
		Game.humans[tag] = true
		Game.nations[tag]["ai"] = false
		_host_post("%s now plays %s." % [players[id]["name"], Game.nation_name(tag)])
		_r_begin.rpc_id(id, tag, _pack(Game.snapshot()))
	_send_lobby()
	return ""


func start() -> String:
	## Host: start the game with everyone's picks.
	if mode != HOST:
		return "Only the host can start."
	var mine: String = players[1]["tag"]
	if mine == "":
		return "Pick a nation first."
	var others: Array = []
	for id in players:
		if id != 1 and players[id]["tag"] != "":
			others.append(players[id]["tag"])
	Game.new_game(mine, 4289, others)
	in_game = true
	var snap := _pack(Game.snapshot())
	for id in players:
		if id != 1 and players[id]["tag"] != "":
			_r_begin.rpc_id(id, players[id]["tag"], snap)
	_send_lobby()
	began.emit()
	return ""


func taken() -> Dictionary:
	var out := {}
	for id in players:
		if players[id]["tag"] != "":
			out[players[id]["tag"]] = players[id]["name"]
	return out


func send_chat(text: String) -> void:
	text = text.strip_edges().substr(0, 200)
	if text == "" or not online():
		return
	if mode == HOST:
		_r_chat.rpc(my_name, text)
		_r_chat(my_name, text)
	else:
		_r_chat_up.rpc_id(1, text)


func _send_lobby() -> void:
	if mode != HOST:
		return
	_r_lobby.rpc(players, in_game)
	lobby_changed.emit()


# ---------------------------------------------------------------- playing

func request(path: String, args: Array) -> Variant:
	## Game.act lands here. Offline and on the host the action runs at once; a client sends it.
	if mode == CLIENT:
		if not ACTIONS.has(path):
			push_warning("Not a multiplayer action: " + path)
			return null
		_r_act.rpc_id(1, path, _encode(args))
		if path == "resolve_event" and args.size() > 0 and args[0] is Dictionary:
			Game.answered[int(args[0].get("uid", -1))] = true   # don't show it again while the host catches up
		return CLIENT_RESULT.get(path, true)
	var out: Variant = Game.call_path(path, args)
	mark_dirty()
	return out


func mark_dirty() -> void:
	_dirty = true


func tell(tag: String, text: String) -> void:
	if mode != HOST:
		return
	var id := tag_owner(tag)
	if id > 1:
		_r_post.rpc_id(id, text, [], "", false)


func broadcast_post(text: String, tags: Array, major: String, near: bool) -> void:
	if mode == HOST and in_game:
		for id in players:
			if id != 1 and players[id]["tag"] != "":
				_r_post.rpc_id(id, text, tags, major, near)


func send_battle_report(tags: Array, report: Dictionary) -> void:
	if mode != HOST:
		return
	var done := {}
	for t in tags:
		var id := tag_owner(t)
		if id > 1 and not done.has(id):
			done[id] = true
			_r_battle.rpc_id(id, report)


func _process(delta: float) -> void:
	if mode != HOST or not in_game:
		return
	_since += delta
	if _dirty and _since >= SNAPSHOT_EVERY:
		_since = 0.0
		_dirty = false
		var snap: Array = []
		for id in players:
			if id != 1 and players[id]["tag"] != "":
				if snap.is_empty():
					snap = _pack(Game.snapshot())
				_r_snap.rpc_id(id, snap)


func _pack(d: Dictionary) -> Array:
	var raw := var_to_bytes(d)
	return [raw.size(), raw.compress(FileAccess.COMPRESSION_ZSTD)]


func _unpack(p: Array) -> Variant:
	if p.size() != 2 or not (p[1] is PackedByteArray):
		return null
	var comp: PackedByteArray = p[1]
	return bytes_to_var(comp.decompress(int(p[0]), FileAccess.COMPRESSION_ZSTD))


func _encode(args: Array) -> Array:
	## Things that only exist on the host are sent as references: a war by its id, an event by its number.
	var out: Array = []
	for a in args:
		if a is Dictionary and a.has("event") and a.has("uid"):
			out.append({"__event": int(a["uid"])})
		elif a is Dictionary and a.has("id") and Game.wars.has(a["id"]) and Game.wars[a["id"]] == a:
			out.append({"__war": int(a["id"])})
		else:
			out.append(a)
	return out


func _decode(args: Array) -> Variant:
	var out: Array = []
	for a in args:
		if a is Dictionary and a.has("__event"):
			var inst: Dictionary = Game.event_by_uid(int(a["__event"]))
			if inst.is_empty():
				return null
			out.append(inst)
		elif a is Dictionary and a.has("__war"):
			if not Game.wars.has(int(a["__war"])):
				return null
			out.append(Game.wars[int(a["__war"])])
		else:
			out.append(a)
	return out


func check(path: String, args: Array, tag: String) -> String:
	## Is this player allowed to do this? "" when they are.
	if not ACTIONS.has(path):
		return "Not allowed."
	var rule: Array = ACTIONS[path]
	var i: int = rule[1]
	if rule[0] != "any" and args.size() <= i:
		return "Not allowed."
	match rule[0]:
		"any":
			return ""
		"tag":
			return "" if typeof(args[i]) == TYPE_STRING and args[i] == tag else "That isn't your nation."
		"army":
			var a: Dictionary = Game.armies.get(args[i], {})
			if a.is_empty() or a["owner"] != tag:
				return "That isn't your army."
			if path == "mil.assign_leader" and args.size() > 1 and int(args[1]) >= 0:
				for l in Game.nations[tag]["leaders"]:
					if int(l["id"]) == int(args[1]):
						return ""
				return "That isn't your general."
			return ""
		"armies":
			if not (args[i] is Array):
				return "Not allowed."
			for id in args[i]:
				if Game.armies.get(id, {}).get("owner", "") != tag:
					return "That isn't your army."
			return ""
		"fleet":
			return "" if Game.fleets.get(args[i], {}).get("owner", "") == tag else "That isn't your fleet."
		"event":
			return "" if args[i] is Dictionary and args[i].get("tag", "") == tag else "That isn't your event."
	return "Not allowed."


# ---------------------------------------------------------------- messages between computers

@rpc("any_peer", "call_remote", "reliable")
func _r_act(path: String, args: Array) -> void:
	if mode != HOST or not in_game:
		return
	var id := multiplayer.get_remote_sender_id()
	var tag: String = players.get(id, {}).get("tag", "")
	if tag == "":
		return
	var dec: Variant = _decode(args)
	if dec == null:
		return   # the event was answered or the war ended in the meantime
	var why := check(path, dec, tag)
	if why != "":
		_r_post.rpc_id(id, why, [], "", false)
		return
	var out: Variant = Game.call_path(path, dec)
	if out is String and out != "":
		_r_post.rpc_id(id, out, [], "", false)
	mark_dirty()


@rpc("any_peer", "call_remote", "reliable")
func _r_pick(tag: String) -> void:
	if mode != HOST:
		return
	var id := multiplayer.get_remote_sender_id()
	var why := _assign(id, tag)
	if why != "":
		_r_chat.rpc_id(id, "", why)


@rpc("any_peer", "call_remote", "reliable")
func _r_chat_up(text: String) -> void:
	if mode != HOST:
		return
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id):
		return
	text = text.strip_edges().substr(0, 200)
	if text == "":
		return
	_r_chat.rpc(players[id]["name"], text)
	_r_chat(players[id]["name"], text)


@rpc("authority", "call_remote", "reliable")
func _r_chat(who: String, text: String) -> void:
	chat_received.emit(who, text)


@rpc("authority", "call_remote", "reliable")
func _r_lobby(p: Dictionary, started: bool) -> void:
	players = p
	in_game = started
	lobby_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _r_begin(tag: String, packed: Array) -> void:
	var s: Variant = _unpack(packed)
	if not (s is Dictionary):
		return
	Game.started = false
	Game.player_tag = tag
	Game.log_lines.clear()
	Game.world_lines.clear()
	Game.apply_snapshot(s)
	Game.post("%s. You play %s." % [Game.date_string(), Game.nation_name(tag)])
	in_game = true
	began.emit()


@rpc("authority", "call_remote", "reliable")
func _r_snap(packed: Array) -> void:
	if mode != CLIENT or not Game.started:
		return
	var s: Variant = _unpack(packed)
	if s is Dictionary:
		Game.apply_snapshot(s)


@rpc("authority", "call_remote", "reliable")
func _r_post(text: String, tags: Array, major: String, near: bool) -> void:
	Game.post(text, tags, major, near)


@rpc("authority", "call_remote", "reliable")
func _r_battle(report: Dictionary) -> void:
	Game.battle_report.emit(report)
