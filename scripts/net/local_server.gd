class_name LocalServer
extends Node
## "Create Server" (CreateServerScreen): a dedicated server (DedicatedServer)
## started by the game on this computer, in the background, for friends:
## the world keeps running for them while this player plays on it like
## anyone else (it joins by 127.0.0.1) and is an op there.
##
## Its settings are in user://server/server.properties (its own folder, so
## a dedicated server's server.properties is never touched): the world,
## the password, internet access (UPnP), friendly defaults for the rest
## (a free port from 25565 on, no spawn protection, shown on the LAN).
## Everything else can be changed in that file.
##
## The game talks to it over the admin channel (ServerStatus): a secret
## token written next to its settings, asks from this computer only. So it
## asks it for its addresses (Invite Friends) and stops it cleanly (the
## world and the players saved): when the player leaves and says so, and
## when the game quits. A server still running after the game went away
## (it crashed) is found again by its pid (RUNNING_FILE).
##
## Net makes this node (Net.local_server).

signal changed

enum State { OFF, STARTING, RUNNING, STOPPING, FAILED }

const DIR := "user://server"
const CONFIG := DIR + "/" + DedicatedServer.CONFIG_FILE
const TOKEN := DIR + "/" + DedicatedServer.ADMIN_TOKEN_FILE
const RUNNING_FILE := DIR + "/running.cfg"
## Seconds to wait for the server to answer its ping (making a new world
## takes a while) and to stop (it saves).
const START_SECONDS := 120.0
const STOP_SECONDS := 30.0
const INFO_SECONDS := 2.0
const MAX_PLAYERS := 10

var state := State.OFF
## Why it didn't start (NetErrors) when FAILED.
var error_code := 0
var error_args := PackedStringArray()
var port := Net.PORT
var password := ""
var world_name := ""
## The server's last "info" answer: port, lan (addresses), internet,
## code, upnp ("off", "working", "open", "failed"), upnp_error, players.
var info := {}

var _pid := -1
var _token := ""
var _since := 0.0
var _ping: ServerStatus
var _socket: PacketPeerUDP
var _ask_id := 0
var _info_timer := 0.0
var _opped := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DedicatedServer.requested():
		set_process(false) # (a server itself: nothing of this)
		return
	_find_running()


func _notification(what: int) -> void:
	# The game is closing: the server goes too (cleanly), nothing is left
	# running unseen.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if is_running() and not DedicatedServer.requested():
			_ask("stop")


func is_running() -> bool:
	return state == State.STARTING or state == State.RUNNING


## The address this game joins it at.
func address() -> String:
	return "127.0.0.1:%d" % port


## Whether this game is playing on it now.
func is_ours() -> bool:
	return state == State.RUNNING and Net.is_client() and Net.last_address == address()


## Starts the server with the world in saves/`folder` (`game_mode` for its
## players), `server_password` ("": none), `internet`: UPnP.
func start(folder: String, game_mode: int, server_password: String, internet: bool) -> void:
	if is_running():
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	port = _free_port()
	password = server_password
	world_name = folder
	var config := ServerConfig.load_or_create(CONFIG)
	for pair: Array in [["server-port", port], ["world-name", folder], ["gamemode", "creative" if game_mode == 1 else "survival"],
			["password", server_password], ["upnp", internet], ["lan-broadcast", true], ["spawn-protection", 0],
			["motd", _world_title(folder)]]:
		config.values[pair[0]] = pair[1]
	if not FileAccess.file_exists(CONFIG) or int(config.values.get("max-players", 20)) == 20:
		config.values["max-players"] = MAX_PLAYERS
	config.save()
	_token = Crypto.new().generate_random_bytes(16).hex_encode()
	var token_file := FileAccess.open(TOKEN, FileAccess.WRITE)
	if token_file == null:
		_fail(NetErrors.SERVER_DIDNT_START, "can't write %s" % ProjectSettings.globalize_path(TOKEN))
		return
	token_file.store_string(_token)
	token_file.close()
	var args := PackedStringArray()
	if OS.has_feature("template"):
		args = ["--headless", "--server", "--no-console", "--config", ProjectSettings.globalize_path(CONFIG)]
	else: # (from the editor or the project: Godot itself, with this project)
		args = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--", "--server", "--no-console",
			"--config", ProjectSettings.globalize_path(CONFIG)]
	_pid = OS.create_process(OS.get_executable_path(), args)
	if _pid <= 0:
		_fail(NetErrors.SERVER_DIDNT_START, "can't start %s" % OS.get_executable_path().get_file())
		return
	var running := ConfigFile.new()
	running.set_value("server", "pid", _pid)
	running.set_value("server", "port", port)
	running.set_value("server", "password", password)
	running.set_value("server", "world", folder)
	running.save(RUNNING_FILE)
	error_code = 0
	info = {}
	_opped = false
	_since = _now()
	_ping = null
	_set_state(State.STARTING)


## Asks it to save and stop (it sends its players away).
func stop() -> void:
	if not is_running():
		return
	_ask("stop")
	_since = _now()
	_set_state(State.STOPPING)


