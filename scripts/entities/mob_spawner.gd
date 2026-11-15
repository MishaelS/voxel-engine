class_name MobSpawner
extends RefCounted
## Natural mob spawning like Beta 1.7.3's (SpawnerAnimals), once a second
## around each player, the network game's too (24..64 blocks away, never
## closer). Each try picks a spot, then the group spreads from it by hops
## of up to 5 blocks (3 times 4 hops, like Beta), every member where it
## suits its kind; a group is at most 4 (wolves: 8).
## - monsters by weight (Beta's biome lists: spider, zombie, skeleton,
##   creeper, slime, 10 each) where it is dark: the sky light there not
##   above a random 0..31 and the light (the night taken off) not above a
##   random 0..7, on a solid block with room above; slimes only in slime
##   chunks (1 in 10, from the seed) below y 16 (above the sea's level in
##   taller worlds the same way), 1 try in 10. Up to 70 around a player,
##   none on Peaceful;
## - animals by weight (sheep 12, pig 10, chicken 10, cow 8; wolves 2 in
##   forests and taiga, Beta's BiomeGenForest and BiomeGenTaiga) on grass
##   (snowy grass too) in light above 8 (the night taken off: by day or by
##   torches), up to 15 around a player;
## - squid in water, up to 5.
## Monsters far away despawn on their own (Mob._despawn); animals stay.

const INTERVAL := 20
const MIN_DISTANCE := 24.0
const MAX_DISTANCE := 64.0
const TRIES := 12
## Counted within COUNT_RANGE of each player (Beta: in the loaded area).
const CAPS := {"monster": 70, "animal": 15, "water": 5}
const COUNT_RANGE := 128.0
const MONSTERS := {"spider": 10, "zombie": 10, "skeleton": 10, "creeper": 10, "slime": 10}
const ANIMALS := {"sheep": 12, "pig": 10, "chicken": 10, "cow": 8}
const WOLF_BIOMES: Array[String] = ["forest", "taiga"]
const WOLF_WEIGHT := 2
## Most of a group (Beta's getMaxSpawnedInChunk).
const GROUP := 4
const WOLF_GROUP := 8

var world: VoxelWorld
var enabled := true
## Spawner blocks seen near the player: position -> ticks until they spawn
## (DungeonBehavior).
var block_spawners := {}
var _counter := 0
## The little mobs turning inside the known spawners: position -> view.
var _views := {}
## Worked out once per spawning round (not for every spot tried): the
## players' positions and how dark the night makes the sky.
var _round_players: Array[Vector3] = []
var _round_darkness := -1.0
## Block id -> 1 for leaves (where animals don't spawn on top).
static var _leaves := PackedByteArray()


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
	if not enabled or _counter % INTERVAL != 0 or world.generator == VoxelWorld.Generator.DEBUG:
		return
	var around := _player_positions()
	if around.is_empty():
		return
	var peaceful: bool = Settings.get_value("difficulty") == 0
	_round_players = around
	_round_darkness = sky_darkness(world)
	_spawn_round(around, peaceful)
	_round_players = []
	_round_darkness = -1.0


func _spawn_round(around: Array[Vector3], peaceful: bool) -> void:
	for at in around:
		var counts := {"monster": 0, "animal": 0, "water": 0}
		for entity in world.entities.near(at, COUNT_RANGE):
			if entity is Mob and not entity.removed:
				counts[_category((entity as Mob).mob_type)] += 1
		for category: String in CAPS:
			if category == "monster" and peaceful:
				continue
			if counts[category] >= CAPS[category]:
				continue
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


## Picks a random spot around the player and spreads a group from it (Beta's
## hops), each member where it suits its kind. Returns true if something
## spawned.
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
	var start := Vector3i(x, y, z)
	if not world.is_inside(start):
		return false
	var mob_type := _choose(category, start)
	if mob_type == "":
		return false
	var most := WOLF_GROUP if mob_type == "wolf" else GROUP
	var spawned := 0
	for cluster in 3:
		var spot := start
		for hop in 4:
			spot += Vector3i(randi_range(0, 5) - randi_range(0, 5), 0, randi_range(0, 5) - randi_range(0, 5))
			if category != "monster":
				# (on the ground there: hills go up and down)
				var ground := _surface(spot.x, spot.z)
				if ground < 0 or absi(ground - spot.y) > 4:
					continue
				spot.y = ground
			if not _suits(category, mob_type, spot):
				continue
			var mob := Mob.create(mob_type)
			if mob_type == "slime":
				mob.size = [1, 2, 4][randi_range(0, 2)]
			if mob_type == "sheep":
				mob.wool_color = Mob.natural_wool()
			mob.equip()
			world.entities.spawn(mob, Vector3(spot) + Vector3(0.5, 0.0, 0.5))
			mob.rotation.y = randf() * TAU
			mob.set("_yaw", mob.rotation.y)
			mob.set("_prev_yaw", mob.rotation.y)
			spawned += 1
			if spawned >= most:
				return true
	return spawned > 0


