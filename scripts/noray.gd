extends Node
## Client for a noray server (github.com/foxssake/noray, MIT): a matchmaker on the internet that
## introduces two players' computers so they can connect without anyone changing their router.
## It gives each computer an id; a player who knows the host's id asks noray to connect them, and
## noray tells both sides the other's internet address (to punch through their routers) or, when that
## can't work, a relay port on the noray server that passes the game's packets along.
##
## Protocol: lines over TCP (default port 8890): "register-host" -> "set-oid <public id>" and
## "set-pid <private id>"; "connect <oid>" -> "connect <ip>:<port>"; "connect-relay <oid>" ->
## "connect-relay <port>". The private id sent over UDP to port 8809 (answer "OK") tells noray which
## internet address and port this computer's game traffic comes from.

signal connect_nat(address: String, port: int)   # someone wants to connect to us directly (or our request's answer)
signal connect_relay(port: int)                  # the same, through the relay port on the server
signal lost                                      # the connection to the noray server dropped

const REGISTRAR_PORT := 8809

var server_ip := ""
var oid := ""          # our public id: the host's join code carries it
var pid := ""          # our private id
var local_port := 0    # the UDP port noray saw our traffic come from (the game must use it)
var _tcp: StreamPeerTCP
var _buf := ""
var _was_open := false


func is_open() -> bool:
	return _tcp != null and _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED


func open(address: String) -> String:
	## Connects and registers. Returns "" or what went wrong. `address` is "host" or "host:port".
	close()
	var host := address
	var tcp_port := 8890
	if ":" in address:
		host = address.get_slice(":", 0)
		tcp_port = int(address.get_slice(":", 1))
	server_ip = host if host.is_valid_ip_address() else find_address(host)
	if server_ip == "":
		return "Could not find the matchmaking server %s (no internet?)." % host
	_tcp = StreamPeerTCP.new()
	if _tcp.connect_to_host(server_ip, tcp_port) != OK:
		return "Could not reach the matchmaking server."
	var t := 0.0
	while _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING and t < 6.0:
		await get_tree().create_timer(0.05).timeout
		_tcp.poll()
		t += 0.05
	if _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		close()
		return "Could not reach the matchmaking server %s." % address
	_was_open = true
	_send("register-host")
	t = 0.0
	while (oid == "" or pid == "") and t < 6.0 and is_open():
		await get_tree().create_timer(0.05).timeout
		t += 0.05
	if oid == "" or pid == "":
		close()
		return "The matchmaking server did not answer."
	# tell noray where our UDP traffic comes from
	var udp := PacketPeerUDP.new()
	udp.bind(0)
	udp.set_dest_address(server_ip, REGISTRAR_PORT)
	var ok := false
	t = 0.0
	while t < 8.0 and not ok:
		udp.put_packet(pid.to_utf8_buffer())
		await get_tree().create_timer(0.1).timeout
		t += 0.1
		while udp.get_available_packet_count() > 0:
			if udp.get_packet().get_string_from_utf8() == "OK":
				ok = true
	local_port = udp.get_local_port()
	udp.close()
	if not ok:
		close()
		return "The matchmaking server could not see this computer's network traffic (a firewall may block the game)."
	return ""


## Where the built-in matchmaker lives, for networks whose DNS blocks its name (a Pi-hole or other
## ad/tracker blocker on the router answers 0.0.0.0, or nothing, for names on its lists).
const KNOWN_ADDRESSES := {"tomfol.io": "172.105.69.73"}
const CACHE_PATH := "user://matchmaker_address.cfg"
static var fake_dns := ""   # test runs: pretend the name lookup answered this (--mp-fake-dns=0.0.0.0)


static func find_address(host: String) -> String:
	## The server's IPv4 address. A blocked or failed lookup falls back to the address that worked
	## last time on this computer, then to the one built into the game, so a DNS blocker can't stop it.
	var ip := fake_dns if fake_dns != "" else IP.resolve_hostname(host, IP.TYPE_IPV4)
	var cache := ConfigFile.new()
	cache.load(CACHE_PATH)
	if _usable(ip):
		if cache.get_value("addresses", host, "") != ip:
			cache.set_value("addresses", host, ip)
			cache.save(CACHE_PATH)
		return ip
	var why := "blocked by this network's DNS (Pi-hole?)" if ip != "" else "not found"
	for fallback in [String(cache.get_value("addresses", host, "")), String(KNOWN_ADDRESSES.get(host, ""))]:
		if _usable(fallback):
			print("[net] the matchmaker's name was %s (got \"%s\"); using its address %s" % [why, ip, fallback])
			return fallback
	return ""


static func _usable(ip: String) -> bool:
	## Not empty, a real IPv4 address, and not one of the "blocked" answers DNS blockers give.
	return ip != "" and ip.is_valid_ip_address() and ip.count(".") == 3 and not ip.begins_with("0.") \
		and not ip.begins_with("127.") and ip != "255.255.255.255"


func request_nat(host_oid: String) -> void:
	_send("connect " + host_oid)


func request_relay(host_oid: String) -> void:
	_send("connect-relay " + host_oid)


func close() -> void:
	if _tcp != null:
		_tcp.disconnect_from_host()
	_tcp = null
	_buf = ""
	oid = ""
	pid = ""
	_was_open = false


func _send(line: String) -> void:
	if _tcp != null:
		_tcp.put_data((line + "\n").to_utf8_buffer())


func _process(_delta: float) -> void:
	if _tcp == null:
		return
	_tcp.poll()
	var st := _tcp.get_status()
	if st != StreamPeerTCP.STATUS_CONNECTED:
		if _was_open and st != StreamPeerTCP.STATUS_CONNECTING:
			_was_open = false
			_tcp = null
			lost.emit()
		return
	var n := _tcp.get_available_bytes()
	if n > 0:
		var got: Array = _tcp.get_data(n)
		if got[0] == OK:
			_buf += (got[1] as PackedByteArray).get_string_from_utf8()
	while "\n" in _buf:
		var line := _buf.get_slice("\n", 0).strip_edges()
		_buf = _buf.substr(_buf.find("\n") + 1)
		var cmd := line.get_slice(" ", 0)
		var data := line.substr(cmd.length() + 1) if " " in line else ""
		match cmd:
			"set-oid":
				oid = data
			"set-pid":
				pid = data
			"connect":
				var hp := data.rsplit(":", true, 1)
				if hp.size() == 2 and hp[1].is_valid_int():
					connect_nat.emit(hp[0], int(hp[1]))
			"connect-relay":
				if data.is_valid_int():
					connect_relay.emit(int(data))


static func punch_from(udp_port: int, address: String, port: int, seconds: float, tree: SceneTree) -> bool:
	## Client side: from our registered port, send to the other side until something comes back
	## (that opens our router for their packets). True when their packets get through.
	var udp := PacketPeerUDP.new()
	if udp.bind(udp_port) != OK:
		return false
	udp.set_dest_address(address, port)
	var heard := false
	var t := 0.0
	while t < seconds and not heard:
		udp.put_packet("$rw-".to_utf8_buffer())
		await tree.create_timer(0.1).timeout
		t += 0.1
		while udp.get_available_packet_count() > 0:
			udp.get_packet()
			heard = true
	if heard:   # a few more, so the other side's router sees us too
		for i in 5:
			udp.put_packet("$rwx".to_utf8_buffer())
	udp.close()
	return heard
