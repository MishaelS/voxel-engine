class_name TreeShapes
extends RefCounted
## Trees exactly like Minecraft Beta 1.7.3's tree generators, step for step
## (the same checks, the same order of random numbers, ours from Godot's
## RandomNumberGenerator):
## - oak (WorldGenTrees): a trunk of 4..6, four leaf layers above its top
##   minus one: two 5 x 5, two 3 x 3, the corners left out at random (always
##   on the top layer);
## - birch (WorldGenForest): the same, trunk 5..7;
## - spruce (WorldGenTaiga2): 6..9 high, 1..2 bare at the bottom, rings of
##   leaves from the top down growing 0/1, 1, 2... to 2..3 and starting over,
##   the trunk 0..2 shorter than the leaves;
## - pine (WorldGenTaiga1): 7..11 high, a long bare trunk and a cone of
##   leaves widening down to 1..5, shrinking by one at its bottom;
## - big oak (WorldGenBigTree): 5..16 high, leaf clusters (balls 2..3 across
##   four layers) at the ends of branches climbing from the trunk at a slope.
## A tree needs room (air or leaves where it grows; grass or dirt under the
## trunk) or it is not grown. The generator's column (NativeBetaGenerator
## does the same in C++) and saplings (SaplingBehavior, in the world) draw
## them through a Canvas.

const BIG_HEIGHT_ATTENUATION := 0.618
const BIG_BRANCH_SLOPE := 0.381
const BIG_LEAF_DISTANCE := 4
## The other two axes for each axis (Beta's otherCoordPairs).
const OTHER := [2, 0, 0, 1, 2, 1]


## Where a tree is drawn. Cells outside it read as air and are not written.
class Canvas:
	## Blocks above this height do not exist.
	var height := 128
	## Big trees' leaf clusters keep within x, z of [low, high] (the
	## generator's column: their leaves fit), world coordinates.
	var low := -2147483648
	var high := 2147483647

	func at(_x: int, _y: int, _z: int) -> int:
		return Blocks.AIR

	func put(_x: int, _y: int, _z: int, _id: int) -> void:
		pass


## A generated column (16 x height x 16, index x + 16 * (z + 16 * y)).
class ColumnCanvas extends Canvas:
	var blocks: PackedInt32Array

	func _init(column_blocks: PackedInt32Array, column_height: int) -> void:
		blocks = column_blocks
		height = column_height
		low = 2
		high = 13

	func at(x: int, y: int, z: int) -> int:
		if x < 0 or x > 15 or z < 0 or z > 15 or y < 0 or y >= height:
			return Blocks.AIR
		return blocks[x + 16 * (z + 16 * y)]

	func put(x: int, y: int, z: int, id: int) -> void:
		if x < 0 or x > 15 or z < 0 or z > 15 or y < 0 or y >= height:
			return
		blocks[x + 16 * (z + 16 * y)] = id


## The world (a sapling growing).
class WorldCanvas extends Canvas:
	var world: VoxelWorld

	func _init(target: VoxelWorld) -> void:
		world = target
		height = target.height

	func at(x: int, y: int, z: int) -> int:
		return world.get_block(Vector3i(x, y, z))

	func put(x: int, y: int, z: int, id: int) -> void:
		world.set_block(Vector3i(x, y, z), id)


static var _leaves := {}


static func is_leaves(id: int) -> bool:
	if _leaves.is_empty():
		for name in ["oak_leaves", "birch_leaves", "spruce_leaves"]:
			_leaves[Blocks.id_of(name)] = true
	return _leaves.has(id)


## Room for a tree: air or leaves.
static func _free(id: int) -> bool:
	return id == Blocks.AIR or is_leaves(id)


## Grass or dirt (Beta's ids 2 and 3; our grasses, snowy grass included).
static func is_ground(id: int) -> bool:
	var name := Blocks.get_type(id).name
	return name.begins_with("grass_") or name == "dirt" or name == "snowy_grass"


## Leaves go where nothing solid is (Beta: not an opaque cube): air, leaves,
## plants; not into water. (Not by opacity: leaves' changes with Fast
## graphics, and the world must not.)
static func _put_leaf(canvas: Canvas, x: int, y: int, z: int, leaf: int) -> void:
	var there := canvas.at(x, y, z)
	if there != leaf and (is_leaves(there) or (Blocks.collides_table[there] == 0 and Blocks.liquid_table[there] == 0)):
		canvas.put(x, y, z, leaf)


static func _put_log(canvas: Canvas, x: int, y: int, z: int, log_id: int) -> void:
	if _free(canvas.at(x, y, z)):
		canvas.put(x, y, z, log_id)


## Whether the cells within `radius` around (x, z) at height y are free.
static func _ring_free(canvas: Canvas, x: int, y: int, z: int, radius: int) -> bool:
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			if not _free(canvas.at(x + dx, y, z + dz)):
				return false
	return true


