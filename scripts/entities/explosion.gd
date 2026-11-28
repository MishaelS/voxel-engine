class_name Explosion
extends RefCounted
## Explosions like the classic game (creepers, later TNT): rays go out in
## every direction from the middle, each with a strength of power x
## (0.7..1.3), losing strength with distance and through blocks (their
## blast resistance); the blocks the rays reach are destroyed, 30% of them
## dropping as items. Creatures and the player nearby are hurt (up to
## ~8 x power right at the middle) and thrown back. Water stops it.
## What drops comes out in a few stacks thrown from the hole; the view of
## a player near it shakes (effects()).


## At most this many TNT blasts a tick: the rest go off the next tick (a
## big pile of TNT went off many at once, each a full blast in one tick).
const BLASTS_PER_TICK := 2
## Blown blocks shown flying off as bits (and told to network clients).
const DEBRIS := 40

## Time of the last blast's parts (microseconds), for profiling.
static var times := {}
static var _blast_tick := -1
static var _blasts := 0
## What a step of a ray loses going through each block (by id).
static var _ray_cost := PackedFloat32Array()


## Whether one more blast may go off this tick (PrimedTnt waits otherwise).
static func take_turn() -> bool:
	if TickLoop.tick_count != _blast_tick:
		_blast_tick = TickLoop.tick_count
		_blasts = 0
	_blasts += 1
	return _blasts <= BLASTS_PER_TICK


static func explode(world: VoxelWorld, center: Vector3, power: float, source: Variant = null) -> void:
	if _ray_cost.size() != Blocks.count():
		_ray_cost.resize(Blocks.count())
		for id in Blocks.count():
			_ray_cost[id] = (resistance(id) / 5.0 + 0.3) * 0.3
	var t0 := Time.get_ticks_usec()
	var destroyed := {}
	# The blocks the rays go through, looked up once each (the rays cross the
	# same cells near the middle hundreds of times; a ray stays in a cell for
	# about three of its steps).
	var seen := {}
	var costs := _ray_cost
	for i in 16:
		for j in 16:
			for k in 16:
				if i != 0 and i != 15 and j != 0 and j != 15 and k != 0 and k != 15:
					continue
				var dir := Vector3(i / 15.0 * 2.0 - 1.0, j / 15.0 * 2.0 - 1.0, k / 15.0 * 2.0 - 1.0).normalized() * 0.3
				var strength := power * (0.7 + randf() * 0.6)
				var point := center
				var last := Vector3i(0, -100000, 0)
				var id := Blocks.AIR
				while strength > 0.0:
					var cell := Vector3i(point.floor())
					if cell != last:
						last = cell
						var known: int = seen.get(cell, -1)
						if known < 0:
							known = world.get_block(cell)
							seen[cell] = known
						id = known
					if id != Blocks.AIR:
						strength -= costs[id]
						if strength > 0.0:
							destroyed[cell] = id
					point += dir
					strength -= 0.3 * 0.75
	var t1 := Time.get_ticks_usec()
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
	var t2 := Time.get_ticks_usec()
	var tnt := Blocks.id_of("tnt")
	# What drops (30% of the blocks, like the game) is gathered by kind and
	# thrown out in a few stacks, not an item a block (a pile of TNT left
	# over a thousand items lying about).
	var drops := {} # item id -> [count, a cell it came from]
	var debris := PackedInt32Array()
	# The blocks around the hole hear of it once each when it is all gone
	# (sand falls, water flows in, torches drop): every blown block telling
	# its six neighbors, most of them blown too, was half of a blast's time.
	var touched := {}
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
				var entry: Array = drops.get(drop[0], [0, cell])
				entry[0] += int(drop[1])
				drops[drop[0]] = entry
		if debris.size() < DEBRIS * 4 and randf() < 0.5:
			debris.append_array(PackedInt32Array([cell.x, cell.y, cell.z, id]))
		world.set_block(cell, Blocks.AIR, false)
		touched[cell] = true
		for offset in VoxelWorld.NEIGHBORS:
			touched[cell + offset] = true
	for cell: Vector3i in touched:
		world._update_block(cell)
	var t3 := Time.get_ticks_usec()
	world.end_batch()
	var t4 := Time.get_ticks_usec()
	for item_id: int in drops:
		var left: int = drops[item_id][0]
		var from := Vector3(drops[item_id][1] as Vector3i) + Vector3(0.5, 0.5, 0.5)
		while left > 0:
			var count := mini(left, mini(Items.max_stack(item_id), 16))
			left -= count
			# Thrown out of the hole, up and away from the middle.
			var away := (from - center).normalized() if from.distance_squared_to(center) > 0.01 else Vector3.UP
			var throw := away * randf_range(0.1, 0.3) + Vector3(randf_range(-0.1, 0.1), randf_range(0.2, 0.45), randf_range(-0.1, 0.1))
			world.items.spawn(item_id, count, from + Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3)), throw)
	var t5 := Time.get_ticks_usec()
	effects(world, center, power, debris)
	if Net.is_host():
		Net.send_explosion(center, power, debris)
	times = {"rays": t1 - t0, "hurt": t2 - t1, "blocks": t3 - t2, "light": t4 - t3, "drops": t5 - t4, "effects": Time.get_ticks_usec() - t5}


## What a blast looks and sounds like (the host's, and told to clients): the
## fireball, clouds, sparks and smoke, bits of the blown blocks (`debris`:
## x, y, z, id each), the bang, and the view shaking for a player near it.
static func effects(world: VoxelWorld, center: Vector3, power: float, debris: PackedInt32Array) -> void:
	world.particles.explosion(center, power, debris)
	var pitch := (1.0 + (randf() - randf()) * 0.2) * 0.7
	Sounds.play("random/explode", center, 4.0, pitch)
	if power >= 4.0:
		Sounds.play("random/explode", center, 2.5, pitch * 0.55) # (a deep rumble under the bang)
	var player := world.player as Player
	if player and not player.dead:
		var distance := player.eye_position().distance_to(center)
		player.shake(clampf(power / 4.0, 0.3, 1.5) * clampf(1.0 - distance / (power * 8.0), 0.0, 1.0))


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
