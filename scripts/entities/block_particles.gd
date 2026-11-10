class_name BlockParticles
extends Node3D
## Particles like the classic game, all in one MultiMesh (particle.gdshader):
## - breaking a block bursts it into 4 x 4 x 4 bits of its texture;
## - hitting a block while breaking it chips small bits off the face;
## - eating sends crumbs of the food from the mouth;
## - a lit furnace gives off smoke and flames.
## Bits fall with gravity (0.04 blocks per tick per tick, drag 0.98), stop
## on blocks and live 4..40 ticks; simulated in game ticks (TickLoop) and
## interpolated between them for drawing. Each bit takes the light where it
## starts.

const MAX_PARTICLES := 4000
const GRAVITY := 0.04

enum Kind { TILE, ITEM, PLAIN }

var world: VoxelWorld

var _positions := PackedVector3Array()
var _previous := PackedVector3Array()
var _velocities := PackedVector3Array()
var _ages := PackedInt32Array()
var _lives := PackedInt32Array()
var _gravity := PackedFloat32Array()
var _custom := PackedColorArray()   # layer, u, v, size
var _colors := PackedColorArray()
var _fade := PackedByteArray()      # 1 = fades out (smoke)
var _multimesh: MultiMesh
var _material: ShaderMaterial
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/particle.gdshader")
	_material.set_shader_parameter("tiles", BlockMaterials.tiles())
	_material.set_shader_parameter("items", Items.icons_texture())
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _material
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.use_custom_data = true
	_multimesh.mesh = quad
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = _multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	add_child(instance)
	TickLoop.add_listener(_tick, TickLoop.Phase.ENTITIES)


func _exit_tree() -> void:
	TickLoop.remove_listener(_tick)


func count() -> int:
	return _ages.size()


# --- Effects ---------------------------------------------------------------------

## A block broken at `pos`: 4 x 4 x 4 bits flying out from its middle.
func break_block(pos: Vector3i, block_id: int) -> void:
	var tile := _tile_of(block_id)
	var tint := _tint_of(block_id)
	var light := _brightness(Vector3(pos) + Vector3(0.5, 0.5, 0.5))
	for x in 4:
		for y in 4:
			for z in 4:
				var offset := (Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5)) / 4.0
				var start := Vector3(pos) + offset
				var velocity := _burst(offset - Vector3(0.5, 0.5, 0.5))
				_add_tile(start, velocity, tile, tint * light, 1.0)


## A chip off the face of a block being broken (one per tick).
func hit_block(pos: Vector3i, normal: Vector3i, block_id: int) -> void:
	var start := Vector3(pos) + Vector3(_rng.randf_range(0.1, 0.9), _rng.randf_range(0.1, 0.9), _rng.randf_range(0.1, 0.9))
	for axis in 3:
		if normal[axis] != 0:
			start[axis] = pos[axis] + (1.1 if normal[axis] > 0 else -0.1)
	if normal.y > 0:
		start.y = pos.y + Blocks.height_table[block_id] + 0.1
	var velocity := _burst(Vector3.ZERO) * 0.2
	velocity.y = (velocity.y - 0.1) * 0.2 + 0.02
	_add_tile(start, velocity, _tile_of(block_id), _tint_of(block_id) * _brightness(start), 0.6)


## Crumbs of an item (eating), from `origin` along `direction`.
func item_crumbs(item_id: int, origin: Vector3, direction: Vector3, amount: int = 5) -> void:
	var light := _brightness(origin)
	for i in amount:
		var velocity := direction * 0.1 + Vector3(_rng.randf_range(-0.05, 0.05), _rng.randf_range(0.05, 0.1), _rng.randf_range(-0.05, 0.05))
		if Items.is_block(item_id):
			_add_tile(origin, velocity, _tile_of(item_id), _tint_of(item_id) * light, 1.0)
		else:
			var item := Items.get_type(item_id)
			var u := ((item.icon % 16) + _rng.randi_range(0, 3) / 4.0) / 16.0
			var v := ((item.icon / 16) + _rng.randi_range(0, 3) / 4.0) / 16.0
			_add(origin, velocity, Color(-1, u, v, _size(1.0)), Color(light, light, light), _life(), 1.0, false)


## A puff of smoke (lava hardening, items burning).
func smoke(point: Vector3, amount: int = 8) -> void:
	for i in amount:
		var start := point + Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.2, 0.2), _rng.randf_range(-0.4, 0.4))
		var gray := _rng.randf_range(0.25, 0.45)
		_add(start, Vector3(0, _rng.randf_range(0.02, 0.05), 0), Color(-2, 0, 0, _rng.randf_range(0.12, 0.25)),
			Color(gray, gray, gray, 0.8), _rng.randi_range(15, 30), -0.01, true)


