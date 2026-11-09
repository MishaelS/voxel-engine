class_name WaterBehavior
extends RefCounted
## Flowing water like the classic game (BlockFlowing):
## - every block of water has a level: 0 = source, 1..7 = flowing, each
##   step away from the source one lower, 8 = falling (water above it);
## - when water or a neighbor changes, it ticks after TICK_DELAY ticks;
## - flowing water takes the level of its highest horizontal neighbor + 1
##   (or "falling" under water) and dries up without one; two sources next
##   to it over solid ground (or a source) make a new source (infinite
##   water);
## - water falls into air below; otherwise (or as a source) it spreads to
##   the sides, only toward the nearest drop within 4 blocks if there is
##   one, else in all directions, until level 7.

const TICK_DELAY := 5
## How far water looks for a drop to flow toward.
const SEARCH_DEPTH := 4
const HORIZONTAL: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]


static func on_update(world: VoxelWorld, pos: Vector3i) -> void:
	world.schedule_tick(pos, TICK_DELAY)


## Water of the given level (0 source .. 7, 8 falling).
static func water_id(level: int) -> int:
	return Blocks.variant("water", level)


static func level_at(world: VoxelWorld, pos: Vector3i) -> int:
	return Blocks.liquid_level_table[world.get_block(pos)]


static func scheduled_tick(world: VoxelWorld, pos: Vector3i) -> void:
	var level := level_at(world, pos)
	if level < 0:
		return
	if level > 0:
		# Flowing water follows its neighbors.
		var smallest := -1
		var sources := 0
		for offset in HORIZONTAL:
			var other := level_at(world, pos + offset)
			if other < 0:
				continue
			if other == 0:
				sources += 1
			var effective := 0 if other >= 8 else other
			if smallest < 0 or effective < smallest:
				smallest = effective
		var new_level := -1 if smallest < 0 else smallest + 1
		if new_level >= 8:
			new_level = -1
		if level_at(world, pos + Vector3i.UP) >= 0:
			new_level = 8
		if sources >= 2:
			var below := world.get_block(pos + Vector3i.DOWN)
			if Blocks.collides_table[below] == 1 or Blocks.liquid_level_table[below] == 0:
				new_level = 0
		if new_level != level:
			world.set_block(pos, Blocks.AIR if new_level < 0 else water_id(new_level))
			if new_level < 0:
				return
			level = new_level

	var below := pos + Vector3i.DOWN
	if _can_flow_into(world, below):
		world.set_block(below, water_id(8))
	elif level == 0 or _blocks_flow(world, below):
		var spread := 1 if level >= 8 else level + 1
		if spread >= 8:
			return
		for offset in _flow_directions(world, pos):
			if _can_flow_into(world, pos + offset):
				world.set_block(pos + offset, water_id(spread))


## Air in a loaded chunk: water can move in.
static func _can_flow_into(world: VoxelWorld, pos: Vector3i) -> bool:
	return pos.y >= 0 and pos.y < WorldGenerator.HEIGHT and world.is_inside(pos) \
		and world.get_block(pos) == Blocks.AIR


## Anything but air and water stops water (unloaded chunks too).
static func _blocks_flow(world: VoxelWorld, pos: Vector3i) -> bool:
	if pos.y < 0 or pos.y >= WorldGenerator.HEIGHT or not world.is_inside(pos):
		return true
	var id := world.get_block(pos)
	return id != Blocks.AIR and Blocks.liquid_table[id] == 0


## Directions to spread to: toward the nearest drop within SEARCH_DEPTH
## blocks (all equally near ones), or every open direction.
static func _flow_directions(world: VoxelWorld, pos: Vector3i) -> Array[Vector3i]:
	var costs: Array[int] = []
	var best := 1000
	for offset in HORIZONTAL:
		var next := pos + offset
		var cost := 1000
		if not _blocks_flow(world, next) and level_at(world, next) != 0:
			if not _blocks_flow(world, next + Vector3i.DOWN):
				cost = 0
			else:
				cost = _flow_cost(world, next, 1, -offset)
		costs.append(cost)
		best = mini(best, cost)
	var result: Array[Vector3i] = []
	for k in HORIZONTAL.size():
		if costs[k] == best:
			result.append(HORIZONTAL[k])
	return result


static func _flow_cost(world: VoxelWorld, pos: Vector3i, depth: int, came_from: Vector3i) -> int:
	var best := 1000
	for offset in HORIZONTAL:
		if offset == came_from:
			continue
		var next := pos + offset
		if _blocks_flow(world, next) or level_at(world, next) == 0:
			continue
		if not _blocks_flow(world, next + Vector3i.DOWN):
			return depth
		if depth < SEARCH_DEPTH:
			best = mini(best, _flow_cost(world, next, depth + 1, -offset))
	return best
