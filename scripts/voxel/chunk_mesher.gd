class_name ChunkMesher
extends RefCounted
## Builds chunk geometry with hidden face culling: a face is emitted only
## if the neighboring block in that direction is not opaque.
## Each vertex also gets baked voxel ambient occlusion (darker in corners
## and creases), so no screen-space AO pass is needed for block edges.
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

## Brightness for AO level 0 (fully enclosed corner) .. 3 (open corner).
## Applied in linear color space, so these are the real light multipliers.
const AO_BRIGHTNESS: Array[float] = [0.5, 0.68, 0.84, 1.0]

## Block colors converted from sRGB to linear once. Vertex colors are emitted
## in linear space (the material has vertex_color_is_srgb = false); multiplying
## an sRGB color by the AO factor would get gamma-expanded by the GPU and
## turn e.g. 0.5 into ~0.22, making AO far too dark.
static var _linear_colors: Array[Color] = _build_linear_colors()

## For every face and corner: offsets (relative to the block in front of the
## face) of the two side neighbors and the diagonal neighbor of that corner.
static var _ao_offsets: Array = _build_ao_offsets()


static func _build_linear_colors() -> Array[Color]:
	var result: Array[Color] = []
	for color in Blocks.COLORS:
		result.append(color.srgb_to_linear())
	return result


static func _build_ao_offsets() -> Array:
	var table := []
	for face in 6:
		var normal := FACE_OFFSETS[face]
		var axis := 0 if normal.x != 0 else (1 if normal.y != 0 else 2)
		var tangent_a := (axis + 1) % 3
		var tangent_b := (axis + 2) % 3
		var per_corner := []
		for corner: Vector3 in FACE_CORNERS[face]:
			var side_a := Vector3i.ZERO
			var side_b := Vector3i.ZERO
			side_a[tangent_a] = int(corner[tangent_a]) * 2 - 1
			side_b[tangent_b] = int(corner[tangent_b]) * 2 - 1
			per_corner.append([side_a, side_b, side_a + side_b])
		table.append(per_corner)
	return table


## Returns Mesh surface arrays, or an empty Array if nothing is visible.
static func build_arrays(data: ChunkData) -> Array:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var ao := PackedInt32Array([0, 0, 0, 0])

	for y in ChunkData.SIZE:
		for z in ChunkData.SIZE:
			for x in ChunkData.SIZE:
				var id := data.get_block(x, y, z)
				if id == Blocks.AIR:
					continue
				var color := _linear_colors[id]
				var origin := Vector3(x, y, z)

				for face in 6:
					var offset := FACE_OFFSETS[face]
					var fx := x + offset.x
					var fy := y + offset.y
					var fz := z + offset.z
					if Blocks.is_opaque(data.get_block_or_air(fx, fy, fz)):
						continue # hidden face: never sent to the GPU

					# Voxel AO: count opaque blocks around each corner, in the
					# layer directly in front of the face.
					var face_ao: Array = _ao_offsets[face]
					for i in 4:
						var n: Array = face_ao[i]
						var a: Vector3i = n[0]
						var b: Vector3i = n[1]
						var c: Vector3i = n[2]
						var side_a := Blocks.is_opaque(data.get_block_or_air(fx + a.x, fy + a.y, fz + a.z))
						var side_b := Blocks.is_opaque(data.get_block_or_air(fx + b.x, fy + b.y, fz + b.z))
						if side_a and side_b:
							ao[i] = 0 # both sides block it: corner fully occluded
						else:
							var diagonal := Blocks.is_opaque(data.get_block_or_air(fx + c.x, fy + c.y, fz + c.z))
							ao[i] = 3 - int(side_a) - int(side_b) - int(diagonal)

					var start := vertices.size()
					var corners: Array = FACE_CORNERS[face]
					var normal := FACE_NORMALS[face]
					for i in 4:
						vertices.append(origin + corners[i])
						normals.append(normal)
						var shade := AO_BRIGHTNESS[ao[i]]
						colors.append(Color(color.r * shade, color.g * shade, color.b * shade))

					# Split the quad along the diagonal through the darker corners,
					# otherwise AO interpolates unevenly (anisotropy artifact).
					if ao[0] + ao[2] > ao[1] + ao[3]:
						indices.append_array([start, start + 1, start + 3, start + 1, start + 2, start + 3])
					else:
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
