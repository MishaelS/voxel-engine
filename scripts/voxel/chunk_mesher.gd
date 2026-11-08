class_name ChunkMesher
extends RefCounted
## Builds chunk geometry with hidden face culling: a face is emitted only
## if the neighboring block in that direction is not opaque.
##
## build_arrays() only reads ChunkData and returns plain surface arrays
## (no Resources, no scene tree), so it can later run on worker threads.
## Swapping in another mesher (e.g. greedy) means writing another
## function with the same input and output.

## Per face: neighbor offset, normal and 4 corner offsets, ordered clockwise
## when viewed from outside (Godot treats clockwise winding as front-facing).
const FACE_OFFSETS: Array[Vector3i] = [
	Vector3i.UP, Vector3i.DOWN, Vector3i.RIGHT, Vector3i.LEFT, Vector3i.BACK, Vector3i.FORWARD,
]
const FACE_NORMALS: Array[Vector3] = [
	Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD,
]
const FACE_CORNERS := [
	[Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)], # +Y
	[Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, 0)], # -Y
	[Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(1, 0, 0), Vector3(1, 0, 1)], # +X
	[Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(0, 0, 1), Vector3(0, 0, 0)], # -X
	[Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 0, 1), Vector3(0, 0, 1)], # +Z
	[Vector3(1, 1, 0), Vector3(0, 1, 0), Vector3(0, 0, 0), Vector3(1, 0, 0)], # -Z
]


## Returns Mesh surface arrays, or an empty Array if nothing is visible.
static func build_arrays(data: ChunkData) -> Array:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for y in ChunkData.SIZE:
		for z in ChunkData.SIZE:
			for x in ChunkData.SIZE:
				var id := data.get_block(x, y, z)
				if id == Blocks.AIR:
					continue
				var color := Blocks.COLORS[id]
				var origin := Vector3(x, y, z)

				for face in 6:
					var offset := FACE_OFFSETS[face]
					if Blocks.is_opaque(data.get_block_or_air(x + offset.x, y + offset.y, z + offset.z)):
						continue # hidden face: never sent to the GPU

					var start := vertices.size()
					var corners: Array = FACE_CORNERS[face]
					var normal := FACE_NORMALS[face]
					for i in 4:
						vertices.append(origin + corners[i])
						normals.append(normal)
						colors.append(color)
					indices.append_array([start, start + 1, start + 2, start, start + 2, start + 3])

	if vertices.is_empty():
		return []

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays
