class_name VoxelWorld
extends Node3D
## An endless world of 16^3 chunks in columns of 16 (256 blocks; classic
## worlds use the lower 128 like Beta 1.7.3, see `height`),
## loaded around the player; its clock and everything that happens in ticks.
##
## Streaming, all on worker threads, nearest first:
## 1. columns within render_distance + 1 of the player are generated;
## 2. a column is lit (sky light, see SkyLight) once its 8 neighbors exist
##    (columns on the outer ring treat neighbors beyond the loaded area as
##    solid: they are not drawn, only their border light is used);
## 3. a chunk is meshed once its column and the 8 around it are lit (border
##    faces, AO and smooth lighting depend on them).
## Columns far away are unloaded. Changing a block re-lights its area right
## away (light removal and re-spreading, like the classic game).
##
## Every game tick (TickLoop, Phase.WORLD), in this order:
## 1. the clock advances (game_time, day_time);
## 2. scheduled block ticks that are due run (falling sand, ...);
## 3. random ticks: random_tick_speed random blocks per chunk get a random
##    tick if their type has one (grass spreading, ...). Chunks without such
##    blocks are skipped.
## Changing a block (set_block) sends a "block update" to it and its 6
## neighbors and marks the affected chunks for re-meshing. Meshes are built
## on worker threads and swapped in when ready.
##
## R regenerates the world with a new seed.

enum Generator {
	BETA,          ## Beta 1.7.3 style terrain, biomes, caves, ores, trees.
	RANDOM_BLOCKS, ## Debug: every block type scattered randomly.
	FLOATING_ISLANDS, ## Islands in the sky over the void (FloatingIslandsGenerator).
	ISLAND,        ## One big island in the sea (IslandGenerator): worlds made before SMALL_ISLANDS.
	DEBUG,         ## Every block in every state and every creature (DebugGenerator).
	SMALL_ISLANDS, ## A small island and a few islets in a deep sea (SmallIslandsGenerator).
}

const NEIGHBORS: Array[Vector3i] = [
	Vector3i.UP, Vector3i.DOWN, Vector3i.RIGHT, Vector3i.LEFT, Vector3i.BACK, Vector3i.FORWARD,
]
const COLUMN_NEIGHBORS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
	Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]
## Like the classic game: scheduled ticks beyond this per game tick wait.
const MAX_SCHEDULED_TICKS_PER_TICK := 65536
## Main-thread time scheduled ticks may take per tick (liquids flooding a
## cave relight and remesh a lot): the rest waits for the next tick.
const SCHEDULED_TICK_BUDGET_US := 3000

@export var generator: Generator = Generator.BETA
@export var world_seed: int = 1337
## Share of non-floor cells filled in RANDOM_BLOCKS mode.
@export_range(0.0, 1.0) var random_density: float = 0.3
## Chunks are loaded around this node (the player / camera).
@export var player: Node3D
## Radius in chunks of the area kept loaded and visible.
@export_range(2, 32) var render_distance: int = 6

@export_group("Ticks")
## Random ticks per chunk per game tick (randomTickSpeed, 3 by default).
@export_range(0, 4096) var random_tick_speed: int = 3
## Time of day of a new world in ticks (0 = 06:00, 3333 ~ 09:20).
@export var start_day_time: float = 3333.0

var clock := WorldClock.new()
## Random source for world logic (random ticks, block behaviors).
var rng := RandomNumberGenerator.new()
## Falling block entities in this world.
var falling_blocks: FallingBlocks
## Dropped items and particles in this world.
var items: ItemEntities
var particles: BlockParticles
## Mobs and other moving things (Entity).
var entities: EntityManager
## The text on signs.
var sign_texts: SignTexts
## Chest lids opening and closing.
## The active world generator.
var world_generator: WorldGenerator
## keepInventory game rule: the player keeps the items on death.
var keep_inventory := false
## Where players appear, set by /setworldspawn (Vector3.INF: find_spawn()
## looks for a place near the origin).
var world_spawn := Vector3.INF
## Blocks sliding from pistons: cell -> {id, node} (PistonBehavior).
var moving_blocks := {}
## Maps drawn so far: number -> {x, z (center), colors} (see Maps).
var maps := {}
## The last power state of things that react to its changes (Redstone.edge).
var redstone_power := {}
## Rain, snow and thunder (Weather).
var weather := Weather.new()
## Jukeboxes playing: position -> AudioStreamPlayer3D (MusicBehavior).
var record_players := {}
var next_map_id := 0
## Where this world is saved (WorldSave.current when started from the
## title screen); null = not saved.
var save: WorldSave
## The simplified land beyond 16 chunks when the render distance is more (FarTerrain).
var far_terrain: FarTerrain
## The world's height (no blocks at or above it: 128 in classic worlds like
## Beta 1.7.3) and sea level (WorldSave.layout).
var height := 128
var sea_level := 64
## A network game's client (Net): the host runs the world; this one draws
## it, asks the host for changed columns, sends its player's edits and runs
## no world ticks of its own.
var remote := false
var _applying_network := false
var _remote_waiting := {} # columns asked from the host
var _remote_centers: Array[Vector2i] = []
## Columns kept loaded around the other players (host; a dedicated
## server's simulation-distance).
var remote_radius := 4
## A dedicated server (Net.dedicated): no meshes are built (nobody looks),
## and with no player of its own the loaded area is around `stream_center`
## (the spawn) besides the players'.
var no_meshes := false
var stream_center := Vector3.INF

var _chunks := {}          # Vector3i -> ChunkData
var _columns := {}         # Vector2i -> Array[ChunkData]: generated columns, bottom to top
var _heightmaps := {}      # Vector2i -> PackedInt32Array (see WorldGenerator.heightmap)
var _lit := {}             # Vector2i -> true: columns with sky light
var _light_jobs := {}      # Vector2i -> LightJob on a worker thread
var _chunk_nodes := {}     # Vector3i -> MeshInstance3D
var _chunk_faces := {}     # Vector3i -> visible faces
var _dirty := {}           # Vector3i -> true: chunks waiting for a new mesh
var _mesh_jobs := {}       # Vector3i -> MeshJob on a worker thread
var _gen_jobs := {}        # Vector2i -> GenerationJob on a worker thread
var _scheduled := {}       # game_time -> {Vector3i: true}
## Like the modern game's simulation distance: around every player only
## this many columns are simulated (block and random ticks, furnaces,
## creatures: EntityManager); beyond, the loaded world is only drawn and
## waits as it is. The players' areas this tick: Vector3i(column x, z,
## radius).
var simulation_distance := 8
var _sim_areas: Array[Vector3i] = []
## Scheduled ticks that came due out of the simulated area: column ->
## {pos: true}, run again (1 tick later) when a player comes near.
var _sleeping_ticks := {}
var _scheduled_count := 0
var _modified := {}        # Vector2i -> true: columns changed since they were saved
var _column_colors := {}   # Vector2i -> [grass, foliage] (WorldGenerator.column_colors)
var _connectivity := {}    # Vector3i -> face connectivity (ChunkMesher.connectivity)
## Block entities like the classic game's tile entities: what a chest
## holds, a furnace's slots and fire. Vector3i -> {"type", "inventory", ...}.
var _block_entities := {}
var _cull_dirty := true
var _cull_task := -1
var _cull_job := {}
var _cull_timer := 0.0
var _camera_chunk := Vector3i(0, -1000, 0)
## Chunks hidden by cave culling in the last pass (debug screen).
var culled_chunks := 0
## Off while something looks at the world from elsewhere (isometric
## screenshots see the cut sides of the loaded area).
## While on, chunks at the edge of the drawn area are meshed as if nothing
## were beyond it, so the area's sides are solid walls (isometric
## screenshots); see set_open_edges().
var open_edges := false
var culling_enabled := true:
	set(value):
		culling_enabled = value
		_cull_dirty = true
		_cull_timer = 0.0
var _water := Blocks.id_of("water")
## Worker jobs at once: half the cores, so the main thread and the
## renderer always find one free (on chips with few fast cores the workers
## took them and frames stalled while the world streamed in).
var _max_jobs := maxi(OS.get_processor_count() / 2, 2)
## While the loading screen waits for the columns within this radius of the
## player (-1 = not loading), their chunks are meshed before all others.
var loading_radius := -1:
	set(value):
		loading_radius = value
		_mesh_scan_needed = true
		# Behind the loading screen nobody plays: every core but one works.
		_max_jobs = maxi(OS.get_processor_count() - 1, 2) if value >= 0 else maxi(OS.get_processor_count() / 2, 2)
var _player_column := Vector2i(2147483647, 0)
var _wanted_columns: Array[Vector2i] = []
var _total_faces := 0
var _last_mesh_ms := 0.0
var _last_generation_ms := 0.0
## Set when something may have made a chunk meshable; avoids rescanning
## the waiting chunks every frame.
var _mesh_scan_needed := true
var _light_scan_needed := true
## Meshable dirty chunks, nearest at the end (see _rebuild_mesh_queue).
var _mesh_queue: Array[Vector3i] = []
var _opacity := Blocks.light_opacity_table


## A chunk mesh built on a worker thread from the chunk's blocks and its 26
## neighbors' (shared copy-on-write arrays: later edits on the main thread
## do not affect the job).
class MeshJob:
	var coord: Vector3i
	var center: PackedInt32Array
	var neighbors := {}
	var center_light: PackedByteArray
	var neighbor_light := {}
	var center_block_light: PackedByteArray
	var neighbor_block_light := {}
	## Grass / foliage colors of the column (WorldGenerator.column_colors).
	var colors: Array = [PackedColorArray(), PackedColorArray()]
	var surfaces := {}
	## The finished mesh (built on the worker too: uploading the arrays is
	## slow), null when the chunk shows nothing.
	var mesh: ArrayMesh
	var faces := 0
	## Face connectivity for cave culling (ChunkMesher.connectivity).
	var connectivity := ChunkMesher.ALL_CONNECTED
	var mesh_ms := 0.0
	var task_id := -1
	## Leaves as with Fast graphics (a chunk far from the player).
	var fast := false

	func run() -> void:
		var start_us := Time.get_ticks_usec()
		if ChunkMesher.native:
			var built: Array = ClassDB.class_call_static("NativeMesher", "build_chunk", coord, center, neighbors,
				center_light, neighbor_light, center_block_light, neighbor_block_light, colors[0], colors[1],
				ChunkMesher.smooth_lighting, ChunkMesher.random_rotation, fast)
			surfaces = built[0]
			connectivity = built[1]
		else:
			var padded := ChunkMesher.pad_blocks(center, neighbors)
			surfaces = ChunkMesher.build(padded, ChunkMesher.pad_light(center_light, neighbor_light, SkyLight.MAX),
				colors[0], colors[1], coord * ChunkData.SIZE, ChunkMesher.pad_light(center_block_light, neighbor_block_light))
			connectivity = ChunkMesher.connectivity(padded)
		if not surfaces.is_empty():
			mesh = ChunkMesher.to_mesh(surfaces)
			for arrays: Array in surfaces.values():
				faces += arrays[Mesh.ARRAY_VERTEX].size() / 4
			surfaces = {}
		mesh_ms = (Time.get_ticks_usec() - start_us) / 1000.0


## Sky light and block light of a column, computed on a worker thread from
## the 3x3 columns around it.
class LightJob:
	var column: Vector2i
	var chunks := []   # 9 arrays of the columns' chunk block arrays
	var glowing := []  # 9 arrays of flags: that chunk has glowing blocks
	var heights := []  # 9 heightmaps
	var light: Array[PackedByteArray] = []
	var block_light: Array[PackedByteArray] = []
	var task_id := -1

	## The native code (bin/libvoxel_native.framework, native/) is loaded: the
	## same light about 50x faster (9 ms a column instead of ~500). Without it,
	## the GDScript below.
	static var native := ClassDB.class_exists("NativeLight")

	func run() -> void:
		if native:
			var both: Array = ClassDB.class_call_static("NativeLight", "compute_column", chunks, heights, glowing,
				Blocks.light_opacity_table, Blocks.light_emission_table)
			light.assign(both[0])
			block_light.assign(both[1])
			return
		var area := SkyLight.area_of(chunks)
		light = SkyLight.compute_column(area, heights)
		block_light = BlockLight.compute_column(area, BlockLight.sources_of(chunks, glowing))


## A column generated on a worker thread.
class GenerationJob:
	var column: Vector2i
	var generator: WorldGenerator
	var save: WorldSave
	var chunks: Array[ChunkData] = []
	var heights := PackedInt32Array()
	var colors: Array = []
	var generation_ms := 0.0
	var task_id := -1

	## Blocks sent by the host (network client): used instead of generating.
	var given := PackedInt32Array()

	func run() -> void:
		var start_us := Time.get_ticks_usec()
		var blocks := given
		if blocks.is_empty() and save and save.has_column(column):
			blocks = save.load_column(column) # generated or changed before: saved
		if blocks.size() == WorldGenerator.LEGACY_VOLUME:
			# Saved 128 high: air above (classic), or up onto the deep layer (old).
			blocks = generator.convert_legacy(column.x, column.y, blocks)
			save.save_column(column, blocks)
		elif blocks.is_empty():
			blocks = generator.generate_blocks(column.x, column.y)
			if save:
				# Kept on disk: next time the world loads it is read, not generated.
				save.save_column(column, blocks)
		heights = WorldGenerator.heightmap(blocks)
		chunks = WorldGenerator.split_column(blocks)
		colors = generator.column_colors(column.x, column.y)
		generation_ms = (Time.get_ticks_usec() - start_us) / 1000.0


func _ready() -> void:
	ChunkMesher.prepare_native()
	save = WorldSave.current
	remote = Net.is_client()
	no_meshes = Net.dedicated
	if Net.dedicated:
		remote_radius = Net.simulation_distance
		render_distance = Net.spawn_radius
	if save:
		world_seed = save.world_seed
		generator = save.generator as Generator
	falling_blocks = FallingBlocks.new()
	falling_blocks.name = "FallingBlocks"
	falling_blocks.world = self
	add_child(falling_blocks)
	items = ItemEntities.new()
	items.name = "Items"
	items.world = self
	items.player = player as Player
	add_child(items)
	particles = BlockParticles.new()
	particles.name = "Particles"
	particles.world = self
	add_child(particles)
	var weather_effects := WeatherEffects.new()
	weather_effects.name = "WeatherEffects"
	weather_effects.world = self
	add_child(weather_effects)
	far_terrain = FarTerrain.new()
	far_terrain.name = "FarTerrain"
	far_terrain.world = self
	add_child(far_terrain)
	entities = EntityManager.new()
	entities.name = "Entities"
	entities.world = self
	add_child(entities)
	sign_texts = SignTexts.new()
	sign_texts.name = "SignTexts"
	sign_texts.world = self
	add_child(sign_texts)
	generate()
	TickLoop.add_listener(_tick, TickLoop.Phase.WORLD)


func _exit_tree() -> void:
	TickLoop.remove_listener(_tick)
	_wait_for_jobs()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("regenerate_world") and save == null:
		world_seed = randi()
		generate()
		get_viewport().set_input_as_handled()


