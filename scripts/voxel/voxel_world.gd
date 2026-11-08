class_name VoxelWorld
extends Node3D
## Owns chunks: generates their data, builds meshes and keeps render stats.
## For now a single chunk at the origin.

@export var world_seed: int = 1337

## Filled after build; read by the HUD.
var stats := {}

var _material: StandardMaterial3D
var _generator: TerrainGenerator
var _chunks := {} # Vector3i -> ChunkData


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = false # mesher emits linear colors
	_material.roughness = 1.0

	_generator = TerrainGenerator.new(world_seed)
	_load_chunk(Vector3i.ZERO)


func _load_chunk(coord: Vector3i) -> void:
	var data := ChunkData.new()
	_generator.fill(data, coord)
	_chunks[coord] = data

	var start_us := Time.get_ticks_usec()
	var arrays := ChunkMesher.build_arrays(data)
	var mesh_ms := (Time.get_ticks_usec() - start_us) / 1000.0

	var faces := 0
	if not arrays.is_empty():
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, _material)

		var instance := MeshInstance3D.new()
		instance.name = "Chunk_%d_%d_%d" % [coord.x, coord.y, coord.z]
		instance.mesh = mesh
		instance.position = Vector3(coord * ChunkData.SIZE)
		add_child(instance)
		faces = arrays[Mesh.ARRAY_VERTEX].size() / 4

	stats = {
		"chunks": _chunks.size(),
		"faces": faces,
		"faces_naive": data.count_solid() * 6, # what we'd draw without culling
		"triangles": faces * 2,
		"vertices": faces * 4,
		"mesh_ms": mesh_ms,
	}
