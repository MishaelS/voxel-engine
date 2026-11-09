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
## At full Ambient Occlusion strength: deep, clearly visible corners.
const AO_BRIGHTNESS: Array[float] = [0.22, 0.45, 0.68, 1.0]
## Block shadows: light levels below full fall off faster than the classic
## curve (raised to this power), so the shade under trees, overhangs and in
## nooks reads clearly.
const SHADOW_CONTRAST := 1.35

## Brightness of light levels 0..15, the classic curve: each level is a
## clear step down, level 0 keeps 5% so caves are dark but not black.
static var LIGHT_BRIGHTNESS := _build_light_curve()

## Smooth lighting (voxel AO + light averaged per corner) on/off ("Smooth
## Lighting" setting; off = flat light per face). Re-mesh after changing.
## Smooth Lighting setting: 0 = off (flat light per face), 1 = minimum
## (light averaged per corner, no ambient occlusion), 2 = maximum (with
## voxel AO). Re-mesh after changing.
static var smooth_lighting := 2

## Index offset in the padded volume for each face direction.
static var _face_deltas := _build_face_deltas()
## Per face and corner: index offsets (from the block in front of the face)
## of the two side neighbors and the diagonal one, for AO.
static var _ao_deltas := _build_ao_deltas()
## FACE_CORNERS and FACE_NORMALS as packed arrays for the mesher's hot loop
## ([face * 4 + corner], [face]).
static var _corner_offsets := _build_corner_offsets()
static var _normals := PackedVector3Array(FACE_NORMALS)
## AO brightness per level and the light curve are applied in the block
## shaders (block_common.gdshaderinc), which read the raw values.
## Water: its surface sits LIQUID_DROP below the block top unless more
## water is above (like the classic game).
const LIQUID_DROP := 0.125


## AO_BRIGHTNESS as the block shaders' `ao_levels` uniform.
static func ao_levels() -> Vector4:
	return Vector4(AO_BRIGHTNESS[0], AO_BRIGHTNESS[1], AO_BRIGHTNESS[2], AO_BRIGHTNESS[3])


static func _build_light_curve() -> PackedFloat32Array:
	var curve := PackedFloat32Array()
	for level in SkyLight.MAX + 1:
		var darkness := 1.0 - level / float(SkyLight.MAX)
		var classic := (1.0 - darkness) / (darkness * 3.0 + 1.0)
		curve.append(pow(classic, SHADOW_CONTRAST) * 0.95 + 0.05)
	return curve


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
	padded[1 + P + P2] = block_id # local (0, 0, 0)
	return padded


## Padded light volume at full light (blocks rendered outside the world).
static func full_light() -> PackedByteArray:
	var padded := PackedByteArray()
	padded.resize(PADDED_VOLUME)
	padded.fill(SkyLight.MAX)
	return padded


## Connectivity of a chunk with every face connected to every other.
const ALL_CONNECTED := (1 << 36) - 1


## Which faces of the chunk are connected to each other through
## non-opaque cells (the visibility graph of "advanced cave culling", as in
## the modern game): bit (a * 6 + b) is set when you can get from face a to
## face b through the chunk. Faces in BlockType order (+Y, -Y, +X, -X, +Z,
## -Z). Empty chunks connect everything, solid ones nothing. Inline flood
## fill on packed arrays (runs on worker threads).
static func connectivity(padded: PackedByteArray) -> int:
	var opaque := Blocks.is_opaque_table
	var open := PackedByteArray()
	open.resize(4096)
	var count := 0
	var i := 0
	for y in SIZE:
		for z in SIZE:
			var row := 1 + P * ((z + 1) + P * (y + 1))
			for x in SIZE:
				if opaque[padded[row + x]] == 0:
					open[i] = 1
					count += 1
				i += 1
	if count == 0:
		return 0
	if count == 4096:
		return ALL_CONNECTED
	var visited := PackedByteArray()
	visited.resize(4096)
	var queue := PackedInt32Array()
	queue.resize(4096)
	var result := 0
	for start in 4096:
		if open[start] == 0 or visited[start] == 1:
			continue
		visited[start] = 1
		queue[0] = start
		var head := 0
		var tail := 1
		var faces := 0
		while head < tail:
			var c := queue[head]
			head += 1
			var x := c & 15
			var z := (c >> 4) & 15
			var y := c >> 8
			var n := 0
			if y == 15:
				faces |= 1
			else:
				n = c + 256
				if open[n] == 1 and visited[n] == 0:
					visited[n] = 1
					queue[tail] = n
					tail += 1
			if y == 0:
				faces |= 2
			else:
				n = c - 256
				if open[n] == 1 and visited[n] == 0:
					visited[n] = 1
					queue[tail] = n
					tail += 1
			if x == 15:
				faces |= 4
			else:
				n = c + 1
				if open[n] == 1 and visited[n] == 0:
					visited[n] = 1
					queue[tail] = n
					tail += 1
			if x == 0:
				faces |= 8
			else:
				n = c - 1
				if open[n] == 1 and visited[n] == 0:
					visited[n] = 1
					queue[tail] = n
					tail += 1
			if z == 15:
				faces |= 16
			else:
				n = c + 16
				if open[n] == 1 and visited[n] == 0:
					visited[n] = 1
					queue[tail] = n
					tail += 1
			if z == 0:
				faces |= 32
			else:
				n = c - 16
				if open[n] == 1 and visited[n] == 0:
					visited[n] = 1
					queue[tail] = n
					tail += 1
		for a in 6:
			if faces & (1 << a):
				for b in 6:
					if faces & (1 << b):
						result |= 1 << (a * 6 + b)
	return result