## Main-thread time of the last frame's world work by phase (microseconds),
## for the debug screen and profiling: stream, generation, light, mesh, cull.
var frame_times := {}


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	for column: Vector2i in _save_tasks.keys():
		if WorkerThreadPool.is_task_completed(_save_tasks[column]):
			_finish_save(column)
	_update_streaming()
	var t1 := Time.get_ticks_usec()
	_finish_generation_jobs()
	_start_generation_jobs()
	var t2 := Time.get_ticks_usec()
	_finish_light_jobs()
	_start_light_jobs()
	var t3 := Time.get_ticks_usec()
	_run_light_spread(LIGHT_SPREAD_FRAME_US)
	if not no_meshes:
		_finish_mesh_jobs()
	var t3b := Time.get_ticks_usec()
	if not no_meshes:
		_start_mesh_jobs()
	var t4 := Time.get_ticks_usec()
	if not no_meshes:
		_update_culling(delta)
	var t5 := Time.get_ticks_usec()
	frame_times = {"stream": t1 - t0, "generation": t2 - t1, "light": t3 - t2, "mesh": t4 - t3, "mesh_upload": t3b - t3, "mesh_queue": _queue_us, "cull": t5 - t4}


# --- World lifecycle ---------------------------------------------------------------

## Starts a new world with the current generator and seed: drops everything,
## generates the spawn column right away and puts the player on the ground.
func generate() -> void:
	_wait_for_jobs()
	_found_spawn = Vector3.INF
	for node: Node in _chunk_nodes.values():
		node.queue_free()
	_chunks.clear()
	_columns.clear()
	_unload_queue.clear()
	_random_dirty = true
	_random_tick_queue.clear()
	_heightmaps.clear()
	_column_colors.clear()
	_lit.clear()
	_chunk_nodes.clear()
	_culled.clear()
	_chunk_faces.clear()
	_dirty.clear()
	_relight_columns.clear()
	_sky_spread.clear()
	_sky_spread_head = 0
	_block_spread.clear()
	_block_spread_head = 0
	_deferred.clear()
	_surface_min.clear()
	_urgent_mesh.clear()
	_total_faces = 0
	_player_column = Vector2i(2147483647, 0)
	rng.seed = world_seed
	clock = WorldClock.new(start_day_time)
	falling_blocks.clear()
	items.clear()
	entities.clear()
	sign_texts.clear()
	for entry: Dictionary in moving_blocks.values():
		if is_instance_valid(entry.node):
			(entry.node as Node).queue_free()
	moving_blocks.clear()
	_block_entities.clear()
	_scheduled.clear()
	_sleeping_ticks.clear()
	_sim_areas.clear()
	_scheduled_count = 0
	_modified.clear()
	_connectivity.clear()
	_cull_dirty = true
	_restore_state()
	var layout := save.layout() if save else WorldSave.layout_of(WorldSave.CLASSIC)
	height = layout.height
	sea_level = layout.sea
	match generator:
		Generator.BETA:
			var beta := BetaGenerator.new(world_seed)
			beta.set_layout(layout)
			world_generator = beta
		Generator.RANDOM_BLOCKS:
			world_generator = RandomBlocksGenerator.new(world_seed, random_density)
		Generator.FLOATING_ISLANDS:
			world_generator = FloatingIslandsGenerator.new(world_seed)
		Generator.ISLAND:
			var island := IslandGenerator.new(world_seed)
			island.set_layout(layout)
			world_generator = island
		Generator.SMALL_ISLANDS:
			var islands := SmallIslandsGenerator.new(world_seed)
			islands.set_layout(layout)
			world_generator = islands
		Generator.DEBUG:
			world_generator = DebugGenerator.new(world_seed)
			random_tick_speed = 0 # (the blocks stay as shown)
			# Always noon and clear, like the game's debug world: time and
			# weather stand still (every water level stays as shown too).
			clock.daylight_cycle = false
			clock.day_time = 6000.0
			weather.cycle = false
			weather.raining = false
			weather.thundering = false
			weather.rain_strength = 0.0
			weather.thunder_strength = 0.0

	if player:
		var player_state: Dictionary = save.state.get("player", {}) if save else {}
		if player_state.has("position"):
			# Back where the player left: that column is needed right away.
			var position: Vector3 = player_state.position
			_generate_now(Vector2i(floori(position.x / ChunkData.SIZE), floori(position.z / ChunkData.SIZE)))
			player.global_position = position
		else:
			player.global_position = find_spawn()
			if save and not remote and save.state.is_empty():
				_first_start(player.global_position)
	elif no_meshes and save:
		# A dedicated server: the spawn area stays loaded.
		stream_center = find_spawn()
		if save.state.is_empty():
			_first_start(stream_center)


## A new world's first start: the bonus chest by the spawn, the debug
## world's creatures.
func _first_start(spawn: Vector3) -> void:
	if generator == Generator.DEBUG:
		place_debug_mobs()
	elif save.bonus_chest:
		place_bonus_chest(Vector3i(spawn.floor()))


## The bonus chest like the game's (since 1.3): on the ground a few blocks
## from the spawn, a torch on each side, with wood, tools and food to start.
func place_bonus_chest(spawn: Vector3i) -> Vector3i:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, "bonus"])
	for attempt in 64:
		var x := spawn.x + rng.randi_range(-5, 5)
		var z := spawn.z + rng.randi_range(-5, 5)
		if absi(x - spawn.x) + absi(z - spawn.z) < 2:
			continue # not where the player stands
		var y := _top_block_y(x, z)
		while y > 0 and Blocks.collides_table[get_block(Vector3i(x, y, z))] == 0:
			y -= 1 # (under grass and flowers)
		var ground := Vector3i(x, y, z)
		if y <= 0 or Blocks.liquid_table[get_block(ground)] == 1 or Blocks.is_opaque_table[get_block(ground)] == 0:
			continue
		var pos := ground + Vector3i.UP
		if get_block(pos) != Blocks.AIR and Blocks.collides_table[get_block(pos)] == 1:
			continue
		set_block(pos, Blocks.variant("chest", rng.randi_range(0, 3)))
		var inventory: Inventory = block_entity(pos).inventory
		var loot := [["stick", 1, 12], ["oak_planks", 1, 12], ["oak_log", 1, 3], ["wooden_axe", 1, 1],
			["wooden_pickaxe", 1, 1], ["stone_pickaxe", 0, 1], ["apple", 1, 2], ["bread", 1, 2]]
		for entry: Array in loot:
			var count := rng.randi_range(entry[1], entry[2])
			if count > 0:
				var slot := rng.randi_range(0, inventory.size() - 1)
				while not inventory.is_empty_slot(slot):
					slot = (slot + 1) % inventory.size()
				inventory.set_slot(slot, Items.id_of(entry[0]), count)
		for side: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var spot := pos + side
			if get_block(spot) == Blocks.AIR and Blocks.is_opaque_table[get_block(spot + Vector3i.DOWN)] == 1:
				set_block(spot, Blocks.id_of("torch"))
		return pos
	return Vector3i.MAX


## The debug world's creatures in a row in front of the blocks, standing
## still (no AI): every kind, and the looks some have (a saddled pig, a
## sheared and a colored sheep, tame and angry wolves, three slime sizes).
func place_debug_mobs() -> void:
	var kinds: Array = []
	for type: String in Mob.TYPES:
		kinds.append({"type": type})
	kinds.append_array([{"type": "pig", "saddled": true}, {"type": "sheep", "sheared": true},
		{"type": "sheep", "wool": "black"}, {"type": "wolf", "tamed": true}, {"type": "wolf", "angry": true},
		{"type": "slime", "size": 2}, {"type": "slime", "size": 4}])
	for i in kinds.size():
		var kind: Dictionary = kinds[i]
		var mob := Mob.create(kind.type)
		mob.no_ai = true
		mob.saddled = kind.get("saddled", false)
		mob.sheared = kind.get("sheared", false)
		mob.wool_color = kind.get("wool", "white")
		mob.tamed = kind.get("tamed", false)
		mob.angry = kind.get("angry", false)
		mob.size = kind.get("size", 1)
		var at := Vector3(1.5 + i * 3, DebugGenerator.FLOOR_Y + 1, -6.5)
		_generate_now(Vector2i(floori(at.x / 16.0), floori(at.z / 16.0)))
		entities.spawn(mob, at)


## Like the classic game, spawn on land: search columns in a spiral from the
## origin (generating them right away; they stay loaded) for a block column
## whose top is a solid block, not water. Falls back to the origin.
const SPAWN_SEARCH_RADIUS := 6

func find_spawn() -> Vector3:
	if remote:
		return Net.world_info.get("spawn", Vector3(8.5, sea_level + 1.0, 8.5))
	if world_spawn != Vector3.INF:
		return world_spawn
	if _found_spawn != Vector3.INF:
		return _found_spawn # (the compass asks 20 times a second)
	_found_spawn = _search_spawn()
	return _found_spawn


## Where find_spawn found the spawn (Vector3.INF: not looked yet; a new
## world looks again).
var _found_spawn := Vector3.INF


func _search_spawn() -> Vector3:
	if generator == Generator.RANDOM_BLOCKS:
		_generate_now(Vector2i.ZERO)
		return Vector3(24, 20, 24)
	if generator == Generator.DEBUG:
		_generate_now(Vector2i(0, -1))
		_generate_now(Vector2i.ZERO)
		return Vector3(0.5, DebugGenerator.FLOOR_Y + 1, -2.5)
	for ring in SPAWN_SEARCH_RADIUS + 1:
		for dx in range(-ring, ring + 1):
			for dz in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var column := Vector2i(dx, dz)
				_generate_now(column)
				for local in [Vector2i(8, 8), Vector2i(4, 4), Vector2i(12, 12), Vector2i(4, 12), Vector2i(12, 4)]:
					var x: int = column.x * 16 + local.x
					var z: int = column.y * 16 + local.y
					var top := _top_block_y(x, z)
					var top_id := get_block(Vector3i(x, top, z))
					if top >= sea_level - 1 and top_id != _water and not Blocks.family_of(top_id).ends_with("_leaves"):
						return Vector3(x + 0.5, top + 1.0, z + 0.5) # feet on the block (not up a tree)
	return Vector3(8.5, sea_level + 1.0, 8.5)


func _generate_now(column: Vector2i) -> void:
	if _columns.has(column) or remote:
		return # (a client waits for the host's answer: the column may be changed)
	var job := GenerationJob.new()
	job.column = column
	job.generator = world_generator
	job.save = save
	job.run()
	_add_column(job)


## The highest block that keeps out sky light at a block column (the
## heightmap; -1 if none or not loaded). Cheap: no search.
func surface_height(x: int, z: int) -> int:
	var heights: Variant = _heightmaps.get(Vector2i(x >> 4, z >> 4))
	if heights == null:
		return -1
	return (heights as PackedInt32Array)[(x & 15) + 16 * (z & 15)]


func _top_block_y(x: int, z: int) -> int:
	for y in range(WorldGenerator.HEIGHT - 1, 0, -1):
		if get_block(Vector3i(x, y, z)) != Blocks.AIR:
			return y
	return -1


## Rebuilds the meshes of all chunks in the background.
## Fancy graphics: leaves in chunks more than this many columns from the
## player are drawn opaque, like Fast graphics (the rest is as near).
const FAST_LEAVES_DISTANCE := 8


func _far_leaves(column: Vector2i) -> bool:
	return not Blocks.is_fast_graphics() and maxi(absi(column.x - _player_column.x), absi(column.y - _player_column.y)) > FAST_LEAVES_DISTANCE


## The chunks with leaves that crossed FAST_LEAVES_DISTANCE (the columns at
## 8 and 9 from the player, now that it moved) are meshed again.
func _remesh_leaf_ring() -> void:
	if Blocks.is_fast_graphics():
		return
	for ring in [FAST_LEAVES_DISTANCE, FAST_LEAVES_DISTANCE + 1]:
		for i in range(-ring, ring + 1):
			for column: Vector2i in [_player_column + Vector2i(i, -ring), _player_column + Vector2i(i, ring),
					_player_column + Vector2i(-ring, i), _player_column + Vector2i(ring, i)]:
				var chunks: Variant = _columns.get(column)
				if chunks == null:
					continue
				for k in (chunks as Array).size():
					if (chunks[k] as ChunkData).leaf_count > 0:
						_mark_dirty_chunk(Vector3i(column.x, k, column.y))


func remesh_all() -> void:
	ChunkMesher.prepare_native() # (the block tables changed: Fast / Fancy)
	for coord: Vector3i in _chunks:
		_dirty[coord] = true
	_deferred.clear()
	_mesh_scan_needed = true


## Changes the loaded radius (Render Distance setting).
func set_render_distance(chunks: int) -> void:
	render_distance = chunks
	_player_column = Vector2i(2147483647, 0) # recompute what to load
	_mesh_scan_needed = true


func _wait_for_jobs() -> void:
	for job: MeshJob in _mesh_jobs.values():
		WorkerThreadPool.wait_for_task_completion(job.task_id)
	_mesh_jobs.clear()
	for job: GenerationJob in _gen_jobs.values():
		WorkerThreadPool.wait_for_task_completion(job.task_id)
	_gen_jobs.clear()
	for job: LightJob in _light_jobs.values():
		WorkerThreadPool.wait_for_task_completion(job.task_id)
	_light_jobs.clear()
	if _cull_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_cull_task)
		_cull_task = -1
	for column: Vector2i in _save_tasks.keys():
		_finish_save(column)


# --- Streaming -----------------------------------------------------------------------

func _player_column_now() -> Vector2i:
	var position := player.global_position if player else (stream_center if stream_center != Vector3.INF else Vector3.ZERO)
	return Vector2i(floori(position.x / ChunkData.SIZE), floori(position.z / ChunkData.SIZE))


## When the player enters another column: list columns to generate (nearest
## first) and unload the ones that are too far.
## Columns out of range, unloaded a few a frame (a whole row of them at
## once, each with its chunks' meshes, stalled the frame the player crossed
## into another column).
var _unload_queue: Array[Vector2i] = []
const UNLOADS_PER_FRAME := 4


func _unload_far_columns() -> void:
	var done := 0
	while done < UNLOADS_PER_FRAME and not _unload_queue.is_empty():
		var column: Vector2i = _unload_queue.pop_back()
		if _columns.has(column) and _out_of_range(column):
			_unload_column(column)
			done += 1


## Beyond the unload distance of this player and the network game's others.
func _out_of_range(column: Vector2i) -> bool:
	var unload_radius := render_distance + 4
	if absi(column.x - _player_column.x) <= unload_radius and absi(column.y - _player_column.y) <= unload_radius:
		return false
	for other in _remote_centers:
		if absi(column.x - other.x) <= remote_radius + 2 and absi(column.y - other.y) <= remote_radius + 2:
			return false
	return true


