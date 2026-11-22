extends Node
## Puts the host's game on the internet without touching any router: a client for a bore server
## (github.com/ekzhang/bore, MIT; bore.pub is its free public one). The host keeps one ordinary
## outgoing TCP connection to the server, which gives it a public port. Whenever a player connects to
## that port, the server says so, the host opens another outgoing connection to accept them, and this
## script passes the bytes between it and the game's own server on this computer.
##
## Everything is an outgoing TCP connection (like loading a web page), so strict routers, symmetric
## NAT and carrier-grade NAT can't block it; and name lookups blocked by a DNS filter (a Pi-hole)
## fall back to the server's known address.
##
## Protocol: JSON messages ending in a 0 byte, on port 7835. Us: {"Hello": 0} (any port), then
## {"Accept": "<id>"} on a new connection per player. Server: {"Hello": <public port>},
## {"Connection": "<id>"}, "Heartbeat", {"Error": "..."}.

signal lost   # the connection to the tunnel server dropped: new players can't join from outside

const CONTROL_PORT := 7835
## Where the built-in tunnel server lives, for networks whose DNS blocks its name (a Pi-hole or other
## blocker answers 0.0.0.0, or nothing, for names on its lists).
const KNOWN_ADDRESSES := {"bore.pub": "159.223.110.159"}
const CACHE_PATH := "user://tunnel_address.cfg"
static var fake_dns := ""   # test runs: pretend the name lookup answered this (--mp-fake-dns=0.0.0.0)

var server_ip := ""
var public_port := 0     # players connect to server_ip:public_port
var local_port := 0      # the game's own server on this computer
var _ctl: StreamPeerTCP
var _buf := PackedByteArray()
var _pairs: Array = []
var _open := false


func is_open() -> bool:
	return _open


func open(server: String, game_port: int) -> String:
	## Asks the server for a public port that leads to `game_port` here. Returns "" or what went wrong.
	close()
	local_port = game_port
	server_ip = server if server.is_valid_ip_address() else find_address(server)
	if server_ip == "":
		return "Could not find the game's internet relay %s (no internet?)." % server
	_ctl = StreamPeerTCP.new()
	if _ctl.connect_to_host(server_ip, CONTROL_PORT) != OK:
		_ctl = null
		return "Could not reach the game's internet relay."
	var t := 0.0
	while _ctl != null and _ctl.get_status() == StreamPeerTCP.STATUS_CONNECTING and t < 8.0:
		await get_tree().create_timer(0.05).timeout
		if _ctl != null:
			_ctl.poll()
		t += 0.05
	if _ctl == null or _ctl.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		close()
		return "Could not reach the game's internet relay (%s). Is something blocking the game's connections?" % server
	_send(_ctl, {"Hello": 0})
	t = 0.0
	while public_port == 0 and t < 8.0 and _ctl != null:
		await get_tree().create_timer(0.05).timeout
		_read_control()
		t += 0.05
	if public_port == 0:
		close()
		return "The game's internet relay did not answer."
	_open = true
	return ""


func close() -> void:
	for pair in _pairs:
		pair["remote"].disconnect_from_host()
		pair["local"].disconnect_from_host()
	_pairs.clear()
	if _ctl != null:
		_ctl.disconnect_from_host()
	_ctl = null
	_buf = PackedByteArray()
	public_port = 0
	_open = false


static func find_address(host: String) -> String:
	## The server's IPv4 address. A blocked or failed lookup falls back to the address that worked
	## last time on this computer, then to the one built into the game, so a DNS blocker can't stop it.
	var ip := fake_dns if fake_dns != "" else IP.resolve_hostname(host, IP.TYPE_IPV4)
	var cache := ConfigFile.new()
	cache.load(CACHE_PATH)
	if usable(ip):
		if cache.get_value("addresses", host, "") != ip:
			cache.set_value("addresses", host, ip)
			cache.save(CACHE_PATH)
		return ip
	var why := "blocked by this network's DNS (Pi-hole?)" if ip != "" else "not found"
	for fallback in [String(cache.get_value("addresses", host, "")), String(KNOWN_ADDRESSES.get(host, ""))]:
		if usable(fallback):
			print("[net] the relay's name was %s (got \"%s\"); using its address %s" % [why, ip, fallback])
			return fallback
	return ""


