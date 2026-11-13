class_name SaplingBehavior
extends RefCounted
## Saplings like the classic game: on a random tick, with enough light
## above (9+), one time in GROW_CHANCE they grow into a tree of their kind
## (oak, birch, spruce; oaks sometimes big), the same shapes as generated
## trees; if there is no room the sapling just waits.

const GROW_LIGHT := 9
## Random ticks per growth (the modern game: 1 in 7 per stage, 2 stages).
const GROW_CHANCE := 14


static func random_tick(world: VoxelWorld, pos: Vector3i) -> void:
	if world.get_light(pos + Vector3i.UP) < GROW_LIGHT or world.rng.randi_range(1, GROW_CHANCE) != 1:
		return
	var kind := Blocks.get_type(world.get_block(pos)).name.trim_suffix("_sapling")
	grow(world, pos, kind, world.rng)


## Grows a tree of `kind` from `pos` (its trunk's lowest block), like Beta
## 1.7.3's saplings (TreeShapes): spruce, birch, or an oak (a big one 1 in
## 10). Returns false (and changes nothing) if there is no room.
static func grow(world: VoxelWorld, pos: Vector3i, kind: String, rng: RandomNumberGenerator) -> bool:
	var canvas := TreeShapes.WorldCanvas.new(world)
	var sapling := world.get_block(pos)
	world.set_block(pos, Blocks.AIR) # (the tree's room counts it as air)
	var grown := false
	match kind:
		"spruce":
			grown = TreeShapes.spruce(canvas, rng, pos.x, pos.y, pos.z)
		"birch":
			grown = TreeShapes.oak(canvas, rng, pos.x, pos.y, pos.z, Blocks.id_of("birch_log"), Blocks.id_of("birch_leaves"), 5)
		_:
			if rng.randi_range(0, 9) == 0:
				grown = TreeShapes.big_oak(canvas, rng, pos.x, pos.y, pos.z)
			else:
				grown = TreeShapes.oak(canvas, rng, pos.x, pos.y, pos.z, Blocks.id_of("oak_log"), Blocks.id_of("oak_leaves"), 4)
	if not grown:
		world.set_block(pos, sapling)
	return grown