## Oak (min_height 4) or birch (5): WorldGenTrees / WorldGenForest.
static func oak(canvas: Canvas, rng: RandomNumberGenerator, x: int, y: int, z: int, log_id: int, leaf: int, min_height: int) -> bool:
	var height := rng.randi_range(min_height, min_height + 2)
	if y < 1 or y + height + 1 > canvas.height:
		return false
	for ly in range(y, y + height + 2):
		var radius := 0 if ly == y else (2 if ly >= y + height + 1 - 2 else 1)
		if not _ring_free(canvas, x, ly, z, radius):
			return false
	if not is_ground(canvas.at(x, y - 1, z)):
		return false
	canvas.put(x, y - 1, z, Blocks.id_of("dirt"))
	for ly in range(y - 3 + height, y + height + 1):
		var above_top := ly - (y + height)
		var radius := 1 - above_top / 2
		for lx in range(x - radius, x + radius + 1):
			for lz in range(z - radius, z + radius + 1):
				if absi(lx - x) != radius or absi(lz - z) != radius or (rng.randi_range(0, 1) != 0 and above_top != 0):
					_put_leaf(canvas, lx, ly, lz, leaf)
	for dy in height:
		_put_log(canvas, x, y + dy, z, log_id)
	return true


## Spruce: WorldGenTaiga2.
static func spruce(canvas: Canvas, rng: RandomNumberGenerator, x: int, y: int, z: int) -> bool:
	var height := rng.randi_range(6, 9)
	var bare := rng.randi_range(1, 2)
	var leafy := height - bare
	var widest := rng.randi_range(2, 3)
	if y < 1 or y + height + 1 > canvas.height:
		return false
	for ly in range(y, y + height + 2):
		if not _ring_free(canvas, x, ly, z, 0 if ly - y < bare else widest):
			return false
	if not is_ground(canvas.at(x, y - 1, z)):
		return false
	canvas.put(x, y - 1, z, Blocks.id_of("dirt"))
	var leaf := Blocks.id_of("spruce_leaves")
	var radius := rng.randi_range(0, 1)
	var limit := 1
	var restart := 0
	for i in leafy + 1:
		var ly := y + height - i
		for lx in range(x - radius, x + radius + 1):
			for lz in range(z - radius, z + radius + 1):
				if absi(lx - x) != radius or absi(lz - z) != radius or radius <= 0:
					_put_leaf(canvas, lx, ly, lz, leaf)
		if radius >= limit:
			radius = restart
			restart = 1
			limit = mini(limit + 1, widest)
		else:
			radius += 1
	var shorter := rng.randi_range(0, 2)
	var log_id := Blocks.id_of("spruce_log")
	for dy in height - shorter:
		_put_log(canvas, x, y + dy, z, log_id)
	return true


## Pine: WorldGenTaiga1.
static func pine(canvas: Canvas, rng: RandomNumberGenerator, x: int, y: int, z: int) -> bool:
	var height := rng.randi_range(7, 11)
	var bare := height - rng.randi_range(0, 1) - 3
	var leafy := height - bare
	var widest := 1 + rng.randi_range(0, leafy)
	if y < 1 or y + height + 1 > canvas.height:
		return false
	for ly in range(y, y + height + 2):
		if not _ring_free(canvas, x, ly, z, 0 if ly - y < bare else widest):
			return false
	if not is_ground(canvas.at(x, y - 1, z)):
		return false
	canvas.put(x, y - 1, z, Blocks.id_of("dirt"))
	var leaf := Blocks.id_of("spruce_leaves")
	var radius := 0
	for ly in range(y + height, y + bare - 1, -1):
		for lx in range(x - radius, x + radius + 1):
			for lz in range(z - radius, z + radius + 1):
				if absi(lx - x) != radius or absi(lz - z) != radius or radius <= 0:
					_put_leaf(canvas, lx, ly, lz, leaf)
		if radius >= 1 and ly == y + bare + 1:
			radius -= 1
		elif radius < widest:
			radius += 1
	var log_id := Blocks.id_of("spruce_log")
	for dy in height - 1:
		_put_log(canvas, x, y + dy, z, log_id)
	return true


# --- Big oak: WorldGenBigTree --------------------------------------------------------------

