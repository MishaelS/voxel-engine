class_name VoxelWorld
extends Node3D
## An endless world of 16^3 chunks, 128 blocks high (columns of 8 chunks),
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
## The active world generator.
var world_generator: WorldGenerator
## keepInventory game rule: the player keeps the items on death.
var keep_inventory := false
## naturalRegeneration game rule: full food heals the player.
var natural_regeneration := true
## doHunger game rule: hunger like Beta 1.8 (on), or like Beta 1.7.3 (off):
## no food bar, food is eaten at once and heals right away.
var hunger := true
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

var _chunks := {}          # Vector3i -> ChunkData
var _columns := {}         # Vector2i -> true: generated columns
var _heightmaps := {}      # Vector2i -> PackedInt32Array (see WorldGenerator.heightmap)
var _lit := {}             # Vector2i -> true: columns with sky light
var _light_jobs := {}      # Vector2i -> LightJob on a worker thread
var _chunk_nodes := {}     # Vector3i -> MeshInstance3D
var _chunk_faces := {}     # Vector3i -> visible faces
var _dirty := {}           # Vector3i -> true: chunks waiting for a new mesh
var _mesh_jobs := {}       # Vector3i -> MeshJob on a worker thread
var _gen_jobs := {}        # Vector2i -> GenerationJob on a worker thread
var _scheduled := {}       # game_time -> {Vector3i: true}
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
## Worker jobs of each kind (generation, light, meshing) at a time; leaves
## two cores for the main and render threads.
var _max_jobs := maxi(OS.get_processor_count() - 2, 1)
## While the loading screen waits for the columns within this radius of the
## player (-1 = not loading), their chunks are meshed before all others.
var loading_radius := -1:
	set(value):
		loading_radius = value
		_mesh_scan_needed = true
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

	func run() -> void:
		var start_us := Time.get_ticks_usec()
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
	var chunks := []   # 9 arrays of 8 block arrays
	var heights := []  # 9 heightmaps
	var light: Array[PackedByteArray] = []
	var block_light: Array[PackedByteArray] = []
	var task_id := -1

	func run() -> void:
		var area := SkyLight.area_of(chunks)
		light = SkyLight.compute_column(area, heights)
		block_light = BlockLight.compute_column(area)


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

	func run() -> void:
		var start_us := Time.get_ticks_usec()
		var blocks := PackedInt32Array()
		if save and save.has_column(column):
			blocks = save.load_column(column) # generated or changed before: saved
		if blocks.is_empty():
			blocks = generator.generate_blocks(column.x, column.y)
			if save:
				# Kept on disk: next time the world loads it is read, not generated.
				save.save_column(column, blocks)
		heights = WorldGenerator.heightmap(blocks)
		chunks = WorldGenerator.split_column(blocks)
		colors = generator.column_colors(column.x, column.y)
		generation_ms = (Time.get_ticks_usec() - start_us) / 1000.0


func _ready() -> void:
	save = WorldSave.current
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
	_update_streaming()
	var t1 := Time.get_ticks_usec()
	_finish_generation_jobs()
	_start_generation_jobs()
	var t2 := Time.get_ticks_usec()
	_finish_light_jobs()
	_start_light_jobs()
	var t3 := Time.get_ticks_usec()
	_finish_mesh_jobs()
	_start_mesh_jobs()
	var t4 := Time.get_ticks_usec()
	_update_culling(delta)
	var t5 := Time.get_ticks_usec()
	frame_times = {"stream": t1 - t0, "generation": t2 - t1, "light": t3 - t2, "mesh": t4 - t3, "cull": t5 - t4}


# --- World lifecycle ---------------------------------------------------------------

## Starts a new world with the current generator and seed: drops everything,
## generates the spawn column right away and puts the player on the ground.
func generate() -> void:
	_wait_for_jobs()
	for node: Node in _chunk_nodes.values():
		node.queue_free()
	_chunks.clear()
	_columns.clear()
	_heightmaps.clear()
	_column_colors.clear()
	_lit.clear()
	_chunk_nodes.clear()
	_chunk_faces.clear()
	_dirty.clear()
	_total_faces = 0
	_player_column = Vector2i(2147483647, 0)
	rng.seed = world_seed
	clock = WorldClock.new(start_day_time)
	falling_blocks.clear()
	items.clear()
	entities.clear()
	sign_texts.clear()
	_block_entities.clear()
	_scheduled.clear()
	_scheduled_count = 0
	_modified.clear()
	_connectivity.clear()
	_cull_dirty = true
	_restore_state()
	match generator:
		Generator.BETA:
			world_generator = BetaGenerator.new(world_seed)
		Generator.RANDOM_BLOCKS:
			world_generator = RandomBlocksGenerator.new(world_seed, random_density)

	if player:
		var player_state: Dictionary = save.state.get("player", {}) if save else {}
		if player_state.has("position"):
			# Back where the player left: that column is needed right away.
			var position: Vector3 = player_state.position
			_generate_now(Vector2i(floori(position.x / ChunkData.SIZE), floori(position.z / ChunkData.SIZE)))
			player.global_position = position
		else:
			player.global_position = find_spawn()


