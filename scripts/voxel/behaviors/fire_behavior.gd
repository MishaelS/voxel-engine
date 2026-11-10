class_name FireBehavior
extends RefCounted
## Fire like the classic game (BlockFire):
## - it burns on top of a solid block or next to something that burns;
## - every 40 ticks (and a bit) it grows older (age 0..15, its variants
##   "fire" .. "fire_15"); old fire with nothing to burn goes out;
## - each tick it may catch its neighbors (BlockType.fire_burn): they burn
##   away, sometimes leaving fire in their place;
## - it spreads to air cells around it (up to 4 above) next to things that
##   burn (BlockType.fire_spread), more easily upward;
## - it crackles and smokes (display ticks); it hurts and sets on fire
##   whoever walks in (Player, Entity).

const TICK_DELAY := 40
const MAX_AGE := 15


static func fire_id(age: int) -> int:
	return Blocks.variant("fire", clampi(age, 0, MAX_AGE))


static func is_fire(id: int) -> bool:
	return Blocks.family_of(id) == "fire"


## Fire can be at `pos`: on a solid block, or next to something that burns.
static func can_burn_at(world: VoxelWorld, pos: Vector3i) -> bool:
	if Blocks.is_opaque_table[world.get_block(pos + Vector3i.DOWN)] == 1:
		return true
	return _spread_chance(world, pos) > 0


## Lights a fire at `pos` (flint and steel, lava): air only, where it can burn.
static func ignite(world: VoxelWorld, pos: Vector3i) -> bool:
	if world.get_block(pos) != Blocks.AIR or not world.is_inside(pos) or not can_burn_at(world, pos):
		return false
	world.set_block(pos, fire_id(0))
	return true


static func on_update(world: VoxelWorld, pos: Vector3i) -> void:
	if not can_burn_at(world, pos):
		world.set_block(pos, Blocks.AIR)
		return
	world.schedule_tick(pos, TICK_DELAY + world.rng.randi_range(0, 9))


static func scheduled_tick(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	if not is_fire(id):
		return
	var rng := world.rng
	var age: int = Blocks.family_ids("fire").find(id)
	if age < MAX_AGE:
		age = mini(age + rng.randi_range(0, 2) / 2, MAX_AGE)
		world.set_block(pos, fire_id(age), false)
	world.schedule_tick(pos, TICK_DELAY + rng.randi_range(0, 9))
	# Rain puts out fire it falls on (or next to), like the game.
	for offset: Vector3i in [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		if WeatherEffects.rains_at(world, pos + offset):
			world.set_block(pos, Blocks.AIR)
			return
	var below := world.get_block(pos + Vector3i.DOWN)
	if not can_burn_at(world, pos):
		if Blocks.is_opaque_table[below] == 0 or age > 3:
			world.set_block(pos, Blocks.AIR)
		return
	if Blocks.get_type(below).fire_burn == 0 and age == MAX_AGE and rng.randi_range(0, 3) == 0:
		world.set_block(pos, Blocks.AIR)
		return
	# Neighbors catch fire and burn away.
	for offset: Vector3i in VoxelWorld.NEIGHBORS:
		_try_burn(world, pos + offset, 250 if offset.y != 0 else 300, age)
	# Spread to the air around (up to 4 above), harder higher up.
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for dy in range(-1, 5):
				if dx == 0 and dy == 0 and dz == 0:
					continue
				var cell := pos + Vector3i(dx, dy, dz)
				if world.get_block(cell) != Blocks.AIR:
					continue
				var odds := 100 + (maxi(dy - 1, 0)) * 100
				var chance := _spread_chance(world, cell)
				if chance > 0 and rng.randi_range(0, odds - 1) <= chance:
					world.set_block(cell, fire_id(0))


## A neighbor burns away with its flammability out of `odds`; it may leave
## fire behind (more likely while the fire is young).
static func _try_burn(world: VoxelWorld, pos: Vector3i, odds: int, age: int) -> void:
	var id := world.get_block(pos)
	var burn := Blocks.get_type(id).fire_burn
	if burn <= 0 or world.rng.randi_range(0, odds - 1) >= burn:
		return
	if Blocks.get_type(id).name == "tnt":
		PrimedTnt.light(world, pos) # TNT catches fire: lit
		return
	if world.rng.randi_range(0, age + 9) < 5:
		world.set_block(pos, fire_id(0))
	else:
		world.set_block(pos, Blocks.AIR)


## How much the blocks around an air cell make fire spread there.
static func _spread_chance(world: VoxelWorld, pos: Vector3i) -> int:
	var best := 0
	for offset: Vector3i in VoxelWorld.NEIGHBORS:
		best = maxi(best, Blocks.get_type(world.get_block(pos + offset)).fire_spread)
	return best


static func display_tick(world: VoxelWorld, pos: Vector3i, rng: RandomNumberGenerator) -> void:
	if rng.randi_range(0, 23) == 0:
		Sounds.play("fire/fire", Vector3(pos) + Vector3(0.5, 0.5, 0.5), 1.0 + rng.randf(), rng.randf() * 0.7 + 0.3)
	world.particles.smoke(Vector3(pos) + Vector3(0.5, 0.7, 0.5), 2)
