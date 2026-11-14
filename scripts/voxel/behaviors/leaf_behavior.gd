class_name LeafBehavior
extends RefCounted
## Leaf decay like the classic game: leaves of trees (not the ones the
## player placed) need a log within 4 blocks, reached through leaves.
## When something next to them changes (a log is cut, a leaf decays), they
## check again a little later, at a random moment; without a log they
## fall apart and drop what they give (oak leaves sometimes an apple).
## So a tree whose trunk is cut loses its crown bit by bit.

const RANGE := 4
## Random delay before the check, in ticks (the classic game uses random
## ticks: leaves vanish over several seconds).
const MIN_DELAY := 20
const MAX_DELAY := 200


static func on_update(world: VoxelWorld, pos: Vector3i) -> void:
	world.schedule_tick(pos, world.rng.randi_range(MIN_DELAY, MAX_DELAY))


static func scheduled_tick(world: VoxelWorld, pos: Vector3i) -> void:
	if not _has_log_near(world, pos):
		world.destroy_block(pos, true, true, false)


## Breadth-first walk from the leaf through leaves, up to RANGE steps,
## looking for a log.
static func _has_log_near(world: VoxelWorld, start: Vector3i) -> bool:
	var seen := {start: true}
	var frontier: Array[Vector3i] = [start]
	for step in RANGE:
		var next: Array[Vector3i] = []
		for pos in frontier:
			for offset in VoxelWorld.NEIGHBORS:
				var other := pos + offset
				if seen.has(other):
					continue
				seen[other] = true
				if not world.is_inside(other):
					return true # unloaded: don't decay
				var name := Blocks.get_type(world.get_block(other)).name
				if Blocks.family_of(world.get_block(other)).ends_with("_log"): # lying logs too
					return true
				if name.ends_with("_leaves") or name.ends_with("_leaves_placed"):
					next.append(other)
		frontier = next
	return false