## Like the classic game, spawn on land: search columns in a spiral from the
## origin (generating them right away; they stay loaded) for a block column
## whose top is a solid block, not water. Falls back to the origin.
const SPAWN_SEARCH_RADIUS := 6

func find_spawn() -> Vector3:
	if generator == Generator.RANDOM_BLOCKS:
		_generate_now(Vector2i.ZERO)
		return Vector3(24, 20, 24)
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
					if top >= WorldGenerator.SEA_LEVEL - 1 and get_block(Vector3i(x, top, z)) != _water:
						return Vector3(x + 0.5, top + 1.0, z + 0.5) # feet on the block
	return Vector3(8.5, WorldGenerator.SEA_LEVEL + 1.0, 8.5)


func _generate_now(column: Vector2i) -> void:
	if _columns.has(column):
		return
	var job := GenerationJob.new()
	job.column = column
	job.generator = world_generator
	job.save = save
	job.run()
	_add_column(job)


func _top_block_y(x: int, z: int) -> int:
	for y in range(WorldGenerator.HEIGHT - 1, 0, -1):
		if get_block(Vector3i(x, y, z)) != Blocks.AIR:
			return y
	return -1


## Rebuilds the meshes of all chunks in the background.
func remesh_all() -> void:
	for coord: Vector3i in _chunks:
		_dirty[coord] = true
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


# --- Streaming -----------------------------------------------------------------------

func _player_column_now() -> Vector2i:
	var position := player.global_position if player else Vector3.ZERO
	return Vector2i(floori(position.x / ChunkData.SIZE), floori(position.z / ChunkData.SIZE))


## When the player enters another column: list columns to generate (nearest
## first) and unload the ones that are too far.
func _update_streaming() -> void:
	var center := _player_column_now()
	if center == _player_column:
		return
	_player_column = center
	_mesh_scan_needed = true
	_light_scan_needed = true
	var radius := render_distance + 1
	_wanted_columns.clear()
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			var column := center + Vector2i(dx, dz)
			if not _columns.has(column):
				_wanted_columns.append(column)
	_wanted_columns.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - center).length_squared() > (b - center).length_squared()) # nearest at the end

	var unload_radius := render_distance + 4
	for column: Vector2i in _columns.keys():
		if absi(column.x - center.x) > unload_radius or absi(column.y - center.y) > unload_radius:
			_unload_column(column)


func _start_generation_jobs() -> void:
	while _gen_jobs.size() < _max_jobs and not _wanted_columns.is_empty():
		var column: Vector2i = _wanted_columns.pop_back()
		if _columns.has(column) or _gen_jobs.has(column):
			continue
		var job := GenerationJob.new()
		job.column = column
		job.generator = world_generator
		job.save = save
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
	_columns[job.column] = true
	_heightmaps[job.column] = job.heights
	_column_colors[job.column] = job.colors
	_light_scan_needed = true
	_last_generation_ms = job.generation_ms
	for k in job.chunks.size():
		var coord := Vector3i(job.column.x, k, job.column.y)
		_chunks[coord] = job.chunks[k]
		_dirty[coord] = true
	_mesh_scan_needed = true


func _unload_column(column: Vector2i) -> void:
	if _modified.has(column):
		_save_column(column)
	_columns.erase(column)
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
	if not _light_scan_needed or _light_jobs.size() >= _max_jobs:
		return
	var candidates: Array[Vector2i] = []
	for column: Vector2i in _columns:
		if _lit.has(column) or _light_jobs.has(column):
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
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - _player_column).length_squared() < (b - _player_column).length_squared())
	for column in candidates:
		if _light_jobs.size() >= _max_jobs:
			break
		var job := LightJob.new()
		job.column = column
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var neighbor := column + Vector2i(dx, dz)
				var blocks := []
				if _columns.has(neighbor):
					for k in WorldGenerator.HEIGHT_CHUNKS:
						blocks.append((_chunks[Vector3i(neighbor.x, k, neighbor.y)] as ChunkData).blocks)
					job.heights.append(_heightmaps[neighbor])
				else: # beyond the loaded area: solid, lets no light through
					for k in WorldGenerator.HEIGHT_CHUNKS:
						blocks.append(_solid_chunk())
					job.heights.append(_solid_heights())
				job.chunks.append(blocks)
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
		_lit[column] = true
		_mesh_scan_needed = true


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
		data.light[i] = level
		_mark_dirty_around(coord, local)


## Re-lights around a changed block, like the classic game: first remove the
## light that depended on the old block (flood out from it, re-queueing
## brighter cells found at the edge), then spread light again from those
## cells and from the changed cell itself. Straight-down sky light (15)
## keeps its full value through clear blocks.
func _relight(pos: Vector3i) -> void:
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

	head = 0
	while head < spread.size():
		var cell := spread[head]
		head += 1
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
				spread.append(neighbor)


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
	var cell := Vector3i(point.floor())
	var atmosphere := Atmosphere.find(get_tree())
	var darkness := atmosphere.sky_darkness if atmosphere else 0.0
	var sky := ChunkMesher.LIGHT_BRIGHTNESS[clampi(roundi(get_light(cell) - darkness), 0, SkyLight.MAX)]
	if atmosphere and atmosphere.sky_darkness <= 0.0:
		sky *= 0.25 + 0.75 * atmosphere.daylight
	return maxf(sky, ChunkMesher.LIGHT_BRIGHTNESS[get_block_light(cell)])


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
		data.block_light[i] = level
		_mark_dirty_around(coord, local)


## Re-lights block light around a changed block: removes the light that
## came through or from the old block (flooding out, re-queueing brighter
## cells found at the edge), then spreads again from those cells and from
## the block itself if it glows.
func _relight_block_light(pos: Vector3i) -> void:
	var removal: Array = [[pos, get_block_light(pos)]]
	var spread: Array[Vector3i] = []
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
	head = 0
	while head < spread.size():
		var cell := spread[head]
		head += 1
		var level := get_block_light(cell)
		if level <= 1:
			continue
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
				spread.append(neighbor)


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
			return {"hit": true, "pos": pos, "normal": normal, "block": id, "distance": distance}
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


## Changes a block, sends block updates to it and its neighbors and marks
## for re-meshing its chunk and the neighbor chunks that see it (their
## border faces and AO). Ignored where no chunk is loaded.
func set_block(pos: Vector3i, id: int, notify: bool = true) -> void:
	var coord := chunk_coord_of(pos)
	var data: ChunkData = _chunks.get(coord)
	if data == null:
		return
	var local := pos - coord * ChunkData.SIZE
	if data.get_block(local.x, local.y, local.z) == id:
		return
	data.set_block(local.x, local.y, local.z, id)
	if _block_entities.has(pos) and _block_entities[pos].type != _entity_type(id):
		if _block_entities[pos].type == "sign":
			sign_texts.remove(pos)
		_block_entities.erase(pos) # the chest / furnace / sign is gone
	_modified[Vector2i(coord.x, coord.z)] = true
	_mark_dirty_around(coord, local)
	_update_heightmap(pos, id)
	if _lit.has(Vector2i(coord.x, coord.z)):
		_relight(pos)
		_relight_block_light(pos)
	if notify:
		_update_block(pos)
		for offset in NEIGHBORS:
			_update_block(pos + offset)


func _mark_dirty_around(coord: Vector3i, local: Vector3i) -> void:
	var ranges := []
	for axis in 3:
		var low := -1 if local[axis] == 0 else 0
		var high := 1 if local[axis] == ChunkData.SIZE - 1 else 0
		ranges.append([low, high])
	for dx in range(ranges[0][0], ranges[0][1] + 1):
		for dy in range(ranges[1][0], ranges[1][1] + 1):
			for dz in range(ranges[2][0], ranges[2][1] + 1):
				var neighbor := coord + Vector3i(dx, dy, dz)
				if _chunks.has(neighbor):
					_dirty[neighbor] = true
	_mesh_scan_needed = true


