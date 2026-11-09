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
## The active world generator.
var world_generator: WorldGenerator
## keepInventory game rule: the player keeps the items on death.
var keep_inventory := false
## naturalRegeneration game rule: full food heals the player.
var natural_regeneration := true
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
var _cull_dirty := true
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
	var center: PackedByteArray
	var neighbors := {}
	var center_light: PackedByteArray
	var neighbor_light := {}
	## Grass / foliage colors of the column (WorldGenerator.column_colors).
	var colors: Array = [PackedColorArray(), PackedColorArray()]
	var surfaces := {}
	## Face connectivity for cave culling (ChunkMesher.connectivity).
	var connectivity := ChunkMesher.ALL_CONNECTED
	var mesh_ms := 0.0
	var task_id := -1

	func run() -> void:
		var start_us := Time.get_ticks_usec()
		var padded := ChunkMesher.pad(center, neighbors)
		surfaces = ChunkMesher.build(padded, ChunkMesher.pad(center_light, neighbor_light, SkyLight.MAX),
			colors[0], colors[1])
		connectivity = ChunkMesher.connectivity(padded)
		mesh_ms = (Time.get_ticks_usec() - start_us) / 1000.0


## Sky light of a column, computed on a worker thread from the 3x3 columns
## around it.
class LightJob:
	var column: Vector2i
	var chunks := []   # 9 arrays of 8 block arrays
	var heights := []  # 9 heightmaps
	var light: Array[PackedByteArray] = []
	var task_id := -1

	func run() -> void:
		light = SkyLight.compute_column(chunks, heights)


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
		var blocks := PackedByteArray()
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


func _process(delta: float) -> void:
	_update_streaming()
	_finish_generation_jobs()
	_start_generation_jobs()
	_finish_light_jobs()
	_start_light_jobs()
	_finish_mesh_jobs()
	_start_mesh_jobs()
	_update_culling(delta)


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
		_lit[column] = true
		_mesh_scan_needed = true


func _in_load_radius(column: Vector2i) -> bool:
	var radius := render_distance + 1
	return absi(column.x - _player_column.x) <= radius and absi(column.y - _player_column.y) <= radius


static var _solid_chunk_cache := PackedByteArray()
static var _solid_heights_cache := PackedInt32Array()


static func _solid_chunk() -> PackedByteArray:
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
	var coord := chunk_coord_of(pos)
	var data: ChunkData = _chunks.get(coord)
	if data == null:
		return 0
	var local := pos - coord * ChunkData.SIZE
	return data.light[ChunkData.index(local.x, local.y, local.z)]


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
	return Vector3i(
		floori(pos.x / float(ChunkData.SIZE)),
		floori(pos.y / float(ChunkData.SIZE)),
		floori(pos.z / float(ChunkData.SIZE)))


func is_inside(pos: Vector3i) -> bool:
	return _chunks.has(chunk_coord_of(pos))


## Block at a world position; AIR where no chunk is loaded.
func get_block(pos: Vector3i) -> int:
	var coord := chunk_coord_of(pos)
	var data: ChunkData = _chunks.get(coord)
	if data == null:
		return Blocks.AIR
	var local := pos - coord * ChunkData.SIZE
	return data.get_block(local.x, local.y, local.z)


## Biome name at a block column (debug screen).
func biome_at(x: int, z: int) -> String:
	return world_generator.biome_name(x, z) if world_generator else ""


## First block hit by a ray (voxel traversal, Amanatides & Woo).
## Air and water are passed through. Returns {hit: bool, pos: Vector3i,
## normal: Vector3i (face that was hit, ZERO if the ray starts inside),
## block: int, distance: float}.
func raycast(origin: Vector3, direction: Vector3, max_distance: float) -> Dictionary:
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
		if id != Blocks.AIR and id != _water:
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
	_modified[Vector2i(coord.x, coord.z)] = true
	_mark_dirty_around(coord, local)
	_update_heightmap(pos, id)
	if _lit.has(Vector2i(coord.x, coord.z)):
		_relight(pos)
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


func _tick(_tick_index: int) -> void:
	clock.tick()
	_run_scheduled_ticks()
	_run_random_ticks()


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


