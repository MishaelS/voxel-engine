class_name LiquidBehavior
extends RefCounted
## Flowing water and lava like the classic game (BlockFlowing):
## - every liquid block has a level: 0 = source, 1..7 = flowing, each step
##   away from the source lower, 8 = falling (liquid of the same kind above);
## - when it or a neighbor changes, it ticks after its delay (water 5 ticks,
##   lava 30);
## - flowing liquid takes the level of its highest horizontal neighbor plus
##   a step (water 1: 7 blocks far, lava 2: 3 blocks far), or "falling"
##   under the same liquid, and dries up without a neighbor; water between
##   two sources over solid ground becomes a source (infinite water);
## - it falls into air below; otherwise (or as a source) it spreads to the
##   sides, only toward the nearest drop within 4 blocks if there is one;
##   plants in the way are washed away (water drops them, lava burns them);
## - lava touching water hardens: a source into obsidian, flowing lava
##   into cobblestone; lava flowing down onto water turns it into stone.
## flow_vector() is the direction the current pushes entities.

const SETTINGS := {
	"water": {"delay": 5, "step": 1, "infinite": true},
	"lava": {"delay": 30, "step": 2, "infinite": false},
}
## How far liquid looks for a drop to flow toward.
const SEARCH_DEPTH := 4
const HORIZONTAL: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]


static func on_update(world: VoxelWorld, pos: Vector3i) -> void:
	var family := Blocks.family_of(world.get_block(pos))
	if family == "lava" and _harden(world, pos):
		return
	world.schedule_tick(pos, SETTINGS[family].delay)


## Liquid of `family` with the given level (0 source .. 7, 8 falling).
static func liquid_id(family: String, level: int) -> int:
	return Blocks.variant(family, level)


## The level of `family` liquid at pos, -1 if something else is there.
static func level_at(world: VoxelWorld, pos: Vector3i, family: String) -> int:
	var id := world.get_block(pos)
	if Blocks.liquid_table[id] == 0 or Blocks.family_of(id) != family:
		return -1
	return Blocks.liquid_level_table[id]


