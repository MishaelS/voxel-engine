class_name RailBehavior
extends RefCounted
## Rails like Beta 1.7.3:
## - 10 shapes (the game's rail metadata): 0 north-south, 1 east-west, 2..5
##   rising toward east, west, north, south, 6..9 curves south-east,
##   south-west, north-west, north-east. Powered and detector rails can't
##   curve;
## - a placed rail turns to join the rails next to it (one up or down makes
##   a slope; two at a corner a curve), and those rails turn toward it when
##   they have a free end, like the game's rail logic;
## - rails need solid ground and break without it;
## - powered rails are powered by redstone, or by a powered rail next in
##   line (up to 8 away); powered they speed carts up, unpowered they brake;
## - detector rails give power while a minecart is on them (checked every
##   20 ticks).
## States: "rail" shape; "powered_rail" / "detector_rail" shape * 2 + on.

const FAMILIES := ["rail", "powered_rail", "detector_rail"]
## The two ends of each shape (x, rise, z), like the game's table.
const ENDS := [
	[Vector3i(0, 0, -1), Vector3i(0, 0, 1)],
	[Vector3i(-1, 0, 0), Vector3i(1, 0, 0)],
	[Vector3i(-1, -1, 0), Vector3i(1, 0, 0)],
	[Vector3i(-1, 0, 0), Vector3i(1, -1, 0)],
	[Vector3i(0, 0, -1), Vector3i(0, -1, 1)],
	[Vector3i(0, -1, -1), Vector3i(0, 0, 1)],
	[Vector3i(0, 0, 1), Vector3i(1, 0, 0)],
	[Vector3i(0, 0, 1), Vector3i(-1, 0, 0)],
	[Vector3i(0, 0, -1), Vector3i(-1, 0, 0)],
	[Vector3i(0, 0, -1), Vector3i(1, 0, 0)],
]
## Shape rising toward a direction.
const RISING := {Vector3i(1, 0, 0): 2, Vector3i(-1, 0, 0): 3, Vector3i(0, 0, -1): 4, Vector3i(0, 0, 1): 5}
const POWER_REACH := 8
const DETECTOR_TICKS := 20


static func is_rail(id: int) -> bool:
	return Blocks.family_of(id) in FAMILIES


static func shape_of(id: int) -> int:
	var family := Blocks.family_of(id)
	var index := Blocks.family_ids(family).find(id)
	return index if family == "rail" else index / 2


static func is_on(id: int) -> bool:
	var family := Blocks.family_of(id)
	return family != "rail" and Blocks.family_ids(family).find(id) % 2 == 1


static func rail_id(family: String, shape: int, on: bool = false) -> int:
	if family == "rail":
		return Blocks.family_ids("rail")[shape]
	return Blocks.family_ids(family)[shape * 2 + (1 if on else 0)]


## Rising direction of a slope shape, or ZERO.
static func rising(shape: int) -> Vector3i:
	for d: Vector3i in RISING:
		if RISING[d] == shape:
			return d
	return Vector3i.ZERO


