class_name GrassBehavior
extends RefCounted
## Grass random tick, as in the classic game (without the light check, since
## there is no block light yet):
## - covered by an opaque block -> turns into dirt;
## - otherwise tries to spread onto dirt nearby (x/z +-1, y -3..+1) that has
##   no opaque block on top, keeping its own biome tint.

const SPREAD_ATTEMPTS := 4

static var _dirt := -1


static func random_tick(world: VoxelWorld, pos: Vector3i) -> void:
	if _dirt < 0:
		_dirt = Blocks.id_of("dirt")
	var grass := world.get_block(pos)

	if Blocks.is_opaque(world.get_block(pos + Vector3i.UP)):
		world.set_block(pos, _dirt)
		return

	for i in SPREAD_ATTEMPTS:
		var target := pos + Vector3i(world.rng.randi_range(-1, 1), world.rng.randi_range(-3, 1), world.rng.randi_range(-1, 1))
		if world.get_block(target) == _dirt and not Blocks.is_opaque(world.get_block(target + Vector3i.UP)):
			world.set_block(target, grass)
