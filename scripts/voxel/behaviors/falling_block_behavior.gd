class_name FallingBlockBehavior
extends RefCounted
## Sand and gravel: when the block or a neighbor changes, check again in
## FALL_DELAY ticks; if there is air or water below, the block becomes a
## falling entity (FallingBlocks) that accelerates down smoothly and turns
## back into a block where it lands - like the classic game.

const FALL_DELAY := 2


static func on_update(world: VoxelWorld, pos: Vector3i) -> void:
	world.schedule_tick(pos, FALL_DELAY)


static func scheduled_tick(world: VoxelWorld, pos: Vector3i) -> void:
	var below := pos + Vector3i.DOWN
	if not world.is_inside(below):
		return
	var below_id := world.get_block(below)
	if below_id != Blocks.AIR and Blocks.liquid_table[below_id] == 0:
		return
	world.start_falling(pos)
