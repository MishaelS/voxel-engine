class_name RedstoneOre
extends RefCounted
## Redstone ore like the classic game: touching it (walking on it, hitting
## or right-clicking it) makes it glow (light 9) and sparkle with red dust;
## a random tick later it goes dark again.


static func touch(world: VoxelWorld, pos: Vector3i) -> void:
	if world == null:
		return
	if Blocks.get_type(world.get_block(pos)).name == "redstone_ore":
		world.set_block(pos, Blocks.id_of("lit_redstone_ore"))
		_sparkle(world, pos)


static func random_tick(world: VoxelWorld, pos: Vector3i) -> void:
	if Blocks.get_type(world.get_block(pos)).name == "lit_redstone_ore":
		world.set_block(pos, Blocks.id_of("redstone_ore"))


static func display_tick(world: VoxelWorld, pos: Vector3i, _rng: RandomNumberGenerator) -> void:
	_sparkle(world, pos)


## Red specks just outside every open face.
static func _sparkle(world: VoxelWorld, pos: Vector3i) -> void:
	for d in Redstone.DIRS:
		if Blocks.is_opaque_table[world.get_block(pos + d)] == 1:
			continue
		var point := Vector3(pos) + Vector3(0.5, 0.5, 0.5) + Vector3(d) * 0.5625
		var spread := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5)
		spread -= Vector3(d) * spread.dot(Vector3(d))
		world.particles.redstone(point + spread, 12)
