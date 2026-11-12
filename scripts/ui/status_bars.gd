class_name StatusBars
extends Control
## Health and hunger above the hotbar in survival, like the classic game:
## 10 hearts on the left, 10 drumsticks on the right (filled from the
## right). Hearts blink when the player is hurt and jitter at low health
## (4 half hearts or less); drumsticks jitter when saturation is gone.
## The armor bar (Player.armor_value(), 10 chestplates) sits above the
## hearts while armor is worn.
## Hidden in creative.

const P := UiTheme.PIXEL
const ICONS := 10
const STEP := 8 * P ## icons overlap by one pixel
const ICON := 9 * P
const WIDTH := 182 * P
const LOW_HEALTH := 4

@export var player: Player

var _heart_full: Texture2D
var _heart_half: Texture2D
var _heart_empty: Texture2D
var _food_full: Texture2D
var _food_half: Texture2D
var _food_empty: Texture2D
var _armor_full: Texture2D
var _armor_half: Texture2D
var _armor_empty: Texture2D
var _bubble: Texture2D
var _bubble_pop: Texture2D
var _heart_jitter := PackedInt32Array()
var _food_jitter := PackedInt32Array()
var _shown := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heart_full = UiTheme.gui_texture("hearts/heart0.png")
	_heart_half = UiTheme.gui_texture("hearts/heart1.png")
	_heart_empty = UiTheme.gui_texture("hearts/heart2.png")
	_food_full = UiTheme.gui_texture("hunger/hunger0.png")
	_food_half = UiTheme.gui_texture("hunger/hunger1.png")
	_food_empty = UiTheme.gui_texture("hunger/hunger2.png")
	_armor_full = UiTheme.gui_texture("armor/armor0.png")
	_armor_half = UiTheme.gui_texture("armor/armor1.png")
	_armor_empty = UiTheme.gui_texture("armor/armor2.png")
	_bubble = UiTheme.gui_texture("bubble/bubble0.png")
	_bubble_pop = UiTheme.gui_texture("bubble/bubble1.png")
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
	_food_jitter.resize(ICONS)


func _process(_delta: float) -> void:
	visible = player != null and not player.is_creative() and not Screenshots.hud_off
	if not visible:
		return
	var low := player.health <= LOW_HEALTH and not player.dead
	var hungry := player.food.saturation <= 0.0 and not player.dead
	for i in ICONS:
		_heart_jitter[i] = randi() % 2 if low else 0
		_food_jitter[i] = (randi() % 2 if randf() < 0.15 else 0) if hungry else 0
	# Redraw only when something visible changed.
	var state := "%d %d %s %s %s %s %d %s" % [player.health, player.food.food, _blinking(), _heart_jitter, _food_jitter, _hunger(),
		player.armor_value(), _bubbles()]
	if state != _shown:
		_shown = state
		queue_redraw()


## The food bar shows only with hunger on (the doHunger game rule).
func _hunger() -> bool:
	return player.world == null or player.world.hunger


func _blinking() -> bool:
	return player.hurt_ticks > 0 and (player.hurt_ticks / 3) % 2 == 1


func _draw() -> void:
	var tint := Color(1.8, 1.8, 1.8) if _blinking() else Color.WHITE
	for i in ICONS:
		var position := Vector2(i * STEP, _heart_jitter[i] * P)
		draw_texture(_heart_empty, position, tint)
		_draw_level(player.health - i * 2, position, _heart_full, _heart_half, tint)
	var armor := player.armor_value()
	if armor > 0:
		for i in ICONS:
			var position := Vector2(i * STEP, -10 * P)
			draw_texture(_armor_empty, position)
			_draw_level(armor - i * 2, position, _armor_full, _armor_half, Color.WHITE)
	# Air bubbles above the food bar under water, like the classic game.
	var bubbles := _bubbles()
	for i in bubbles.x + bubbles.y:
		var position := Vector2(WIDTH - ICON - i * STEP, -10 * P)
		draw_texture(_bubble if i < bubbles.x else _bubble_pop, position)
	if not _hunger():
		return
	for i in ICONS:
		var position := Vector2(WIDTH - ICON - i * STEP, _food_jitter[i] * P)
		draw_texture(_food_empty, position)
		_draw_level(player.food.food - i * 2, position, _food_full, _food_half, Color.WHITE)


## [full, popping] bubbles while under water (none otherwise).
func _bubbles() -> Vector2i:
	if player.dead or not player.eyes_in_water():
		return Vector2i.ZERO
	var full := ceili((player.air - 2) * 10.0 / Player.MAX_AIR)
	var popping := ceili(player.air * 10.0 / Player.MAX_AIR) - full
	return Vector2i(maxi(full, 0), maxi(popping, 0))


## Full icon for 2+ points left, half for 1.
func _draw_level(points: int, position: Vector2, full: Texture2D, half: Texture2D, tint: Color) -> void:
	if points >= 2:
		draw_texture(full, position, tint)
	elif points == 1:
		draw_texture(half, position, tint)
