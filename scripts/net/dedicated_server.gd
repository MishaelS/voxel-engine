class_name DedicatedServer
extends Node
## A dedicated server: the game started with --server (SERVER.md):
##   godot --headless --path <project> -- --server [--port N] [--world NAME] [--config FILE]
## Net makes this node at startup. It reads server.properties (ServerConfig,
## made with the defaults the first time: --config, else
## user://server.properties), loads or creates the world, starts the server
## scene (scenes/server.tscn: the world without a player, a camera or the
## UI) and hosts it with Net; clients join as they join anyone.
##
## The console: lines typed on stdin (read on a thread, so the game never
## waits) run as commands of the server, with every right: /say, /list,
## /kick, /ban, /op, /whitelist, /save-all, /stop and the game's own. Joins,
## leaves, the chat, commands and what the security checks refuse are
## written to stdout and to logs/latest.log next to the config (the one
## before is kept with its date).
##
## Godot can't catch SIGINT / SIGTERM itself: tools/run_server.sh turns
## them into "stop" on the console, which saves the world and the players,
## closes the router's ports and exits.

const SERVER_SCENE := "res://scenes/server.tscn"
const KEEP_LOGS := 20

var config: ServerConfig
var port := Net.PORT
var _log: FileAccess
var _console: Thread
var _console_done := false
var _hosted := false
var _stopping := false


## Whether the game was started as a dedicated server.
static func requested() -> bool:
	return "--server" in OS.get_cmdline_user_args() or "--server" in OS.get_cmdline_args()


static func _argument(key: String) -> String:
	for args: PackedStringArray in [OS.get_cmdline_user_args(), OS.get_cmdline_args()]:
		var i := args.find(key)
		if i >= 0 and i + 1 < args.size():
			return args[i + 1]
	return ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	TranslationServer.set_locale("en") # (the console and what players are told: English, like the game's servers)
	var config_path := _argument("--config")
	if config_path == "":
		config_path = "user://server.properties"
	elif config_path.is_relative_path() and not config_path.begins_with("user://") and not config_path.begins_with("res://"):
		config_path = OS.get_environment("PWD").path_join(config_path) if OS.get_environment("PWD") != "" else config_path
	var first_start := not FileAccess.file_exists(config_path)
	config = ServerConfig.load_or_create(config_path)
	_open_log(config_path.get_base_dir().path_join("logs"))
	log_line("Starting Voxel Engine server version %s" % ProjectSettings.get_setting("application/config/version", "dev"))
	if first_start:
		log_line("Made %s with the default settings" % ProjectSettings.globalize_path(config_path))
	if DisplayServer.get_name() != "headless":
		log_line("Tip: start the server with --headless (no window, no sound)")
	port = int(_argument("--port")) if _argument("--port").is_valid_int() else config.get_int("server-port", 1, 65534)
	var world_name := _argument("--world") if _argument("--world") != "" else config.get_string("world-name")
	Net.configure_dedicated(self)
	Engine.max_fps = 60 # (no screen to wait for: the loop would spin)
	var save := _world_save(world_name)
	if save == null:
		log_line("Can't open the world '%s'" % world_name)
		get_tree().quit(1)
		return
	_start_console()
	# The project's main scene starts first (and goes): the world is given
	# to the server's scene only.
	await get_tree().process_frame
	WorldSave.current = save
	get_tree().change_scene_to_file(SERVER_SCENE)


func _process(_delta: float) -> void:
	if _hosted or _stopping:
		return
	var game := Game.find(get_tree())
	if game == null or game.world == null or not game.world.is_inside_tree():
		return
	_hosted = true
	var error := Net.host(port)
	if error != "":
		log_line("Can't start the server: %s" % error)
		get_tree().quit(1)
		return
	log_line("Server started on port %d (status ping on %d) with the world '%s'" % [port, port + ServerStatus.PORT_OFFSET, game.world.save.name])
	log_line("Type help for the commands, stop to save and stop")


