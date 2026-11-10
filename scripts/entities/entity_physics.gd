class_name EntityPhysics
extends RefCounted
## Collision of entity boxes (the player, mobs, arrows...) with the block
## grid, like the classic game: a box (half width, height; the position is
## the middle of its bottom) moved axis by axis, Y first, then X, then Z,
## clipped against every colliding block on the way. Blocks lower than a
## full block (beds) collide at their height. 64-bit floats throughout:
## Vector3 would round the clipped distances and let boxes sink into blocks.


## The part of the move (dx, dy, dz) a box at feet (x, y, z) can make.
static func sweep(world: VoxelWorld, x: float, y: float, z: float, half_width: float, height: float,
		dx: float, dy: float, dz: float) -> PackedFloat64Array:
	var min_x := x - half_width
	var max_x := x + half_width
	var min_y := y
	var max_y := y + height
	var min_z := z - half_width
	var max_z := z + half_width
	var boxes := solid_boxes(world,
		minf(min_x, min_x + dx), minf(min_y, min_y + dy), minf(min_z, min_z + dz),
		maxf(max_x, max_x + dx), maxf(max_y, max_y + dy), maxf(max_z, max_z + dz))
	for b in boxes:
		if max_x > b.x and min_x < b.x + 1 and max_z > b.z and min_z < b.z + 1:
			if dy > 0.0 and max_y <= b.y:
				dy = minf(dy, b.y - max_y)
			elif dy < 0.0 and min_y >= b.y + b.w - 1e-7:
				dy = maxf(dy, b.y + b.w - min_y)
	min_y += dy
	max_y += dy
	for b in boxes:
		if max_y > b.y and min_y < b.y + b.w and max_z > b.z and min_z < b.z + 1:
			if dx > 0.0 and max_x <= b.x:
				dx = minf(dx, b.x - max_x)
			elif dx < 0.0 and min_x >= b.x + 1:
				dx = maxf(dx, b.x + 1 - min_x)
	min_x += dx
	max_x += dx
	for b in boxes:
		if max_x > b.x and min_x < b.x + 1 and max_y > b.y and min_y < b.y + b.w:
			if dz > 0.0 and max_z <= b.z:
				dz = minf(dz, b.z - max_z)
			elif dz < 0.0 and min_z >= b.z + 1:
				dz = maxf(dz, b.z + 1 - min_z)
	return PackedFloat64Array([dx, dy, dz])


## The colliding blocks touching the given box: (x, y, z, height of the
## block's top above y; 1 for full blocks, 9/16 for beds).
static func solid_boxes(world: VoxelWorld, min_x: float, min_y: float, min_z: float,
		max_x: float, max_y: float, max_z: float) -> Array[Vector4]:
	var result: Array[Vector4] = []
	if world == null:
		return result
	var collides := Blocks.collides_table
	var heights := Blocks.height_table
	for y in range(floori(min_y), floori(max_y) + 1):
		if y < 0 or y >= WorldGenerator.HEIGHT:
			continue
		for z in range(floori(min_z), floori(max_z) + 1):
			for x in range(floori(min_x), floori(max_x) + 1):
				var id := world.get_block(Vector3i(x, y, z))
				if collides[id] == 1 and min_y < y + heights[id]:
					result.append(Vector4(x, y, z, heights[id]))
	return result


## True if a box at feet (x, y, z) touches no colliding block.
static func is_free(world: VoxelWorld, x: float, y: float, z: float, half_width: float, height: float) -> bool:
	const E := 0.001
	return solid_boxes(world, x - half_width + E, y + E, z - half_width + E,
		x + half_width - E, y + height - E, z + half_width - E).is_empty()


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