func _update_streaming() -> void:
	_unload_far_columns()
	var center := _player_column_now()
	var others: Array[Vector2i] = []
	if Net.is_host():
		others.assign(Net.remote_columns())
	if center == _player_column and others == _remote_centers:
		return
	_remote_centers = others
	var moved := center != _player_column and _player_column.x != 2147483647
	_player_column = center
	_heavy_frame = Engine.get_process_frames() # (the scans below: this frame's heavy step)
	if moved:
		_remesh_leaf_ring()
		if open_edges:
			_refresh_edges() # the drawn area moves with the player
	_mesh_scan_needed = true
	_light_scan_needed = true
	_wake_deferred()
	var radius := render_distance + 1
	if remote:
		radius = mini(radius, Net.view_limit + 1) # (the host sends changed land no farther)
	_wanted_columns.clear()
	# Ring by ring from the outside in: the nearest end up last (taken
	# first) without sorting hundreds of columns.
	for ring in range(radius, -1, -1):
		for dx in range(-ring, ring + 1):
			for dz: int in ([-ring, ring] if absi(dx) != ring else range(-ring, ring + 1)):
				var column := center + Vector2i(dx, dz)
				if not _columns.has(column):
					_wanted_columns.append(column)
	# Host: the columns around the other players too (their edits and the
	# world's ticks there need them).
	for other in _remote_centers:
		for dx in range(-remote_radius, remote_radius + 1):
			for dz in range(-remote_radius, remote_radius + 1):
				var column := other + Vector2i(dx, dz)
				if not _columns.has(column) and not _wanted_columns.has(column):
					_wanted_columns.append(column)

	_unload_queue.clear()
	for column: Vector2i in _columns.keys():
		if _out_of_range(column):
			_unload_queue.append(column)


## The biome's grass (kind 1) or foliage (kind 2) color at a block column
## (linear; white where the column has none).
func biome_color(pos: Vector3i, kind: int) -> Color:
	var colors: Array = _column_colors.get(Vector2i(pos.x >> 4, pos.z >> 4), [])
	if kind < 1 or colors.size() < kind:
		return Color.WHITE
	var list: PackedColorArray = colors[kind - 1]
	if list.size() != 256:
		return Color.WHITE
	return list[(pos.x & 15) + 16 * (pos.z & 15)]


## No column near the player waits to be generated (far work may start).
func is_streaming_idle() -> bool:
	return _wanted_columns.is_empty() and _gen_jobs.is_empty() and _remote_waiting.is_empty()


func _start_generation_jobs() -> void:
	if remote:
		_start_remote_columns()
		return
	while _gen_jobs.size() < maxi(_max_jobs - 2, 1) and _busy_jobs() < _job_room() and not _wanted_columns.is_empty():
		var column: Vector2i = _wanted_columns.pop_back()
		if _columns.has(column) or _gen_jobs.has(column):
			continue
		_finish_save(column) # still being written from when it unloaded
		var job := GenerationJob.new()
		job.column = column
		job.generator = world_generator
		job.save = save
		job.task_id = WorkerThreadPool.add_task(job.run, false, "Column generation")
		_gen_jobs[column] = job


## Client: each column is asked from the host first; it answers with the
## blocks of a changed column or "generate it" (the same blocks from the
## same seed). Asked columns wait without holding up the rest.
func _start_remote_columns() -> void:
	var asked := 0
	while asked < 16 and not _wanted_columns.is_empty():
		var column: Vector2i = _wanted_columns.pop_back()
		if _columns.has(column) or _gen_jobs.has(column) or _remote_waiting.has(column):
			continue
		_remote_waiting[column] = true
		Net.column_for(column)
		asked += 1
	for column: Vector2i in _remote_waiting.keys():
		if _gen_jobs.size() >= maxi(_max_jobs - 2, 1) or _busy_jobs() >= _job_room():
			break
		if not _in_load_radius(column):
			_remote_waiting.erase(column)
			continue
		var answer: Variant = Net.column_for(column)
		if answer is String and answer == "wait":
			continue
		_remote_waiting.erase(column)
		var job := GenerationJob.new()
		job.column = column
		job.generator = world_generator
		job.save = null # nothing of a client's is saved
		if answer is PackedInt32Array:
			job.given = answer
		job.task_id = WorkerThreadPool.add_task(job.run, false, "Column generation")
		_gen_jobs[column] = job


func _finish_generation_jobs() -> void:
	for column: Vector2i in _gen_jobs.keys():
		var job: GenerationJob = _gen_jobs[column]
		if not WorkerThreadPool.is_task_completed(job.task_id):
			continue
		WorkerThreadPool.wait_for_task_completion(job.task_id)
		_gen_jobs.erase(column)
		if job.generator == world_generator:
			_add_column(job)


func _add_column(job: GenerationJob) -> void:
	_columns[job.column] = job.chunks # the column's chunks, bottom to top
	_add_random_chunks(job.column)
	var lowest := WorldGenerator.HEIGHT
	for height in job.heights:
		lowest = mini(lowest, height)
	_surface_min[job.column] = lowest
	_heightmaps[job.column] = job.heights
	_column_colors[job.column] = job.colors
	_light_scan_needed = true
	_last_generation_ms = job.generation_ms
	for k in job.chunks.size():
		var coord := Vector3i(job.column.x, k, job.column.y)
		_chunks[coord] = job.chunks[k]
		_dirty[coord] = true
	if loading_radius >= 0:
		_mesh_scan_needed = true # (not lit yet: nothing to mesh while playing)
	if remote:
		apply_network_blocks(Net.take_waiting_changes(job.column)) # changed while it was on its way


func _unload_column(column: Vector2i) -> void:
	if _modified.has(column):
		_save_column(column, true)
	_columns.erase(column)
	_random_columns.erase(column)
	_relight_columns.erase(column)
	_deferred.erase(column)
	_surface_min.erase(column)
	_heightmaps.erase(column)
	_column_colors.erase(column)
	_lit.erase(column)
	for k in WorldGenerator.HEIGHT_CHUNKS:
		var coord := Vector3i(column.x, k, column.y)
		_chunks.erase(coord)
		_dirty.erase(coord)
		_total_faces -= _chunk_faces.get(coord, 0)
		_chunk_faces.erase(coord)
		_connectivity.erase(coord)
		var node: Node = _chunk_nodes.get(coord)
		if node:
			node.queue_free()
			_chunk_nodes.erase(coord)
			_culled.erase(coord)


## A chunk can be meshed once its column and all columns around it are lit.
func _can_mesh(coord: Vector3i) -> bool:
	var column := Vector2i(coord.x, coord.z)
	if absi(column.x - _player_column.x) > render_distance or absi(column.y - _player_column.y) > render_distance:
		return false
	if not _lit.has(column):
		return false
	for offset in COLUMN_NEIGHBORS:
		if not _lit.has(column + offset):
			return false
	return true


# --- Lighting ------------------------------------------------------------------------

func _start_light_jobs() -> void:
	if not _light_scan_needed or _light_jobs.size() >= _half_jobs() or _busy_jobs() >= _job_room():
		return
	var candidates: Array[Vector2i] = []
	for column: Vector2i in _columns:
		if _light_jobs.has(column) or (_lit.has(column) and not _relight_columns.has(column)):
			continue
		if absi(column.x - _player_column.x) > render_distance + 1 or absi(column.y - _player_column.y) > render_distance + 1:
			continue
		var ready := true
		for offset in COLUMN_NEIGHBORS:
			var neighbor: Vector2i = column + offset
			if not _columns.has(neighbor) and _in_load_radius(neighbor):
				ready = false
				break
		if ready:
			candidates.append(column)
	if candidates.is_empty():
		_light_scan_needed = false
		return
	# Columns never lit come first (nearest first), then the ones to light
	# again: new land must not wait for a lava flow somewhere.
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var again_a := _lit.has(a)
		var again_b := _lit.has(b)
		if again_a != again_b:
			return again_b
		return (a - _player_column).length_squared() < (b - _player_column).length_squared())
	for column in candidates:
		if _light_jobs.size() >= _half_jobs() or _busy_jobs() >= _job_room():
			break
		var job := LightJob.new()
		job.column = column
		_relight_columns.erase(column) # (a change from now on asks again)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var neighbor := column + Vector2i(dx, dz)
				var blocks := []
				var glow := PackedByteArray()
				glow.resize(WorldGenerator.HEIGHT_CHUNKS)
				if _columns.has(neighbor):
					var k := 0
					for chunk: ChunkData in _columns[neighbor]:
						blocks.append(chunk.blocks)
						glow[k] = 1 if chunk.glow_count > 0 else 0
						k += 1
					job.heights.append(_heightmaps[neighbor])
				else: # beyond the loaded area: solid, lets no light through
					for k in WorldGenerator.HEIGHT_CHUNKS:
						blocks.append(_solid_chunk())
					job.heights.append(_solid_heights())
				job.chunks.append(blocks)
				job.glowing.append(glow)
		job.task_id = WorkerThreadPool.add_task(job.run, false, "Column light")
		_light_jobs[column] = job


func _finish_light_jobs() -> void:
	for column: Vector2i in _light_jobs.keys():
		var job: LightJob = _light_jobs[column]
		if not WorkerThreadPool.is_task_completed(job.task_id):
			continue
		WorkerThreadPool.wait_for_task_completion(job.task_id)
		_light_jobs.erase(column)
		_light_scan_needed = true
		if not _columns.has(column):
			continue
		for k in WorldGenerator.HEIGHT_CHUNKS:
			var data: ChunkData = _chunks.get(Vector3i(column.x, k, column.y))
			if data:
				data.light = job.light[k]
				data.block_light = job.block_light[k]
				data.share_uniform()
		if _lit.has(column):
			# Lit again after far changes: its chunks show the new light.
			for k in WorldGenerator.HEIGHT_CHUNKS:
				var coord := Vector3i(column.x, k, column.y)
				var waiting: Variant = _deferred.get(column)
				if _chunks.has(coord) and not (waiting != null and (waiting as Dictionary).has(k)):
					_dirty[coord] = true
		_lit[column] = true
		if loading_radius >= 0:
			_mesh_scan_needed = true # loading: strict order, nearest first
		else:
			# Only what this column made ready joins the queue (sorting every
			# waiting chunk again for each lit column cost several ms a time).
			_enqueue_column(column)
			for offset in COLUMN_NEIGHBORS:
				_enqueue_column(column + offset)


func _in_load_radius(column: Vector2i) -> bool:
	var radius := render_distance + 1
	return absi(column.x - _player_column.x) <= radius and absi(column.y - _player_column.y) <= radius


static var _solid_chunk_cache := PackedInt32Array()
static var _solid_heights_cache := PackedInt32Array()


static func _solid_chunk() -> PackedInt32Array:
	if _solid_chunk_cache.is_empty():
		_solid_chunk_cache.resize(ChunkData.VOLUME)
		_solid_chunk_cache.fill(Blocks.id_of("stone"))
	return _solid_chunk_cache


static func _solid_heights() -> PackedInt32Array:
	if _solid_heights_cache.is_empty():
		_solid_heights_cache.resize(256)
		_solid_heights_cache.fill(WorldGenerator.HEIGHT - 1)
	return _solid_heights_cache


func light_jobs_count() -> int:
	return _light_jobs.size()


## Sky light at a block (0..15): 15 above the world, 0 below it or where
## nothing is loaded.
func get_light(pos: Vector3i) -> int:
	if pos.y >= WorldGenerator.HEIGHT:
		return SkyLight.MAX
	var data: ChunkData = _chunks.get(Vector3i(pos.x >> 4, pos.y >> 4, pos.z >> 4))
	if data == null:
		return 0
	return data.light[(pos.x & 15) + ((pos.z & 15) << 4) + ((pos.y & 15) << 8)]


func _set_light(pos: Vector3i, level: int) -> void:
	var coord := chunk_coord_of(pos)
	var data: ChunkData = _chunks.get(coord)
	if data == null:
		return
	var local := pos - coord * ChunkData.SIZE
	var i := ChunkData.index(local.x, local.y, local.z)
	if data.light[i] != level:
		data.own_light()
		data.light[i] = level
		_mark_dirty_around(coord, local)


## Re-lights around a changed block, like the classic game: first remove the
## light that depended on the old block (flood out from it, re-queueing
## brighter cells found at the edge), then spread light again from those
## cells and from the changed cell itself. Straight-down sky light (15)
## keeps its full value through clear blocks.
func _relight(pos: Vector3i) -> void:
	if LightJob.native:
		_relight_native(pos, true)
		return
	var removal: Array = [[pos, get_light(pos)]]
	var spread: Array[Vector3i] = []
	_set_light(pos, 0)
	var head := 0
	while head < removal.size():
		var entry: Array = removal[head]
		head += 1
		var cell: Vector3i = entry[0]
		var level: int = entry[1]
		for offset in NEIGHBORS:
			var neighbor := cell + offset
			var neighbor_level := get_light(neighbor)
			if neighbor_level == 0 or neighbor.y >= WorldGenerator.HEIGHT:
				continue
			if neighbor_level < level or (offset == Vector3i.DOWN and level == SkyLight.MAX and neighbor_level == SkyLight.MAX):
				_set_light(neighbor, 0)
				removal.append([neighbor, neighbor_level])
			else:
				spread.append(neighbor)

	# The changed cell takes light from its neighbors.
	var opacity: int = _opacity[get_block(pos)]
	if opacity < SkyLight.MAX:
		var best := 0
		for offset in NEIGHBORS:
			var neighbor_level := get_light(pos + offset)
			var candidate := neighbor_level - opacity if offset == Vector3i.UP and neighbor_level == SkyLight.MAX \
				else neighbor_level - maxi(opacity, 1)
			best = maxi(best, candidate)
		if best > 0:
			_set_light(pos, best)
			spread.append(pos)
	_sky_spread.append_array(spread)
	_run_light_spread(LIGHT_SPREAD_NOW_US)


# Light spreading on to darker cells only ever raises levels, so it can
# stop and go on later: the cells to spread from wait in these queues and
# are worked off a little at a time (at once after a change, then every
# frame). A lava flow lighting up a cave took tens of ms in one go.
const LIGHT_SPREAD_NOW_US := 300
const LIGHT_SPREAD_FRAME_US := 1000
var _sky_spread: Array[Vector3i] = []
var _sky_spread_head := 0
var _block_spread: Array[Vector3i] = []
var _block_spread_head := 0


