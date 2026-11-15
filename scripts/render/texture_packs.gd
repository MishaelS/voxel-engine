class_name TexturePacks
extends RefCounted
## Texture packs like Minecraft Beta 1.7.3's, and more: a .zip (or a folder,
## unpacked; the files may sit in one folder inside it) in
## user://texturepacks/ with the jar's files at their places:
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
##   misc/grasscolor.png, misc/foliagecolor.png, misc/shadow.png,
##   misc/vignette.png, misc/water.png, terrain/sun.png, terrain/moon.png,
##   title/mclogo.png, title/mojang.png, title/splashes.txt.
## Beyond Beta's (README, "Texture pack layout"):
##   sounds/<group><n>.ogg|wav|mp3 (like assets/sounds: sounds/dig/stone1.ogg;
##   Beta's resources folder newsound/ too): a group a pack has is all its
##   own (Sounds); music/<name>.ogg|mp3 (music/dawn|day|night|menu/ for a
##   time; a game track of the same name is replaced); records/<disc>.ogg|mp3
##   (Beta's streaming/ too: the jukebox's discs, cat and 13);
##   title/logo.png (the whole logo, any size), title/intro.png (the
##   studio screen), title/background.png (a still picture behind the title
##   menu instead of the live world), title/bg/panorama0..5.png (a turning
##   cube panorama instead), title/shade.png (the shade over it),
##   gui/creative.png (the creative inventory).
## Any file a pack has replaces the game's; the rest stay. Pictures are
## used at Beta's sizes (BETA_SIZES; a bigger or smaller one is scaled to
## it), and parts of a file (the hotbar in gui.png, a heart in icons.png)
## are cut from it where Beta has them (region()).
##
## Several packs can be on at once (Options -> Texture Packs, the order
## in Settings.texture_packs): the first one's file wins, then the next
## one's, then the game's; so a small pack (only sounds, only the GUI) goes
## on top of a big one. The packs on are taken once (the first file asked
## for) and stay until the next start.
##
## The game's own textures (res://assets/textures/) are laid out the same,
## so they are the "Default" pack; pictures of the game's own that Beta has
## no file for (the creative inventory, the particle and chest atlases, the
## big title logo...) are in assets/textures/extra/; a pack changes those
## through EXTRA_FILES (the particle atlas takes a pack's particles.png
## pictures, the font is the game's own TTF unless a pack has
## font/default.png, title/mclogo.png and title/mojang.png stand for the
## logo and the intro).

const DIR := "user://texturepacks/"
const GAME_TEXTURES := "res://assets/textures/"
## The folder of the packs (tests point it elsewhere).
static var folder := DIR
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
	"art/kz.png": Vector2i(256, 256), "environment/rain.png": Vector2i(64, 256),
	"environment/snow.png": Vector2i(64, 256), "environment/clouds.png": Vector2i(256, 256),
	"misc/dial.png": Vector2i(16, 16), "misc/mapicons.png": Vector2i(32, 32), "misc/mapbg.png": Vector2i(128, 128),
	"misc/pumpkinblur.png": Vector2i(256, 256), "misc/grasscolor.png": Vector2i(256, 256),
	"misc/foliagecolor.png": Vector2i(256, 256), "misc/shadow.png": Vector2i(64, 64),
	"misc/vignette.png": Vector2i(256, 256), "misc/water.png": Vector2i(16, 16),
	"terrain/sun.png": Vector2i(32, 32),
	"terrain/moon.png": Vector2i(32, 32), "title/mclogo.png": Vector2i(256, 256),
	"title/mojang.png": Vector2i(256, 256),
}
## Mob and armor skins: 64 x 32 in Beta (the player's own 64 x 64 skins are
## widened from it, PlayerProfile.normalize_skin).
const SKIN_SIZE := Vector2i(64, 32)
## The game's own pictures (extra/) a pack can change, and the pack's file
## for each (used at its own size).
const EXTRA_FILES := {
	"extra/title_logo.png": "title/logo.png",
	"extra/title_intro.png": "title/intro.png",
	"extra/title_blur.png": "title/shade.png",
	"extra/creative.png": "gui/creative.png",
}
## Folders of a pack's sounds, music and discs (the first is the game's
## layout, the others Beta's resources folder's).
const SOUND_FOLDERS: Array[String] = ["sounds/", "newsound/", "sound/"]
const MUSIC_FOLDERS: Array[String] = ["music/"]
const RECORD_FOLDERS: Array[String] = ["records/", "streaming/"]
const AUDIO_EXTENSIONS: Array[String] = ["ogg", "wav", "mp3"]
## The folders a pack has at its top.
const PACK_FOLDERS: Array[String] = ["gui", "mob", "armor", "item", "art", "environment", "misc", "terrain",
	"title", "font", "achievement", "sounds", "newsound", "sound", "music", "records", "streaming"]

