class_name ItemMeshes
extends RefCounted
## 3D shapes of flat items, like the game's items in hand and on the
## ground: the 16 x 16 picture as a front and a back face 1/16 thick, with an
## edge strip along every border between filled and empty pixels. Size
## 1 x 1 x 1/16, the picture's top left at (0, 1, 0).
## Flat items are the non-block items (their icon in items.png) and the
## plants (their tile in the block atlas, colored like grass where needed;
## the color is in the vertex COLOR).

static var _cache := {} # [id, material] -> ArrayMesh


## Drawn flat (not as a cube): items and plants.
static func is_flat(id: int) -> bool:
	return not Items.is_block(id) or Blocks.shape_table[id] == BlockType.Shape.CROSS or Blocks.get_type(id).flat_item


## The texture the flat picture comes from: items.png or the block atlas.
static func atlas_path(id: int) -> String:
	return Items.ICONS_PATH if not Items.is_block(id) else Blocks.ATLAS_PATH


## The texture flat pictures are drawn from (the shared item atlas, so
## animated icons move in hand and on the ground too).
static func atlas_texture(id: int) -> Texture2D:
	return Items.icons_texture() if not Items.is_block(id) else load(Blocks.ATLAS_PATH)


static func extruded(item_id: int, material: Material) -> ArrayMesh:
	var key := [item_id, material.get_instance_id()]
	if _cache.has(key):
		return _cache[key]
	var atlas: Image = (atlas_texture(item_id)).get_image()
	if atlas.is_compressed():
		atlas.decompress()
	var tile := 0
	var tint := Color.WHITE
	if Items.is_block(item_id):
		tile = Blocks.face_tiles[item_id * 6 + 2]
		var block := Blocks.get_type(item_id)
		if block.biome_tint != 0:
			tint = block.tint.srgb_to_linear()
	else:
		tile = Items.get_type(item_id).icon
	var tile_x := (tile % 16) * 16
	var tile_y := (tile / 16) * 16
	var filled := func(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < 16 and y < 16 and atlas.get_pixel(tile_x + x, tile_y + y).a > 0.5
	const T := 1.0 / 16.0
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var uv0 := Vector2(tile_x, tile_y) / 256.0
	var uv_size := Vector2(16, 16) / 256.0
	var colors := PackedColorArray()
	var add_quad := func(corners: Array, normal: Vector3, quad_uvs: Array) -> void:
		var start := vertices.size()
		for k in 4:
			vertices.append(corners[k])
			normals.append(normal)
			uvs.append(quad_uvs[k])
			colors.append(tint)
		indices.append_array([start, start + 1, start + 2, start, start + 2, start + 3])
	# Front (+Z) and back (-Z).
	add_quad.call([Vector3(0, 1, T), Vector3(1, 1, T), Vector3(1, 0, T), Vector3(0, 0, T)], Vector3.BACK,
		[uv0, uv0 + Vector2(uv_size.x, 0), uv0 + uv_size, uv0 + Vector2(0, uv_size.y)])
	add_quad.call([Vector3(1, 1, 0), Vector3(0, 1, 0), Vector3(0, 0, 0), Vector3(1, 0, 0)], Vector3.FORWARD,
		[uv0 + Vector2(uv_size.x, 0), uv0, uv0 + Vector2(0, uv_size.y), uv0 + uv_size])
	# Edges: each pixel's sides that border an empty pixel, in its color.
	for y in 16:
		for x in 16:
			if not filled.call(x, y):
				continue
			var x0 := x * T
			var x1 := x0 + T
			var y1 := 1.0 - y * T
			var y0 := y1 - T
			var pixel := uv0 + (Vector2(x, y) + Vector2(0.5, 0.5)) / 256.0
			var flat := [pixel, pixel, pixel, pixel]
			if not filled.call(x, y - 1):
				add_quad.call([Vector3(x0, y1, 0), Vector3(x1, y1, 0), Vector3(x1, y1, T), Vector3(x0, y1, T)], Vector3.UP, flat)
			if not filled.call(x, y + 1):
				add_quad.call([Vector3(x0, y0, T), Vector3(x1, y0, T), Vector3(x1, y0, 0), Vector3(x0, y0, 0)], Vector3.DOWN, flat)
			if not filled.call(x - 1, y):
				add_quad.call([Vector3(x0, y1, 0), Vector3(x0, y1, T), Vector3(x0, y0, T), Vector3(x0, y0, 0)], Vector3.LEFT, flat)
			if not filled.call(x + 1, y):
				add_quad.call([Vector3(x1, y1, T), Vector3(x1, y1, 0), Vector3(x1, y0, 0), Vector3(x1, y0, T)], Vector3.RIGHT, flat)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	_cache[key] = mesh
	return mesh
