class_name SpongeBehavior
extends RefCounted
## Sponges: a dry one touching water drinks all the water REACH blocks
## around it (a 5 x 5 x 5 cube: sources and flowing water) and turns wet;
## a wet one soaks nothing more and drips while it has air under or beside
## it. A wet sponge is dried in a furnace (Smelting) and used again. Wet
## ones grow on the floor of warm seas (BetaGenerator, new worlds).

const REACH := 2


## A dry sponge placed, or something changed next to it: soaks if water
## touches it.
static func on_update(world: VoxelWorld, pos: Vector3i) -> void:
	var touching := false
	for offset in VoxelWorld.NEIGHBORS:
		if _is_water(world.get_block(pos + offset)):
			touching = true
			break
	if not touching:
		return
	var drunk := 0
	world.begin_batch()
	for dy in range(-REACH, REACH + 1):
		for dz in range(-REACH, REACH + 1):
			for dx in range(-REACH, REACH + 1):
				var cell := pos + Vector3i(dx, dy, dz)
				if _is_water(world.get_block(cell)):
					world.set_block(cell, Blocks.AIR, false)
					drunk += 1
	world.set_block(pos, Blocks.id_of("wet_sponge"), false)
	world.end_batch()
	# The water left around flows back in on its own.
	for dy in range(-REACH - 1, REACH + 2):
		for dz in range(-REACH - 1, REACH + 2):
			for dx in range(-REACH - 1, REACH + 2):
				if absi(dx) == REACH + 1 or absi(dy) == REACH + 1 or absi(dz) == REACH + 1:
					world._update_block(pos + Vector3i(dx, dy, dz))
	Sounds.play("random/splash", Vector3(pos) + Vector3(0.5, 0.5, 0.5), 0.3, 0.6)
	world.particles.splash(Vector3(pos) + Vector3(0.5, 1.0, 0.5))


static func _is_water(id: int) -> bool:
	return Blocks.liquid_table[id] == 1 and Blocks.family_of(id) == "water"


## A wet sponge drips: a drop off its underside when there is air below,
## else off a side with air next to it.
static func display_tick(world: VoxelWorld, pos: Vector3i, rng: RandomNumberGenerator) -> void:
	if rng.randi_range(0, 2) != 0:
		return
	if world.get_block(pos + Vector3i.DOWN) == Blocks.AIR:
		world.particles.drip(Vector3(pos) + Vector3(rng.randf_range(0.1, 0.9), -0.05, rng.randf_range(0.1, 0.9)))
		return
	var side := VoxelWorld.NEIGHBORS[2 + rng.randi_range(0, 3)]
	if world.get_block(pos + side) == Blocks.AIR:
		var along := Vector3(absi(side.z), 0, absi(side.x)) * rng.randf_range(-0.4, 0.4)
		world.particles.drip(Vector3(pos) + Vector3(0.5, rng.randf_range(0.1, 0.5), 0.5) + Vector3(side) * 0.53 + along)
