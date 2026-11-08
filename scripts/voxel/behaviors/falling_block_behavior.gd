class_name FallingBlockBehavior
extends RefCounted
## Sand and gravel: when the block or a neighbor changes, check again in
## FALL_DELAY ticks; if there is air or water below, move one block down and
## repeat (falls 10 blocks per second at 20 TPS).
## Simplification: the classic game turns the block into a falling entity;
## until entities exist the block moves block by block.

const FALL_DELAY := 2

static var _water := -1


static func on_update(world: VoxelWorld, pos: Vector3i) -> void:
	world.schedule_tick(pos, FALL_DELAY)


static func scheduled_tick(world: VoxelWorld, pos: Vector3i) -> void:
	if _water < 0:
		_water = Blocks.id_of("water")
	var below := pos + Vector3i.DOWN
	if not world.is_inside(below):
		return
	var below_id := world.get_block(below)
	if below_id != Blocks.AIR and below_id != _water:
		return
	var id := world.get_block(pos)
	world.set_block(pos, Blocks.AIR)
	world.set_block(below, id) # the update at the new position schedules the next step
