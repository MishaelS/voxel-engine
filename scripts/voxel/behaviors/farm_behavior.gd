class_name FarmBehavior
extends RefCounted
## Farming like the classic game:
## - a hoe turns grass or dirt (with air above) into farmland; tilling grass
##   sometimes gives seeds;
## - farmland is wet with water within 4 blocks (same level or one up), and
##   dry farmland with nothing planted turns back into dirt; landing on it
##   from a fall tramples it back into dirt; a block on it does too;
## - seeds grow into wheat on farmland: 8 stages, a random tick in 3 moves
##   it on when wet (in 6 when dry), in enough light (9+);
## - bone meal grows wheat at once, makes saplings into trees and grass
##   blocks sprout tall grass and flowers around;
## - a cake on the floor is eaten a slice at a time (6 slices).

const WATER_RANGE := 4
const GROW_LIGHT := 9


static func is_farmland(id: int) -> bool:
	return Blocks.family_of(id) == "farmland"


static func on_update(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	match Blocks.family_of(id):
		"farmland":
			if Blocks.is_opaque_table[world.get_block(pos + Vector3i.UP)] == 1:
				world.set_block(pos, Blocks.id_of("dirt"))
		"wheat_crop":
			if not is_farmland(world.get_block(pos + Vector3i.DOWN)):
				world.destroy_block(pos, true, true)
		"cake":
			if Blocks.is_opaque_table[world.get_block(pos + Vector3i.DOWN)] == 0:
				world.destroy_block(pos, false, true)


static func random_tick(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	match Blocks.family_of(id):
		"farmland":
			var wet := _has_water(world, pos)
			if wet:
				if id != Blocks.id_of("farmland_wet"):
					world.set_block(pos, Blocks.id_of("farmland_wet"))
			elif id == Blocks.id_of("farmland_wet"):
				world.set_block(pos, Blocks.id_of("farmland"))
			elif Blocks.family_of(world.get_block(pos + Vector3i.UP)) != "wheat_crop":
				world.set_block(pos, Blocks.id_of("dirt"))
		"wheat_crop":
			var stage := Blocks.family_ids("wheat_crop").find(id)
			if stage >= 7 or world.get_combined_light(pos) < GROW_LIGHT:
				return
			var wet := world.get_block(pos + Vector3i.DOWN) == Blocks.id_of("farmland_wet")
			if world.rng.randi_range(1, 3 if wet else 6) == 1:
				world.set_block(pos, Blocks.family_ids("wheat_crop")[stage + 1])


static func _has_water(world: VoxelWorld, pos: Vector3i) -> bool:
	for x in range(-WATER_RANGE, WATER_RANGE + 1):
		for z in range(-WATER_RANGE, WATER_RANGE + 1):
			for y in range(0, 2):
				if LiquidBehavior.level_at(world, pos + Vector3i(x, y, z), "water") >= 0:
					return true
	return false


## A hoe on grass or dirt with air above: farmland. Returns true if it did.
static func till(world: VoxelWorld, pos: Vector3i) -> bool:
	var name := Blocks.get_type(world.get_block(pos)).name
	if not (name.begins_with("grass_") or name == "dirt") or world.get_block(pos + Vector3i.UP) != Blocks.AIR:
		return false
	world.set_block(pos, Blocks.id_of("farmland"))
	Sounds.play_block("step", Blocks.id_of("farmland"), Vector3(pos) + Vector3(0.5, 1.0, 0.5))
	if name.begins_with("grass_") and world.rng.randi_range(0, 7) == 0:
		world.items.drop_from_block(pos + Vector3i.UP, Items.id_of("seeds"), 1)
	return true


## Landing on farmland from a fall tramples it.
static func trample(world: VoxelWorld, pos: Vector3i) -> void:
	if is_farmland(world.get_block(pos)):
		world.set_block(pos, Blocks.id_of("dirt"))


## Bone meal on a block. Returns true if it was used.
static func bone_meal(world: VoxelWorld, pos: Vector3i) -> bool:
	var id := world.get_block(pos)
	var name := Blocks.get_type(id).name
	if Blocks.family_of(id) == "wheat_crop":
		var ripe: int = Blocks.family_ids("wheat_crop")[7]
		if id == ripe:
			return false
		world.set_block(pos, ripe)
	elif name.ends_with("_sapling"):
		SaplingBehavior.grow(world, pos, name.trim_suffix("_sapling"), world.rng)
	elif name.begins_with("grass_"):
		# Tall grass and some flowers sprout around, like the classic game.
		for attempt in 64:
			var spot := pos + Vector3i.UP
			for step in world.rng.randi_range(0, 6):
				spot += Vector3i(world.rng.randi_range(-1, 1), world.rng.randi_range(-1, 1) * world.rng.randi_range(0, 2) / 2,
					world.rng.randi_range(-1, 1))
			if world.get_block(spot) != Blocks.AIR or not Blocks.get_type(world.get_block(spot + Vector3i.DOWN)).name.begins_with("grass_"):
				continue
			var plant := "tall_grass"
			if world.rng.randi_range(0, 9) == 0:
				plant = "dandelion" if world.rng.randi_range(0, 3) != 0 else "rose"
			world.set_block(spot, Blocks.id_of(plant))
	else:
		return false
	world.particles.smoke(Vector3(pos) + Vector3(0.5, 1.0, 0.5), 6)
	return true


## A slice of cake: 3 health at once, like Beta. Returns true if eaten.
static func eat_cake(world: VoxelWorld, pos: Vector3i, player: Player) -> bool:
	var id := world.get_block(pos)
	var eaten := Blocks.family_ids("cake").find(id)
	if player.health >= Player.MAX_HEALTH:
		return false
	player.heal(3)
	Sounds.play("random/eat", null, 0.5, randf_range(0.9, 1.1))
	if eaten >= 5:
		world.set_block(pos, Blocks.AIR)
	else:
		world.set_block(pos, Blocks.family_ids("cake")[eaten + 1])
	return true
