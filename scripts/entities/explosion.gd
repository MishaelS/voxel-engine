class_name Explosion
extends RefCounted
## Explosions like the classic game (creepers, later TNT): rays go out in
## every direction from the middle, each with a strength of power x
## (0.7..1.3), losing strength with distance and through blocks (their
## blast resistance); the blocks the rays reach are destroyed, 30% of them
## dropping as items. Creatures and the player nearby are hurt (up to
## ~8 x power right at the middle) and thrown back. Water stops it.


static func explode(world: VoxelWorld, center: Vector3, power: float, source: Variant = null) -> void:
	var destroyed := {}
	for i in 16:
		for j in 16:
			for k in 16:
				if i != 0 and i != 15 and j != 0 and j != 15 and k != 0 and k != 15:
					continue
				var dir := Vector3(i / 15.0 * 2.0 - 1.0, j / 15.0 * 2.0 - 1.0, k / 15.0 * 2.0 - 1.0).normalized()
				var strength := power * (0.7 + randf() * 0.6)
				var point := center
				while strength > 0.0:
					var cell := Vector3i(point.floor())
					var id := world.get_block(cell)
					if id != Blocks.AIR:
						strength -= (resistance(id) / 5.0 + 0.3) * 0.3
						if strength > 0.0:
							destroyed[cell] = id
					point += dir * 0.3
					strength -= 0.3 * 0.75
	if source is Mob and not GameRules.flag(world, "mobGriefing"):
		destroyed.clear() # a creeper's blast hurts but breaks nothing
	# Creatures and the player.
	var reach := power * 2.0
	var player := world.player as Player
	if player and not player.dead:
		var middle := player.global_position + Vector3(0, Player.HEIGHT * 0.5, 0)
		var f := 1.0 - middle.distance_to(center) / reach
		if f > 0.0:
			player.damage(int((f * f + f) / 2.0 * 8.0 * power + 1.0))
			player.velocity += (middle - center).normalized() * f
	# The network game's other players (the host's world): hurt and pushed
	# on their computers.
	if Net.is_host():
		for avatar: RemotePlayer in Net.avatars.values():
			if not is_instance_valid(avatar) or avatar.dead:
				continue
			var middle := avatar.target_position + Vector3(0, Player.HEIGHT * 0.5, 0)
			var f := 1.0 - middle.distance_to(center) / reach
			if f > 0.0:
				avatar.damage(int((f * f + f) / 2.0 * 8.0 * power + 1.0))
				avatar.knockback(center)
	for entity in world.entities.near(center, reach):
		if entity == source or entity is PrimedTnt:
			if entity is PrimedTnt and entity != source:
				entity.velocity += (entity.center() - center).normalized() * 0.5
			continue
		var f := 1.0 - entity.center().distance_to(center) / reach
		if f > 0.0:
			entity.damage(int((f * f + f) / 2.0 * 8.0 * power + 1.0), center)
			entity.velocity += (entity.center() - center).normalized() * f
	var tnt := Blocks.id_of("tnt")
	world.begin_batch() # the hole's light all together at the end
	for cell: Vector3i in destroyed:
		var id: int = destroyed[cell]
		if world.get_block(cell) != id:
			continue
		if id == tnt:
			PrimedTnt.light(world, cell, true) # a chain reaction, on a short fuse
			continue
		if randf() < 0.3:
			for drop: Array in Blocks.drops_of(id, world.rng, true):
				world.items.drop_from_block(cell, drop[0], drop[1])
		world.set_block(cell, Blocks.AIR)
	world.end_batch()
	world.particles.explosion(center, power)
	Sounds.play("random/explode", center, 4.0, (1.0 + (randf() - randf()) * 0.2) * 0.7)


## Blast resistance like the classic game: stone-like blocks 30, obsidian
## 6000, bedrock and liquids stop explosions, others 5 x hardness.
static func resistance(id: int) -> float:
	var block := Blocks.get_type(id)
	if block.liquid:
		return 500.0
	if block.hardness < 0.0:
		return 3600000.0
	# By family: turned and upside-down stairs, top slabs count as their block.
	match Blocks.family_of(id):
		"obsidian":
			return 6000.0
		"stone", "cobblestone", "mossy_cobblestone", "bricks", "cobblestone_stairs", "cobblestone_stairs_top", \
				"cobblestone_slab", "cobblestone_slab_top", "stone_slab", "stone_slab_top", "double_stone_slab", \
				"double_cobblestone_slab":
			return 30.0
	return block.hardness * 5.0
