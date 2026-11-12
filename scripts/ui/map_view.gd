class_name MapView
extends Node
## The map in hand, like the classic game: while the player holds a map it
## fills in around them (Maps.update) and its picture is kept here
## (`texture`); HeldItem draws it held in both hands in front of the view,
## with the player's marker (marker()). A map that has no number yet gets
## one, drawn around where it is first held.

var player: Player
## The map's picture (Maps.SIZE square), null before the first map.
var texture: ImageTexture
## A map is in hand (and drawn).
var holding := false

var _number := -1
var _last_tick := -1
var _dirty := true


func _process(_delta: float) -> void:
	var world := player.world if player else null
	holding = world != null and not player.dead and Items.name_of(player.held_block()) == "map"
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
	if _dirty:
		_dirty = false
		var image := Maps.image_of(world, number)
		if texture == null:
			texture = ImageTexture.create_from_image(image)
		else:
			texture.update(image)


## The player's marker on the map: [position in map pixels (0..Maps.SIZE),
## turn in 16ths of a full turn like the game's icons (0 = pointing up,
## north), on the map (false: off its edge, shown there as a dot)].
func marker() -> Array:
	var map: Dictionary = player.world.maps.get(_number, {}) if player and player.world else {}
	if map.is_empty():
		return [Vector2(Maps.SIZE, Maps.SIZE) / 2.0, 0, true]
	var at := Vector2((player.global_position.x - float(map.x)) / Maps.SCALE + Maps.SIZE / 2.0,
		(player.global_position.z - float(map.z)) / Maps.SCALE + Maps.SIZE / 2.0)
	var inside := at.x >= 0.0 and at.y >= 0.0 and at.x <= Maps.SIZE and at.y <= Maps.SIZE
	at = at.clamp(Vector2.ZERO, Vector2(Maps.SIZE, Maps.SIZE))
	var look := player.look_direction()
	# Map pixels: x east, y south (down); the icon points up at turn 0.
	var angle := atan2(look.x, -look.z)
	var turn := posmod(roundi(angle / TAU * 16.0), 16)
	return [at, turn, inside]
