class_name VoxelWorld
extends Node3D
## A world: chunks of blocks, its clock and everything that happens in ticks.
## For now a single chunk at the origin.
##
## Every game tick (TickLoop, Phase.WORLD), in this order:
## 1. the clock advances (game_time, day_time);
## 2. scheduled block ticks that are due run (falling sand, ...);
## 3. random ticks: random_tick_speed random blocks per chunk get a random
##    tick if their type has one (grass spreading, ...).
## Changing a block (set_block) sends a "block update" to it and its 6
## neighbors and marks the chunk for re-meshing. Meshes are rebuilt on
## worker threads and swapped in when ready, so block changes never stall
## the frame.
##
## R regenerates the world with a new seed.

enum Generator {
	TERRAIN,       ## Heightmap terrain.
	RANDOM_BLOCKS, ## Debug: every block type scattered randomly.
}

const NEIGHBORS: Array[Vector3i] = [
	Vector3i.UP, Vector3i.DOWN, Vector3i.RIGHT, Vector3i.LEFT, Vector3i.BACK, Vector3i.FORWARD,
]
## Like the classic game: scheduled ticks beyond this per game tick wait.
const MAX_SCHEDULED_TICKS_PER_TICK := 65536

@export var generator: Generator = Generator.TERRAIN
@export var world_seed: int = 1337
## Share of non-floor cells filled in RANDOM_BLOCKS mode.
@export_range(0.0, 1.0) var random_density: float = 0.3

@export_group("Ticks")
## Random ticks per chunk per game tick (randomTickSpeed, 3 by default).
@export_range(0, 4096) var random_tick_speed: int = 3
## Time of day of a new world in ticks (0 = 06:00, 3333 ~ 09:20).
@export var start_day_time: float = 3333.0

## Filled after meshing; read by the HUD.
var stats := {}
var clock := WorldClock.new()
## Random source for world logic (random ticks, block behaviors).
var rng := RandomNumberGenerator.new()
## Falling block entities in this world.
var falling_blocks: FallingBlocks

var _chunks := {}          # Vector3i -> ChunkData
var _chunk_nodes := {}     # Vector3i -> MeshInstance3D
var _dirty := {}           # Vector3i -> true: chunks waiting for a new mesh
var _mesh_jobs := {}       # Vector3i -> MeshJob running on a worker thread
var _scheduled := {}       # game_time -> {Vector3i: true}
var _scheduled_count := 0
var _water := -1


## A chunk mesh being built on a worker thread. The worker only writes
## `surfaces`/`mesh_ms`; the main thread reads them after the task finished.
class MeshJob:
	var coord: Vector3i
	var data: ChunkData
	var surfaces := {}
	var mesh_ms := 0.0
	var task_id := -1

	func run() -> void:
		var start_us := Time.get_ticks_usec()
		surfaces = ChunkMesher.build(data)
		mesh_ms = (Time.get_ticks_usec() - start_us) / 1000.0


func _ready() -> void:
	falling_blocks = FallingBlocks.new()
	falling_blocks.name = "FallingBlocks"
	falling_blocks.world = self
	add_child(falling_blocks)
	generate()
	TickLoop.add_listener(_tick, TickLoop.Phase.WORLD)


func _exit_tree() -> void:
	TickLoop.remove_listener(_tick)
	for job: MeshJob in _mesh_jobs.values():
		WorkerThreadPool.wait_for_task_completion(job.task_id)
	_mesh_jobs.clear()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("regenerate_world"):
		world_seed = randi()
		generate()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	_finish_mesh_jobs()
	_start_mesh_jobs()


# --- World generation ------------------------------------------------------

func generate() -> void:
	rng.seed = world_seed
	clock = WorldClock.new(start_day_time)
	falling_blocks.clear()
	_scheduled.clear()
	_scheduled_count = 0
	var data := ChunkData.new()
	match generator:
		Generator.TERRAIN:
			TerrainGenerator.new(world_seed).fill(data, Vector3i.ZERO)
		Generator.RANDOM_BLOCKS:
			RandomBlocksGenerator.new(world_seed, random_density).fill(data, Vector3i.ZERO)
	add_chunk(Vector3i.ZERO, data)


