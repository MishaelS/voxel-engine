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
##   outer jelly);
## - "glow": always fully lit, whatever the light (the spider's eyes, like
##   Beta's spider_eyes.png layer); its mesh has the "glow" meta.

const MODELS_PATH := "res://assets/models/mobs.json"
const SKINS := "res://assets/textures/"
## The skins' files, where Beta 1.7.3 has them (TexturePacks): mob/<name>.png
## unless named here.
const SKIN_FILES := {
	"player": "mob/char.png", "pale_wolf": "mob/wolf.png", "saddle_pig": "mob/saddle.png",
	"boat": "item/boat.png", "minecart": "item/cart.png",
	"creeper_power": "armor/power.png",
}


## A skin's file: mob/zombie.png, armor/iron_1.png (armor_iron_1)...
static func skin_path(texture: String) -> String:
	if SKIN_FILES.has(texture):
		return SKINS + SKIN_FILES[texture]
	if texture.begins_with("armor_"):
		var parts := texture.split("_") # armor_<material>_<1|2>
		var material: String = {"leather": "cloth", "chainmail": "chain", "golden": "gold"}.get(parts[1], parts[1])
		return SKINS + "armor/%s_%s.png" % [material, parts[2]]
	return SKINS + "mob/" + texture + ".png"

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
		if part.get("glow", false):
			instance.set_meta("glow", true)
		instances[part.name] = instance
		meshes.append(instance)
	return {"root": root, "parts": parts, "meshes": meshes, "instances": instances, "spec": spec}


## Items held like the game's (tools, sticks, bones, rods): pointing
## forward from the fist rather than held up as a picture.
const HELD_LIKE_TOOLS := ["_sword", "_pickaxe", "_axe", "_shovel", "_hoe", "stick", "bone", "fishing_rod"]


## An item in a creature's (or the player's) right hand, to be added to the
## model's right arm part (pixel units, the arm hanging down): a bow held
## by its grip with the string toward the body, tools pointing forward
## from the fist, other items and blocks small in the hand. Returns null
## for nothing.
static func held_item(mob: String, item_id: int) -> MeshInstance3D:
	if item_id == Blocks.AIR or item_id < 0:
		return null
	var has_arm := false
	for part: Dictionary in model(mob).parts:
		has_arm = has_arm or part.name == "right_arm"
	if not has_arm:
		return null
	var mesh := MeshInstance3D.new()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Beta's RenderPlayer / RenderBiped.renderEquippedItems, step by step
	# (OpenGL's order: each step applies to what follows), in its model's
	# axes (y down, the front toward -z) and blocks.
	var gl := _gl_move(-0.0625, 0.4375, 0.0625) # (the hand, from the arm's pivot)
	var picture: Transform3D # the mesh's own place in what Beta draws
	if not ItemMeshes.is_flat(item_id):
		mesh.mesh = FallingBlocks.block_mesh(item_id)
		mesh.set_meta("block", true) # lit through entity_light (FallingBlocks.light)
		gl = gl * _gl_move(0, 0.1875, -0.3125) * _gl_turn(20, Vector3.RIGHT) * _gl_turn(45, Vector3.UP) \
			* Transform3D(Basis.from_scale(Vector3(0.375, -0.375, 0.375)), Vector3.ZERO)
		picture = _gl_move(-0.5, -0.5, -0.5) # (renderBlockOnInventory: a cube around its middle)
	else:
		mesh.mesh = ItemMeshes.extruded(item_id, ItemEntities._flat_material(item_id))
		var name := Items.name_of(item_id)
		if name == "bow": # (skeletons hold it like the player: RenderPlayer's bow)
			gl = gl * _gl_move(0, 0.125, 0.3125) * _gl_turn(-20, Vector3.UP) \
				* Transform3D(Basis.from_scale(Vector3(0.625, -0.625, 0.625)), Vector3.ZERO) \
				* _gl_turn(-100, Vector3.RIGHT) * _gl_turn(45, Vector3.UP)
		elif HELD_LIKE_TOOLS.any(func(suffix: String) -> bool: return name.ends_with(suffix)):
			if name == "fishing_rod":
				gl = gl * _gl_turn(180, Vector3.BACK) * _gl_move(0, -0.125, 0)
			gl = gl * _gl_move(0, 0.1875, 0) * Transform3D(Basis.from_scale(Vector3(0.625, -0.625, 0.625)), Vector3.ZERO) \
				* _gl_turn(-100, Vector3.RIGHT) * _gl_turn(45, Vector3.UP)
		else:
			gl = gl * _gl_move(0.25, 0.1875, -0.1875) * Transform3D(Basis.from_scale(Vector3.ONE * 0.375), Vector3.ZERO) \
				* _gl_turn(60, Vector3.BACK) * _gl_turn(-90, Vector3.RIGHT) * _gl_turn(20, Vector3.BACK)
		# ItemRenderer.renderItem's flat picture: 1.5 blocks, turned, then a
		# square 0..1 seen right from -z (the mesh: from +z, its back at 0).
		gl = gl * _gl_move(0, -0.3, 0) * Transform3D(Basis.from_scale(Vector3.ONE * 1.5), Vector3.ZERO) \
			* _gl_turn(50, Vector3.UP) * _gl_turn(335, Vector3.BACK) * _gl_move(-0.9375, -0.0625, 0)
		picture = Transform3D(Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)), Vector3(1, 0, 0))
	# Beta's axes -> the model's (y up, the front toward +z: turned half
	# around x), blocks -> pixels.
	var axes := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1)).scaled(Vector3.ONE * 16.0), Vector3.ZERO)
	mesh.transform = axes * gl * picture
	return mesh