## Works the light spreading queues off for at most `budget_us`.
func _run_light_spread(budget_us: int) -> void:
	if _sky_spread.is_empty() and _block_spread.is_empty():
		return
	var started := Time.get_ticks_usec()
	var steps := 0
	while _block_spread_head < _block_spread.size():
		var cell := _block_spread[_block_spread_head]
		_block_spread_head += 1
		var level := get_block_light(cell)
		if level > 1:
			for offset in NEIGHBORS:
				var neighbor := cell + offset
				if neighbor.y < 0 or neighbor.y >= WorldGenerator.HEIGHT or not is_inside(neighbor):
					continue
				var neighbor_opacity: int = _opacity[get_block(neighbor)]
				if neighbor_opacity >= SkyLight.MAX:
					continue
				var candidate := level - maxi(neighbor_opacity, 1)
				if candidate > get_block_light(neighbor):
					_set_block_light(neighbor, candidate)
					_block_spread.append(neighbor)
		steps += 1
		if steps & 31 == 0 and Time.get_ticks_usec() - started > budget_us:
			break
	if _block_spread_head >= _block_spread.size():
		_block_spread.clear()
		_block_spread_head = 0
	while _sky_spread_head < _sky_spread.size():
		if steps & 31 == 0 and Time.get_ticks_usec() - started > budget_us:
			break
		steps += 1
		var cell := _sky_spread[_sky_spread_head]
		_sky_spread_head += 1
		var level := get_light(cell)
		if level <= 1:
			continue
		for offset in NEIGHBORS:
			var neighbor := cell + offset
			if neighbor.y < 0 or neighbor.y >= WorldGenerator.HEIGHT or not is_inside(neighbor):
				continue
			var neighbor_opacity: int = _opacity[get_block(neighbor)]
			if neighbor_opacity >= SkyLight.MAX:
				continue
			var candidate := level - neighbor_opacity if offset == Vector3i.DOWN and level == SkyLight.MAX \
				else level - maxi(neighbor_opacity, 1)
			if candidate > get_light(neighbor):
				_set_light(neighbor, candidate)
				_sky_spread.append(neighbor)
	if _sky_spread_head >= _sky_spread.size():
		_sky_spread.clear()
		_sky_spread_head = 0


## Block light (glowing blocks) at a world position; 0 where nothing is loaded.
func get_block_light(pos: Vector3i) -> int:
	if pos.y < 0 or pos.y >= WorldGenerator.HEIGHT:
		return 0
	var coord := chunk_coord_of(pos)
	var data: ChunkData = _chunks.get(coord)
	if data == null:
		return 0
	var local := pos - coord * ChunkData.SIZE
	return data.block_light[ChunkData.index(local.x, local.y, local.z)]


## Brightness (linear, the classic light curve) of the light at a point,
## for things drawn there like blocks (the held item, dropped items,
## particles): sky light minus the night (Classic) or dimmed by the daylight
## (Dynamic Lighting), or block light if brighter.
func brightness_at(point: Vector3) -> float:
	var atmosphere := Atmosphere.find(get_tree())
	var darkness := atmosphere.sky_darkness if atmosphere else 0.0
	var day := 0.25 + 0.75 * atmosphere.daylight if atmosphere and atmosphere.sky_darkness <= 0.0 else 1.0
	return _cell_brightness(Vector3i(point.floor()), darkness, day)


## Brightness of a cell (brightness_at()); inside a solid block, where no
## light is stored, the brightest cell next to it (the bits of a block
## just broken, an item pushed into a wall), like the classic game.
func _cell_brightness(cell: Vector3i, darkness: float, day: float) -> float:
	if Blocks.is_opaque_table[get_block(cell)] == 1:
		var best := 0.0
		for offset in NEIGHBORS:
			var next := cell + offset
			if Blocks.is_opaque_table[get_block(next)] == 0:
				best = maxf(best, _light_brightness(next, darkness, day))
		return best
	return _light_brightness(cell, darkness, day)


func _light_brightness(cell: Vector3i, darkness: float, day: float) -> float:
	var sky := ChunkMesher.LIGHT_BRIGHTNESS[clampi(roundi(get_light(cell) - darkness), 0, SkyLight.MAX)] * day
	return maxf(sky, ChunkMesher.LIGHT_BRIGHTNESS[get_block_light(cell)])


## Blocks and brightness of cells (x, y, z triples) for the particles
## (NativeParticles.cells_needed()): [ids, brightness].
func cells_for_particles(cells: PackedInt32Array) -> Array:
	var count := cells.size() / 3
	var ids := PackedInt32Array()
	var brightness := PackedFloat32Array()
	ids.resize(count)
	brightness.resize(count)
	var atmosphere := Atmosphere.find(get_tree())
	var darkness := atmosphere.sky_darkness if atmosphere else 0.0
	var day := 0.25 + 0.75 * atmosphere.daylight if atmosphere and atmosphere.sky_darkness <= 0.0 else 1.0
	for n in count:
		var cell := Vector3i(cells[n * 3], cells[n * 3 + 1], cells[n * 3 + 2])
		ids[n] = get_block(cell)
		brightness[n] = _cell_brightness(cell, darkness, day)
	return [ids, brightness]


## The brighter of sky light minus `sky_darkness` levels and block light.
func get_combined_light(pos: Vector3i, sky_darkness: float = 0.0) -> int:
	return maxi(clampi(roundi(get_light(pos) - sky_darkness), 0, SkyLight.MAX), get_block_light(pos))


func _set_block_light(pos: Vector3i, level: int) -> void:
	var coord := chunk_coord_of(pos)
	var data: ChunkData = _chunks.get(coord)
	if data == null:
		return
	var local := pos - coord * ChunkData.SIZE
	var i := ChunkData.index(local.x, local.y, local.z)
	if data.block_light[i] != level:
		data.own_block_light()
		data.block_light[i] = level
		_mark_dirty_around(coord, local)


## Re-lights block light around a changed block: removes the light that
## came through or from the old block (flooding out, re-queueing brighter
## cells found at the edge), then spreads again from those cells and from
## the block itself if it glows.
func _relight_block_light(pos: Vector3i) -> void:
	if LightJob.native:
		_relight_native(pos, false)
		return
	var here := get_block_light(pos)
	var glow: int = Blocks.light_emission_table[get_block(pos)]
	var spread: Array[Vector3i] = []
	if glow == 0 and here == 0:
		# No block light here: nothing to do unless a neighbor has some to
		# give (a block opened up next to a lit cell).
		var lit_near := false
		for offset in NEIGHBORS:
			if get_block_light(pos + offset) > 1:
				lit_near = true
				break
		if not lit_near:
			return
	if glow >= here and glow > 0:
		# A source at least as bright as the light that was here: nothing
		# gets darker, the light only spreads from it.
		_set_block_light(pos, glow)
		spread.append(pos)
		_spread_block_light(spread)
		return
	var removal: Array = [[pos, here]]
	_set_block_light(pos, 0)
	var head := 0
	while head < removal.size():
		var entry: Array = removal[head]
		head += 1
		var cell: Vector3i = entry[0]
		var level: int = entry[1]
		for offset in NEIGHBORS:
			var neighbor := cell + offset
			var neighbor_level := get_block_light(neighbor)
			if neighbor_level == 0:
				continue
			if neighbor_level < level and Blocks.light_emission_table[get_block(neighbor)] < neighbor_level:
				_set_block_light(neighbor, 0)
				removal.append([neighbor, neighbor_level])
			else:
				spread.append(neighbor) # lit from elsewhere (or glowing): spreads again
	# The block itself: its own glow, or light from its neighbors.
	var id := get_block(pos)
	var best: int = Blocks.light_emission_table[id]
	var opacity: int = _opacity[id]
	if opacity < SkyLight.MAX:
		for offset in NEIGHBORS:
			best = maxi(best, get_block_light(pos + offset) - maxi(opacity, 1))
	if best > 0:
		_set_block_light(pos, best)
		spread.append(pos)
	_spread_block_light(spread)


## _relight() (`sky`) or _relight_block_light() in native code
## (NativeLight.relight_edit): the same light, removed and spread again to
## the end at once (no queue left for the next frames), over the 3x3 columns
## around the block (light never reaches farther).
func _relight_native(pos: Vector3i, sky: bool) -> void:
	if not sky and Blocks.light_emission_table[get_block(pos)] == 0 and get_block_light(pos) == 0:
		# No block light here and none next to it: nothing changes.
		var lit_near := false
		for offset in NEIGHBORS:
			if get_block_light(pos + offset) > 1:
				lit_near = true
				break
		if not lit_near:
			return
	var column := Vector2i(pos.x >> 4, pos.z >> 4)
	# Light changes at most 15 blocks up (and block light 15 down); sky light
	# can go all the way down an opened shaft.
	var low := 0 if sky else maxi((pos.y >> 4) - 1, 0)
	var high := mini((pos.y >> 4) + 1, WorldGenerator.HEIGHT_CHUNKS - 1)
	var no_blocks := PackedInt32Array()
	var no_light := PackedByteArray()
	var blocks := []
	var lights := []
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var column_blocks := []
			var column_light := []
			for k in WorldGenerator.HEIGHT_CHUNKS:
				var data: ChunkData = _chunks.get(Vector3i(column.x + dx, k, column.y + dz)) if k >= low and k <= high else null
				if data:
					column_blocks.append(data.blocks)
					column_light.append(data.light if sky else data.block_light)
				else:
					column_blocks.append(no_blocks)
					column_light.append(no_light)
			blocks.append(column_blocks)
			lights.append(column_light)
	var at := Vector3i(pos.x - (column.x - 1) * 16, pos.y, pos.z - (column.y - 1) * 16)
	var result: Array = ClassDB.class_call_static("NativeLight", "relight_edit", sky, at, blocks, lights,
		_opacity, Blocks.light_emission_table)
	var chunks: PackedInt32Array = result[0]
	var masks: PackedInt32Array = result[2]
	for n in chunks.size():
		var slot := chunks[n]
		var c := slot / WorldGenerator.HEIGHT_CHUNKS
		var coord := Vector3i(column.x + c / 3 - 1, slot % WorldGenerator.HEIGHT_CHUNKS, column.y + c % 3 - 1)
		var data: ChunkData = _chunks.get(coord)
		if data == null:
			continue
		if sky:
			data.light = result[1][n]
		else:
			data.block_light = result[1][n]
		var mask := masks[n]
		for bit in 27:
			if mask & (1 << bit):
				_mark_dirty_chunk(coord + Vector3i(bit / 9 - 1, (bit / 3) % 3 - 1, bit % 3 - 1))


## Block light flowing on from the cells in `spread` to darker cells
## (queued: _run_light_spread).
func _spread_block_light(spread: Array[Vector3i]) -> void:
	_block_spread.append_array(spread)
	_run_light_spread(LIGHT_SPREAD_NOW_US)


## Keeps the heightmap in step with block changes (used when lighting
## columns that load later).
func _update_heightmap(pos: Vector3i, id: int) -> void:
	var column := Vector2i(floori(pos.x / 16.0), floori(pos.z / 16.0))
	var heights: PackedInt32Array = _heightmaps.get(column, PackedInt32Array())
	if heights.is_empty():
		return
	var i := posmod(pos.x, 16) + 16 * posmod(pos.z, 16)
	if _opacity[id] > 0:
		heights[i] = maxi(heights[i], pos.y)
	elif pos.y == heights[i]:
		var y := pos.y - 1
		while y >= 0 and _opacity[get_block(Vector3i(pos.x, y, pos.z))] == 0:
			y -= 1
		heights[i] = y
		_surface_min[column] = mini(_surface_min.get(column, y), y) # dug deeper
	_heightmaps[column] = heights


# --- Blocks --------------------------------------------------------------------------

static func chunk_coord_of(pos: Vector3i) -> Vector3i:
	return Vector3i(pos.x >> 4, pos.y >> 4, pos.z >> 4) # chunks are 16^3 (floor division)


func is_inside(pos: Vector3i) -> bool:
	return _chunks.has(chunk_coord_of(pos))


## Block at a world position; AIR where no chunk is loaded.
func get_block(pos: Vector3i) -> int:
	# Called very often: chunk and index worked out inline (chunks are 16^3).
	var data: ChunkData = _chunks.get(Vector3i(pos.x >> 4, pos.y >> 4, pos.z >> 4))
	if data == null:
		return Blocks.AIR
	return data.blocks[(pos.x & 15) + ((pos.z & 15) << 4) + ((pos.y & 15) << 8)]


## Biome name at a block column (debug screen).
func biome_at(x: int, z: int) -> String:
	return world_generator.biome_name(x, z) if world_generator else ""


## First block hit by a ray (voxel traversal, Amanatides & Woo).
## Air and liquids are passed through (water and lava sources are hit with
## `hit_water_sources`, for buckets). Returns {hit: bool, pos: Vector3i,
## normal: Vector3i (face that was hit, ZERO if the ray starts inside),
## block: int, distance: float}.
func raycast(origin: Vector3, direction: Vector3, max_distance: float, hit_water_sources: bool = false) -> Dictionary:
	var dir := direction.normalized()
	var pos := Vector3i(origin.floor())
	var step := Vector3i(int(signf(dir.x)), int(signf(dir.y)), int(signf(dir.z)))
	var t_delta := Vector3.ZERO
	var t_max := Vector3.ZERO
	for axis in 3:
		if dir[axis] == 0.0:
			t_delta[axis] = INF
			t_max[axis] = INF
		else:
			t_delta[axis] = absf(1.0 / dir[axis])
			var boundary := pos[axis] + (1.0 if dir[axis] > 0.0 else 0.0)
			t_max[axis] = (boundary - origin[axis]) / dir[axis]
	var normal := Vector3i.ZERO
	var distance := 0.0
	while distance <= max_distance:
		var id := get_block(pos)
		if id != Blocks.AIR and (Blocks.liquid_table[id] == 0 or (hit_water_sources and Blocks.liquid_level_table[id] == 0)):
			var shape := _ray_shape_hit(origin, dir, pos, id, normal, distance)
			if not shape.is_empty():
				return {"hit": true, "pos": pos, "normal": shape[1], "block": id, "distance": shape[0]}
		var axis := 0
		if t_max.y < t_max[axis]:
			axis = 1
		if t_max.z < t_max[axis]:
			axis = 2
		distance = t_max[axis]
		pos[axis] += step[axis]
		t_max[axis] += t_delta[axis]
		normal = Vector3i.ZERO
		normal[axis] = -step[axis]
	return {"hit": false}


## Where the ray hits the block's own shape: [distance, normal], or []
## when it passes by (a snow layer, a slab, a torch: the ray goes on to the
## block behind, like the game's). Full blocks are hit where entered.
func _ray_shape_hit(origin: Vector3, dir: Vector3, pos: Vector3i, id: int, normal: Vector3i, distance: float) -> Array:
	var boxes: Array = Blocks.outline_table[id]
	if boxes.size() == 1 and (boxes[0] as AABB).is_equal_approx(AABB(Vector3.ZERO, Vector3.ONE)):
		return [distance, normal]
	var best: Array = []
	for box: AABB in boxes:
		var low := box.position + Vector3(pos)
		var high := box.end + Vector3(pos)
		var enter := -INF
		var leave := INF
		var face := normal
		var missed := false
		for axis in 3:
			if absf(dir[axis]) < 1e-9:
				if origin[axis] < low[axis] or origin[axis] > high[axis]:
					missed = true
					break
				continue
			var t1 := (low[axis] - origin[axis]) / dir[axis]
			var t2 := (high[axis] - origin[axis]) / dir[axis]
			if t1 > t2:
				var swap := t1
				t1 = t2
				t2 = swap
			if t1 > enter:
				enter = t1
				face = Vector3i.ZERO
				face[axis] = -1 if dir[axis] > 0.0 else 1
			leave = minf(leave, t2)
		if missed or enter > leave or leave < 0.0:
			continue
		var at := maxf(enter, 0.0)
		if best.is_empty() or at < best[0]:
			best = [at, face if enter >= 0.0 else normal]
	return best


