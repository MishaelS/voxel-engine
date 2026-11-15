extends Node
## Autoload: multiplayer (stage 15), the classic game's way: a player opens
## their world to the network from the pause menu ("Open to LAN") and is the
## host; others join by address or from the list of games on the local
## network. Or a dedicated server (DedicatedServer, `--server`, SERVER.md)
## hosts a world with no player of its own: started by hand (the
## start-server files, tools/run.sh --server) or by the game in the
## background (Create Server: LocalServer, which this one joins). Godot's
## high-level multiplayer over ENet.
##
## The host runs the world: liquids, growth, redstone, ticks and saving. A
## client draws it and moves its own player:
## - columns: a client generates the ones nobody has changed itself (the
##   generators are deterministic, the same blocks from the same seed); the
##   host sends the changed ones (compressed) within its view distance. Then
##   every block change is sent to the clients in batches, a tick at a time;
## - a client's edits (breaking, placing, buckets...) show at once and go to
##   the host, which checks and makes them with all their effects (or sends
##   the block back as it is); using levers, buttons, doors and trapdoors is
##   done by the host;
## - players see each other (RemotePlayer: the player model with the skin,
##   walking, sneaking, swinging, the item in hand, the name above);
## - chat, the time of day and the weather are shared.
## - creatures, boats, minecarts, arrows, TNT and paintings are the host's:
##   10 times a second each client gets the ones within 96 blocks (new ones
##   with their whole state) and moves its copies ("puppets") along; what a
##   client makes (an arrow shot, a boat put down) the host makes. A client
##   hits them, rides the host's boats and minecarts (steering them) through
##   the host. Creatures go after any player; players hurt each other
##   through the host (pvp);
## - dropped items too: each client sees the ones within 48 blocks, drops
##   and throws through the host and picks them up with its leave;
## - chests, furnaces, dispensers and signs are the host's (below);
## - the host keeps each client's player (where it was, inventory, armor,
##   health, game mode) by its tag in the world's save, and gives it back on
##   joining.
##
## Trust: everything goes through the host. Clients never reach each other
## (the server relay is off: chat, looks, hits and movement are passed on by
## the host after its checks), and nothing a client sends is believed as is
## (NetGuard): types, ranges and sizes are checked, text is cleaned, and
## - where a player is, is the host's: movement faster than the game allows
##   (walking, flying in creative, riding) is sent back (NetGuard.Mover);
##   teleports and respawns go through the host;
## - breaking, placing, using, signs, containers, hits and pick-ups only
##   reach REACH_SURVIVAL / REACH_CREATIVE blocks from that place; nothing
##   is made in unloaded land; survival can't place or break what only the
##   world makes (bedrock, spawners); the spawn is protected for non-ops;
## - the game mode is the host's (/gamemode goes through it), so is who may
##   cheat (ops, NetGuard);
## - containers: a client's change to a slot that changed on the host since
##   it saw it is merged, or undone on both sides (no two players take the
##   same stack); entity states from clients are rebuilt from known keys.
## Inventories are each client's own: a changed client can still give itself
## items; the host refuses what only the world makes and what is impossible
## (counts, ids, damage), not every item it can't account for.
##
## Joining: a joining player is asked to prove who it is with this server's
## salt and answers with its tag (PlayerProfile.tag_for_server: a hash of
## its computer's hashed id and the salt; the same on this server, different
## on others, nothing about the computer in it), its name (3-16 of A-Z, 0-9,
## _; Player Settings' name is spelled that way, NetGuard.network_name) and,
## if the server has a password, a hash of it with a one-time nonce (the
## password itself never goes over the network). Then bans (by tag,
## user://bans.cfg, and by address, banned-ips.cfg), the whitelist, max
## players. At most MAX_PENDING joins wait to introduce themselves (for
## HELLO_SECONDS), max_per_address connections and MAX_TRIES tries in
## TRIES_SECONDS from one address; idle players can be kicked. Floods (chat,
## edits, columns...) are refused and bad data counted (strikes): too much
## of either is a kick.
##
## Lag is not cheating: movement may come late and in bursts (NetGuard.Mover
## allows what the time gone by allows), flood limits are token buckets with
## room for a burst, being out of reach only refuses, and too far only sends
## the player back; kicks are for long runs of it or for impossible data.
## ENet's timeouts are long (PEER_TIMEOUT_*); a client shows "Bad connection"
## (ConnectionIndicator) while the host is silent or slow, and the host tells
## a client it hears badly.
##
## Why a join was refused or a game ended goes as a code and its arguments
## (NetErrors, _refused), never as English text: each client shows it in its
## own language (the Disconnected screen, with the code); the log shows the
## code with the English text. Clients name the host by address, a domain
## name (looked up without waiting) or an invite code. Ops (ServerLists: ops.cfg, names tied to tags) run
## the cheat and admin commands; the host of an Open to LAN game always is
## one, and its Allow Cheats lets everyone cheat. Commands: /players,
## /kick, /ban, /pardon, /ban-ip, /pardon-ip, /op, /deop, /whitelist,
## /save-all, /stop. (A changed client can fake its tag: this stops casual
## bots and spam, not a determined attacker or a flood at the network level.)
##
## The server list pings without joining: while hosting, a ServerStatus
## Responder answers small UDP asks on the game port + 1 with the players
## in, the most, the version, the host's name and the world's name (a
## dedicated server's motd) (the protocol and its limits are in
## server_status.gd).
##
## Playing over the internet: "Allow Internet Access" in Open to LAN opens
## the ports on the home router (PortForward, UPnP) and gives an invite code
## (InviteCode: the router's address, short and typo-proof) that joining
## takes wherever an address goes. A server with a public-address (an IP or
## a domain name) gives that instead (invite_code, /invite).

signal players_changed
signal lan_games_changed

enum Mode { OFFLINE, HOST, CLIENT }

const PORT := 25565
const LAN_PORT := 4445
const LAN_SEND_SECONDS := 1.5
const LAN_FORGET_SECONDS := 5.0
const LAN_GAMES_MAX := 64
## Players at most in an Open to LAN game (a dedicated server: max-players).
const MAX_PLAYERS := 8
const CONFIG_PATH := "user://multiplayer.cfg"
## Seconds between the host's time and weather messages.
const SYNC_SECONDS := 1.0
## Player state messages a second (each tick).
const STATE_RATE := 20.0
const SERVER_CONFIG := "user://server.cfg"
## Joining limits per address, the time to introduce oneself, joins waiting
## at once.
const MAX_PER_ADDRESS := 3
const MAX_TRIES := 8
const TRIES_SECONDS := 30.0
const HELLO_SECONDS := 10.0
const MAX_PENDING := 8
## ENet's timeouts (both sides): a peer that stops answering is dropped
## after PEER_TIMEOUT_MIN_MS at the soonest (when even its slow resends go
## unanswered) and PEER_TIMEOUT_MAX_MS at the latest, so a short drop of
## Wi-Fi or a stall of the other side doesn't end the game.
const PEER_TIMEOUT_LIMIT := 32
const PEER_TIMEOUT_MIN_MS := 10000
const PEER_TIMEOUT_MAX_MS := 30000
## Flood limits: [count, seconds] per kind, as a token bucket (FLOOD_BURST
## times the count saved up: what a lag spike delivers at once is no flood).
## More is refused; refusing at twice the rate for about FLOOD_SECONDS
## (a client sending three times what it may) is a kick.
const CHAT_LIMIT := 8      # lines per 5 seconds
const EDIT_LIMIT := 60     # edits and uses per second
const COLUMN_LIMIT := 400  # column requests per second
const ATTACK_LIMIT := 30   # hits per second (a sword's sweep hits several)
const SPAWN_LIMIT := 8     # entities made per second
const DROP_LIMIT := 64     # items dropped per second (a death drops 40 stacks)
const STATE_LIMIT := 60    # movement messages per second (20 are sent)
const FLOOD_BURST := 3.0
const FLOOD_SECONDS := 10.0
## Client: a stall (no word from the host) this long, or a round trip this
## slow, shows the connection warning (ConnectionIndicator).
const STALL_SECONDS := 1.5
const SLOW_PING_MS := 500
## Host: a client silent this long (or losing this share of packets) is
## told its connection is unstable, at most every WARN_SECONDS.
const CLIENT_SILENT_SECONDS := 3.0
const CLIENT_LOSS := 0.15
const WARN_SECONDS := 30.0
## Strikes (bad data: impossible ids, sizes, positions) in STRIKE_SECONDS
## before a kick. What lag explains (out of reach, a game mode changing
## meanwhile) weighs nothing or little: it is refused and logged only.
const STRIKE_LIMIT := 30
const STRIKE_SECONDS := 60.0
## Reach from the eyes to the block (a little more than the game's 4.5 / 5:
## the host sees players a moment late).
const REACH_SURVIVAL := 6.0
const REACH_CREATIVE := 8.0
## Entities in one snapshot, new ones (with their whole state) in one, items.
const SNAPSHOT_ENTITIES := 200
const SNAPSHOT_NEW := 24
const SNAPSHOT_ITEMS := 200
## Entities a client may make (arrows it shoots, boats and carts it puts
## down, paintings it hangs, TNT it lights).
const CLIENT_SPAWNS: Array[String] = ["arrow", "boat", "minecart", "chest_minecart", "furnace_minecart", "painting", "tnt"]
## Seconds everyone must sleep before a dedicated server skips the night.
const SLEEP_SECONDS := 5.0

var mode := Mode.OFFLINE
## A network game's "Allow Cheats" (the host chooses on opening: everyone
## may cheat; a dedicated server: only ops). A client: whether it may (the
## host says on joining and when it changes). Also the game mode new players
## get.
var cheats := false
var lan_game_mode := 0
## Open to LAN's "Allow Internet Access": host() opens the router's ports.
var internet := false
## The router's ports while hosting with internet access.
var port_forward := PortForward.new()
## The port the host listens on.
var host_port := PORT
## A dedicated server (DedicatedServer, its settings from server.properties).
var dedicated := false
var server: DedicatedServer
## Create Server: the server this game started in the background.
var local_server: LocalServer
## The host's settings (Open to LAN: these defaults).
var max_players := MAX_PLAYERS
var motd := ""
var password := ""
var bind_ip := ""
var view_distance := 34
var simulation_distance := 4
var spawn_protection := 0
var spawn_radius := 3
var idle_minutes := 0
var pvp := true
var autosave_seconds := 300.0
var max_per_address := MAX_PER_ADDRESS
var lan_broadcast := true
var server_difficulty := -1
## Ops, the whitelist and bans (user://).
var lists := ServerLists.new()
## Commands that change the world (or reach other players): a client's run
## on the host (Commands not listed here run on the player's own side).
const HOST_COMMANDS: Array[String] = ["time", "weather", "gamerule", "tick", "setblock", "fill", "clone", "summon",
	"kill", "damage", "execute", "setworldspawn", "difficulty", "msg", "tell", "w", "gamemode", "tp", "teleport",
	"say", "kick", "ban", "pardon", "ban-ip", "pardon-ip", "op", "deop", "whitelist", "players", "save-all", "stop",
	"invite"]
## Commands always allowed (no cheats needed); the host decides on the ones
## in OP_COMMANDS.
const FREE_COMMANDS: Array[String] = ["help", "seed", "say", "players", "kick", "ban", "pardon", "list", "me",
	"msg", "tell", "w", "invite", "ban-ip", "pardon-ip", "op", "deop", "whitelist", "save-all", "stop"]
## Commands only ops may run on the host.
const OP_COMMANDS: Array[String] = ["players", "kick", "ban", "pardon", "ban-ip", "pardon-ip", "op", "deop",
	"whitelist", "save-all", "stop"]
var player_name := ""
var last_address := "127.0.0.1"
## Client: the password to join with (asked when a server wants one: the
## Multiplayer screen shows the password screen when `password_wanted`).
var join_password := ""
var password_wanted := false
## Client: the host's view distance (columns farther aren't asked for).
var view_limit := 64
## Peer id -> {"name": String, "ping": ms (-1 unknown)}, everyone in the
## game (this one too; a dedicated server isn't a player); the host measures
## the pings and sends them each second (the Tab list).
var players := {}
## Peer id -> RemotePlayer.
var avatars := {}
## Peer id -> {"color": name color (PlayerProfile.COLORS), "png": the skin as
## PNG (empty: default), "skin": its texture or null}: how each player looks.
var looks := {}
## LAN games found: "address:port" -> {"name", "world", "address", "port", "seen"}.
var lan_games := {}
## The host's world, as a client got it (WorldSave-like values).
var world_info := {}
## Why the last connection ended or failed (NetErrors: a code, 0 if it
## didn't, and its arguments); `show_disconnected`: a game in progress
## ended so (the title screen shows the Disconnected screen).
var last_code := 0
var last_args := PackedStringArray()
var show_disconnected := false
## The address players reach this server at (server.properties'
## public-address, e.g. "myserver.duckdns.org"): shown and given instead of
## the invite code when set.
var public_address := ""
## Client: when the host was last heard from (s), its round trip (ms).
var _last_heard := 0.0
## Client: a hostname being looked up before connecting (IP resolver id).
var _resolve_id := -1
var _resolve_host := ""
var _resolve_port := 0

