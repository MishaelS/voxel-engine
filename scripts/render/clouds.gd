class_name Clouds
extends MeshInstance3D
## The cloud layer, like the classic game's fancy clouds: 12x12-block
## cells, 4 blocks thick, 44 blocks above the sea (y = 172), drifting east with the game ticks.
##
## The shape comes from a repeating 256x256 pattern (made once from
## seamless noise). The mesh is built once: a grid of boxes that follows
## the camera cell by cell; the shader hides empty cells and inner faces
## (see clouds.gdshader), so nothing is rebuilt while playing.

const CELL := 12.0
const THICKNESS := 4.0
const HEIGHT := WorldGenerator.SEA_LEVEL + 44.0
const GRID := 48            ## cells across the mesh (576 blocks)
const PATTERN_SIZE := 256
## Blocks per game tick (the classic speed).
const SPEED := 0.03
## Share of the pattern covered by clouds.
const COVERAGE := 0.38

@export var camera: Camera3D
@export var world: VoxelWorld

var _material: ShaderMaterial


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/clouds.gdshader")
	_material.set_shader_parameter("pattern", _make_pattern())
	_material.set_shader_parameter("fade_end", GRID * CELL * 0.5)
	_material.set_shader_parameter("fade_start", GRID * CELL * 0.25)
	mesh = _make_mesh()
	mesh.surface_set_material(0, _material)
	# The mesh moves with the camera: never culled by its own bounds.
	custom_aabb = AABB(Vector3(-1e6, -1e3, -1e6), Vector3(2e6, 2e3, 2e6))


## Fancy: 3D boxes; Fast: a flat layer (the classic fast clouds).
func set_fancy(fancy: bool) -> void:
	scale.y = 1.0 if fancy else 0.01


func set_color(color: Color) -> void:
	_material.set_shader_parameter("cloud_color", color)


func _process(_delta: float) -> void:
	if camera == null:
		return
	# Game ticks in a world; real time elsewhere (title screen).
	var ticks := Time.get_ticks_msec() / 50.0
	if world:
		ticks = world.clock.game_time + (0.0 if TickLoop.frozen else TickLoop.alpha)
	if not Settings.get_value("cloud_motion"):
		ticks = 0.0
	# Scrolling repeats with the pattern, which keeps the numbers small.
	var scroll := fmod(ticks * SPEED, PATTERN_SIZE * CELL)
	var eye := camera.global_position
	var base_x := floori((eye.x + scroll) / CELL) - GRID / 2
	var base_z := floori(eye.z / CELL) - GRID / 2
	global_position = Vector3(base_x * CELL - scroll, HEIGHT, base_z * CELL)
	_material.set_shader_parameter("offset", Vector2i(base_x, base_z))
	_material.set_shader_parameter("camera_position", eye)


## 1 = cloud, 0 = sky. Seamless noise, so the pattern tiles.
func _make_pattern() -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	noise.seed = 108
	var image := noise.get_seamless_image(PATTERN_SIZE, PATTERN_SIZE)
	image.convert(Image.FORMAT_L8)
	# Threshold at the level that gives the wanted coverage.
	var values := image.get_data()
	var sorted := values.duplicate()
	sorted.sort()
	var threshold := sorted[int((1.0 - COVERAGE) * (sorted.size() - 1))]
	for i in values.size():
		values[i] = 255 if values[i] > threshold else 0
	return ImageTexture.create_from_image(Image.create_from_data(PATTERN_SIZE, PATTERN_SIZE, false, Image.FORMAT_L8, values))


## A box for every cell of the grid; UV = the cell's index.
func _make_mesh() -> ArrayMesh:
	const FACES := [
		# normal, 4 corners (unit box), clockwise from outside
		[Vector3.UP, [Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)]],
		[Vector3.DOWN, [Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, 0)]],
		[Vector3.RIGHT, [Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(1, 0, 0), Vector3(1, 0, 1)]],
		[Vector3.LEFT, [Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(0, 0, 1), Vector3(0, 0, 0)]],
		[Vector3.BACK, [Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 0, 1), Vector3(0, 0, 1)]],
		[Vector3.FORWARD, [Vector3(1, 1, 0), Vector3(0, 1, 0), Vector3(0, 0, 0), Vector3(1, 0, 0)]],
	]
	var size := Vector3(CELL, THICKNESS, CELL)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for cz in GRID:
		for cx in GRID:
			var origin := Vector3(cx * CELL, 0.0, cz * CELL)
			var cell := Vector2(cx, cz)
			for face: Array in FACES:
				var start := vertices.size()
				for corner: Vector3 in face[1]:
					vertices.append(origin + corner * size)
					normals.append(face[0])
					uvs.append(cell)
				indices.append_array([start, start + 1, start + 2, start, start + 2, start + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result