func _run_random_ticks() -> void:
	var ticks_randomly := Blocks.ticks_randomly
	for coord: Vector3i in _chunks:
		var data: ChunkData = _chunks[coord]
		if data.tickable_count == 0:
			continue
		var origin: Vector3i = coord * ChunkData.SIZE
		for i in random_tick_speed:
			var index := rng.randi_range(0, ChunkData.VOLUME - 1)
			var id: int = data.blocks[index]
			if ticks_randomly[id] == 0:
				continue
			var local := Vector3i(
				index % ChunkData.SIZE,
				index / (ChunkData.SIZE * ChunkData.SIZE),
				(index / ChunkData.SIZE) % ChunkData.SIZE)
			Blocks.get_type(id).random_tick.call(self, origin + local)


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
		job.colors = _column_colors.get(Vector2i(coord.x, coord.z), job.colors)
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					var offset := Vector3i(dx, dy, dz)
					if offset != Vector3i.ZERO:
						var neighbor: ChunkData = _chunks.get(coord + offset)
						if open_edges and not _in_render_radius(Vector2i(coord.x + dx, coord.z + dz)):
							neighbor = null # beyond the edge counts as air: solid side walls
						job.neighbors[offset] = neighbor.blocks if neighbor else PackedByteArray()
						job.neighbor_light[offset] = neighbor.light if neighbor else PackedByteArray()
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


func _finish_mesh_jobs() -> void:
	# Finished meshes uploaded per frame (main-thread work): Chunk Updates.
	var max_uploads: int = Settings.CHUNK_UPDATE_CHOICES[Settings.get_value("chunk_updates")]
	var uploads := 0
	for coord: Vector3i in _mesh_jobs.keys():
		if uploads >= max_uploads:
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
	var faces := 0
	var mesh: ArrayMesh = null
	if not job.surfaces.is_empty():
		mesh = ChunkMesher.to_mesh(job.surfaces)
		for arrays: Array in job.surfaces.values():
			faces += arrays[Mesh.ARRAY_VERTEX].size() / 4
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

	var reached := {camera_chunk: true}
	var queue := []
	for face in 6:
		queue.append([camera_chunk + FACE_DIRECTIONS[face], face ^ 1, 1 << face])
	var head := 0
	while head < queue.size():
		var entry: Array = queue[head]
		head += 1
		var coord: Vector3i = entry[0]
		if reached.has(coord) or coord.y < 0 or coord.y >= WorldGenerator.HEIGHT_CHUNKS \
				or absi(coord.x - _player_column.x) > render_distance or absi(coord.z - _player_column.y) > render_distance:
			continue
		reached[coord] = true
		var entered: int = entry[1]
		var directions: int = entry[2]
		var connections: int = _connectivity.get(coord, ChunkMesher.ALL_CONNECTED)
		for face in 6:
			if directions & (1 << (face ^ 1)):
				continue # never back toward the camera
			if (connections >> (entered * 6 + face)) & 1 == 0:
				continue # no way through this chunk to that face
			queue.append([coord + FACE_DIRECTIONS[face], face ^ 1, directions | (1 << face)])

	culled_chunks = 0
	for coord: Vector3i in _chunk_nodes:
		var visible := reached.has(coord)
		(_chunk_nodes[coord] as Node3D).visible = visible
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
	var blocks := PackedByteArray()
	for k in WorldGenerator.HEIGHT_CHUNKS:
		blocks.append_array((_chunks[Vector3i(column.x, k, column.y)] as ChunkData).blocks)
	save.save_column(column, blocks)


## World state for the save: time and game rules.
func save_state() -> Dictionary:
	var rules := {}
	for rule_name in GameRules.names():
		rules[rule_name] = GameRules.rules[rule_name].get.call(self)
	return {"game_time": clock.game_time, "day_time": clock.day_time, "rules": rules}


func _restore_state() -> void:
	var world_state: Dictionary = save.state.get("world", {}) if save else {}
	if world_state.is_empty():
		return
	clock.game_time = world_state.get("game_time", 0)
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