## Changes a block, sends block updates to it and its neighbors and marks
## for re-meshing its chunk and the neighbor chunks that see it (their
## border faces and AO). Ignored where no chunk is loaded.
func set_block(pos: Vector3i, id: int, notify: bool = true) -> void:
	if pos.y >= height and id != Blocks.AIR:
		return # above the world (classic worlds: 128, like Beta 1.7.3)
	var coord := chunk_coord_of(pos)
	var data: ChunkData = _chunks.get(coord)
	if data == null:
		return
	var local := pos - coord * ChunkData.SIZE
	var old := data.get_block(local.x, local.y, local.z)
	if old == id:
		return
	if remote and not _applying_network:
		# The player's own edit: shown at once, made by the host.
		Net.send_set_block(pos, id)
		notify = false
	elif Net.is_host():
		Net.block_changed(pos, id)
	data.set_block(local.x, local.y, local.z, id)
	if Blocks.ticks_randomly[id] == 1 and not _random_chunk_set.has(coord) and _in_random_reach(Vector2i(coord.x, coord.z)):
		_random_chunks.append(coord) # (a chunk with nothing that ticked before)
		_random_chunk_set[coord] = true
	if _block_entities.has(pos) and _block_entities[pos].type != _entity_type(id):
		if _block_entities[pos].type == "sign":
			sign_texts.remove(pos)
		_block_entities.erase(pos) # the chest / furnace / sign is gone
	_modified[Vector2i(coord.x, coord.z)] = true
	_mark_dirty_around(coord, local)
	_update_heightmap(pos, id)
	if _lit.has(Vector2i(coord.x, coord.z)):
		# Light only depends on how much light a block lets through and gives
		# off: flowing water changing its level, lava spreading next to lava
		# and most block swaps leave it as it is.
		var emission := Blocks.light_emission_table
		if _opacity[old] != _opacity[id] or emission[old] != emission[id]:
			var column := Vector2i(coord.x, coord.z)
			if absi(column.x - _player_column.x) > NEAR_LIGHT_RADIUS or absi(column.y - _player_column.y) > NEAR_LIGHT_RADIUS:
				# Far from the player: the columns around are lit again as a whole
				# on a worker thread (lava spreading over a plain kept the main
				# thread relighting cell by cell for minutes).
				for dx in range(-1, 2):
					for dz in range(-1, 2):
						_relight_columns[column + Vector2i(dx, dz)] = true
				_light_scan_needed = true
			elif _batch_depth > 0 and LightJob.native:
				# In a batch (end_batch): lit all together.
				if _opacity[old] != _opacity[id]:
					_batch_sky.append(pos)
				_batch_block.append(pos)
			elif _opacity[old] != _opacity[id]:
				_relight(pos)
				_relight_block_light(pos)
			else:
				_relight_block_light(pos)
	if notify:
		_update_block(pos)
		for offset in NEIGHBORS:
			_update_block(pos + offset)


## Many block changes at once (a network packet, /fill, an explosion):
## between begin_batch() and end_batch() the light near the player is not
## worked out block by block (each a native call with the arrays of 9
## columns, ~100 us) but for all of them in one call at the end.
var _batch_depth := 0
var _batch_sky: Array[Vector3i] = []
var _batch_block: Array[Vector3i] = []
## A batch's area at most this many columns across, else block by block.
const BATCH_AREA_COLUMNS := 12


func begin_batch() -> void:
	_batch_depth += 1


func end_batch() -> void:
	_batch_depth = maxi(_batch_depth - 1, 0)
	if _batch_depth > 0:
		return
	var sky := _batch_sky.duplicate()
	var block := _batch_block.duplicate()
	_batch_sky.clear()
	_batch_block.clear()
	if not sky.is_empty():
		_relight_batch(sky, true)
	if not block.is_empty():
		_relight_batch(block, false)


func _relight_batch(cells: Array[Vector3i], sky: bool) -> void:
	var low := Vector2i(cells[0].x >> 4, cells[0].z >> 4)
	var high := low
	for cell in cells:
		var column := Vector2i(cell.x >> 4, cell.z >> 4)
		low = Vector2i(mini(low.x, column.x), mini(low.y, column.y))
		high = Vector2i(maxi(high.x, column.x), maxi(high.y, column.y))
	low -= Vector2i.ONE
	high += Vector2i.ONE
	var size := high - low + Vector2i.ONE
	if size.x > BATCH_AREA_COLUMNS or size.y > BATCH_AREA_COLUMNS:
		# Far apart: one by one.
		for cell in cells:
			_relight_native(cell, sky)
		return
	var no_blocks := PackedInt32Array()
	var no_light := PackedByteArray()
	var blocks := []
	var lights := []
	for cx in size.x:
		for cz in size.y:
			var column_blocks := []
			var column_light := []
			for k in WorldGenerator.HEIGHT_CHUNKS:
				var data: ChunkData = _chunks.get(Vector3i(low.x + cx, k, low.y + cz))
				column_blocks.append(data.blocks if data else no_blocks)
				column_light.append((data.light if sky else data.block_light) if data else no_light)
			blocks.append(column_blocks)
			lights.append(column_light)
	var positions := PackedInt32Array()
	positions.resize(cells.size() * 3)
	var origin := Vector3i(low.x * 16, 0, low.y * 16)
	for i in cells.size():
		var at := cells[i] - origin
		positions[i * 3] = at.x
		positions[i * 3 + 1] = at.y
		positions[i * 3 + 2] = at.z
	var result: Array = ClassDB.class_call_static("NativeLight", "relight_edits", sky, positions, size.x, size.y,
		blocks, lights, _opacity, Blocks.light_emission_table)
	if result.is_empty():
		return
	var chunks: PackedInt32Array = result[0]
	var masks: PackedInt32Array = result[2]
	for n in chunks.size():
		var slot := chunks[n]
		var c := slot / WorldGenerator.HEIGHT_CHUNKS
		var coord := Vector3i(low.x + c / size.y, slot % WorldGenerator.HEIGHT_CHUNKS, low.y + c % size.y)
		var data: ChunkData = _chunks.get(coord)
		if data == null:
			continue
		if sky:
			data.light = result[1][n]
		else:
			data.block_light = result[1][n]
		var mask := masks[n]
		for bit in 27:
			if mask & (1 << bit):
				_mark_dirty_chunk(coord + Vector3i(bit / 9 - 1, (bit / 3) % 3 - 1, bit % 3 - 1))


## Light changes within this many columns of the player are worked out at
## once, cell by cell; farther ones by lighting the column again in the
## background (_relight_columns).
const NEAR_LIGHT_RADIUS := 3
var _relight_columns := {} # Vector2i -> true: lit columns whose light is out of date


## Changes this many columns around the player are meshed before anything
## else (the player's own edits must show at once); farther ones wait their
## turn, or a far lava flow would keep every worker busy.
const URGENT_MESH_RADIUS := 3


func _mark_dirty_around(coord: Vector3i, local: Vector3i) -> void:
	var ranges := []
	for axis in 3:
		var low := -1 if local[axis] == 0 else 0
		var high := 1 if local[axis] == ChunkData.SIZE - 1 else 0
		ranges.append([low, high])
	for dx in range(ranges[0][0], ranges[0][1] + 1):
		for dy in range(ranges[1][0], ranges[1][1] + 1):
			for dz in range(ranges[2][0], ranges[2][1] + 1):
				_mark_dirty_chunk(coord + Vector3i(dx, dy, dz))


## Marks a chunk to be meshed again (if loaded and not waiting for the
## player to come near).
func _mark_dirty_chunk(neighbor: Vector3i) -> void:
	if not _chunks.has(neighbor) or no_meshes:
		return
	var column := Vector2i(neighbor.x, neighbor.z)
	var waiting: Variant = _deferred.get(column)
	if waiting != null and (waiting as Dictionary).has(neighbor.y):
		return # a far deep chunk without a mesh: built when the player comes
	if absi(column.x - _player_column.x) <= URGENT_MESH_RADIUS and absi(column.y - _player_column.y) <= URGENT_MESH_RADIUS:
		_urgent_mesh[neighbor] = true # changed near the player: before the rest
	elif not _dirty.has(neighbor):
		_mesh_backlog.append(neighbor) # far away (lava flowing in a cave): in its turn
	_dirty[neighbor] = true


## Sends a "block update" to the block at pos (its on_update handler).
func _update_block(pos: Vector3i) -> void:
	if remote:
		return # the host's world reacts
	var handler := Blocks.get_type(get_block(pos)).on_update
	if handler.is_valid():
		handler.call(self, pos)


## Turns the block at `pos` into a falling entity (sand, gravel).
func start_falling(pos: Vector3i) -> void:
	var id := get_block(pos)
	if id == Blocks.AIR:
		return
	set_block(pos, Blocks.AIR) # updates neighbors: blocks above start falling too
	falling_blocks.spawn(pos, id)


# --- Breaking and block entities -------------------------------------------------------

const CHEST_SIZE := 27
const FURNACE_SIZE := 3
const DISPENSER_SIZE := 9


## Breaks a block like the classic game: bits fly (particles), it drops what
## it gives (when `drop`; `can_harvest` = broken with the right tool), a
## chest or furnace spills what it holds and a bed loses its other half.
func destroy_block(pos: Vector3i, drop: bool = true, can_harvest: bool = true, effects: bool = true) -> void:
	var id := get_block(pos)
	if id == Blocks.AIR:
		return
	if remote:
		# Broken by this player: the bits and sound here, the breaking (and
		# what it drops) by the host.
		if effects:
			particles.break_block(pos, id)
			Sounds.play_block("break", id, Vector3(pos) + Vector3(0.5, 0.5, 0.5))
		Net.send_destroy(pos, drop, can_harvest)
		_applying_network = true
		set_block(pos, Blocks.AIR, false)
		_applying_network = false
		return
	if Blocks.family_of(id) == "dungeon_chest":
		DungeonBehavior.open_chest(self, pos) # its loot spills out
	if Blocks.family_of(id) == "jukebox":
		MusicBehavior.eject(self, pos) # the disc pops out
	if Blocks.family_of(id) == "piston_head":
		PistonBehavior.head_broken(self, pos, id) # the piston goes with it
	if effects:
		particles.break_block(pos, id)
		Sounds.play_block("break", id, Vector3(pos) + Vector3(0.5, 0.5, 0.5))
	if drop and GameRules.flag(self, "doTileDrops"):
		for entry: Array in Blocks.drops_of(id, rng, can_harvest):
			items.drop_from_block(pos, entry[0], entry[1])
	var entity: Dictionary = _block_entities.get(pos, {})
	if not entity.is_empty() and entity.has("inventory"):
		var inventory: Inventory = entity.inventory
		for slot in inventory.size():
			if inventory.count_at(slot) > 0:
				items.drop_from_block(pos, inventory.id_at(slot), inventory.count_at(slot), inventory.damage_at(slot))
		_block_entities.erase(pos)
	var family := Blocks.family_of(id)
	if family.begins_with("bed_"):
		var direction := Blocks.FACING_DIRECTIONS[Blocks.facing_table[id]]
		var other := pos + (direction if family == "bed_foot" else -direction)
		if Blocks.family_of(get_block(other)).begins_with("bed_"):
			particles.break_block(other, get_block(other))
			set_block(other, Blocks.AIR)
	set_block(pos, Blocks.AIR)


## "chest" / "furnace" for blocks with a block entity, else "".
static func _entity_type(id: int) -> String:
	var family := Blocks.family_of(id)
	if family.begins_with("chest"):
		return "chest"
	if family == "furnace" or family == "furnace_lit":
		return "furnace"
	if family == "sign" or family == "wall_sign":
		return "sign"
	if family == "jukebox" or family == "note_block" or family == "dispenser":
		return family
	return ""


## The block entities of signs: position -> {"type": "sign", "lines"}.
func sign_entities() -> Dictionary:
	var result := {}
	for pos: Vector3i in _block_entities:
		if _block_entities[pos].type == "sign":
			result[pos] = _block_entities[pos]
	return result


## Writes a sign's text (SignEditScreen).
func set_sign_text(pos: Vector3i, lines: Array) -> void:
	var entity := block_entity(pos)
	if entity.is_empty() or entity.type != "sign":
		return
	entity.lines = lines
	sign_texts.update(pos, lines)
	if remote and not _applying_network:
		Net.send_sign(pos, lines) # the host keeps it and tells the others
	elif Net.is_host():
		Net.sign_changed(pos, lines)


## The signs in a column (Net, sent with it): [x, y, z, lines] each.
func column_signs_for_network(column: Vector2i) -> Array:
	var result := []
	for pos: Vector3i in _block_entities:
		var entity: Dictionary = _block_entities[pos]
		if entity.type == "sign" and floori(pos.x / float(ChunkData.SIZE)) == column.x \
				and floori(pos.z / float(ChunkData.SIZE)) == column.y:
			result.append([pos.x, pos.y, pos.z, entity.lines])
	return result


## Client: a sign's text from the host (its column may still be on the way:
## the label appears with it, SignTexts).
func apply_network_sign(pos: Vector3i, lines: Array) -> void:
	_applying_network = true
	if is_inside(pos) and SignBehavior.is_sign(get_block(pos)):
		set_sign_text(pos, lines)
	else:
		_block_entities[pos] = {"type": "sign", "lines": lines}
	_applying_network = false


## The block entity at `pos` (made when missing), or {} if the block has none.
func block_entity(pos: Vector3i) -> Dictionary:
	var type := _entity_type(get_block(pos))
	if type == "":
		return {}
	if not _block_entities.has(pos) or _block_entities[pos].type != type:
		if type == "sign":
			_block_entities[pos] = {"type": "sign", "lines": ["", "", "", ""]}
			return _block_entities[pos]
		if type == "dispenser":
			_block_entities[pos] = {"type": type, "inventory": Inventory.new(DISPENSER_SIZE)}
			return _block_entities[pos]
		if type == "jukebox" or type == "note_block":
			_block_entities[pos] = {"type": type, "record": 0} if type == "jukebox" else {"type": type, "note": 0}
			return _block_entities[pos]
		var entity := {"type": type, "inventory": Inventory.new(CHEST_SIZE if type == "chest" else FURNACE_SIZE)}
		if type == "furnace":
			entity.merge({"burn": 0, "burn_total": 0, "cook": 0})
		_block_entities[pos] = entity
	return _block_entities[pos]


func _tick_block_entities() -> void:
	for pos: Vector3i in _block_entities.keys():
		var entity: Dictionary = _block_entities[pos]
		if entity.type != "furnace" or not is_inside(pos) or not is_simulated_column(Vector2i(pos.x >> 4, pos.z >> 4)):
			continue
		_tick_furnace(pos, entity)


