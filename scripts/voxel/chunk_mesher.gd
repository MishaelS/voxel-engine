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
## Plants: two diagonal squares across the block, each drawn from both
## sides (corners top-left, top-right, bottom-right, bottom-left).
const CROSS_LOW := 0.05
const CROSS_HIGH := 0.95
static var CROSS_QUADS: Array[PackedVector3Array] = [
	PackedVector3Array([Vector3(CROSS_LOW, 1, CROSS_LOW), Vector3(CROSS_HIGH, 1, CROSS_HIGH), Vector3(CROSS_HIGH, 0, CROSS_HIGH), Vector3(CROSS_LOW, 0, CROSS_LOW)]),
	PackedVector3Array([Vector3(CROSS_HIGH, 1, CROSS_HIGH), Vector3(CROSS_LOW, 1, CROSS_LOW), Vector3(CROSS_LOW, 0, CROSS_LOW), Vector3(CROSS_HIGH, 0, CROSS_HIGH)]),
	PackedVector3Array([Vector3(CROSS_LOW, 1, CROSS_HIGH), Vector3(CROSS_HIGH, 1, CROSS_LOW), Vector3(CROSS_HIGH, 0, CROSS_LOW), Vector3(CROSS_LOW, 0, CROSS_HIGH)]),
	PackedVector3Array([Vector3(CROSS_HIGH, 1, CROSS_LOW), Vector3(CROSS_LOW, 1, CROSS_HIGH), Vector3(CROSS_LOW, 0, CROSS_HIGH), Vector3(CROSS_HIGH, 0, CROSS_LOW)]),
]

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
## Random Texture Rotation setting (see BlockType.random_rotation).
static var random_rotation := true

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
## Height of still water's surface below the block top (the ice strip next
## to water is drawn above it).
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
static func pad_blocks(center: PackedInt32Array, neighbors: Dictionary, fill: int = 0) -> PackedInt32Array:
	var padded := PackedInt32Array()
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
		var blocks: PackedInt32Array = neighbors[offset]
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


