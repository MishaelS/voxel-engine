class_name Painting
extends Entity
## Paintings like the classic game (EntityPainting): right-clicking the side
## of a block with a painting hangs one there, picked at random among the
## pictures that fit (solid wall behind every block of it, nothing in front,
## no other painting in the way). Hitting it, or losing the wall behind,
## drops it as an item. Our own pictures, at the places of Beta 1.7.3's in
## art/kz.png (a texture pack's kz.png shows its pictures), 1x1 to 4x4 blocks.

const ATLAS := "res://assets/textures/art/kz.png"
## name -> [width, height (blocks), cell x, cell y (16 px cells)].
const ARTS := {
	"sunrise": [1, 1, 0, 0], "lake": [1, 1, 1, 0], "flower": [1, 1, 2, 0], "tower": [1, 1, 3, 0],
	"moon": [1, 1, 4, 0], "forest_path": [1, 1, 5, 0], "star": [1, 1, 6, 0],
	"hills": [2, 1, 0, 2], "sea": [2, 1, 2, 2], "desert": [2, 1, 4, 2], "road": [2, 1, 6, 2], "clouds": [2, 1, 8, 2],
	"waterfall": [1, 2, 0, 4], "tree": [1, 2, 1, 4],
	"mountain": [2, 2, 0, 8], "village": [2, 2, 2, 8], "storm": [2, 2, 4, 8], "garden": [2, 2, 6, 8],
	"panorama": [4, 2, 0, 6], "river_valley": [4, 3, 12, 4], "night_sky": [4, 4, 0, 12], "volcano": [4, 4, 4, 12],
	# Beta's places the game has no picture for: hung when a texture pack's
	# kz.png has one there.
	"spare_2x2": [2, 2, 8, 8], "spare_4x3": [4, 3, 12, 7], "spare_4x4": [4, 4, 8, 12],
}
const SPARE: Array[String] = ["spare_2x2", "spare_4x3", "spare_4x4"]
static var _empty := {} # spare pictures the texture has nothing at


## Whether a picture can be hung (the spare places: only with a picture there).
static func _drawn(name: String) -> bool:
	if not name in SPARE:
		return true
	if not _empty.has(name):
		var size: Array = ARTS[name]
		var image := TexturePacks.load_image(ATLAS)
		var cell := image.get_size().x / 16
		var rect := Rect2i(int(size[2]) * cell, int(size[3]) * cell, int(size[0]) * cell, int(size[1]) * cell)
		_empty[name] = image.get_region(rect).is_invisible()
	return not _empty[name]
const DEPTH := 1.0 / 16.0

static var _material: ShaderMaterial

var art := "sunrise"
## The direction it faces (away from the wall): one of the 4 horizontals.
var facing := Vector3i(0, 0, 1)
## The block in front of the wall at its lower left (seen from the front).
var anchor := Vector3i.ZERO

var _check := 0


## Hangs a painting on the face `normal` of the wall block `wall`, or
## returns null if no picture fits there.
static func hang(world: VoxelWorld, wall: Vector3i, normal: Vector3i) -> Painting:
	if normal.y != 0 or normal == Vector3i.ZERO:
		return null
	var fitting: Array[String] = []
	for name: String in ARTS:
		if _drawn(name) and _fits(world, name, wall + normal, normal):
			fitting.append(name)
	if fitting.is_empty():
		return null
	var painting := Painting.new()
	painting.art = fitting[randi_range(0, fitting.size() - 1)]
	painting.facing = normal
	painting.anchor = _anchor_for(painting.art, wall + normal, normal)
	world.entities.spawn(painting, painting._center())
	return painting


## The blocks right of the front, seen from the front.
static func _right_of(normal: Vector3i) -> Vector3i:
	return Vector3i(-normal.z, 0, normal.x)


## Centered on the clicked block like the game (wider ones lean left).
static func _anchor_for(name: String, front: Vector3i, normal: Vector3i) -> Vector3i:
	var size: Array = ARTS[name]
	var right := _right_of(normal)
	return front - right * ((int(size[0]) - 1) / 2) - Vector3i(0, (int(size[1]) - 1) / 2, 0)


static func _fits(world: VoxelWorld, name: String, front: Vector3i, normal: Vector3i, except: Painting = null) -> bool:
	var size: Array = ARTS[name]
	var anchor_cell := _anchor_for(name, front, normal)
	var right := _right_of(normal)
	for x in int(size[0]):
		for y in int(size[1]):
			var cell := anchor_cell + right * x + Vector3i(0, y, 0)
			var behind := world.get_block(cell - normal)
			if Blocks.collides_table[behind] == 0 or Blocks.liquid_table[behind] == 1:
				return false
			var here := world.get_block(cell)
			if here != Blocks.AIR and Blocks.collides_table[here] == 1:
				return false
			for other in world.entities.all():
				if other is Painting and other != except and not other.removed and (other as Painting).covers(cell):
					return false
	return true


