class_name MobModels
extends RefCounted
## Mob models from assets/models/mobs.json: each part is a box (pixels,
## facing +Z, origin at the feet) unfolded on the mob's skin (64 x 64 or
## the classic 64 x 32) like the game's: top and bottom squares, then the
## strip -X, front +Z, +X, back -Z (see tools/make_mob_textures.py).
## build() makes a node tree: a root (scaled to blocks) with one pivot node
## per part (turned by the animation) holding the part's mesh.
## Optional part keys:
## - "inflate": pixels added on every side, same texture (armor, hats);
## - "mirror": the texture flipped left-right (the classic left limbs);
## - "rotate": [x, y, z] degrees the pivot starts turned by (the cow's
##   body lies along the box's height, like the game's);
## - "parent": another part whose pivot it moves with (horns, overlays;
##   give it the same pivot);
## - "texture": another skin than the mob's own.

const MODELS_PATH := "res://assets/models/mobs.json"
const SKINS := "res://assets/textures/mobs/"

static var _models := {}
static var _meshes := {} # "mob/part" -> ArrayMesh
static var _materials := {} # texture -> ShaderMaterial


static func model(mob: String) -> Dictionary:
	if _models.is_empty():
		var text := FileAccess.get_file_as_string(MODELS_PATH)
		_models = JSON.parse_string(text)
	return _models.get(mob, {})


## The node tree of a mob's model: {"root": Node3D, "parts": {name: pivot
## Node3D}, "meshes": [MeshInstance3D], "instances": {name: MeshInstance3D},
## "spec": the model}.
static func build(mob: String) -> Dictionary:
	var spec := model(mob)
	var root := Node3D.new()
	root.scale = Vector3.ONE * float(spec.get("scale", 1.0)) / 16.0
	var parts := {}
	var instances := {}
	var meshes: Array[MeshInstance3D] = []
	for part: Dictionary in spec.parts:
		var instance := MeshInstance3D.new()
		instance.mesh = _mesh(mob, part)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if part.has("parent"):
			(parts[part.parent] as Node3D).add_child(instance)
		else:
			var pivot := Node3D.new()
			pivot.name = part.name
			pivot.position = _v(part.pivot)
			if part.has("rotate"):
				pivot.rotation_degrees = _v(part.rotate)
			pivot.add_child(instance)
			root.add_child(pivot)
			parts[part.name] = pivot
		instances[part.name] = instance
		meshes.append(instance)
	return {"root": root, "parts": parts, "meshes": meshes, "instances": instances, "spec": spec}


static func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


## A skin's size in pixels (64 x 64, or 64 x 32 for the classic ones).
static func _skin_size(texture: String) -> Vector2:
	var image := load(SKINS + texture + ".png") as Texture2D
	return Vector2(image.get_size()) if image else Vector2(64, 64)


static func _material(texture: String) -> ShaderMaterial:
	if not _materials.has(texture):
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/mob.gdshader")
		material.set_shader_parameter("skin", load(SKINS + texture + ".png"))
		_materials[texture] = material
	return _materials[texture]


## A part's box around its pivot, with the skin's unfolded faces.
static func part_mesh(mob: String, part: Dictionary) -> ArrayMesh:
	return _mesh(mob, part)


## A part's box around its pivot, with the skin's unfolded faces.
static func _mesh(mob: String, part: Dictionary) -> ArrayMesh:
	var texture: String = part.get("texture", mob)
	var key := "%s/%s/%s/%s/%s/%s" % [mob, part.name, texture, part.get("inflate", 0.0), part.uv, part.get("mirror", false)]
	if _meshes.has(key):
		return _meshes[key]
	var size := _v(part.size)
	var from := _v(part.from) - _v(part.pivot)
	var to := from + size
	var inflate := float(part.get("inflate", 0.0))
	from -= Vector3.ONE * inflate
	to += Vector3.ONE * inflate
	var u: float = part.uv[0]
	var v: float = part.uv[1]
	var w := roundf(size.x)
	var h := roundf(size.y)
	var d := roundf(size.z)
	var x0 := from.x
	var y0 := from.y
	var z0 := from.z
	var x1 := to.x
	var y1 := to.y
	var z1 := to.z
	# Face: corners (top left, top right, bottom right, bottom left seen from
	# outside), normal, texture rectangle.
	var faces := [
		[[Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1)], Vector3.UP, Rect2(u + d, v, w, d)],
		[[Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x0, y0, z0)], Vector3.DOWN, Rect2(u + d + w, v, w, d)],
		[[Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x0, y0, z1), Vector3(x0, y0, z0)], Vector3.LEFT, Rect2(u, v + d, d, h)],
		[[Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y0, z1), Vector3(x0, y0, z1)], Vector3.BACK, Rect2(u + d, v + d, w, h)],
		[[Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1)], Vector3.RIGHT, Rect2(u + d + w, v + d, d, h)],
		[[Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3(x0, y0, z0), Vector3(x1, y0, z0)], Vector3.FORWARD, Rect2(u + 2 * d + w, v + d, w, h)],
	]
	if part.get("mirror", false):
		# The classic mirrored limbs: each face flipped, -X and +X swapped.
		var west: Rect2 = faces[2][2]
		faces[2][2] = faces[4][2]
		faces[4][2] = west
	var skin := _skin_size(texture)
	var mirror: bool = part.get("mirror", false)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for face: Array in faces:
		var start := vertices.size()
		var rect: Rect2 = face[2]
		var corner_uvs := [Vector2(1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)] if mirror \
			else [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for k in 4:
			vertices.append(face[0][k])
			normals.append(face[1])
			uvs.append((rect.position + rect.size * corner_uvs[k]) / skin)
		indices.append_array([start, start + 1, start + 2, start, start + 2, start + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material(texture))
	_meshes[key] = mesh
	return mesh
