class_name FenceBehavior
extends RefCounted
## Fences: a post with rails toward the fences next to it and, like the
## modern game's, toward full solid blocks (not leaves or pumpkins). The connections are part of the block's state ("fence" ..
## "fence_15", bits: south, west, north, east), worked out again whenever
## a neighbor changes.


static func is_fence(id: int) -> bool:
	return Blocks.family_of(id) == "fence"


static func is_gate(id: int) -> bool:
	var family := Blocks.family_of(id)
	return family == "fence_gate" or family == "fence_gate_open"


## Opens or shuts the fence gate at `pos` like the modern game's: opened
## from the side it faces, it turns round to swing away from the opener
## (`opener_facing`: Blocks' facing the opener looks; -1: keep it).
static func toggle_gate(world: VoxelWorld, pos: Vector3i, opener_facing: int = -1) -> void:
	var id := world.get_block(pos)
	if not is_gate(id):
		return
	var open := Blocks.family_of(id) == "fence_gate"
	var facing := Blocks.facing_table[id]
	if open and opener_facing >= 0 and facing == (opener_facing + 2) % 4:
		facing = opener_facing
	world.set_block(pos, Blocks.variant("fence_gate_open" if open else "fence_gate", facing))
	Sounds.play("door/" + ("open" if open else "close"), Vector3(pos) + Vector3(0.5, 0.5, 0.5), 1.0, randf() * 0.1 + 0.9)


static func on_update(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	if not is_fence(id):
		return
	var mask := 0
	for d in 4:
		if joins(world.get_block(pos + Blocks.FENCE_DIRECTIONS[d]), d):
			mask |= 1 << d
	var wanted: int = Blocks.family_ids("fence")[mask]
	if wanted != id:
		world.set_block(pos, wanted, false)


## Whether a fence reaches out to a block next to it (`direction`: 0..3,
## Blocks.FENCE_DIRECTIONS; -1 any): another fence, a fence gate across
## that way (its line goes on), or a full solid cube (stone, planks,
## glass...), but not leaves or pumpkins, like the modern game's exceptions.
static func joins(id: int, direction: int = -1) -> bool:
	if is_fence(id):
		return true
	if is_gate(id):
		# (a gate facing south or north lies across x: it joins fences east and west)
		return direction < 0 or (direction % 2) != (Blocks.facing_table[id] % 2)
	if Blocks.collides_table[id] == 0 or Blocks.shape_table[id] != BlockType.Shape.CUBE or Blocks.height_table[id] < 1.0:
		return false
	var family := Blocks.family_of(id)
	return not family.ends_with("_leaves") and not family.contains("pumpkin") and not family.contains("jack_o_lantern")
