class_name MapView
extends Control
## The map in hand, like the classic game: while the player holds a map it
## is shown in the lower middle of the screen on parchment, with an arrow
## where the player is, pointing where they look; meanwhile it fills in
## around them (Maps.update). A map that has no number yet gets one, drawn
## around where it is first held.

const P := UiTheme.PIXEL

var player: Player

var _texture: ImageTexture
var _background: Texture2D
var _number := -1
var _last_tick := -1
var _dirty := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background = load("res://assets/textures/misc/map_background.png")


func _process(_delta: float) -> void:
	var world := player.world if player else null
	var holding := world != null and not player.dead and Items.name_of(player.held_block()) == "map" \
		and not GameInput.is_blocked()
	visible = holding and not player.third_person
	if not holding:
		_number = -1
		return
	var slot := player.selected_slot
	var number := player.inventory.damage_at(slot)
	if number == 0:
		number = Maps.create(world, player.global_position)
		player.inventory.set_slot(slot, player.inventory.id_at(slot), 1, number)
	if number != _number:
		_number = number
		_dirty = true
	var tick := int(Time.get_ticks_msec() / 50)
	if tick != _last_tick:
		_last_tick = tick
		if Maps.update(world, number, player.global_position, tick):
			_dirty = true
	if _dirty and visible:
		_dirty = false
		var image := Maps.image_of(world, number)
		if _texture == null:
			_texture = ImageTexture.create_from_image(image)
		else:
			_texture.update(image)
	queue_redraw()


func _draw() -> void:
	if _texture == null or player == null or player.world == null:
		return
	# Above the hotbar and the health, armor and food bars.
	var side := minf(size.y - 56 * P - 8 * P, minf(size.y * 0.6, size.x * 0.5))
	var origin := Vector2((size.x - side) / 2.0, size.y - side - 56 * P)
	draw_texture_rect(_background, Rect2(origin, Vector2(side, side)), false)
	var margin := side * 7.0 / 142.0
	var inner := Rect2(origin + Vector2(margin, margin), Vector2(side - margin * 2.0, side - margin * 2.0))
	draw_texture_rect(_texture, inner, false, Color(1, 1, 1, 0.85))
	# The player: an arrow at their place on the map, pointing where they look.
	var map: Dictionary = player.world.maps.get(_number, {})
	if map.is_empty():
		return
	var at := Vector2((player.global_position.x - float(map.x)) / Maps.SCALE + Maps.SIZE / 2.0,
		(player.global_position.z - float(map.z)) / Maps.SCALE + Maps.SIZE / 2.0)
	at = at.clamp(Vector2.ZERO, Vector2(Maps.SIZE, Maps.SIZE))
	var center := inner.position + at / Maps.SIZE * inner.size
	var look := player.look_direction()
	var forward := Vector2(look.x, look.z).normalized() if Vector2(look.x, look.z).length_squared() > 1e-6 else Vector2(0, -1)
	var right := Vector2(-forward.y, forward.x)
	var unit := inner.size.x / Maps.SIZE * 3.0
	var points := PackedVector2Array([center + forward * unit * 1.4, center - forward * unit + right * unit,
		center - forward * unit * 0.4, center - forward * unit - right * unit])
	draw_colored_polygon(points, Color(1, 1, 1))
	draw_polyline(points + PackedVector2Array([points[0]]), Color(0, 0, 0), maxf(P * 0.5, 1.0))
