class_name TorchBehavior
extends RefCounted
## Torches like the classic game: on the floor or on a wall (leaning away
## from it), they need a solid block to hold them: on the block below, or
## the wall behind. Without it they fall off (and drop). A small flame and
## smoke come out of the tip (display ticks).

## Where the torch's flame is, from the block's corner (floor torch).
const FLOOR_TIP := Vector3(0.5, 0.7, 0.5)


## The block holding a torch, or the torch's own position for odd cases.
static func support_of(world: VoxelWorld, pos: Vector3i) -> Vector3i:
	var id := world.get_block(pos)
	var facing := Blocks.facing_table[id]
	if Blocks.family_of(id) == "wall_torch":
		return pos - Blocks.FACING_DIRECTIONS[facing]
	return pos + Vector3i.DOWN


## A block a torch can stand on or hang from: a full opaque block.
static func can_hold(world: VoxelWorld, pos: Vector3i) -> bool:
	return Blocks.is_opaque_table[world.get_block(pos)] == 1


static func on_update(world: VoxelWorld, pos: Vector3i) -> void:
	if not can_hold(world, support_of(world, pos)):
		world.destroy_block(pos, true, true)


static func display_tick(world: VoxelWorld, pos: Vector3i, _rng: RandomNumberGenerator) -> void:
	var id := world.get_block(pos)
	var tip := Vector3(pos) + FLOOR_TIP
	if Blocks.family_of(id) == "wall_torch":
		# Leaning away from the wall: the tip is higher and out from it.
		var out := Vector3(Blocks.FACING_DIRECTIONS[Blocks.facing_table[id]])
		tip = Vector3(pos) + Vector3(0.5, 0.92, 0.5) - out * 0.27
	world.particles.torch(tip)