## Adds or replaces a chunk and builds its mesh right away (synchronously).
func add_chunk(coord: Vector3i, data: ChunkData) -> void:
	_chunks[coord] = data
	_dirty.erase(coord)
	var job := MeshJob.new()
	job.coord = coord
	job.data = data
	job.run()
	_apply_mesh(job)


## Rebuilds the meshes of all chunks in the background.
func remesh_all() -> void:
	for coord: Vector3i in _chunks:
		_dirty[coord] = true


# --- Blocks ----------------------------------------------------------------

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


## First block hit by a ray (voxel traversal, Amanatides & Woo).
## Air and water are passed through. Returns {hit: bool, pos: Vector3i,
## normal: Vector3i (face that was hit, ZERO if the ray starts inside),
## block: int, distance: float}.
func raycast(origin: Vector3, direction: Vector3, max_distance: float) -> Dictionary:
	if _water < 0:
		_water = Blocks.id_of("water")
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
## the chunk for re-meshing. Ignored where no chunk is loaded.
func set_block(pos: Vector3i, id: int, notify: bool = true) -> void:
	var coord := chunk_coord_of(pos)
	var data: ChunkData = _chunks.get(coord)
	if data == null:
		return
	var local := pos - coord * ChunkData.SIZE
	if data.get_block(local.x, local.y, local.z) == id:
		return
	data.set_block(local.x, local.y, local.z, id)
	_dirty[coord] = true
	# TODO: also mark neighbor chunks dirty for blocks on a chunk border
	# (their faces and AO depend on this block) once there are many chunks.
	if notify:
		_update_block(pos)
		for offset in NEIGHBORS:
			_update_block(pos + offset)


## Sends a "block update" to the block at pos (its on_update handler).
func _update_block(pos: Vector3i) -> void:
	var handler := Blocks.get_type(get_block(pos)).on_update
	if handler.is_valid():
		handler.call(self, pos)


# --- Ticks -----------------------------------------------------------------

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


## Turns the block at `pos` into a falling entity (sand, gravel).
func start_falling(pos: Vector3i) -> void:
	var id := get_block(pos)
	if id == Blocks.AIR:
		return
	set_block(pos, Blocks.AIR) # updates neighbors: blocks above start falling too
	falling_blocks.spawn(pos, id)


func mesh_jobs_count() -> int:
	return _mesh_jobs.size()


func scheduled_tick_count() -> int:
	return _scheduled_count


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


# --- Meshing ---------------------------------------------------------------

func _start_mesh_jobs() -> void:
	for coord: Vector3i in _dirty.keys():
		if _mesh_jobs.has(coord):
			continue # rebuilt again after the running job finishes
		_dirty.erase(coord)
		var job := MeshJob.new()
		job.coord = coord
		job.data = (_chunks[coord] as ChunkData).copy() # snapshot for the worker
		job.task_id = WorkerThreadPool.add_task(job.run, false, "Chunk mesh")
		_mesh_jobs[coord] = job


func _finish_mesh_jobs() -> void:
	for coord: Vector3i in _mesh_jobs.keys():
		var job: MeshJob = _mesh_jobs[coord]
		if not WorkerThreadPool.is_task_completed(job.task_id):
			continue
		WorkerThreadPool.wait_for_task_completion(job.task_id)
		_mesh_jobs.erase(coord)
		if _chunks.has(coord):
			_apply_mesh(job)


func _apply_mesh(job: MeshJob) -> void:
	var faces := 0
	var mesh := ArrayMesh.new()
	for layer: int in job.surfaces:
		var arrays: Array = job.surfaces[layer]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, BlockMaterials.get_material(layer))
		faces += arrays[Mesh.ARRAY_VERTEX].size() / 4

	var instance: MeshInstance3D = _chunk_nodes.get(job.coord)
	if instance == null:
		instance = MeshInstance3D.new()
		instance.name = "Chunk_%d_%d_%d" % [job.coord.x, job.coord.y, job.coord.z]
		instance.position = Vector3(job.coord * ChunkData.SIZE)
		add_child(instance)
		_chunk_nodes[job.coord] = instance
	instance.mesh = mesh if faces > 0 else null

	stats = {
		"generator": Generator.keys()[generator],
		"seed": world_seed,
		"chunks": _chunks.size(),
		"faces": faces,
		"faces_naive": job.data.count_solid() * 6, # what we'd draw without culling
		"triangles": faces * 2,
		"vertices": faces * 4,
		"mesh_ms": job.mesh_ms,
	}
