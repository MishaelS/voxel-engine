class_name BlockInteraction
extends Node3D
## What the player does with blocks (with the mouse captured):
## LMB breaks the targeted block, RMB places the selected hotbar block on
## its face, MMB picks the targeted block into the hotbar. 1-9 and the
## mouse wheel choose the hotbar slot. The targeted block gets a thin
## black outline, like the classic game.

@export var camera: Camera3D
@export var world: VoxelWorld
@export var hotbar: Hotbar
## How far blocks can be reached (5 in creative mode).
@export var reach: float = 5.0

## Current raycast result (see VoxelWorld.raycast), read by the debug screen.
var target := {}

var _outline: MeshInstance3D
var _water := -1


func _ready() -> void:
	_water = Blocks.id_of("water")
	_outline = MeshInstance3D.new()
	_outline.mesh = _make_outline_mesh()
	_outline.visible = false
	add_child(_outline)


func _process(_delta: float) -> void:
	target = world.raycast(camera.global_position, -camera.global_basis.z, reach) if camera and world else {}
	_outline.visible = target.get("hit", false)
	if _outline.visible:
		_outline.global_position = Vector3(target.pos)


func _unhandled_input(event: InputEvent) -> void:
	if GameInput.is_blocked():
		return
	for i in Hotbar.SLOT_COUNT:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			hotbar.select(i)
			get_viewport().set_input_as_handled()
			return
	if not (event is InputEventMouseButton and event.pressed):
		return
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if not event.ctrl_pressed: # Ctrl + wheel = fly speed (FreeCamera)
				hotbar.scroll(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
				get_viewport().set_input_as_handled()
		MOUSE_BUTTON_LEFT:
			if _captured() and target.get("hit", false):
				world.set_block(target.pos, Blocks.AIR)
				get_viewport().set_input_as_handled()
		MOUSE_BUTTON_RIGHT:
			if _captured():
				_place()
				get_viewport().set_input_as_handled()
		MOUSE_BUTTON_MIDDLE:
			if _captured() and target.get("hit", false):
				hotbar.pick(target.block)
				get_viewport().set_input_as_handled()


func _captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _place() -> void:
	if not target.get("hit", false) or target.normal == Vector3i.ZERO:
		return
	var pos: Vector3i = target.pos + target.normal
	var current := world.get_block(pos)
	if not world.is_inside(pos) or (current != Blocks.AIR and current != _water):
		return
	if pos == Vector3i(camera.global_position.floor()):
		return # not inside the player
	world.set_block(pos, hotbar.selected_block())


## The 12 edges of a block, slightly enlarged to avoid z-fighting.
static func _make_outline_mesh() -> ImmediateMesh:
	const E := 0.002
	var corners: Array[Vector3] = []
	for i in 8:
		corners.append(Vector3(1.0 + E if i & 1 else -E, 1.0 + E if i & 2 else -E, 1.0 + E if i & 4 else -E))
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0, 0, 0, 0.6)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for a in 8:
		for bit in [1, 2, 4]:
			if a & bit == 0:
				mesh.surface_add_vertex(corners[a])
				mesh.surface_add_vertex(corners[a | bit])
	mesh.surface_end()
	return mesh
