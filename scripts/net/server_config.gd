class_name ServerConfig
extends RefCounted
## server.properties of a dedicated server (DedicatedServer), like the
## classic game's: one key=value per line, # comments. Made with every key
## and what it does the first time the server starts; keys missing from an
## older file get their defaults (and are written back).

## [key, default, what it does]
const KEYS := [
	["server-port", 25565, "UDP port of the game; the server list's ping uses this port + 1 (open both)"],
	["server-ip", "", "Address to listen on (empty: all of this computer's addresses)"],
	["world-name", "world", "The world's folder under saves/ (made when missing)"],
	["seed", "", "Seed of a new world (empty: random; text is hashed)"],
	["world-type", "default", "A new world's type: default, tall, floating, island"],
	["bonus-chest", false, "A chest of starting things by the spawn of a new world"],
	["gamemode", "survival", "Game mode of players: survival or creative"],
	["difficulty", "normal", "peaceful, easy, normal or hard"],
	["max-players", 20, "Players at most (1-100)"],
	["motd", "A Voxel Engine Server", "The message shown in the server list"],
	["password", "", "Joining needs this password (empty: none); it is never sent over the network"],
	["white-list", false, "Only players on the whitelist may join (/whitelist add <name>)"],
	["enforce-tags", true, "Ties names on the whitelist and the ops list to the computer of whoever joined with them first"],
	["view-distance", 12, "Columns around a player the server sends changed land for (4-32)"],
	["simulation-distance", 5, "Columns around each player kept loaded and ticking (2-10)"],
	["spawn-protection", 16, "Blocks around the world spawn only ops may change (0: off)"],
	["idle-timeout", 0, "Minutes a player may stand idle before being kicked (0: never)"],
	["pvp", true, "Players can hurt each other"],
	["autosave-minutes", 5, "Minutes between saves of the world (1-60)"],
	["upnp", false, "Open the ports on the router by UPnP (a home server; a VPS doesn't need it)"],
	["lan-broadcast", false, "Show the server in the Multiplayer list of players on the same network"],
	["max-connections-per-ip", 3, "Connections at most from one address"],
	["spawn-radius", 3, "Columns kept loaded around the spawn while nobody plays"],
]

var path := ""
var values := {}


## Reads `file` (made with the defaults when missing). Returns the config.
static func load_or_create(file: String) -> ServerConfig:
	var config := ServerConfig.new()
	config.path = file
	for entry: Array in KEYS:
		config.values[entry[0]] = entry[1]
	var missing := not FileAccess.file_exists(file)
	if not missing:
		var text := FileAccess.get_file_as_string(file)
		var found := {}
		for raw_line in text.split("\n"):
			var line := raw_line.strip_edges()
			if line == "" or line.begins_with("#") or not line.contains("="):
				continue
			var key := line.get_slice("=", 0).strip_edges()
			var value := line.substr(line.find("=") + 1).strip_edges()
			found[key] = true
			config.values[key] = config._parse(key, value)
		for entry: Array in KEYS:
			missing = missing or not found.has(entry[0])
	if missing:
		config.save()
	return config


func _parse(key: String, text: String) -> Variant:
	var default: Variant = null
	for entry: Array in KEYS:
		if entry[0] == key:
			default = entry[1]
	if default is bool:
		return text.to_lower() in ["true", "on", "yes", "1"]
	if default is int:
		return text.to_int() if text.is_valid_int() else default
	return text


func get_string(key: String) -> String:
	return str(values.get(key, ""))


func get_int(key: String, low: int = -2147483648, high: int = 2147483647) -> int:
	var value: Variant = values.get(key, 0)
	return clampi(int(value) if value is int else str(value).to_int(), low, high)


func get_bool(key: String) -> bool:
	var value: Variant = values.get(key, false)
	return value if value is bool else str(value).to_lower() == "true"


func set_value(key: String, value: Variant) -> void:
	values[key] = value
	save()


## Writes every key with its comment (and keys this version doesn't know
## at the end, kept as they were).
func save() -> void:
	var lines := PackedStringArray(["# Voxel Engine dedicated server settings (see SERVER.md).",
		"# Restart the server after changing them.", ""])
	var known := {}
	for entry: Array in KEYS:
		known[entry[0]] = true
		lines.append("# " + str(entry[2]))
		lines.append("%s=%s" % [entry[0], _text(values.get(entry[0], entry[1]))])
	for key: String in values:
		if not known.has(key):
			lines.append("%s=%s" % [key, _text(values[key])])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string("\n".join(lines) + "\n")


static func _text(value: Variant) -> String:
	if value is bool:
		return "true" if value else "false"
	return str(value).replace("\n", " ")
