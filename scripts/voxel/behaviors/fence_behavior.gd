class_name FenceBehavior
extends RefCounted
## Fences like the classic game: a post with rails toward the fences next
## to it. The connections are part of the block's state ("fence" ..
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
		if is_fence(world.get_block(pos + Blocks.FENCE_DIRECTIONS[d])):
			mask |= 1 << d
	var wanted: int = Blocks.family_ids("fence")[mask]
	if wanted != id:
		world.set_block(pos, wanted, false)
