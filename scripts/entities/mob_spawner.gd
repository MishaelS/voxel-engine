class_name MobSpawner
extends RefCounted
## Natural mob spawning like the classic game, once a second around each
## player, the network game's too (24..64 blocks away, never closer):
## - monsters (zombies, skeletons, creepers, spiders) in groups of 1..4
##   where it is dark (combined light 7 or less, the night sky counts as
##   dark), on solid ground with two free blocks above; slimes in slime
##   chunks (1 in 10, from the seed) below y 40. Up to 40 at a time, none
##   on Peaceful;
## - animals (pigs, cows, sheep, chickens; wolves in forests and taiga)
##   on lit grass, up to 15;
## - squid in water, up to 5.
## Mobs far away despawn on their own (Mob._despawn).

const INTERVAL := 20
const MIN_DISTANCE := 24.0
const MAX_DISTANCE := 64.0
const TRIES := 12
const CAPS := {"monster": 40, "animal": 15, "water": 5}
const MONSTERS: Array[String] = ["zombie", "skeleton", "creeper", "spider"]
const ANIMALS: Array[String] = ["pig", "cow", "sheep", "chicken"]
const WOLF_BIOMES: Array[String] = ["forest", "taiga", "seasonal_forest", "rainforest"]

var world: VoxelWorld
var enabled := true
## Spawner blocks seen near the player: position -> ticks until they spawn
## (DungeonBehavior).
var block_spawners := {}
var _counter := 0
## The little mobs turning inside the known spawners: position -> view.
var _views := {}


## Keeps a SpawnerMobView inside every spawner known (and none in gone
## ones).
func _update_views() -> void:
	for pos: Vector3i in _views.keys():
		if not block_spawners.has(pos) or not is_instance_valid(_views[pos]):
			if is_instance_valid(_views[pos]):
				(_views[pos] as Node).queue_free()
			_views.erase(pos)
	for pos: Vector3i in block_spawners:
		if not _views.has(pos):
			var type := Blocks.get_type(world.get_block(pos)).name.trim_prefix("mob_spawner_")
			if not Mob.TYPES.has(type):
				continue
			var view := SpawnerMobView.create(world, pos, type)
			world.add_child(view)
			_views[pos] = view


func _init(owner: VoxelWorld) -> void:
	world = owner


func tick() -> void:
	for pos: Vector3i in block_spawners.keys():
		var delay := DungeonBehavior.tick_spawner(world, pos, block_spawners[pos])
		if delay < 0:
			block_spawners.erase(pos)
		else:
			block_spawners[pos] = delay
	_update_views()
	_counter += 1
	if not enabled or _counter % INTERVAL != 0:
		return
	var around := _player_positions()
	if around.is_empty():
		return
	var counts := {"monster": 0, "animal": 0, "water": 0}
	for entity in world.entities.all():
		if entity is Mob:
			counts[_category((entity as Mob).mob_type)] += 1
	var peaceful: bool = Settings.get_value("difficulty") == 0
	for category: String in CAPS:
		if category == "monster" and peaceful:
			continue
		# Like the game's caps that grow with the loaded area: one share per player.
		if counts[category] >= CAPS[category] * around.size():
			continue
		for at in around:
			for i in TRIES:
				if _try_spawn(category, at):
					break


## Where the living players are: this one and, hosting, the clients' (Net).
func _player_positions() -> Array[Vector3]:
	var result: Array[Vector3] = []
	var player := world.player as Player
	if player and not player.dead:
		result.append(player.global_position)
	if Net.is_host():
		for avatar: RemotePlayer in Net.avatars.values():
			if is_instance_valid(avatar) and not avatar.dead:
				result.append(avatar.target_position)
	return result


static func _category(mob_type: String) -> String:
	if mob_type == "squid":
		return "water"
	if Mob.TYPES[mob_type].get("hostile", false):
		return "monster"
	return "animal"


## Picks a random spot around the player and spawns a group there if the
## spot suits the category. Returns true if something spawned.
func _try_spawn(category: String, around: Vector3) -> bool:
	var angle := randf() * TAU
	var distance := randf_range(MIN_DISTANCE, MAX_DISTANCE)
	var x := floori(around.x + cos(angle) * distance)
	var z := floori(around.z + sin(angle) * distance)
	# Monsters: any height up to the ground there (not the empty sky above).
	var y := randi_range(1, maxi(world.surface_height(x, z) + 1, 2))
	if category != "monster":
		y = _surface(x, z)
		if y < 0:
			return false
	var pos := Vector3i(x, y, z)
	if not world.is_inside(pos):
		return false
	var mob_type := _choose(category, pos)
	if mob_type == "":
		return false
	var group := randi_range(1, 4) if category != "water" else randi_range(1, 2)
	var spawned := 0
	for i in group:
		var spot := pos + Vector3i(randi_range(-3, 3), 0, randi_range(-3, 3)) if i > 0 else pos
		if i > 0:
			# Look up and down a little for the group members' ground.
			for dy in [0, 1, -1]:
				if _suits(category, mob_type, spot + Vector3i(0, dy, 0)):
					spot += Vector3i(0, dy, 0)
					break
		if not _suits(category, mob_type, spot):
			continue
		var mob := Mob.create(mob_type)
		if mob_type == "slime":
			mob.size = [1, 2, 4][randi_range(0, 2)]
		if mob_type == "sheep":
			mob.wool_color = Mob.natural_wool()
		world.entities.spawn(mob, Vector3(spot) + Vector3(0.5, 0.0, 0.5))
		mob.rotation.y = randf() * TAU
		spawned += 1
	return spawned > 0


## The air cell above the highest solid block or water in the column, -1
## if there is none loaded.
func _surface(x: int, z: int) -> int:
	for y in range(WorldGenerator.HEIGHT - 1, 0, -1):
		var id := world.get_block(Vector3i(x, y, z))
		if id == Blocks.AIR:
			continue
		if Blocks.liquid_table[id] == 1:
			return y # squid spawn inside the water
		if Blocks.collides_table[id] == 1:
			return y + 1
		if Blocks.get_type(id).name.ends_with("_leaves"):
			return -1
	return -1


func _choose(category: String, pos: Vector3i) -> String:
	match category:
		"water":
			return "squid"
		"animal":
			var biome := world.biome_at(pos.x, pos.z)
			if biome in WOLF_BIOMES and randi_range(0, 4) == 0:
				return "wolf"
			return ANIMALS[randi_range(0, ANIMALS.size() - 1)]
		_:
			if pos.y < 40 + WorldGenerator.LEGACY_SHIFT and is_slime_chunk(world.world_generator.world_seed if world.world_generator else 0, pos.x >> 4, pos.z >> 4) \
					and randi_range(0, 4) == 0:
				return "slime"
			return MONSTERS[randi_range(0, MONSTERS.size() - 1)]


## Whether a mob of that kind may stand at pos (its feet's cell).
func _suits(category: String, mob_type: String, pos: Vector3i) -> bool:
	if not world.is_inside(pos) or pos.y < 1 or pos.y >= WorldGenerator.HEIGHT - 2:
		return false
	var feet := world.get_block(pos)
	if category == "water":
		return Blocks.liquid_table[feet] == 1 and Blocks.family_of(feet) == "water" \
			and Blocks.family_of(world.get_block(pos + Vector3i.DOWN)) == "water"
	var below := world.get_block(pos + Vector3i.DOWN)
	if Blocks.collides_table[below] == 0 or Blocks.liquid_table[below] == 1:
		return false
	if not _free(feet) or not _free(world.get_block(pos + Vector3i.UP)):
		return false
	if mob_type == "spider" and not (_free(world.get_block(pos + Vector3i(1, 0, 0))) and _free(world.get_block(pos + Vector3i(0, 0, 1)))):
		return false
	for at in _player_positions():
		if at.distance_to(Vector3(pos)) < MIN_DISTANCE:
			return false
	if category == "animal":
		return Blocks.get_type(below).name.begins_with("grass") and world.get_combined_light(pos, sky_darkness(world)) >= 9
	if mob_type == "slime":
		return true
	return world.get_combined_light(pos, sky_darkness(world)) <= 7 and randi_range(0, 31) >= world.get_light(pos) - roundi(sky_darkness(world))


static func _free(id: int) -> bool:
	return id == Blocks.AIR or (Blocks.collides_table[id] == 0 and Blocks.liquid_table[id] == 0)


## How many levels the night takes off the sky light (11 at midnight).
static func sky_darkness(world: VoxelWorld) -> float:
	var atmosphere := Atmosphere.find(world.get_tree())
	var daylight := atmosphere.daylight if atmosphere else 1.0
	return (1.0 - clampf(daylight, 0.0, 1.0)) * 11.0


## Slime chunks like the classic game: 1 in 10 chunks, from the seed.
static func is_slime_chunk(seed_value: int, cx: int, cz: int) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, cx, cz, "slime"])
	return rng.randi_range(0, 9) == 0
