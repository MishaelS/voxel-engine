extends Node
## Autoload: multiplayer (stage 15), the classic game's way: a player opens
## their world to the network from the pause menu ("Open to LAN") and is the
## host; others join by address or from the list of games on the local
## network. Godot's high-level multiplayer over ENet.
##
## The host runs the world: liquids, growth, redstone, ticks and saving. A
## client draws it and moves its own player:
## - columns: a client generates the ones nobody has changed itself (the
##   generators are deterministic, the same blocks from the same seed); the
##   host sends the changed ones (compressed). Then every block change is
##   sent to the clients in batches, a tick at a time;
## - a client's edits (breaking, placing, buckets...) show at once and go to
##   the host, which makes them with all their effects; using levers,
##   buttons, doors and trapdoors is done by the host;
## - players see each other (RemotePlayer: the player model with the skin,
##   walking, sneaking, swinging, the item in hand, the name above);
## - chat, the time of day and the weather are shared.
## - creatures, boats, minecarts, arrows, TNT and paintings are the host's:
##   10 times a second each client gets the ones within 96 blocks (new ones
##   with their whole state) and moves its copies ("puppets") along; what a
##   client makes (an arrow shot, a boat put down) the host makes. A client
##   hits them, rides the host's boats and minecarts (steering them) through
##   the host. Creatures go after any player; players hurt each other;
## - dropped items too: each client sees the ones within 48 blocks, drops
##   and throws through the host and picks them up with its leave;
## - the host keeps each client's player (where it was, inventory, armor,
##   health) by its tag in the world's save, and gives it back on joining.
## Chests, furnaces, dispensers and signs are the next step.
##
## Telling players apart and keeping bots out (the host): a joining player
## is asked to prove who it is with this server's salt and answers with its
## tag (PlayerProfile.tag_for_server: a hash of its computer's hashed id and
## the salt; the same on this server, different on others, nothing about
## the computer in it). The host bans by tag (user://bans.cfg), allows 3
## connections and 5 tries in 30 s from one address, drops a connection that
## doesn't introduce itself within 5 s and kicks players flooding the chat,
## edits or column requests. Commands: /players, /kick, /ban,
## /pardon. (A changed client can fake its tag: this stops casual bots and
## spam, not a determined attacker or a flood at the network level.)

signal players_changed
signal lan_games_changed

enum Mode { OFFLINE, HOST, CLIENT }

const PORT := 25565
const LAN_PORT := 4445
const LAN_SEND_SECONDS := 1.5
const LAN_FORGET_SECONDS := 5.0
const MAX_PLAYERS := 8
const CONFIG_PATH := "user://multiplayer.cfg"
## Seconds between the host's time and weather messages.
const SYNC_SECONDS := 1.0
## Player state messages a second (each tick).
const STATE_RATE := 20.0
const SERVER_CONFIG := "user://server.cfg"
const BANS_PATH := "user://bans.cfg"
## Joining limits per address, the time to introduce oneself, flood limits.
const MAX_PER_ADDRESS := 3
const MAX_TRIES := 5
const TRIES_SECONDS := 30.0
const HELLO_SECONDS := 5.0
const CHAT_LIMIT := 8      # lines per 5 seconds
const EDIT_LIMIT := 80     # edits and uses per second
const COLUMN_LIMIT := 400  # column requests per second

var mode := Mode.OFFLINE
## A network game's "Allow Cheats" (the host chooses on opening; clients get
## it on joining) and the game mode new players get.
var cheats := false
var lan_game_mode := 0
## Commands that need cheats and change the world: a client's run on the
## host (Commands not listed here run on the player's own side).
const HOST_COMMANDS: Array[String] = ["time", "weather", "gamerule", "tick", "setblock", "fill"]
## Commands always allowed (no cheats needed).
const FREE_COMMANDS: Array[String] = ["help", "seed", "say", "players", "kick", "ban", "pardon"]
var player_name := ""
var last_address := "127.0.0.1"
## Peer id -> {"name": String, "ping": ms (-1 unknown)}, everyone in the
## game (this one too); the host measures the pings and sends them each
## second (the Tab list).
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
## Why the last connection ended ("" if it did not fail).
var last_error := ""