## The world `world_name` (a folder in saves/), made with the settings
## of server.properties when it doesn't exist yet.
func _world_save(world_name: String) -> WorldSave:
	var folder := world_name.strip_edges().validate_filename().replace(" ", "_")
	if folder == "":
		folder = "world"
	var save := WorldSave.new()
	save.folder = folder
	if save.load_level():
		log_line("Loading the world '%s' (%s)" % [save.name, ProjectSettings.globalize_path(save.path())])
		return save
	var types := {"default": [VoxelWorld.Generator.BETA, WorldSave.CLASSIC], "tall": [VoxelWorld.Generator.BETA, WorldSave.TALL],
		"floating": [VoxelWorld.Generator.FLOATING_ISLANDS, WorldSave.FLOATING], "island": [VoxelWorld.Generator.ISLAND, WorldSave.CLASSIC]}
	var type: Array = types.get(config.get_string("world-type").to_lower(), types["default"])
	save.name = world_name.strip_edges() if world_name.strip_edges() != "" else "world"
	save.world_seed = WorldSave.seed_from_text(config.get_string("seed"))
	save.generator = type[0]
	save.terrain = type[1]
	save.height = WorldGenerator.LEGACY_HEIGHT if save.terrain == WorldSave.CLASSIC else WorldGenerator.HEIGHT
	save.game_mode = Net.lan_game_mode
	save.allow_cheats = false
	save.bonus_chest = config.get_bool("bonus-chest")
	save.created = int(Time.get_unix_time_from_system())
	save.last_played = save.created
	DirAccess.make_dir_recursive_absolute(save.path(WorldSave.COLUMNS_DIR))
	save.write_level()
	if not FileAccess.file_exists(save.path(WorldSave.LEVEL_FILE)):
		return null
	log_line("Made a new world '%s' (seed %d) in %s" % [save.name, save.world_seed, ProjectSettings.globalize_path(save.path())])
	return save


# --- Log -------------------------------------------------------------------------------------

func _open_log(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var latest := dir.path_join("latest.log")
	if FileAccess.file_exists(latest):
		var stamp := Time.get_datetime_string_from_unix_time(int(FileAccess.get_modified_time(latest))).replace(":", ".")
		DirAccess.rename_absolute(latest, dir.path_join(stamp + ".log"))
	var old := Array(DirAccess.get_files_at(dir)).filter(func(f: String) -> bool: return f.ends_with(".log") and f != "latest.log")
	old.sort()
	for i in maxi(old.size() - KEEP_LOGS, 0):
		DirAccess.remove_absolute(dir.path_join(old[i]))
	_log = FileAccess.open(latest, FileAccess.WRITE)


## A line for the console and the log, with the time.
func log_line(text: String) -> void:
	var line := "[%s] %s" % [Time.get_time_string_from_system(), text]
	print(line)
	if _log:
		_log.store_line(line)
		_log.flush()


# --- Console -----------------------------------------------------------------------------------

func _start_console() -> void:
	if OS.get_stdin_type() == OS.STD_HANDLE_INVALID:
		return
	_console = Thread.new()
	_console.start(_read_console)


## The console thread: a line at a time; many empty reads in a row are the
## end of the input (nobody types there: under systemd, or the pipe closed).
func _read_console() -> void:
	var empty := 0
	while not _console_done:
		var line := OS.read_string_from_stdin(4096).strip_edges()
		if line == "":
			empty += 1
			if empty > 50:
				return
			OS.delay_msec(100)
			continue
		empty = 0
		_on_console_line.call_deferred(line)


func _on_console_line(line: String) -> void:
	if _stopping:
		return
	var text := NetGuard.clean_text(line, 1024)
	if text == "":
		return
	log_line("> " + text)
	run_command(text)


## Runs a command (or says what isn't one) as the server: every right.
func run_command(text: String) -> void:
	var game := Game.find(get_tree())
	var source := CommandSource.new()
	source.name = "Server"
	source.world = game.world if game else null
	source.output = func(message: String, _kind: int) -> void:
		for message_line in message.split("\n"):
			log_line(message_line)
	if not text.begins_with("/"):
		text = "/" + text
	if source.world == null and not text.trim_prefix("/").get_slice(" ", 0) in ["stop", "help"]:
		log_line("The world is still loading")
		return
	Commands.dispatcher.execute(text, source)


# --- Stopping ------------------------------------------------------------------------------------

## Saves the world and everyone's player, sends the players away, closes the
## router's ports and exits.
func stop() -> void:
	if _stopping:
		return
	_stopping = true
	log_line("Stopping the server")
	await Net.shutdown_server("Server closed")
	var game := Game.find(get_tree())
	if game:
		log_line("Saving the world")
		game.save_game()
	Net.leave()
	Net.port_forward.close_now()
	log_line("Server stopped")
	_console_done = true
	if _console and not _console.is_alive():
		_console.wait_to_finish()
	if _log:
		_log.close()
	get_tree().quit()