## A furnace tick like the classic game: fuel burns down; when something
## can be smelted, new fuel is lit and the item cooks for COOK_TICKS; the
## block shows its fire while burning.
func _tick_furnace(pos: Vector3i, entity: Dictionary) -> void:
	var inventory: Inventory = entity.inventory
	var was_burning: bool = entity.burn > 0
	if entity.burn > 0:
		entity.burn -= 1
	var result := Smelting.result_of(inventory.id_at(0))
	var can_smelt := result != Blocks.AIR and (inventory.is_empty_slot(2) \
		or (inventory.id_at(2) == result and inventory.count_at(2) < Items.max_stack(result)))
	if entity.burn == 0 and can_smelt:
		var fuel := Items.fuel_ticks(inventory.id_at(1))
		if fuel > 0:
			entity.burn = fuel
			entity.burn_total = fuel
			if Items.name_of(inventory.id_at(1)) == "lava_bucket":
				inventory.set_slot(1, Items.id_of("bucket"), 1) # the bucket stays
			else:
				inventory.take(1)
	if entity.burn > 0 and can_smelt:
		entity.cook += 1
		if entity.cook >= Smelting.COOK_TICKS:
			entity.cook = 0
			inventory.take(0)
			inventory.set_slot(2, result, inventory.count_at(2) + 1)
	else:
		entity.cook = 0
	var burning: bool = entity.burn > 0
	if burning != was_burning:
		var facing := maxi(Blocks.facing_table[get_block(pos)], 0)
		set_block(pos, Blocks.variant("furnace_lit" if burning else "furnace", facing))


# --- Ticks -----------------------------------------------------------------------------

## Requests a scheduled tick for the block at pos in `delay` game ticks.
## Several requests for the same position and tick are merged.
func schedule_tick(pos: Vector3i, delay: int) -> void:
	if remote or generator == Generator.DEBUG:
		return # (the debug world stays as shown: no flowing, falling, burning)
	var due := clock.game_time + maxi(delay, 1)
	if not _scheduled.has(due):
		_scheduled[due] = {}
	var bucket: Dictionary = _scheduled[due]
	if not bucket.has(pos):
		bucket[pos] = true
		_scheduled_count += 1


func scheduled_tick_count() -> int:
	return _scheduled_count


func mesh_jobs_count() -> int:
	return _mesh_jobs.size()


func generation_jobs_count() -> int:
	return _gen_jobs.size()


## Time of the last tick's parts (microseconds), for profiling.
var tick_times := {}


func _tick(_tick_index: int) -> void:
	if remote:
		# The host runs the world (and sends the time and weather).
		clock.tick()
		_run_display_ticks()
		_mood_tick()
		return
	var t0 := Time.get_ticks_usec()
	_update_sim_areas()
	clock.tick()
	weather.tick()
	WeatherEffects.world_tick(self)
	var t1 := Time.get_ticks_usec()
	_run_scheduled_ticks()
	var t2 := Time.get_ticks_usec()
	_run_random_ticks()
	var t3 := Time.get_ticks_usec()
	_tick_block_entities()
	var t4 := Time.get_ticks_usec()
	_run_display_ticks()
	_wake_springs()
	_mood_tick()
	var t5 := Time.get_ticks_usec()
	tick_times = {"weather": t1 - t0, "scheduled": t2 - t1, "random": t3 - t2, "random_queue": random_queue_us, "block_entities": t4 - t3, "display": t5 - t4}


## Cave sounds like the game's mood sounds: every 6000-18000 ticks a spot
## near the player is tried; dark air out of the sky's sight (deep in a
## cave) plays an eerie sound there.
var _mood_wait := 0


func _mood_tick() -> void:
	if player == null:
		return
	if _mood_wait == 0:
		_mood_wait = _display_rng.randi_range(6000, 18000)
	_mood_wait -= 1
	if _mood_wait > 0:
		return
	var center := Vector3i(player.global_position.floor())
	var spot := center + Vector3i(_display_rng.randi_range(-8, 8), _display_rng.randi_range(-8, 8), _display_rng.randi_range(-8, 8))
	if get_block(spot) == Blocks.AIR and get_light(spot) == 0 and get_block_light(spot) < _display_rng.randi_range(0, 7):
		Sounds.play("ambient/cave", Vector3(spot) + Vector3(0.5, 0.5, 0.5), 0.7, 0.8 + _display_rng.randf() * 0.2)
	else:
		_mood_wait = _display_rng.randi_range(0, 1200) + 1 # try again soon


## Display ticks like the game: random blocks around the player show their
## effects (torch flames and smoke, fire, lava pops, burning furnaces).
const DISPLAY_TICKS := 1000
const DISPLAY_RANGE := 16
var _display_rng := RandomNumberGenerator.new()


## A burning furnace's smoke and flames in front.
static func furnace_display_tick(world: VoxelWorld, pos: Vector3i, rng: RandomNumberGenerator) -> void:
	if rng.randf() < 0.5:
		world.particles.furnace(pos, maxi(Blocks.facing_table[world.get_block(pos)], 0))


func _run_display_ticks() -> void:
	if player == null:
		return
	# Like the game's 1000 random blocks around the player, picked straight
	# from the arrays of the 3 x 3 x 3 chunks around (cheap: 27 lookups).
	var center := chunk_coord_of(Vector3i(player.global_position.floor()))
	var handlers := Blocks.display_table
	var per_chunk := DISPLAY_TICKS / 27 + 1
	for dy in range(-1, 2):
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var coord := center + Vector3i(dx, dy, dz)
				var data: ChunkData = _chunks.get(coord)
				if data == null:
					continue
				var blocks := data.blocks
				var origin := coord * ChunkData.SIZE
				for i in per_chunk:
					var index := _display_rng.randi() & 4095
					var id: int = blocks[index]
					if handlers[id] == 1:
						var pos := origin + Vector3i(index & 15, index >> 8, (index >> 4) & 15)
						Blocks.get_type(id).display_tick.call(self, pos, _display_rng)
				if coord.y == 0:
					_void_dust(data, origin)


## Springs start to flow when a player comes near (their display tick, see
## NatureBehavior.spring_display_tick): the host does it around the network
## game's other players too (a dedicated server has no player of its own).
const SPRING_TRIES := 10
var _spring_table := PackedByteArray()


func _wake_springs() -> void:
	if not Net.is_host() or Net.avatars.is_empty():
		return
	if _spring_table.is_empty():
		_spring_table.resize(Blocks.count())
		for id in Blocks.count():
			_spring_table[id] = 1 if Blocks.get_type(id).name.ends_with("_spring") else 0
	for at: Vector3 in player_positions():
		if player and at == player.global_position:
			continue # (its own display ticks)
		var center := chunk_coord_of(Vector3i(at.floor()))
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var coord := center + Vector3i(dx, dy, dz)
					var data: ChunkData = _chunks.get(coord)
					if data == null:
						continue
					for i in SPRING_TRIES:
						var index := _display_rng.randi() & 4095
						if _spring_table[data.blocks[index]] == 1:
							NatureBehavior.spring_display_tick(self, coord * ChunkData.SIZE + Vector3i(index & 15, index >> 8, (index >> 4) & 15), _display_rng)


## The void's dust like the game's: in air near the bedrock (below y 8),
## dark specks drift, more the deeper (a cell at height y: 7 - y in 8).
const VOID_DUST_TRIES := 40


func _void_dust(data: ChunkData, origin: Vector3i) -> void:
	for i in VOID_DUST_TRIES:
		var index := _display_rng.randi() & 2047 # the lowest 8 layers
		var y := index >> 8
		if data.blocks[index] == Blocks.AIR and _display_rng.randi_range(0, 7) > y:
			var pos := origin + Vector3i(index & 15, y, (index >> 4) & 15)
			particles.void_speck(Vector3(pos) + Vector3(_display_rng.randf(), _display_rng.randf(), _display_rng.randf()))


func _run_scheduled_ticks() -> void:
	var now := clock.game_time
	if not _scheduled.has(now):
		return
	var bucket: Dictionary = _scheduled[now]
	_scheduled.erase(now)
	var processed := 0
	var started := Time.get_ticks_usec()
	for pos: Vector3i in bucket:
		_scheduled_count -= 1
		if processed >= MAX_SCHEDULED_TICKS_PER_TICK or Time.get_ticks_usec() - started > SCHEDULED_TICK_BUDGET_US:
			schedule_tick(pos, 1) # over the limit: wait for the next tick
			continue
		var column := Vector2i(pos.x >> 4, pos.z >> 4)
		if not is_simulated_column(column):
			if not _sleeping_ticks.has(column):
				_sleeping_ticks[column] = {}
			(_sleeping_ticks[column] as Dictionary)[pos] = true
			continue
		processed += 1
		var handler := Blocks.get_type(get_block(pos)).scheduled_tick
		if handler.is_valid():
			handler.call(self, pos)


## The simulated areas around the players this tick (simulation_distance;
## a network player's no further than the world is loaded around it).
## When they changed, the scheduled ticks that slept in columns now inside
## wake up.
func _update_sim_areas() -> void:
	var areas: Array[Vector3i] = []
	var own := player as Player
	for at in player_positions(false):
		var radius := simulation_distance if own and at == own.global_position else mini(simulation_distance, remote_radius)
		areas.append(Vector3i(floori(at.x) >> 4, floori(at.z) >> 4, radius))
	if areas == _sim_areas:
		return
	_sim_areas = areas
	for column: Vector2i in _sleeping_ticks.keys():
		if is_simulated_column(column):
			for pos: Vector3i in _sleeping_ticks[column]:
				schedule_tick(pos, 1)
			_sleeping_ticks.erase(column)


## Whether the column is in a player's simulated area (see
## simulation_distance). True before the first tick (nothing known yet).
func is_simulated_column(column: Vector2i) -> bool:
	if _sim_areas.is_empty():
		return true
	for area in _sim_areas:
		if absi(column.x - area.x) <= area.z and absi(column.y - area.y) <= area.z:
			return true
	return false


func is_simulated(at: Vector3) -> bool:
	return is_simulated_column(Vector2i(floori(at.x) >> 4, floori(at.z) >> 4))


## Where the players are: this one and, hosting, the network game's
## others (their last position the host accepted); `alive_only` leaves out
## the dead.
func player_positions(alive_only: bool = true) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var own := player as Player
	if own and not (alive_only and own.dead):
		result.append(own.global_position)
	if Net.is_host():
		for avatar: RemotePlayer in Net.avatars.values():
			if is_instance_valid(avatar) and not (alive_only and avatar.dead):
				result.append(avatar.target_position)
	return result


## Random ticks reach simulation_distance columns around the players, like
## the game's (9 chunks in Beta; the rest of the loaded world just waits).
## Main-thread time random ticks may take per tick; what's left over goes on
## next tick from where it stopped, so a tick never stalls a frame.
const RANDOM_TICK_BUDGET_US := 2000

var _random_tick_queue: Array[Vector3i] = []
## The chunks random ticks go through, kept between rounds and kept up to
## date as things change: a column loaded in reach adds its chunks, a player
## moving to another column adds the columns come into reach and drops the
## ones left behind, a block that ticks placed in a chunk not on the list
## adds it. (Scanning every column's chunks each round was most of the
## cost.) Only a new world gathers them all again (_random_dirty).
var _random_chunks: Array[Vector3i] = []
var _random_chunk_set := {}
var _random_columns := {} # Vector2i -> true: columns gone through
var _random_dirty := true
var _random_centers: Array[Vector2i] = []
var _random_radii := PackedInt32Array()


## Whether random ticks reach the column (around one of the players).
func _in_random_reach(column: Vector2i) -> bool:
	for c in _random_centers.size():
		var center := _random_centers[c]
		if absi(column.x - center.x) <= _random_radii[c] and absi(column.y - center.y) <= _random_radii[c]:
			return true
	return false


## A column just loaded joins the list if it is in reach of a player (an
## unloaded one's chunks are just skipped: not in _chunks).
func _add_random_chunks(column: Vector2i) -> void:
	if _in_random_reach(column):
		_add_random_column(column)


func _add_random_column(column: Vector2i) -> void:
	_random_columns[column] = true
	var cy := 0
	for data: ChunkData in _columns[column]:
		var coord := Vector3i(column.x, cy, column.y)
		if data.tickable_count > 0 and not _random_chunk_set.has(coord):
			_random_chunks.append(coord)
			_random_chunk_set[coord] = true
		cy += 1


## Main-thread time gathering the chunks last tick (profiling).
var random_queue_us := 0


func _run_random_ticks() -> void:
	if random_tick_speed <= 0:
		return
	var queue_started := Time.get_ticks_usec()
	if _random_tick_queue.is_empty():
		# A new round: the chunks with something that ticks, near the
		# players (this one, and the network game's others on the host).
		var centers: Array[Vector2i] = []
		var radii := PackedInt32Array()
		for at in player_positions(false):
			centers.append(Vector2i(floori(at.x) >> 4, floori(at.z) >> 4))
			radii.append(simulation_distance if player and at == player.global_position else mini(simulation_distance, remote_radius))
		if _random_dirty:
			_random_dirty = false
			_random_chunks.clear()
			_random_chunk_set.clear()
			_random_columns.clear()
			_random_centers.clear()
		if centers != _random_centers or radii != _random_radii:
			_random_centers = centers
			_random_radii = radii
			# Out of reach now: dropped.
			var kept: Array[Vector3i] = []
			for coord in _random_chunks:
				if _in_random_reach(Vector2i(coord.x, coord.z)):
					kept.append(coord)
				else:
					_random_chunk_set.erase(coord)
			_random_chunks = kept
			for column: Vector2i in _random_columns.keys():
				if not _in_random_reach(column):
					_random_columns.erase(column)
			# Come into reach: added.
			for c in centers.size():
				var center := centers[c]
				for cx in range(center.x - radii[c], center.x + radii[c] + 1):
					for cz in range(center.y - radii[c], center.y + radii[c] + 1):
						var column := Vector2i(cx, cz)
						if _columns.has(column) and not _random_columns.has(column):
							_add_random_column(column)
		_random_tick_queue = _random_chunks.duplicate()
	var ticks_randomly := Blocks.ticks_randomly
	var started := Time.get_ticks_usec()
	random_queue_us = started - queue_started
	if _native_ticks:
		_random_ticks_native(started)
		return
	while not _random_tick_queue.is_empty():
		var coord: Vector3i = _random_tick_queue.pop_back()
		var data: ChunkData = _chunks.get(coord)
		if data == null or data.tickable_count == 0:
			continue
		var blocks := data.blocks
		var origin: Vector3i = coord * ChunkData.SIZE
		for i in random_tick_speed:
			var index := rng.randi() & 4095
			var id: int = blocks[index]
			if ticks_randomly[id] == 0:
				continue
			Blocks.get_type(id).random_tick.call(self, origin + Vector3i(index & 15, index >> 8, (index >> 4) & 15))
		if Time.get_ticks_usec() - started > RANDOM_TICK_BUDGET_US:
			break


## The round's picking in C++ (NativePath.random_ticks): only the tries that
## hit a block that ticks come back to run here.
static var _native_ticks := ClassDB.class_exists("NativePath")
static var _grass_table := PackedByteArray()
static var _grass_covers := PackedByteArray()


