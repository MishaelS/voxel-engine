class_name ChunkMesher
extends RefCounted
## Builds chunk geometry, one surface per render layer (Blocks.Layer).
##
## Face culling: a face is emitted only if the neighbor in that direction is
## not opaque; faces between two blocks of the same "cull_self" type (glass,
## water) are skipped too.
## Each vertex gets baked voxel ambient occlusion (darker corners/creases).
##
## build() only reads ChunkData and returns plain surface arrays (no
## Resources, no scene tree), so it can later run on worker threads.
## Swapping in another mesher (e.g. greedy) means writing another function
## with the same input and output.

## Face order matches BlockType: +Y, -Y, +X, -X, +Z, -Z.
const FACE_OFFSETS: Array[Vector3i] = [
	Vector3i.UP, Vector3i.DOWN, Vector3i.RIGHT, Vector3i.LEFT, Vector3i.BACK, Vector3i.FORWARD,
]
const FACE_NORMALS: Array[Vector3] = [
	Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD,
]
## 4 corners per face: top-left, top-right, bottom-right, bottom-left as seen
## from outside (clockwise = front-facing in Godot). Side faces are upright,
## so textures are not rotated.
const FACE_CORNERS := [
	[Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)], # +Y
	[Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, 0)], # -Y
	[Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(1, 0, 0), Vector3(1, 0, 1)], # +X
	[Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(0, 0, 1), Vector3(0, 0, 0)], # -X
	[Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 0, 1), Vector3(0, 0, 1)], # +Z
	[Vector3(1, 1, 0), Vector3(0, 1, 0), Vector3(0, 0, 0), Vector3(1, 0, 0)], # -Z
]
const CORNER_UVS: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]

## Brightness for AO level 0 (fully enclosed corner) .. 3 (open corner).
## Linear light multipliers (the shader works in linear space).
const AO_BRIGHTNESS: Array[float] = [0.5, 0.68, 0.84, 1.0]

## For every face and corner: offsets (relative to the block in front of the
## face) of the two side neighbors and the diagonal neighbor of that corner.
static var _ao_offsets: Array = _build_ao_offsets()


## Geometry buffers of one render layer.
class Surface:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var layers := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	func to_arrays() -> Array:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = layers
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		return arrays


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


## Returns {Blocks.Layer: surface arrays} for every non-empty layer.
static func build(data: ChunkData) -> Dictionary:
	var surfaces: Array[Surface] = []
	for i in Blocks.LAYER_COUNT:
		surfaces.append(Surface.new())

	var opaque := Blocks.is_opaque_table
	var cull_self := Blocks.cull_self_table
	var layer_of := Blocks.layer_table
	var face_tiles := Blocks.face_tiles
	var face_overlays := Blocks.face_overlays
	var tints := Blocks.tints_linear
	var ao := PackedInt32Array([3, 3, 3, 3])

	for y in ChunkData.SIZE:
		for z in ChunkData.SIZE:
			for x in ChunkData.SIZE:
				var id := data.get_block(x, y, z)
				if id == Blocks.AIR:
					continue
				var layer: int = layer_of[id]
				var surface := surfaces[layer]
				var tint := tints[id]
				var origin := Vector3(x, y, z)
				var with_ao := layer != Blocks.Layer.TRANSLUCENT

				for face in 6:
					var offset := FACE_OFFSETS[face]
					var fx := x + offset.x
					var fy := y + offset.y
					var fz := z + offset.z
					var neighbor := data.get_block_or_air(fx, fy, fz)
					if opaque[neighbor] == 1:
						continue # hidden by an opaque block: never sent to the GPU
					if neighbor == id and cull_self[id] == 1:
						continue # glass next to glass, water next to water

					if with_ao:
						_compute_ao(data, face, fx, fy, fz, opaque, ao)
					else:
						ao.fill(3)

					var index := id * 6 + face
					var tile_layers := Vector2(face_tiles[index], face_overlays[index])
					var start := surface.vertices.size()
					var corners: Array = FACE_CORNERS[face]
					var normal := FACE_NORMALS[face]
					for i in 4:
						surface.vertices.append(origin + corners[i])
						surface.normals.append(normal)
						surface.uvs.append(CORNER_UVS[i])
						surface.layers.append(tile_layers)
						surface.colors.append(Color(tint.r, tint.g, tint.b, AO_BRIGHTNESS[ao[i]]))

					# Split the quad along the diagonal through the darker corners,
					# otherwise AO interpolates unevenly (anisotropy artifact).
					if ao[0] + ao[2] > ao[1] + ao[3]:
						surface.indices.append_array([start, start + 1, start + 3, start + 1, start + 2, start + 3])
					else:
						surface.indices.append_array([start, start + 1, start + 2, start, start + 2, start + 3])

	var result := {}
	for layer in Blocks.LAYER_COUNT:
		if not surfaces[layer].vertices.is_empty():
			result[layer] = surfaces[layer].to_arrays()
	return result


## Voxel AO (0fps method): per corner, count opaque blocks in the layer in
## front of the face - two side neighbors and the diagonal one.
static func _compute_ao(data: ChunkData, face: int, fx: int, fy: int, fz: int, opaque: PackedByteArray, ao: PackedInt32Array) -> void:
	var face_ao: Array = _ao_offsets[face]
	for i in 4:
		var n: Array = face_ao[i]
		var a: Vector3i = n[0]
		var b: Vector3i = n[1]
		var side_a := opaque[data.get_block_or_air(fx + a.x, fy + a.y, fz + a.z)] == 1
		var side_b := opaque[data.get_block_or_air(fx + b.x, fy + b.y, fz + b.z)] == 1
		if side_a and side_b:
			ao[i] = 0 # both sides block it: corner fully occluded
		else:
			var c: Vector3i = n[2]
			var diagonal := opaque[data.get_block_or_air(fx + c.x, fy + c.y, fz + c.z)] == 1
			ao[i] = 3 - int(side_a) - int(side_b) - int(diagonal)
