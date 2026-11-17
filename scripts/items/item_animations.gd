class_name ItemAnimations
extends Node
## Animated item icons like the classic game (TextureCompassFX,
## TextureWatchFX), drawn into the shared item atlas (Items.icons_texture())
## so they move in the inventory, in hand and on the ground:
## - the compass needle points to the spawn point, turning with the
##   player's view and swinging a little before it settles;
## - the clock shows its dial (assets/textures/misc/dial.png) turned by the
##   time of day behind the icon's window (the magenta pixels of its icon):
##   the sun at the top at noon, the moon at midnight.

const COMPASS_TILE := 54
const CLOCK_TILE := 70
const DIAL_PATH := "res://assets/textures/misc/dial.png"

var player: Player

var _compass_base: Image
var _clock_base: Image
var _dial: Image
var _needle := 0.0
var _needle_speed := 0.0
var _dial_angle := 0.0
var _dial_speed := 0.0
var _last_tick := -1
## What the icons showed last (uploaded only when one changed: the whole
## item atlas went to the graphics card 20 times a second).
var _compass_shown := PackedByteArray()
var _clock_shown := PackedByteArray()
## The angles the icons were last drawn at (drawn again only when they
## turned enough to move a pixel: a still needle cost a frame's time).
var _compass_drawn := INF
var _clock_drawn := INF
var _compass_image: Image
var _clock_image: Image


func _ready() -> void:
	var atlas := Items.icons_image()
	_compass_base = _tile(atlas, COMPASS_TILE)
	_clock_base = _tile(atlas, CLOCK_TILE)
	_dial = TexturePacks.load_texture(DIAL_PATH).get_image()
	if _dial.is_compressed():
		_dial.decompress()
	_dial.convert(Image.FORMAT_RGBA8)


static func _tile(atlas: Image, tile: int) -> Image:
	return atlas.get_region(Rect2i((tile % 16) * 16, (tile / 16) * 16, 16, 16))


func _process(_delta: float) -> void:
	# Once per game tick, like the game's texture effects.
	var tick := int(Time.get_ticks_msec() / 50)
	if tick == _last_tick or player == null:
		return
	_last_tick = tick
	_turn_needles()
	if absf(_needle - _compass_drawn) > 0.01 or _compass_image == null:
		_compass_drawn = _needle
		_compass_image = _draw_compass()
	if absf(_dial_angle - _clock_drawn) > 0.005 or _clock_image == null:
		_clock_drawn = _dial_angle
		_clock_image = _draw_clock()
	var compass := _compass_image
	var clock := _clock_image
	if compass.get_data() == _compass_shown and clock.get_data() == _clock_shown:
		return
	var atlas := Items.icons_image()
	_compass_shown = compass.get_data()
	_clock_shown = clock.get_data()
	atlas.blit_rect(compass, Rect2i(0, 0, 16, 16), Vector2i((COMPASS_TILE % 16) * 16, (COMPASS_TILE / 16) * 16))
	atlas.blit_rect(clock, Rect2i(0, 0, 16, 16), Vector2i((CLOCK_TILE % 16) * 16, (CLOCK_TILE / 16) * 16))
	Items.icons_texture().update(atlas)


## The needle: the angle from where the player looks to the spawn point
## (clockwise), reached with the classic springy swing.
func _turn_needles() -> void:
	var target := 0.0
	var spawn := player.spawn_position()
	var to_spawn := Vector2(spawn.x - player.global_position.x, spawn.z - player.global_position.z)
	if to_spawn.length_squared() > 1e-4:
		var look := player.look_direction()
		var forward := Vector2(look.x, look.z).normalized()
		var right := Vector2(-forward.y, forward.x)
		target = atan2(to_spawn.dot(right), to_spawn.dot(forward))
	var difference := wrapf(target - _needle, -PI, PI)
	_needle_speed = (_needle_speed + clampf(difference, -1.0, 1.0) * 0.1) * 0.8
	_needle += _needle_speed
	var dial_target := 0.0
	if player.world:
		dial_target = -DayNightCycle.angle_at(player.world.clock.time_of_day()) * TAU # 0 at noon
	var dial_difference := wrapf(dial_target - _dial_angle, -PI, PI)
	_dial_speed = (_dial_speed + clampf(dial_difference, -1.0, 1.0) * 0.1) * 0.8
	_dial_angle += _dial_speed


func _draw_compass() -> Image:
	var image := _compass_base.duplicate() as Image
	var s := sin(_needle)
	var c := cos(_needle)
	for i in range(-4, 5):
		image.set_pixel(int(8.5 + c * i * 0.3), int(7.5 - s * i * 0.3 * 0.5), Color8(100, 100, 100))
	for i in range(-8, 17):
		var color := Color8(255, 20, 20) if i >= 0 else Color8(100, 100, 100)
		image.set_pixel(int(8.5 + s * i * 0.3), int(7.5 - c * i * 0.3 * 0.5), color)
	return image


## The dial behind the window, turned so the sun is on top at noon.
func _draw_clock() -> Image:
	var image := _clock_base.duplicate() as Image
	var s := sin(_dial_angle)
	var c := cos(_dial_angle)
	for y in 16:
		for x in 16:
			var pixel := _clock_base.get_pixel(x, y)
			if pixel.a == 0.0 or pixel.g8 != 0 or pixel.r8 != pixel.b8 or pixel.b8 == 0:
				continue
			var dx := -(x / 15.0 - 0.5)
			var dy := y / 15.0 - 0.5
			var u := int((dx * c + dy * s + 0.5) * 16.0) & 15
			var v := int((dy * c - dx * s + 0.5) * 16.0) & 15
			var shade := pixel.r
			var dial := _dial.get_pixel(u, v)
			image.set_pixel(x, y, Color(dial.r * shade, dial.g * shade, dial.b * shade, 1.0))
	return image
