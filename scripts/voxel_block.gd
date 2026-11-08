@tool
class_name VoxelBlock
extends MeshInstance3D
## A single voxel (a 1x1x1 cube) whose mesh is built manually face by face.
## The same approach (assembling faces into an ArrayMesh) will later form the basis
## of chunk meshing: there, hidden faces simply won't be added.

@export var color: Color = Color(0.45, 0.75, 0.35):
	set(value):
		color = value
		_rebuild()

## Cube faces: a normal and 4 vertices (clockwise when viewed from outside -
## in Godot, a face with clockwise winding is considered front-facing).
const FACES := [
	{"normal": Vector3.UP,      "verts": [Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)]},
	{"normal": Vector3.DOWN,    "verts": [Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, 0)]},
	{"normal": Vector3.RIGHT,   "verts": [Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(1, 0, 0), Vector3(1, 0, 1)]},
	{"normal": Vector3.LEFT,    "verts": [Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(0, 0, 1), Vector3(0, 0, 0)]},
	{"normal": Vector3.BACK,    "verts": [Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 0, 1), Vector3(0, 0, 1)]},
	{"normal": Vector3.FORWARD, "verts": [Vector3(1, 1, 0), Vector3(0, 1, 0), Vector3(0, 0, 0), Vector3(1, 0, 0)]},
]
const FACE_UVS := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	for face in FACES:
		var start := vertices.size()
		for i in 4:
			vertices.append(face.verts[i])
			normals.append(face.normal)
			uvs.append(FACE_UVS[i])
		# Два треугольника на грань: 0-1-2 и 0-2-3
		indices.append_array([start, start + 1, start + 2, start, start + 2, start + 3])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	array_mesh.surface_set_material(0, material)

	mesh = array_mesh
