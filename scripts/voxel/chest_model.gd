class_name ChestModel
extends RefCounted
## Chests are blocks like Beta 1.7.3's (Blocks._chest): a full cube drawn
## with terrain.png's chest tiles (top and bottom 25, sides 26, a single
## chest's front 27; a large chest's front 41 / 42 and back 58 / 57 by
## half). A large chest is two blocks, its halves (Part).

enum Part { SINGLE, LEFT, RIGHT }
## LEFT is the half on the left when looking at the front (its partner on
## its right, ChestBehavior.right_of).

## The chest as ChestLids draws it while its lid opens, like the modern
## game's chest: the base and the lid (the top LID_PIXELS, the side tiles'
## rows above their dark seam). The outside is the chunk mesher's own cube
## of the chest where it stands (ChunkMesher.build on its 3x3x3
## neighborhood: the same light, smooth light, AO and faces left out next
## to the other half or a block), cut in two at the seam, so it looks just
## like the block. Inside it is just a black hole (rimmed by the top
## tile's edges); the lid's underside is the top tile.
const LID_PIXELS := 5
const BASE_PIXELS := 16 - LID_PIXELS


## [base mesh, lid mesh] of the chest at `cell` (block `id`), in the cell's
## own coordinates (0..1); the lid turns about the back top edge of the base
## (hinge_of).
static func lid_meshes(world: VoxelWorld, cell: Vector3i, id: int) -> Array[ArrayMesh]:
	var base := _Mesh.new()
	var lid := _Mesh.new()
	var cut := BASE_PIXELS / 16.0
	var top_light := Color(1, 1, 1, 1)
	var top_glow := 0.0
	var arrays: Array = _cube_arrays(world, cell).get(Blocks.Layer.OPAQUE, [])
	if not arrays.is_empty():
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		# Each face is 4 vertices and 6 indices; the chest's own faces are
		# the ones on its cell's surface pointing out of it.
		for quad in positions.size() / 4:
			var middle := Vector3.ZERO
			for c in 4:
				middle += positions[quad * 4 + c] / 4.0
			var normal: Vector3 = (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array)[quad * 4]
			var local := middle - Vector3.ONE
			if not AABB(Vector3(-0.01, -0.01, -0.01), Vector3(1.02, 1.02, 1.02)).has_point(local) \
					or normal.dot(local - Vector3(0.5, 0.5, 0.5)) <= 0.0:
				continue
			if normal.y > 0.5:
				var corner := _vertex(arrays, quad * 4)
				top_light = corner[4]
				top_glow = corner[5]
			for triangle in 2:
				var corners: Array = []
				for k in 3:
					var vertex := _vertex(arrays, indices[quad * 6 + triangle * 3 + k])
					vertex[0] -= Vector3.ONE
					corners.append(vertex)
				base.add_polygon(_clip(corners, cut, true))
				lid.add_polygon(_clip(corners, cut, false))
	var inside := Color(0, 0, 0, top_light.a)
	var outside := Color(1, 1, 1, top_light.a)
	var boxes := _inside_boxes(Blocks.chest_part_table[id])
	var turn: float = BlockModel.FACING_TURNS[Blocks.facing_table[id]]
	base.add_quads(BlockModel.quads_of(boxes[0], turn), inside, top_glow)
	base.add_quads(BlockModel.quads_of(boxes[1], turn), outside, top_glow)
	lid.add_quads(BlockModel.quads_of(boxes[2], turn), outside, top_glow)
	return [base.to_mesh(), lid.to_mesh()]


## The hinge of a chest's lid in its cell (the back top edge of the base)
## and the axis the lid opens about (by a positive angle).
static func hinge_of(id: int) -> Array[Vector3]:
	var front := Vector3(Blocks.FACING_DIRECTIONS[Blocks.facing_table[id]])
	return [Vector3(0.5, BASE_PIXELS / 16.0, 0.5) - front * 0.5, front.cross(Vector3.UP)]


## The chunk mesher's surfaces for the chest at `cell` alone with its 26
## neighbors (meshed too; their faces are sorted out by lid_meshes).
static func _cube_arrays(world: VoxelWorld, cell: Vector3i) -> Dictionary:
	var P := ChunkMesher.P
	var blocks := PackedInt32Array()
	blocks.resize(ChunkMesher.PADDED_VOLUME)
	var light := PackedByteArray()
	light.resize(ChunkMesher.PADDED_VOLUME)
	var glow := PackedByteArray()
	glow.resize(ChunkMesher.PADDED_VOLUME)
	for dy in range(-1, 2):
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var at := cell + Vector3i(dx, dy, dz)
				# The chest at local (1, 1, 1); padded indices are 1 further.
				var i := (dx + 2) + P * ((dz + 2) + P * (dy + 2))
				blocks[i] = world.get_block(at)
				light[i] = world.get_light(at)
				glow[i] = world.get_block_light(at)
	return ChunkMesher.build(blocks, light, PackedColorArray(), PackedColorArray(), null, glow)


## A vertex of mesher arrays: [position, normal, uv, layers (UV2), color,
## block light (0..255), AO level, AO level it is blended toward, blend].
static func _vertex(arrays: Array, i: int) -> Array:
	var layers: Vector2 = (arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array)[i]
	var level := clampi(int(fposmod(layers.x + 0.01, 1.0) * 4.0 + 0.5), 0, 3)
	return [(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)[i], (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array)[i],
		(arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array)[i], layers, (arrays[Mesh.ARRAY_COLOR] as PackedColorArray)[i],
		float((arrays[Mesh.ARRAY_CUSTOM0] as PackedByteArray)[i * 4]), level, level, 0.0]


