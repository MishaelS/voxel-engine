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
## FACE_CORNERS, FACE_NORMALS and AO_BRIGHTNESS as packed arrays for the
## mesher's hot loop ([face * 4 + corner], [face], [ao level]).
static var _corner_offsets := _build_corner_offsets()
static var _normals := PackedVector3Array(FACE_NORMALS)
static var _ao_brightness := PackedFloat32Array(AO_BRIGHTNESS)


static func _build_light_curve() -> PackedFloat32Array:
	var curve := PackedFloat32Array()
	for level in SkyLight.MAX + 1:
		var darkness := 1.0 - level / float(SkyLight.MAX)
		curve.append((1.0 - darkness) / (darkness * 3.0 + 1.0) * 0.95 + 0.05)
	return curve


static func padded_index(x: int, y: int, z: int) -> int:
	return (x + 1) + P * ((z + 1) + P * (y + 1))


static func _delta(offset: Vector3i) -> int:
	return offset.x + P * offset.z + P2 * offset.y


static func _build_face_deltas() -> PackedInt32Array:
	var deltas := PackedInt32Array()
	for offset in FACE_OFFSETS:
		deltas.append(_delta(offset))
	return deltas


static func _build_corner_offsets() -> PackedVector3Array:
	var offsets := PackedVector3Array()
	for corners: Array in FACE_CORNERS:
		for corner: Vector3 in corners:
			offsets.append(corner)
	return offsets


## [face * 12 + corner * 3 + (side a, side b, diagonal)].
static func _build_ao_deltas() -> PackedInt32Array:
	var table := PackedInt32Array()
	for face in 6:
		var normal := FACE_OFFSETS[face]
		var axis := 0 if normal.x != 0 else (1 if normal.y != 0 else 2)
		var tangent_a := (axis + 1) % 3
		var tangent_b := (axis + 2) % 3
		for corner: Vector3 in FACE_CORNERS[face]:
			var side_a := Vector3i.ZERO
			var side_b := Vector3i.ZERO
			side_a[tangent_a] = int(corner[tangent_a]) * 2 - 1
			side_b[tangent_b] = int(corner[tangent_b]) * 2 - 1
			table.append(_delta(side_a))
			table.append(_delta(side_b))
			table.append(_delta(side_a + side_b))
	return table


## Builds the padded volume of a chunk. `neighbors` maps each of the 26
## offsets (Vector3i, components -1..1) to that chunk's array; missing
## neighbors get `fill` (air for blocks, full light for light).
static func pad(center: PackedByteArray, neighbors: Dictionary, fill: int = 0) -> PackedByteArray:
	var padded := PackedByteArray()
	padded.resize(PADDED_VOLUME)
	if fill != 0:
		padded.fill(fill)
	var src := 0
	for y in SIZE:
		for z in SIZE:
			var dst := 1 + P * ((z + 1) + P * (y + 1))
			for x in SIZE:
				padded[dst + x] = center[src]
				src += 1
	for offset: Vector3i in neighbors:
		var blocks: PackedByteArray = neighbors[offset]
		if blocks.is_empty():
			continue
		# Which cells of the border this neighbor fills, in its own coordinates.
		var x0 := SIZE - 1 if offset.x < 0 else 0
		var x1 := 0 if offset.x > 0 else SIZE - 1
		var y0 := SIZE - 1 if offset.y < 0 else 0
		var y1 := 0 if offset.y > 0 else SIZE - 1
		var z0 := SIZE - 1 if offset.z < 0 else 0
		var z1 := 0 if offset.z > 0 else SIZE - 1
		var shift := (1 + offset.x * SIZE) + P * (1 + offset.z * SIZE) + P2 * (1 + offset.y * SIZE)
		for y in range(y0, y1 + 1):
			for z in range(z0, z1 + 1):
				var row := SIZE * (z + SIZE * y)
				var dst := shift + P * z + P2 * y
				for x in range(x0, x1 + 1):
					padded[dst + x] = blocks[row + x]
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

	# Sort the chunk's blocks by render layer, then mesh layer by layer so the
	# hot loop writes into plain local arrays.
	var layer_of := Blocks.layer_table
	var opaque_cells := PackedInt32Array()
	var cutout_cells := PackedInt32Array()
	var translucent_cells := PackedInt32Array()
	for y in SIZE:
		for z in SIZE:
			var row := 1 + P * ((z + 1) + P * (y + 1))
			for x in SIZE:
				var i := row + x
				var id := padded[i]
				if id == Blocks.AIR:
					continue
				var layer := layer_of[id]
				if layer == Blocks.Layer.OPAQUE:
					opaque_cells.append(i)
				elif layer == Blocks.Layer.CUTOUT:
					cutout_cells.append(i)
				else:
					translucent_cells.append(i)

	var result := {}
	var smooth := ao_enabled
	var arrays := _build_layer(padded, light, opaque_cells, smooth)
	if not arrays.is_empty():
		result[Blocks.Layer.OPAQUE] = arrays
	arrays = _build_layer(padded, light, cutout_cells, smooth)
	if not arrays.is_empty():
		result[Blocks.Layer.CUTOUT] = arrays
	arrays = _build_layer(padded, light, translucent_cells, false)
	if not arrays.is_empty():
		result[Blocks.Layer.TRANSLUCENT] = arrays
	return result