## Big oak. False (nothing drawn) without room.
static func big_oak(canvas: Canvas, rng: RandomNumberGenerator, x: int, y: int, z: int) -> bool:
	var base := Vector3i(x, y, z)
	var height_limit := 5 + rng.randi_range(0, 11)
	if not is_ground(canvas.at(x, y - 1, z)):
		return false
	var blocked := _check_line(canvas, base, Vector3i(x, y + height_limit - 1, z))
	if blocked != -1:
		if blocked < 6:
			return false
		height_limit = blocked
	if y + height_limit > canvas.height:
		return false
	var trunk_height := int(height_limit * BIG_HEIGHT_ATTENUATION)
	if trunk_height >= height_limit:
		trunk_height = height_limit - 1
	var nodes := _leaf_nodes(canvas, rng, base, height_limit, trunk_height)
	var leaf := Blocks.id_of("oak_leaves")
	var log_id := Blocks.id_of("oak_log")
	for node: Array in nodes:
		for ly in range(node[1], node[1] + BIG_LEAF_DISTANCE):
			var layer: int = ly - node[1]
			_cross_section(canvas, node[0], ly, node[2], 2.0 if layer == 0 or layer == BIG_LEAF_DISTANCE - 1 else 3.0, leaf)
	_place_line(canvas, base, Vector3i(x, y + trunk_height, z), log_id)
	for node: Array in nodes:
		if node[3] - y >= height_limit * 0.2:
			_place_line(canvas, Vector3i(x, node[3], z), Vector3i(node[0], node[1], node[2]), log_id)
	return true


## The leaf clusters: [x, y, z, where their branch leaves the trunk].
static func _leaf_nodes(canvas: Canvas, rng: RandomNumberGenerator, base: Vector3i, height_limit: int, trunk_height: int) -> Array:
	var per_layer := maxi(int(1.382 + pow(height_limit / 13.0, 2.0)), 1)
	var top := base.y + height_limit - BIG_LEAF_DISTANCE
	var trunk_top := base.y + trunk_height
	var nodes := [[base.x, top, base.z, trunk_top]]
	var y := top - 1
	var layer := top - base.y
	while layer >= 0:
		var size := _layer_size(layer, height_limit)
		if size >= 0.0:
			for attempt in per_layer:
				var distance := size * (rng.randf() + 0.328)
				var angle := rng.randf() * 2.0 * 3.14159
				var nx := floori(distance * sin(angle) + base.x + 0.5)
				var nz := floori(distance * cos(angle) + base.z + 0.5)
				if nx < canvas.low or nx > canvas.high or nz < canvas.low or nz > canvas.high:
					continue # (its leaves would not fit)
				var node := Vector3i(nx, y, nz)
				if _check_line(canvas, node, node + Vector3i(0, BIG_LEAF_DISTANCE, 0)) != -1:
					continue
				var reach := sqrt(pow(absi(base.x - nx), 2.0) + pow(absi(base.z - nz), 2.0)) * BIG_BRANCH_SLOPE
				var from_y := trunk_top if y - reach > trunk_top else int(y - reach)
				if _check_line(canvas, Vector3i(base.x, from_y, base.z), node) == -1:
					nodes.append([nx, y, nz, from_y])
		y -= 1
		layer -= 1
	return nodes


## How far the branches reach at a height (negative: none there).
static func _layer_size(layer: int, height_limit: int) -> float:
	if layer < height_limit * 0.3:
		return -1.618
	var half := height_limit / 2.0
	var off := height_limit / 2.0 - layer
	var size: float
	if off == 0.0:
		size = half
	elif absf(off) >= half:
		size = 0.0
	else:
		size = sqrt(half * half - off * off)
	return size * 0.5


## A disc of leaves (y up), round like Beta's.
static func _cross_section(canvas: Canvas, x: int, y: int, z: int, size: float, leaf: int) -> void:
	var reach := int(size + 0.618)
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			if sqrt(pow(absi(dx) + 0.5, 2.0) + pow(absi(dz) + 0.5, 2.0)) > size:
				continue
			var there := canvas.at(x + dx, y, z + dz)
			if there == Blocks.AIR or is_leaves(there):
				canvas.put(x + dx, y, z + dz, leaf)


## The cells of the line from a to b, b included (Beta's stepping).
static func _line(a: Vector3i, b: Vector3i) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	var delta := b - a
	var main := 0
	for axis in 3:
		if absi(delta[axis]) > absi(delta[main]):
			main = axis
	if delta[main] == 0:
		return cells
	var first: int = OTHER[main]
	var second: int = OTHER[main + 3]
	var step := 1 if delta[main] > 0 else -1
	var d1 := float(delta[first]) / delta[main]
	var d2 := float(delta[second]) / delta[main]
	var k := 0
	var end := delta[main] + step
	while k != end:
		var cell := Vector3i.ZERO
		cell[main] = floori(a[main] + k + 0.5)
		cell[first] = floori(a[first] + k * d1 + 0.5)
		cell[second] = floori(a[second] + k * d2 + 0.5)
		cells.append(cell)
		k += step
	return cells


## -1 if the line is free (air, leaves), else how far it got.
static func _check_line(canvas: Canvas, a: Vector3i, b: Vector3i) -> int:
	var cells := _line(a, b)
	for i in cells.size():
		var cell := cells[i]
		if not _free(canvas.at(cell.x, cell.y, cell.z)):
			return i
	return -1


static func _place_line(canvas: Canvas, a: Vector3i, b: Vector3i, id: int) -> void:
	for cell in _line(a, b):
		canvas.put(cell.x, cell.y, cell.z, id)
