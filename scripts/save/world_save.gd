class_name WorldSave
extends RefCounted
## A saved world, like the classic game's world folders:
##   user://saves/<folder>/level.cfg     - name, seed, generator, game mode,
##                                         time, game rules and the player
##   user://saves/<folder>/columns/x.z.bin - every column generated so far
##                                           (with the player's changes)
## Columns are zstd-compressed (32 KB raw each). A column is written when it
## is first generated, so loading the world again reads it instead of
## generating it, and again when the player changed it.
##
## `current` is the world being played; the game scene reads it on start.
## Without it (the game scene run directly) the world is not saved.

const ROOT := "user://saves"
const LEVEL_FILE := "level.cfg"
const COLUMNS_DIR := "columns"

static var current: WorldSave

var folder := ""
var name := "New World"
var world_seed := 0
var generator := 0 # VoxelWorld.Generator
var game_mode := 0 # Player.GameMode
var created := 0      # unix time
var last_played := 0  # unix time
## World and player state, written by save_state(); empty for a new world.
var state := {}


## All saved worlds, most recently played first.
static func list_all() -> Array[WorldSave]:
	var worlds: Array[WorldSave] = []
	var dir := DirAccess.open(ROOT)
	if dir == null:
		return worlds
	for folder_name in dir.get_directories():
		var save := WorldSave.new()
		save.folder = folder_name
		if save.load_level():
			worlds.append(save)
	worlds.sort_custom(func(a: WorldSave, b: WorldSave) -> bool: return a.last_played > b.last_played)
	return worlds


## Creates the folder of a new world (the name is made unique on disk).
static func create(world_name: String, seed_value: int, world_generator: int, mode: int) -> WorldSave:
	var save := WorldSave.new()
	save.name = world_name.strip_edges() if not world_name.strip_edges().is_empty() else "New World"
	save.world_seed = seed_value
	save.generator = world_generator
	save.game_mode = mode
	save.created = int(Time.get_unix_time_from_system())
	save.last_played = save.created
	save.folder = _unique_folder(save.name)
	DirAccess.make_dir_recursive_absolute(save.path(COLUMNS_DIR))
	save.write_level()
	return save


## Seed from the text typed by the player: a number is used as is, any
## other text is hashed (like the classic game); empty = random.
static func seed_from_text(text: String) -> int:
	text = text.strip_edges()
	if text.is_empty():
		return randi()
	if text.is_valid_int():
		return text.to_int()
	return text.hash()


static func _unique_folder(world_name: String) -> String:
	var base := world_name.validate_filename().replace(" ", "_")
	if base.is_empty():
		base = "World"
	var candidate := base
	var n := 1
	while DirAccess.dir_exists_absolute(ROOT.path_join(candidate)):
		n += 1
		candidate = "%s_%d" % [base, n]
	return candidate


func path(file: String = "") -> String:
	return ROOT.path_join(folder).path_join(file)


func load_level() -> bool:
	var config := ConfigFile.new()
	if config.load(path(LEVEL_FILE)) != OK:
		return false
	name = config.get_value("world", "name", folder)
	world_seed = config.get_value("world", "seed", 0)
	generator = config.get_value("world", "generator", 0)
	game_mode = config.get_value("world", "game_mode", 0)
	created = config.get_value("world", "created", 0)
	last_played = config.get_value("world", "last_played", 0)
	state = config.get_value("state", "data", {})
	return true


func write_level() -> void:
	var config := ConfigFile.new()
	config.set_value("world", "name", name)
	config.set_value("world", "seed", world_seed)
	config.set_value("world", "generator", generator)
	config.set_value("world", "game_mode", game_mode)
	config.set_value("world", "created", created)
	config.set_value("world", "last_played", last_played)
	config.set_value("state", "data", state)
	DirAccess.make_dir_recursive_absolute(path())
	config.save(path(LEVEL_FILE))


## Deletes the world folder and everything in it.
func delete() -> void:
	_remove_recursive(path())


static func _remove_recursive(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	for sub in dir.get_directories():
		_remove_recursive(dir_path.path_join(sub))
	DirAccess.remove_absolute(dir_path)


# --- Columns (thread-safe: only files, no shared state) ---------------------------

func _column_path(column: Vector2i) -> String:
	return path(COLUMNS_DIR).path_join("%d.%d.bin" % [column.x, column.y])


func has_column(column: Vector2i) -> bool:
	return FileAccess.file_exists(_column_path(column))


## The blocks of a saved column (WorldGenerator layout), or empty.
## Columns are stored as 32-bit ids (older saves: one byte per block,
## converted on load).
func load_column(column: Vector2i) -> PackedInt32Array:
	var file := FileAccess.open_compressed(_column_path(column), FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return PackedInt32Array()
	var data := file.get_buffer(WorldGenerator.COLUMN_VOLUME * 4)
	if data.size() == WorldGenerator.COLUMN_VOLUME * 4:
		return data.to_int32_array()
	if data.size() == WorldGenerator.COLUMN_VOLUME:
		# An older save (one byte per block): converted and written back in
		# the new format, so this happens only once.
		var blocks := PackedInt32Array(Array(data))
		file = null
		save_column(column, blocks)
		return blocks
	return PackedInt32Array()


func save_column(column: Vector2i, blocks: PackedInt32Array) -> void:
	var file := FileAccess.open_compressed(_column_path(column), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file:
		file.store_buffer(blocks.to_byte_array())