var _peer: ENetMultiplayerPeer
var _lan_out: PacketPeerUDP
var _lan_in: PacketPeerUDP
var _status_responder: ServerStatus.Responder
var _lan_timer := 0.0
var _sync_timer := 0.0
var _state_timer := 0.0
var _second_timer := 0.0
var _sleep_time := 0.0
var _pending_blocks := PackedInt32Array()
## Client: columns asked for -> true (or when to ask again, a host's
## "later"); answers: column -> PackedInt32Array (the host's blocks) or empty
## (generate it); block changes waiting for a column that is on its way.
var _asked := {}
var _answers := {}
var _waiting_changes := {}
var _swings := 0
## Host: peer id -> address, the tags of the players in (peer id -> tag),
## joins waiting to introduce themselves (peer id -> deadline) and their
## nonces, tries by address (address -> [times]), counters for the flood
## limits, strikes (peer -> [[time, weight]...]), peers being dropped.
var _addresses := {}
var _tags := {}
var _waiting_hello := {}
var _nonces := {}
var _tries := {}
var _counters := {}
var _strikes := {}
var _dropping := {}
## Host: the names joins introduced themselves with (for the log), when
## each client was last heard from and last warned about its connection.
var _hello_names := {}
var _heard := {}
var _warned := {}
var _server_salt := ""
## Host: each client's movement (NetGuard.Mover), game mode, op or not, last
## activity (idle kick), when it was last told its game mode.
var _moves := {}
var _modes := {}
var _ops := {}
var _active := {}
var _mode_told := {}
var _spawn_cache := Vector3.INF
var _spawn_cached_at := -100.0
## Host: next entity / item number; per client what it has seen
## (peer -> {number: true}).
var _next_net_id := 1
var _known_entities := {}
var _known_items := {}
var _snapshot_timer := 0.0
## Host: each client's player as last sent, by tag (kept in the world save).
var saved_players := {}
## Client: the host's entities by number.
var _puppets := {}
const SNAPSHOT_SECONDS := 0.1
const ENTITY_RANGE := 96.0
const ITEM_RANGE := 48.0
const PLAYER_SAVE_SECONDS := 10.0
var _player_save_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # networking goes on in the pause menu
	_load_config()
	PlayerProfile.load_profile()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	port_forward.changed.connect(_on_forward_changed)
	local_server = LocalServer.new()
	local_server.name = "LocalServer"
	add_child(local_server)
	if DedicatedServer.requested():
		var node := DedicatedServer.new()
		node.name = "DedicatedServer"
		add_child(node)


func _notification(what: int) -> void:
	# Quitting: nothing stays open on the router; a client's player goes to
	# the host first.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if is_client() and what == NOTIFICATION_WM_CLOSE_REQUEST:
			leave()
		port_forward.close_now()


func is_online() -> bool:
	return mode != Mode.OFFLINE


func is_host() -> bool:
	return mode == Mode.HOST


func is_client() -> bool:
	return mode == Mode.CLIENT


func _load_config() -> void:
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)
	player_name = config.get_value("player", "name", "")
	last_address = config.get_value("player", "address", last_address)
	if player_name == "":
		player_name = "Player%d" % randi_range(100, 999)


func save_config() -> void:
	if dedicated:
		return
	var config := ConfigFile.new()
	config.set_value("player", "name", player_name)
	config.set_value("player", "address", last_address)
	config.save(CONFIG_PATH)


## A dedicated server's settings (DedicatedServer, from server.properties).
func configure_dedicated(node: DedicatedServer) -> void:
	dedicated = true
	server = node
	var config := node.config
	player_name = "Server"
	max_players = config.get_int("max-players", 1, 100)
	motd = NetGuard.clean_text(config.get_string("motd"), 64)
	password = config.get_string("password")
	bind_ip = config.get_string("server-ip").strip_edges()
	view_distance = config.get_int("view-distance", 4, 32)
	simulation_distance = config.get_int("simulation-distance", 2, 10)
	spawn_protection = config.get_int("spawn-protection", 0, 1000)
	spawn_radius = config.get_int("spawn-radius", 1, 8)
	idle_minutes = config.get_int("idle-timeout", 0, 10000)
	pvp = config.get_bool("pvp")
	autosave_seconds = config.get_int("autosave-minutes", 1, 60) * 60.0
	max_per_address = config.get_int("max-connections-per-ip", 1, 100)
	lan_broadcast = config.get_bool("lan-broadcast")
	internet = config.get_bool("upnp")
	public_address = NetGuard.clean_text(config.get_string("public-address"), 128).replace(" ", "")
	lists.enforce_tags = config.get_bool("enforce-tags")
	lan_game_mode = 1 if config.get_string("gamemode").to_lower() in ["creative", "c", "1"] else 0
	server_difficulty = {"peaceful": 0, "easy": 1, "normal": 2, "hard": 3, "0": 0, "1": 1, "2": 2, "3": 3}.get(
		config.get_string("difficulty").to_lower(), 2)
	cheats = false


func _world() -> VoxelWorld:
	var game := Game.find(get_tree())
	return game.world if game else null


func _game_player() -> Player:
	var game := Game.find(get_tree())
	return game.player if game else null


func _chat() -> Chat:
	return get_tree().get_first_node_in_group("chat") as Chat


func _message(text: String) -> void:
	var chat := _chat()
	if chat:
		chat.add_message(text, CommandSource.MessageKind.INFO)


## A line for the log: a dedicated server's console and logs/latest.log,
## the game's own log (stdout) otherwise.
func log_event(text: String) -> void:
	if server:
		server.log_line(text)
	else:
		print("[Net] ", text)


# --- Hosting and joining -------------------------------------------------------------

## Opens the world being played to the network. Returns an error text, or "".
func host(port: int = PORT) -> String:
	if is_online():
		return "Already open"
	_peer = ENetMultiplayerPeer.new()
	if bind_ip != "":
		_peer.set_bind_ip(bind_ip)
	# Room for MAX_PENDING more than the players: a full server can still say so.
	var error := _peer.create_server(port, max_players + MAX_PENDING)
	if error != OK:
		_peer = null
		return "Can't open port %d" % port
	_peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	# Clients only ever talk to the host (it checks and passes things on).
	(multiplayer as SceneMultiplayer).server_relay = false
	multiplayer.multiplayer_peer = _peer
	mode = Mode.HOST
	players = {} if dedicated else {1: {"name": player_name}}
	var world := _world()
	saved_players = world.save.state.get("net_players", {}) if world and world.save else {}
	looks = {} if dedicated else {1: _own_look()}
	_status_responder = ServerStatus.Responder.new()
	_status_responder.open(port)
	if server and server.admin_token != "":
		_status_responder.admin_token = server.admin_token
		_status_responder.admin = server.admin_command
	if lan_broadcast:
		_lan_out = PacketPeerUDP.new()
		_lan_out.set_broadcast_enabled(true)
		_lan_out.set_dest_address("255.255.255.255", LAN_PORT)
	host_port = port
	if internet:
		port_forward.open(port)
	players_changed.emit()
	return ""


## Opens the router's ports for a game already hosted (Invite Friends).
func allow_internet() -> void:
	internet = true
	if is_host() and port_forward.state != PortForward.State.WORKING:
		port_forward.open(host_port)


## What friends type to join over the internet: the public address when
## the server has one (public-address), else the invite code while the
## router's ports are open, else "".
func invite_code() -> String:
	if not is_host():
		return ""
	if public_address != "":
		return public_address
	if port_forward.state != PortForward.State.OPEN:
		return ""
	return InviteCode.encode(port_forward.external_ip, port_forward.port)


## The address players connect to over the internet, for the log and the
## console: the public address, else the router's address while its ports
## are open, else "".
func internet_address() -> String:
	if public_address != "":
		return public_address
	if is_host() and port_forward.state == PortForward.State.OPEN:
		return "%s:%d" % [port_forward.external_ip, port_forward.port] if port_forward.port != PORT else port_forward.external_ip
	return ""


func _on_forward_changed() -> void:
	if not is_host():
		return
	match port_forward.state:
		PortForward.State.OPEN:
			_message(Lang.t("Open to the internet. Invite code: %s (/invite copies it)") % invite_code())
			log_event("Router ports open (%s:%d); invite code %s" % [port_forward.external_ip, port_forward.port,
				InviteCode.encode(port_forward.external_ip, port_forward.port)])
			if dedicated:
				log_event("Players connect to: %s" % internet_address())
		PortForward.State.FAILED:
			_message(Lang.t("Can't open the world to the internet: %s") % Lang.t(port_forward.error))
			_message(Lang.t("Friends can still join over a VPN: Game Menu > Invite Friends"))
			log_event("Can't open the router's ports: %s" % port_forward.error)


## Connects to a host ("address", "address:port", a domain name or an
## invite code). The game starts when the host answers (welcome). Returns
## 0, or why it can't even try (a NetErrors code; also in last_code).
## A name is looked up first (without waiting: _poll_resolve).
func join(address: String) -> int:
	leave()
	password_wanted = false
	_set_error(0)
	if InviteCode.looks_like_code(address) and InviteCode.decode(address) == "":
		return _set_error(NetErrors.INVITE_TYPO)
	var parts := ServerStatus.split_address(address)
	var host_name: String = parts[0]
	var port: int = parts[1]
	if host_name == "" or port <= 0 or port > 65535:
		return _set_error(NetErrors.NO_ADDRESS)
	last_address = address.strip_edges()
	save_config()
	mode = Mode.CLIENT
	if host_name.is_valid_ip_address():
		return _connect(host_name, port)
	_resolve_host = host_name
	_resolve_port = port
	_resolve_id = IP.resolve_hostname_queue_item(host_name, IP.TYPE_IPV4)
	return 0


## Client: the looked-up address of a join by name, when it's known.
func _poll_resolve() -> void:
	var status := IP.get_resolve_item_status(_resolve_id)
	if status == IP.RESOLVER_STATUS_WAITING:
		return
	var ip := IP.get_resolve_item_address(_resolve_id) if status == IP.RESOLVER_STATUS_DONE else ""
	IP.erase_resolve_item(_resolve_id)
	_resolve_id = -1
	if ip == "":
		var host_name := _resolve_host
		leave()
		_set_error(NetErrors.CANT_RESOLVE, PackedStringArray([host_name]))
		players_changed.emit()
		return
	if _connect(ip, _resolve_port) != 0:
		leave()
		players_changed.emit()


func _connect(ip: String, port: int) -> int:
	_peer = ENetMultiplayerPeer.new()
	if _peer.create_client(ip, port) != OK:
		_peer = null
		mode = Mode.OFFLINE
		return _set_error(NetErrors.CANT_CONNECT, PackedStringArray(["%s:%d" % [ip, port]]))
	_peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = _peer
	mode = Mode.CLIENT
	_last_heard = _now()
	return 0


## Remembers why the connection ended (0: it didn't); returns the code.
func _set_error(code: int, args: PackedStringArray = PackedStringArray()) -> int:
	last_code = code
	last_args = args
	return code


## The last error in the player's language with its code ("" if none).
func error_text() -> String:
	return NetErrors.text(last_code, last_args) if last_code != 0 else ""


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Leaves the game or stops hosting.
func leave() -> void:
	if is_client():
		send_player_state() # (the host keeps this player)
	elif is_host() and _has_clients():
		# Clients are told why (else they'd see "connection lost").
		_refused.rpc(NetErrors.SERVER_CLOSED if dedicated else NetErrors.HOST_LEFT, PackedStringArray())
	if _peer and _peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED and _peer.host:
		_peer.host.flush() # (what was just sent goes before the connection closes)
	if _resolve_id >= 0:
		IP.erase_resolve_item(_resolve_id)
		_resolve_id = -1
	if _peer:
		_peer.close()
	_peer = null
	if not dedicated:
		cheats = false
	multiplayer.multiplayer_peer = null
	mode = Mode.OFFLINE
	players.clear()
	looks.clear()
	_puppets.clear()
	_known_entities.clear()
	_known_items.clear()
	for avatar: Node in avatars.values():
		if is_instance_valid(avatar):
			avatar.queue_free()
	avatars.clear()
	_asked.clear()
	_answers.clear()
	_waiting_changes.clear()
	_pending_blocks.clear()
	_viewers.clear()
	_lids_sent = PackedInt32Array()
	_open_containers.clear()
	_container_slots.clear()
	for list: Dictionary in [_addresses, _tags, _waiting_hello, _nonces, _counters, _strikes, _dropping, _moves,
			_modes, _ops, _active, _mode_told, _hello_names, _heard, _warned]:
		list.clear()
	world_info.clear()
	_lan_out = null
	if _status_responder:
		_status_responder.close()
	_status_responder = null
	if not dedicated:
		internet = false
	port_forward.close()
	players_changed.emit()


## Players in the game (a dedicated server isn't one).
func player_count() -> int:
	return players.size()


## Whether the host has anyone to send to.
func _has_clients() -> bool:
	for id: int in players:
		if id != 1:
			return true
	return false


## The clients in the game (not the host).
func _clients() -> Array[int]:
	var result: Array[int] = []
	for id: int in players:
		if id != 1:
			result.append(id)
	return result


func _on_peer_connected(id: int) -> void:
	if not is_host():
		return
	var enet := _peer.get_peer(id)
	var address := enet.get_remote_address() if enet else ""
	if enet:
		enet.set_timeout(PEER_TIMEOUT_LIMIT, PEER_TIMEOUT_MIN_MS, PEER_TIMEOUT_MAX_MS)
	var now := Time.get_ticks_msec() / 1000.0
	_addresses[id] = address
	if lists.is_ip_banned(address):
		_drop(id, NetErrors.BANNED)
		return
	var tries: Array = _tries.get(address, []).filter(func(t: float) -> bool: return now - t < TRIES_SECONDS)
	tries.append(now)
	_tries[address] = tries
	if _tries.size() > 1000:
		_tries.clear() # (many addresses: forgotten rather than kept forever)
		_tries[address] = tries
	var same_address := _addresses.values().count(address) - 1 # (this one is in already)
	if tries.size() > MAX_TRIES or same_address >= max_per_address:
		_drop(id, NetErrors.TOO_MANY_CONNECTIONS)
		return
	if _waiting_hello.size() >= MAX_PENDING:
		_drop(id, NetErrors.SERVER_BUSY)
		return
	_waiting_hello[id] = now + HELLO_SECONDS
	_nonces[id] = Crypto.new().generate_random_bytes(16).hex_encode()
	_challenge.rpc_id(id, _salt(), _nonces[id], password != "")


## This server's salt (made once): players' tags are made with it.
func _salt() -> String:
	if _server_salt == "":
		var config := ConfigFile.new()
		config.load(SERVER_CONFIG)
		_server_salt = config.get_value("server", "salt", "")
		if _server_salt == "":
			_server_salt = Crypto.new().generate_random_bytes(16).hex_encode()
			config.set_value("server", "salt", _server_salt)
			config.save(SERVER_CONFIG)
	return _server_salt


## What a client sends for the password: the password hashed with the
## server's salt, hashed again with this join's nonce (a recorded answer is
## worth nothing the next time; the password never leaves the computer).
static func password_proof(salt: String, nonce: String, secret: String) -> String:
	return (nonce + "|" + (salt + "|" + secret).sha256_text()).sha256_text()


