class_name PlayerProfile
extends RefCounted
## The player's own look ("Player Settings"): the name (Net.player_name), the
## name's color and the skin. Kept in user://player.cfg; a skin chosen from a
## file is copied to user://skins/custom.png. Others in a network game see
## them too (Net sends the color and the skin).
##
## Skins: 64 x 64 (the modern layout) or 64 x 32 (the classic one; widened
## to 64 x 64 like the game does: the left arm and leg copied from the right
## ones, so the model's UVs fit both).

const CONFIG_PATH := "user://player.cfg"
const SKIN_PATH := "user://skins/custom.png"
## Name colors like the game's chat colors; the last one is a rainbow.
const COLORS: Array[Array] = [
	["White", Color("ffffff")], ["Yellow", Color("ffff55")], ["Gold", Color("ffaa00")],
	["Red", Color("ff5555")], ["Pink", Color("ff55ff")], ["Purple", Color("aa00aa")],
	["Blue", Color("5555ff")], ["Aqua", Color("55ffff")], ["Green", Color("55ff55")],
	["Gray", Color("aaaaaa")], ["Rainbow", Color.WHITE],
]
const RAINBOW := 10

static var name_color := 0
## A random secret made once when the computer gives no id of its own.
static var _fallback_secret := ""
## Mixed into the computer's id before hashing (so the hash is this game's own).
## Kept from the game's old name (Bedrock Edition): a new one would give
## every player a new id, and servers would no longer know them.
const APP_SALT := "voxel-engine-bedrock-edition/player"
## The custom skin (null: the default one).
static var skin: ImageTexture
static var _loaded := false


static func load_profile() -> void:
	if _loaded:
		return
	_loaded = true
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)
	name_color = clampi(int(config.get_value("player", "name_color", 0)), 0, COLORS.size() - 1)
	_fallback_secret = config.get_value("player", "secret", "")
	if FileAccess.file_exists(SKIN_PATH):
		var image := Image.load_from_file(ProjectSettings.globalize_path(SKIN_PATH))
		if image and normalize_skin(image) == "":
			skin = ImageTexture.create_from_image(image)
	MobModels.set_skin("player", skin)


static func save_profile() -> void:
	var config := ConfigFile.new()
	config.set_value("player", "name_color", name_color)
	if _fallback_secret != "":
		config.set_value("player", "secret", _fallback_secret)
	config.save(CONFIG_PATH)


# --- The player's tag (servers tell players apart) ----------------------------------------

## This computer's secret: its id (OS.get_unique_id: the hardware's own on
## macOS and Windows) hashed with the game's salt. Never sent anywhere.
static func _device_secret() -> String:
	var device := OS.get_unique_id()
	if device == "":
		if _fallback_secret == "":
			var crypto := Crypto.new()
			_fallback_secret = crypto.generate_random_bytes(32).hex_encode()
			save_profile()
		device = _fallback_secret
	return (APP_SALT + "|" + device).sha256_text()


## What this player shows a server: the secret hashed with that server's own
## salt. The same every time on one server (so it can ban it), different on
## every other one (so servers can't follow a player between them), and
## nothing about the computer can be got back from it.
static func tag_for_server(server_salt: String) -> String:
	return (_device_secret() + "|" + server_salt).sha256_text()


## The color of a name with color `index` now (the rainbow goes round).
static func color_of(index: int, offset: float = 0.0) -> Color:
	if index == RAINBOW:
		return Color.from_hsv(fmod(Time.get_ticks_msec() / 3000.0 + offset, 1.0), 0.6, 1.0)
	return COLORS[clampi(index, 0, COLORS.size() - 1)][1]


## A name for the chat (BBCode): in its color, a rainbow letter by letter.
static func bbcode_name(player_name: String, index: int, alpha: float = 1.0) -> String:
	var text := player_name.replace("[", "[lb]")
	if index != RAINBOW:
		var color := color_of(index)
		color.a = alpha
		return "[color=#%s]%s[/color]" % [color.to_html(true), text]
	var result := ""
	for i in player_name.length():
		var hue := Color.from_hsv(float(i) / maxf(player_name.length(), 1.0), 0.6, 1.0, alpha)
		result += "[color=#%s]%s[/color]" % [hue.to_html(true), player_name[i].replace("[", "[lb]")]
	return result


## Makes a skin image fit the model: RGBA, 64 x 64 (a classic 64 x 32 one
## widened). Returns an error text, or "".
static func normalize_skin(image: Image) -> String:
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	if image.get_size() == Vector2i(64, 64):
		return ""
	if image.get_size() != Vector2i(64, 32):
		return "A skin must be 64 x 64 or 64 x 32 pixels"
	var wide := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	wide.blit_rect(image, Rect2i(0, 0, 64, 32), Vector2i.ZERO)
	# The classic layout has one arm and one leg: the left ones are copies.
	wide.blit_rect(image, Rect2i(0, 16, 16, 16), Vector2i(16, 48)) # leg
	wide.blit_rect(image, Rect2i(40, 16, 16, 16), Vector2i(32, 48)) # arm
	image.copy_from(wide)
	return ""


## Takes a skin from a PNG file. Returns an error text, or "".
static func load_skin_file(path: String) -> String:
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return "Not a picture"
	var error := normalize_skin(image)
	if error != "":
		return error
	DirAccess.make_dir_recursive_absolute(SKIN_PATH.get_base_dir())
	image.save_png(SKIN_PATH)
	skin = ImageTexture.create_from_image(image)
	MobModels.set_skin("player", skin)
	Net.send_look()
	return ""


static func reset_skin() -> void:
	if FileAccess.file_exists(SKIN_PATH):
		DirAccess.remove_absolute(SKIN_PATH)
	skin = null
	MobModels.set_skin("player", null)
	Net.send_look()


## The skin to show (custom or default).
static func skin_texture() -> Texture2D:
	return skin if skin else MobModels.skin_texture("player")


## The skin as PNG bytes for the network (empty: the default skin).
static func skin_png() -> PackedByteArray:
	return skin.get_image().save_png_to_buffer() if skin else PackedByteArray()


## A skin received from another player (PNG bytes), or null (default).
static func skin_from_png(data: PackedByteArray) -> ImageTexture:
	if data.is_empty() or data.size() > 64 * 1024:
		return null
	var image := Image.new()
	if image.load_png_from_buffer(data) != OK or normalize_skin(image) != "":
		return null
	return ImageTexture.create_from_image(image)