## Whether it hangs in front of `cell`.
func covers(cell: Vector3i) -> bool:
	var size: Array = ARTS[art]
	var local := cell - anchor
	var right := _right_of(facing)
	var along := local.x * right.x + local.z * right.z
	return local - right * along == Vector3i(0, local.y, 0) and along >= 0 and along < int(size[0]) \
		and local.y >= 0 and local.y < int(size[1])


## The middle of its back, against the wall (the node's place).
func _center() -> Vector3:
	var size: Array = ARTS[art]
	var right := Vector3(_right_of(facing))
	return Vector3(anchor) + Vector3(0.5, 0, 0.5) - Vector3(facing) * 0.5 + right * (float(size[0]) / 2.0 - 0.5) \
		+ Vector3(0, float(size[1]) / 2.0, 0)


func type_name() -> String:
	return "painting"


func _ready() -> void:
	gravity = 0.0
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://shaders/mob.gdshader")
		_material.set_shader_parameter("skin", TexturePacks.load_texture(ATLAS))
	_build()


func _build() -> void:
	for child in get_children():
		child.queue_free()
	var size: Array = ARTS[art]
	var w := float(size[0])
	var h := float(size[1])
	var front := Rect2(float(size[2]) * 16.0, float(size[3]) * 16.0, w * 16.0, h * 16.0)
	var back := Rect2(192, 0, 16, 16) # (Beta's back of the pictures)
	# Built facing +Z, then turned to its facing.
	var x0 := -w / 2.0
	var x1 := w / 2.0
	var y0 := -h / 2.0
	var y1 := h / 2.0
	var faces := [
		[[Vector3(x0, y1, DEPTH), Vector3(x1, y1, DEPTH), Vector3(x1, y0, DEPTH), Vector3(x0, y0, DEPTH)], Vector3.BACK, front],
		[[Vector3(x1, y1, 0), Vector3(x0, y1, 0), Vector3(x0, y0, 0), Vector3(x1, y0, 0)], Vector3.FORWARD, back],
		[[Vector3(x0, y1, 0), Vector3(x1, y1, 0), Vector3(x1, y1, DEPTH), Vector3(x0, y1, DEPTH)], Vector3.UP, back],
		[[Vector3(x0, y0, DEPTH), Vector3(x1, y0, DEPTH), Vector3(x1, y0, 0), Vector3(x0, y0, 0)], Vector3.DOWN, back],
		[[Vector3(x0, y1, 0), Vector3(x0, y1, DEPTH), Vector3(x0, y0, DEPTH), Vector3(x0, y0, 0)], Vector3.LEFT, back],
		[[Vector3(x1, y1, DEPTH), Vector3(x1, y1, 0), Vector3(x1, y0, 0), Vector3(x1, y0, DEPTH)], Vector3.RIGHT, back],
	]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for face: Array in faces:
		var start := vertices.size()
		var rect: Rect2 = face[2]
		for k in 4:
			vertices.append(face[0][k])
			normals.append(face[1])
			uvs.append((rect.position + rect.size * [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)][k]) / 256.0)
		indices.append_array([start, start + 1, start + 2, start, start + 2, start + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.rotation.y = atan2(float(facing.x), float(facing.z))
	add_child(instance)


## Hangs still; every 100 ticks checks it still has its wall.
func tick() -> void:
	_prev = Vector3(_x, _y, _z)
	age += 1
	_check += 1
	if _check >= 100:
		_check = 0
		if not _fits(world, art, anchor + _right_of(facing) * ((int(ARTS[art][0]) - 1) / 2) + Vector3i(0, (int(ARTS[art][1]) - 1) / 2, 0), facing, self):
			drop()


## A thin board on the wall.
func hit_box() -> AABB:
	var size: Array = ARTS[art]
	var right := Vector3(_right_of(facing)).abs()
	var out := Vector3(facing).abs()
	var extent := right * float(size[0]) + Vector3(0, float(size[1]), 0) + out * DEPTH
	var center := _center() + Vector3(facing) * DEPTH * 0.5
	return AABB(center - extent / 2.0, extent)


## Any hit takes it down.
func damage(_amount: int, _from: Variant = null) -> bool:
	drop()
	return true


func drop() -> void:
	if removed:
		return
	removed = true
	var player := world.player as Player
	if player == null or not player.is_creative():
		world.items.spawn(Items.id_of("painting"), 1, _center() + Vector3(facing) * 0.3)


func _process(_delta: float) -> void:
	global_position = Vector3(_x, _y, _z)
	if world:
		var light := world.brightness_at(_center() + Vector3(facing) * 0.5)
		for child in get_children():
			if child is MeshInstance3D:
				(child as MeshInstance3D).set_instance_shader_parameter("brightness", light)


func save_state() -> Dictionary:
	var state := super()
	state.merge({"art": art, "facing": facing, "anchor": anchor}, true)
	return state


func load_state(state: Dictionary) -> void:
	super(state)
	art = state.get("art", art)
	if not ARTS.has(art):
		art = "sunrise"
	facing = state.get("facing", facing)
	anchor = state.get("anchor", anchor)
	_build()
