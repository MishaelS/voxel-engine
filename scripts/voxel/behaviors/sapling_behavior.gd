class_name SaplingBehavior
extends RefCounted
## Saplings like the classic game: on a random tick, with enough light
## above (9+), one time in GROW_CHANCE they grow into a tree of their kind
## (oak, birch, spruce), the same shapes as generated trees; if there is no
## room the sapling just waits.

const GROW_LIGHT := 9
## Random ticks per growth (the modern game: 1 in 7 per stage, 2 stages).
const GROW_CHANCE := 14


static func random_tick(world: VoxelWorld, pos: Vector3i) -> void:
	if world.get_light(pos + Vector3i.UP) < GROW_LIGHT or world.rng.randi_range(1, GROW_CHANCE) != 1:
		return
	var kind := Blocks.get_type(world.get_block(pos)).name.trim_suffix("_sapling")
	grow(world, pos, kind, world.rng)


## Grows a tree of `kind` from `pos` (its trunk's lowest block). Returns
## false (and changes nothing) if there is no room.
static func grow(world: VoxelWorld, pos: Vector3i, kind: String, rng: RandomNumberGenerator) -> bool:
	var log_id := Blocks.id_of(kind + "_log")
	var leaves := Blocks.id_of(kind + "_leaves")
	var blocks := {} # Vector3i -> id: the tree, placed only if it all fits
	var height := 0
	if kind == "spruce":
		height = rng.randi_range(6, 9)
		var bare := rng.randi_range(1, 2)
		var radius := 0
		var max_radius := rng.randi_range(2, 3)
		for y in range(height, bare - 1, -1):
			for x in range(-radius, radius + 1):
				for z in range(-radius, radius + 1):
					if radius > 0 and absi(x) == radius and absi(z) == radius:
						continue
					blocks[pos + Vector3i(x, y, z)] = leaves
			radius = 0 if radius >= max_radius else radius + 1
			if radius == 0 and y < height - 1:
				radius = 1
		blocks[pos + Vector3i(0, height + 1, 0)] = leaves
	else:
		height = rng.randi_range(5, 7) if kind == "birch" else rng.randi_range(4, 6)
		for y in range(height - 3, height + 1):
			var above_top := y - height
			var radius := 1 - above_top / 2
			for x in range(-radius, radius + 1):
				for z in range(-radius, radius + 1):
					var corner := absi(x) == radius and absi(z) == radius
					if corner and (rng.randi_range(0, 1) == 0 or above_top == 0):
						continue
					blocks[pos + Vector3i(x, y, z)] = leaves
	# Room for the trunk: air, plants or the sapling itself.
	if pos.y + height + 2 >= world.height:
		return false
	for y in height:
		var there := world.get_block(pos + Vector3i(0, y, 0))
		if y > 0 and there != Blocks.AIR and Blocks.replaceable_table[there] == 0 and not Blocks.get_type(there).name.ends_with("_leaves"):
			return false
	world.set_block(pos + Vector3i.DOWN, Blocks.id_of("dirt"))
	for cell: Vector3i in blocks:
		var there := world.get_block(cell)
		if there == Blocks.AIR or Blocks.replaceable_table[there] == 1:
			world.set_block(cell, blocks[cell])
	for y in height:
		world.set_block(pos + Vector3i(0, y, 0), log_id)
	return true
