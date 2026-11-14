class_name ServerStatus
extends RefCounted
## The server list's status ping, without joining the game: one small UDP
## question to the game port + 1 (ENet already uses the game port itself),
## one small answer.
##
## Ask:    "VEBE?;<token>" padded with spaces to exactly ASK_SIZE bytes.
## Answer: "VEBE!;<token>;<players>;<max>;<version>;<host name>;<motd>"
##         (fields without ";" or line breaks, at most ANSWER_MAX bytes: the
##         motd, last, is shortened to fit).
## The token is a random number the asker checks, so stray or replayed
## answers are ignored; the round trip of the matching ask is the ping.
##
## The host (Responder) answers only well-formed asks of exactly ASK_SIZE
## bytes and never sends more than ANSWER_MAX bytes, so a spoofed address
## gets at most twice the bytes sent in its name; and at most
## ANSWERS_PER_ADDRESS answers per ANSWER_SECONDS to one address and
## ANSWERS_PER_SECOND in all, so it can't be used to flood anyone.
##
## The asker (this class): start(), then poll() every frame until done.
## It asks again each RETRY_SECONDS (UDP may lose a packet) and gives up
## after TIMEOUT_SECONDS.

enum State { RESOLVING, PINGING, DONE, UNREACHABLE, UNRESOLVED }

const PORT_OFFSET := 1
const ASK := "VEBE?"
const ANSWER := "VEBE!"
const ASK_SIZE := 64
const ANSWER_MAX := 128
const RETRY_SECONDS := 1.0
const TIMEOUT_SECONDS := 3.0
const ANSWERS_PER_ADDRESS := 4
const ANSWER_SECONDS := 5.0
const ANSWERS_PER_SECOND := 40

var state := State.RESOLVING
## The answer (when DONE): round trip in ms, the host's name, its message
## of the day (the world's name), players in, most players, game version.
var ping := -1
var host_name := ""
var motd := ""
var players := 0
var max_players := 0
var version := ""

var _host := ""
var _port := 0
var _ip := ""
var _resolve_id := -1
var _socket: PacketPeerUDP
var _started := 0.0
var _next_ask := 0.0
## token -> ticks (ms) when that ask was sent.
var _asks := {}


## Splits "host", "host:port" or an invite code (the default port is Net.PORT).
static func split_address(address: String) -> Array:
	var text := InviteCode.to_address(address)
	var port := Net.PORT
	if text.count(":") == 1:
		port = int(text.get_slice(":", 1))
		text = text.get_slice(":", 0)
	return [text, port]


func _init(address: String) -> void:
	var parts := split_address(address)
	_host = parts[0]
	_port = parts[1]
	_started = _now()
	if _host == "" or _port <= 0 or _port + PORT_OFFSET > 65535:
		state = State.UNRESOLVED
	elif _host.is_valid_ip_address():
		_ip = _host
		_open()
	else:
		_resolve_id = IP.resolve_hostname_queue_item(_host, IP.TYPE_IPV4)


## Is the ping still going?
func is_waiting() -> bool:
	return state == State.RESOLVING or state == State.PINGING


## Advances the ping; returns true once it's over (state is final).
func poll() -> bool:
	if state == State.RESOLVING and _resolve_id >= 0:
		var status := IP.get_resolve_item_status(_resolve_id)
		if status == IP.RESOLVER_STATUS_WAITING:
			return false
		_ip = IP.get_resolve_item_address(_resolve_id) if status == IP.RESOLVER_STATUS_DONE else ""
		IP.erase_resolve_item(_resolve_id)
		_resolve_id = -1
		if _ip == "":
			state = State.UNRESOLVED
			return true
		_open()
	if state != State.PINGING:
		return true
	while _socket.get_available_packet_count() > 0:
		if _read(_socket.get_packet()):
			close()
			state = State.DONE
			return true
	var now := _now()
	if now - _started > TIMEOUT_SECONDS:
		close()
		state = State.UNREACHABLE
		return true
	if now >= _next_ask:
		_send()
	return false