static func usable(ip: String) -> bool:
	## A real IPv4 address, not one of the "blocked" answers DNS blockers give.
	return ip != "" and ip.is_valid_ip_address() and ip.count(".") == 3 and not ip.begins_with("0.") \
		and not ip.begins_with("127.") and ip != "255.255.255.255"


func _send(peer: StreamPeerTCP, msg: Variant) -> void:
	var data := JSON.stringify(msg).to_utf8_buffer()
	data.append(0)
	peer.put_data(data)


func _read_control() -> void:
	if _ctl == null:
		return
	_ctl.poll()
	if _ctl.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		if _open:
			print("[net] lost the internet relay")
			close()
			lost.emit()
		return
	var n := _ctl.get_available_bytes()
	if n > 0:
		var got: Array = _ctl.get_data(n)
		if got[0] == OK:
			_buf.append_array(got[1])
	while true:
		var end := _buf.find(0)
		if end < 0:
			break
		var text := _buf.slice(0, end).get_string_from_utf8()
		_buf = _buf.slice(end + 1)
		var msg: Variant = JSON.parse_string(text)
		if msg is Dictionary:
			if msg.has("Hello"):
				public_port = int(msg["Hello"])
			elif msg.has("Connection"):
				_accept(String(msg["Connection"]))
			elif msg.has("Error"):
				print("[net] relay error: ", msg["Error"])


func _accept(id: String) -> void:
	## A player is knocking on our public port: take them in and connect them to the game.
	var remote := StreamPeerTCP.new()
	var local := StreamPeerTCP.new()
	if remote.connect_to_host(server_ip, CONTROL_PORT) != OK or local.connect_to_host("127.0.0.1", local_port) != OK:
		return
	_pairs.append({"remote": remote, "local": local, "id": id, "accepted": false,
		"to_local": PackedByteArray(), "to_remote": PackedByteArray(), "age": 0.0})


func _process(delta: float) -> void:
	if _ctl == null:
		return
	_read_control()
	for pair in _pairs.duplicate():
		if not _pump(pair, delta):
			pair["remote"].disconnect_from_host()
			pair["local"].disconnect_from_host()
			_pairs.erase(pair)


func _pump(pair: Dictionary, delta: float) -> bool:
	## Moves bytes both ways for one player. False when that connection is over.
	var remote: StreamPeerTCP = pair["remote"]
	var local: StreamPeerTCP = pair["local"]
	remote.poll()
	local.poll()
	var rs := remote.get_status()
	var ls := local.get_status()
	pair["age"] = float(pair["age"]) + delta
	if rs == StreamPeerTCP.STATUS_ERROR or ls == StreamPeerTCP.STATUS_ERROR:
		return false
	if rs == StreamPeerTCP.STATUS_NONE or ls == StreamPeerTCP.STATUS_NONE:
		return false
	if rs != StreamPeerTCP.STATUS_CONNECTED or ls != StreamPeerTCP.STATUS_CONNECTED:
		return float(pair["age"]) < 10.0   # still connecting
	if not pair["accepted"]:
		_send(remote, {"Accept": pair["id"]})
		pair["accepted"] = true
	var n := remote.get_available_bytes()
	if n > 0:
		var got: Array = remote.get_data(n)
		if got[0] == OK:
			pair["to_local"].append_array(got[1])
	n = local.get_available_bytes()
	if n > 0:
		var got2: Array = local.get_data(n)
		if got2[0] == OK:
			pair["to_remote"].append_array(got2[1])
	for k in [["to_local", local], ["to_remote", remote]]:
		var pending: PackedByteArray = pair[k[0]]
		if pending.size() > 0:
			var res: Array = (k[1] as StreamPeerTCP).put_partial_data(pending)
			if res[0] != OK:
				return false
			pair[k[0]] = pending.slice(int(res[1]))
	return true
