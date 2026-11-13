class_name WorldSave
extends RefCounted
## A saved world, like the classic game's world folders:
##   user://saves/<folder>/level.cfg     - name, seed, generator, game mode,
##                                         time, game rules and the player
##   user://saves/<folder>/columns/x.z.bin - every column generated so far
##                                           (with the player's changes)
## Columns are zstd-compressed (256 KB raw each: 32-bit ids, 256 high
## whatever the world's own height). Columns saved 128 high are filled up
## with air as they load (WorldGenerator.convert_legacy). A column is written when it
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
## A network game's world as a client has it (Net): kept in memory only,
## never written.
var remote := false
var name := "New World"
var world_seed := 0
var generator := 0 # VoxelWorld.Generator
var game_mode := 0 # Player.GameMode
## Commands that change the world or the player (/gamemode, /time, /tp...)
## are allowed, like the game's "Allow Cheats". Worlds from before: allowed.
var allow_cheats := true
## A chest of starting things by the spawn, put there when the world is
## first played (VoxelWorld.place_bonus_chest).
var bonus_chest := false
## The world type: "classic" (Beta 1.7.3: 128 high, the sea at 64), "tall"
## (Tall Mountains: 256 high, the sea at 64) or "old" (made 256 high with
## the sea at 128 and a deep layer, before the world types).
const CLASSIC := "classic"
const TALL := "tall"
const OLD := "old"
## Floating Islands: 256 high, no sea.
const FLOATING := "floating"
const TYPES: Array[String] = [CLASSIC, TALL, FLOATING]
var terrain := CLASSIC
## The world's height (128 or 256) and, in old worlds, whether the terrain
## has the taller mountains.
var height := WorldGenerator.LEGACY_HEIGHT
var tall_terrain := false
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
static func create(world_name: String, seed_value: int, world_generator: int, mode: int, cheats: bool = true,
		world_type: String = CLASSIC) -> WorldSave:
	var save := WorldSave.new()
	save.allow_cheats = cheats
	save.terrain = world_type if world_type in TYPES else CLASSIC
	save.height = WorldGenerator.LEGACY_HEIGHT if save.terrain == CLASSIC else WorldGenerator.HEIGHT
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
	allow_cheats = config.get_value("world", "allow_cheats", true)
	bonus_chest = config.get_value("world", "bonus_chest", false)
	created = config.get_value("world", "created", 0)
	last_played = config.get_value("world", "last_played", 0)
	height = config.get_value("world", "height", WorldGenerator.LEGACY_HEIGHT)
	tall_terrain = config.get_value("world", "tall_terrain", false)
	# Worlds from before the world types: 128 high ones are classic, 256
	# high ones old.
	terrain = config.get_value("world", "terrain", CLASSIC if height < WorldGenerator.HEIGHT else OLD)
	state = config.get_value("state", "data", {})
	return true


func write_level() -> void:
	if remote:
		return
	var config := ConfigFile.new()
	config.set_value("world", "name", name)
	config.set_value("world", "seed", world_seed)
	config.set_value("world", "generator", generator)
	config.set_value("world", "game_mode", game_mode)
	config.set_value("world", "allow_cheats", allow_cheats)
	config.set_value("world", "bonus_chest", bonus_chest)
	config.set_value("world", "created", created)
	config.set_value("world", "last_played", last_played)
	config.set_value("world", "height", height)
	config.set_value("world", "tall_terrain", tall_terrain)
	config.set_value("world", "terrain", terrain)
	config.set_value("state", "data", state)
	DirAccess.make_dir_recursive_absolute(path())
	config.save(path(LEVEL_FILE))


## How the world is laid out: "height" (where building stops), "sea",
## and for the generator "shift" (the classic part's bottom), "deep" (the
## old worlds' deep layer under it), "upper" (the classic part's height)
## and "tall" (softer slopes above the middle: higher mountains).
static func layout_of(world_type: String, old_tall: bool = false) -> Dictionary:
	match world_type:
		TALL:
			return {"height": 256, "sea": 64, "shift": 0, "deep": false, "upper": 256, "tall": true}
		FLOATING:
			return {"height": 256, "sea": 0, "shift": 0, "deep": false, "upper": 256, "tall": false}
		OLD:
			return {"height": 256, "sea": 128, "shift": WorldGenerator.LEGACY_SHIFT, "deep": true,
				"upper": 192 if old_tall else 128, "tall": old_tall}
	return {"height": 128, "sea": 64, "shift": 0, "deep": false, "upper": 128, "tall": false}


func layout() -> Dictionary:
	return layout_of(terrain, tall_terrain)


## Deletes the world folder and everything in it.
func delete() -> void:
	if remote or folder.strip_edges() == "":
		return # (an empty folder would be the whole saves folder)
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
	if remote:
		return false
	return FileAccess.file_exists(_column_path(column))


## The blocks of a saved column (WorldGenerator layout), or empty.
## Columns are stored as 32-bit ids. A column saved when the world was 128
## high comes back with WorldGenerator.LEGACY_VOLUME blocks (also from the
## oldest saves with one byte per block): the caller converts it
## (WorldGenerator.convert_legacy) and saves it again.
func load_column(column: Vector2i) -> PackedInt32Array:
	var file := FileAccess.open_compressed(_column_path(column), FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return PackedInt32Array()
	var data := file.get_buffer(WorldGenerator.COLUMN_VOLUME * 4)
	if data.size() == WorldGenerator.COLUMN_VOLUME * 4 or data.size() == WorldGenerator.LEGACY_VOLUME * 4:
		return data.to_int32_array()
	if data.size() == WorldGenerator.LEGACY_VOLUME:
		return PackedInt32Array(Array(data)) # the oldest saves: one byte per block
	return PackedInt32Array()


func save_column(column: Vector2i, blocks: PackedInt32Array) -> void:
	if remote:
		return
	var file := FileAccess.open_compressed(_column_path(column), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file:
		file.store_buffer(blocks.to_byte_array())