var _peer: ENetMultiplayerPeer
var _lan_out: PacketPeerUDP
var _lan_in: PacketPeerUDP
var _lan_timer := 0.0
var _sync_timer := 0.0
var _state_timer := 0.0
var _pending_blocks := PackedInt32Array()
## Client: columns asked for -> true; answers: column -> PackedInt32Array
## (the host's blocks) or empty (generate it); block changes waiting for a
## column that is on its way.
var _asked := {}
var _answers := {}
var _waiting_changes := {}
var _swings := 0
## Host: peer id -> address, the tags of the players in (peer id -> tag),
## joins waiting to introduce themselves (peer id -> deadline), tries by
## address (address -> [times]), counters for the flood limits.
var _addresses := {}
var _tags := {}
var _waiting_hello := {}
var _tries := {}
var _counters := {}
var _server_salt := ""
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
	var config := ConfigFile.new()
	config.set_value("player", "name", player_name)
	config.set_value("player", "address", last_address)
	config.save(CONFIG_PATH)


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


# --- Hosting and joining -------------------------------------------------------------

## Opens the world being played to the network. Returns an error text, or "".
func host(port: int = PORT) -> String:
	if is_online():
		return "Already open"
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		_peer = null
		return "Can't open port %d" % port
	multiplayer.multiplayer_peer = _peer
	mode = Mode.HOST
	players = {1: {"name": player_name}}
	var world := _world()
	saved_players = world.save.state.get("net_players", {}) if world and world.save else {}
	looks = {1: _own_look()}
	_lan_out = PacketPeerUDP.new()
	_lan_out.set_broadcast_enabled(true)
	_lan_out.set_dest_address("255.255.255.255", LAN_PORT)
	players_changed.emit()
	return ""


## Connects to a host ("address" or "address:port"). The game starts when the
## host answers (welcome).
func join(address: String) -> String:
	leave()
	var host_name := address.strip_edges()
	var port := PORT
	if host_name.contains(":"):
		port = int(host_name.get_slice(":", 1))
		host_name = host_name.get_slice(":", 0)
	if host_name == "":
		return "No address"
	last_address = address.strip_edges()
	save_config()
	_peer = ENetMultiplayerPeer.new()
	if _peer.create_client(host_name, port) != OK:
		_peer = null
		return "Can't connect to %s" % address
	multiplayer.multiplayer_peer = _peer
	mode = Mode.CLIENT
	last_error = ""
	return ""


## Leaves the game or stops hosting.
func leave() -> void:
	if is_client():
		send_player_state() # (the host keeps this player)
	if _peer:
		_peer.close()
	_peer = null
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
	world_info.clear()
	_lan_out = null
	players_changed.emit()


func _on_peer_connected(id: int) -> void:
	if not is_host():
		return
	var address := _peer.get_peer(id).get_remote_address() if _peer.get_peer(id) else ""
	var now := Time.get_ticks_msec() / 1000.0
	var tries: Array = _tries.get(address, []).filter(func(t: float) -> bool: return now - t < TRIES_SECONDS)
	tries.append(now)
	_tries[address] = tries
	var same_address := _addresses.values().count(address)
	if tries.size() > MAX_TRIES or same_address >= MAX_PER_ADDRESS:
		_drop(id, "Too many connections from your address")
		return
	_addresses[id] = address
	_waiting_hello[id] = now + HELLO_SECONDS
	_challenge.rpc_id(id, _salt())


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


## Host -> joining client: "prove who you are with this salt".
@rpc("authority", "call_remote", "reliable")
func _challenge(salt: String) -> void:
	_hello.rpc_id(1, player_name, str(ProjectSettings.get_setting("application/config/version", "dev")),
		PlayerProfile.tag_for_server(salt))
	send_look()


## Host: tells a peer why and closes its connection a moment later (so the
## reason arrives).
func _drop(id: int, reason: String) -> void:
	_refused.rpc_id(id, reason)
	_waiting_hello.erase(id)
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		if _peer and _peer.get_peer(id):
			_peer.disconnect_peer(id))


## Host: whether a peer stays under a flood limit (`limit` in `seconds`);
## kicked if not.
func _within(id: int, kind: String, limit: int, seconds: float) -> bool:
	if not players.has(id):
		return false # not introduced: ignored
	var now := Time.get_ticks_msec() / 1000.0
	var key := "%d/%s" % [id, kind]
	var entry: Array = _counters.get(key, [now, 0])
	if now - float(entry[0]) > seconds:
		entry = [now, 0]
	entry[1] = int(entry[1]) + 1
	_counters[key] = entry
	if int(entry[1]) > limit:
		_drop(id, "Kicked for spamming")
		return false
	return true


