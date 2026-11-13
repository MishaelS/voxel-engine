class_name TexturePacks
extends RefCounted
## Texture packs exactly like Minecraft Beta 1.7.3's: a .zip (or a folder,
## unpacked) in user://texturepacks/ with the jar's files at their places:
##   pack.txt (two lines about it), pack.png (its picture), terrain.png,
##   particles.png, font/default.png (its letters; others from the game's
##   font), gui/gui.png, gui/icons.png, gui/items.png,
##   gui/background.png, gui/inventory.png, gui/crafting.png,
##   gui/furnace.png, gui/container.png, gui/trap.png, gui/unknown_pack.png,
##   mob/*.png (char, zombie, skeleton, creeper, spider, pig, saddle, cow,
##   sheep, sheep_fur, chicken, squid, slime, wolf, wolf_tame, wolf_angry),
##   armor/<cloth|chain|iron|gold|diamond>_<1|2>.png, item/arrows.png,
##   item/boat.png, item/cart.png, art/kz.png, environment/rain.png,
##   environment/snow.png, environment/clouds.png, misc/dial.png,
##   misc/mapbg.png, misc/mapicons.png, misc/pumpkinblur.png,
##   misc/grasscolor.png, misc/foliagecolor.png, terrain/sun.png,
##   terrain/moon.png, title/mclogo.png, title/mojang.png.
## Any file a pack has replaces the game's; the rest stay. Pictures are
## used at Beta's sizes (BETA_SIZES; a bigger or smaller one is scaled to
## it), and parts of a file (the hotbar in gui.png, a heart in icons.png)
## are cut from it where Beta has them (region()).
##
## The game's own textures (res://assets/textures/) are laid out the same,
## so they are the "Default" pack; pictures of the game's own that Beta has
## no file for (the creative inventory, the particle and chest atlases, the
## big title logo...) are in assets/textures/extra/ and no pack changes
## them (the particle atlas takes a pack's particles.png pictures, the
## font is the game's own TTF unless a pack has font/default.png), except where a Beta file stands for them (title/mclogo.png for the
## logo, title/mojang.png for the intro).
##
## Picked in Options -> Texture Packs (the "texture_pack" setting), used
## from the next start.

const DIR := "user://texturepacks/"
const GAME_TEXTURES := "res://assets/textures/"
## Beta 1.7.3's sizes of its files (a pack's picture of another size is
## scaled to it); files not listed: the game's own size.
const BETA_SIZES := {
	"terrain.png": Vector2i(256, 256), "particles.png": Vector2i(128, 128), "pack.png": Vector2i(64, 64),
	"font/default.png": Vector2i(128, 128),
	"gui/gui.png": Vector2i(256, 256), "gui/icons.png": Vector2i(256, 256), "gui/items.png": Vector2i(256, 256),
	"gui/background.png": Vector2i(16, 16), "gui/inventory.png": Vector2i(256, 256),
	"gui/crafting.png": Vector2i(256, 256), "gui/furnace.png": Vector2i(256, 256),
	"gui/container.png": Vector2i(256, 256), "gui/trap.png": Vector2i(256, 256),
	"gui/unknown_pack.png": Vector2i(64, 64),
	"item/arrows.png": Vector2i(32, 32), "item/boat.png": Vector2i(64, 32), "item/cart.png": Vector2i(64, 32),
	"art/kz.png": Vector2i(256, 256), "environment/rain.png": Vector2i(64, 64),
	"environment/snow.png": Vector2i(64, 64), "environment/clouds.png": Vector2i(256, 256),
	"misc/dial.png": Vector2i(16, 16), "misc/mapicons.png": Vector2i(32, 32), "misc/mapbg.png": Vector2i(128, 128),
	"misc/pumpkinblur.png": Vector2i(256, 256), "misc/grasscolor.png": Vector2i(256, 256),
	"misc/foliagecolor.png": Vector2i(256, 256), "terrain/sun.png": Vector2i(32, 32),
	"terrain/moon.png": Vector2i(32, 32), "title/mclogo.png": Vector2i(256, 256),
	"title/mojang.png": Vector2i(256, 256),
}
## Mob and armor skins: 64 x 32 in Beta (the player's own 64 x 64 skins are
## widened from it, PlayerProfile.normalize_skin).
const SKIN_SIZE := Vector2i(64, 32)

static var _cache := {}
static var _pack_files := {} # (relative path -> Image or null) of the pack in use
static var _zip: ZIPReader
static var _opened := ""


## The packs there are: folders and .zip files (name -> path).
static func packs() -> Dictionary:
	var result := {}
	DirAccess.make_dir_recursive_absolute(DIR)
	var dir := DirAccess.open(DIR)
	if dir == null:
		return result
	for folder in dir.get_directories():
		result[folder] = DIR + folder
	for file in dir.get_files():
		if file.get_extension().to_lower() == "zip":
			result[file.get_basename()] = DIR + file
	return result


## The pack names, sorted.
static func names() -> PackedStringArray:
	var result := PackedStringArray(packs().keys())
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


# --- A pack's files -----------------------------------------------------------------------

## The bytes of a file in a pack (folder or zip), or empty.
static func _read(pack_path: String, file: String) -> PackedByteArray:
	if pack_path.get_extension().to_lower() == "zip":
		if _opened != pack_path:
			if _zip:
				_zip.close()
			_zip = ZIPReader.new()
			_opened = pack_path if _zip.open(pack_path) == OK else ""
			if _opened == "":
				_zip = null
		if _zip == null:
			return PackedByteArray()
		# Some packs are zipped with a folder around the files.
		for candidate in [file] + Array(_zip.get_files()).filter(func(f: String) -> bool: return f.ends_with("/" + file)):
			if _zip.file_exists(candidate):
				return _zip.read_file(candidate)
		return PackedByteArray()
	var full := pack_path.path_join(file)
	return FileAccess.get_file_as_bytes(full) if FileAccess.file_exists(full) else PackedByteArray()


