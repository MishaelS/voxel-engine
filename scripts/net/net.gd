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
## Creatures, dropped items, chests and minecarts are the next step: in
## this step they are the host's own (a client gets its drops straight
## into the inventory).

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

var mode := Mode.OFFLINE
var player_name := ""
var last_address := "127.0.0.1"
## Peer id -> {"name": String, "ping": ms (-1 unknown)}, everyone in the
## game (this one too); the host measures the pings and sends them each
## second (the Tab list).
var players := {}
## Peer id -> RemotePlayer.
var avatars := {}
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # networking goes on in the pause menu
	_load_config()
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
	if _peer:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	mode = Mode.OFFLINE
	players.clear()
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


func _on_peer_connected(_id: int) -> void:
	pass # the client introduces itself (hello)


func _on_peer_disconnected(id: int) -> void:
	if not players.has(id):
		return
	var left_name: String = players[id].name
	players.erase(id)
	if avatars.has(id):
		(avatars[id] as Node).queue_free()
		avatars.erase(id)
	_message("%s left the game" % left_name)
	if is_host():
		_send_players.rpc(players)
	players_changed.emit()


func _on_connected() -> void:
	_hello.rpc_id(1, player_name, str(ProjectSettings.get_setting("application/config/version", "dev")))


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
func _hello(joining_name: String, version: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	var game_version := str(ProjectSettings.get_setting("application/config/version", "dev"))
	if version != game_version:
		_refused.rpc_id(id, "The host plays version %s" % game_version)
		return
	var world := _world()
	var host_player := _game_player()
	if world == null or host_player == null:
		_refused.rpc_id(id, "The host is not in a world")
		return
	var taken := false
	for peer: int in players:
		taken = taken or players[peer].name == joining_name
	var unique_name := joining_name if not taken else "%s%d" % [joining_name, id % 100]
	players[id] = {"name": unique_name}
	var save := world.save
	_welcome.rpc_id(id, {
		"name": save.name if save else "World", "seed": world.world_seed, "generator": world.generator,
		"tall": save.tall_terrain if save else true, "game_mode": save.game_mode if save else 0,
		"spawn": world.find_spawn(), # the world spawn (not the host's bed)
		"game_time": world.clock.game_time, "day_time": world.clock.day_time,
		"your_name": unique_name,
	})
	_send_players.rpc(players)
	_message("%s joined the game" % unique_name)
	_joined_message.rpc("%s joined the game" % unique_name)
	players_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _refused(reason: String) -> void:
	last_error = reason
	leave()
	players_changed.emit()


## Host -> client: the world to play; the client loads it (Game).
@rpc("authority", "call_remote", "reliable")
func _welcome(info: Dictionary) -> void:
	world_info = info
	player_name = info.get("your_name", player_name)
	var save := WorldSave.new()
	save.remote = true
	save.name = info.get("name", "World")
	save.world_seed = info.get("seed", 0)
	save.generator = info.get("generator", 0)
	save.tall_terrain = info.get("tall", true)
	save.game_mode = info.get("game_mode", 0)
	save.state = {"player": {"position": info.get("spawn", Vector3(8, 140, 8)), "spawn": info.get("spawn", Vector3(8, 140, 8))}}
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
	if not is_online() or _world() == null:
		return
	_state_timer -= delta
	if _state_timer <= 0.0:
		_state_timer = 1.0 / STATE_RATE
		_send_own_state()
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
	if not is_host():
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


## Client -> host: a block broken by the player.
func send_destroy(pos: Vector3i) -> void:
	_client_destroy.rpc_id(1, pos.x, pos.y, pos.z)


## Client -> host: a lever, button, door, trapdoor or note block used.
func send_use(pos: Vector3i) -> void:
	_client_use.rpc_id(1, pos.x, pos.y, pos.z)


@rpc("any_peer", "call_remote", "reliable")
func _client_set_block(x: int, y: int, z: int, id: int) -> void:
	var world := _world()
	if is_host() and world and id >= 0 and id < Blocks.count():
		world.set_block(Vector3i(x, y, z), id)


@rpc("any_peer", "call_remote", "reliable")
func _client_destroy(x: int, y: int, z: int) -> void:
	var world := _world()
	if is_host() and world:
		world.destroy_block(Vector3i(x, y, z), false, false)


@rpc("any_peer", "call_remote", "reliable")
func _client_use(x: int, y: int, z: int) -> void:
	var world := _world()
	if is_host() and world:
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
		| (8 if player.sleeping else 0)
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
		avatar.player_name = players[id].name
		world.add_child(avatar)
		avatar.global_position = at
		avatars[id] = avatar
	avatar.set_state(at, yaw, pitch, flags, held, swings)


# --- Chat, time and weather -------------------------------------------------------------------

## Says something to everyone.
func say(text: String) -> void:
	_chat_line.rpc(player_name, text)


@rpc("any_peer", "call_remote", "reliable")
func _chat_line(from: String, text: String) -> void:
	var chat := _chat()
	if chat:
		chat.add_message("<%s> %s" % [from, text], CommandSource.MessageKind.CHAT)


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