## A round of random ticks takes this many game ticks: each tick a share of
## the chunks gets that many times the tries, so a block is ticked as often
## as before while gathering the chunks (most of the cost) happens for a
## quarter of them a tick.
const RANDOM_ROUND_TICKS := 4


func _random_ticks_native(_started: int) -> void:
	var arrays := []
	var origins: Array[Vector3i] = []
	var share := ceili(float(_random_chunks.size()) / RANDOM_ROUND_TICKS)
	while share > 0 and not _random_tick_queue.is_empty():
		share -= 1
		var coord: Vector3i = _random_tick_queue.pop_back()
		var data: ChunkData = _chunks.get(coord)
		if data == null or data.tickable_count == 0:
			continue
		arrays.append(data.blocks)
		origins.append(coord * ChunkData.SIZE)
	if _grass_table.is_empty():
		# For leaving out the grass ticks that can change nothing
		# (NativePath.random_ticks_pruned, by GrassBehavior's rules).
		var grass_tick := Callable(GrassBehavior, "random_tick")
		for block in Blocks.types:
			_grass_table.append(1 if block.random_tick == grass_tick else 0)
			_grass_covers.append(1 if Blocks.is_opaque(block.id) or Blocks.liquid_table[block.id] == 1 else 0)
	var hits: PackedInt32Array = ClassDB.class_call_static("NativePath", "random_ticks_pruned", arrays,
		random_tick_speed * RANDOM_ROUND_TICKS, Blocks.ticks_randomly, rng.randi(), _grass_table, _grass_covers,
		Blocks.id_of("dirt"))
	for i in range(0, hits.size(), 2):
		var index := hits[i + 1]
		var origin := origins[hits[i]]
		# (a block ticked before may have changed this one: run what is there now)
		var pos := origin + Vector3i(index & 15, index >> 8, (index >> 4) & 15)
		var id := get_block(pos)
		if Blocks.ticks_randomly[id] == 1:
			Blocks.get_type(id).random_tick.call(self, pos)


# --- Meshing -----------------------------------------------------------------------------

## Slots generation and light may fill: all but one while meshes wait and
## none is running (a mesh job is short, a column takes much longer: without
## the spare slot what is ready would wait to be seen), all otherwise.
func _job_room() -> int:
	var meshes_wait := not _mesh_queue.is_empty() or not _mesh_backlog.is_empty() or not _urgent_mesh.is_empty()
	return _max_jobs - (1 if meshes_wait and _mesh_jobs.is_empty() else 0)


## Light takes all but two of the worker slots at most.
func _half_jobs() -> int:
	return maxi(_max_jobs - 2, 1)


## Worker jobs of every kind running now: generation, light and meshes
## share the cores, so the main thread keeps one to itself.
func _busy_jobs() -> int:
	return _gen_jobs.size() + _light_jobs.size() + _mesh_jobs.size()


## Chunks with changed blocks: meshed first, without waiting for the queue.
var _urgent_mesh := {}
## When the queue was last sorted (ms): sorting every waiting chunk is the
## expensive part, so while the world streams in it happens at most every
## MESH_QUEUE_INTERVAL_MS.
var _queue_sorted_at := -100000
const MESH_QUEUE_INTERVAL_MS := 250


## The dirty chunks of a column that just became meshable go to the
## backlog (taken after the sorted queue); air and far deep chunks are
## dealt with at once.
func _enqueue_column(column: Vector2i) -> void:
	if no_meshes or not _columns.has(column) or not _can_mesh(Vector3i(column.x, 0, column.y)):
		return
	var near := open_edges or _near_player(column)
	for k in WorldGenerator.HEIGHT_CHUNKS:
		var coord := Vector3i(column.x, k, column.y)
		if not _dirty.has(coord) or _mesh_jobs.has(coord):
			continue
		var chunk: ChunkData = _chunks[coord]
		if chunk.air_count == ChunkData.VOLUME:
			_clear_chunk_mesh(coord)
		elif not near and _is_deep(coord):
			_dirty.erase(coord)
			if not _deferred.has(column):
				_deferred[column] = {}
			(_deferred[column] as Dictionary)[k] = true
		else:
			_mesh_backlog.append(coord)


var _mesh_backlog: Array[Vector3i] = []

## The frame's heavy step is taken: when the player crosses into another
## column the streaming scan, the meshing queue's sort and the start of the
## cave culling (copies of big dictionaries) all came due at once - 20 ms
## and more in one frame, a stutter every 16 blocks walked. Each now takes a
## frame of its own (_take_heavy_frame).
var _heavy_frame := -1


## True once a frame: the caller may do its heavy step now; false if another
## did one this frame (it comes again next frame).
func _take_heavy_frame() -> bool:
	var frame := Engine.get_process_frames()
	if frame == _heavy_frame:
		return false
	_heavy_frame = frame
	return true


func _start_mesh_jobs() -> void:
	var free_slots := _max_jobs - _busy_jobs()
	if _light_scan_needed or not _wanted_columns.is_empty():
		# A slot stays free for columns waiting to be generated or lit:
		# endless re-meshing (lava flowing, its light changing) starved them.
		free_slots = mini(free_slots, _max_jobs - 1 - _mesh_jobs.size())
	if free_slots <= 0:
		return
	var now := Time.get_ticks_msec()
	if _mesh_scan_needed and (_mesh_queue.is_empty() or now - _queue_sorted_at >= MESH_QUEUE_INTERVAL_MS) \
			and _take_heavy_frame():
		_mesh_scan_needed = false
		_queue_sorted_at = now
		_rebuild_mesh_queue()
	var picked: Array[Vector3i] = []
	for coord: Vector3i in _urgent_mesh.keys():
		if picked.size() >= free_slots:
			break
		if _mesh_jobs.has(coord):
			continue # waits for that job; picked up again when it ends
		_urgent_mesh.erase(coord)
		var chunk: ChunkData = _chunks.get(coord)
		if chunk == null or not _dirty.has(coord) or not _can_mesh(coord):
			continue
		if chunk.air_count == ChunkData.VOLUME:
			_clear_chunk_mesh(coord)
			continue
		picked.append(coord)
	while picked.size() < free_slots and not _mesh_queue.is_empty():
		var coord: Vector3i = _mesh_queue.pop_back()
		if _dirty.has(coord) and not _mesh_jobs.has(coord) and _chunks.has(coord) and not picked.has(coord):
			picked.append(coord)
	while picked.size() < free_slots and not _mesh_backlog.is_empty():
		var coord: Vector3i = _mesh_backlog.pop_back()
		if _dirty.has(coord) and not _mesh_jobs.has(coord) and _chunks.has(coord) and not picked.has(coord):
			picked.append(coord)
	for coord in picked:
		_dirty.erase(coord)
		var job := MeshJob.new()
		job.coord = coord
		var data: ChunkData = _chunks[coord]
		job.center = data.blocks # copy-on-write snapshots
		job.center_light = data.light
		job.center_block_light = data.block_light
		job.colors = _column_colors.get(Vector2i(coord.x, coord.z), job.colors)
		job.fast = data.leaf_count > 0 and _far_leaves(Vector2i(coord.x, coord.z))
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					var offset := Vector3i(dx, dy, dz)
					if offset != Vector3i.ZERO:
						var neighbor: ChunkData = _chunks.get(coord + offset)
						if open_edges and not _in_render_radius(Vector2i(coord.x + dx, coord.z + dz)):
							neighbor = null # beyond the edge counts as air: solid side walls
						job.neighbors[offset] = neighbor.blocks if neighbor else PackedInt32Array()
						job.neighbor_light[offset] = neighbor.light if neighbor else PackedByteArray()
						job.neighbor_block_light[offset] = neighbor.block_light if neighbor else PackedByteArray()
		job.task_id = WorkerThreadPool.add_task(job.run, false, "Chunk mesh")
		_mesh_jobs[coord] = job


## Sorts the meshable dirty chunks, nearest last (popped first). Rebuilt
## only when something changed what can be meshed (a column lit or loaded,
## the player moved to another column, a block changed), not every time a
## mesh finishes: scanning all waiting chunks is the expensive part.
var _queue_us := 0


func _rebuild_mesh_queue() -> void:
	var queue_start := Time.get_ticks_usec()
	_mesh_queue.clear()
	_mesh_backlog.clear() # everything waiting is sorted again here
	var center := Vector3(_player_column.x, (player.global_position.y if player else float(sea_level)) / ChunkData.SIZE, _player_column.y)
	# Per column, worked out once for all its chunks: whether it can be
	# meshed, and the height at or under which its chunks count as deep
	# (_is_deep; -1: none are, near the player or with open edges).
	var column_info := {} # Vector2i -> Vector2i(meshable 0/1, deep top)
	var view: Vector3 = player.look_direction() if player and player.has_method("look_direction") else Vector3.ZERO
	var keys := PackedInt64Array()
	var coords: Array[Vector3i] = []
	var empty: Array[Vector3i] = []
	var deep: Array[Vector3i] = []
	for coord: Vector3i in _dirty:
		# The column first: most waiting chunks are in columns that can't be
		# meshed yet (not lit, or their neighbors aren't), passed over at once.
		var column := Vector2i(coord.x, coord.z)
		var info: Variant = column_info.get(column)
		if info == null:
			info = Vector2i(1 if _can_mesh(coord) else 0, -1 if open_edges or _near_player(column) else _deep_top(column))
			column_info[column] = info
		var deep_chunk: bool = coord.y * ChunkData.SIZE + ChunkData.SIZE <= (info as Vector2i).y
		if (info as Vector2i).x == 0 and not deep_chunk:
			continue
		if _mesh_jobs.has(coord):
			continue
		var chunk: ChunkData = _chunks.get(coord)
		if chunk and chunk.air_count == ChunkData.VOLUME:
			empty.append(coord) # nothing to draw: no job at all
			continue
		if deep_chunk:
			deep.append(coord) # far underground: built when the player comes near
			continue
		# Farthest first after sorting: key = -distance (fixed point), index.
		# Like the modern game, chunks in front of the camera come first:
		# the ones behind count as three times farther.
		var offset := Vector3(coord) - center
		var distance: int
		if loading_radius >= 0:
			# Loading: the columns the loading screen waits for come first,
			# nearest columns first, whichever way the camera looks.
			var away := maxi(absi(column.x - _player_column.x), absi(column.y - _player_column.y))
			distance = int(Vector2(offset.x, offset.z).length_squared() * 16.0) + (1 << 24 if away > loading_radius else 0)
		else:
			var weight := 3.0 if offset.length_squared() > 2.0 and offset.normalized().dot(view) < -0.2 else 1.0
			distance = int(offset.length_squared() * weight * 16.0)
		keys.append((-distance << 20) | coords.size())
		coords.append(coord)
	keys.sort()
	for key in keys:
		_mesh_queue.append(coords[key & 0xFFFFF])
	for coord in empty:
		_clear_chunk_mesh(coord)
	for coord in deep:
		_dirty.erase(coord)
		var column := Vector2i(coord.x, coord.z)
		if not _deferred.has(column):
			_deferred[column] = {}
		(_deferred[column] as Dictionary)[coord.y] = true
	_queue_us = Time.get_ticks_usec() - queue_start


## Chunks deep under the ground far from the player have no mesh until the
## player comes within DEEP_MESH_RADIUS columns: nobody sees them (caves are
## dark and hidden), and they were most of the meshing work.
const DEEP_MESH_RADIUS := 4
## A chunk is deep when its top is this far below the lowest surface of its
## column and the 8 around it (so cliffs, pits and overhangs still show).
const DEEP_MARGIN := 8
var _deferred := {}       # Vector2i (column) -> {chunk y: true}: deep chunks waiting for the player
var _surface_min := {}    # Vector2i -> lowest heightmap value of the column


func _near_player(column: Vector2i) -> bool:
	return absi(column.x - _player_column.x) <= DEEP_MESH_RADIUS and absi(column.y - _player_column.y) <= DEEP_MESH_RADIUS


## The highest top a chunk of `column` may have and still be deep
## (_is_deep for all its chunks at once).
func _deep_top(column: Vector2i) -> int:
	var lowest := 2147483647
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			lowest = mini(lowest, _surface_min.get(Vector2i(column.x + dx, column.y + dz), -1))
	return lowest - DEEP_MARGIN


func _is_deep(coord: Vector3i) -> bool:
	var top := coord.y * ChunkData.SIZE + ChunkData.SIZE
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var lowest: int = _surface_min.get(Vector2i(coord.x + dx, coord.z + dz), -1)
			if top > lowest - DEEP_MARGIN:
				return false
	return true


## The player came near: the deep chunks around get their meshes.
func _wake_deferred() -> void:
	for dx in range(-DEEP_MESH_RADIUS, DEEP_MESH_RADIUS + 1):
		for dz in range(-DEEP_MESH_RADIUS, DEEP_MESH_RADIUS + 1):
			_wake_column(_player_column + Vector2i(dx, dz))


func _wake_column(column: Vector2i) -> void:
	var waiting: Variant = _deferred.get(column)
	if waiting == null:
		return
	_deferred.erase(column)
	for y: int in waiting:
		var coord := Vector3i(column.x, y, column.y)
		if _chunks.has(coord):
			_dirty[coord] = true


## A chunk of only air: no mesh, open to cave culling on every side.
func _clear_chunk_mesh(coord: Vector3i) -> void:
	_dirty.erase(coord)
	_connectivity.erase(coord)
	_total_faces -= _chunk_faces.get(coord, 0)
	_chunk_faces.erase(coord)
	var instance: MeshInstance3D = _chunk_nodes.get(coord)
	if instance:
		instance.queue_free()
		_chunk_nodes.erase(coord)
		_culled.erase(coord)
	_cull_dirty = true


const MESH_UPLOAD_BUDGET_US := 4000


func _finish_mesh_jobs() -> void:
	# Finished meshes uploaded per frame (main-thread work): Chunk Updates.
	var max_uploads: int = Settings.CHUNK_UPDATE_CHOICES[Settings.get_value("chunk_updates")]
	var uploads := 0
	var started := Time.get_ticks_usec()
	for coord: Vector3i in _mesh_jobs.keys():
		# Also at most ~4 ms of uploads a frame, so moving doesn't stutter.
		if uploads >= max_uploads or (uploads > 0 and Time.get_ticks_usec() - started > MESH_UPLOAD_BUDGET_US):
			break
		var job: MeshJob = _mesh_jobs[coord]
		if not WorkerThreadPool.is_task_completed(job.task_id):
			continue
		WorkerThreadPool.wait_for_task_completion(job.task_id)
		_mesh_jobs.erase(coord)
		if _dirty.has(coord):
			_urgent_mesh[coord] = true # changed again while it was being meshed
		if _chunks.has(coord):
			_apply_mesh(job)
			uploads += 1


