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
## - "texture": another skin than the mob's own;
## - "translucent": drawn see-through by the skin's alpha (the slime's
##   outer jelly).

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


## Items held like the game's (tools, sticks, bones, rods): pointing
## forward from the fist rather than held up as a picture.
const HELD_LIKE_TOOLS := ["_sword", "_pickaxe", "_axe", "_shovel", "_hoe", "stick", "bone", "fishing_rod", "reed"]


## An item in a creature's (or the player's) right hand, to be added to the
## model's right arm part (pixel units, the arm hanging down): a bow held
## by its grip with the string toward the body, tools pointing forward
## from the fist, other items and blocks small in the hand. Returns null
## for nothing.
static func held_item(mob: String, item_id: int) -> MeshInstance3D:
	if item_id == Blocks.AIR or item_id < 0:
		return null
	var arm: Dictionary = {}
	for part: Dictionary in model(mob).parts:
		if part.name == "right_arm":
			arm = part
	if arm.is_empty():
		return null
	var from := _v(arm.from)
	var size := _v(arm.size)
	var hand := Vector3(from.x + size.x * 0.5, from.y, from.z + size.z * 0.5) - _v(arm.pivot) + Vector3(0, 1.5, 0)
	var mesh := MeshInstance3D.new()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var basis: Basis
	var grip: Vector3 # the held point of the mesh (its own units)
	var scale := 10.0
	if not ItemMeshes.is_flat(item_id):
		mesh.mesh = FallingBlocks.block_mesh(item_id)
		scale = 6.0
		basis = Basis(Vector3.UP, PI / 4.0) * Basis(Vector3.RIGHT, deg_to_rad(20.0))
		grip = Vector3(0.5, 0.5, 0.5)
	else:
		mesh.mesh = ItemMeshes.extruded(item_id, ItemEntities._flat_material(item_id))
		var name := Items.name_of(item_id)
		# The picture stands upright along the arm's forward direction.
		var upright := Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0))
		if name == "bow":
			# The limb (the picture's diagonal) along the forward direction, the
			# arc outward and the string toward the body: held up like this
			# when the arm points ahead (skeletons aiming).
			var r := sqrt(0.5)
			basis = Basis(Vector3(0, r, r), Vector3(0, -r, r), Vector3(1, 0, 0))
			grip = Vector3(0.45, 0.45, 1.0 / 32.0)
		elif HELD_LIKE_TOOLS.any(func(suffix: String) -> bool: return name.ends_with(suffix)):
			basis = Basis(Vector3.RIGHT, deg_to_rad(25.0)) * upright
			grip = Vector3(0.22, 0.22, 1.0 / 32.0)
			hand.z += 1.0
		else:
			scale = 6.0
			basis = upright
			grip = Vector3(0.5, 0.5, 1.0 / 32.0)
			hand.z += 2.0
	basis = basis.scaled(Vector3.ONE * scale)
	mesh.transform = Transform3D(basis, hand - basis * grip)
	return mesh


static func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


## A skin's size in pixels (64 x 64, or 64 x 32 for the classic ones).
static func _skin_size(texture: String) -> Vector2:
	var image := TexturePacks.load_texture(SKINS + texture + ".png")
	return Vector2(image.get_size()) if image else Vector2(64, 64)


static func _material(texture: String, translucent: bool = false) -> ShaderMaterial:
	var key := texture + ("#translucent" if translucent else "")
	if not _materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/mob_translucent.gdshader") if translucent else preload("res://shaders/mob.gdshader")
		material.set_shader_parameter("skin", TexturePacks.load_texture(SKINS + texture + ".png"))
		_materials[key] = material
	return _materials[key]


## A part's box around its pivot, with the skin's unfolded faces.
static func part_mesh(mob: String, part: Dictionary) -> ArrayMesh:
	return _mesh(mob, part)


## A part's box around its pivot, with the skin's unfolded faces.
static func _mesh(mob: String, part: Dictionary) -> ArrayMesh:
	var texture: String = part.get("texture", mob)
	var translucent: bool = part.get("translucent", false)
	var key := "%s/%s/%s/%s/%s/%s/%s" % [mob, part.name, texture, part.get("inflate", 0.0), part.uv, part.get("mirror", false), translucent]
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
	mesh.surface_set_material(0, _material(texture, translucent))
	_meshes[key] = mesh
	return mesh
