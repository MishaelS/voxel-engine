class_name DungeonBehavior
extends RefCounted
## Dungeons like the classic game: a cobblestone room (mossy floor bits)
## underground with a mob spawner in the middle and up to two chests.
## - Spawners (mob_spawner_<type>) wake up when the player comes within 16
##   blocks (found by display ticks), smoke and flicker, and every 200..799
##   ticks try to spawn up to 4 of their mob around them (not when 6 are
##   already near, monsters only in the dark, none on Peaceful).
## - The generator places "dungeon_chest" markers; the first time one is
##   seen (display tick), opened or broken it turns into a chest with the
##   classic loot.

const RANGE := 16.0
const SPAWNER_TYPES: Array[String] = ["zombie", "skeleton", "spider"]
const CHEST_ROLLS := 8


## Display tick of a spawner: remembers it (MobSpawner ticks it) and
## smokes.
static func spawner_display_tick(world: VoxelWorld, pos: Vector3i, rng: RandomNumberGenerator) -> void:
	var spawner := world.entities.spawner if world.entities else null
	if spawner and not spawner.block_spawners.has(pos):
		spawner.block_spawners[pos] = 20
	var point := Vector3(pos) + Vector3(rng.randf(), rng.randf(), rng.randf())
	world.particles.smoke(point, 1)
	world.particles.torch(point)


## One game tick of a spawner block. Returns false if it is gone.
static func tick_spawner(world: VoxelWorld, pos: Vector3i, delay: int) -> int:
	var id := world.get_block(pos)
	if not Blocks.get_type(id).name.begins_with("mob_spawner_"):
		return -1
	var near := false
	for at in world.player_positions():
		near = near or at.distance_to(Vector3(pos) + Vector3(0.5, 0.5, 0.5)) <= RANGE
	if not near:
		return delay
	if delay > 0:
		return delay - 1
	var mob_type := Blocks.get_type(id).name.trim_prefix("mob_spawner_")
	if Settings.get_value("difficulty") == 0 and Mob.TYPES[mob_type].get("hostile", false):
		return randi_range(200, 799)
	var center := Vector3(pos) + Vector3(0.5, 0.5, 0.5)
	for i in 4:
		if world.entities.count_near(mob_type, center, 8.0) >= 6:
			break
		var spot := pos + Vector3i(randi_range(-4, 4), randi_range(-1, 1), randi_range(-4, 4))
		if not _can_spawn(world, spot):
			continue
		var mob := Mob.create(mob_type)
		world.entities.spawn(mob, Vector3(spot) + Vector3(0.5, 0.0, 0.5))
		mob.rotation.y = randf() * TAU
		world.particles.smoke(Vector3(spot) + Vector3(0.5, 0.5, 0.5), 6)
	return randi_range(200, 799)


static func _can_spawn(world: VoxelWorld, spot: Vector3i) -> bool:
	if not world.is_inside(spot):
		return false
	var below := world.get_block(spot + Vector3i.DOWN)
	if Blocks.collides_table[below] == 0:
		return false
	for dy in 2:
		var id := world.get_block(spot + Vector3i(0, dy, 0))
		if id != Blocks.AIR and (Blocks.collides_table[id] == 1 or Blocks.liquid_table[id] == 1):
			return false
	return world.get_combined_light(spot, MobSpawner.sky_darkness(world)) <= 7


## Display tick of a dungeon chest marker: becomes a real chest with loot.
static func chest_display_tick(world: VoxelWorld, pos: Vector3i, _rng: RandomNumberGenerator) -> void:
	open_chest(world, pos)


## Turns the dungeon chest marker at pos into a chest full of loot.
static func open_chest(world: VoxelWorld, pos: Vector3i) -> void:
	if world.remote or Blocks.family_of(world.get_block(pos)) != "dungeon_chest":
		return
	world.set_block(pos, Blocks.variant("chest", 0))
	var entity := world.block_entity(pos)
	if entity.is_empty():
		return
	var inventory: Inventory = entity.inventory
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([pos, "dungeon"])
	for roll in CHEST_ROLLS:
		var loot := _loot(rng)
		if loot.is_empty():
			continue
		var slot := rng.randi_range(0, inventory.size() - 1)
		inventory.set_slot(slot, Items.id_of(loot[0]), loot[1])


