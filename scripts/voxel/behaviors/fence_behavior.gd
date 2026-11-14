class_name FenceBehavior
extends RefCounted
## Fences: a post with rails toward the fences next to it and, like the
## modern game's, toward full solid blocks (not leaves or pumpkins). The connections are part of the block's state ("fence" ..
## "fence_15", bits: south, west, north, east), worked out again whenever
## a neighbor changes.


static func is_fence(id: int) -> bool:
	return Blocks.family_of(id) == "fence"


static func on_update(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	if not is_fence(id):
		return
	var mask := 0
	for d in 4:
		if joins(world.get_block(pos + Blocks.FENCE_DIRECTIONS[d])):
			mask |= 1 << d
	var wanted: int = Blocks.family_ids("fence")[mask]
	if wanted != id:
		world.set_block(pos, wanted, false)


## Whether a fence reaches out to a block next to it: another fence, or a
## full solid cube (stone, planks, glass...), but not leaves or pumpkins,
## like the modern game's exceptions.
static func joins(id: int) -> bool:
	if is_fence(id):
		return true
	if Blocks.collides_table[id] == 0 or Blocks.shape_table[id] != BlockType.Shape.CUBE or Blocks.height_table[id] < 1.0:
		return false
	var family := Blocks.family_of(id)
	return not family.ends_with("_leaves") and not family.contains("pumpkin") and not family.contains("jack_o_lantern")