## Surface arrays for the given cells (padded indices) of one layer, or []
## if no face is visible. Everything inside the loops is inline arithmetic
## on packed arrays: in GDScript, function calls and generic Array indexing
## serialize across worker threads.
##
## Per corner, from the layer of cells in front of the face (the front cell,
## two side neighbors and the diagonal one):
## - voxel AO (0fps method): how many of the side / diagonal cells are opaque;
## - smooth light: the average light of those of the 4 cells that are clear.
static func _build_layer(padded: PackedByteArray, light: PackedByteArray, cells: PackedInt32Array, smooth: bool) -> Array:
	if cells.is_empty():
		return []
	var opaque := Blocks.is_opaque_table
	var cull_self := Blocks.cull_self_table
	var face_tiles := Blocks.face_tiles
	var face_overlays := Blocks.face_overlays
	var tints := Blocks.tints_linear
	var face_deltas := _face_deltas
	var ao_deltas := _ao_deltas
	var corner_offsets := _corner_offsets
	var normals_table := _normals
	var ao_brightness := _ao_brightness
	var curve := LIGHT_BRIGHTNESS

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var layers := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var uv0 := Vector2(0, 0)
	var uv1 := Vector2(1, 0)
	var uv2 := Vector2(1, 1)
	var uv3 := Vector2(0, 1)

	for i in cells:
		var id := padded[i]
		var tint := tints[id]
		var origin := Vector3(i % P - 1, i / P2 - 1, (i / P) % P - 1)
		var self_culls := cull_self[id] == 1

		for face in 6:
			var front := i + face_deltas[face]
			var neighbor := padded[front]
			if opaque[neighbor] == 1:
				continue # hidden by an opaque block: never sent to the GPU
			if neighbor == id and self_culls:
				continue # glass next to glass, water next to water

			var index := id * 6 + face
			var tile_layers := Vector2(face_tiles[index], face_overlays[index])
			var normal := normals_table[face]
			var start := vertices.size()
			var front_light := light[front]
			var ao_sum_02 := 0
			var ao_sum_13 := 0
			for c in 4:
				var ao := 3
				var level := float(front_light)
				if smooth:
					var base := face * 12 + c * 3
					var a := front + ao_deltas[base]
					var b := front + ao_deltas[base + 1]
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
						ao = 0 # both sides block it: corner fully occluded
					else:
						var d := front + ao_deltas[base + 2]
						var diagonal := opaque[padded[d]] == 1
						if not diagonal:
							total += light[d]
							count += 1
						ao = 3 - int(side_a) - int(side_b) - int(diagonal)
					level = float(total) / count
				var low := int(level)
				var brightness := 1.0
				if low < SkyLight.MAX:
					var from := curve[low]
					brightness = from + (curve[low + 1] - from) * (level - low)
				if c == 0 or c == 2:
					ao_sum_02 += ao
				else:
					ao_sum_13 += ao
				vertices.append(origin + corner_offsets[face * 4 + c])
				normals.append(normal)
				layers.append(tile_layers)
				colors.append(Color(tint.r, tint.g, tint.b, ao_brightness[ao] * brightness))
			uvs.append(uv0)
			uvs.append(uv1)
			uvs.append(uv2)
			uvs.append(uv3)

			# Split the quad along the diagonal through the darker corners,
			# otherwise AO interpolates unevenly (anisotropy artifact).
			indices.append(start)
			indices.append(start + 1)
			if ao_sum_02 > ao_sum_13:
				indices.append(start + 3)
				indices.append(start + 1)
				indices.append(start + 2)
				indices.append(start + 3)
			else:
				indices.append(start + 2)
				indices.append(start)
				indices.append(start + 2)
				indices.append(start + 3)

	if vertices.is_empty():
		return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = layers
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays
