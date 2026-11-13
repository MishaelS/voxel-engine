class_name Nightmares
extends RefCounted
## Beta 1.7.3's bed rules about monsters:
## - no sleep with a monster near the bed (EntityPlayer.sleepInBedAt: any
##   EntityMob in the box bed ±8, ±5 up and down; slimes and wolves are not
##   EntityMob there);
## - nightmares (SpawnerAnimals.performSleepSpawning): when the night is
##   about to be skipped, up to 20 tries pick a random spot within 32
##   blocks of the sleeper (±16 up and down), drop it onto the ground and
##   climb to the first cell a monster may spawn in (dark like natural
##   spawning, MobSpawner._suits); a spider, zombie or skeleton there that
##   has a path to the sleeper ending next to the bed appears beside the bed
##   instead, the sleeper wakes up and the night goes on. So a bed in the
##   dark open is risky, one in a lit room is safe. Neither on Peaceful.

## Beta's nightSpawnEntities (no creepers).
const TYPES: Array[String] = ["spider", "zombie", "skeleton"]
const TRIES := 20
## The spot is at most this far along x and z (Beta: rand(32) - rand(32)).
const SPREAD := 32
## And up or down (Beta: rand(16) - rand(16)).
const SPREAD_UP := 16
## Cells a path search may look at (Beta's limit: 32 blocks).
const PATH_NODES := 1200
## The box around the bed where a monster stops the sleep.
const NEAR := Vector3(8, 5, 8)


## Whether a monster (Beta's EntityMob: not slimes) is within NEAR of the
## bed's block.
static func monsters_near(world: VoxelWorld, bed: Vector3i) -> bool:
	if Settings.get_value("difficulty") == 0:
		return false
	var low := Vector3(bed) - NEAR
	var high := Vector3(bed) + Vector3.ONE + NEAR
	for entity in world.entities.near(Vector3(bed) + Vector3(0.5, 0.5, 0.5), NEAR.length() + 2.0):
		if not entity is Mob or entity.removed:
			continue
		var mob := entity as Mob
		if not mob.is_hostile() or mob.mob_type == "slime":
			continue
		# (its box overlaps the area, like Beta's getEntitiesWithinAABB)
		var feet := mob.feet()
		if feet.x + mob.half_width > low.x and feet.x - mob.half_width < high.x \
				and feet.y + mob.height > low.y and feet.y < high.y \
				and feet.z + mob.half_width > low.z and feet.z - mob.half_width < high.z:
			return true
	return false


## Tries to send a nightmare to the sleeping player in the bed at `bed`
## (its head half). Returns true if a monster came: the player is to wake
## up and the night is not skipped.
static func haunt(world: VoxelWorld, player: Node3D, bed: Vector3i) -> bool:
	if Settings.get_value("difficulty") == 0 or world.entities.spawner == null:
		return false
	var at: Vector3 = player.global_position
	var origin := Vector3i(at.floor())
	for i in TRIES:
		var x := origin.x + randi_range(0, SPREAD - 1) - randi_range(0, SPREAD - 1)
		var z := origin.z + randi_range(0, SPREAD - 1) - randi_range(0, SPREAD - 1)
		var top := clampi(origin.y + randi_range(0, SPREAD_UP - 1) - randi_range(0, SPREAD_UP - 1), 1, WorldGenerator.HEIGHT - 3)
		var mob_type: String = TYPES[randi_range(0, TYPES.size() - 1)]
		var spot := _spot(world, mob_type, Vector3i(x, top, z))
		if spot == Vector3i.MAX:
			continue
		var path := Pathfinder.find(world, spot, origin, _tall(mob_type), PATH_NODES)
		if path.size() < 2:
			continue
		var last := path[-1]
		if absf(last.x + 0.5 - at.x) >= 1.5 or absf(last.z + 0.5 - at.z) >= 1.5 or absf(last.y - at.y) >= 1.5:
			continue
		var beside := _beside(world, bed, _tall(mob_type))
		if beside == Vector3i.MAX:
			beside = last
		var mob := Mob.create(mob_type)
		world.entities.spawn(mob, Vector3(beside) + Vector3(0.5, 0.0, 0.5))
		mob.target = player
		mob.set("_say_timer", 0) # (Beta: playLivingSound)
		return true
	return false


## Beta's search in the column: down onto a solid block (not below y 2),
## then up to SPREAD_UP cells to the first one a monster of that kind may
## spawn in (dark enough, room for it); Vector3i.MAX if none.
static func _spot(world: VoxelWorld, mob_type: String, from: Vector3i) -> Vector3i:
	if not world.is_inside(from):
		return Vector3i.MAX
	var y := from.y
	while y > 2 and Blocks.collides_table[world.get_block(Vector3i(from.x, y - 1, from.z))] == 0:
		y -= 1
	var spawner := world.entities.spawner
	while y < from.y + SPREAD_UP and y < WorldGenerator.HEIGHT - 2:
		var cell := Vector3i(from.x, y, from.z)
		if spawner._suits("monster", mob_type, cell, false):
			return cell
		y += 1
	return Vector3i.MAX


## Where a monster stands beside the bed (Beta's
## BlockBed.getNearestEmptyChunkCoordinates): the nearest cell around the
## bed at its height with ground and room for it; Vector3i.MAX if none.
static func _beside(world: VoxelWorld, bed: Vector3i, tall: int) -> Vector3i:
	var best := Vector3i.MAX
	var best_distance := INF
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			for dy in [0, 1, -1]:
				var cell := bed + Vector3i(dx, dy, dz)
				if Blocks.family_of(world.get_block(cell)).begins_with("bed_"):
					continue
				if not Pathfinder.standable(world, cell, tall):
					continue
				var distance := Vector3(cell - bed).length()
				if distance < best_distance:
					best_distance = distance
					best = cell
				break
	return best


## How many cells high the monster is (spiders are low).
static func _tall(mob_type: String) -> int:
	return 1 if mob_type == "spider" else 2
