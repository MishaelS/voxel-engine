class_name NatureBehavior
extends RefCounted
## Cactus, sugar cane and mushrooms like the classic game, and springs.
## - Cactus stands on sand or cactus with nothing solid beside it (it breaks
##   otherwise), grows up to 3 high (a random tick in 16 adds a block on
##   top) and pricks whoever touches it (Player, Entity: 1 damage).
## - Sugar cane stands on sugar cane, or on grass / dirt / sand with water
##   right next to that block; grows up to 3 high like cactus.
## - Mushrooms stand on a solid block in the dark (light below 13) and now
##   and then spread to a dark spot nearby.
## - Springs (generated in cave walls) turn into a source when the player
##   comes near (display ticks) and start flowing.

const MAX_HEIGHT := 3
const GROW_CHANCE := 16
const MUSHROOM_LIGHT := 13


static func on_update(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	if not can_stay(world, pos, id):
		world.destroy_block(pos, true, true)


static func can_stay(world: VoxelWorld, pos: Vector3i, id: int) -> bool:
	var name := Blocks.get_type(id).name
	var below := world.get_block(pos + Vector3i.DOWN)
	var below_name := Blocks.get_type(below).name
	match name:
		"cactus":
			for offset: Vector3i in LiquidBehavior.HORIZONTAL:
				if Blocks.collides_table[world.get_block(pos + offset)] == 1:
					return false
			return below_name == "cactus" or below_name == "sand"
		"sugar_cane_block":
			if below_name == "sugar_cane_block":
				return true
			if not (below_name.begins_with("grass_") or below_name == "dirt" or below_name == "sand"):
				return false
			for offset: Vector3i in LiquidBehavior.HORIZONTAL:
				if LiquidBehavior.level_at(world, pos + Vector3i.DOWN + offset, "water") >= 0:
					return true
			return false
		"brown_mushroom", "red_mushroom":
			return Blocks.is_opaque_table[below] == 1 and world.get_combined_light(pos) < MUSHROOM_LIGHT
	return true


static func random_tick(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	var name := Blocks.get_type(id).name
	if name == "cactus" or name == "sugar_cane_block":
		if world.get_block(pos + Vector3i.UP) != Blocks.AIR or world.rng.randi_range(1, GROW_CHANCE) != 1:
			return
		var height := 1
		while Blocks.get_type(world.get_block(pos - Vector3i(0, height, 0))).name == name:
			height += 1
		if height < MAX_HEIGHT and can_stay(world, pos + Vector3i.UP, id):
			world.set_block(pos + Vector3i.UP, id)
	elif name.ends_with("_mushroom") and world.rng.randi_range(0, 99) == 0:
		var spot := pos + Vector3i(world.rng.randi_range(-1, 1), world.rng.randi_range(0, 1) - world.rng.randi_range(0, 1),
			world.rng.randi_range(-1, 1))
		if world.get_block(spot) == Blocks.AIR and can_stay(world, spot, id):
			world.set_block(spot, id)


static func spring_display_tick(world: VoxelWorld, pos: Vector3i, _rng: RandomNumberGenerator) -> void:
	var family := Blocks.family_of(world.get_block(pos))
	world.set_block(pos, Blocks.variant(family, 0))
