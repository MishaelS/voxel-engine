class_name Pathfinder
extends RefCounted
## Paths for creatures on the block grid (A*), a bit smarter than Beta
## 1.7.3's (which mostly walked straight at the target): around walls and
## holes, up one block at a time (a jump), down at most MAX_DROP, through
## water (slower), never into lava, fire, cactus or onto fences.
##
## A cell is where a creature's feet are: its block and the ones above it up
## to the creature's height are free (no collision box), the block under it
## has a top to stand on (or the cell is water). Moves go to the 8 cells
## around (diagonals only when both sides are free), with costs 1 / 1.41,
## +1 up, +0.5 per block down, x2 in water.
##
## Searches are limited (MAX_NODES each, NODE_BUDGET cells a tick for every
## creature together), so a target out of reach gives the cell nearest to it
## found, and many creatures don't slow the game: the rest wait a tick.

const MAX_NODES := 400
const MAX_DROP := 3
## Cells searched in one game tick, for all creatures together (in C++ a
## cell costs under a microsecond: 1200 is about a millisecond a tick; with
## 500 a crowd at night ran out and the rest walked straight into walls).
const NODE_BUDGET := 1200
const NEIGHBORS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

static var _solid := PackedByteArray()  # has a collision box
static var _floor := PackedByteArray()  # its top can be stood on (not a fence)
static var _harmful := PackedByteArray() # lava, fire, cactus
## The liquids table for a creature that doesn't swim off (animals): none, so
## water is only walked where there is ground under it (a block deep).
static var _dry := PackedByteArray()
## find_script's swimming (standable reads it while a dry search runs).
static var _swim := true
static var _budget := NODE_BUDGET
static var _budget_age := -1


static func _tables() -> void:
	if _solid.size() == Blocks.count():
		return
	_solid.resize(Blocks.count())
	_floor.resize(Blocks.count())
	_harmful.resize(Blocks.count())
	_dry.resize(Blocks.count())
	for id in Blocks.count():
		var boxes: Array = Blocks.collision_table[id]
		var top := 0.0
		for box: AABB in boxes:
			top = maxf(top, box.end.y)
		_solid[id] = 1 if not boxes.is_empty() else 0
		_floor[id] = 1 if not boxes.is_empty() and top <= 1.0 else 0
		var family := Blocks.family_of(id)
		_harmful[id] = 1 if family == "lava" or family == "fire" or family == "cactus" else 0


## How many cells a search may look at now (0: wait for the next tick);
## the search's own count is taken off (spend()).
static func budget(game_tick: int, wanted: int) -> int:
	if game_tick != _budget_age:
		_budget_age = game_tick
		_budget = NODE_BUDGET
	return mini(wanted, _budget) if _budget >= mini(wanted, 100) else 0


static var last_visited := 0


## Whether a creature `tall` cells high can have its feet at `cell`.
static func standable(world: VoxelWorld, cell: Vector3i, tall: int) -> bool:
	_tables()
	for dy in tall:
		var id := world.get_block(cell + Vector3i(0, dy, 0))
		if _solid[id] == 1 or _harmful[id] == 1:
			return false
	var here := world.get_block(cell)
	if _swim and Blocks.liquid_table[here] == 1:
		return true # swimming
	var below := world.get_block(cell + Vector3i.DOWN)
	return _floor[below] == 1 and _harmful[below] == 0


## Where a creature at `cell` ends up stepping toward the column (x, z):
## the same height, one up (if it can jump: free above its head), or the
## first floor at most MAX_DROP down; Vector3i.MAX if nowhere.
static func _step(world: VoxelWorld, cell: Vector3i, to: Vector2i, tall: int) -> Vector3i:
	var same := Vector3i(to.x, cell.y, to.y)
	if standable(world, same, tall):
		return same
	var up := same + Vector3i.UP
	if standable(world, up, tall) and _solid[world.get_block(cell + Vector3i(0, tall, 0))] == 0:
		return up
	for dy in range(1, MAX_DROP + 1):
		var down := same - Vector3i(0, dy, 0)
		var id := world.get_block(down + Vector3i(0, tall - 1, 0))
		if _solid[id] == 1:
			return Vector3i.MAX # a wall
		if standable(world, down, tall):
			# (the cells in between must be free to fall through)
			return down
	return Vector3i.MAX


## NativePath (C++: the same search step by step) when the native library
## is there.
static var _native := ClassDB.class_exists("NativePath")