## The same for a light array (sky light: missing neighbors full, block
## light: dark).
static func pad_light(center: PackedByteArray, neighbors: Dictionary, fill: int = 0) -> PackedByteArray:
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
static func single_block(block_id: int) -> PackedInt32Array:
	var padded := PackedInt32Array()
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
static func connectivity(padded: PackedInt32Array) -> int:
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
## CUSTOM0 holds the block light (one byte per vertex used).
const MESH_FLAGS := Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES \
	| (Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)


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
## `origin`: world position of the chunk's first block, which picks each
## block's random texture rotation (null = no random rotation: single blocks).
## `block_light`: the padded block light (glowing blocks); empty = none.
static func build(padded: PackedInt32Array, light: PackedByteArray,
		grass := PackedColorArray(), foliage := PackedColorArray(), origin: Variant = null,
		block_light := PackedByteArray()) -> Dictionary:
	var opaque := Blocks.is_opaque_table
	if block_light.is_empty():
		block_light.resize(PADDED_VOLUME)
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
	var rotate := random_rotation and origin != null
	var at: Vector3i = origin if rotate else Vector3i.ZERO
	var smooth := smooth_lighting > 0
	var use_ao := smooth_lighting >= 2
	var arrays := _build_layer(padded, light, opaque_cells, smooth, use_ao, grass, foliage, rotate, at, block_light)
	if not arrays.is_empty():
		result[Blocks.Layer.OPAQUE] = arrays
	arrays = _build_layer(padded, light, cutout_cells, smooth, use_ao, grass, foliage, rotate, at, block_light)
	if not arrays.is_empty():
		result[Blocks.Layer.CUTOUT] = arrays
	arrays = _build_layer(padded, light, translucent_cells, false, false, grass, foliage, rotate, at, block_light)
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
static func _build_layer(padded: PackedInt32Array, light: PackedByteArray, cells: PackedInt32Array,
		smooth: bool, use_ao: bool, grass: PackedColorArray, foliage: PackedColorArray,
		rotate := false, at := Vector3i.ZERO, block_light := PackedByteArray()) -> Array:
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
	var rotation_table := Blocks.random_rotation_table
	var corner_uvs := CORNER_UVS
	var heights := Blocks.height_table
	var uv_modes := Blocks.uv_mode_table
	var cull_groups := Blocks.cull_group_table
	var liquid_levels := Blocks.liquid_level_table
	var collides := Blocks.collides_table
	var corner_heights := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
	var shapes := Blocks.shape_table
	var models := Blocks.model_table
	var has_colors := grass.size() == 256 and foliage.size() == 256

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var layers := PackedVector2Array()
	var colors := PackedColorArray()
	# Block light per vertex (CUSTOM0.r in the shaders, 0..255 = 0..15).
	var glow := PackedByteArray()
	var indices := PackedInt32Array()

	for i in cells:
		var id := padded[i]
		var tint := tints[id]
		var origin := Vector3(i % P - 1, i / P2 - 1, (i / P) % P - 1)
		if has_colors and biome_tint[id] != 0:
			var column := (i % P - 1) + 16 * ((i / P) % P - 1)
			tint = grass[column] if biome_tint[id] == 1 else foliage[column]
		if shapes[id] == BlockType.Shape.MODEL:
			# A block model (BlockModel): lit by the light in the cell, shaded by side.
			var model_color := Color(tint.r, tint.g, tint.b, float(light[i]) / SkyLight.MAX)
			var model_glow := block_light[i] * 17
			for quad: Array in BlockModel.quads(models[id]):
				var corners: PackedVector3Array = quad[0]
				var quad_uvs: PackedVector2Array = quad[2]
				var model_layer := float(quad[3]) + 0.75
				var start := vertices.size()
				for c in 4:
					vertices.append(origin + corners[c])
					normals.append(quad[1])
					uvs.append(quad_uvs[c])
					layers.append(Vector2(model_layer, -1.0))
					colors.append(model_color)
					glow.append(model_glow)
					glow.append(0)
					glow.append(0)
					glow.append(0)
				indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))
			continue
		if shapes[id] == BlockType.Shape.CROSS:
			# Two crossed squares, both sides, lit by the light in the cell
			# (no face shading or AO, like the classic game's plants).
			var cross_tile := float(face_tiles[id * 6 + 2]) + 0.75
			var cross_overlay := -2.0 if face_overlays[id * 6 + 2] == -2 else -1.0 # -2: glowing (fire)
			var cross_color := Color(tint.r, tint.g, tint.b, float(light[i]) / SkyLight.MAX)
			var cross_glow := block_light[i] * 17
			for quad: PackedVector3Array in CROSS_QUADS:
				var start := vertices.size()
				for c in 4:
					vertices.append(origin + quad[c])
					normals.append(Vector3.UP)
					uvs.append(corner_uvs[c])
					layers.append(Vector2(cross_tile, cross_overlay))
					colors.append(cross_color)
					glow.append(cross_glow)
					glow.append(0)
					glow.append(0)
					glow.append(0)
				indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))
			continue
		var self_culls := cull_self[id] == 1
		var group := cull_groups[id]
		var top := heights[id]
		# Liquid surface without liquid above: each top corner as high as the
		# liquid around it, like the classic game (flowing water slopes down).
		var sloped := liquid[id] == 1 and liquid[padded[i + P2]] == 0
		if sloped:
			for k in 4:
				var cx := k & 1
				var cz := k >> 1
				var total := 0.0
				var weight := 0.0
				var full := false
				for dz in 2:
					for dx in 2:
						var j := i + (cx - 1 + dx) + (cz - 1 + dz) * P
						var other := padded[j]
						if liquid[padded[j + P2]] == 1:
							full = true
						if liquid[other] == 1:
							var level := liquid_levels[other]
							var part := ((0 if level >= 8 else level) + 1) / 9.0
							if level == 0 or level >= 8:
								total += part * 10.0
								weight += 10.0
							total += part
							weight += 1.0
						elif collides[other] == 0:
							total += 1.0
							weight += 1.0
				corner_heights[k] = 1.0 if full else 1.0 - total / maxf(weight, 1.0)
		# Random texture variant, fixed per block position (like the modern
		# game's position random): bits 0-1 turn the top / bottom, bit 2
		# mirrors (MIRROR blocks only).
		var turn := -1
		var variants := rotation_table[id]
		if rotate and variants != BlockType.Rotation.NONE:
			var wx := at.x + i % P - 1
			var wy := at.y + i / P2 - 1
			var wz := at.z + (i / P) % P - 1
			var h := (wx * 3129871) ^ (wz * 116129781) ^ wy
			h = h * h * 42317861 + h * 11
			turn = (h >> 16) & 7
			if variants == BlockType.Rotation.TURN:
				turn &= 3 # turned around the vertical axis: sides unchanged
			else:
				turn &= 6 # mirrored and / or turned by 180 degrees

		for face in 6:
			var front := i + face_deltas[face]
			var neighbor := padded[front]
			if opaque[neighbor] == 1 and (face != 0 or top >= 1.0):
				continue # hidden by an opaque block: never sent to the GPU
			if self_culls and cull_groups[neighbor] == group:
				continue # glass next to glass, water next to water, bed halves
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
			var front_glow := block_light[front]
			var ao_sum_02 := 0
			var ao_sum_13 := 0
			for c in 4:
				var ao := 3
				var level := float(front_light)
				var glow_level := float(front_glow)
				if smooth:
					var base := face * 12 + c * 3
					var a := front + ao_deltas[base]
					var b := front + ao_deltas[base + 1]
					var side_a := opaque[padded[a]] == 1
					var side_b := opaque[padded[b]] == 1
					var total := front_light
					var total_glow := front_glow
					var count := 1
					if not side_a:
						total += light[a]
						total_glow += block_light[a]
						count += 1
					if not side_b:
						total += light[b]
						total_glow += block_light[b]
						count += 1
					if side_a and side_b:
						ao = 0 # both sides block it: corner fully occluded
					else:
						var d := front + ao_deltas[base + 2]
						var diagonal := opaque[padded[d]] == 1
						if not diagonal:
							total += light[d]
							total_glow += block_light[d]
							count += 1
						ao = 3 - int(side_a) - int(side_b) - int(diagonal)
					level = float(total) / count
					glow_level = float(total_glow) / count
					if not use_ao:
						ao = 3
				if c == 0 or c == 2:
					ao_sum_02 += ao
				else:
					ao_sum_13 += ao
				var corner := corner_offsets[face * 4 + c]
				if corner.y > 0.5:
					if sloped:
						corner.y = corner_heights[int(corner.x) + 2 * int(corner.z)]
					elif top < 1.0:
						corner.y = top
				elif raise > 0.0:
					corner.y = raise
				vertices.append(origin + corner)
				normals.append(normal)
				layers.append(Vector2(tile + ao * 0.25, overlay))
				colors.append(Color(tint.r, tint.g, tint.b, level / SkyLight.MAX))
				glow.append(roundi(glow_level * 17.0))
				glow.append(0)
				glow.append(0)
				glow.append(0)
			# Texture coordinates: the block's own orientation (beds) or its
			# random rotation; lowered tops (beds) and raised bottoms (ice
			# strips) show the matching part of the texture.
			var mode := uv_modes[index]
			if turn >= 0 and raise == 0.0:
				mode = turn if face < 2 else (turn & 4)
			for c in 4:
				var uv := corner_uvs[(c + mode) & 3]
				if mode & 4:
					uv.x = 1.0 - uv.x
				if face >= 2:
					if c < 2 and sloped:
						# Flowing liquid's lowered sides: the texture is cut off at
						# the surface, not squeezed (like the game's).
						uv.y = 1.0 - (vertices[start + c].y - origin.y)
					elif c < 2 and top < 1.0:
						uv.y = 1.0 - top
					elif c >= 2 and raise > 0.0:
						uv.y = 1.0 - raise
				uvs.append(uv)

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
					glow.append_array(glow.slice((start + c) * 4, (start + c) * 4 + 4))
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
	arrays[Mesh.ARRAY_CUSTOM0] = glow
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays
