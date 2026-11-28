class_name EntityPhysics
extends RefCounted
## Collision of entity boxes (the player, mobs, arrows...) with the block
## grid, like the classic game: a box (half width, height; the position is
## the middle of its bottom) moved axis by axis, Y first, then X, then Z,
## clipped against every collision box on the way (BlockType.collision_boxes:
## full blocks, beds, stairs, fences, door panels...). 64-bit floats throughout:
## Vector3 would round the clipped distances and let boxes sink into blocks.


## Solid entities (boats, like Beta's: their box can be stood on and
## bumped into), registered while they are in the world.
static var solid_entities: Array[Entity] = []


## The part of the move (dx, dy, dz) a box at feet (x, y, z) can make;
## `ignore`: the entity moving (not stopped by its own box).
static func sweep(world: VoxelWorld, x: float, y: float, z: float, half_width: float, height: float,
		dx: float, dy: float, dz: float, ignore: Object = null) -> PackedFloat64Array:
	var min_x := x - half_width
	var max_x := x + half_width
	var min_y := y
	var max_y := y + height
	var min_z := z - half_width
	var max_z := z + half_width
	var boxes := solid_boxes(world,
		minf(min_x, min_x + dx), minf(min_y, min_y + dy), minf(min_z, min_z + dz),
		maxf(max_x, max_x + dx), maxf(max_y, max_y + dy), maxf(max_z, max_z + dz), ignore)
	for b in boxes:
		var b_end := b.end
		if max_x > b.position.x and min_x < b_end.x and max_z > b.position.z and min_z < b_end.z:
			if dy > 0.0 and max_y <= b.position.y + 1e-7:
				dy = minf(dy, b.position.y - max_y)
			elif dy < 0.0 and min_y >= b_end.y - 1e-7:
				dy = maxf(dy, b_end.y - min_y)
	min_y += dy
	max_y += dy
	for b in boxes:
		var b_end := b.end
		if max_y > b.position.y and min_y < b_end.y and max_z > b.position.z and min_z < b_end.z:
			if dx > 0.0 and max_x <= b.position.x + 1e-7:
				dx = minf(dx, b.position.x - max_x)
			elif dx < 0.0 and min_x >= b_end.x - 1e-7:
				dx = maxf(dx, b_end.x - min_x)
	min_x += dx
	max_x += dx
	for b in boxes:
		var b_end := b.end
		if max_x > b.position.x and min_x < b_end.x and max_y > b.position.y and min_y < b_end.y:
			if dz > 0.0 and max_z <= b.position.z + 1e-7:
				dz = minf(dz, b.position.z - max_z)
			elif dz < 0.0 and min_z >= b_end.z - 1e-7:
				dz = maxf(dz, b_end.z - min_z)
	return PackedFloat64Array([dx, dy, dz])


## The collision boxes (world space) of the blocks touching the given box:
## full blocks, beds 9/16 high, stairs, fences 1.5 high, door panels...
static func solid_boxes(world: VoxelWorld, min_x: float, min_y: float, min_z: float,
		max_x: float, max_y: float, max_z: float, ignore: Object = null) -> Array[AABB]:
	var result: Array[AABB] = []
	if world == null:
		return result
	for entity in solid_entities:
		if entity == ignore or entity.removed or entity.world != world:
			continue
		var feet := entity.feet()
		var box := AABB(Vector3(feet.x - entity.half_width, feet.y, feet.z - entity.half_width),
			Vector3(entity.half_width * 2.0, entity.height, entity.half_width * 2.0))
		if box.end.y > min_y and box.position.y < max_y and box.end.x > min_x and box.position.x < max_x \
				and box.end.z > min_z and box.position.z < max_z:
			result.append(box)
	var table := Blocks.collision_table
	# Fences reach 1.5 blocks up: look one block lower too.
	for y in range(floori(min_y) - 1, floori(max_y) + 1):
		if y < 0 or y >= WorldGenerator.HEIGHT:
			continue
		for z in range(floori(min_z), floori(max_z) + 1):
			for x in range(floori(min_x), floori(max_x) + 1):
				var boxes: Array = table[world.get_block(Vector3i(x, y, z))]
				for box: AABB in boxes:
					var world_box := AABB(box.position + Vector3(x, y, z), box.size)
					if world_box.end.y > min_y and world_box.position.y < max_y \
							and world_box.end.x > min_x and world_box.position.x < max_x \
							and world_box.end.z > min_z and world_box.position.z < max_z:
						result.append(world_box)
	return result


## True if a box at feet (x, y, z) touches no colliding block.
static func is_free(world: VoxelWorld, x: float, y: float, z: float, half_width: float, height: float) -> bool:
	const E := 0.001
	return solid_boxes(world, x - half_width + E, y + E, z - half_width + E,
		x + half_width - E, y + height - E, z + half_width - E).is_empty()


## Cactus (bit 1: the box slightly grown) and fire (bit 2: slightly shrunk)
## touching the box, in one pass over its cells (Entity._burn: two passes
## with a block type looked up for every cell were a quarter of a
## creature's tick).
static var _hazard := PackedByteArray()


static func hazards(world: VoxelWorld, x: float, y: float, z: float, half_width: float, height: float) -> int:
	if world == null:
		return 0
	if _hazard.size() != Blocks.count():
		_hazard.resize(Blocks.count())
		for id in Blocks.count():
			_hazard[id] = (1 if Blocks.get_type(id).name == "cactus" else 0) | (2 if FireBehavior.is_fire(id) else 0)
	const E := 0.01
	var found := 0
	for by in range(floori(y - E), floori(y + height + E) + 1):
		for bz in range(floori(z - half_width - E), floori(z + half_width + E) + 1):
			for bx in range(floori(x - half_width - E), floori(x + half_width + E) + 1):
				var kind := _hazard[world.get_block(Vector3i(bx, by, bz))]
				if kind == 0:
					continue
				if kind & 1:
					found |= 1
				if kind & 2 and by >= floori(y + 0.001) and by <= floori(y + height - 0.001) \
						and bz >= floori(z - half_width + 0.001) and bz <= floori(z + half_width - 0.001) \
						and bx >= floori(x - half_width + 0.001) and bx <= floori(x + half_width - 0.001):
					found |= 2
	return found


## True if the box (slightly grown) touches a cactus.
static func touches_cactus(world: VoxelWorld, x: float, y: float, z: float, half_width: float, height: float) -> bool:
	if world == null:
		return false
	const E := 0.01
	for by in range(floori(y - E), floori(y + height + E) + 1):
		for bz in range(floori(z - half_width - E), floori(z + half_width + E) + 1):
			for bx in range(floori(x - half_width - E), floori(x + half_width + E) + 1):
				if Blocks.get_type(world.get_block(Vector3i(bx, by, bz))).name == "cactus":
					return true
	return false


## True if the box (slightly shrunk) touches fire.
static func touches_fire(world: VoxelWorld, x: float, y: float, z: float, half_width: float, height: float) -> bool:
	if world == null:
		return false
	for by in range(floori(y + 0.001), floori(y + height - 0.001) + 1):
		for bz in range(floori(z - half_width + 0.001), floori(z + half_width - 0.001) + 1):
			for bx in range(floori(x - half_width + 0.001), floori(x + half_width - 0.001) + 1):
				if FireBehavior.is_fire(world.get_block(Vector3i(bx, by, bz))):
					return true
	return false


## True if liquid of a family ("water", "lava") is inside the box shrunk by
## 0.4 vertically (feet and head have to be really in it, the classic check).
static func touches_liquid(world: VoxelWorld, x: float, y: float, z: float, half_width: float, height: float,
		family: String) -> bool:
	if world == null:
		return false
	var liquid := Blocks.liquid_table
	for by in range(floori(y + 0.4), floori(y + height - 0.4) + 1):
		for bz in range(floori(z - half_width + 0.001), floori(z + half_width - 0.001) + 1):
			for bx in range(floori(x - half_width + 0.001), floori(x + half_width - 0.001) + 1):
				var id := world.get_block(Vector3i(bx, by, bz))
				if liquid[id] == 1 and Blocks.family_of(id) == family:
					return true
	return false
