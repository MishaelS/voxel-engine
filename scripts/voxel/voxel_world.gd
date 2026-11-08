class_name VoxelWorld
extends Node3D
## Owns chunks: generates their data, builds meshes and keeps render stats.
## For now a single chunk at the origin.
## R regenerates the world with a new seed.

enum Generator {
	TERRAIN,       ## Heightmap terrain.
	RANDOM_BLOCKS, ## Debug: every block type scattered randomly.
}

@export var generator: Generator = Generator.TERRAIN
@export var world_seed: int = 1337
## Share of non-floor cells filled in RANDOM_BLOCKS mode.
@export_range(0.0, 1.0) var random_density: float = 0.3

## Filled after build; read by the HUD.
var stats := {}

var _chunks := {} # Vector3i -> ChunkData


func _ready() -> void:
	generate()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("regenerate_world"):
		world_seed = randi()
		generate()
		get_viewport().set_input_as_handled()


func generate() -> void:
	var data := ChunkData.new()
	match generator:
		Generator.TERRAIN:
			TerrainGenerator.new(world_seed).fill(data, Vector3i.ZERO)
		Generator.RANDOM_BLOCKS:
			RandomBlocksGenerator.new(world_seed, random_density).fill(data, Vector3i.ZERO)
	add_chunk(Vector3i.ZERO, data)


## Builds and shows the mesh of a chunk; replaces an existing one.
func add_chunk(coord: Vector3i, data: ChunkData) -> void:
	_chunks[coord] = data
	var node_name := "Chunk_%d_%d_%d" % [coord.x, coord.y, coord.z]
	var old := get_node_or_null(node_name)
	if old:
		remove_child(old)
		old.queue_free()

	var start_us := Time.get_ticks_usec()
	var surfaces := ChunkMesher.build(data)
	var mesh_ms := (Time.get_ticks_usec() - start_us) / 1000.0

	var faces := 0
	if not surfaces.is_empty():
		var mesh := ArrayMesh.new()
		for layer: int in surfaces:
			var arrays: Array = surfaces[layer]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, BlockMaterials.get_material(layer))
			faces += arrays[Mesh.ARRAY_VERTEX].size() / 4

		var instance := MeshInstance3D.new()
		instance.name = node_name
		instance.mesh = mesh
		instance.position = Vector3(coord * ChunkData.SIZE)
		add_child(instance)

	stats = {
		"generator": Generator.keys()[generator],
		"seed": world_seed,
		"chunks": _chunks.size(),
		"faces": faces,
		"faces_naive": data.count_solid() * 6, # what we'd draw without culling
		"triangles": faces * 2,
		"vertices": faces * 4,
		"mesh_ms": mesh_ms,
	}
