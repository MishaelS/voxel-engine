class_name TitlePanorama
extends Node3D
## Live background of the title screen, like the classic game's panorama:
## always the same place of the same world (a forest of seed TITLE_SEED),
## seen from just above the trees, the view slowly turning around on the
## spot under a calm evening sky with twinkling stars and 3D clouds.
##
## A 9 x 9 column piece around that place is generated, lit and meshed on
## worker threads when the title screen opens (the menu stays smooth), then
## fades in; its edges are hidden in fog the color of the horizon.

const TITLE_SEED := 1337
## Column at the middle of the view (a forest with some relief).
const TITLE_COLUMN := Vector2i(-4, 3)
const RADIUS := 4 ## columns around the middle: 9 x 9
const SIZE := RADIUS * 2 + 1
const CHUNKS := SIZE * SIZE * WorldGenerator.HEIGHT_CHUNKS
## Eye height above the ground in the middle (just above the treetops).
const EYE_ABOVE_GROUND := 11.0
const TURN_SECONDS := 160.0 ## one full turn
const PITCH_DEGREES := -6.0
const FADE_SECONDS := 1.5
const FOG_COLOR := Color(0.42, 0.36, 0.5)

enum Stage { GENERATE, LIGHT, MESH, DONE }

var camera: Camera3D

var _generator: WorldGenerator
var _stage := Stage.GENERATE
var _task := -1
var _chunk_blocks: Array = []   # [column * 8 + k] -> PackedByteArray
var _heights: Array = []        # [column] -> PackedInt32Array
var _colors: Array = []         # [column] -> [grass, foliage]
var _chunk_light: Array = []
var _surfaces: Array = []
var _instances: Array[MeshInstance3D] = []
var _fade := 0.0
var _angle := 0.0
var _eye := Vector3(72.0, 80.0, 72.0)


func _ready() -> void:
	ChunkMesher.random_rotation = Settings.get_value("random_rotation")
	_build_scene()
	_generator = BetaGenerator.new(TITLE_SEED)
	_chunk_blocks.resize(CHUNKS)
	_heights.resize(SIZE * SIZE)
	_colors.resize(SIZE * SIZE)
	_task = WorkerThreadPool.add_group_task(_generate_column, SIZE * SIZE, -1, false, "Title world")


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_task)


func _build_scene() -> void:
	# A calm evening sky (title_sky.gdshader), lit by a low warm light.
	var sky_material := ShaderMaterial.new()
	sky_material.shader = preload("res://shaders/title_sky.gdshader")
	var to_sun := Vector3(0.55, 0.32, -0.5).normalized()
	sky_material.set_shader_parameter("glow_direction", to_sun)
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 1.4
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# The piece ends RADIUS columns away: fog hides its edges.
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = FOG_COLOR
	environment.fog_depth_begin = RADIUS * 16.0 * 0.45
	environment.fog_depth_end = RADIUS * 16.0 * 0.95
	environment.fog_sky_affect = 0.0
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.look_at_from_position(Vector3.ZERO, -to_sun, Vector3.UP)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.8, 0.62)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)

	camera = Camera3D.new()
	camera.fov = 70.0
	camera.far = 400.0
	camera.current = true
	add_child(camera)
	_update_camera(0.0)

	add_child(WaterAnimation.new())
	var clouds := Clouds.new()
	clouds.camera = camera
	add_child(clouds)
	clouds.set_color(Color(0.62, 0.52, 0.62)) # evening clouds


func _process(delta: float) -> void:
	_update_camera(delta)
	if _task >= 0 and WorkerThreadPool.is_group_task_completed(_task):
		WorkerThreadPool.wait_for_group_task_completion(_task)
		_task = -1
		_next_stage()
	if _stage == Stage.DONE and _fade < 1.0:
		_fade = minf(_fade + delta / FADE_SECONDS, 1.0)
		for instance in _instances:
			instance.transparency = 1.0 - _fade


## Standing on the spot, slowly turning around.
func _update_camera(delta: float) -> void:
	_angle += TAU * delta / TURN_SECONDS
	camera.position = _eye
	camera.rotation = Vector3(deg_to_rad(PITCH_DEGREES), _angle, 0.0)


