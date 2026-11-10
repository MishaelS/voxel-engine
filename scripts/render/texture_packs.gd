class_name TexturePacks
extends RefCounted
## Texture packs like the classic game: folders in user://texturepacks/,
## each laid out like assets/textures (terrain.png, items.png,
## mobs/zombie.png, gui/..., environment/rain.png...). Any file a pack has
## replaces the game's own; the rest stay. Picked in Options -> Texture
## Packs (the "texture_pack" setting), used from the next start.
## Code loads textures through load_texture() / load_image().

const DIR := "user://texturepacks/"
const GAME_TEXTURES := "res://assets/textures/"

static var _cache := {}


## The pack folders there are.
static func names() -> PackedStringArray:
	var result := PackedStringArray()
	DirAccess.make_dir_recursive_absolute(DIR)
	var dir := DirAccess.open(DIR)
	if dir == null:
		return result
	for folder in dir.get_directories():
		result.append(folder)
	result.sort()
	return result


## The choices of the setting: the game's own textures, then the packs.
static func choices() -> PackedStringArray:
	var result := PackedStringArray(["Default"])
	result.append_array(names())
	return result


## The pack in use ("" = the game's own textures).
static func current() -> String:
	var index: Variant = Settings.get_value("texture_pack") if Settings else 0
	var all := choices()
	if index == null or int(index) <= 0 or int(index) >= all.size():
		return ""
	return all[int(index)]


## The pack's file standing in for a game texture, or "".
static func _pack_file(path: String) -> String:
	var pack := current()
	if pack == "" or not path.begins_with(GAME_TEXTURES):
		return ""
	var file := DIR + pack + "/" + path.trim_prefix(GAME_TEXTURES)
	return file if FileAccess.file_exists(file) else ""


## A texture: the pack's if it has one, else the game's.
static func load_texture(path: String) -> Texture2D:
	var file := _pack_file(path)
	if file == "":
		return load(path) as Texture2D
	if not _cache.has(file):
		var image := Image.load_from_file(file)
		_cache[file] = ImageTexture.create_from_image(image) if image else load(path)
	return _cache[file]


## The picture of a texture (uncompressed RGBA8).
static func load_image(path: String) -> Image:
	var image := load_texture(path).get_image()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image
