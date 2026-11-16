class_name HitboxView
extends MeshInstance3D
## Entity hitboxes like the modern game's F3+B (debug builds only,
## DebugScreen): a white box around every creature, cart, boat, arrow,
## dropped item and network player near the camera, a red rectangle at
## a creature's eye height and a blue line 2 blocks long where it looks.
## Lines drawn where the entities are drawn this frame.

const REACH := 64.0
const BOX := Color.WHITE
const EYES := Color(1, 0, 0)
const LOOK := Color(0, 0, 1)

var world: VoxelWorld
var _lines := ImmediateMesh.new()


func _ready() -> void:
	mesh = _lines
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material_override = material
	visible = false


func _process(_delta: float) -> void:
	_lines.clear_surfaces()
	if not visible or world == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var eye := camera.global_position
	_lines.surface_begin(Mesh.PRIMITIVE_LINES)
	var any := false
	for entity in world.entities.all():
		if entity.removed or entity.global_position.distance_to(eye) > REACH:
			continue
		var at := entity.global_position
		_box(AABB(at - Vector3(entity.half_width, 0, entity.half_width), Vector3(entity.half_width * 2.0, entity.height, entity.half_width * 2.0)), BOX)
		any = true
		if entity is Mob:
			var mob := entity as Mob
			var eyes := at + Vector3(0, mob.height * 0.85, 0)
			_box(AABB(eyes - Vector3(mob.half_width, 0.01, mob.half_width), Vector3(mob.half_width * 2.0, 0.02, mob.half_width * 2.0)), EYES)
			_line(eyes, eyes + mob.look_direction() * 2.0, LOOK)
	for point in world.items.positions():
		if point.distance_to(eye) <= REACH:
			_box(AABB(point - Vector3(0.125, 0.125, 0.125), Vector3(0.25, 0.25, 0.25)), BOX)
			any = true
	for avatar: RemotePlayer in Net.avatars.values():
		if is_instance_valid(avatar) and not avatar.dead and avatar.global_position.distance_to(eye) <= REACH:
			_box(AABB(avatar.global_position - Vector3(0.3, 0, 0.3), Vector3(0.6, 1.8, 0.6)), BOX)
			any = true
	if not any:
		_line(Vector3.ZERO, Vector3.ZERO, BOX) # (a surface can't be empty)
	_lines.surface_end()


func _line(a: Vector3, b: Vector3, color: Color) -> void:
	_lines.surface_set_color(color)
	_lines.surface_add_vertex(a)
	_lines.surface_set_color(color)
	_lines.surface_add_vertex(b)


func _box(box: AABB, color: Color) -> void:
	var p := box.position
	var e := box.end
	var corners := [Vector3(p.x, p.y, p.z), Vector3(e.x, p.y, p.z), Vector3(e.x, p.y, e.z), Vector3(p.x, p.y, e.z),
		Vector3(p.x, e.y, p.z), Vector3(e.x, e.y, p.z), Vector3(e.x, e.y, e.z), Vector3(p.x, e.y, e.z)]
	for edge: Vector2i in [Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 0), Vector2i(4, 5), Vector2i(5, 6),
			Vector2i(6, 7), Vector2i(7, 4), Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7)]:
		_line(corners[edge.x], corners[edge.y], color)