# --- Stages (worker threads) -------------------------------------------------------

func _next_stage() -> void:
	match _stage:
		Stage.GENERATE:
			var middle: PackedInt32Array = _heights[(SIZE * SIZE) / 2]
			_eye = Vector3(SIZE * 8.0, middle[8 + 16 * 8] + 1.0 + EYE_ABOVE_GROUND, SIZE * 8.0)
			_chunk_light.resize(CHUNKS)
			_stage = Stage.LIGHT
			_task = WorkerThreadPool.add_group_task(_light_column, SIZE * SIZE, -1, false, "Title light")
		Stage.LIGHT:
			_surfaces.resize(CHUNKS)
			_stage = Stage.MESH
			_task = WorkerThreadPool.add_group_task(_mesh_chunk, CHUNKS, -1, false, "Title meshes")
		Stage.MESH:
			_stage = Stage.DONE
			_show_meshes()


func _generate_column(index: int) -> void:
	var column := TITLE_COLUMN + Vector2i(index % SIZE - RADIUS, index / SIZE - RADIUS)
	var blocks := _generator.generate_blocks(column.x, column.y)
	_heights[index] = WorldGenerator.heightmap(blocks)
	_colors[index] = _generator.column_colors(column.x, column.y)
	for k in WorldGenerator.HEIGHT_CHUNKS:
		_chunk_blocks[index * 8 + k] = blocks.slice(k * ChunkData.VOLUME, (k + 1) * ChunkData.VOLUME)


## Light; beyond the piece counts as open air (only seen through fog).
func _light_column(index: int) -> void:
	var x := index % SIZE
	var z := index / SIZE
	var air := PackedByteArray()
	air.resize(ChunkData.VOLUME)
	var no_height := PackedInt32Array()
	no_height.resize(256)
	no_height.fill(-1)
	var chunks := []
	var heights := []
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var nx := x + dx
			var nz := z + dz
			var inside := nx >= 0 and nz >= 0 and nx < SIZE and nz < SIZE
			var column := []
			for k in WorldGenerator.HEIGHT_CHUNKS:
				column.append(_chunk_blocks[(nx + nz * SIZE) * 8 + k] if inside else air)
			chunks.append(column)
			heights.append(_heights[nx + nz * SIZE] if inside else no_height)
	var light := SkyLight.compute_column(chunks, heights)
	for k in WorldGenerator.HEIGHT_CHUNKS:
		_chunk_light[index * 8 + k] = light[k]


func _mesh_chunk(index: int) -> void:
	var column := index / 8
	var k := index % 8
	var x := column % SIZE
	var z := column / SIZE
	var neighbors := {}
	var neighbor_light := {}
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				var nx := x + dx
				var nz := z + dz
				var nk := k + dy
				if (dx == 0 and dy == 0 and dz == 0) or nx < 0 or nz < 0 or nx >= SIZE or nz >= SIZE \
						or nk < 0 or nk >= WorldGenerator.HEIGHT_CHUNKS:
					continue
				var other := (nx + nz * SIZE) * 8 + nk
				neighbors[Vector3i(dx, dy, dz)] = _chunk_blocks[other]
				neighbor_light[Vector3i(dx, dy, dz)] = _chunk_light[other]
	var colors: Array = _colors[column]
	_surfaces[index] = ChunkMesher.build(ChunkMesher.pad(_chunk_blocks[index], neighbors),
		ChunkMesher.pad(_chunk_light[index], neighbor_light, SkyLight.MAX), colors[0], colors[1],
		Vector3i(TITLE_COLUMN.x + x - RADIUS, k, TITLE_COLUMN.y + z - RADIUS) * ChunkData.SIZE)


func _show_meshes() -> void:
	for index in CHUNKS:
		var surfaces: Dictionary = _surfaces[index]
		if surfaces.is_empty():
			continue
		var column := index / 8
		var instance := MeshInstance3D.new()
		instance.mesh = ChunkMesher.to_mesh(surfaces)
		instance.position = Vector3(column % SIZE, index % 8, column / SIZE) * ChunkData.SIZE
		instance.transparency = 1.0
		add_child(instance)
		_instances.append(instance)
	_chunk_blocks.clear()
	_chunk_light.clear()
	_surfaces.clear()