## Runs a server command (as its console would).
func command(line: String) -> void:
	if state == State.RUNNING:
		_ask("cmd " + line)


## Opens the router's ports now (Invite Friends' Allow Internet Access).
func allow_internet() -> void:
	if state == State.RUNNING:
		_ask("upnp")
		info["upnp"] = "working"
		changed.emit()


func _process(delta: float) -> void:
	_read_answers()
	match state:
		State.STARTING:
			if not OS.is_process_running(_pid):
				_fail_from_log()
				return
			if _ping == null:
				_ping = ServerStatus.new(address())
			if _ping.poll():
				if _ping.state == ServerStatus.State.DONE:
					_ping = null
					_set_state(State.RUNNING)
					_ask("info")
					return
				_ping = null # (not answering yet: ask again)
			if _now() - _since > START_SECONDS:
				OS.kill(_pid)
				_fail(NetErrors.SERVER_DIDNT_START, "no answer")
		State.RUNNING:
			if not OS.is_process_running(_pid):
				_forget()
				_set_state(State.OFF)
				return
			_info_timer -= delta
			if _info_timer <= 0.0:
				_info_timer = INFO_SECONDS
				_ask("info")
			if not _opped and is_ours() and not Net.world_info.is_empty():
				_opped = true # the player who started it may run its commands
				command("op " + Net.player_name)
		State.STOPPING:
			if not OS.is_process_running(_pid):
				_forget()
				_set_state(State.OFF)
			elif _now() - _since > STOP_SECONDS:
				OS.kill(_pid)


func _set_state(new_state: State) -> void:
	state = new_state
	changed.emit()


func _fail(code: int, detail: String) -> void:
	error_code = code
	error_args = PackedStringArray([detail])
	if code == NetErrors.PORT_TAKEN:
		error_args = PackedStringArray([str(port)])
	Net.log_event("Create Server: %s" % NetErrors.log_text(error_code, error_args))
	_forget()
	_set_state(State.FAILED)


## The server quit while starting: why, from the end of its log.
func _fail_from_log() -> void:
	var log_text := FileAccess.get_file_as_string(DIR + "/logs/latest.log")
	if log_text.contains("Can't start the server: Can't open port"):
		_fail(NetErrors.PORT_TAKEN, "")
		return
	var reason := "it stopped"
	for line in log_text.strip_edges().split("\n"):
		if line.contains("Can't"):
			reason = line.get_slice("] ", 1)
	_fail(NetErrors.SERVER_DIDNT_START, reason)


func _forget() -> void:
	_pid = -1
	_ping = null
	if _socket:
		_socket.close()
	_socket = null
	DirAccess.remove_absolute(RUNNING_FILE)
	DirAccess.remove_absolute(TOKEN)


## A server this game started before (and is still running): taken over.
func _find_running() -> void:
	var running := ConfigFile.new()
	if running.load(RUNNING_FILE) != OK:
		return
	var pid := int(running.get_value("server", "pid", -1))
	_token = FileAccess.get_file_as_string(TOKEN).strip_edges()
	if pid <= 0 or not OS.is_process_running(pid) or _token == "":
		_forget()
		return
	_pid = pid
	port = int(running.get_value("server", "port", Net.PORT))
	password = str(running.get_value("server", "password", ""))
	world_name = str(running.get_value("server", "world", ""))
	_since = _now()
	_set_state(State.STARTING) # (until its ping answers)


## A port from 25565 on that nothing uses (the game's and the ping's).
func _free_port() -> int:
	for candidate in range(Net.PORT, Net.PORT + 40, 2):
		var ok := true
		for p in [candidate, candidate + ServerStatus.PORT_OFFSET]:
			var probe := PacketPeerUDP.new()
			if probe.bind(p) != OK:
				ok = false
			probe.close()
		if ok:
			return candidate
	return Net.PORT


func _world_title(folder: String) -> String:
	var save := WorldSave.new()
	save.folder = folder
	return save.name if save.load_level() else folder


# --- The admin channel -------------------------------------------------------------------------

func _ask(command_text: String) -> void:
	if _token == "":
		return
	if _socket == null:
		_socket = PacketPeerUDP.new()
		if _socket.bind(0, "127.0.0.1") != OK:
			Net.log_event("Create Server: can't open a local port to talk to the server")
			_socket = null
			return
	_socket.set_dest_address("127.0.0.1", port + ServerStatus.PORT_OFFSET)
	_ask_id += 1
	_socket.put_packet(("%s;%s;%d;%s" % [ServerStatus.ADMIN_ASK, _token, _ask_id, command_text]).to_utf8_buffer())


func _read_answers() -> void:
	if _socket == null:
		return
	while _socket.get_available_packet_count() > 0:
		var packet := _socket.get_packet()
		if _socket.get_packet_port() != port + ServerStatus.PORT_OFFSET:
			continue
		var parts := packet.get_string_from_utf8().split(";", true, 2)
		if parts.size() != 3 or parts[0] != ServerStatus.ADMIN_ANSWER:
			continue
		var answer: Variant = JSON.parse_string(parts[2]) if parts[2].begins_with("{") else null
		if answer is Dictionary:
			info = answer
			changed.emit()


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