static func scheduled_tick(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	if Blocks.liquid_table[id] == 0:
		return
	var family := Blocks.family_of(id)
	if family == "lava" and _harden(world, pos):
		return
	var settings: Dictionary = SETTINGS[family]
	var step: int = settings.step
	var level := Blocks.liquid_level_table[id]
	if level > 0:
		# Flowing liquid follows its neighbors.
		var smallest := -1
		var sources := 0
		for offset in HORIZONTAL:
			var other := level_at(world, pos + offset, family)
			if other < 0:
				continue
			if other == 0:
				sources += 1
			var effective := 0 if other >= 8 else other
			if smallest < 0 or effective < smallest:
				smallest = effective
		var new_level := -1 if smallest < 0 else smallest + step
		if new_level >= 8:
			new_level = -1
		if level_at(world, pos + Vector3i.UP, family) >= 0:
			new_level = 8
		if sources >= 2 and settings.infinite:
			var below := world.get_block(pos + Vector3i.DOWN)
			if Blocks.collides_table[below] == 1 or level_at(world, pos + Vector3i.DOWN, family) == 0:
				new_level = 0
		if new_level != level:
			world.set_block(pos, Blocks.AIR if new_level < 0 else liquid_id(family, new_level))
			if new_level < 0:
				return
			level = new_level

	var below := pos + Vector3i.DOWN
	if family == "lava" and level_at(world, below, "water") >= 0:
		world.set_block(below, Blocks.id_of("stone")) # lava onto water
		return
	if _can_flow_into(world, below):
		_flow_into(world, below, family, 8)
	elif level == 0 or _blocks_flow(world, below, family):
		var spread := step if level >= 8 else level + step
		if spread >= 8:
			return
		for offset in _flow_directions(world, pos, family):
			if _can_flow_into(world, pos + offset):
				_flow_into(world, pos + offset, family, spread)


## Lava touching water (above or beside) hardens. Returns true if it did.
static func _harden(world: VoxelWorld, pos: Vector3i) -> bool:
	for offset: Vector3i in [Vector3i.UP, Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		if level_at(world, pos + offset, "water") >= 0:
			var level := Blocks.liquid_level_table[world.get_block(pos)]
			world.particles.smoke(Vector3(pos) + Vector3(0.5, 1.0, 0.5))
			world.set_block(pos, Blocks.id_of("obsidian" if level == 0 else "cobblestone"))
			return true
	return false


static func _flow_into(world: VoxelWorld, pos: Vector3i, family: String, level: int) -> void:
	var there := world.get_block(pos)
	if there != Blocks.AIR:
		# A plant in the way: water washes it away, lava burns it.
		world.destroy_block(pos, family == "water", true, false)
	world.set_block(pos, liquid_id(family, level))


## Air or a plant in a loaded chunk: liquid can move in.
static func _can_flow_into(world: VoxelWorld, pos: Vector3i) -> bool:
	if pos.y < 0 or pos.y >= WorldGenerator.HEIGHT or not world.is_inside(pos):
		return false
	var id := world.get_block(pos)
	return id == Blocks.AIR or Blocks.replaceable_table[id] == 1


## Anything but air, plants and the same liquid stops it (unloaded chunks too).
static func _blocks_flow(world: VoxelWorld, pos: Vector3i, family: String) -> bool:
	if pos.y < 0 or pos.y >= WorldGenerator.HEIGHT or not world.is_inside(pos):
		return true
	var id := world.get_block(pos)
	if id == Blocks.AIR or Blocks.replaceable_table[id] == 1:
		return false
	return level_at(world, pos, family) < 0


## Directions to spread to: toward the nearest drop within SEARCH_DEPTH
## blocks (all equally near ones), or every open direction.
static func _flow_directions(world: VoxelWorld, pos: Vector3i, family: String) -> Array[Vector3i]:
	var costs: Array[int] = []
	var best := 1000
	for offset in HORIZONTAL:
		var next := pos + offset
		var cost := 1000
		if not _blocks_flow(world, next, family) and level_at(world, next, family) != 0:
			if not _blocks_flow(world, next + Vector3i.DOWN, family):
				cost = 0
			else:
				cost = _flow_cost(world, next, 1, -offset, family)
		costs.append(cost)
		best = mini(best, cost)
	var result: Array[Vector3i] = []
	for k in HORIZONTAL.size():
		if costs[k] == best:
			result.append(HORIZONTAL[k])
	return result


static func _flow_cost(world: VoxelWorld, pos: Vector3i, depth: int, came_from: Vector3i, family: String) -> int:
	var best := 1000
	for offset in HORIZONTAL:
		if offset == came_from:
			continue
		var next := pos + offset
		if _blocks_flow(world, next, family) or level_at(world, next, family) == 0:
			continue
		if not _blocks_flow(world, next + Vector3i.DOWN, family):
			return depth
		if depth < SEARCH_DEPTH:
			best = mini(best, _flow_cost(world, next, depth + 1, -offset, family))
	return best


## Direction of the current at a liquid block, like the classic game:
## toward lower neighbors (and down along a falling column next to walls).
## Not normalized; ZERO in still liquid.
static func flow_vector(world: VoxelWorld, pos: Vector3i) -> Vector3:
	var id := world.get_block(pos)
	if Blocks.liquid_table[id] == 0:
		return Vector3.ZERO
	var family := Blocks.family_of(id)
	var level := Blocks.liquid_level_table[id]
	var own := 0 if level >= 8 else level
	var flow := Vector3.ZERO
	for offset in HORIZONTAL:
		var other := level_at(world, pos + offset, family)
		if other < 0:
			if not _blocks_flow(world, pos + offset, family):
				# Open side: toward the liquid that falls below it.
				var below := level_at(world, pos + offset + Vector3i.DOWN, family)
				if below >= 0:
					var effective := 0 if below >= 8 else below
					flow += Vector3(offset) * (effective - (own - 8))
		else:
			var effective := 0 if other >= 8 else other
			flow += Vector3(offset) * (effective - own)
	if level >= 8:
		for offset in HORIZONTAL:
			if _blocks_flow(world, pos + offset, family) or _blocks_flow(world, pos + offset + Vector3i.UP, family):
				flow = flow.normalized() + Vector3(0, -6, 0)
				break
	return flow
