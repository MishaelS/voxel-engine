class_name BlockInteraction
extends Node3D
## What the player does with blocks (with the mouse captured), like the
## classic game:
## - LMB: break the targeted block. Creative: instantly (holding repeats
##   every 5 ticks). Survival: hold it until the block breaks (hardness x
##   1.5 seconds by hand, cracks show the progress), then it goes into the
##   inventory (stone gives cobblestone, glass and leaves nothing).
##   Unbreakable blocks (bedrock) never break in survival.
## - RMB: place the selected hotbar block on the targeted face (holding
##   repeats every 4 ticks). Survival uses up one item.
## - MMB: pick the targeted block (see Hotbar.pick).
## - 1-9 and the mouse wheel choose the hotbar slot.
## The targeted block gets a thin black outline.

const TICK := 1.0 / 20.0
const BREAK_DELAY_TICKS := 5
const PLACE_DELAY_TICKS := 4
## Breaking speed by hand: progress per tick = 1 / (hardness * 30).
const HAND_BREAK_FACTOR := 30.0
## Atlas tiles of the 10 crack stages.
const CRACK_TILE := 240

@export var player: Player
@export var world: VoxelWorld
@export var hotbar: Hotbar

## Current raycast result (see VoxelWorld.raycast), read by the debug screen.
var target := {}
## Survival breaking progress of `target` (0..1).
var break_progress := 0.0

var _outline: MeshInstance3D
var _cracks: MeshInstance3D
var _crack_material: ShaderMaterial
var _breaking_pos := Vector3i(0, -1000, 0)
var _break_delay := 0.0 # ticks
var _place_delay := 0.0 # ticks


func _ready() -> void:
	_outline = MeshInstance3D.new()
	_outline.mesh = _make_outline_mesh()
	_outline.visible = false
	add_child(_outline)
	_cracks = MeshInstance3D.new()
	_cracks.mesh = _make_crack_mesh()
	_cracks.visible = false
	_cracks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cracks)


func _process(delta: float) -> void:
	target = world.raycast(player.eye_position(), player.look_direction(), player.reach()) if player and world else {}
	var hit: bool = target.get("hit", false)
	_outline.visible = hit
	if hit:
		_outline.global_position = Vector3(target.pos)

	var ticks := delta / TICK
	_break_delay = maxf(_break_delay - ticks, 0.0)
	_place_delay = maxf(_place_delay - ticks, 0.0)
	var active := _captured() and not GameInput.is_blocked()
	if active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and hit:
		_continue_breaking(target.pos, ticks)
	else:
		_stop_breaking()
	if active and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and _place_delay <= 0.0:
		_place()
		_place_delay = PLACE_DELAY_TICKS


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
			hotbar.scroll(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
			get_viewport().set_input_as_handled()
		MOUSE_BUTTON_LEFT:
			if _captured():
				_break_delay = 0.0 # a fresh click breaks right away in creative
				get_viewport().set_input_as_handled()
		MOUSE_BUTTON_RIGHT:
			if _captured():
				_place_delay = 0.0
				get_viewport().set_input_as_handled()
		MOUSE_BUTTON_MIDDLE:
			if _captured() and target.get("hit", false):
				hotbar.pick(target.block)
				get_viewport().set_input_as_handled()


func _captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


# --- Breaking ---------------------------------------------------------------------

func _continue_breaking(pos: Vector3i, ticks: float) -> void:
	if _break_delay > 0.0:
		return
	if player.is_creative():
		world.set_block(pos, Blocks.AIR)
		_break_delay = BREAK_DELAY_TICKS
		return
	var hardness := Blocks.get_type(world.get_block(pos)).hardness
	if hardness < 0.0:
		_stop_breaking()
		return
	if pos != _breaking_pos:
		_breaking_pos = pos
		break_progress = 0.0
	break_progress += ticks / maxf(hardness * HAND_BREAK_FACTOR, 0.001)
	if break_progress >= 1.0:
		var id := world.get_block(pos)
		world.set_block(pos, Blocks.AIR)
		player.inventory.add(Blocks.drop_of(id), 1)
		_stop_breaking()
		_break_delay = BREAK_DELAY_TICKS
		return
	_cracks.visible = true
	_cracks.global_position = Vector3(pos)
	_crack_material.set_shader_parameter("stage", CRACK_TILE + mini(int(break_progress * 10.0), 9))


func _stop_breaking() -> void:
	break_progress = 0.0
	_breaking_pos = Vector3i(0, -1000, 0)
	_cracks.visible = false


# --- Placing -----------------------------------------------------------------------

func _place() -> void:
	if not target.get("hit", false) or target.normal == Vector3i.ZERO:
		return
	var id := hotbar.selected_block()
	if id == Blocks.AIR:
		return
	var pos: Vector3i = target.pos + target.normal
	var current := world.get_block(pos)
	if not world.is_inside(pos) or Blocks.collides_table[current] == 1:
		return
	if Blocks.collides_table[id] == 1 and player.intersects_block(pos):
		return # not inside the player
	world.set_block(pos, id)
	if not player.is_creative():
		player.inventory.take(hotbar.selected)


# --- Meshes --------------------------------------------------------------------------

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


## A block cube (the mesher's, so UVs are 0..1 per face) slightly enlarged,
## drawn with the crack texture multiplied over the block.
func _make_crack_mesh() -> ArrayMesh:
	_crack_material = ShaderMaterial.new()
	_crack_material.shader = preload("res://shaders/block_cracks.gdshader")
	_crack_material.set_shader_parameter("tiles",
		BlockMaterials.get_material(Blocks.Layer.OPAQUE).get_shader_parameter("tiles"))
	var surfaces := ChunkMesher.build(ChunkMesher.single_block(Blocks.id_of("stone")), ChunkMesher.full_light())
	var arrays: Array = surfaces[Blocks.Layer.OPAQUE]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in vertices.size():
		vertices[i] = (vertices[i] - Vector3(0.5, 0.5, 0.5)) * 1.004 + Vector3(0.5, 0.5, 0.5)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _crack_material)
	return mesh
