class_name GrassBehavior
extends RefCounted
## Grass blocks on a random tick, like the classic game:
## - under water (any liquid above) or under a block that lets little light
##   through with almost no light (< 4) above -> turns into dirt; an opaque
##   block on top always kills it;
## - with enough light above (9+) it spreads onto dirt nearby (x/z +-1,
##   y -3..+1) that is not covered and not under water, keeping its own
##   biome tint.

const SPREAD_ATTEMPTS := 4
const SPREAD_LIGHT := 9
const SURVIVE_LIGHT := 4

static var _dirt := -1


static func random_tick(world: VoxelWorld, pos: Vector3i) -> void:
	if _dirt < 0:
		_dirt = Blocks.id_of("dirt")
	var grass := world.get_block(pos)
	if not can_live(world, pos):
		world.set_block(pos, _dirt)
		return
	if world.get_light(pos + Vector3i.UP) < SPREAD_LIGHT:
		return
	for i in SPREAD_ATTEMPTS:
		var target := pos + Vector3i(world.rng.randi_range(-1, 1), world.rng.randi_range(-3, 1), world.rng.randi_range(-1, 1))
		if world.get_block(target) == _dirt and can_live(world, target):
			world.set_block(target, grass)


## Grass can stay on the block at `pos`: nothing opaque or liquid on top,
## and some light comes in.
static func can_live(world: VoxelWorld, pos: Vector3i) -> bool:
	var above := world.get_block(pos + Vector3i.UP)
	if Blocks.is_opaque(above) or Blocks.liquid_table[above] == 1:
		return false
	return Blocks.light_opacity_table[above] <= 2 or world.get_light(pos + Vector3i.UP) >= SURVIVE_LIGHT