static var _cache := {}
static var _pack_files := {} # "pack:file" -> Image or null
static var _zips := {} # zip path -> ZIPReader
static var _indexes := {} # pack path -> {file in the pack -> where it is (zip entry or full path)}
static var _active := PackedStringArray()
static var _active_taken := false


## The packs there are: folders and .zip files (name -> path).
static func packs() -> Dictionary:
	var result := {}
	DirAccess.make_dir_recursive_absolute(folder)
	var dir := DirAccess.open(folder)
	if dir == null:
		return result
	for sub in dir.get_directories():
		result[sub] = folder.path_join(sub)
	for file in dir.get_files():
		if file.get_extension().to_lower() == "zip":
			result[file.get_basename()] = folder.path_join(file)
	return result


## The pack names, sorted.
static func names() -> PackedStringArray:
	var result := PackedStringArray(packs().keys())
	result.sort()
	return result


## The choices of the old one-pack setting: the game's own textures, then
## the packs (Settings moves it to the list).
static func choices() -> PackedStringArray:
	var result := PackedStringArray(["Default"])
	result.append_array(names())
	return result


## The packs on, first = wins (taken once: they stay until the next start).
static func active() -> PackedStringArray:
	if not _active_taken:
		_active_taken = true
		_active = PackedStringArray()
		var there := packs()
		var wanted: PackedStringArray = Settings.texture_packs if Settings else PackedStringArray()
		for pack in wanted:
			if there.has(pack) and not _active.has(pack):
				_active.append(pack)
	return _active


## Puts these packs on now (tests; the game takes them at the start):
## drops everything loaded from the packs before.
static func use_packs(list: PackedStringArray) -> void:
	_active = list.duplicate()
	_active_taken = true
	_cache.clear()
	_pack_files.clear()
	_indexes.clear()
	for zip: ZIPReader in _zips.values():
		zip.close()
	_zips.clear()


## The pack that wins ("" = the game's own textures).
static func current() -> String:
	var list := active()
	return list[0] if not list.is_empty() else ""


# --- A pack's files -----------------------------------------------------------------------

## Where each file of a pack is: {"terrain.png": entry or full path}. A pack
## zipped (or unpacked) with one folder around its files counts from
## inside it.
static func _index(pack_path: String) -> Dictionary:
	if _indexes.has(pack_path):
		return _indexes[pack_path]
	var all := PackedStringArray()
	if pack_path.get_extension().to_lower() == "zip":
		var zip := ZIPReader.new()
		if zip.open(pack_path) == OK:
			_zips[pack_path] = zip
			for entry in zip.get_files():
				if not entry.ends_with("/") and not entry.begins_with("__MACOSX/"):
					all.append(entry)
	else:
		_list_files(pack_path, "", all)
	# One folder around everything (and not a pack's own folder: a pack of
	# only gui/ files): from inside it.
	var prefix := ""
	if not all.is_empty() and all[0].contains("/") and not all[0].get_slice("/", 0) in PACK_FOLDERS:
		var first := all[0].get_slice("/", 0) + "/"
		if Array(all).all(func(f: String) -> bool: return f.begins_with(first)):
			prefix = first
	var index := {}
	for entry in all:
		var name := entry.trim_prefix(prefix)
		if name.get_file().begins_with("."):
			continue
		index[name] = entry if pack_path.get_extension().to_lower() == "zip" else pack_path.path_join(entry)
	_indexes[pack_path] = index
	return index