func close() -> void:
	if _socket:
		_socket.close()
	_socket = null
	if _resolve_id >= 0:
		IP.erase_resolve_item(_resolve_id)
		_resolve_id = -1


func _open() -> void:
	_socket = PacketPeerUDP.new()
	if _socket.bind(0) != OK or _socket.connect_to_host(_ip, _port + PORT_OFFSET) != OK:
		_socket = null
		state = State.UNREACHABLE
		return
	state = State.PINGING
	_started = _now() # the timeout counts from the first ask, not the lookup
	_send()


func _send() -> void:
	_next_ask = _now() + RETRY_SECONDS
	var token := str(randi())
	_asks[token] = Time.get_ticks_msec()
	_socket.put_packet(("%s;%s" % [ASK, token]).rpad(ASK_SIZE).to_utf8_buffer())


func _read(packet: PackedByteArray) -> bool:
	if packet.size() > ANSWER_MAX:
		return false
	var parts := packet.get_string_from_utf8().split(";")
	if parts.size() < 7 or parts[0] != ANSWER or not _asks.has(parts[1]):
		return false
	ping = Time.get_ticks_msec() - int(_asks[parts[1]])
	players = int(parts[2])
	max_players = int(parts[3])
	version = parts[4]
	host_name = parts[5]
	motd = parts[6]
	return true


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## The host's side: answers asks on the game port + 1 while hosting.
class Responder:
	var _socket: PacketPeerUDP
	## address -> [times answered], answers in the current second.
	var _answered := {}
	var _second := 0
	var _this_second := 0

	## Starts answering; false if the port is taken (pings then fail, the
	## game itself works).
	func open(game_port: int) -> bool:
		_socket = PacketPeerUDP.new()
		if _socket.bind(game_port + PORT_OFFSET) != OK:
			_socket = null
		return _socket != null

	func close() -> void:
		if _socket:
			_socket.close()
		_socket = null
		_answered.clear()

	## Answers waiting asks; `info` gives [players, max, version, host
	## name, motd] (called only when there is someone to answer).
	func poll(info: Callable) -> void:
		if _socket == null:
			return
		var now := ServerStatus._now()
		var answer_info: Array = []
		while _socket.get_available_packet_count() > 0:
			var packet := _socket.get_packet()
			var address := _socket.get_packet_ip()
			var port := _socket.get_packet_port()
			if packet.size() != ASK_SIZE:
				continue
			var parts := packet.get_string_from_utf8().strip_edges().split(";")
			if parts.size() != 2 or parts[0] != ASK or not parts[1].is_valid_int():
				continue
			if not _allowed(address, now):
				continue
			if answer_info.is_empty():
				answer_info = info.call()
			var fields: Array[String] = [ANSWER, parts[1]]
			for value: Variant in answer_info:
				fields.append(str(value).replace(";", ",").replace("\n", " ").left(32))
			var reply := ";".join(fields).to_utf8_buffer()
			while reply.size() > ANSWER_MAX and fields[-1] != "":
				fields[-1] = fields[-1].left(-1)
				reply = ";".join(fields).to_utf8_buffer()
			_socket.set_dest_address(address, port)
			_socket.put_packet(reply)

	func _allowed(address: String, now: float) -> bool:
		if int(now) != _second:
			_second = int(now)
			_this_second = 0
		if _this_second >= ANSWERS_PER_SECOND:
			return false
		if _answered.size() > 1024:
			_answered.clear() # many addresses: forget (the total limit holds)
		var times: Array = _answered.get(address, []).filter(func(t: float) -> bool: return now - t < ANSWER_SECONDS)
		if times.size() >= ANSWERS_PER_ADDRESS:
			_answered[address] = times
			return false
		times.append(now)
		_answered[address] = times
		_this_second += 1
		return true
