class_name ItemMeshes
extends RefCounted
## 3D shapes of flat items, like the classic game's items in hand: the
## 16 x 16 icon as a front and a back face 1/16 thick, with an edge strip
## along every border between filled and empty pixels. Size 1 x 1 x 1/16,
## the icon's top left at (0, 1, 0).

static var _cache := {} # id -> ArrayMesh


static func extruded(item_id: int, material: Material) -> ArrayMesh:
	if _cache.has(item_id):
		return _cache[item_id]
	var item := Items.get_type(item_id)
	var atlas: Image = (load(Items.ICONS_PATH) as Texture2D).get_image()
	if atlas.is_compressed():
		atlas.decompress()
	var tile_x := (item.icon % 16) * 16
	var tile_y := (item.icon / 16) * 16
	var filled := func(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < 16 and y < 16 and atlas.get_pixel(tile_x + x, tile_y + y).a > 0.5
	const T := 1.0 / 16.0
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var uv0 := Vector2(tile_x, tile_y) / 256.0
	var uv_size := Vector2(16, 16) / 256.0
	var add_quad := func(corners: Array, normal: Vector3, quad_uvs: Array) -> void:
		var start := vertices.size()
		for k in 4:
			vertices.append(corners[k])
			normals.append(normal)
			uvs.append(quad_uvs[k])
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
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	_cache[item_id] = mesh
	return mesh
