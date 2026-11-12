class_name StatusBars
extends Control
## Health and armor above the hotbar in survival, like Beta 1.7.3 (no
## hunger): 10 hearts on the left, the armor bar (Player.armor_value(), 10
## chestplates, filled from the right) on the right while armor is worn,
## air bubbles above the hearts under water. Hearts blink when the player
## is hurt and jitter at low health (4 half hearts or less).
## Hidden in creative.

const P := UiTheme.PIXEL
const ICONS := 10
const STEP := 8 * P ## icons overlap by one pixel
const ICON := 9 * P
const WIDTH := 182 * P
const LOW_HEALTH := 4
const ICONS_PATH := "res://assets/textures/icons.png"

@export var player: Player

var _heart_full: Texture2D
var _heart_half: Texture2D
var _heart_empty: Texture2D
var _heart_blink: Texture2D
var _armor_full: Texture2D
var _armor_half: Texture2D
var _armor_empty: Texture2D
var _bubble: Texture2D
var _bubble_pop: Texture2D
var _heart_jitter := PackedInt32Array()
var _shown := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The game's icons.png: 9 x 9 icons at their places in it.
	var icons := TexturePacks.load_texture(ICONS_PATH).get_image()
	if icons.is_compressed():
		icons.decompress()
	_heart_empty = _icon(icons, 16, 0)
	_heart_blink = _icon(icons, 25, 0)
	_heart_full = _icon(icons, 52, 0)
	_heart_half = _icon(icons, 61, 0)
	_armor_empty = _icon(icons, 16, 9)
	_armor_half = _icon(icons, 25, 9)
	_armor_full = _icon(icons, 34, 9)
	_bubble = _icon(icons, 16, 18)
	_bubble_pop = _icon(icons, 25, 18)
	# Over the hotbar, 40 pixels above the bottom (the classic place).
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -91 * P
	offset_right = 91 * P
	offset_top = -33 * P # right above the hotbar, like the classic game
	offset_bottom = -23 * P
	_heart_jitter.resize(ICONS)


func _process(_delta: float) -> void:
	visible = player != null and not player.is_creative() and not Screenshots.hud_off
	if not visible:
		return
	var low := player.health <= LOW_HEALTH and not player.dead
	for i in ICONS:
		_heart_jitter[i] = randi() % 2 if low else 0
	# Redraw only when something visible changed.
	var state := "%d %s %s %d %s" % [player.health, _blinking(), _heart_jitter, player.armor_value(), _bubbles()]
	if state != _shown:
		_shown = state
		queue_redraw()


func _blinking() -> bool:
	return player.hurt_ticks > 0 and (player.hurt_ticks / 3) % 2 == 1


func _draw() -> void:
	var tint := Color.WHITE
	for i in ICONS:
		var position := Vector2(i * STEP, _heart_jitter[i] * P)
		draw_texture(_heart_blink if _blinking() else _heart_empty, position, tint)
		_draw_level(player.health - i * 2, position, _heart_full, _heart_half, tint)
	var armor := player.armor_value()
	if armor > 0:
		for i in ICONS:
			var position := Vector2(WIDTH - ICON - i * STEP, 0)
			draw_texture(_armor_empty, position)
			_draw_level(armor - i * 2, position, _armor_full, _armor_half, Color.WHITE)
	# Air bubbles above the hearts under water, like the classic game.
	var bubbles := _bubbles()
	for i in bubbles.x + bubbles.y:
		draw_texture(_bubble if i < bubbles.x else _bubble_pop, Vector2(i * STEP, -10 * P))


## [full, popping] bubbles while under water (none otherwise).
func _bubbles() -> Vector2i:
	if player.dead or not player.eyes_in_water():
		return Vector2i.ZERO
	var full := ceili((player.air - 2) * 10.0 / Player.MAX_AIR)
	var popping := ceili(player.air * 10.0 / Player.MAX_AIR) - full
	return Vector2i(maxi(full, 0), maxi(popping, 0))


## Full icon for 2+ points left, half for 1.
## One 9 x 9 icon of icons.png, scaled like the rest of the GUI.
static func _icon(icons: Image, x: int, y: int) -> ImageTexture:
	var image := icons.get_region(Rect2i(x, y, 9, 9))
	image.convert(Image.FORMAT_RGBA8)
	image.resize(9 * P, 9 * P, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(image)


func _draw_level(points: int, position: Vector2, full: Texture2D, half: Texture2D, tint: Color) -> void:
	if points >= 2:
		draw_texture(full, position, tint)
	elif points == 1:
		draw_texture(half, position, tint)