## The part of a triangle below (or above) the height `cut`. New corners
## lie on the triangle's edges and carry what the GPU would interpolate
## there; the AO blends between the edge's two levels (the block shaders'
## CUSTOM0.g / .b), so the cut face shades exactly like the whole one.
static func _clip(corners: Array, cut: float, below: bool) -> Array:
	var result: Array = []
	for k in 3:
		var a: Array = corners[k]
		var b: Array = corners[(k + 1) % 3]
		var a_in: bool = (a[0].y <= cut + 0.0001) if below else (a[0].y >= cut - 0.0001)
		var b_in: bool = (b[0].y <= cut + 0.0001) if below else (b[0].y >= cut - 0.0001)
		if a_in:
			result.append(a)
		if a_in != b_in:
			var t: float = (cut - a[0].y) / (b[0].y - a[0].y)
			result.append([(a[0] as Vector3).lerp(b[0], t), a[1], (a[2] as Vector2).lerp(b[2], t),
				a[3], (a[4] as Color).lerp(b[4], t), lerpf(a[5], b[5], t), a[6], b[6], t])
	return result


## The inside of the chest, facing south (+Z) before turning: [the inside
## (black), the rims (the top tile's edges on the walls), the lid's
## underside]. A large chest's halves leave out the walls between
## them (LEFT has its partner at +X, RIGHT at -X: ChestBehavior.right_of).
static func _inside_boxes(part: int) -> Array:
	var top := Blocks.CHEST_TOP
	var h := float(BASE_PIXELS)
	var inside := [
		{"from": Vector3(0, 0, 0), "to": Vector3(16, 1, 16), "faces": {BlockModel.UP: {"layer": top}}},
		{"from": Vector3(0, 0, 15), "to": Vector3(16, h, 16), "faces": {BlockModel.NORTH: {"layer": top}}},
		{"from": Vector3(0, 0, 0), "to": Vector3(16, h, 1), "faces": {BlockModel.SOUTH: {"layer": top}}},
	]
	var rims := [
		{"from": Vector3(0, 0, 15), "to": Vector3(16, h, 16), "faces": {BlockModel.UP: {"layer": top}}},
		{"from": Vector3(0, 0, 0), "to": Vector3(16, h, 1), "faces": {BlockModel.UP: {"layer": top}}},
	]
	if part != Part.RIGHT:
		inside.append({"from": Vector3(0, 0, 0), "to": Vector3(1, h, 16), "faces": {BlockModel.EAST: {"layer": top}}})
		rims.append({"from": Vector3(0, 0, 1), "to": Vector3(1, h, 15), "faces": {BlockModel.UP: {"layer": top}}})
	if part != Part.LEFT:
		inside.append({"from": Vector3(15, 0, 0), "to": Vector3(16, h, 16), "faces": {BlockModel.WEST: {"layer": top}}})
		rims.append({"from": Vector3(15, 0, 1), "to": Vector3(16, h, 15), "faces": {BlockModel.UP: {"layer": top}}})
	var underside := [{"from": Vector3(0, h, 0), "to": Vector3(16, 16, 16), "faces": {BlockModel.DOWN: {"layer": top}}}]
	return [inside, rims, underside]


## Mesh arrays in the block shaders' format (ChunkMesher), opaque layer.
class _Mesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var layers := PackedVector2Array()
	var colors := PackedColorArray()
	var custom := PackedByteArray()
	var indices := PackedInt32Array()

	func add(vertex: Array) -> void:
		vertices.append(vertex[0])
		normals.append(vertex[1])
		uvs.append(vertex[2])
		var layer: Vector2 = vertex[3]
		layers.append(Vector2(floorf(layer.x + 0.01) + int(vertex[6]) / 4.0, layer.y))
		colors.append(vertex[4])
		# Block light; the AO level blended toward and how far (block_common).
		custom.append_array(PackedByteArray([roundi(vertex[5]), roundi(int(vertex[7]) / 3.0 * 255.0),
			roundi(float(vertex[8]) * 255.0), 0]))

	## A convex polygon (from _clip), as a fan.
	func add_polygon(corners: Array) -> void:
		if corners.size() < 3:
			return
		var start := vertices.size()
		for vertex: Array in corners:
			add(vertex)
		for k in range(1, corners.size() - 1):
			indices.append_array(PackedInt32Array([start, start + k, start + k + 1]))

	## Block model quads (BlockModel.quads_of), no AO.
	func add_quads(quads: Array, color: Color, glow: float) -> void:
		for quad: Array in quads:
			var corners: PackedVector3Array = quad[0]
			var quad_uvs: PackedVector2Array = quad[2]
			var start := vertices.size()
			for c in 4:
				add([corners[c], quad[1], quad_uvs[c], Vector2(float(quad[3]), -1.0), color, glow, 3, 3, 0.0])
			indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))

	func to_mesh() -> ArrayMesh:
		if vertices.is_empty():
			return null
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = layers
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_CUSTOM0] = custom
		arrays[Mesh.ARRAY_INDEX] = indices
		return ChunkMesher.to_mesh({Blocks.Layer.OPAQUE: arrays})