## An explosion: big puffs of smoke all around and a flash.
func explosion(center: Vector3, power: float) -> void:
	for i in int(power * 16):
		var offset := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * power * 0.8
		var gray := _rng.randf_range(0.4, 0.75)
		_add(center + offset, offset * 0.03 + Vector3(0, 0.02, 0), Color(-2, 0, 0, _rng.randf_range(0.2, 0.45)),
			Color(gray, gray, gray, 0.9), _rng.randi_range(12, 30), -0.01, true)
	for i in 6:
		_add(center, Vector3.ZERO, Color(-2, 0, 0, power * 0.3), Color(1.0, 0.95, 0.8, 0.8), 3, 0.0, true)


## Redstone dust glowing (wire, torches, lit ore): a red speck, brighter
## with more power, like the game's "reddust".
func redstone(point: Vector3, power: int) -> void:
	var f := power / 15.0
	var color := Color(f * 0.6 + 0.4, maxf(f * f * 0.7 - 0.5, 0.0), maxf(f * f * 0.6 - 0.7, 0.0), 1.0)
	_add(point, Vector3(0, 0.005, 0), Color(-2, 0, 0, 0.05), color, _rng.randi_range(10, 20), 0.0, true)


## An air bubble rising (drowning).
func bubble(point: Vector3) -> void:
	_add(point, Vector3(0, 0.05, 0), Color(-2, 0, 0, 0.06), Color(0.75, 0.85, 1.0, 0.9), _rng.randi_range(8, 20), -0.002, false)


## Rain hitting the ground: a tiny droplet bouncing up (a ripple on water).
func rain_splash(point: Vector3, on_water: bool) -> void:
	var velocity := Vector3(_rng.randf_range(-0.02, 0.02), _rng.randf_range(0.03, 0.06), _rng.randf_range(-0.02, 0.02))
	_add(point, velocity if not on_water else velocity * 0.3, Color(-2, 0, 0, 0.04), Color(0.6, 0.7, 1.0, 0.8),
		_rng.randi_range(4, 8), 0.04, false)


## A splash on water (a fish biting): droplets thrown up.
func splash(point: Vector3) -> void:
	for i in 12:
		var velocity := Vector3(_rng.randf_range(-0.08, 0.08), _rng.randf_range(0.08, 0.2), _rng.randf_range(-0.08, 0.08))
		_add(point, velocity, Color(-2, 0, 0, 0.06), Color(0.55, 0.7, 1.0, 0.9), _rng.randi_range(8, 16), 0.04, false)


## A note floating up from a note block, colored by its pitch like the game.
func note(point: Vector3, pitch: int) -> void:
	var f := pitch / 24.0
	var color := Color(maxf(sin(f * TAU) * 0.65 + 0.35, 0.0), maxf(sin((f + 1.0 / 3.0) * TAU) * 0.65 + 0.35, 0.0),
		maxf(sin((f + 2.0 / 3.0) * TAU) * 0.65 + 0.35, 0.0), 1.0)
	_add(point, Vector3(0, 0.02, 0), Color(-2, 0, 0, 0.18), color, 20, 0.0, true)


## Hearts rising (a wolf tamed).
func hearts(point: Vector3) -> void:
	for i in 7:
		var start := point + Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf_range(0, 0.5), _rng.randf_range(-0.5, 0.5))
		_add(start, Vector3(0, 0.02, 0), Color(-2, 0, 0, 0.15), Color(0.95, 0.2, 0.25, 1.0), 25, 0.0, true)


## A torch's tip: a wisp of smoke and a small flame.
func torch(tip: Vector3) -> void:
	var gray := _rng.randf_range(0.2, 0.35)
	_add(tip, Vector3(0, 0.01, 0), Color(-2, 0, 0, 0.08), Color(gray, gray, gray, 0.7), _rng.randi_range(8, 16), -0.02, true)
	_add(tip, Vector3.ZERO, Color(-2, 0, 0, 0.06), Color(1.0, 0.65, 0.2, 1.0), _rng.randi_range(5, 10), 0.0, true)


## A lava pop: an orange spark jumps up and falls back.
func lava_pop(point: Vector3) -> void:
	var velocity := Vector3(_rng.randf_range(-0.04, 0.04), _rng.randf_range(0.15, 0.3), _rng.randf_range(-0.04, 0.04))
	_add(point, velocity, Color(-2, 0, 0, 0.1), Color(1.0, 0.5, 0.1, 1.0), _rng.randi_range(16, 30), 0.75, true)


## Smoke and sometimes a flame in front of a lit furnace.
func furnace(pos: Vector3i, facing: int) -> void:
	var front := Vector3(Blocks.FACING_DIRECTIONS[facing])
	var side := Vector3(-front.z, 0, front.x)
	var start := Vector3(pos) + Vector3(0.5, 0.0, 0.5) + front * 0.52 \
		+ side * _rng.randf_range(-0.3, 0.3) + Vector3(0, _rng.randf_range(0.1, 0.45), 0)
	var gray := _rng.randf_range(0.2, 0.35)
	_add(start, Vector3(0, 0.01, 0), Color(-2, 0, 0, 0.12), Color(gray, gray, gray, 0.8),
		_rng.randi_range(10, 20), -0.02, true)
	if _rng.randf() < 0.5:
		_add(start, Vector3.ZERO, Color(-2, 0, 0, 0.08), Color(1.0, 0.6, 0.15, 1.0),
			_rng.randi_range(8, 14), 0.0, true)


