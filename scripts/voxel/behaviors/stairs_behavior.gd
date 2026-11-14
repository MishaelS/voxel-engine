class_name StairsBehavior
extends RefCounted
## Stairs corners like the modern game (StairsBlock.getStairsShape): stairs
## next to stairs of the same half turned 90 degrees make an outer corner
## (the turned stairs behind them) or an inner corner (in front of them).
## The shape is part of the block's state (Blocks._stairs: each family's
## ids are the 4 straight facings, then 4 facings per corner shape),
## worked out again whenever a neighbor changes.
##
## Here a stairs' facing is where its low step points; the modern game's
## facing is where the high part is (behind), so "behind" below is
## -FACING_DIRECTIONS[facing].

## Shapes in family order; left / right as the game's: its facing turned
## counterclockwise (seen from above) is left.
const SHAPES: Array[String] = ["straight", "inner_left", "inner_right", "outer_left", "outer_right"]
const STRAIGHT := 0
const INNER_LEFT := 1
const INNER_RIGHT := 2
const OUTER_LEFT := 3
const OUTER_RIGHT := 4


static func is_stairs(id: int) -> bool:
	var family := Blocks.family_of(id)
	return family.ends_with("_stairs") or family.ends_with("_stairs_top")


static func is_upside_down(id: int) -> bool:
	return Blocks.family_of(id).ends_with("_stairs_top")


## The shape of a stairs block (SHAPES index).
static func shape_of(id: int) -> int:
	return Blocks.family_ids(Blocks.family_of(id)).find(id) / 4


## The stairs block of `family` with that facing and shape.
static func variant(family: String, facing: int, shape: int) -> int:
	return Blocks.family_ids(family)[shape * 4 + facing]


static func on_update(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	if not is_stairs(id):
		return
	var wanted := variant(Blocks.family_of(id), Blocks.facing_table[id], shape_at(world, pos, id))
	if wanted != id:
		world.set_block(pos, wanted, false) # neighbors only look at its facing and half, which stay


## The shape stairs `id` takes at `pos`, from the stairs behind and in front.
static func shape_at(world: VoxelWorld, pos: Vector3i, id: int) -> int:
	var back := _back(id)
	var behind := world.get_block(pos + back)
	if is_stairs(behind) and is_upside_down(behind) == is_upside_down(id):
		var turned := _back(behind)
		if turned.x != back.x and turned.z != back.z and _differs(world, pos - turned, id):
			return OUTER_LEFT if turned == _left_of(back) else OUTER_RIGHT
	var ahead := world.get_block(pos - back)
	if is_stairs(ahead) and is_upside_down(ahead) == is_upside_down(id):
		var turned := _back(ahead)
		if turned.x != back.x and turned.z != back.z and _differs(world, pos + turned, id):
			return INNER_LEFT if turned == _left_of(back) else INNER_RIGHT
	return STRAIGHT


## Where the high part of stairs is (the game's facing).
static func _back(id: int) -> Vector3i:
	return -Blocks.FACING_DIRECTIONS[Blocks.facing_table[id]]


## A direction turned counterclockwise seen from above (north -> west).
static func _left_of(direction: Vector3i) -> Vector3i:
	return Vector3i(direction.z, 0, -direction.x)


## Not stairs facing the same way on the same half as `id` (those keep a
## row of stairs straight next to a corner).
static func _differs(world: VoxelWorld, at: Vector3i, id: int) -> bool:
	var other := world.get_block(at)
	return not is_stairs(other) or Blocks.facing_table[other] != Blocks.facing_table[id] \
		or is_upside_down(other) != is_upside_down(id)