func _on_peer_disconnected(id: int) -> void:
	_waiting_hello.erase(id)
	_known_entities.erase(id)
	_known_items.erase(id)
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
	if avatars.has(id):
		(avatars[id] as Node).queue_free()
		avatars.erase(id)
	_message("%s left the game" % left_name)
	if is_host():
		_send_players.rpc(players)
	players_changed.emit()


func _on_connected() -> void:
	pass # the host asks to introduce (_challenge)


func _on_connection_failed() -> void:
	last_error = "Could not connect"
	leave()
	players_changed.emit()


func _on_server_disconnected() -> void:
	last_error = "The host left the game"
	leave()
	var game := Game.find(get_tree())
	if game:
		game.quit_to_title()


## Client -> host: who is joining.
@rpc("any_peer", "call_remote", "reliable")
func _hello(joining_name: String, version: String, tag: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if not _waiting_hello.has(id) or players.has(id):
		return
	_waiting_hello.erase(id)
	var game_version := str(ProjectSettings.get_setting("application/config/version", "dev"))
	if version != game_version:
		_drop(id, "The host plays version %s" % game_version)
		return
	if tag.length() != 64 or not tag.is_valid_hex_number():
		_drop(id, "Could not connect")
		return
	if is_banned(tag):
		_drop(id, "You are banned from this server")
		return
	joining_name = joining_name.strip_edges().left(16)
	if joining_name == "":
		joining_name = "Player"
	_tags[id] = tag
	var world := _world()
	var host_player := _game_player()
	if world == null or host_player == null:
		_drop(id, "The host is not in a world")
		return
	var taken := false
	for peer: int in players:
		taken = taken or players[peer].name == joining_name
	var unique_name := joining_name if not taken else "%s%d" % [joining_name, id % 100]
	players[id] = {"name": unique_name}
	var save := world.save
	_welcome.rpc_id(id, {
		"name": save.name if save else "World", "seed": world.world_seed, "generator": world.generator,
		"tall": save.tall_terrain if save else true, "game_mode": lan_game_mode, "cheats": cheats,
		"spawn": world.find_spawn(), # the world spawn (not the host's bed)
		"game_time": world.clock.game_time, "day_time": world.clock.day_time,
		"your_name": unique_name, "player": saved_players.get(tag, {}),
	})
	_send_players.rpc(players)
	# How everyone already here looks.
	for peer: int in looks:
		_look.rpc_id(id, peer, looks[peer].color, looks[peer].png)
	_message("%s joined the game" % unique_name)
	_joined_message.rpc("%s joined the game" % unique_name)
	players_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _refused(reason: String) -> void:
	last_error = reason
	var in_game := Game.find(get_tree()) != null
	leave()
	players_changed.emit()
	if in_game:
		Game.find(get_tree()).quit_to_title() # kicked or banned while playing


## Host -> client: the world to play; the client loads it (Game).
@rpc("authority", "call_remote", "reliable")
func _welcome(info: Dictionary) -> void:
	world_info = info
	player_name = info.get("your_name", player_name)
	cheats = bool(info.get("cheats", false))
	var save := WorldSave.new()
	save.remote = true
	save.name = info.get("name", "World")
	save.world_seed = info.get("seed", 0)
	save.generator = info.get("generator", 0)
	save.tall_terrain = info.get("tall", true)
	save.game_mode = info.get("game_mode", 0)
	var saved_player: Dictionary = info.get("player", {})
	save.state = {"player": saved_player if not saved_player.is_empty() else {"position": info.get("spawn", Vector3(8, 140, 8))}}
	WorldSave.current = save
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")


@rpc("authority", "call_remote", "reliable")
func _send_players(all: Dictionary) -> void:
	players = all
	players_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _joined_message(text: String) -> void:
	_message(text)


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
	if is_host() and _lan_out:
		_lan_timer -= delta
		if _lan_timer <= 0.0:
			_lan_timer = LAN_SEND_SECONDS
			var world := _world()
			var world_name: String = world.save.name if world and world.save else "World"
			_lan_out.put_packet(("VEBE;%s;%s;%d" % [player_name, world_name, PORT]).to_utf8_buffer())
	if _lan_in:
		var changed := false
		while _lan_in.get_available_packet_count() > 0:
			var text := _lan_in.get_packet().get_string_from_utf8()
			var parts := text.split(";")
			if parts.size() < 4 or parts[0] != "VEBE":
				continue
			var address := _lan_in.get_packet_ip()
			var key := "%s:%s" % [address, parts[3]]
			changed = changed or not lan_games.has(key)
			lan_games[key] = {"name": parts[1], "world": parts[2], "address": address, "port": int(parts[3]), "seen": now}
		for key: String in lan_games.keys():
			if now - float(lan_games[key].seen) > LAN_FORGET_SECONDS:
				lan_games.erase(key)
				changed = true
		if changed:
			lan_games_changed.emit()
	if is_host():
		for id: int in _waiting_hello.keys():
			if now > float(_waiting_hello[id]):
				_drop(id, "Could not connect") # never introduced itself
	if not is_online() or _world() == null:
		return
	_state_timer -= delta
	if _state_timer <= 0.0:
		_state_timer = 1.0 / STATE_RATE
		_send_own_state()
	if is_host() and players.size() > 1:
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
		if not _pending_blocks.is_empty():
			_blocks_changed.rpc(_pending_blocks)
			_pending_blocks = PackedInt32Array()
		_sync_timer -= delta
		if _sync_timer <= 0.0:
			_sync_timer = SYNC_SECONDS
			_send_world_sync()


# --- World: columns and block changes ----------------------------------------------------

## Host: a block changed (VoxelWorld.set_block); sent to the clients with the
## rest of this frame's changes.
func block_changed(pos: Vector3i, id: int) -> void:
	if is_host() and players.size() > 1:
		_pending_blocks.append_array(PackedInt32Array([pos.x, pos.y, pos.z, id]))


## Client: what to do with a column the world wants: "wait" (asked, no answer
## yet), "generate" or its blocks (PackedInt32Array).
func column_for(column: Vector2i) -> Variant:
	if _answers.has(column):
		var answer: Variant = _answers[column]
		_answers.erase(column)
		_asked.erase(column)
		return answer if (answer as PackedInt32Array).size() > 0 else "generate"
	if not _asked.has(column):
		_asked[column] = true
		_request_column.rpc_id(1, column.x, column.y)
	return "wait"


## Client: block changes that came while the column was on its way.
func take_waiting_changes(column: Vector2i) -> PackedInt32Array:
	var changes: PackedInt32Array = _waiting_changes.get(column, PackedInt32Array())
	_waiting_changes.erase(column)
	return changes


@rpc("any_peer", "call_remote", "reliable")
func _request_column(cx: int, cz: int) -> void:
	if not is_host() or not _within(multiplayer.get_remote_sender_id(), "column", COLUMN_LIMIT, 1.0):
		return
	var world := _world()
	var data := PackedByteArray()
	if world:
		var blocks := world.column_blocks_for_network(Vector2i(cx, cz))
		if not blocks.is_empty():
			data = blocks.to_byte_array().compress(FileAccess.COMPRESSION_ZSTD)
	_column_answer.rpc_id(multiplayer.get_remote_sender_id(), cx, cz, data)


@rpc("authority", "call_remote", "reliable")
func _column_answer(cx: int, cz: int, data: PackedByteArray) -> void:
	var blocks := PackedInt32Array()
	if not data.is_empty():
		blocks = data.decompress(WorldGenerator.COLUMN_VOLUME * 4, FileAccess.COMPRESSION_ZSTD).to_int32_array()
	_answers[Vector2i(cx, cz)] = blocks


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


## Client -> host: a block set by the player (placing, buckets...).
func send_set_block(pos: Vector3i, id: int) -> void:
	_client_set_block.rpc_id(1, pos.x, pos.y, pos.z, id)


## Client -> host: a block broken by the player (its drops on the ground).
func send_destroy(pos: Vector3i, drop: bool, can_harvest: bool) -> void:
	_client_destroy.rpc_id(1, pos.x, pos.y, pos.z, drop, can_harvest)


## Client -> host: a lever, button, door, trapdoor or note block used.
func send_use(pos: Vector3i) -> void:
	_client_use.rpc_id(1, pos.x, pos.y, pos.z)


@rpc("any_peer", "call_remote", "reliable")
func _client_set_block(x: int, y: int, z: int, id: int) -> void:
	var world := _world()
	if is_host() and _within(multiplayer.get_remote_sender_id(), "edit", EDIT_LIMIT, 1.0) and world and id >= 0 and id < Blocks.count():
		world.set_block(Vector3i(x, y, z), id)


@rpc("any_peer", "call_remote", "reliable")
func _client_destroy(x: int, y: int, z: int, drop: bool, can_harvest: bool) -> void:
	var world := _world()
	if is_host() and _within(multiplayer.get_remote_sender_id(), "edit", EDIT_LIMIT, 1.0) and world:
		world.destroy_block(Vector3i(x, y, z), drop, can_harvest)


@rpc("any_peer", "call_remote", "reliable")
func _client_use(x: int, y: int, z: int) -> void:
	var world := _world()
	if is_host() and _within(multiplayer.get_remote_sender_id(), "edit", EDIT_LIMIT, 1.0) and world:
		BlockInteraction.use_shared(world, Vector3i(x, y, z))


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
	_player_state.rpc(player.global_position, player.rotation.y, player.pitch(), flags, player.held_block(), _swings)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _player_state(at: Vector3, yaw: float, pitch: float, flags: int, held: int, swings: int) -> void:
	var id := multiplayer.get_remote_sender_id()
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


# --- Chat, time and weather -------------------------------------------------------------------

## Says something to everyone.
func say(text: String) -> void:
	_chat_line.rpc(player_name, text)


@rpc("any_peer", "call_remote", "reliable")
func _chat_line(from: String, text: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if is_host() and not _within(sender, "chat", CHAT_LIMIT, 5.0):
		return
	if players.has(sender):
		from = players[sender].name # (not whatever name it claims)
	text = text.left(256)
	var chat := _chat()
	if chat:
		var look: Dictionary = looks.get(multiplayer.get_remote_sender_id(), {})
		chat.add_chat(from, text, int(look.get("color", 0)))


# --- Looks: name colors and skins ----------------------------------------------------------

func _own_look() -> Dictionary:
	return {"color": PlayerProfile.name_color, "png": PlayerProfile.skin_png(), "skin": PlayerProfile.skin}


## Sends this player's name color and skin to everyone (on joining and
## when they change in Player Settings).
func send_look() -> void:
	if not is_online() or multiplayer.multiplayer_peer == null:
		return
	var own := _own_look()
	var id := multiplayer.get_unique_id()
	looks[id] = own
	_look.rpc(id, own.color, own.png)
	players_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _look(id: int, color: int, png: PackedByteArray) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != id and sender != 1:
		return # only one's own look (or the host passing it on)
	looks[id] = {"color": clampi(color, 0, PlayerProfile.COLORS.size() - 1), "png": png,
		"skin": PlayerProfile.skin_from_png(png)}
	var avatar: RemotePlayer = avatars.get(id)
	if avatar and is_instance_valid(avatar):
		avatar.set_look(looks[id].color, looks[id].skin)
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
	if world == null or players.size() < 2:
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


@rpc("authority", "call_remote", "reliable")
func _world_sync(game_time: int, day_time: float, raining: bool, rain: float, thundering: bool, thunder: float) -> void:
	var world := _world()
	if world == null:
		return
	world.clock.game_time = game_time
	world.clock.day_time = day_time
	world.weather.raining = raining
	world.weather.rain_strength = rain
	world.weather.thundering = thundering
	world.weather.thunder_strength = thunder


# --- The host's commands (NetCommands) and bans ---------------------------------------------

func is_banned(tag: String) -> bool:
	var config := ConfigFile.new()
	config.load(BANS_PATH)
	return config.has_section_key("bans", tag)


## The players with their tags (first 8 characters) and addresses.
func describe_players() -> String:
	var lines := PackedStringArray()
	for id: int in players:
		var tag: String = PlayerProfile.tag_for_server(_salt()) if id == 1 else _tags.get(id, "")
		lines.append("%s  #%s  %s" % [players[id].name, tag.left(8), "host" if id == 1 else _addresses.get(id, "?")])
	return "\n".join(lines)


func _peer_named(player: String) -> int:
	for id: int in players:
		if str(players[id].name).to_lower() == player.strip_edges().to_lower() and id != 1:
			return id
	return 0


func kick(player: String) -> String:
	var id := _peer_named(player)
	if id == 0:
		return ""
	_drop(id, "Kicked by the host")
	return players[id].name


## Bans a player's tag (they can't come back from that computer) and kicks them.
func ban(player: String) -> String:
	var id := _peer_named(player)
	if id == 0 or not _tags.has(id):
		return ""
	var config := ConfigFile.new()
	config.load(BANS_PATH)
	config.set_value("bans", _tags[id], players[id].name)
	config.save(BANS_PATH)
	_drop(id, "You are banned from this server")
	return players[id].name


## Lifts a ban by the start of the tag (or the name it was banned with).
func pardon(tag_or_name: String) -> String:
	var config := ConfigFile.new()
	config.load(BANS_PATH)
	if not config.has_section("bans"):
		return ""
	var wanted := tag_or_name.strip_edges().trim_prefix("#").to_lower()
	for tag: String in config.get_section_keys("bans"):
		var banned_name := str(config.get_value("bans", tag))
		if wanted != "" and (tag.begins_with(wanted) or banned_name.to_lower() == wanted):
			config.erase_section_key("bans", tag)
			config.save(BANS_PATH)
			return banned_name
	return ""


# --- Entities and dropped items (the host's, seen by clients) --------------------------------

func _avatar_of(peer: int) -> RemotePlayer:
	var avatar: RemotePlayer = avatars.get(peer)
	return avatar if avatar and is_instance_valid(avatar) else null


## Host: each client gets the entities and items near its player: new ones
## whole, all with where they are now, and which ones went.
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
		for entity in world.entities.all():
			if entity.removed or entity.type_name() == "fishing_bobber":
				continue
			if Vector2(entity.feet().x - at.x, entity.feet().z - at.z).length() > ENTITY_RANGE:
				continue
			if entity.net_id == 0:
				entity.net_id = _next_net_id
				_next_net_id += 1
			seen[entity.net_id] = true
			var whole: Variant = null if known.has(entity.net_id) else entity.save_state()
			entries.append([entity.net_id, entity.feet(), entity.net_yaw(), entity.net_state(), whole])
		var gone := PackedInt32Array()
		for id: int in known:
			if not seen.has(id):
				gone.append(id)
		_known_entities[peer] = seen
		var known_items: Dictionary = _known_items.get(peer, {})
		var seen_items := {}
		var items := []
		for item: Dictionary in world.items.net_items():
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
	if not is_host() or world == null or not _within(peer, "edit", EDIT_LIMIT, 1.0):
		return
	var entity := world.entities.create(str(state.get("type", "")))
	if entity == null or entity is Mob:
		return # (no creatures from clients)
	world.entities.spawn(entity, state.get("position", Vector3.ZERO))
	entity.load_state(state)
	entity.velocity = extra.get("velocity", Vector3.ZERO)
	if "_yaw" in entity:
		entity.set("_yaw", float(extra.get("yaw", 0.0)))
	if entity is Arrow:
		(entity as Arrow).shooter = _avatar_of(peer)
		(entity as Arrow).power = float(extra.get("power", 1.0))


## Client -> host: hit the host's entity `id` for `amount`.
func send_attack(id: int, amount: int) -> void:
	_client_attack.rpc_id(1, id, amount)


@rpc("any_peer", "call_remote", "reliable")
func _client_attack(id: int, amount: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var world := _world()
	if not is_host() or world == null or not _within(peer, "edit", EDIT_LIMIT, 1.0):
		return
	var entity := world.entities.by_net_id(id)
	var avatar := _avatar_of(peer)
	if entity == null or avatar == null or entity.center().distance_to(avatar.target_position) > 7.0:
		return
	if entity.damage(clampi(amount, 0, 40), avatar.target_position) and entity is Mob:
		(entity as Mob).hurt_by(avatar)


## Client -> host: get into the host's boat or minecart `id`.
func send_mount(id: int) -> void:
	_client_mount.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func _client_mount(id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var world := _world()
	if not is_host() or world == null or not players.has(peer):
		return
	var entity := world.entities.by_net_id(id)
	if entity and (entity is Boat or (entity is Minecart and entity.type_name() == "minecart")) and entity.seat_free():
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
	var world := _world()
	if not is_host() or world == null:
		return
	var entity := world.entities.by_net_id(id)
	if entity and entity.remote_rider == multiplayer.get_remote_sender_id() and entity.has_method("steer"):
		entity.call("steer", clampf(forward, -1.0, 1.0), look)


@rpc("any_peer", "call_remote", "reliable")
func _client_dismount(id: int) -> void:
	var world := _world()
	if not is_host() or world == null:
		return
	var entity := world.entities.by_net_id(id)
	if entity and entity.remote_rider == multiplayer.get_remote_sender_id():
		entity.remote_rider = 0


# --- Players hurting players (and creatures hurting clients) -------------------------------------

## Hurts the player of `peer` (the host's creatures, another player's hit).
func hurt_peer(peer: int, amount: int, from: Vector3) -> void:
	if peer == multiplayer.get_unique_id():
		var player := _game_player()
		if player:
			if amount > 0:
				player.damage(amount)
			if from != Vector3.INF:
				player.knockback(from)
		return
	_hurt.rpc_id(peer, amount, from)


@rpc("any_peer", "call_remote", "reliable")
func _hurt(amount: int, from: Vector3) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender) or (sender != 1 and not _within_any(sender)):
		return
	var player := _game_player()
	if player == null:
		return
	if amount > 0:
		player.damage(mini(amount, 20))
	if from != Vector3.INF and from.is_finite():
		player.knockback(from)


## Hits from other players: at most a few a second.
func _within_any(sender: int) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	var key := "%d/hurt" % sender
	var entry: Array = _counters.get(key, [now, 0])
	if now - float(entry[0]) > 1.0:
		entry = [now, 0]
	entry[1] = int(entry[1]) + 1
	_counters[key] = entry
	return int(entry[1]) <= 10


# --- Dropped items: through the host ----------------------------------------------------------------

## Client -> host: an item dropped or thrown here.
func send_item(id: int, count: int, position: Vector3, velocity: Vector3, damage: int, delay: int) -> void:
	_client_item.rpc_id(1, id, count, position, velocity, damage, delay)


@rpc("any_peer", "call_remote", "reliable")
func _client_item(id: int, count: int, position: Vector3, velocity: Vector3, damage: int, delay: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var world := _world()
	if not is_host() or world == null or not _within(peer, "edit", EDIT_LIMIT, 1.0):
		return
	if id <= 0 or count <= 0 or count > 64:
		return
	world.items.spawn(id, count, position, velocity, delay, damage)


## Client -> host: pick up the host's item `nid` (it walked over it).
func send_pickup(nid: int) -> void:
	_client_pickup.rpc_id(1, nid)


@rpc("any_peer", "call_remote", "reliable")
func _client_pickup(nid: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var world := _world()
	var avatar := _avatar_of(peer)
	if not is_host() or world == null or avatar == null:
		return
	var taken: Array = world.items.take_for_network(nid, avatar.target_position)
	if not taken.is_empty():
		_give.rpc_id(peer, taken[0], taken[1], taken[2])


@rpc("authority", "call_remote", "reliable")
func _give(id: int, count: int, damage: int) -> void:
	var player := _game_player()
	if player == null:
		return
	var left := player.inventory.add(id, count, damage)
	Sounds.play("random/pop", null, 0.2, ((randf() - randf()) * 0.7 + 1.0) * 2.0)
	if left > 0: # (no room after all: back on the ground)
		send_item(id, left, player.global_position + Vector3(0, 1, 0), Vector3.ZERO, damage, 40)


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
	if not is_host() or not _tags.has(peer):
		return
	saved_players[_tags[peer]] = state


# --- Cheats ----------------------------------------------------------------------------------

## Whether commands needing cheats may run here: the network game's choice
## when online, else the world's ("Allow Cheats").
func cheats_allowed() -> bool:
	if is_online():
		return cheats
	return WorldSave.current == null or WorldSave.current.allow_cheats


## Client -> host: a world command (HOST_COMMANDS) typed by this player.
func send_command(text: String) -> void:
	_client_command.rpc_id(1, text)


@rpc("any_peer", "call_remote", "reliable")
func _client_command(text: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var world := _world()
	if not is_host() or world == null or not cheats or not _within(peer, "chat", CHAT_LIMIT, 5.0):
		return
	var root := text.strip_edges().trim_prefix("/").get_slice(" ", 0).to_lower()
	if not root in HOST_COMMANDS:
		return
	var source := CommandSource.new()
	source.name = str(players[peer].name)
	source.world = world
	source.origin = _avatar_of(peer) # ~ ~ ~ are where that player is
	source.output = func(message: String, kind: int) -> void: _command_output.rpc_id(peer, message, kind)
	Commands.dispatcher.execute(text, source)


@rpc("authority", "call_remote", "reliable")
func _command_output(text: String, kind: int) -> void:
	var chat := _chat()
	if chat:
		chat.add_message(text, kind)