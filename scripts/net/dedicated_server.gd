class_name DedicatedServer
extends Node
## A dedicated server: the game started with --server (SERVER.md):
##   "<game>" --headless --server [--port N] [--world NAME] [--config FILE]
##   godot --headless --path <project> -- --server [...]
## or the start-server files next to an exported game (tools/server/).
## Net makes this node at startup. It reads server.properties (ServerConfig;
## where: config_path(), made with the defaults the first time), loads or
## creates the world, starts the server scene (scenes/server.tscn: the world
## without a player, a camera or the UI) and hosts it with Net; clients
## join as they join anyone.
##
## Create Server in the game (LocalServer) starts one too, in the
## background, with its own settings in user://server/ and a secret token
## next to them (ADMIN_TOKEN_FILE): that game may then ask it for its
## addresses and stop it cleanly over the admin channel (ServerStatus).
##
## The console: lines typed on stdin (read on a thread, so the game never
## waits) run as commands of the server, with every right: /say, /list,
## /kick, /ban, /op, /whitelist, /save-all, /stop and the game's own. Joins,
## leaves, the chat, commands and what the security checks refuse are
## written to stdout and to logs/latest.log next to the config (the one
## before is kept with its date).
##
## Godot can't catch SIGINT / SIGTERM itself: tools/run.sh --server and the start-server files turn
## them into "stop" on the console, which saves the world and the players,
## closes the router's ports and exits.

const SERVER_SCENE := "res://scenes/server.tscn"
const KEEP_LOGS := 20
const CONFIG_FILE := "server.properties"
const ADMIN_TOKEN_FILE := "admin.token"

var config: ServerConfig
var port := Net.PORT
var _log: FileAccess
var _console: Thread
var _console_done := false
var _hosted := false
var _stopping := false
## The admin channel's token (ADMIN_TOKEN_FILE next to the settings; "": none).
var admin_token := ""


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
	var path := config_path()
	var first_start := not FileAccess.file_exists(path)
	config = ServerConfig.load_or_create(path)
	_open_log(path.get_base_dir().path_join("logs"))
	log_line("Starting Voxel Engine server version %s" % ProjectSettings.get_setting("application/config/version", "dev"))
	log_line(("Made %s with the default settings" if first_start else "Settings: %s") % ProjectSettings.globalize_path(path))
	var token_path := path.get_base_dir().path_join(ADMIN_TOKEN_FILE)
	if FileAccess.file_exists(token_path):
		admin_token = FileAccess.get_file_as_string(token_path).strip_edges()
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
	for ip in InviteCode.lan_addresses():
		log_line("On the local network: %s" % ("%s:%d" % [ip, port] if port != Net.PORT else ip))
	if Net.public_address != "":
		log_line("Players connect to: %s" % Net.public_address)
	elif Net.internet:
		log_line("Opening the ports on the router (UPnP)...")
	else:
		log_line("Over the internet: forward UDP ports %d and %d to this computer, or set upnp=true; a domain name goes in public-address" % [port, port + 1])
	log_line("Type help for the commands, stop to save and stop")


## Where server.properties is: --config; else next to the game (an
## exported game: the executable's folder, on macOS the folder holding the
## .app, so a server folder is portable); else the folder the server was
## started in; else user://. The first time it is made next to the game when
## that folder can be written to, else in user:// (running from the project
## too: never in the project's folder).
static func config_path() -> String:
	var given := _argument("--config")
	if given != "":
		if given.is_relative_path() and not given.begins_with("user://") and not given.begins_with("res://"):
			return working_folder().path_join(given) if working_folder() != "" else given
		return given
	var game := game_folder()
	var here := working_folder()
	for folder: String in [game, here]:
		if folder != "" and FileAccess.file_exists(folder.path_join(CONFIG_FILE)):
			return folder.path_join(CONFIG_FILE)
	if game != "" and _writable(game):
		return game.path_join(CONFIG_FILE)
	return "user://" + CONFIG_FILE


## The folder of an exported game (the .app's folder on macOS); "" when
## running from the editor or the project (the executable is Godot's).
static func game_folder() -> String:
	if not OS.has_feature("template"):
		return ""
	var folder := OS.get_executable_path().get_base_dir()
	if folder.ends_with(".app/Contents/MacOS"):
		folder = folder.get_base_dir().get_base_dir().get_base_dir()
	return folder


## The folder the game was started in.
static func working_folder() -> String:
	var pwd := OS.get_environment("PWD")
	if pwd != "":
		return pwd
	var dir := DirAccess.open(".")
	return dir.get_current_dir() if dir else ""


static func _writable(folder: String) -> bool:
	var probe := folder.path_join(".write-test")
	var file := FileAccess.open(probe, FileAccess.WRITE)
	if file == null:
		return false
	file.close()
	DirAccess.remove_absolute(probe)
	return true


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
	# (--no-console: started by the game, LocalServer; its input isn't ours.)
	if OS.get_stdin_type() == OS.STD_HANDLE_INVALID or "--no-console" in OS.get_cmdline_user_args() \
			or "--no-console" in OS.get_cmdline_args():
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


# --- The admin channel ---------------------------------------------------------------------------

## A command from the game that started this server (ServerStatus, with the
## token): "info" (JSON: port, addresses, players), "stop", "cmd <line>".
func admin_command(text: String) -> String:
	var command := text.get_slice(" ", 0)
	match command:
		"info":
			var lan := PackedStringArray()
			for ip in InviteCode.lan_addresses():
				lan.append("%s:%d" % [ip, port] if port != Net.PORT else ip)
			var forward := Net.port_forward
			return JSON.stringify({"port": port, "lan": lan, "internet": Net.internet_address(), "code": Net.invite_code(),
				"upnp": ["off", "working", "open", "failed"][forward.state] if Net.internet else "off",
				"upnp_error": forward.error, "players": Net.player_count(), "world": config.get_string("world-name")})
		"stop":
			log_line("Stop asked by the game that started this server")
			stop.call_deferred()
			return "ok"
		"upnp":
			Net.allow_internet()
			return "ok"
		"cmd":
			var line := NetGuard.clean_text(text.substr(4), 1024)
			log_line("> " + line + " (from the game)")
			run_command.call_deferred(line)
			return "ok"
	return "unknown"


# --- Stopping ------------------------------------------------------------------------------------

## Saves the world and everyone's player, sends the players away, closes the
## router's ports and exits.
func stop() -> void:
	if _stopping:
		return
	_stopping = true
	log_line("Stopping the server")
	await Net.shutdown_server(NetErrors.SERVER_CLOSED)
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