## Armor slot -> [[model part, texture layer, inflate, uv, mirrored], ...]
## (the left limbs use the right ones' texture, mirrored, like the game).
const ARMOR_PARTS := [
	[["head", 1, 1.0, [0, 0], false]],
	[["body", 1, 1.0, [16, 16], false], ["right_arm", 1, 1.0, [40, 16], false], ["left_arm", 1, 1.0, [40, 16], true]],
	[["body", 2, 0.5, [16, 16], false], ["right_leg", 2, 0.5, [0, 16], false], ["left_leg", 2, 0.5, [0, 16], true]],
	[["right_leg", 1, 1.0, [0, 16], false], ["left_leg", 1, 1.0, [0, 16], true]],
]


## The worn armor (`armor`: 4 slots, helmet first) drawn over a biped
## model (the player's, zombies', skeletons') like the game's armor layers:
## the player's own boxes (helmet, chestplate and boots 1 pixel bigger,
## leggings half a pixel; textures armor_<material>_1 / _2) on the model's
## parts, so a skeleton's armor is the size of the player's. Returns the
## pieces made (the caller lights them and frees them).
static func armor_pieces(built: Dictionary, armor: Inventory) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	var boxes := {}
	for part: Dictionary in model("player").parts:
		boxes[part.name] = part
	for slot in mini(armor.size(), ARMOR_PARTS.size()):
		var item := Items.get_type(armor.id_at(slot)) if armor.count_at(slot) > 0 else null
		if item == null or item.armor_slot != slot:
			continue
		for piece: Array in ARMOR_PARTS[slot]:
			if not boxes.has(piece[0]) or not (built.parts as Dictionary).has(piece[0]):
				continue
			var part: Dictionary = (boxes[piece[0]] as Dictionary).duplicate()
			part.texture = "armor_%s_%d" % [item.armor_material, piece[1]]
			part.inflate = piece[2]
			part.uv = piece[3]
			part.mirror = piece[4]
			var instance := MeshInstance3D.new()
			instance.mesh = part_mesh("player", part)
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(built.parts[piece[0]] as Node3D).add_child(instance)
			result.append(instance)
	return result


## A charged creeper's glow (Beta's RenderCreeper): every part of its
## model POWER_SHELL pixels bigger with armor/power.png sliding over it, added to what
## is behind (shaders/creeper_power.gdshader; `material` shared, its ticks
## set each frame). Returns the pieces made.
static func power_shell(built: Dictionary, material: ShaderMaterial) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for part: Dictionary in (built.spec as Dictionary).parts:
		if not (built.parts as Dictionary).has(part.name):
			continue
		var shell := part.duplicate()
		shell.texture = "creeper_power"
		shell.inflate = float(part.get("inflate", 0.0)) + POWER_SHELL
		var instance := MeshInstance3D.new()
		instance.mesh = part_mesh("creeper", shell)
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(built.parts[part.name] as Node3D).add_child(instance)
		result.append(instance)
	return result


## How far the glow stands out from the body (pixels; Beta's 2, ours a
## little closer).
const POWER_SHELL := 1.0
static var _power_material: ShaderMaterial