## One roll of the classic dungeon loot: [item, count] or [].
static func _loot(rng: RandomNumberGenerator) -> Array:
	match rng.randi_range(0, 10):
		0:
			return ["saddle", 1]
		1:
			return ["iron_ingot", rng.randi_range(1, 4)]
		2:
			return ["bread", 1]
		3:
			return ["wheat", rng.randi_range(1, 4)]
		4:
			return ["gunpowder", rng.randi_range(1, 4)]
		5:
			return ["string", rng.randi_range(1, 4)]
		6:
			return ["bucket", 1]
		7:
			return ["golden_apple", 1] if rng.randi_range(0, 99) == 0 else []
		8:
			return ["redstone", rng.randi_range(1, 4)] if rng.randi_range(0, 1) == 0 else []
		9:
			if rng.randi_range(0, 9) == 0:
				return ["music_disc_13" if rng.randi_range(0, 1) == 0 else "music_disc_cat", 1]
			return []
	return ["cocoa_beans", 1]


## Generator side: tries to build a dungeon in the column's blocks like
## the classic game: a room 7 or 9 blocks wide, 4 high inside, with a
## solid floor and ceiling and 1..5 openings into air at floor level
## (caves). The game tries 8 times per column; rooms here stay inside one
## column, so it tries TRIES times to come out about as often.
const TRIES := 32


static func place(blocks: PackedInt32Array, rng: RandomNumberGenerator, height: int, ids: Dictionary) -> void:
	for attempt in TRIES:
		var cx := rng.randi_range(4, 11)
		var cy := rng.randi_range(4, height - 20)
		var cz := rng.randi_range(4, 11)
		var rx := rng.randi_range(2, 3)
		var rz := rng.randi_range(2, 3)
		if cx - rx - 1 < 0 or cx + rx + 1 > 15 or cz - rz - 1 < 0 or cz + rz + 1 > 15:
			continue
		# The openings first (only the room's edge at floor level): most spots
		# have none, and scanning the whole room for each was a third of a
		# column's generation time.
		var openings := 0
		for x in range(cx - rx - 1, cx + rx + 2):
			var x_edge := x == cx - rx - 1 or x == cx + rx + 1
			for z in range(cz - rz - 1, cz + rz + 2):
				if (x_edge or z == cz - rz - 1 or z == cz + rz + 1) \
						and blocks[_index(x, cy, z)] == Blocks.AIR and blocks[_index(x, cy + 1, z)] == Blocks.AIR:
					openings += 1
		if openings < 1 or openings > 5:
			continue
		var fits := true
		for x in range(cx - rx - 1, cx + rx + 2):
			for z in range(cz - rz - 1, cz + rz + 2):
				for y in range(cy - 1, cy + 5):
					var id := blocks[_index(x, y, z)]
					var solid := id != Blocks.AIR and Blocks.collides_table[id] == 1
					if ((y == cy - 1 or y == cy + 4) and not solid) or Blocks.liquid_table[id] == 1:
						fits = false
						break
				if not fits:
					break
			if not fits:
				break
		if not fits:
			continue
		for x in range(cx - rx - 1, cx + rx + 2):
			for z in range(cz - rz - 1, cz + rz + 2):
				for y in range(cy + 3, cy - 2, -1):
					var i := _index(x, y, z)
					var edge := x == cx - rx - 1 or x == cx + rx + 1 or z == cz - rz - 1 or z == cz + rz + 1
					if y >= cy and y <= cy + 3 and not edge:
						blocks[i] = Blocks.AIR
					elif y == cy - 1 and rng.randi_range(0, 3) != 0:
						blocks[i] = ids.mossy
					elif blocks[i] != Blocks.AIR and Blocks.collides_table[blocks[i]] == 1:
						blocks[i] = ids.cobble
		# Chests along walls.
		for chest in 2:
			for tries in 3:
				var x := cx + rng.randi_range(-rx, rx)
				var z := cz + rng.randi_range(-rz, rz)
				var walls := 0
				for side: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if Blocks.collides_table[blocks[_index(x + side.x, cy, z + side.y)]] == 1:
						walls += 1
				if walls == 1 and blocks[_index(x, cy, z)] == Blocks.AIR:
					blocks[_index(x, cy, z)] = ids.chest
					break
		blocks[_index(cx, cy, cz)] = ids["spawner_" + SPAWNER_TYPES[[0, 0, 1, 2][rng.randi_range(0, 3)]]]
		return


static func _index(x: int, y: int, z: int) -> int:
	return WorldGenerator.index(x, y, z)
