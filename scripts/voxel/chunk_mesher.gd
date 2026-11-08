class_name ChunkMesher
extends RefCounted
## Builds chunk geometry, one surface per render layer (Blocks.Layer).
##
## Input is a "padded" volume: the chunk's 16^3 blocks plus a one-block
## border taken from the 26 neighbor chunks (18^3, see pad()). Every
## neighbor lookup - face culling and AO across chunk borders included - is
## then a plain index offset, with no bounds checks or chunk lookups.
##
## Face culling: a face is emitted only if the neighbor in that direction is
## not opaque; faces between two blocks of the same "cull_self" type (glass,
## water) are skipped too.
## Each vertex gets baked voxel ambient occlusion (darker corners/creases)
## and sky light: the average light of the up to 4 clear cells around the
## corner in front of the face ("smooth lighting" of the classic game),
## mapped to brightness with the classic light curve.
##
## build() only reads byte arrays and returns plain surface arrays (no
## Resources, no scene tree), so it runs on worker threads.

const SIZE := ChunkData.SIZE
## Edge of the padded volume.
const P := SIZE + 2
const P2 := P * P
const PADDED_VOLUME := P * P * P

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

## Brightness of light levels 0..15, the classic curve: each level is a
## clear step down, level 0 keeps 5% so caves are dark but not black.
static var LIGHT_BRIGHTNESS := _build_light_curve()

## Smooth lighting (voxel AO + light averaged per corner) on/off ("Smooth
## Lighting" setting; off = flat light per face). Re-mesh after changing.
static var ao_enabled := true

## Index offset in the padded volume for each face direction.
static var _face_deltas := _build_face_deltas()
## Per face and corner: index offsets (from the block in front of the face)
## of the two side neighbors and the diagonal one, for AO.
static var _ao_deltas := _build_ao_deltas()


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


static func _build_light_curve() -> PackedFloat32Array:
	var curve := PackedFloat32Array()
	for level in SkyLight.MAX + 1:
		var darkness := 1.0 - level / float(SkyLight.MAX)
		curve.append((1.0 - darkness) / (darkness * 3.0 + 1.0) * 0.95 + 0.05)
	return curve


static func _brightness(level: float) -> float:
	var low := floori(level)
	if low >= SkyLight.MAX:
		return 1.0
	return lerpf(LIGHT_BRIGHTNESS[low], LIGHT_BRIGHTNESS[low + 1], level - low)


static func padded_index(x: int, y: int, z: int) -> int:
	return (x + 1) + P * ((z + 1) + P * (y + 1))


static func _delta(offset: Vector3i) -> int:
	return offset.x + P * offset.z + P2 * offset.y


static func _build_face_deltas() -> PackedInt32Array:
	var deltas := PackedInt32Array()
	for offset in FACE_OFFSETS:
		deltas.append(_delta(offset))
	return deltas


static func _build_ao_deltas() -> Array:
	var table := []
	for face in 6:
		var normal := FACE_OFFSETS[face]
		var axis := 0 if normal.x != 0 else (1 if normal.y != 0 else 2)
		var tangent_a := (axis + 1) % 3
		var tangent_b := (axis + 2) % 3
		var per_corner := PackedInt32Array()
		for corner: Vector3 in FACE_CORNERS[face]:
			var side_a := Vector3i.ZERO
			var side_b := Vector3i.ZERO
			side_a[tangent_a] = int(corner[tangent_a]) * 2 - 1
			side_b[tangent_b] = int(corner[tangent_b]) * 2 - 1
			per_corner.append(_delta(side_a))
			per_corner.append(_delta(side_b))
			per_corner.append(_delta(side_a + side_b))
		table.append(per_corner)
	return table


## Builds the padded volume of a chunk. `neighbors` maps each of the 26
## offsets (Vector3i, components -1..1) to that chunk's array; missing
## neighbors get `fill` (air for blocks, full light for light).
static func pad(center: PackedByteArray, neighbors: Dictionary, fill: int = 0) -> PackedByteArray:
	var padded := PackedByteArray()
	padded.resize(PADDED_VOLUME)
	if fill != 0:
		padded.fill(fill)
	for y in SIZE:
		for z in SIZE:
			var src := SIZE * (z + SIZE * y)
			var dst := padded_index(0, y, z)
			for x in SIZE:
				padded[dst + x] = center[src + x]
	for offset: Vector3i in neighbors:
		var blocks: PackedByteArray = neighbors[offset]
		if blocks.is_empty():
			continue
		# Which cells of the border this neighbor fills, in its own coordinates.
		var ranges := []
		for axis in 3:
			match offset[axis]:
				-1: ranges.append([SIZE - 1, SIZE - 1])
				1: ranges.append([0, 0])
				_: ranges.append([0, SIZE - 1])
		for y in range(ranges[1][0], ranges[1][1] + 1):
			for z in range(ranges[2][0], ranges[2][1] + 1):
				for x in range(ranges[0][0], ranges[0][1] + 1):
					var target := Vector3i(x, y, z) + offset * SIZE
					padded[padded_index(target.x, target.y, target.z)] = blocks[x + SIZE * (z + SIZE * y)]
	return padded