## Host -> joining client: "prove who you are with this salt" (and the
## password, if `needs_password`, with this nonce).
@rpc("authority", "call_remote", "reliable")
func _challenge(salt: String, nonce: String, needs_password: bool) -> void:
	var proof := ""
	if needs_password and join_password != "":
		proof = password_proof(salt, nonce, join_password)
	_hello.rpc_id(1, NetGuard.network_name(player_name), str(ProjectSettings.get_setting("application/config/version", "dev")),
		PlayerProfile.tag_for_server(salt), proof)


## Host: tells a peer why (a NetErrors code and its arguments: the client
## shows it in its own language) and closes its connection a moment later
## (so the reason arrives). The log gets the code and the English text.
func _drop(id: int, code: int, args: PackedStringArray = PackedStringArray()) -> void:
	if _dropping.has(id):
		return
	_dropping[id] = true
	_refused.rpc_id(id, code, args)
	_waiting_hello.erase(id)
	var address: String = _addresses.get(id, "?")
	if players.has(id):
		log_event("%s (%s) was kicked: %s" % [players[id].name, address, NetErrors.log_text(code, args)])
	else:
		var who: String = _hello_names.get(id, "")
		log_event("Refused %s%s: %s" % [who + " " if who != "" else "", "(%s)" % address, NetErrors.log_text(code, args)])
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		if _peer and id in multiplayer.get_peers():
			_peer.disconnect_peer(id))


## Host: whether a joined peer stays under a flood limit (`limit` in
## `seconds`): a token bucket holding FLOOD_BURST times `limit`, so the
## messages a lag spike held back and delivers at once pass. More is
## refused (and logged once); refusing at twice the allowed rate for about
## FLOOD_SECONDS is a kick.
func _within(id: int, kind: String, limit: int, seconds: float) -> bool:
	if not _joined(id):
		return false # not introduced: ignored
	var now := _now()
	var rate := float(limit) / seconds
	var capacity := float(limit) * FLOOD_BURST
	var key := "%d/%s" % [id, kind]
	# [tokens, when last filled, refusals lately (fading over FLOOD_SECONDS)]
	var bucket: Array = _counters.get(key, [capacity, now, 0.0])
	var dt := maxf(now - float(bucket[1]), 0.0)
	bucket[0] = minf(float(bucket[0]) + rate * dt, capacity)
	bucket[1] = now
	bucket[2] = float(bucket[2]) * exp(-dt / FLOOD_SECONDS)
	_counters[key] = bucket
	if float(bucket[0]) >= 1.0:
		bucket[0] = float(bucket[0]) - 1.0
		return true
	var first := float(bucket[2]) < 1.0
	bucket[2] = float(bucket[2]) + 1.0
	if float(bucket[2]) > maxf(rate * FLOOD_SECONDS * 2.0, 20.0):
		_drop(id, NetErrors.KICKED_SPAM)
		return false
	if first:
		log_event("[flood] %s (%s): too many %s messages, refused" % [str(players.get(id, {}).get("name", "?")), _addresses.get(id, "?"), kind])
		if kind == "chat":
			_command_output.rpc_id(id, Lang.t("You are sending messages too fast"), CommandSource.MessageKind.ERROR)
	return false


## Host: a peer that joined (introduced itself and was let in).
func _joined(id: int) -> bool:
	return is_host() and id != 1 and players.has(id) and not _dropping.has(id)


## Host: something a client sent was refused (`why`, for the log). Strikes
## add up (`weight` each); too many in STRIKE_SECONDS is a kick. Weight 0:
## what lag explains (out of reach of where the host last saw the player):
## refused and logged (the first few), never a kick.
func _strike(id: int, why: String, weight: int = 1) -> void:
	var now := _now()
	var list: Array = (_strikes.get(id, []) as Array).filter(func(entry: Array) -> bool: return now - float(entry[0]) < STRIKE_SECONDS)
	list.append([now, weight])
	_strikes[id] = list
	var total := 0
	for entry: Array in list:
		total += int(entry[1])
	if list.size() <= 10:
		log_event("[security] %s (%s): %s" % [str(players.get(id, {}).get("name", "?")), _addresses.get(id, "?"), why])
	if total > STRIKE_LIMIT:
		_drop(id, NetErrors.KICKED_BAD_DATA)


func _on_peer_disconnected(id: int) -> void:
	_waiting_hello.erase(id)
	_nonces.erase(id)
	_dropping.erase(id)
	_close_for(id)
	_known_entities.erase(id)
	_known_items.erase(id)
	for key: String in _counters.keys():
		if key.begins_with("%d/" % id):
			_counters.erase(key)
	_strikes.erase(id)
	_hello_names.erase(id)
	_heard.erase(id)
	_warned.erase(id)
	if is_host():
		var world := _world()
		if world:
			for entity in world.entities.all():
				if entity.remote_rider == id:
					entity.remote_rider = 0 # its rider left
	if not players.has(id):
		_addresses.erase(id)
		return
	var left_name: String = players[id].name
	players.erase(id)
	looks.erase(id)
	_tags.erase(id)
	_addresses.erase(id)
	_moves.erase(id)
	_modes.erase(id)
	_ops.erase(id)
	_active.erase(id)
	_mode_told.erase(id)
	if avatars.has(id):
		(avatars[id] as Node).queue_free()
		avatars.erase(id)
	_message(Lang.t("%s left the game") % left_name)
	if is_host():
		log_event("%s left the game" % left_name)
		_send_players.rpc(players)
		_server_message.rpc("%s left the game" % left_name)
	players_changed.emit()


func _on_connected() -> void:
	# The host asks to introduce (_challenge). Its timeouts as the host's.
	var host_peer := _peer.get_peer(1) if _peer else null
	if host_peer:
		host_peer.set_timeout(PEER_TIMEOUT_LIMIT, PEER_TIMEOUT_MIN_MS, PEER_TIMEOUT_MAX_MS)
	_last_heard = _now()


func _on_connection_failed() -> void:
	leave()
	_set_error(NetErrors.CANT_REACH)
	players_changed.emit()


## The host went without saying why (a refusal says, _refused): the
## connection broke. Timed out when nothing came for a while before.
func _on_server_disconnected() -> void:
	var silent := _now() - _last_heard
	leave()
	_set_error(NetErrors.TIMED_OUT if silent > 3.0 else NetErrors.CONNECTION_LOST)
	var game := Game.find(get_tree())
	if game:
		show_disconnected = true
		game.quit_to_title()
	players_changed.emit()


## Client -> host: who is joining.
@rpc("any_peer", "call_remote", "reliable")
func _hello(joining_name: String, version: String, tag: String, proof: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if not _waiting_hello.has(id) or players.has(id):
		return
	_waiting_hello.erase(id)
	var address: String = _addresses.get(id, "?")
	if joining_name.length() > 64 or version.length() > 32 or tag.length() > 64 or proof.length() > 64:
		_drop(id, NetErrors.HANDSHAKE_FAILED)
		return
	_hello_names[id] = NetGuard.clean_text(joining_name, 16)
	var game_version := str(ProjectSettings.get_setting("application/config/version", "dev"))
	if version != game_version:
		_drop(id, NetErrors.VERSION_MISMATCH, PackedStringArray([game_version, NetGuard.clean_text(version, 32)]))
		return
	if tag.length() != 64 or not tag.is_valid_hex_number():
		_drop(id, NetErrors.HANDSHAKE_FAILED)
		return
	if lists.is_banned(tag):
		_drop(id, NetErrors.BANNED)
		return
	if password != "":
		if proof == "":
			_drop(id, NetErrors.PASSWORD_NEEDED)
			return
		if proof != password_proof(_salt(), str(_nonces.get(id, "")), password):
			_drop(id, NetErrors.WRONG_PASSWORD)
			return
	_nonces.erase(id)
	if not NetGuard.valid_name(joining_name):
		_drop(id, NetErrors.BAD_NAME)
		return
	if whitelist_on() and not lists.is_whitelisted(joining_name, tag) and not lists.is_op(joining_name, tag):
		_drop(id, NetErrors.NOT_WHITELISTED)
		return
	if player_count() >= max_players:
		_drop(id, NetErrors.SERVER_FULL)
		return
	var world := _world()
	if world == null or (not dedicated and _game_player() == null):
		_drop(id, NetErrors.HOST_NOT_IN_WORLD)
		return
	_tags[id] = tag
	var unique_name := joining_name
	var n := 2
	while _name_taken(unique_name):
		unique_name = "%s%d" % [joining_name.left(NetGuard.NAME_MAX - str(n).length()), n]
		n += 1
	players[id] = {"name": unique_name}
	_ops[id] = lists.is_op(unique_name, tag) or lists.is_op(joining_name, tag)
	var saved: Dictionary = saved_players.get(tag, {})
	_modes[id] = clampi(int(saved.get("game_mode", lan_game_mode)), 0, 1)
	var start: Vector3 = saved.get("position", world.find_spawn())
	var now := Time.get_ticks_msec() / 1000.0
	_moves[id] = NetGuard.Mover.new(start if NetGuard.in_world(start) else world.find_spawn(), now)
	_active[id] = now
	var save := world.save
	_welcome.rpc_id(id, {
		"name": save.name if save else "World", "seed": world.world_seed, "generator": world.generator,
		"tall": save.tall_terrain if save else false, "terrain": save.terrain if save else WorldSave.CLASSIC,
		"game_mode": _modes[id], "cheats": can_cheat(id), "op": is_op(id), "view_distance": view_distance,
		"spawn": world.find_spawn(), # the world spawn (not the host's bed)
		"game_time": world.clock.game_time, "day_time": world.clock.day_time,
		"your_name": unique_name, "player": saved,
	})
	_send_players.rpc(players)
	# How everyone already here looks.
	for peer: int in looks:
		_look_of.rpc_id(id, peer, looks[peer].color, looks[peer].png)
	_message(Lang.t("%s joined the game") % unique_name)
	log_event("%s joined the game from %s (#%s)%s" % [unique_name, address, tag.left(8), " as an op" if _ops[id] else ""])
	_server_message.rpc("%s joined the game" % unique_name)
	players_changed.emit()


func _name_taken(wanted: String) -> bool:
	for peer: int in players:
		if str(players[peer].name).to_lower() == wanted.to_lower():
			return true
	return false


## Host -> client: why it can't join or has to go (a NetErrors code and
## its arguments; the client shows them in its language).
@rpc("authority", "call_remote", "reliable")
func _refused(code: int, args: PackedStringArray) -> void:
	_set_error(code if NetErrors.MESSAGES.has(code) else NetErrors.CONNECTION_LOST, NetErrors.clean_args(args))
	password_wanted = NetErrors.wants_password(code)
	var game := Game.find(get_tree())
	leave()
	if game:
		show_disconnected = true # kicked, banned or the server stopped while playing
		game.quit_to_title()
	players_changed.emit()


## Host -> client: the world to play; the client loads it (Game).
@rpc("authority", "call_remote", "reliable")
func _welcome(info: Dictionary) -> void:
	world_info = info
	player_name = str(info.get("your_name", player_name)).left(NetGuard.NAME_MAX)
	cheats = bool(info.get("cheats", false))
	view_limit = clampi(int(info.get("view_distance", 64)), 2, 64)
	var save := WorldSave.new()
	save.remote = true
	save.name = str(info.get("name", "World")).left(64)
	save.world_seed = info.get("seed", 0)
	save.generator = info.get("generator", 0)
	save.tall_terrain = info.get("tall", false)
	save.terrain = info.get("terrain", WorldSave.CLASSIC)
	save.height = int(save.layout().height)
	save.game_mode = info.get("game_mode", 0)
	var saved_player: Dictionary = info.get("player", {})
	save.state = {"player": saved_player if not saved_player.is_empty() else {"position": info.get("spawn", Vector3(8, 140, 8))}}
	WorldSave.current = save
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")
	send_look()


@rpc("authority", "call_remote", "reliable")
func _send_players(all: Dictionary) -> void:
	_last_heard = _now()
	players = all
	# Players gone (the host tells: clients don't see each other's connections).
	for id: int in avatars.keys():
		if not players.has(id):
			if is_instance_valid(avatars[id]):
				(avatars[id] as Node).queue_free()
			avatars.erase(id)
			looks.erase(id)
	players_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _server_message(text: String) -> void:
	_message(text)


## Host: a message for everyone (/say, the console), the log too.
func broadcast_message(text: String) -> void:
	_message(text)
	log_event(text)
	if is_host() and _has_clients():
		_server_message.rpc(text)


## The server list's status answer (ServerStatus): players in, the most,
## the version, the host's name, the world's name (or the motd) as the
## message of the day.
func _status_info() -> Array:
	var world := _world()
	var world_name: String = world.save.name if world and world.save else "World"
	return [player_count(), max_players, str(ProjectSettings.get_setting("application/config/version", "dev")),
		player_name, motd if motd != "" else world_name]


# --- LAN discovery ---------------------------------------------------------------------

## Starts listening for games on the local network (the join screen).
func listen_lan() -> void:
	if _lan_in:
		return
	_lan_in = PacketPeerUDP.new()
	if _lan_in.bind(LAN_PORT) != OK:
		_lan_in = null


func stop_listening_lan() -> void:
	if _lan_in:
		_lan_in.close()
	_lan_in = null
	lan_games.clear()


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if is_host() and _status_responder:
		_status_responder.poll(_status_info)
	if is_host() and _lan_out:
		_lan_timer -= delta
		if _lan_timer <= 0.0:
			_lan_timer = LAN_SEND_SECONDS
			var world := _world()
			var world_name: String = motd if motd != "" else (world.save.name if world and world.save else "World")
			_lan_out.put_packet(("VEBE;%s;%s;%d" % [player_name.replace(";", " "), world_name.replace(";", " "), host_port]).to_utf8_buffer())
	if _lan_in:
		var changed := false
		var read := 0
		while _lan_in.get_available_packet_count() > 0 and read < 64:
			read += 1
			var packet := _lan_in.get_packet()
			if packet.size() > 256:
				continue
			var parts := packet.get_string_from_utf8().split(";")
			if parts.size() < 4 or parts[0] != "VEBE" or not parts[3].is_valid_int():
				continue
			var address := _lan_in.get_packet_ip()
			var key := "%s:%s" % [address, parts[3]]
			if not lan_games.has(key) and lan_games.size() >= LAN_GAMES_MAX:
				continue
			changed = changed or not lan_games.has(key)
			lan_games[key] = {"name": NetGuard.clean_text(parts[1], 32), "world": NetGuard.clean_text(parts[2], 32),
				"address": address, "port": clampi(int(parts[3]), 1, 65535), "seen": now}
		for key: String in lan_games.keys():
			if now - float(lan_games[key].seen) > LAN_FORGET_SECONDS:
				lan_games.erase(key)
				changed = true
		if changed:
			lan_games_changed.emit()
	if is_host():
		for id: int in _waiting_hello.keys():
			if now > float(_waiting_hello[id]):
				_drop(id, NetErrors.HANDSHAKE_FAILED) # never introduced itself
		_second_timer -= delta
		if _second_timer <= 0.0:
			_second_timer = 1.0
			_check_idle(now)
			_check_connections(now)
	if _resolve_id >= 0:
		_poll_resolve()
	if not is_online() or _peer == null or _world() == null:
		return
	_state_timer -= delta
	if _state_timer <= 0.0:
		_state_timer = 1.0 / STATE_RATE
		_send_own_state()
	if is_host() and _has_clients():
		_snapshot_timer -= delta
		if _snapshot_timer <= 0.0:
			_snapshot_timer = SNAPSHOT_SECONDS
			_send_snapshots()
	if is_client():
		_player_save_timer -= delta
		if _player_save_timer <= 0.0:
			_player_save_timer = PLAYER_SAVE_SECONDS
			send_player_state()
	if is_host():
		if not _viewers.is_empty():
			_container_timer -= delta
			if _container_timer <= 0.0:
				_container_timer = CONTAINER_SECONDS
				_send_container_changes()
		_lid_timer -= delta
		if _lid_timer <= 0.0:
			_lid_timer = CONTAINER_SECONDS
			_send_chest_lids()
		if not _pending_blocks.is_empty():
			_blocks_changed.rpc(_pending_blocks)
			_pending_blocks = PackedInt32Array()
		_sync_timer -= delta
		if _sync_timer <= 0.0:
			_sync_timer = SYNC_SECONDS
			_send_world_sync()
		if dedicated:
			_dedicated_sleep(delta)


## Host: players idle for idle_minutes are kicked (0: never).
func _check_idle(now: float) -> void:
	if idle_minutes <= 0:
		return
	for id: int in _clients():
		if now - float(_active.get(id, now)) > idle_minutes * 60.0:
			_drop(id, NetErrors.KICKED_IDLE)


## Host: a client that went quiet (or loses many packets) is told its
## connection is unstable (it arrives when the connection is back) and the
## log says so; ENet's own timeout (PEER_TIMEOUT_MAX_MS) ends it if it
## stays gone. Lag is never a kick.
func _check_connections(now: float) -> void:
	for id: int in _clients():
		if not _heard.has(id) or now - float(_warned.get(id, -WARN_SECONDS)) < WARN_SECONDS:
			continue
		var silent := now - float(_heard[id])
		var peer := _peer.get_peer(id) if _peer else null
		var loss := peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS) / float(ENetPacketPeer.PACKET_LOSS_SCALE) if peer else 0.0
		if silent < CLIENT_SILENT_SECONDS and loss < CLIENT_LOSS:
			continue
		_warned[id] = now
		log_event("[net] %s: connection problems (%s)" % [players[id].name,
			"nothing for %.0f s" % silent if silent >= CLIENT_SILENT_SECONDS else "%d%% packets lost" % roundi(loss * 100.0)])
		_connection_warning.rpc_id(id)


## Host -> client: the host hears it badly (ConnectionIndicator shows it).
@rpc("authority", "call_remote", "reliable")
func _connection_warning() -> void:
	_message(Lang.t("Your connection is unstable"))
	warned_at = _now()


## Client: when the host last said the connection is unstable (s).
var warned_at := -100.0


## Client: how the connection to the host is doing: the round trip (ms,
## -1 unknown) and how long nothing came from the host (s).
func connection_quality() -> Dictionary:
	if not is_client() or _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return {"ping": -1, "silent": 0.0}
	var host_peer := _peer.get_peer(1)
	var ping := int(host_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if host_peer else -1
	return {"ping": ping, "silent": _now() - _last_heard}


## Client: whether to show the connection warning.
func connection_bad() -> bool:
	if _world() == null:
		return false
	var quality := connection_quality()
	return float(quality.silent) > STALL_SECONDS or int(quality.ping) > SLOW_PING_MS or _now() - warned_at < 5.0


## A dedicated server: when every player sleeps for SLEEP_SECONDS, the night
## passes (on the host of an Open to LAN game its own player does it).
func _dedicated_sleep(delta: float) -> void:
	var world := _world()
	var sleeping := false
	for avatar: RemotePlayer in avatars.values():
		sleeping = sleeping or (is_instance_valid(avatar) and avatar.is_sleeping())
	if not sleeping or not all_asleep() or world == null or not DayNightCycle.is_night(world.clock.day_time):
		_sleep_time = 0.0
		return
	_sleep_time += delta
	if _sleep_time >= SLEEP_SECONDS:
		_sleep_time = 0.0
		world.clock.add_day_time(WorldClock.TICKS_PER_DAY - fposmod(world.clock.day_time, WorldClock.TICKS_PER_DAY))
		broadcast_message("Good morning")
		_send_world_sync()


# --- World: columns and block changes ----------------------------------------------------

## Host: a block changed (VoxelWorld.set_block); sent to the clients with the
## rest of this frame's changes.
func block_changed(pos: Vector3i, id: int) -> void:
	if is_host() and _has_clients():
		_pending_blocks.append_array(PackedInt32Array([pos.x, pos.y, pos.z, id]))


## Client: what to do with a column the world wants: "wait" (asked, no answer
## yet), "generate" or its blocks (PackedInt32Array).
func column_for(column: Vector2i) -> Variant:
	if _answers.has(column):
		var answer: Variant = _answers[column]
		_answers.erase(column)
		_asked.erase(column)
		return answer if (answer as PackedInt32Array).size() > 0 else "generate"
	var asked: Variant = _asked.get(column)
	if asked == null or (asked is float and Time.get_ticks_msec() / 1000.0 >= float(asked)):
		_asked[column] = true
		_request_column.rpc_id(1, column.x, column.y)
	return "wait"


## Client: block changes that came while the column was on its way.
func take_waiting_changes(column: Vector2i) -> PackedInt32Array:
	var changes: PackedInt32Array = _waiting_changes.get(column, PackedInt32Array())
	_waiting_changes.erase(column)
	return changes


## Host: where a client's player is as the host accepted it.
func _position_of(peer: int) -> Vector3:
	if peer == 1 or (peer == multiplayer.get_unique_id() and is_host()):
		var player := _game_player()
		return player.global_position if player else Vector3.INF
	var mover: NetGuard.Mover = _moves.get(peer)
	return mover.position if mover else Vector3.INF


@rpc("any_peer", "call_remote", "reliable")
func _request_column(cx: int, cz: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not is_host() or not _within(peer, "column", COLUMN_LIMIT, 1.0):
		return
	var at := _position_of(peer)
	if absi(cx) > 2000000 or absi(cz) > 2000000 or at == Vector3.INF:
		_strike(peer, "column out of the world", 2)
		return
	var world := _world()
	# Only around where the host sees the player: nobody makes the host
	# read (or answer for) the whole world.
	if maxi(absi(cx - (floori(at.x) >> 4)), absi(cz - (floori(at.z) >> 4))) > view_distance + 2:
		_column_later.rpc_id(peer, cx, cz)
		return
	var data := PackedByteArray()
	if world:
		var blocks := world.column_blocks_for_network(Vector2i(cx, cz))
		if not blocks.is_empty():
			data = blocks.to_byte_array().compress(FileAccess.COMPRESSION_ZSTD)
	var signs: Array = world.column_signs_for_network(Vector2i(cx, cz)) if world else []
	_column_answer.rpc_id(peer, cx, cz, data, signs)


@rpc("authority", "call_remote", "reliable")
func _column_answer(cx: int, cz: int, data: PackedByteArray, signs: Array) -> void:
	var world := _world()
	if world:
		for sign: Variant in signs:
			if sign is Array and (sign as Array).size() == 4:
				world.apply_network_sign(Vector3i(int(sign[0]), int(sign[1]), int(sign[2])), _sign_lines(sign[3]))
	var blocks := PackedInt32Array()
	if not data.is_empty():
		blocks = data.decompress(WorldGenerator.COLUMN_VOLUME * 4, FileAccess.COMPRESSION_ZSTD).to_int32_array()
		if blocks.size() != WorldGenerator.COLUMN_VOLUME:
			blocks = PackedInt32Array()
	_answers[Vector2i(cx, cz)] = blocks


## Host -> client: that column is beyond the view distance from where the
## host sees the player; ask again in a moment.
@rpc("authority", "call_remote", "reliable")
func _column_later(cx: int, cz: int) -> void:
	_asked[Vector2i(cx, cz)] = Time.get_ticks_msec() / 1000.0 + 3.0


@rpc("authority", "call_remote", "reliable")
func _blocks_changed(changes: PackedInt32Array) -> void:
	var world := _world()
	if world == null:
		return
	var later := world.apply_network_blocks(changes)
	# Changes for columns still on their way: applied when they arrive.
	for i in range(0, later.size(), 4):
		var column := Vector2i(later[i] >> 4, later[i + 2] >> 4)
		if _asked.has(column) or _answers.has(column):
			var list: PackedInt32Array = _waiting_changes.get(column, PackedInt32Array())
			list.append_array(later.slice(i, i + 4))
			_waiting_changes[column] = list


## Client -> host: the text its player wrote on a sign.
func send_sign(pos: Vector3i, lines: Array) -> void:
	_client_sign.rpc_id(1, pos, lines)


## Host: a sign's text changed (here or from a client): to every client.
func sign_changed(pos: Vector3i, lines: Array) -> void:
	if _has_clients():
		_sign_text.rpc(pos, lines)


## At most four lines of a sign's length (from the network), cleaned.
static func _sign_lines(value: Variant) -> Array:
	var lines := ["", "", "", ""]
	if value is Array:
		for i in mini((value as Array).size(), 4):
			lines[i] = NetGuard.clean_text(str(value[i]).left(SignBehavior.LINE_LENGTH * 2), SignBehavior.LINE_LENGTH)
	return lines


@rpc("any_peer", "call_remote", "reliable")
func _client_sign(pos: Vector3i, lines: Array) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var world := _world()
	if world == null or not _within(peer, "edit", EDIT_LIMIT, 1.0) or lines.size() > 4:
		return
	if not _edit_allowed(peer, pos, true):
		return
	world.set_sign_text(pos, _sign_lines(lines))


@rpc("authority", "call_remote", "reliable")
func _sign_text(pos: Vector3i, lines: Array) -> void:
	var world := _world()
	if world:
		world.apply_network_sign(pos, _sign_lines(lines))


## Client -> host: a block set by the player (placing, buckets...).
func send_set_block(pos: Vector3i, id: int) -> void:
	_client_set_block.rpc_id(1, pos.x, pos.y, pos.z, id)


## Client -> host: a block broken by the player (its drops on the ground).
func send_destroy(pos: Vector3i, drop: bool, can_harvest: bool) -> void:
	_client_destroy.rpc_id(1, pos.x, pos.y, pos.z, drop, can_harvest)


## Client -> host: a lever, button, door, trapdoor or note block used.
func send_use(pos: Vector3i) -> void:
	_client_use.rpc_id(1, pos.x, pos.y, pos.z)


## Host: whether the player of `peer` may change (or use) the block at
## `pos`: loaded here, within its reach, outside the spawn protection
## (`protected`: an edit, not a use) unless an op.
func _edit_allowed(peer: int, pos: Vector3i, protected: bool) -> bool:
	var world := _world()
	if not NetGuard.in_world_i(pos):
		_strike(peer, "block out of the world %s" % pos, 3)
		return false
	if world == null or not world.is_inside(pos):
		return false # (land the host hasn't loaded: the player can't be there)
	var at := _position_of(peer)
	if at == Vector3.INF:
		return false
	var reach := REACH_CREATIVE if is_creative(peer) else REACH_SURVIVAL
	if NetGuard.distance_to_block(at + Vector3(0, Player.EYE_HEIGHT, 0), pos) > reach:
		_strike(peer, "out of reach %s" % pos, 0)
		return false
	if protected and _spawn_protected(peer, pos):
		_command_output.rpc_id(peer, Lang.t("The spawn is protected: only ops can change it"), CommandSource.MessageKind.ERROR)
		return false
	return true


func _spawn_protected(peer: int, pos: Vector3i) -> bool:
	if spawn_protection <= 0 or is_op(peer):
		return false
	var now := Time.get_ticks_msec() / 1000.0
	if now - _spawn_cached_at > 10.0:
		_spawn_cached_at = now
		var world := _world()
		_spawn_cache = world.find_spawn() if world else Vector3.INF
	if _spawn_cache == Vector3.INF:
		return false
	return absi(pos.x - floori(_spawn_cache.x)) <= spawn_protection and absi(pos.z - floori(_spawn_cache.z)) <= spawn_protection


## Host -> a client whose edit was refused: the block as it really is.
func _restore_block(peer: int, pos: Vector3i) -> void:
	var world := _world()
	if world and world.is_inside(pos) and NetGuard.in_world_i(pos):
		_blocks_changed.rpc_id(peer, PackedInt32Array([pos.x, pos.y, pos.z, world.get_block(pos)]))


@rpc("any_peer", "call_remote", "reliable")
func _client_set_block(x: int, y: int, z: int, id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var world := _world()
	if world == null or not _within(peer, "edit", EDIT_LIMIT, 1.0):
		return
	var pos := Vector3i(x, y, z)
	if id < 0 or id >= Blocks.count():
		_strike(peer, "no such block %d" % id, 5)
		_restore_block(peer, pos)
		return
	if not _edit_allowed(peer, pos, true):
		_restore_block(peer, pos)
		return
	if not is_creative(peer) and NetGuard.survival_forbidden(id):
		_strike(peer, "placing %s in survival" % Blocks.get_type(id).name, 2) # (or its game mode just changed)
		_restore_block(peer, pos)
		return
	_active[peer] = Time.get_ticks_msec() / 1000.0
	world.set_block(pos, id)


@rpc("any_peer", "call_remote", "reliable")
func _client_destroy(x: int, y: int, z: int, drop: bool, can_harvest: bool) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var world := _world()
	if world == null or not _within(peer, "edit", EDIT_LIMIT, 1.0):
		return
	var pos := Vector3i(x, y, z)
	if not _edit_allowed(peer, pos, true):
		_restore_block(peer, pos)
		return
	var id := world.get_block(pos)
	if id == Blocks.AIR:
		return
	var creative := is_creative(peer)
	if not creative and NetGuard.unbreakable(id):
		_strike(peer, "breaking %s in survival" % Blocks.get_type(id).name, 2)
		_restore_block(peer, pos)
		return
	# What drops is the host's call: nothing in creative; the right tool by
	# what the player holds (as it last said).
	var avatar := _avatar_of(peer)
	var held := avatar.held_block() if avatar else Blocks.AIR
	_active[peer] = Time.get_ticks_msec() / 1000.0
	world.destroy_block(pos, drop and not creative, can_harvest and Items.can_harvest(held, id))


@rpc("any_peer", "call_remote", "reliable")
func _client_use(x: int, y: int, z: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var world := _world()
	if world == null or not _within(peer, "edit", EDIT_LIMIT, 1.0):
		return
	var pos := Vector3i(x, y, z)
	if _edit_allowed(peer, pos, false):
		_active[peer] = Time.get_ticks_msec() / 1000.0
		BlockInteraction.use_shared(world, pos)


## Host: where the clients' players are (their columns are kept loaded).
func remote_columns() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for avatar: RemotePlayer in avatars.values():
		if is_instance_valid(avatar):
			var at := avatar.target_position
			result.append(Vector2i(floori(at.x / ChunkData.SIZE), floori(at.z / ChunkData.SIZE)))
	return result


# --- Players ---------------------------------------------------------------------------------

## The local player swung its arm (shown on the others' screens).
func swung() -> void:
	_swings += 1


func _send_own_state() -> void:
	var player := _game_player()
	if player == null:
		return
	var flags := (1 if player.sneaking else 0) | (2 if player.vehicle else 0) | (4 if player.dead else 0) \
		| (8 if player.sleeping else 0) | (16 if player.is_creative() else 0)
	if is_host():
		for peer in _clients():
			_peer_state.rpc_id(peer, 1, player.global_position, player.rotation.y, player.pitch(), flags, player.held_block(), _swings)
	else:
		_player_state.rpc_id(1, player.global_position, player.rotation.y, player.pitch(), flags, player.held_block(), _swings)


## Client -> host: where its player is now (20 times a second). The host
## checks the move (NetGuard.Mover) and passes it on to the others.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _player_state(at: Vector3, yaw: float, pitch: float, flags: int, held: int, swings: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	var world := _world()
	if _joined(id):
		_heard[id] = _now()
	if world == null or not _within(id, "state", STATE_LIMIT, 1.0):
		return
	if not NetGuard.in_world(at) or not is_finite(yaw) or not is_finite(pitch):
		_strike(id, "impossible position", 3)
		return
	flags &= 31
	if held != Blocks.AIR and not Items.exists(held):
		held = Blocks.AIR
	pitch = clampf(pitch, -PI, PI)
	var now := Time.get_ticks_msec() / 1000.0
	var mover: NetGuard.Mover = _moves.get(id)
	if mover == null:
		return
	var dead := flags & 4 != 0
	if mover.dead and not dead and _respawn_ok(id, at):
		mover.teleport(at, now) # back to life at the spawn or its bed
		mover.waiting_for = Vector3.INF
	mover.dead = dead
	var creative := is_creative(id)
	var before := mover.position
	var verdict := mover.check(at, now, creative, flags & 2 != 0)
	if verdict == NetGuard.Mover.IGNORE:
		return
	if verdict == NetGuard.Mover.REJECT:
		# Sent back to where it was last fine (lag that outran even the
		# allowance looks the same); only a long run of large ones kicks.
		var excess := mover.excess
		if mover.violated(now):
			_drop(id, NetErrors.KICKED_MOVING)
			return
		var count := mover.violations.size()
		if count <= 3 or count % 10 == 0:
			log_event("[movement] %s moved %.1f blocks too far (%d lately), sent back" % [players[id].name, excess, count])
		_correct_position.rpc_id(id, mover.position)
		return
	# The game mode is the host's: a client saying otherwise is told again.
	if (flags & 16 != 0) != creative and now - float(_mode_told.get(id, -10.0)) > 2.0:
		_mode_told[id] = now
		_set_mode.rpc_id(id, _modes.get(id, lan_game_mode), can_cheat(id))
	flags = (flags & ~16) | (16 if creative else 0)
	var avatar: RemotePlayer = avatars.get(id)
	if avatar and is_instance_valid(avatar) and (before.distance_to(at) > 0.05 or absf(angle_difference(avatar.rotation.y, yaw)) > 0.05):
		_active[id] = now
	_show_state(id, at, yaw, pitch, flags, held, swings)
	for peer in _clients():
		if peer != id:
			_peer_state.rpc_id(peer, id, at, yaw, pitch, flags, held, swings)


## Host: whether a player coming back to life at `at` is where it may
## respawn: the world spawn or by a bed (the one it last slept in).
func _respawn_ok(peer: int, at: Vector3) -> bool:
	var world := _world()
	if world == null:
		return false
	var spawn := world.find_spawn()
	if Vector2(at.x - spawn.x, at.z - spawn.z).length() < 8.0:
		return true
	var saved: Dictionary = saved_players.get(_tags.get(peer, ""), {})
	var bed: Variant = saved.get("spawn", Vector3.INF)
	if bed is Vector3 and bed != Vector3.INF and (bed as Vector3).distance_to(at) < 4.0:
		return true
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			for dy in range(-1, 2):
				if Blocks.family_of(world.get_block(Vector3i(at.floor()) + Vector3i(dx, dy, dz))).begins_with("bed_"):
					return true
	return false


## Host -> client: the other player `id` (or the host's own, 1) moved.
@rpc("authority", "call_remote", "unreliable_ordered")
func _peer_state(id: int, at: Vector3, yaw: float, pitch: float, flags: int, held: int, swings: int) -> void:
	_last_heard = _now()
	if id == multiplayer.get_unique_id() or not players.has(id):
		return
	_show_state(id, at, yaw, pitch, flags, held, swings)


func _show_state(id: int, at: Vector3, yaw: float, pitch: float, flags: int, held: int, swings: int) -> void:
	var world := _world()
	if world == null or not players.has(id):
		return
	var avatar: RemotePlayer = avatars.get(id)
	if avatar == null or not is_instance_valid(avatar):
		avatar = RemotePlayer.new()
		avatar.world = world
		avatar.peer_id = id
		avatar.player_name = players[id].name
		world.add_child(avatar)
		avatar.global_position = at
		avatars[id] = avatar
		var look: Dictionary = looks.get(id, {})
		avatar.set_look(int(look.get("color", 0)), look.get("skin"))
	avatar.set_state(at, yaw, pitch, flags, held, swings)


## Host -> client: back to where the host saw it (it moved too fast), or
## moved by the host (/tp, a respawn the host decided).
@rpc("authority", "call_remote", "reliable")
func _correct_position(at: Vector3) -> void:
	var player := _game_player()
	if player and at.is_finite():
		CommandTargets.teleport(player, at)


## Host: moves a client's player (/tp from the host or the console).
func teleport_peer(peer: int, at: Vector3) -> void:
	if peer == multiplayer.get_unique_id():
		var player := _game_player()
		if player:
			CommandTargets.teleport(player, at)
		return
	var mover: NetGuard.Mover = _moves.get(peer)
	if mover:
		mover.teleport(at, Time.get_ticks_msec() / 1000.0)
	var avatar := _avatar_of(peer)
	if avatar:
		avatar.target_position = at
	_correct_position.rpc_id(peer, at)


## Host: the game mode of a player (0 survival, 1 creative), kept with its
## player in the save.
func is_creative(peer: int) -> bool:
	if peer == multiplayer.get_unique_id():
		var player := _game_player()
		return player != null and player.is_creative()
	return int(_modes.get(peer, lan_game_mode)) == Player.GameMode.CREATIVE


func set_peer_game_mode(peer: int, game_mode: int) -> void:
	if peer == multiplayer.get_unique_id():
		var player := _game_player()
		if player:
			player.game_mode = game_mode as Player.GameMode
		return
	_modes[peer] = game_mode
	var tag: String = _tags.get(peer, "")
	if tag != "":
		var saved: Dictionary = saved_players.get(tag, {})
		saved["game_mode"] = game_mode
		saved_players[tag] = saved
	_set_mode.rpc_id(peer, game_mode, can_cheat(peer))


## Host -> client: its game mode and whether it may cheat (an op).
@rpc("authority", "call_remote", "reliable")
func _set_mode(game_mode: int, may_cheat: bool) -> void:
	cheats = may_cheat
	var player := _game_player()
	if player and player.game_mode != clampi(game_mode, 0, 1):
		player.game_mode = clampi(game_mode, 0, 1) as Player.GameMode


# --- Chat, time and weather -------------------------------------------------------------------

## Says something to everyone (the chat already shows it here).
func say(text: String) -> void:
	text = NetGuard.clean_text(text)
	if text == "":
		return
	if is_host():
		log_event("<%s> %s" % [player_name, text])
		for peer in _clients():
			_chat_from.rpc_id(peer, 1, player_name, text)
	elif is_client():
		_chat_line.rpc_id(1, text)


## Client -> host: a chat line; the host passes it on with the name it knows.
@rpc("any_peer", "call_remote", "reliable")
func _chat_line(text: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not _within(sender, "chat", CHAT_LIMIT, 5.0):
		return
	text = NetGuard.clean_text(text)
	if text == "":
		return
	_active[sender] = Time.get_ticks_msec() / 1000.0
	var from: String = players[sender].name
	log_event("<%s> %s" % [from, text])
	var chat := _chat()
	if chat:
		chat.add_chat(from, text, color_of(sender))
	for peer in _clients():
		if peer != sender:
			_chat_from.rpc_id(peer, sender, from, text)


## Host -> client: someone's chat line.
@rpc("authority", "call_remote", "reliable")
func _chat_from(id: int, from: String, text: String) -> void:
	var chat := _chat()
	if chat:
		chat.add_chat(from.left(NetGuard.NAME_MAX + 4), text.left(NetGuard.CHAT_MAX), color_of(id))


# --- Looks: name colors and skins ----------------------------------------------------------

func _own_look() -> Dictionary:
	return {"color": PlayerProfile.name_color, "png": PlayerProfile.skin_png(), "skin": PlayerProfile.skin}


## Sends this player's name color and skin to everyone (on joining and
## when they change in Player Settings).
func send_look() -> void:
	if not is_online() or multiplayer.multiplayer_peer == null or dedicated:
		return
	var own := _own_look()
	var id := multiplayer.get_unique_id()
	looks[id] = own
	if is_host():
		for peer in _clients():
			_look_of.rpc_id(peer, id, own.color, own.png)
	else:
		_look.rpc_id(1, own.color, own.png)
	players_changed.emit()


## Client -> host: its look; checked (a small real skin) and passed on.
@rpc("any_peer", "call_remote", "reliable")
func _look(color: int, png: PackedByteArray) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not _within(sender, "look", 6, 10.0):
		return
	var skin: Texture2D = null
	if png.size() > NetGuard.SKIN_BYTES:
		_strike(sender, "skin of %d bytes" % png.size(), 3)
		png = PackedByteArray()
	elif not png.is_empty():
		skin = PlayerProfile.skin_from_png(png)
		if skin == null:
			png = PackedByteArray()
	color = clampi(color, 0, PlayerProfile.COLORS.size() - 1)
	_set_look(sender, color, png, skin)
	for peer in _clients():
		if peer != sender:
			_look_of.rpc_id(peer, sender, color, png)


## Host -> client: how player `id` looks.
@rpc("authority", "call_remote", "reliable")
func _look_of(id: int, color: int, png: PackedByteArray) -> void:
	if png.size() > NetGuard.SKIN_BYTES:
		png = PackedByteArray()
	_set_look(id, clampi(color, 0, PlayerProfile.COLORS.size() - 1), png, PlayerProfile.skin_from_png(png))


func _set_look(id: int, color: int, png: PackedByteArray, skin: Texture2D) -> void:
	looks[id] = {"color": color, "png": png, "skin": skin}
	var avatar: RemotePlayer = avatars.get(id)
	if avatar and is_instance_valid(avatar):
		avatar.set_look(color, skin)
	players_changed.emit()


## Name color of a player (PlayerProfile.COLORS index).
func color_of(id: int) -> int:
	if id == multiplayer.get_unique_id() or not is_online():
		return PlayerProfile.name_color
	return int(looks.get(id, {}).get("color", 0))


## Skin of a player (null: the default one).
func skin_of(id: int) -> Texture2D:
	if not is_online() or id == multiplayer.get_unique_id():
		return PlayerProfile.skin
	return looks.get(id, {}).get("skin")


func _send_world_sync() -> void:
	var world := _world()
	if world == null or not _has_clients():
		return
	# The round trip to each player (ENet's measure), for the Tab list.
	for id: int in players:
		var peer := _peer.get_peer(id) if id != 1 and _peer else null
		players[id]["ping"] = 0 if id == 1 else (int(peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if peer else -1)
	_send_players.rpc(players)
	players_changed.emit()
	var weather := world.weather
	_world_sync.rpc(world.clock.game_time, world.clock.day_time, weather.raining, weather.rain_strength,
		weather.thundering, weather.thunder_strength)
	if not _lids_sent.is_empty():
		_chest_lids.rpc(_lids_sent) # (for players who joined since)


@rpc("authority", "call_remote", "reliable")
func _world_sync(game_time: int, day_time: float, raining: bool, rain: float, thundering: bool, thunder: float) -> void:
	_last_heard = _now()
	var world := _world()
	if world == null:
		return
	world.clock.game_time = game_time
	world.clock.day_time = day_time
	world.weather.raining = raining
	world.weather.rain_strength = rain
	world.weather.thundering = thundering
	world.weather.thunder_strength = thunder


# --- Permissions, the host's commands (NetCommands), bans and lists ---------------------------

## Whether a player is an op: the host of an Open to LAN game always, a
## client when on the ops list (ServerLists, its name tied to its tag).
func is_op(peer: int) -> bool:
	if peer == multiplayer.get_unique_id() or peer == 0:
		return is_host() or not is_online()
	return bool(_ops.get(peer, false))


## Whether a player may run cheat commands: ops, and everyone in an Open to
## LAN game with Allow Cheats on.
func can_cheat(peer: int) -> bool:
	return is_op(peer) or (cheats and not dedicated)


func whitelist_on() -> bool:
	return server.config.get_bool("white-list") if dedicated else lists.whitelist_enabled()


func set_whitelist(on: bool) -> void:
	if dedicated:
		server.config.set_value("white-list", on)
	else:
		lists.set_whitelist_enabled(on)


func is_banned(tag: String) -> bool:
	return lists.is_banned(tag)


## The players with their tags (first 8 characters) and addresses.
func describe_players() -> String:
	var lines := PackedStringArray()
	for id: int in players:
		var tag: String = PlayerProfile.tag_for_server(_salt()) if id == 1 else _tags.get(id, "")
		lines.append("%s  #%s  %s%s%s" % [players[id].name, tag.left(8), "host" if id == 1 else _addresses.get(id, "?"),
			"  op" if is_op(id) and id != 1 else "", "  creative" if is_creative(id) else ""])
	if lines.is_empty():
		lines.append(Lang.t("Nobody is here"))
	return "\n".join(lines)


func _peer_named(player: String) -> int:
	for id: int in players:
		if str(players[id].name).to_lower() == player.strip_edges().to_lower() and id != 1:
			return id
	return 0


func kick(player: String, reason: String = "") -> String:
	var id := _peer_named(player)
	if id == 0:
		return ""
	var who: String = players[id].name
	if reason.strip_edges() != "":
		_drop(id, NetErrors.KICKED_REASON, PackedStringArray([NetGuard.clean_text(reason, 100)]))
	else:
		_drop(id, NetErrors.KICKED)
	return who


## Bans a player's tag (they can't come back from that computer) and kicks them.
func ban(player: String) -> String:
	var id := _peer_named(player)
	if id == 0 or not _tags.has(id):
		return ""
	var who: String = players[id].name
	lists.ban(_tags[id], who)
	_drop(id, NetErrors.BANNED)
	return who


## Lifts a ban by the start of the tag (or the name it was banned with).
func pardon(tag_or_name: String) -> String:
	return lists.pardon(tag_or_name)


## Bans an address (or the address of the player named so) and kicks
## everyone from it. Returns the address or "".
func ban_ip(target: String) -> String:
	var address := target.strip_edges()
	var id := _peer_named(address)
	if id != 0:
		address = _addresses.get(id, "")
	if not address.is_valid_ip_address():
		return ""
	lists.ban_ip(address, players[id].name if id != 0 else "")
	for peer: int in _addresses.keys():
		if _addresses[peer] == address:
			_drop(peer, NetErrors.BANNED)
	return address


func pardon_ip(address: String) -> bool:
	return lists.pardon_ip(address)


## Makes a player an op (online: tied to its computer; else by name, tied
## when it joins). Returns the name.
func op_player(player: String) -> String:
	var id := _peer_named(player)
	var who := player.strip_edges()
	if id != 0:
		who = players[id].name
		lists.op(who, _tags.get(id, ""))
		_ops[id] = true
		_set_mode.rpc_id(id, _modes.get(id, lan_game_mode), can_cheat(id))
		_command_output.rpc_id(id, Lang.t("You are now an operator"), CommandSource.MessageKind.INFO)
	elif NetGuard.valid_name(who):
		lists.op(who, "")
	else:
		return ""
	return who


func deop_player(player: String) -> String:
	var id := _peer_named(player)
	var who: String = players[id].name if id != 0 else player.strip_edges()
	var was := lists.deop(who)
	if id != 0 and _ops.get(id, false):
		_ops[id] = false
		was = true
		_set_mode.rpc_id(id, _modes.get(id, lan_game_mode), can_cheat(id))
		_command_output.rpc_id(id, Lang.t("You are no longer an operator"), CommandSource.MessageKind.INFO)
	return who if was else ""


func whitelist_add(player: String) -> String:
	var id := _peer_named(player)
	var who: String = players[id].name if id != 0 else player.strip_edges()
	if id == 0 and not NetGuard.valid_name(who):
		return ""
	lists.whitelist_add(who, _tags.get(id, "") if id != 0 else "")
	return who


func whitelist_remove(player: String) -> String:
	var who := player.strip_edges()
	return who if lists.whitelist_remove(who) else ""


## Saves the world now (the players' newest states come with the next save).
func save_all() -> void:
	if is_host() and _has_clients():
		_save_request.rpc()
	var game := Game.find(get_tree())
	if game:
		game.save_game()


## Host -> clients: send your player now (a save is coming).
@rpc("authority", "call_remote", "reliable")
func _save_request() -> void:
	send_player_state()


## A dedicated server stopping: everyone's player is asked for, then they
## are sent away (`code`: NetErrors).
func shutdown_server(code: int) -> void:
	if not is_host():
		return
	if _has_clients():
		_save_request.rpc()
		await get_tree().create_timer(1.0).timeout
		for peer in _clients():
			_drop(peer, code)
		await get_tree().create_timer(0.7).timeout


# --- Entities and dropped items (the host's, seen by clients) --------------------------------

func _avatar_of(peer: int) -> RemotePlayer:
	var avatar: RemotePlayer = avatars.get(peer)
	return avatar if avatar and is_instance_valid(avatar) else null


## Host: each client gets the entities and items near its player: new ones
## whole (SNAPSHOT_NEW at a time), all with where they are now, and which
## ones went; at most SNAPSHOT_ENTITIES / SNAPSHOT_ITEMS in one.
func _send_snapshots() -> void:
	var world := _world()
	if world == null:
		return
	for peer: int in players:
		if peer == 1:
			continue
		var avatar := _avatar_of(peer)
		if avatar == null:
			continue
		var at := avatar.target_position
		var known: Dictionary = _known_entities.get(peer, {})
		var seen := {}
		var entries := []
		var new_ones := 0
		for entity in world.entities.all():
			if entries.size() >= SNAPSHOT_ENTITIES:
				break
			if entity.removed or entity.type_name() == "fishing_bobber":
				continue
			if Vector2(entity.feet().x - at.x, entity.feet().z - at.z).length() > ENTITY_RANGE:
				continue
			if entity.net_id == 0:
				entity.net_id = _next_net_id
				_next_net_id += 1
			var is_new := not known.has(entity.net_id)
			if is_new:
				if new_ones >= SNAPSHOT_NEW:
					continue # (next time)
				new_ones += 1
			seen[entity.net_id] = true
			entries.append([entity.net_id, entity.feet(), entity.net_yaw(), entity.net_state(), entity.save_state() if is_new else null])
		var gone := PackedInt32Array()
		for id: int in known:
			if not seen.has(id):
				gone.append(id)
		_known_entities[peer] = seen
		var known_items: Dictionary = _known_items.get(peer, {})
		var seen_items := {}
		var items := []
		for item: Dictionary in world.items.net_items():
			if items.size() >= SNAPSHOT_ITEMS:
				break
			var pos: Vector3 = item.pos
			if Vector2(pos.x - at.x, pos.z - at.z).length() > ITEM_RANGE:
				continue
			if not item.has("nid"):
				item.nid = _next_net_id
				_next_net_id += 1
			seen_items[item.nid] = true
			items.append([item.nid, item.id, item.count, item.damage, pos])
		var items_gone := PackedInt32Array()
		for id: int in known_items:
			if not seen_items.has(id):
				items_gone.append(id)
		_known_items[peer] = seen_items
		_snapshot.rpc_id(peer, entries, gone, items, items_gone)


@rpc("authority", "call_remote", "reliable")
func _snapshot(entries: Array, gone: PackedInt32Array, items: Array, items_gone: PackedInt32Array) -> void:
	_last_heard = _now()
	var world := _world()
	if world == null:
		return
	for entry: Array in entries:
		var id: int = entry[0]
		var puppet: Entity = _puppets.get(id)
		if puppet == null or not is_instance_valid(puppet) or puppet.removed:
			var whole: Variant = entry[4]
			if whole == null:
				continue # (its whole state comes again: seen anew)
			puppet = world.entities.create(str((whole as Dictionary).get("type", "")))
			if puppet == null:
				continue
			puppet.puppet = true
			puppet.net_id = id
			world.entities.spawn(puppet, entry[1])
			puppet.load_state(whole)
			_puppets[id] = puppet
		puppet.apply_net_state(entry[1], entry[2], entry[3])
	for id in gone:
		var puppet: Entity = _puppets.get(id)
		if puppet and is_instance_valid(puppet):
			puppet.removed = true
		_puppets.erase(id)
	world.items.apply_net_items(items, items_gone)


## Client -> host: an entity made here (EntityManager.spawn) for the host
## to make.
func send_spawn(entity: Entity) -> void:
	var extra := {"velocity": entity.velocity, "yaw": entity.net_yaw()}
	if entity is Arrow:
		extra["power"] = (entity as Arrow).power
	_client_spawn.rpc_id(1, entity.save_state(), extra)


@rpc("any_peer", "call_remote", "reliable")
func _client_spawn(state: Dictionary, extra: Dictionary) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var world := _world()
	if world == null or not _within(peer, "spawn", SPAWN_LIMIT, 1.0):
		return
	if state.size() > 32 or extra.size() > 8:
		_strike(peer, "entity state too big", 3)
		return
	var type := str(state.get("type", ""))
	if not type in CLIENT_SPAWNS:
		_strike(peer, "making a %s" % type.left(32), 5)
		return
	var entity := world.entities.create(type)
	if entity == null:
		return
	# Only the keys (and value types) this kind has; where it appears near
	# the player; no faster than a full bow's arrow.
	var clean := NetGuard.clean_entity_state(state, entity.save_state())
	var at: Vector3 = clean.get("position", Vector3.INF)
	var eye := _position_of(peer) + Vector3(0, Player.EYE_HEIGHT, 0)
	if not NetGuard.in_world(at) or not eye.is_finite() or at.distance_to(eye) > (REACH_CREATIVE if is_creative(peer) else REACH_SURVIVAL) + 2.0:
		_strike(peer, "a %s out of reach" % type, 0)
		entity.free()
		return
	if type == "tnt":
		clean["fuse"] = PrimedTnt.FUSE
	world.entities.spawn(entity, at)
	entity.load_state(clean)
	var velocity: Variant = extra.get("velocity", Vector3.ZERO)
	entity.velocity = (velocity as Vector3).limit_length(4.0) if velocity is Vector3 and (velocity as Vector3).is_finite() else Vector3.ZERO
	var yaw: Variant = extra.get("yaw", 0.0)
	if "_yaw" in entity and yaw is float and is_finite(yaw):
		entity.set("_yaw", yaw)
	if entity is Arrow:
		(entity as Arrow).shooter = _avatar_of(peer)
		var power: Variant = extra.get("power", 1.0)
		(entity as Arrow).power = clampf(power, 0.0, 1.0) if power is float and is_finite(power) else 1.0


## Client -> host: hit the host's entity `id` for `amount`.
func send_attack(id: int, amount: int) -> void:
	_client_attack.rpc_id(1, id, amount)


## The hardest hit a player can make with what it holds (a critical hit
## is half as hard again).
func _max_hit(peer: int) -> int:
	var avatar := _avatar_of(peer)
	var damage := Items.attack_damage(avatar.held_block() if avatar else Blocks.AIR)
	return damage + damage / 2 + 1


@rpc("any_peer", "call_remote", "reliable")
func _client_attack(id: int, amount: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var world := _world()
	if world == null or not _within(peer, "attack", ATTACK_LIMIT, 1.0):
		return
	var entity := world.entities.by_net_id(id)
	var avatar := _avatar_of(peer)
	if entity == null or avatar == null or avatar.dead:
		return
	if entity.center().distance_to(avatar.target_position + Vector3(0, Player.EYE_HEIGHT, 0)) > REACH_SURVIVAL + 1.0:
		_strike(peer, "hit out of reach", 0)
		return
	_active[peer] = Time.get_ticks_msec() / 1000.0
	if entity.damage(clampi(amount, 0, _max_hit(peer)), avatar.target_position) and entity is Mob:
		(entity as Mob).hurt_by(avatar)


## Client -> host: get into the host's boat or minecart `id`.
func send_mount(id: int) -> void:
	_client_mount.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func _client_mount(id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var world := _world()
	var avatar := _avatar_of(peer)
	if world == null or avatar == null or avatar.dead or not _within(peer, "edit", EDIT_LIMIT, 1.0):
		return
	var entity := world.entities.by_net_id(id)
	if entity == null or entity.center().distance_to(avatar.target_position) > REACH_CREATIVE:
		return
	if (entity is Boat or (entity is Minecart and entity.type_name() == "minecart")) and entity.seat_free():
		entity.remote_rider = peer
		_mounted.rpc_id(peer, id)


@rpc("authority", "call_remote", "reliable")
func _mounted(id: int) -> void:
	var puppet: Entity = _puppets.get(id)
	var player := _game_player()
	if puppet and is_instance_valid(puppet) and player and player.vehicle == null:
		player.mount(puppet)


## Client -> host: rowing / pushing the vehicle it rides, or getting off.
func send_steer(id: int, forward: float, look: Vector3) -> void:
	_client_steer.rpc_id(1, id, forward, look)


func send_dismount(id: int) -> void:
	_client_dismount.rpc_id(1, id)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _client_steer(id: int, forward: float, look: Vector3) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var world := _world()
	if world == null or not _within(peer, "steer", STATE_LIMIT, 1.0) or not look.is_finite() or not is_finite(forward):
		return
	var entity := world.entities.by_net_id(id)
	if entity and entity.remote_rider == peer and entity.has_method("steer"):
		entity.call("steer", clampf(forward, -1.0, 1.0), look.normalized() if look.length() > 0.001 else Vector3.FORWARD)


@rpc("any_peer", "call_remote", "reliable")
func _client_dismount(id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var world := _world()
	if world == null or not _joined(peer):
		return
	var entity := world.entities.by_net_id(id)
	if entity and entity.remote_rider == peer:
		entity.remote_rider = 0


# --- Clients using the host's creatures (shears, dye, saddle, bucket, bone, coal) -----------------

## Client -> host: RMB on the host's creature `id` with the item in hand.
func send_interact(id: int) -> void:
	var player := _game_player()
	if player == null:
		return
	var slot := player.selected_slot
	var held := PackedInt32Array([player.inventory.id_at(slot), player.inventory.count_at(slot), player.inventory.damage_at(slot)])
	_client_interact.rpc_id(1, id, held, player.vehicle != null)


@rpc("any_peer", "call_remote", "reliable")
func _client_interact(id: int, held: PackedInt32Array, riding: bool) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var world := _world()
	var avatar := _avatar_of(peer)
	if world == null or avatar == null or avatar.dead or held.size() != 3 or not _within(peer, "edit", EDIT_LIMIT, 1.0):
		return
	var entity := world.entities.by_net_id(id)
	if entity == null or not entity.has_method("interact") or entity.center().distance_to(avatar.target_position) > 7.0:
		return
	if not NetGuard.valid_stack(held[0], held[1], held[2]):
		_strike(peer, "impossible item in hand", 3)
		return
	var proxy := NetPlayerProxy.new(held, is_creative(peer), riding, avatar.target_position)
	if not entity.call("interact", proxy, proxy.inventory.id_at(0)):
		return
	var mounted := 0
	if proxy.mounted and proxy.mounted.seat_free():
		proxy.mounted.remote_rider = peer
		mounted = proxy.mounted.net_id
	var inventory := proxy.inventory
	_interacted.rpc_id(peer, PackedInt32Array([held[0], held[1], held[2],
		inventory.id_at(0), inventory.count_at(0), inventory.damage_at(0),
		inventory.id_at(1), inventory.count_at(1), inventory.damage_at(1)]), mounted)


## Client: what the creature did to the item in hand (before -> after, and
## anything more it got), and the creature it got on.
@rpc("authority", "call_remote", "reliable")
func _interacted(slots: PackedInt32Array, mounted: int) -> void:
	var player := _game_player()
	if player == null or slots.size() != 9:
		return
	var inventory := player.inventory
	var slot := player.selected_slot
	if inventory.id_at(slot) == slots[0] and inventory.count_at(slot) == slots[1]:
		inventory.set_slot(slot, slots[3], slots[4], slots[5])
	if slots[6] != Blocks.AIR and slots[7] > 0:
		var left := inventory.add(slots[6], slots[7], slots[8])
		if left > 0:
			player.throw_items(slots[6], left, slots[8])
	player.swing()
	if mounted != 0:
		_mounted(mounted)


## Client -> host: RMB on a jukebox with the item in hand (a disc goes in,
## or the one inside comes out).
func send_jukebox(pos: Vector3i) -> void:
	var player := _game_player()
	if player == null:
		return
	var slot := player.selected_slot
	var held := PackedInt32Array([player.inventory.id_at(slot), player.inventory.count_at(slot), player.inventory.damage_at(slot)])
	_client_jukebox.rpc_id(1, pos, held)


@rpc("any_peer", "call_remote", "reliable")
func _client_jukebox(pos: Vector3i, held: PackedInt32Array) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var world := _world()
	var avatar := _avatar_of(peer)
	if world == null or avatar == null or held.size() != 3 or not _within(peer, "edit", EDIT_LIMIT, 1.0):
		return
	if not NetGuard.in_world_i(pos) or Blocks.family_of(world.get_block(pos)) != "jukebox" \
			or Vector3(pos).distance_to(avatar.target_position) > CONTAINER_REACH:
		return
	if not NetGuard.valid_stack(held[0], held[1], held[2]):
		_strike(peer, "impossible item in hand", 3)
		return
	var proxy := NetPlayerProxy.new(held, is_creative(peer), false, avatar.target_position)
	if MusicBehavior.use_jukebox(world, pos, proxy, proxy.inventory.id_at(0)):
		var inventory := proxy.inventory
		_interacted.rpc_id(peer, PackedInt32Array([held[0], held[1], held[2],
			inventory.id_at(0), inventory.count_at(0), inventory.damage_at(0), Blocks.AIR, 0, 0]), 0)


## Host: a jukebox started (`track`) or stopped ("") playing: for everyone.
func record_changed(pos: Vector3i, track: String) -> void:
	if _has_clients():
		_record.rpc(pos, track)


@rpc("authority", "call_remote", "reliable")
func _record(pos: Vector3i, track: String) -> void:
	var world := _world()
	if world == null:
		return
	if track == "":
		MusicBehavior.stop_record(world, pos)
	elif track.is_valid_filename() and not track.contains("/"):
		MusicBehavior.play_record(world, pos, track)


## Host: whether every player sleeps (the night passes only then, like the
## game's servers); the dead don't count.
func all_asleep() -> bool:
	for avatar: RemotePlayer in avatars.values():
		if is_instance_valid(avatar) and not avatar.dead and not avatar.is_sleeping():
			return false
	return true


# --- Players hurting players (and creatures hurting clients) -------------------------------------

## Hurts the player of `peer` (the host's creatures, another player's hit;
## a client's hits go through the host).
func hurt_peer(peer: int, amount: int, from: Vector3) -> void:
	if peer == multiplayer.get_unique_id():
		var player := _game_player()
		if player:
			if amount > 0:
				player.damage(amount)
			if from != Vector3.INF:
				player.knockback(from)
		return
	if is_host():
		_hurt.rpc_id(peer, amount, from)
	elif is_client():
		_client_hurt.rpc_id(1, peer, amount, from != Vector3.INF)


## Client -> host: its player hit the player of `target` (`amount`, and
## pushed it away with `knock`). The host checks pvp, the reach and the
## weapon, and hurts it from where it sees the attacker.
@rpc("any_peer", "call_remote", "reliable")
func _client_hurt(target: int, amount: int, knock: bool) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not _within(peer, "attack", ATTACK_LIMIT, 1.0) or not pvp or target == peer:
		return
	if not (_joined(target) or (target == 1 and not dedicated)):
		return
	var attacker := _avatar_of(peer)
	var at := _position_of(target)
	if attacker == null or attacker.dead or at == Vector3.INF:
		return
	var from := attacker.target_position
	if (at + Vector3(0, 0.9, 0)).distance_to(from + Vector3(0, Player.EYE_HEIGHT, 0)) > REACH_SURVIVAL + 1.0:
		_strike(peer, "hit a player out of reach", 0)
		return
	_active[peer] = Time.get_ticks_msec() / 1000.0
	hurt_peer(target, clampi(amount, 0, _max_hit(peer)), from if knock else Vector3.INF)


## Host -> client: its player is hurt (and pushed away from `from`).
@rpc("authority", "call_remote", "reliable")
func _hurt(amount: int, from: Vector3) -> void:
	var player := _game_player()
	if player == null:
		return
	if amount > 0:
		player.damage(mini(amount, 20))
	if from != Vector3.INF and from.is_finite():
		player.knockback(from)


# --- Dropped items: through the host ----------------------------------------------------------------

## Client -> host: an item dropped or thrown here.
func send_item(id: int, count: int, position: Vector3, velocity: Vector3, damage: int, delay: int) -> void:
	_client_item.rpc_id(1, id, count, position, velocity, damage, delay)


@rpc("any_peer", "call_remote", "reliable")
func _client_item(id: int, count: int, position: Vector3, velocity: Vector3, damage: int, delay: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var world := _world()
	if world == null or not _within(peer, "drop", DROP_LIMIT, 1.0):
		return
	if id == Blocks.AIR or not NetGuard.valid_stack(id, count, damage):
		_strike(peer, "dropping an impossible item (%d x%d)" % [id, count], 3)
		return
	if not is_creative(peer) and id < Blocks.count() and NetGuard.survival_forbidden(id):
		_strike(peer, "dropping %s in survival" % Blocks.get_type(id).name, 2)
		return
	var eye := _position_of(peer) + Vector3(0, Player.EYE_HEIGHT, 0)
	if not eye.is_finite():
		return
	if not position.is_finite() or position.distance_to(eye) > 4.0:
		position = eye # (from its eyes, not wherever it said)
	velocity = velocity.limit_length(1.5) if velocity.is_finite() else Vector3.ZERO
	world.items.spawn(id, count, position, velocity, clampi(delay, 0, 200), damage)


## Client -> host: pick up the host's item `nid` (it walked over it).
func send_pickup(nid: int) -> void:
	_client_pickup.rpc_id(1, nid)


@rpc("any_peer", "call_remote", "reliable")
func _client_pickup(nid: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var world := _world()
	var avatar := _avatar_of(peer)
	if world == null or avatar == null or avatar.dead or not _within(peer, "pickup", 200, 1.0):
		return
	var taken: Array = world.items.take_for_network(nid, avatar.target_position)
	if not taken.is_empty():
		_give.rpc_id(peer, taken[0], taken[1], taken[2])


@rpc("authority", "call_remote", "reliable")
func _give(id: int, count: int, damage: int) -> void:
	var player := _game_player()
	if player == null or not NetGuard.valid_stack(id, count, damage) or id == Blocks.AIR:
		return
	var left := player.inventory.add(id, count, damage)
	Sounds.play("random/pop", null, 0.2, ((randf() - randf()) * 0.7 + 1.0) * 2.0)
	if left > 0: # (no room after all: back on the ground)
		send_item(id, left, player.global_position + Vector3(0, 1, 0), Vector3.ZERO, damage, 40)


## Host -> client: takes back items it got from a container slot another
## player had emptied first (the cursor first, then the inventory).
@rpc("authority", "call_remote", "reliable")
func _take_back(id: int, count: int) -> void:
	var player := _game_player()
	if player == null or count <= 0:
		return
	var screen := _inventory_screen()
	if screen:
		count -= screen.take_from_cursor(id, count)
	var inventory := player.inventory
	for slot in inventory.size():
		if count <= 0:
			break
		if inventory.id_at(slot) == id:
			var taken := mini(count, inventory.count_at(slot))
			inventory.take(slot, taken)
			count -= taken


# --- Clients' players kept by the host ------------------------------------------------------------

## Client -> host: this player as it is now (every 10 s and on leaving).
func send_player_state() -> void:
	var player := _game_player()
	if player == null or not is_client() or multiplayer.multiplayer_peer == null:
		return
	_client_player_state.rpc_id(1, player.save_state())


@rpc("any_peer", "call_remote", "reliable")
func _client_player_state(state: Dictionary) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not is_host() or not _tags.has(peer) or not players.has(peer):
		return
	# (A kicked player's last state still counts: it is sent on leaving.)
	if not _dropping.has(peer) and not _within(peer, "save", 6, 10.0):
		return
	var clean := NetGuard.clean_player_state(state, _position_of(peer))
	if clean.is_empty():
		_strike(peer, "player state too big", 3)
		return
	var tag: String = _tags[peer]
	if int(_modes.get(peer, lan_game_mode)) != lan_game_mode:
		clean["game_mode"] = _modes[peer]
	saved_players[tag] = clean


# --- Cheats ----------------------------------------------------------------------------------

## Whether commands needing cheats may run here: the network game's choice
## when online (a client: whether the host lets it), else the world's
## ("Allow Cheats").
func cheats_allowed() -> bool:
	if is_online():
		return cheats
	return WorldSave.current == null or WorldSave.current.allow_cheats


## Client -> host: a world command (HOST_COMMANDS) typed by this player.
func send_command(text: String) -> void:
	_client_command.rpc_id(1, text.left(1024))


@rpc("any_peer", "call_remote", "reliable")
func _client_command(text: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var world := _world()
	if world == null or not _within(peer, "chat", CHAT_LIMIT, 5.0):
		return
	text = NetGuard.clean_text(text, 1024)
	var root := text.trim_prefix("/").get_slice(" ", 0).to_lower()
	if not root in HOST_COMMANDS:
		return
	var allowed := can_cheat(peer) or root in FREE_COMMANDS
	if root in OP_COMMANDS or (not is_op(peer) and _runs_op_command(text)):
		allowed = is_op(peer)
	var who: String = players[peer].name
	if not allowed:
		log_event("%s tried the command: %s" % [who, text])
		_command_output.rpc_id(peer, Lang.t("You don't have permission to use this command"), CommandSource.MessageKind.ERROR)
		return
	log_event("%s issued the command: %s" % [who, text])
	_active[peer] = Time.get_ticks_msec() / 1000.0
	var source := CommandSource.new()
	source.name = who
	source.world = world
	source.origin = _avatar_of(peer) # ~ ~ ~ are where that player is
	source.output = func(message: String, kind: int) -> void: _command_output.rpc_id(peer, message, kind)
	Commands.dispatcher.execute(text, source)


## Whether a command runs an op's command inside (/execute ... run kick).
static func _runs_op_command(text: String) -> bool:
	var words := text.to_lower().split(" ", false)
	for i in words.size() - 1:
		if words[i] == "run" and words[i + 1].trim_prefix("/") in OP_COMMANDS:
			return true
	return false


@rpc("authority", "call_remote", "reliable")
func _command_output(text: String, kind: int) -> void:
	var chat := _chat()
	if chat:
		chat.add_message(text.left(4096), clampi(kind, 0, CommandSource.MessageKind.size() - 1))

# --- Containers: chests, furnaces and dispensers are the host's -------------------------------------
# A client asks the host to open one (both halves of a large chest); the host
# sends what is inside, and the client opens its window on its own copy of
# the block entities (VoxelWorld.block_entity). Then both sides send only
# the slots that changed: the client what its player moved, the host
# (10 times a second) what changed there (its player, the furnace, a
# dispenser firing, another client) and the furnace's fire and arrow.
# A client's change to a slot that changed on the host since the client saw
# it is merged when it is more or less of the same item (a furnace's output
# growing while it is taken) and otherwise undone on both sides: the host
# keeps its slot and takes back from the client what it got (_take_back) and
# gives back what it put in (_give). So two players can't take one stack.

const CONTAINER_SECONDS := 0.1
const CONTAINER_REACH := 8.0
# A container's key: its block's position (Vector3i) or a chest minecart's
# net id (int).
## Host: key -> {peer: [slots sent (PackedInt32Array), furnace numbers]}.
var _viewers := {}
var _container_timer := 0.0
## Client: the keys open and their slots as last agreed with the host.
var _open_containers: Array = []
var _container_slots := {}
var _applying_container := false


## A container's slots as one array: ids, counts, damages.
static func _slots_of(inventory: Inventory) -> PackedInt32Array:
	var result := PackedInt32Array()
	for slot in inventory.size():
		result.append_array(PackedInt32Array([inventory.id_at(slot), inventory.count_at(slot), inventory.damage_at(slot)]))
	return result


## The slots of `now` that differ from `before`: [slot, id, count, damage]...
static func _slot_changes(before: PackedInt32Array, now: PackedInt32Array) -> PackedInt32Array:
	var result := PackedInt32Array()
	for slot in now.size() / 3:
		var i := slot * 3
		if before.size() <= i + 2 or before[i] != now[i] or before[i + 1] != now[i + 1] or before[i + 2] != now[i + 2]:
			result.append_array(PackedInt32Array([slot, now[i], now[i + 1], now[i + 2]]))
	return result


static func _furnace_numbers(entity: Dictionary) -> PackedInt32Array:
	if entity.get("type", "") != "furnace":
		return PackedInt32Array()
	return PackedInt32Array([entity.burn, entity.burn_total, entity.cook])


## The block entity with an inventory at a key (chest, furnace, dispenser),
## a chest minecart's chest, or {}.
func _container_at(world: VoxelWorld, key: Variant) -> Dictionary:
	if world == null:
		return {}
	if key is int:
		var cart: Entity = world.entities.by_net_id(key) if is_host() else _puppets.get(key)
		if cart and is_instance_valid(cart) and not cart.removed and cart is Minecart and (cart as Minecart).inventory:
			return {"type": "chest", "inventory": (cart as Minecart).inventory}
		return {}
	if not key is Vector3i:
		return {}
	var entity := world.block_entity(key)
	return entity if entity.has("inventory") else {}


## Where a container is (to check a player's reach).
func _container_center(world: VoxelWorld, key: Variant) -> Vector3:
	if key is int:
		var cart: Entity = world.entities.by_net_id(key)
		return cart.center() if cart else Vector3.INF
	return Vector3(key as Vector3i) + Vector3(0.5, 0.5, 0.5)


## Client: open the chest minecart `id` of the host.
func open_cart_container(id: int) -> void:
	_client_open_cart.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func _client_open_cart(id: int) -> void:
	_open_for(multiplayer.get_remote_sender_id(), [id])


## Client: open the container(s) at `positions` (a large chest: left, right).
func open_container(positions: Array[Vector3i]) -> void:
	var packed := PackedInt32Array()
	for pos in positions:
		packed.append_array(PackedInt32Array([pos.x, pos.y, pos.z]))
	_client_open.rpc_id(1, packed)


@rpc("any_peer", "call_remote", "reliable")
func _client_open(packed: PackedInt32Array) -> void:
	if packed.size() not in [3, 6]:
		_strike(multiplayer.get_remote_sender_id(), "opening %d numbers" % packed.size(), 3)
		return
	var keys := []
	for i in range(0, packed.size(), 3):
		var pos := Vector3i(packed[i], packed[i + 1], packed[i + 2])
		if not NetGuard.in_world_i(pos):
			return
		keys.append(pos)
	_open_for(multiplayer.get_remote_sender_id(), keys)


## Host: a client opens the containers `keys` (one, or a large chest's halves).
func _open_for(peer: int, keys: Array) -> void:
	var world := _world()
	var avatar := _avatar_of(peer)
	if world == null or avatar == null or avatar.dead or not _within(peer, "edit", EDIT_LIMIT, 1.0):
		return
	_close_for(peer)
	var states := []
	for key: Variant in keys:
		if _container_center(world, key).distance_to(avatar.target_position) > CONTAINER_REACH:
			return
		if key is Vector3i and ChestBehavior.blocked(world, key):
			return
		if key is Vector3i and Blocks.family_of(world.get_block(key)) == "dungeon_chest":
			DungeonBehavior.open_chest(world, key) # its loot appears now
		var entity := _container_at(world, key)
		if entity.is_empty() or (keys.size() == 2 and entity.type != "chest"):
			return
		states.append([key, _slots_of(entity.inventory), _furnace_numbers(entity)])
	for state: Array in states:
		var key: Variant = state[0]
		if not _viewers.has(key):
			_viewers[key] = {}
		_viewers[key][peer] = [state[1], state[2]]
	_active[peer] = Time.get_ticks_msec() / 1000.0
	_container_opened.rpc_id(peer, states)


## Client: the host's contents; the window opens on them.
@rpc("authority", "call_remote", "reliable")
func _container_opened(states: Array) -> void:
	var world := _world()
	var screen := _inventory_screen()
	if world == null or screen == null or screen.is_open():
		_client_close.rpc_id(1)
		return
	var entities: Array[Dictionary] = []
	_open_containers.clear()
	_container_slots.clear()
	for state: Array in states:
		var pos: Variant = state[0]
		var entity := _container_at(world, pos)
		if entity.is_empty():
			_client_close.rpc_id(1)
			return
		_set_container(pos, entity, state[1], state[2])
		entities.append(entity)
		_open_containers.append(pos)
		(entity.inventory as Inventory).changed.connect(_container_changed.bind(pos))
	if entities.size() == 2:
		screen.open_large_chest(entities[0], entities[1])
	else:
		screen.open_container(entities[0])
	if screen.is_open() and _open_containers[0] is Vector3i and ChestBehavior.is_chest(world.get_block(_open_containers[0])):
		world.chest_lids.hold(_open_containers.duplicate(), screen)
	screen.closed.connect(_container_screen_closed, CONNECT_ONE_SHOT)


func _inventory_screen() -> InventoryScreen:
	var screens := get_tree().root.find_children("*", "InventoryScreen", true, false)
	return screens[0] as InventoryScreen if not screens.is_empty() else null


## Client: the host's slots (all, or changes) and furnace numbers.
func _set_container(pos: Variant, entity: Dictionary, slots: PackedInt32Array, furnace: PackedInt32Array, changes := false) -> void:
	var inventory: Inventory = entity.inventory
	var known: PackedInt32Array = _container_slots.get(pos, _slots_of(inventory))
	_applying_container = true
	if changes:
		for i in range(0, slots.size() - 3, 4):
			var slot := slots[i]
			if slot >= 0 and slot < inventory.size():
				inventory.set_slot(slot, slots[i + 1], slots[i + 2], slots[i + 3])
	else:
		for slot in mini(inventory.size(), slots.size() / 3):
			inventory.set_slot(slot, slots[slot * 3], slots[slot * 3 + 1], slots[slot * 3 + 2])
	_applying_container = false
	known = _slots_of(inventory)
	_container_slots[pos] = known
	if furnace.size() == 3 and entity.type == "furnace":
		entity.burn = furnace[0]
		entity.burn_total = furnace[1]
		entity.cook = furnace[2] # (the window draws them every frame)


## Client: its player moved items in an open container: the slots go to the host.
func _container_changed(pos: Variant) -> void:
	if _applying_container or not _open_containers.has(pos):
		return
	var entity := _container_at(_world(), pos)
	if entity.is_empty():
		return
	var now := _slots_of(entity.inventory)
	var changes := _slot_changes(_container_slots.get(pos, PackedInt32Array()), now)
	_container_slots[pos] = now
	if not changes.is_empty():
		_client_container_slots.rpc_id(1, pos, changes)


@rpc("any_peer", "call_remote", "reliable")
func _client_container_slots(pos: Variant, changes: PackedInt32Array) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var world := _world()
	if world == null or not _within(peer, "container", 200, 1.0):
		return
	if not (pos is Vector3i or pos is int) or not _viewers.has(pos) or not (_viewers[pos] as Dictionary).has(peer):
		return
	var entity := _container_at(world, pos)
	var inventory: Inventory = entity.get("inventory")
	if entity.is_empty() or changes.size() % 4 != 0 or changes.size() > inventory.size() * 4:
		_strike(peer, "bad container change", 2)
		return
	var creative := is_creative(peer)
	var agreed: PackedInt32Array = (_viewers[pos][peer][0] as PackedInt32Array).duplicate()
	var stale := {} # slots the client must be told again
	for i in range(0, changes.size(), 4):
		var slot := changes[i]
		var id := changes[i + 1]
		var count := changes[i + 2]
		var damage := changes[i + 3]
		if slot < 0 or slot >= inventory.size() or not NetGuard.valid_stack(id, count, damage):
			_strike(peer, "impossible container slot (%d: %d x%d)" % [slot, id, count], 3)
			continue
		if not creative and id < Blocks.count() and NetGuard.survival_forbidden(id):
			_strike(peer, "putting %s in a container in survival" % Blocks.get_type(id).name, 2)
			stale[slot] = true
			continue
		var k := slot * 3
		var before := PackedInt32Array([agreed[k], agreed[k + 1], agreed[k + 2]]) if agreed.size() > k + 2 else PackedInt32Array([0, 0, 0])
		var current := PackedInt32Array([inventory.id_at(slot), inventory.count_at(slot), inventory.damage_at(slot)])
		if current == before:
			inventory.set_slot(slot, id, count, damage)
			continue
		# Changed here meanwhile: more or less of the same item merges ...
		if before[0] == current[0] and (id == current[0] or count == 0) and before[0] != Blocks.AIR:
			var merged := current[1] + (count - before[1])
			if merged >= 0 and merged <= Items.max_stack(current[0]):
				inventory.set_slot(slot, current[0], merged, current[2])
				stale[slot] = true
				continue
			if merged < 0:
				# It took more than is left: the rest goes back.
				inventory.set_slot(slot, Blocks.AIR, 0)
				_take_back.rpc_id(peer, before[0], -merged)
				stale[slot] = true
				continue
		# ... anything else is undone: the client gives back what it took
		# and gets back what it put in.
		if before[0] != Blocks.AIR and before[1] > 0:
			_take_back.rpc_id(peer, before[0], before[1])
		if id != Blocks.AIR and count > 0:
			_give.rpc_id(peer, id, count, damage)
		stale[slot] = true
	# What this client has now (the stale slots as it thinks they are, so the
	# next round sends it the real ones); the others get it with the next
	# round too.
	var known := _slots_of(inventory)
	for i in range(0, changes.size(), 4):
		var slot := changes[i]
		if stale.has(slot) and slot >= 0 and slot * 3 + 2 < known.size():
			known[slot * 3] = changes[i + 1]
			known[slot * 3 + 1] = changes[i + 2]
			known[slot * 3 + 2] = changes[i + 3]
	_viewers[pos][peer][0] = known


## Client: the window closed (its player, or the host's _container_closed).
func _container_screen_closed() -> void:
	var world := _world()
	for pos in _open_containers:
		var entity := _container_at(world, pos) if world else {}
		if not entity.is_empty() and (entity.inventory as Inventory).changed.is_connected(_container_changed):
			(entity.inventory as Inventory).changed.disconnect(_container_changed)
	_open_containers.clear()
	_container_slots.clear()
	if is_client():
		_client_close.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _client_close() -> void:
	if is_host():
		_close_for(multiplayer.get_remote_sender_id())


## Host: the chests the clients have open (ChestLids: their lids open).
func viewed_chests() -> Array:
	if not is_host():
		return []
	return _viewers.keys().filter(func(key: Variant) -> bool: return key is Vector3i)


## Host: which chests are open (any player's), sent when it changes so
## everyone sees their lids open (ChestLids).
var _lids_sent := PackedInt32Array()
var _lid_timer := 0.0


func _send_chest_lids() -> void:
	var world := _world()
	if world == null:
		return
	var packed := PackedInt32Array()
	for cell in world.chest_lids.open_cells():
		packed.append_array(PackedInt32Array([cell.x, cell.y, cell.z]))
	if packed != _lids_sent:
		_lids_sent = packed
		_chest_lids.rpc(packed)


@rpc("authority", "call_remote", "reliable")
func _chest_lids(packed: PackedInt32Array) -> void:
	var world := _world()
	if world == null or packed.size() % 3 != 0:
		return
	var cells: Array[Vector3i] = []
	for i in range(0, packed.size(), 3):
		cells.append(Vector3i(packed[i], packed[i + 1], packed[i + 2]))
	world.chest_lids.set_remote(cells)


func _close_for(peer: int) -> void:
	for pos: Variant in _viewers.keys():
		(_viewers[pos] as Dictionary).erase(peer)
		if (_viewers[pos] as Dictionary).is_empty():
			_viewers.erase(pos)


## Host: what changed in the containers clients look into goes to them.
func _send_container_changes() -> void:
	var world := _world()
	for pos: Variant in _viewers.keys():
		var entity := _container_at(world, pos)
		var viewers: Dictionary = _viewers[pos]
		if entity.is_empty():
			for peer: int in viewers:
				_container_closed.rpc_id(peer) # broken
			_viewers.erase(pos)
			continue
		var now := _slots_of(entity.inventory)
		var furnace := _furnace_numbers(entity)
		for peer: int in viewers:
			var sent: Array = viewers[peer]
			var changes := _slot_changes(sent[0], now)
			var furnace_changed: bool = furnace != (sent[1] as PackedInt32Array)
			if changes.is_empty() and not furnace_changed:
				continue
			_container_update.rpc_id(peer, pos, changes, furnace if furnace_changed else PackedInt32Array())
			viewers[peer] = [now, furnace]


@rpc("authority", "call_remote", "reliable")
func _container_update(pos: Variant, changes: PackedInt32Array, furnace: PackedInt32Array) -> void:
	var world := _world()
	if world == null or not _open_containers.has(pos):
		return
	var entity := _container_at(world, pos)
	if not entity.is_empty():
		_set_container(pos, entity, changes, furnace, true)


@rpc("authority", "call_remote", "reliable")
func _container_closed() -> void:
	var screen := _inventory_screen()
	if screen and screen.is_open() and not _open_containers.is_empty():
		screen.close()