## Vertex data is stored compressed on the GPU (16-bit positions and UVs,
## octahedral normals): half the memory and vertex bandwidth.
const MESH_FLAGS := Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES


## ArrayMesh from build() output: one surface per layer with that layer's
## block material, or `material` for every surface.
static func to_mesh(surfaces: Dictionary, material: Material = null) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for layer: int in surfaces:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfaces[layer], [], {}, MESH_FLAGS)
		mesh.surface_set_material(mesh.get_surface_count() - 1,
			material if material else BlockMaterials.get_material(layer))
	return mesh


## Mesh of one block at full light, exactly as it looks in the world
## (falling blocks, icons, the block in hand).
static func block_mesh(block_id: int, material: Material = null) -> ArrayMesh:
	return to_mesh(build(single_block(block_id), full_light()), material)


## Returns {Blocks.Layer: surface arrays} for every non-empty layer.
## `grass` / `foliage`: colors of the chunk's 256 block columns (x + 16 * z)
## for biome-tinted blocks (BlockType.biome_tint); empty = the blocks' own
## tints.
static func build(padded: PackedByteArray, light: PackedByteArray,
		grass := PackedColorArray(), foliage := PackedColorArray()) -> Dictionary:
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
	var smooth := smooth_lighting > 0
	var use_ao := smooth_lighting >= 2
	var arrays := _build_layer(padded, light, opaque_cells, smooth, use_ao, grass, foliage)
	if not arrays.is_empty():
		result[Blocks.Layer.OPAQUE] = arrays
	arrays = _build_layer(padded, light, cutout_cells, smooth, use_ao, grass, foliage)
	if not arrays.is_empty():
		result[Blocks.Layer.CUTOUT] = arrays
	arrays = _build_layer(padded, light, translucent_cells, false, false, grass, foliage)
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
##
## Vertex data: COLOR.rgb = tint, COLOR.a = smooth sky light level / 15 (the
## shader turns it into brightness, minus the night's darkness like the
## classic game); UV2.x = base tile + AO level (0..3) / 4, UV2.y = overlay.
static func _build_layer(padded: PackedByteArray, light: PackedByteArray, cells: PackedInt32Array,
		smooth: bool, use_ao: bool, grass: PackedColorArray, foliage: PackedColorArray) -> Array:
	if cells.is_empty():
		return []
	var opaque := Blocks.is_opaque_table
	var cull_self := Blocks.cull_self_table
	var liquid := Blocks.liquid_table
	var layer_of := Blocks.layer_table
	var face_tiles := Blocks.face_tiles
	var face_overlays := Blocks.face_overlays
	var tints := Blocks.tints_linear
	var face_deltas := _face_deltas
	var ao_deltas := _ao_deltas
	var corner_offsets := _corner_offsets
	var normals_table := _normals
	var biome_tint := Blocks.biome_tint_table
	var has_colors := grass.size() == 256 and foliage.size() == 256
	var water := Blocks.id_of("water") # not a static var: Blocks may still be registering

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
		if has_colors and biome_tint[id] != 0:
			var column := (i % P - 1) + 16 * ((i / P) % P - 1)
			tint = grass[column] if biome_tint[id] == 1 else foliage[column]
		var self_culls := cull_self[id] == 1
		# Lowered top corners: water without water above.
		var drop := LIQUID_DROP if id == water and padded[i + P2] != water else 0.0

		for face in 6:
			var front := i + face_deltas[face]
			var neighbor := padded[front]
			if opaque[neighbor] == 1:
				continue # hidden by an opaque block: never sent to the GPU
			if neighbor == id and self_culls:
				continue # glass next to glass, water next to water
			if liquid[id] == 1 and neighbor != Blocks.AIR and layer_of[neighbor] == Blocks.Layer.TRANSLUCENT:
				continue # water under ice: only the ice face is drawn
			# Ice next to water: only the strip above the water's surface is
			# drawn; the part under it would show through the water as a ghost
			# wall. With more water above, the water reaches the top: nothing.
			var raise := 0.0
			if face >= 2 and liquid[neighbor] == 1 and layer_of[id] == Blocks.Layer.TRANSLUCENT:
				if liquid[padded[front + P2]] == 1:
					continue
				raise = 1.0 - LIQUID_DROP

			var index := id * 6 + face
			var tile := float(face_tiles[index])
			var overlay := float(face_overlays[index])
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
					if not use_ao:
						ao = 3
				if c == 0 or c == 2:
					ao_sum_02 += ao
				else:
					ao_sum_13 += ao
				var corner := corner_offsets[face * 4 + c]
				if corner.y > 0.5:
					corner.y -= drop
				elif raise > 0.0:
					corner.y = raise
				vertices.append(origin + corner)
				normals.append(normal)
				layers.append(Vector2(tile + ao * 0.25, overlay))
				colors.append(Color(tint.r, tint.g, tint.b, level / SkyLight.MAX))
			uvs.append(uv0)
			uvs.append(uv1)
			if raise > 0.0:
				uvs.append(Vector2(1, 1.0 - raise))
				uvs.append(Vector2(0, 1.0 - raise))
			else:
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

			# Water surface: also a copy facing down, so it is seen from under
			# water (translucent faces are drawn from the front only).
			if face == 0 and liquid[id] == 1:
				var below := vertices.size()
				for c in 4:
					vertices.append(vertices[start + c])
					normals.append(Vector3.DOWN)
					layers.append(layers[start + c])
					colors.append(colors[start + c])
					uvs.append(uvs[start + c])
				indices.append_array(PackedInt32Array([below, below + 2, below + 1, below, below + 3, below + 2]))

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