## The air cell above the highest solid block or water in the column, -1
## if there is none loaded. (Chunks of only air, most of the sky, are
## skipped whole.)
func _surface(x: int, z: int) -> int:
	if _leaves.is_empty():
		_leaves.resize(Blocks.collides_table.size())
		for id in _leaves.size():
			_leaves[id] = int(Blocks.get_type(id) != null and Blocks.get_type(id).name.ends_with("_leaves"))
	var chunks: Dictionary = world.get("_chunks")
	var liquid := Blocks.liquid_table
	var collides := Blocks.collides_table
	var column := (x & 15) + ((z & 15) << 4)
	for cy in range((WorldGenerator.HEIGHT - 1) >> 4, -1, -1):
		var data: ChunkData = chunks.get(Vector3i(x >> 4, cy, z >> 4))
		if data == null or data.air_count == ChunkData.VOLUME:
			continue
		var blocks := data.blocks
		for ly in range(15, -1, -1):
			var y := (cy << 4) + ly
			if y <= 0 or y >= WorldGenerator.HEIGHT:
				continue
			var id := blocks[column + (ly << 8)]
			if id == Blocks.AIR:
				continue
			if liquid[id] == 1:
				return y # squid spawn inside the water
			if collides[id] == 1:
				return y + 1
			if _leaves[id] == 1:
				return -1
	return -1


func _choose(category: String, pos: Vector3i) -> String:
	match category:
		"water":
			return "squid"
		"animal":
			var weights: Dictionary = ANIMALS.duplicate()
			if world.biome_at(pos.x, pos.z) in WOLF_BIOMES:
				weights["wolf"] = WOLF_WEIGHT
			return _weighted(weights)
		_:
			return _weighted(MONSTERS)


## A name picked by weight ({name: weight}).
static func _weighted(weights: Dictionary) -> String:
	var total := 0
	for name: String in weights:
		total += int(weights[name])
	var roll := randi_range(0, total - 1)
	for name: String in weights:
		roll -= int(weights[name])
		if roll < 0:
			return name
	return ""


## Whether a mob of that kind may stand at pos (its feet's cell);
## `keep_away`: not within MIN_DISTANCE of a player (nightmares come close,
## Nightmares).
func _suits(category: String, mob_type: String, pos: Vector3i, keep_away: bool = true) -> bool:
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
	if keep_away:
		for at in (_round_players if not _round_players.is_empty() else _player_positions()):
			if at.distance_to(Vector3(pos)) < MIN_DISTANCE:
				return false
	var darkness := _round_darkness if _round_darkness >= 0.0 else sky_darkness(world)
	if category == "animal":
		var ground := Blocks.get_type(below).name
		return (ground.begins_with("grass") or ground == "snowy_grass") and world.get_combined_light(pos, darkness) > 8
	if mob_type == "slime":
		# Beta's EntitySlime: a slime chunk, low down, 1 try in 10.
		return is_slime_chunk(world.world_generator.world_seed if world.world_generator else 0, pos.x >> 4, pos.z >> 4) \
			and pos.y < 16 + world.sea_level - WorldGenerator.SEA_LEVEL and randi_range(0, 9) == 0
	# Beta's EntityMob: the sky light not above a random 0..31, then the
	# light (the night taken off) not above a random 0..7.
	if world.get_light(pos) > randi_range(0, 31):
		return false
	return world.get_combined_light(pos, darkness) <= randi_range(0, 7)


## Room for a creature: air, or a block without a full cube (snow on the
## ground, flowers, tall grass) and no liquid, like Beta's.
static func _free(id: int) -> bool:
	if id == Blocks.AIR:
		return true
	if Blocks.liquid_table[id] == 1:
		return false
	return Blocks.collides_table[id] == 0


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