static func _image_from(bytes: PackedByteArray) -> Image:
	if bytes.is_empty():
		return null
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image


## The picture a pack (the one in use, or `pack`) has for a Beta file, at
## Beta's size, or null.
static func pack_image(file: String, pack := "") -> Image:
	var name := pack if pack != "" else current()
	if name == "":
		return null
	var key := name + ":" + file
	if not _pack_files.has(key):
		var path: String = packs().get(name, "")
		var image := _image_from(_read(path, file)) if path != "" else null
		if image:
			var size: Vector2i = BETA_SIZES.get(file, SKIN_SIZE if file.begins_with("mob/") or file.begins_with("armor/") else image.get_size())
			if file == "mob/char.png" and image.get_size() == Vector2i(64, 64):
				size = image.get_size() # (a newer 64 x 64 skin: as it is)
			if image.get_size() != size:
				image.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
		_pack_files[key] = image
	return _pack_files[key]


## A pack's pack.txt (its two lines), or "".
static func description(pack: String) -> String:
	var path: String = packs().get(pack, "")
	if path == "":
		return ""
	var text := _read(path, "pack.txt").get_string_from_utf8().strip_edges()
	var lines := text.split("\n")
	return "\n".join(lines.slice(0, 2)).strip_edges()


## A pack's picture (pack.png, or gui/unknown_pack.png), as a texture.
static func icon(pack: String) -> Texture2D:
	var image := pack_image("pack.png", pack) if pack != "" else null
	if image:
		return ImageTexture.create_from_image(image)
	if pack == "":
		return load(GAME_TEXTURES + "pack.png")
	return load_texture(GAME_TEXTURES + "gui/unknown_pack.png")


# --- Textures the game uses ---------------------------------------------------------------

## Tiles of terrain.png the game has blocks for and Beta 1.7.3 had not
## (spruce and birch planks): where a terrain.png has nothing there (empty,
## or the "missing" checkers), the game's own from extra/terrain_extra.png.
const GAME_TILES: Array[int] = [198, 214]
const TERRAIN_EXTRA := "res://assets/textures/extra/terrain_extra.png"


## A texture: the pack's if it has the file, else the game's.
## `path`: res://assets/textures/<Beta file>, or extra/... (the game's own).
static func load_texture(path: String) -> Texture2D:
	var file := path.trim_prefix(GAME_TEXTURES)
	if not path.begins_with(GAME_TEXTURES) or file.begins_with("extra/"):
		return load(path) as Texture2D
	if file == "terrain.png":
		if not _cache.has(file):
			_cache[file] = ImageTexture.create_from_image(_terrain_with_game_tiles())
		return _cache[file]
	var image := pack_image(file)
	if image == null:
		return load(path) as Texture2D
	if not _cache.has(file):
		_cache[file] = ImageTexture.create_from_image(image)
	return _cache[file]


## terrain.png (the pack's or the game's) with GAME_TILES filled in where
## it has nothing.
static func _terrain_with_game_tiles() -> Image:
	var image := pack_image("terrain.png")
	if image == null:
		image = (load(GAME_TEXTURES + "terrain.png") as Texture2D).get_image()
		if image.is_compressed():
			image.decompress()
		image.convert(Image.FORMAT_RGBA8)
	else:
		image = image.duplicate()
	var extra := (load(TERRAIN_EXTRA) as Texture2D).get_image()
	if extra.is_compressed():
		extra.decompress()
	extra.convert(Image.FORMAT_RGBA8)
	var size := image.get_width() / 16
	if extra.get_width() != image.get_width():
		extra.resize(image.get_width(), image.get_height(), Image.INTERPOLATE_NEAREST)
	for tile in GAME_TILES:
		var rect := Rect2i((tile % 16) * size, (tile / 16) * size, size, size)
		if _is_missing(image.get_region(rect)):
			image.blit_rect(extra, rect, rect.position)
	return image


## Nothing drawn: all transparent, or two colors only (the "missing" checkers).
static func _is_missing(tile: Image) -> bool:
	if tile.is_invisible():
		return true
	var colors := {}
	for y in tile.get_height():
		for x in tile.get_width():
			colors[tile.get_pixel(x, y)] = true
			if colors.size() > 2:
				return false
	return true


## The game's own texture, whatever the pack (the player list's signal bars
## in its icons.png, which Beta's has no place for).
static func default_texture(path: String) -> Texture2D:
	return load(path) as Texture2D


## The picture of a texture (uncompressed RGBA8).
static func load_image(path: String) -> Image:
	var image := load_texture(path).get_image()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image


## A part of a Beta file (the hotbar in gui/gui.png...), in its pixels.
static func region(file: String, rect: Rect2i) -> Image:
	return load_image(GAME_TEXTURES + file).get_region(rect)


## Parts of a Beta file put together: [[source rect, place], ...] on a
## picture of `size` (Beta draws some pictures in pieces: the small chest
## from container.png, the slider knob from a button).
static func pieces(file: String, size: Vector2i, parts: Array) -> Image:
	var source := load_image(GAME_TEXTURES + file)
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	for part: Array in parts:
		image.blit_rect(source, part[0], part[1])
	return image