static func _list_files(root: String, sub: String, into: PackedStringArray) -> void:
	var dir := DirAccess.open(root.path_join(sub))
	if dir == null:
		return
	for file in dir.get_files():
		into.append(sub + file)
	for child in dir.get_directories():
		_list_files(root, sub + child + "/", into)


## The bytes of a file in a pack (folder or zip), or empty.
static func _read(pack_path: String, file: String) -> PackedByteArray:
	var where: String = _index(pack_path).get(file, "")
	if where == "":
		return PackedByteArray()
	if _zips.has(pack_path):
		return (_zips[pack_path] as ZIPReader).read_file(where)
	return FileAccess.get_file_as_bytes(where)


## Whether a pack has a file.
static func pack_has(pack: String, file: String) -> bool:
	var path: String = packs().get(pack, "")
	return path != "" and _index(path).has(file)


## The bytes of a file from the packs on (the first that has it), or empty.
static func read_file(file: String) -> PackedByteArray:
	for pack in active():
		if pack_has(pack, file):
			return _read(packs()[pack], file)
	return PackedByteArray()


## Whether a pack on has the file.
static func has_file(file: String) -> bool:
	for pack in active():
		if pack_has(pack, file):
			return true
	return false


## The files of one pack under a folder ("sounds/"): {path in the pack:
## path under the folder}.
static func files_in(pack: String, under: String) -> Dictionary:
	var result := {}
	var path: String = packs().get(pack, "")
	if path == "":
		return result
	for file: String in _index(path):
		if file.begins_with(under):
			result[file] = file.trim_prefix(under)
	return result


## A sound from a pack's file (Ogg Vorbis, WAV or MP3), or null.
static func audio_stream(pack: String, file: String) -> AudioStream:
	var path: String = packs().get(pack, "")
	var bytes := _read(path, file) if path != "" else PackedByteArray()
	if bytes.is_empty():
		return null
	match file.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(bytes)
		"wav":
			return AudioStreamWAV.load_from_buffer(bytes)
		"mp3":
			var mp3 := AudioStreamMP3.new()
			mp3.data = bytes
			return mp3 if mp3.get_length() > 0.0 else null
	return null


## A text file from the packs on (title/splashes.txt), or "".
static func read_text(file: String) -> String:
	return read_file(file).get_string_from_utf8()


static func _image_from(bytes: PackedByteArray) -> Image:
	if bytes.is_empty():
		return null
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image


## The picture the packs on (or only `pack`) have for a file, at Beta's
## size, or null.
static func pack_image(file: String, pack := "") -> Image:
	if pack == "":
		for name in active():
			var image := pack_image(file, name)
			if image:
				return image
		return null
	var key := pack + ":" + file
	if not _pack_files.has(key):
		var path: String = packs().get(pack, "")
		var image := _image_from(_read(path, file)) if path != "" else null
		if image:
			var size: Vector2i = BETA_SIZES.get(file, SKIN_SIZE if file.begins_with("mob/") or file.begins_with("armor/") else image.get_size())
			if file == "mob/char.png" and image.get_size() == Vector2i(64, 64):
				size = image.get_size() # (a newer 64 x 64 skin: as it is)
			if image.get_size() != size:
				image.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
		elif path != "" and _index(path).has(file):
			push_warning("Texture pack %s: %s is not a PNG picture" % [pack, file])
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
	if file.begins_with("extra/") and EXTRA_FILES.has(file) and has_file(EXTRA_FILES[file]):
		file = EXTRA_FILES[file] # (a pack's picture for one of the game's own)
	elif not path.begins_with(GAME_TEXTURES) or file.begins_with("extra/"):
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