## Padded volume holding one block at local (0, 0, 0) (falling blocks).
static func single_block(block_id: int) -> PackedByteArray:
	var padded := PackedByteArray()
	padded.resize(PADDED_VOLUME)
	padded[padded_index(0, 0, 0)] = block_id
	return padded


## Padded light volume at full light (blocks rendered outside the world).
static func full_light() -> PackedByteArray:
	var padded := PackedByteArray()
	padded.resize(PADDED_VOLUME)
	padded.fill(SkyLight.MAX)
	return padded


## Returns {Blocks.Layer: surface arrays} for every non-empty layer.
static func build(padded: PackedByteArray, light: PackedByteArray) -> Dictionary:
	var opaque := Blocks.is_opaque_table
	# Fully buried chunk (no see-through block anywhere, border included):
	# nothing can be visible.
	var see_through := false
	for id in padded:
		if opaque[id] == 0:
			see_through = true
			break
	if not see_through:
		return {}

	var surfaces: Array[Surface] = []
	for i in Blocks.LAYER_COUNT:
		surfaces.append(Surface.new())
	var cull_self := Blocks.cull_self_table
	var layer_of := Blocks.layer_table
	var face_tiles := Blocks.face_tiles
	var face_overlays := Blocks.face_overlays
	var tints := Blocks.tints_linear
	var face_deltas := _face_deltas
	var ao := PackedInt32Array([3, 3, 3, 3])
	var corner_light := PackedFloat32Array([15.0, 15.0, 15.0, 15.0])

	for y in SIZE:
		for z in SIZE:
			var row := padded_index(0, y, z)
			for x in SIZE:
				var i := row + x
				var id: int = padded[i]
				if id == Blocks.AIR:
					continue
				var layer: int = layer_of[id]
				var surface := surfaces[layer]
				var tint := tints[id]
				var origin := Vector3(x, y, z)
				var smooth := ao_enabled and layer != Blocks.Layer.TRANSLUCENT

				for face in 6:
					var front := i + face_deltas[face]
					var neighbor: int = padded[front]
					if opaque[neighbor] == 1:
						continue # hidden by an opaque block: never sent to the GPU
					if neighbor == id and cull_self[id] == 1:
						continue # glass next to glass, water next to water

					if smooth:
						_compute_corners(padded, light, opaque, _ao_deltas[face], front, ao, corner_light)
					else:
						ao.fill(3)
						corner_light.fill(light[front])

					var index := id * 6 + face
					var tile_layers := Vector2(face_tiles[index], face_overlays[index])
					var start := surface.vertices.size()
					var corners: Array = FACE_CORNERS[face]
					var normal := FACE_NORMALS[face]
					for c in 4:
						surface.vertices.append(origin + corners[c])
						surface.normals.append(normal)
						surface.uvs.append(CORNER_UVS[c])
						surface.layers.append(tile_layers)
						var shade := AO_BRIGHTNESS[ao[c]] * _brightness(corner_light[c])
						surface.colors.append(Color(tint.r, tint.g, tint.b, shade))

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


## Per corner, from the layer of cells in front of the face (the front cell,
## two side neighbors and the diagonal one):
## - voxel AO (0fps method): how many of the side / diagonal cells are opaque;
## - smooth light: the average light of those of the 4 cells that are clear.
static func _compute_corners(padded: PackedByteArray, light: PackedByteArray, opaque: PackedByteArray,
		deltas: PackedInt32Array, front: int, ao: PackedInt32Array, corner_light: PackedFloat32Array) -> void:
	var front_light := light[front]
	for c in 4:
		var a := front + deltas[c * 3]
		var b := front + deltas[c * 3 + 1]
		var side_a := opaque[padded[a]] == 1
		var side_b := opaque[padded[b]] == 1
		var total := front_light
		var count := 1
		if not side_a:
			total += light[a]
			count += 1
		if not side_b:
			total += light[b]
			count += 1
		if side_a and side_b:
			ao[c] = 0 # both sides block it: corner fully occluded
		else:
			var d := front + deltas[c * 3 + 2]
			var diagonal := opaque[padded[d]] == 1
			if not diagonal:
				total += light[d]
				count += 1
			ao[c] = 3 - int(side_a) - int(side_b) - int(diagonal)
		corner_light[c] = float(total) / count