func _apply_mesh(job: MeshJob) -> void:
	var faces := job.faces
	var mesh: ArrayMesh = job.mesh
	_total_faces += faces - _chunk_faces.get(job.coord, 0)
	_chunk_faces[job.coord] = faces
	_last_mesh_ms = job.mesh_ms
	_connectivity[job.coord] = job.connectivity
	_cull_dirty = true

	var instance: MeshInstance3D = _chunk_nodes.get(job.coord)
	if mesh == null:
		if instance:
			instance.queue_free()
			_chunk_nodes.erase(job.coord)
			_culled.erase(job.coord)
		return
	if instance == null:
		instance = MeshInstance3D.new()
		instance.position = Vector3(job.coord * ChunkData.SIZE)
		add_child(instance)
		_chunk_nodes[job.coord] = instance
		_culled.erase(job.coord)
	instance.mesh = mesh


# --- Edges (world diorama) -----------------------------------------------------

## Radius in chunks of the drawn area while the edges are open (the world
## diorama's Area; -1: the render distance). Chunks beyond it are hidden.
var edge_radius := -1
## The edge columns last re-meshed with walls (to restore when they move).
var _open_edge_columns: Array[Vector2i] = []


func _edge_radius() -> int:
	return render_distance if edge_radius < 0 else mini(edge_radius, render_distance)


func _in_render_radius(column: Vector2i) -> bool:
	var radius := _edge_radius()
	return absi(column.x - _player_column.x) <= radius and absi(column.y - _player_column.y) <= radius


## Columns on the edge of the drawn area.
func _edge_columns() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var radius := _edge_radius()
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			if maxi(absi(dx), absi(dz)) == radius:
				result.append(_player_column + Vector2i(dx, dz))
	return result


## Re-meshes the edge columns with (or without) solid side walls.
func set_open_edges(open: bool) -> void:
	open_edges = open
	if open:
		# The isometric view shows the ground cut open: every chunk is needed.
		for column: Vector2i in _deferred.keys():
			_wake_column(column)
	_refresh_edges()


## Changes the drawn area's radius (see edge_radius).
func set_edge_radius(radius: int) -> void:
	if radius == edge_radius:
		return
	edge_radius = radius
	if open_edges:
		_refresh_edges()


## Re-meshes the old and the new edge columns (walls on or off) and shows
## or hides the chunks beyond the edge.
func _refresh_edges() -> void:
	var columns: Array[Vector2i] = _open_edge_columns.duplicate()
	_open_edge_columns.clear()
	if open_edges:
		_open_edge_columns = _edge_columns()
	columns.append_array(_edge_columns())
	for column: Vector2i in columns:
		for k in WorldGenerator.HEIGHT_CHUNKS:
			var coord := Vector3i(column.x, k, column.y)
			if _chunks.has(coord):
				_dirty[coord] = true
	_mesh_scan_needed = true
	_cull_dirty = true
	_cull_timer = 0.0


## Lowest and highest block y of the non-empty chunks in the drawn area.
func edge_height_range() -> Vector2i:
	var radius := _edge_radius()
	var low := height
	var high := 0
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			for k in WorldGenerator.HEIGHT_CHUNKS:
				var chunk: ChunkData = _chunks.get(Vector3i(_player_column.x + dx, k, _player_column.y + dz))
				if chunk and chunk.air_count < ChunkData.VOLUME:
					low = mini(low, k * ChunkData.SIZE)
					high = maxi(high, (k + 1) * ChunkData.SIZE)
	return Vector2i(0, height) if high <= low else Vector2i(low, high)


## Edge chunks still waiting for their new mesh.
func edges_pending() -> int:
	var count := 0
	for column in _edge_columns():
		for k in WorldGenerator.HEIGHT_CHUNKS:
			var coord := Vector3i(column.x, k, column.y)
			if _dirty.has(coord) or _mesh_jobs.has(coord):
				count += 1
	return count


# --- Cave culling -----------------------------------------------------------------------

const FACE_DIRECTIONS: Array[Vector3i] = [
	Vector3i.UP, Vector3i.DOWN, Vector3i.RIGHT, Vector3i.LEFT, Vector3i.BACK, Vector3i.FORWARD,
]
## Seconds between culling passes at most (they run when something changed).
const CULL_INTERVAL := 0.1


## Advanced cave culling, like the modern game: a breadth-first walk from
## the camera's chunk through the chunk faces that are connected inside
## each chunk (ChunkMesher.connectivity), never turning back toward the
## camera. Chunks it can't reach (caves behind solid rock, the ground under
## the player) are hidden. Runs when the camera enters another chunk or a
## chunk's mesh changes; frustum culling is still done by the renderer.
func _update_culling(delta: float) -> void:
	_cull_timer -= delta
	var eye: Vector3 = player.eye_position() if player and player.has_method("eye_position") \
		else (player.global_position if player else Vector3.ZERO)
	var camera_chunk := chunk_coord_of(Vector3i(eye.floor()))
	if camera_chunk != _camera_chunk:
		_camera_chunk = camera_chunk
		_cull_dirty = true
	# The search runs on a worker thread; its result is applied when done.
	if _cull_task >= 0:
		if not WorkerThreadPool.is_task_completed(_cull_task):
			return
		WorkerThreadPool.wait_for_task_completion(_cull_task)
		_cull_task = -1
		_apply_culling(_cull_job)
	if not _cull_dirty or _cull_timer > 0.0 or not _take_heavy_frame():
		return
	_cull_dirty = false
	_cull_timer = CULL_INTERVAL
	if not culling_enabled or not Settings.get_value("cave_culling") or camera_chunk.y < 0 \
			or camera_chunk.y >= WorldGenerator.HEIGHT_CHUNKS or not _chunks.has(camera_chunk):
		for coord: Vector3i in _chunk_nodes:
			# (with the edges open, only the drawn area)
			(_chunk_nodes[coord] as Node3D).visible = not open_edges or _in_render_radius(Vector2i(coord.x, coord.z))
		culled_chunks = 0
		_culled.clear()
		return
	_cull_job = {"connectivity": _connectivity.duplicate(), "camera": camera_chunk, "column": _player_column,
		"distance": render_distance, "reached": {}, "nodes": _chunk_nodes.keys(), "culled": _culled.duplicate(),
		"hide": [], "show": []}
	_cull_task = WorkerThreadPool.add_task(_cull_search.bind(_cull_job), false, "cave culling")


## The cave culling search (worker thread): from the camera's chunk through
## the chunks' open faces (ChunkMesher.connectivity), never turning back
## toward the camera; what it can't reach is hidden.
static func _cull_search(job: Dictionary) -> void:
	var connectivity: Dictionary = job.connectivity
	var camera: Vector3i = job.camera
	var column: Vector2i = job.column
	var distance: int = job.distance
	var reached: Dictionary = job.reached
	reached[camera] = true
	var queue := []
	for face in 6:
		queue.append([camera + FACE_DIRECTIONS[face], face ^ 1, 1 << face])
	var head := 0
	while head < queue.size():
		var entry: Array = queue[head]
		head += 1
		var coord: Vector3i = entry[0]
		if reached.has(coord) or coord.y < 0 or coord.y >= WorldGenerator.HEIGHT_CHUNKS \
				or absi(coord.x - column.x) > distance or absi(coord.z - column.y) > distance:
			continue
		reached[coord] = true
		var entered: int = entry[1]
		var directions: int = entry[2]
		var connections: int = connectivity.get(coord, ChunkMesher.ALL_CONNECTED)
		for face in 6:
			if directions & (1 << (face ^ 1)):
				continue # never back toward the camera
			if (connections >> (entered * 6 + face)) & 1 == 0:
				continue # no way through this chunk to that face
			queue.append([coord + FACE_DIRECTIONS[face], face ^ 1, directions | (1 << face)])
	# What changes: the chunks to hide and to show again (the main thread
	# only touches those).
	var culled: Dictionary = job.culled
	for node_coord: Vector3i in job.nodes:
		var visible := reached.has(node_coord)
		if visible and culled.has(node_coord):
			(job.show as Array).append(node_coord)
		elif not visible and not culled.has(node_coord):
			(job.hide as Array).append(node_coord)


## Chunks hidden by cave culling (their nodes).
var _culled := {}


## Shows the reached chunks and hides the rest: the changes the search
## worked out (_cull_search).
func _apply_culling(job: Dictionary) -> void:
	for coord: Vector3i in job.show:
		_culled.erase(coord)
		var node: Node3D = _chunk_nodes.get(coord)
		if node:
			node.visible = true
	for coord: Vector3i in job.hide:
		var node: Node3D = _chunk_nodes.get(coord)
		if node:
			node.visible = false
			_culled[coord] = true
	culled_chunks = _culled.size()


# --- Saving --------------------------------------------------------------------------

## Writes every changed loaded column to the save (columns unloaded earlier
## were written when they unloaded).
## `in_background` (the autosave while playing): the columns are
## compressed and written on worker threads - written here, some 70 columns
## held a frame for 50 ms every autosave. Leaving the world saves here and
## waits for everything still being written.
func save_columns(in_background: bool = false) -> void:
	if save == null:
		return
	PistonBehavior.finish_all(self) # no half-moved blocks in the save
	if not in_background:
		for column: Vector2i in _save_tasks.keys():
			_finish_save(column)
	for column: Vector2i in _modified.keys():
		if _columns.has(column):
			_save_column(column, in_background)
	_modified.clear()


## `in_background`: compressed and written on a worker thread (columns
## unloading behind the player: a dozen at a time stalled the frame).
func _save_column(column: Vector2i, in_background: bool = false) -> void:
	_modified.erase(column)
	if save == null:
		return
	var blocks := PackedInt32Array()
	for k in WorldGenerator.HEIGHT_CHUNKS:
		blocks.append_array((_chunks[Vector3i(column.x, k, column.y)] as ChunkData).blocks)
	_finish_save(column) # an older save of it still running: first
	if in_background:
		var target := save
		_save_tasks[column] = WorkerThreadPool.add_task(func() -> void: target.save_column(column, blocks), false, "Column save")
	else:
		save.save_column(column, blocks)


var _save_tasks := {} # Vector2i -> worker task writing that column


## Waits for a column's background save (before it is read or written again).
func _finish_save(column: Vector2i) -> void:
	if _save_tasks.has(column):
		WorkerThreadPool.wait_for_task_completion(_save_tasks[column])
		_save_tasks.erase(column)


## World state for the save: time and game rules.
func save_state() -> Dictionary:
	var rules := {}
	for rule_name in GameRules.names():
		rules[rule_name] = GameRules.rules[rule_name].get.call(self)
	var saved_block_entities := {}
	for pos: Vector3i in _block_entities:
		var entity: Dictionary = _block_entities[pos].duplicate()
		if entity.has("inventory"):
			entity.inventory = (entity.inventory as Inventory).save_state()
		saved_block_entities[pos] = entity
	return {"game_time": clock.game_time, "day_time": clock.day_time, "rules": rules,
		"block_entities": saved_block_entities, "items": items.save_state(), "entities": entities.save_state(),
		"maps": maps, "next_map_id": next_map_id, "weather": weather.save_state(), "stats": Stats.save_state(),
		"spawn": world_spawn}


func _restore_state() -> void:
	var world_state: Dictionary = save.state.get("world", {}) if save else {}
	Stats.load_state(world_state.get("stats", {})) # each world has its own
	if world_state.is_empty():
		return
	clock.game_time = world_state.get("game_time", 0)
	var saved_block_entities: Dictionary = world_state.get("block_entities", {})
	for pos: Vector3i in saved_block_entities:
		var entity: Dictionary = saved_block_entities[pos].duplicate()
		if entity.has("inventory"):
			var inventory := Inventory.new({"chest": CHEST_SIZE, "dispenser": DISPENSER_SIZE}.get(entity.type, FURNACE_SIZE))
			inventory.load_state(entity.inventory)
			entity.inventory = inventory
		_block_entities[pos] = entity
	items.load_state(world_state.get("items", []))
	entities.load_state(world_state.get("entities", []))
	maps = world_state.get("maps", {})
	weather.load_state(world_state.get("weather", {}))
	next_map_id = world_state.get("next_map_id", 0)
	world_spawn = world_state.get("spawn", Vector3.INF)
	clock.day_time = world_state.get("day_time", start_day_time)
	var rules: Dictionary = world_state.get("rules", {})
	for rule_name: String in rules:
		if GameRules.rules.has(rule_name):
			GameRules.rules[rule_name].set.call(self, rules[rule_name])


## How far the area around the player is: columns generated, lit and fully
## meshed within `radius` columns (for the loading screen).
func loading_progress(radius: int) -> Dictionary:
	var center := _player_column_now()
	var generated := 0
	var lit := 0
	var meshed := 0
	var total := 0
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			var column := center + Vector2i(dx, dz)
			total += 1
			if not _columns.has(column):
				continue
			generated += 1
			if not _lit.has(column):
				continue
			lit += 1
			var done := true
			for k in WorldGenerator.HEIGHT_CHUNKS:
				var coord := Vector3i(column.x, k, column.y)
				if _dirty.has(coord) or _mesh_jobs.has(coord):
					done = false
					break
			if done:
				meshed += 1
	return {"generated": generated, "lit": lit, "meshed": meshed, "total": total}


## Numbers for the debug screen (built on request, not every frame).
func get_stats() -> Dictionary:
	return {
		"generator": Generator.keys()[generator],
		"seed": world_seed,
		"chunks": _chunks.size(),
		"columns": _columns.size(),
		"visible_chunks": _chunk_nodes.size(),
		"faces": _total_faces,
		"triangles": _total_faces * 2,
		"vertices": _total_faces * 4,
		"mesh_ms": _last_mesh_ms,
		"generation_ms": _last_generation_ms,
		"pending": _dirty.size(),
	}


# --- Network (Net) --------------------------------------------------------------------

## Client: block changes from the host ([x, y, z, id] each); returns the
## ones for chunks not here (yet).
func apply_network_blocks(changes: PackedInt32Array) -> PackedInt32Array:
	var later := PackedInt32Array()
	_applying_network = true
	begin_batch()
	for i in range(0, changes.size() - 3, 4):
		var pos := Vector3i(changes[i], changes[i + 1], changes[i + 2])
		if _chunks.has(chunk_coord_of(pos)):
			set_block(pos, changes[i + 3], false)
		else:
			later.append_array(changes.slice(i, i + 4))
	end_batch()
	_applying_network = false
	return later


## Host: a column's blocks for a client, or empty when it is as generated
## (the client makes it itself).
func column_blocks_for_network(column: Vector2i) -> PackedInt32Array:
	var saved := save != null and not save.remote
	if saved:
		_finish_save(column)
	if _columns.has(column) and (_modified.has(column) or (saved and save.has_column(column))):
		var blocks := PackedInt32Array()
		for chunk: ChunkData in _columns[column]:
			blocks.append_array(chunk.blocks)
		return blocks
	if saved and save.has_column(column):
		var blocks := save.load_column(column)
		if blocks.size() == WorldGenerator.LEGACY_VOLUME:
			blocks = world_generator.convert_legacy(column.x, column.y, blocks)
		return blocks if blocks.size() == WorldGenerator.COLUMN_VOLUME else PackedInt32Array()
	return PackedInt32Array()