## Sends a "block update" to the block at pos (its on_update handler).
func _update_block(pos: Vector3i) -> void:
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
	if Blocks.family_of(id) == "dungeon_chest":
		DungeonBehavior.open_chest(self, pos) # its loot spills out
	if Blocks.family_of(id) == "jukebox":
		MusicBehavior.eject(self, pos) # the disc pops out
	if Blocks.family_of(id) == "piston_head":
		PistonBehavior.head_broken(self, pos, id) # the piston goes with it
	if effects:
		particles.break_block(pos, id)
		Sounds.play_block("break", id, Vector3(pos) + Vector3(0.5, 0.5, 0.5))
	if drop:
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
		if entity.type != "furnace" or not is_inside(pos):
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
	var t0 := Time.get_ticks_usec()
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
	_mood_tick()
	var t5 := Time.get_ticks_usec()
	tick_times = {"weather": t1 - t0, "scheduled": t2 - t1, "random": t3 - t2, "block_entities": t4 - t3, "display": t5 - t4}


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


func _run_scheduled_ticks() -> void:
	var now := clock.game_time
	if not _scheduled.has(now):
		return
	var bucket: Dictionary = _scheduled[now]
	_scheduled.erase(now)
	var processed := 0
	for pos: Vector3i in bucket:
		if processed >= MAX_SCHEDULED_TICKS_PER_TICK:
			schedule_tick(pos, 1) # over the limit: wait for the next tick
			continue
		processed += 1
		_scheduled_count -= 1
		var handler := Blocks.get_type(get_block(pos)).scheduled_tick
		if handler.is_valid():
			handler.call(self, pos)


## Random ticks reach this many columns around the player, like the game's
## (9 chunks there; the rest of the loaded world just waits).
const RANDOM_TICK_RADIUS := 8
## Main-thread time random ticks may take per tick; what's left over goes on
## next tick from where it stopped, so a tick never stalls a frame.
const RANDOM_TICK_BUDGET_US := 4000

var _random_tick_queue: Array[Vector3i] = []


func _run_random_ticks() -> void:
	if player == null or random_tick_speed <= 0:
		return
	if _random_tick_queue.is_empty():
		# A new round: the chunks with something that ticks, near the player.
		var center := Vector2i(floori(player.global_position.x) >> 4, floori(player.global_position.z) >> 4)
		for cx in range(center.x - RANDOM_TICK_RADIUS, center.x + RANDOM_TICK_RADIUS + 1):
			for cz in range(center.y - RANDOM_TICK_RADIUS, center.y + RANDOM_TICK_RADIUS + 1):
				if not _columns.has(Vector2i(cx, cz)):
					continue
				for cy in WorldGenerator.HEIGHT_CHUNKS:
					var coord := Vector3i(cx, cy, cz)
					var data: ChunkData = _chunks.get(coord)
					if data and data.tickable_count > 0:
						_random_tick_queue.append(coord)
	var ticks_randomly := Blocks.ticks_randomly
	var started := Time.get_ticks_usec()
	while not _random_tick_queue.is_empty():
		var coord: Vector3i = _random_tick_queue.pop_back()
		var data: ChunkData = _chunks.get(coord)
		if data == null:
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


# --- Meshing -----------------------------------------------------------------------------

func _start_mesh_jobs() -> void:
	var free_slots := _max_jobs - _mesh_jobs.size()
	if free_slots <= 0:
		return
	if _mesh_scan_needed:
		_mesh_scan_needed = false
		_rebuild_mesh_queue()
	var picked: Array[Vector3i] = []
	while picked.size() < free_slots and not _mesh_queue.is_empty():
		var coord: Vector3i = _mesh_queue.pop_back()
		if _dirty.has(coord) and not _mesh_jobs.has(coord) and _chunks.has(coord):
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
func _rebuild_mesh_queue() -> void:
	_mesh_queue.clear()
	var center := Vector3(_player_column.x, (player.global_position.y if player else 64.0) / ChunkData.SIZE, _player_column.y)
	var meshable_columns := {} # Vector2i -> bool, checked once per column
	var view: Vector3 = player.look_direction() if player and player.has_method("look_direction") else Vector3.ZERO
	var keys := PackedInt64Array()
	var coords: Array[Vector3i] = []
	for coord: Vector3i in _dirty:
		if _mesh_jobs.has(coord):
			continue
		var column := Vector2i(coord.x, coord.z)
		var meshable: Variant = meshable_columns.get(column)
		if meshable == null:
			meshable = _can_mesh(coord)
			meshable_columns[column] = meshable
		if not meshable:
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
			_mesh_scan_needed = true # changed again while it was being meshed
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
		return
	if instance == null:
		instance = MeshInstance3D.new()
		instance.position = Vector3(job.coord * ChunkData.SIZE)
		add_child(instance)
		_chunk_nodes[job.coord] = instance
	instance.mesh = mesh