# --- Simulation ----------------------------------------------------------------------

func _tick(_tick_index: int) -> void:
	var i := 0
	while i < _ages.size():
		_ages[i] += 1
		if _ages[i] >= _lives[i]:
			_remove(i)
			continue
		var position := _positions[i]
		_previous[i] = position
		var velocity := _velocities[i]
		velocity.y -= GRAVITY * _gravity[i]
		var on_ground := false
		if world and _gravity[i] > 0.0:
			# Stop on blocks, axis by axis.
			for axis in [1, 0, 2]:
				var next := position
				next[axis] += velocity[axis]
				if _solid(next):
					if axis == 1 and velocity.y < 0.0:
						on_ground = true
					velocity[axis] = 0.0
				else:
					position = next
		else:
			position += velocity
		velocity *= 0.98
		if on_ground:
			velocity.x *= 0.7
			velocity.z *= 0.7
		_positions[i] = position
		_velocities[i] = velocity
		i += 1


func _solid(point: Vector3) -> bool:
	var cell := Vector3i(point.floor())
	var id := world.get_block(cell)
	return Blocks.blocks_point(id, point - Vector3(cell))


func _process(_delta: float) -> void:
	var total := _ages.size()
	if _multimesh.instance_count != total:
		_multimesh.instance_count = total
	var alpha := TickLoop.alpha
	for i in total:
		var position := _previous[i].lerp(_positions[i], alpha)
		_multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, position))
		var color := _colors[i]
		if _fade[i] == 1:
			color.a *= 1.0 - float(_ages[i]) / _lives[i]
		_multimesh.set_instance_color(i, color)
		_multimesh.set_instance_custom_data(i, _custom[i])


# --- Helpers --------------------------------------------------------------------------

## The classic burst: away from the middle at a random speed, a bit upward.
func _burst(direction: Vector3) -> Vector3:
	var velocity := direction + Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.4, 0.4))
	var speed := (_rng.randf() + _rng.randf() + 1.0) * 0.15
	velocity = velocity.normalized() * speed * 0.4 if velocity.length_squared() > 1e-6 else Vector3.ZERO
	velocity.y += 0.1
	return velocity


func _add_tile(start: Vector3, velocity: Vector3, tile: int, color: Color, scale: float) -> void:
	color.a = 1.0 # (tint * brightness also scaled alpha)
	var u := _rng.randi_range(0, 3) / 4.0
	var v := _rng.randi_range(0, 3) / 4.0
	_add(start, velocity, Color(tile, u, v, _size(scale)), color, _life(), 1.0, false)


func _add(start: Vector3, velocity: Vector3, custom: Color, color: Color, life: int, gravity: float, fade: bool) -> void:
	if _ages.size() >= MAX_PARTICLES:
		return
	_positions.append(start)
	_previous.append(start)
	_velocities.append(velocity)
	_ages.append(0)
	_lives.append(life)
	_gravity.append(gravity)
	_custom.append(custom)
	_colors.append(color)
	_fade.append(1 if fade else 0)


func _size(scale: float) -> float:
	return 0.1 * (_rng.randf() * 0.5 + 0.5) * 2.0 * scale


func _life() -> int:
	return int(4.0 / (_rng.randf() * 0.9 + 0.1))


func _remove(index: int) -> void:
	var last := _ages.size() - 1
	_positions[index] = _positions[last]
	_previous[index] = _previous[last]
	_velocities[index] = _velocities[last]
	_ages[index] = _ages[last]
	_lives[index] = _lives[last]
	_gravity[index] = _gravity[last]
	_custom[index] = _custom[last]
	_colors[index] = _colors[last]
	_fade[index] = _fade[last]
	_positions.resize(last)
	_previous.resize(last)
	_velocities.resize(last)
	_ages.resize(last)
	_lives.resize(last)
	_gravity.resize(last)
	_custom.resize(last)
	_colors.resize(last)
	_fade.resize(last)


## The texture bits come from the block's bottom face, like the classic game
## (grass gives dirt bits, logs their rings).
static func _tile_of(block_id: int) -> int:
	return Blocks.face_tiles[block_id * 6 + 1]


## Leaves keep their color; grass gives plain dirt bits.
static func _tint_of(block_id: int) -> Color:
	var block := Blocks.get_type(block_id)
	return block.tint.srgb_to_linear() if block.name.ends_with("_leaves") else Color.WHITE


## Brightness of the light at a point, like the blocks (night darkness too).
func _brightness(point: Vector3) -> float:
	return world.brightness_at(point) if world else 1.0