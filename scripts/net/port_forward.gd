class_name PortForward
extends RefCounted
## "Allow Internet Access": asks the home router (UPnP) to pass the game
## port and the status port (+1, the server list's ping) to this computer,
## so a friend on the internet can join by the invite code. The way the old
## LAN-over-internet tools felt, without setting up the router by hand.
##
## UPnP's discovery waits for the router's answer (~2 s), so it runs on a
## thread and `changed` is emitted on the main thread when it's done. The
## mappings are removed when the host stops (close()) and when the game
## quits (close_now()), so nothing is left open on the router.
##
## It can't help when the router has UPnP off or none, or when the provider
## gives the router no public address of its own (CGNAT: the "external"
## address is a private one): then the reason is in `error` and the players
## can use a VPN that makes one network of their computers instead.

signal changed

enum State { OFF, WORKING, OPEN, FAILED }

const DESCRIPTION := "Voxel Engine"
const DISCOVER_MS := 2000

var state := State.OFF
## The router's internet address (when OPEN).
var external_ip := ""
var port := 0
## Why it failed (an English text for Lang.t), when FAILED.
var error := ""

var _thread: Thread
var _upnp: UPNP
var _mapped: Array[int] = []
## Set by close() while the thread works: it undoes its mappings itself.
var _closing := false
var _mutex := Mutex.new()
## Counts open()s, so a late answer from an earlier one is ignored.
var _generation := 0


## Starts opening `game_port` and the status port on the router.
func open(game_port: int) -> void:
	_join_thread()
	port = game_port
	state = State.WORKING
	error = ""
	external_ip = ""
	_closing = false
	_generation += 1
	_thread = Thread.new()
	_thread.start(_work.bind(game_port, _generation))
	changed.emit()


## Removes the mappings (on a thread: the router may be slow to answer).
func close() -> void:
	_mutex.lock()
	_closing = true
	_mutex.unlock()
	if _thread and _thread.is_alive():
		return # the working thread removes what it made
	_join_thread()
	_set_off()
	if not _mapped.is_empty():
		var upnp := _upnp
		var mapped := _mapped.duplicate()
		_mapped.clear()
		_thread = Thread.new()
		_thread.start(func() -> void: _unmap(upnp, mapped))


## Removes the mappings now and waits (quitting the game).
func close_now() -> void:
	_mutex.lock()
	_closing = true
	_mutex.unlock()
	_join_thread()
	_unmap(_upnp, _mapped)
	_mapped.clear()
	_set_off()


func _set_off() -> void:
	if state != State.OFF:
		state = State.OFF
		changed.emit()


func _join_thread() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null


func _is_closing() -> bool:
	_mutex.lock()
	var closing := _closing
	_mutex.unlock()
	return closing


## The thread: discover the router, check its address, map the ports.
func _work(game_port: int, generation: int) -> void:
	var upnp := UPNP.new()
	var mapped: Array[int] = []
	var fail := ""
	var ip := ""
	var result := upnp.discover(DISCOVER_MS, 2, "")
	var gateway := upnp.get_gateway() if result == UPNP.UPNP_RESULT_SUCCESS else null
	if gateway == null or not gateway.is_valid_gateway():
		fail = "Your router didn't answer: UPnP is off in its settings or not supported"
	else:
		ip = upnp.query_external_address()
		if not ip.is_valid_ip_address() or ip.contains(":"):
			fail = "Your router didn't tell its internet address"
		elif InviteCode.is_private_ip(ip):
			fail = "Your provider doesn't give your router its own internet address (CGNAT)"
	if fail == "":
		for p: int in [game_port, game_port + ServerStatus.PORT_OFFSET]:
			if _is_closing():
				break
			var mapping := upnp.add_port_mapping(p, p, DESCRIPTION, "UDP", 0)
			if mapping != UPNP.UPNP_RESULT_SUCCESS:
				if p == game_port: # (the status port is only for the ping)
					fail = "Your router refused to open the port"
				break
			mapped.append(p)
	if fail != "" or _is_closing():
		_unmap(upnp, mapped)
		mapped.clear()
	_finished.call_deferred(upnp, mapped, ip, fail, generation)


func _finished(upnp: UPNP, mapped: Array[int], ip: String, fail: String, generation: int) -> void:
	if generation != _generation:
		_unmap(upnp, mapped) # (an earlier open's late answer)
		return
	_join_thread()
	if _is_closing():
		_unmap(upnp, mapped)
		_set_off()
		return
	_upnp = upnp
	_mapped = mapped
	external_ip = ip if fail == "" else ""
	error = fail
	state = State.OPEN if fail == "" else State.FAILED
	changed.emit()


static func _unmap(upnp: UPNP, mapped: Array) -> void:
	if upnp == null:
		return
	for p: int in mapped:
		upnp.delete_port_mapping(p, "UDP")