# --- Edges (isometric screenshots) -----------------------------------------------

func _in_render_radius(column: Vector2i) -> bool:
	return absi(column.x - _player_column.x) <= render_distance and absi(column.y - _player_column.y) <= render_distance


## Columns on the edge of the drawn area.
func _edge_columns() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dx in range(-render_distance, render_distance + 1):
		for dz in range(-render_distance, render_distance + 1):
			if maxi(absi(dx), absi(dz)) == render_distance:
				result.append(_player_column + Vector2i(dx, dz))
	return result


## Re-meshes the edge columns with (or without) solid side walls.
func set_open_edges(open: bool) -> void:
	open_edges = open
	for column in _edge_columns():
		for k in WorldGenerator.HEIGHT_CHUNKS:
			var coord := Vector3i(column.x, k, column.y)
			if _chunks.has(coord):
				_dirty[coord] = true
	_mesh_scan_needed = true


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
		_apply_culling(_cull_job.reached)
	if not _cull_dirty or _cull_timer > 0.0:
		return
	_cull_dirty = false
	_cull_timer = CULL_INTERVAL
	if not culling_enabled or not Settings.get_value("cave_culling") or camera_chunk.y < 0 \
			or camera_chunk.y >= WorldGenerator.HEIGHT_CHUNKS or not _chunks.has(camera_chunk):
		for node: Node3D in _chunk_nodes.values():
			node.visible = true
		culled_chunks = 0
		return
	_cull_job = {"connectivity": _connectivity.duplicate(), "camera": camera_chunk, "column": _player_column,
		"distance": render_distance, "reached": {}}
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


## Shows the reached chunks and hides the rest (only those that change).
func _apply_culling(reached: Dictionary) -> void:
	culled_chunks = 0
	for coord: Vector3i in _chunk_nodes:
		var visible := reached.has(coord)
		var node: Node3D = _chunk_nodes[coord]
		if node.visible != visible:
			node.visible = visible
		if not visible:
			culled_chunks += 1


# --- Saving --------------------------------------------------------------------------

## Writes every changed loaded column to the save (columns unloaded earlier
## were written when they unloaded).
func save_columns() -> void:
	if save == null:
		return
	for column: Vector2i in _modified.keys():
		if _columns.has(column):
			_save_column(column)
	_modified.clear()


func _save_column(column: Vector2i) -> void:
	_modified.erase(column)
	if save == null:
		return
	var blocks := PackedInt32Array()
	for k in WorldGenerator.HEIGHT_CHUNKS:
		blocks.append_array((_chunks[Vector3i(column.x, k, column.y)] as ChunkData).blocks)
	save.save_column(column, blocks)


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
		"maps": maps, "next_map_id": next_map_id, "weather": weather.save_state(), "stats": Stats.save_state()}


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
	clock.day_time = world_state.get("day_time", start_day_time)
	var rules: Dictionary = world_state.get("rules", {})
	for rule_name: String in rules:
		if GameRules.rules.has(rule_name):
			GameRules.rules[rule_name].set.call(self, rules[rule_name])


## Loading state of each column within `radius` of the player, row by row
## (dz outer, dx inner): [state, surface height] with state 0 = not
## generated, 1 = generated, 2 = lit, 3 = meshed; height = the surface in
## the column's middle (-1 if not generated). Used by the loading screen.
func column_states(radius: int) -> Array:
	var center := _player_column_now()
	var result := []
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var column := center + Vector2i(dx, dz)
			var state := 0
			var height := -1
			if maxi(absi(dx), absi(dz)) > render_distance:
				# Never meshed (beyond the render distance): counts as done.
				var heights: Variant = _heightmaps.get(column)
				result.append([3, (heights as PackedInt32Array)[8 + 16 * 8] if heights else 64])
				continue
			if _columns.has(column):
				state = 1
				height = (_heightmaps[column] as PackedInt32Array)[8 + 16 * 8]
				if _lit.has(column):
					state = 2
					var done := true
					for k in WorldGenerator.HEIGHT_CHUNKS:
						var coord := Vector3i(column.x, k, column.y)
						if _dirty.has(coord) or _mesh_jobs.has(coord):
							done = false
							break
					if done:
						state = 3
			result.append([state, height])
	return result


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