## The horizontal directions a shape connects to.
static func ends_of(shape: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for e: Vector3i in ENDS[shape]:
		result.append(Vector3i(e.x, 0, e.z))
	return result


## The rail touching pos from `direction` (same height, one up or one
## down), or a position with y = -1000.
static func rail_toward(world: VoxelWorld, pos: Vector3i, direction: Vector3i) -> Vector3i:
	for dy in [0, 1, -1]:
		var at: Vector3i = pos + direction + Vector3i(0, dy, 0)
		if is_rail(world.get_block(at)):
			return at
	return Vector3i(0, -1000, 0)


## Whether the rail at `at` (a neighbor of pos) points at pos, or could
## (has a free end).
static func _can_join(world: VoxelWorld, at: Vector3i, pos: Vector3i) -> bool:
	var shape := shape_of(world.get_block(at))
	var toward := Vector3i(pos.x - at.x, 0, pos.z - at.z)
	if toward in ends_of(shape):
		return true
	var joined := 0
	for e in ends_of(shape):
		if rail_toward(world, at, e).y != -1000:
			joined += 1
	return joined < 2


## The shape a rail at pos takes from the rails around it.
static func shape_for(world: VoxelWorld, pos: Vector3i, curves: bool) -> int:
	var found: Array[Vector3i] = []
	var heights := {}
	for d in Redstone.HORIZONTAL:
		var at := rail_toward(world, pos, d)
		if at.y != -1000 and _can_join(world, at, pos):
			found.append(d)
			heights[d] = at.y - pos.y
	var has := func(d: Vector3i) -> bool: return found.has(d)
	var shape := 0
	var axis := Vector3i(0, 0, 1)
	if has.call(Vector3i(0, 0, 1)) or has.call(Vector3i(0, 0, -1)):
		axis = Vector3i(0, 0, 1)
		shape = 0
	if (has.call(Vector3i(1, 0, 0)) or has.call(Vector3i(-1, 0, 0))) and not (has.call(Vector3i(0, 0, 1)) or has.call(Vector3i(0, 0, -1))):
		axis = Vector3i(1, 0, 0)
		shape = 1
	if curves:
		var s: bool = has.call(Vector3i(0, 0, 1))
		var n: bool = has.call(Vector3i(0, 0, -1))
		var e: bool = has.call(Vector3i(1, 0, 0))
		var w: bool = has.call(Vector3i(-1, 0, 0))
		if not (s and n) and not (e and w):
			if s and e:
				return 6
			if s and w:
				return 7
			if n and w:
				return 8
			if n and e:
				return 9
	# A straight rail: a slope toward a rail one higher.
	for d: Vector3i in [axis, -axis]:
		if heights.get(d, 0) == 1:
			return RISING[d]
	return shape


static func on_update(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	if not is_rail(id):
		return
	var shape := shape_of(id)
	if not Redstone.is_solid(world.get_block(pos + Vector3i.DOWN)):
		world.destroy_block(pos, true, true)
		return
	if Blocks.family_of(id) == "powered_rail":
		var on := _powered(world, pos, shape)
		if on != is_on(id):
			world.set_block(pos, rail_id("powered_rail", shape, on))


## A rail placed: its shape from the rails around, then those rails turn
## toward it when they can.
static func place(world: VoxelWorld, pos: Vector3i, family: String) -> void:
	var shape := shape_for(world, pos, family == "rail")
	world.set_block(pos, rail_id(family, shape), false)
	for e in ends_of(shape):
		var at := rail_toward(world, pos, e)
		if at.y == -1000:
			continue
		var other := world.get_block(at)
		var other_family := Blocks.family_of(other)
		var turned := shape_for(world, at, other_family == "rail")
		if turned != shape_of(other):
			world.set_block(at, rail_id(other_family, turned, is_on(other)), false)
	world.set_block(pos, Blocks.AIR, false)
	world.set_block(pos, rail_id(family, shape))


## Powered by redstone, or along a line of powered rails (up to 8) that is.
static func _powered(world: VoxelWorld, pos: Vector3i, shape: int) -> bool:
	if Redstone.indirectly_powered(world, pos):
		return true
	for e in ends_of(shape):
		var at := pos
		for step in POWER_REACH:
			at = rail_toward(world, at, e)
			if at.y == -1000:
				break
			var id := world.get_block(at)
			if Blocks.family_of(id) != "powered_rail" or not (e in ends_of(shape_of(id)) or -e in ends_of(shape_of(id))):
				break
			if Redstone.indirectly_powered(world, at):
				return true
	return false


## A minecart is on the detector rail at pos.
static func cart_on(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	if Blocks.family_of(id) != "detector_rail" or is_on(id):
		return
	world.set_block(pos, rail_id("detector_rail", shape_of(id), true), false)
	Redstone.notify_around(world, pos)
	Redstone.notify_around(world, pos + Vector3i.DOWN)
	world.schedule_tick(pos, DETECTOR_TICKS)


static func detector_tick(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	if Blocks.family_of(id) != "detector_rail" or not is_on(id):
		return
	var box := AABB(Vector3(pos) + Vector3(0.125, 0, 0.125), Vector3(0.75, 0.875, 0.75))
	for entity in world.entities.all():
		if entity is Minecart and not entity.removed and entity.hit_box().intersects(box):
			world.schedule_tick(pos, DETECTOR_TICKS)
			return
	world.set_block(pos, rail_id("detector_rail", shape_of(id), false), false)
	Redstone.notify_around(world, pos)
	Redstone.notify_around(world, pos + Vector3i.DOWN)