## The glow's material (one for every charged creeper).
static func power_material() -> ShaderMaterial:
	if _power_material == null:
		_power_material = ShaderMaterial.new()
		_power_material.shader = preload("res://shaders/creeper_power.gdshader")
		_power_material.set_shader_parameter("skin", skin_texture("creeper_power"))
	return _power_material


## A held item's place when the arms are raised straight forward
## (MobAnimation: turned -90 degrees about x): a bow is rolled a little
## about the hand, so it stands upright in front of the creature; the rest
## stay as they are on the arm.
static func aimed_transform(item_id: int, held: Transform3D) -> Transform3D:
	if Items.name_of(item_id) != "bow":
		return held
	var arm := Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3.ZERO)
	var hand := Vector3(0, 0, 10) # (the arm's end, from its pivot, in the model's axes)
	var roll := Transform3D(Basis.IDENTITY, hand) * Transform3D(Basis(Vector3.BACK, deg_to_rad(BOW_ROLL)), Vector3.ZERO) \
		* Transform3D(Basis.IDENTITY, -hand)
	return arm.affine_inverse() * roll * arm * held
## How far their bow is rolled upright (degrees, about the hand).
const BOW_ROLL := 30.0


static func _gl_move(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(x, y, z))


static func _gl_turn(degrees: float, axis: Vector3) -> Transform3D:
	return Transform3D(Basis(axis, deg_to_rad(degrees)), Vector3.ZERO)


static func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


## A skin's size in pixels (64 x 64, or 64 x 32 for the classic ones).
static func _skin_size(texture: String) -> Vector2:
	var image := default_skin(texture)
	return Vector2(image.get_size()) if image else Vector2(64, 64)


static func _material(texture: String, translucent: bool = false) -> ShaderMaterial:
	var key := texture + ("#translucent" if translucent else "")
	if not _materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/mob_translucent.gdshader") if translucent else preload("res://shaders/mob.gdshader")
		material.set_shader_parameter("skin", skin_texture(texture))
		_materials[key] = material
	return _materials[key]


## Skins replaced at run time (the player's own skin, PlayerProfile).
static var _skin_overrides := {}


## A model's skin: the replacement if there is one, else its file.
static func skin_texture(texture: String) -> Texture2D:
	if _skin_overrides.has(texture):
		return _skin_overrides[texture]
	return default_skin(texture)


static func default_skin(texture: String) -> Texture2D:
	var skin := TexturePacks.load_texture(skin_path(texture))
	if texture == "player" and skin and skin.get_height() == 32:
		# A texture pack's classic 64 x 32 char.png: widened like the
		# player's own skins (the left arm and leg copied).
		if not _wide_skins.has(skin):
			var image := skin.get_image()
			PlayerProfile.normalize_skin(image)
			_wide_skins[skin] = ImageTexture.create_from_image(image)
		return _wide_skins[skin]
	return skin


static var _wide_skins := {}


## The material of `texture`'s parts drawn with another skin of the same
## layout (a wolf's tame and angry skins), kept for all of them.
static func state_material(texture: String, skin: String) -> ShaderMaterial:
	var key := texture + "@" + skin
	if not _materials.has(key):
		_materials[key] = material_with_skin(texture, default_skin(skin))
	return _materials[key]


## Replaces a model's skin everywhere it is drawn (null: back to its file).
static func set_skin(texture: String, skin: Texture2D) -> void:
	if skin:
		_skin_overrides[texture] = skin
	else:
		_skin_overrides.erase(texture)
	for key: String in _materials:
		if key == texture or key.begins_with(texture + "#"):
			(_materials[key] as ShaderMaterial).set_shader_parameter("skin", skin_texture(texture))


## A material of a model with another skin (another player's).
static func material_with_skin(texture: String, skin: Texture2D) -> ShaderMaterial:
	var material := _material(texture).duplicate() as ShaderMaterial
	material.set_shader_parameter("skin", skin if skin else default_skin(texture))
	return material


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
			var corner_uv: Vector2 = corner_uvs[k]
			if face[1] == Vector3.DOWN:
				# Like the game's ModelBox: the bottom square lies the same way as
				# the top one (seen from below: flipped); the cow's, pig's and
				# sheep's rear is this face of their turned body.
				corner_uv.y = 1.0 - corner_uv.y
			vertices.append(face[0][k])
			normals.append(face[1])
			uvs.append((rect.position + rect.size * corner_uv) / skin)
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