## A path of cells from `start` toward `goal` (the goal itself, or the
## nearest cell found); empty if nothing better than standing still.
## `swim` false (animals): no swimming off, only water with ground a block
## under it is walked through.
static func find(world: VoxelWorld, start: Vector3i, goal: Vector3i, tall: int, max_nodes: int = MAX_NODES,
		swim: bool = true) -> Array[Vector3i]:
	_tables()
	if not _native:
		_swim = swim
		var path := find_script(world, start, goal, tall, max_nodes)
		_swim = true
		return path
	var found: PackedInt32Array = ClassDB.class_call_static("NativePath", "find", world.get("_chunks"), start, goal, tall,
		max_nodes, _solid, _floor, _harmful, Blocks.liquid_table if swim else _dry)
	var result: Array[Vector3i] = []
	var visited := found[0]
	last_visited = visited
	_budget -= visited
	for i in range(1, found.size(), 3):
		result.append(Vector3i(found[i], found[i + 1], found[i + 2]))
	return result


## find() in GDScript (no native library).
static func find_script(world: VoxelWorld, start: Vector3i, goal: Vector3i, tall: int, max_nodes: int = MAX_NODES) -> Array[Vector3i]:
	_tables()
	var result: Array[Vector3i] = []
	if start == goal:
		return result
	var heap := _Heap.new()
	heap.push(start, _guess(start, goal))
	var closed := {}
	var came := {}
	var cost := {start: 0.0}
	var best := start
	var best_guess := _guess(start, goal)
	var visited := 0
	while not heap.is_empty() and visited < max_nodes:
		var current: Vector3i = heap.pop()
		if closed.has(current):
			continue
		closed[current] = true
		visited += 1
		if current == goal:
			best = goal
			break
		var guess := _guess(current, goal)
		if guess < best_guess:
			best_guess = guess
			best = current
		for i in NEIGHBORS.size():
			var offset: Vector2i = NEIGHBORS[i]
			if i >= 4:
				# Diagonals: both sides open at this height.
				if not _open(world, current + Vector3i(offset.x, 0, 0), tall) or not _open(world, current + Vector3i(0, 0, offset.y), tall):
					continue
			var next := _step(world, current, Vector2i(current.x + offset.x, current.z + offset.y), tall)
			if next == Vector3i.MAX or closed.has(next):
				continue
			var step := 1.41 if i >= 4 else 1.0
			if next.y > current.y:
				step += 1.0
			elif next.y < current.y:
				step += 0.5 * (current.y - next.y)
			if _swim and Blocks.liquid_table[world.get_block(next)] == 1:
				step *= 2.0
			var total: float = cost[current] + step
			if total < cost.get(next, INF):
				cost[next] = total
				came[next] = current
				heap.push(next, total + _guess(next, goal))
	last_visited = visited
	_budget -= visited
	if best == start:
		return result
	var cell := best
	while cell != start:
		result.push_front(cell)
		cell = came[cell]
	return result


## A binary min-heap of cells by score.
class _Heap:
	var cells: Array[Vector3i] = []
	var scores := PackedFloat32Array()

	func is_empty() -> bool:
		return cells.is_empty()

	func push(cell: Vector3i, score: float) -> void:
		cells.append(cell)
		scores.append(score)
		var i := cells.size() - 1
		while i > 0:
			var parent := (i - 1) / 2
			if scores[parent] <= scores[i]:
				break
			_swap(i, parent)
			i = parent

	func pop() -> Vector3i:
		var top := cells[0]
		var last := cells.size() - 1
		_swap(0, last)
		cells.resize(last)
		scores.resize(last)
		var i := 0
		while true:
			var smallest := i
			for child in [2 * i + 1, 2 * i + 2]:
				if child < last and scores[child] < scores[smallest]:
					smallest = child
			if smallest == i:
				break
			_swap(i, smallest)
			i = smallest
		return top

	func _swap(a: int, b: int) -> void:
		var cell := cells[a]
		cells[a] = cells[b]
		cells[b] = cell
		var score := scores[a]
		scores[a] = scores[b]
		scores[b] = score


## Free at that height for walking through (feet and head).
static func _open(world: VoxelWorld, cell: Vector3i, tall: int) -> bool:
	for dy in tall:
		if _solid[world.get_block(cell + Vector3i(0, dy, 0))] == 1:
			return false
	return true


static func _guess(a: Vector3i, b: Vector3i) -> float:
	var dx := absi(a.x - b.x)
	var dz := absi(a.z - b.z)
	return maxi(dx, dz) + 0.41 * mini(dx, dz) + absi(a.y - b.y) * 0.5
