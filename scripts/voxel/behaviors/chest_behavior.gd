class_name ChestBehavior
extends RefCounted
## Single and large chests like the game: a chest placed next to a single
## chest facing the same way (on its left or right) joins it into a large
## chest; each half keeps its own 27 slots, opened together as 54. When one
## half goes, the other becomes a single chest again.


## The direction to the right of a chest's front, seen from the front.
static func is_chest(id: int) -> bool:
	return Blocks.family_of(id).begins_with("chest")


static func right_of(facing: int) -> Vector3i:
	return [Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(0, 0, -1)][facing]


## The other half of a large chest, or null.
static func partner(world: VoxelWorld, pos: Vector3i) -> Variant:
	var id := world.get_block(pos)
	var part := Blocks.chest_part_table[id]
	if not is_chest(id) or part == ChestModel.Part.SINGLE:
		return null
	var facing := Blocks.facing_table[id]
	# The left half has its partner on the right, the right half on the left.
	var other: Vector3i = pos + right_of(facing) * (1 if part == ChestModel.Part.LEFT else -1)
	var other_id := world.get_block(other)
	var wanted := ChestModel.Part.RIGHT if part == ChestModel.Part.LEFT else ChestModel.Part.LEFT
	if is_chest(other_id) and Blocks.chest_part_table[other_id] == wanted \
			and Blocks.facing_table[other_id] == facing:
		return other
	return null


## The chest to place at `pos` facing `facing`: half of a large chest when a
## single chest facing the same way is beside it (that one becomes the
## other half), else a single chest.
static func place(world: VoxelWorld, pos: Vector3i, facing: int) -> void:
	var right := right_of(facing)
	for side: int in [1, -1]:
		var other: Vector3i = pos + right * side
		var other_id := world.get_block(other)
		if is_chest(other_id) \
				and Blocks.chest_part_table[other_id] == ChestModel.Part.SINGLE \
				and Blocks.facing_table[other_id] == facing:
			# The new chest is the left half when the other one is on its right.
			var mine := "chest_left" if side == 1 else "chest_right"
			var theirs := "chest_right" if side == 1 else "chest_left"
			world.set_block(pos, Blocks.variant(mine, facing), false)
			world.set_block(other, Blocks.variant(theirs, facing))
			world.set_block(pos, Blocks.variant(mine, facing)) # (updates neighbors)
			return
	world.set_block(pos, Blocks.variant("chest", facing))


## A half without its partner becomes a single chest.
static func on_update(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	if Blocks.chest_part_table[id] != ChestModel.Part.SINGLE and partner(world, pos) == null:
		world.set_block(pos, Blocks.variant("chest", Blocks.facing_table[id]))
