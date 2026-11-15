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
##
## A texture pack can have its own instead (TexturePacks): six pictures of
## a cube around the eye, title/bg/panorama0..5.png (front, right, back,
## left, top, bottom, like the later game's), turning the same way; or one
## still picture, title/background.png, covering the screen.

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
var _chunk_blocks: Array = []   # [column * WorldGenerator.HEIGHT_CHUNKS + k] -> PackedByteArray
var _heights: Array = []        # [column] -> PackedInt32Array
var _colors: Array = []         # [column] -> [grass, foliage]
var _chunk_light: Array = []
var _surfaces: Array = []
var _instances: Array[MeshInstance3D] = []
var _fade := 0.0
var _angle := 0.0
var _eye := Vector3(72.0, 80.0, 72.0)


## The pack's cube panorama pictures (six, or none).
static func pack_faces() -> Array[Texture2D]:
	var faces: Array[Texture2D] = []
	for i in 6:
		var bytes := TexturePacks.read_file("title/bg/panorama%d.png" % i)
		var image := Image.new()
		if bytes.is_empty() or image.load_png_from_buffer(bytes) != OK:
			return [] as Array[Texture2D]
		image.generate_mipmaps()
		faces.append(ImageTexture.create_from_image(image))
	return faces


func _ready() -> void:
	var faces := pack_faces()
	if not faces.is_empty():
		_build_cube(faces)
		return
	var still := TexturePacks.read_file("title/background.png")
	var picture := Image.new()
	if not still.is_empty() and picture.load_png_from_buffer(still) == OK:
		_build_still(picture)
		return
	ChunkMesher.random_rotation = Settings.get_value("random_rotation")
	ChunkMesher.prepare_native()
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
	add_child(LavaAnimation.new())
	add_child(FireAnimation.new())
	var clouds := Clouds.new()
	clouds.camera = camera
	add_child(clouds)
	clouds.set_color(Color(0.62, 0.52, 0.62)) # evening clouds


## A pack's panorama: the six pictures on a cube around the eye.
func _build_cube(faces: Array[Texture2D]) -> void:
	_plain_environment()
	camera = Camera3D.new()
	camera.fov = 85.0
	camera.near = 0.05
	camera.far = 10.0
	camera.current = true
	add_child(camera)
	_eye = Vector3.ZERO
	_update_camera(0.0)
	# [position, rotation] of each face, its picture facing the eye.
	var places := [
		[Vector3(0, 0, -1), Vector3.ZERO], [Vector3(1, 0, 0), Vector3(0, -PI / 2, 0)],
		[Vector3(0, 0, 1), Vector3(0, PI, 0)], [Vector3(-1, 0, 0), Vector3(0, PI / 2, 0)],
		[Vector3(0, 1, 0), Vector3(PI / 2, 0, 0)], [Vector3(0, -1, 0), Vector3(-PI / 2, 0, 0)],
	]
	for i in 6:
		var quad := QuadMesh.new()
		quad.size = Vector2(2.002, 2.002) # (a hair bigger: no seams)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_texture = faces[i]
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		material.disable_fog = true
		quad.material = material
		var face := MeshInstance3D.new()
		face.mesh = quad
		face.position = places[i][0]
		face.rotation = places[i][1]
		face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(face)


## A pack's still picture covering the screen (under the menu's blur).
func _build_still(picture: Image) -> void:
	_plain_environment()
	camera = Camera3D.new()
	camera.current = true
	add_child(camera)
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(picture)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	set_process(false)


func _plain_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)


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
		_chunk_blocks[index * WorldGenerator.HEIGHT_CHUNKS + k] = blocks.slice(k * ChunkData.VOLUME, (k + 1) * ChunkData.VOLUME)


## Light; beyond the piece counts as open air (only seen through fog).
func _light_column(index: int) -> void:
	var x := index % SIZE
	var z := index / SIZE
	var air := PackedInt32Array()
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
				column.append(_chunk_blocks[(nx + nz * SIZE) * WorldGenerator.HEIGHT_CHUNKS + k] if inside else air)
			chunks.append(column)
			heights.append(_heights[nx + nz * SIZE] if inside else no_height)
	var light: Array
	if VoxelWorld.LightJob.native:
		var glowing := []
		var none := PackedByteArray()
		none.resize(WorldGenerator.HEIGHT_CHUNKS)
		for c in 9:
			glowing.append(none) # sky light only
		light = ClassDB.class_call_static("NativeLight", "compute_column", chunks, heights, glowing,
			Blocks.light_opacity_table, Blocks.light_emission_table)[0]
	else:
		light = SkyLight.compute_column(SkyLight.area_of(chunks), heights)
	for k in WorldGenerator.HEIGHT_CHUNKS:
		_chunk_light[index * WorldGenerator.HEIGHT_CHUNKS + k] = light[k]


func _mesh_chunk(index: int) -> void:
	var column := index / WorldGenerator.HEIGHT_CHUNKS
	var k := index % WorldGenerator.HEIGHT_CHUNKS
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
				var other := (nx + nz * SIZE) * WorldGenerator.HEIGHT_CHUNKS + nk
				neighbors[Vector3i(dx, dy, dz)] = _chunk_blocks[other]
				neighbor_light[Vector3i(dx, dy, dz)] = _chunk_light[other]
	var colors: Array = _colors[column]
	var origin := Vector3i(TITLE_COLUMN.x + x - RADIUS, k, TITLE_COLUMN.y + z - RADIUS)
	if ChunkMesher.native:
		_surfaces[index] = ClassDB.class_call_static("NativeMesher", "build_chunk", origin, _chunk_blocks[index],
			neighbors, _chunk_light[index], neighbor_light, PackedByteArray(), {}, colors[0], colors[1],
			ChunkMesher.smooth_lighting, ChunkMesher.random_rotation)[0]
		return
	_surfaces[index] = ChunkMesher.build(ChunkMesher.pad_blocks(_chunk_blocks[index], neighbors),
		ChunkMesher.pad_light(_chunk_light[index], neighbor_light, SkyLight.MAX), colors[0], colors[1],
		Vector3i(TITLE_COLUMN.x + x - RADIUS, k, TITLE_COLUMN.y + z - RADIUS) * ChunkData.SIZE)


func _show_meshes() -> void:
	for index in CHUNKS:
		var surfaces: Dictionary = _surfaces[index]
		if surfaces.is_empty():
			continue
		var column := index / WorldGenerator.HEIGHT_CHUNKS
		var instance := MeshInstance3D.new()
		instance.mesh = ChunkMesher.to_mesh(surfaces)
		instance.position = Vector3(column % SIZE, index % WorldGenerator.HEIGHT_CHUNKS, column / SIZE) * ChunkData.SIZE
		instance.transparency = 1.0
		add_child(instance)
		_instances.append(instance)
	_chunk_blocks.clear()
	_chunk_light.clear()
	_surfaces.clear()
