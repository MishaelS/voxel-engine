class_name InventoryPlayerView
extends TextureRect
## The player standing in the black box of the survival inventory, like
## Beta 1.7.3's GuiInventory: the same model as the third-person view
## (PlayerModel: skin, armor, the item in hand), 30 window pixels to a
## block with the feet at (51, 75) of the window, turning toward the mouse
## (the body by atan(dx / 40) * 20 degrees, the head twice as far, the
## head and the whole figure tilting by atan(dy / 40) * 20) and lit by
## the standard item lighting (shaders/mob_gui.gdshader). Drawn in its own
## 3D world through a SubViewport at the screen's resolution, so the
## skin's pixels stay sharp at any GUI scale; the limbs keep still apart
## from the idle arm sway.

## The part of the window (texture pixels) the picture covers: the black
## box (26, 8, 52 x 70) inside its frame; what reaches out of it (a sword
## in the hand, an arm turned aside) is cut off at the box's edge.
const AREA := Rect2i(26, 8, 52, 70)
## Where the feet stand and where the eyes are taken to be (texture pixels).
const FEET := Vector2(51, 71)
const EYES := Vector2(51, 21)
## Window pixels to a block (GuiInventory's glScalef(30)).
const SCALE := 30.0
const P := UiTheme.PIXEL

var player: Player
var _viewport: SubViewport
var _camera: Camera3D
var _tilt: Node3D # turned around x toward the mouse, at the feet
var _model: PlayerModel
var _materials := {} # the model's ShaderMaterial -> the same skin with mob_gui


func _ready() -> void:
	position = Vector2(AREA.position) * P
	size = Vector2(AREA.size) * P
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true # (the game's world is not drawn in it)
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.size = AREA.size.y / SCALE
	# Looking along -z at the area's middle; the feet are the world's origin.
	var middle := Vector2(AREA.position) + Vector2(AREA.size) / 2.0
	_camera.position = Vector3((middle.x - FEET.x) / SCALE, (FEET.y - middle.y) / SCALE, 10)
	_camera.far = 20.0
	_viewport.add_child(_camera)
	_tilt = Node3D.new()
	_viewport.add_child(_tilt)
	_model = PlayerModel.new()
	_model.player = player
	_tilt.add_child(_model)
	# Posed here instead of by its own _process (that one follows the
	# player in the world: walking, the view, the light where it stands).
	_model.set_process(false)
	texture = _viewport.get_texture()
	_update()


func _process(_delta: float) -> void:
	# Drawn only while the window is open.
	var mode := SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	if _viewport.render_target_update_mode != mode:
		_viewport.render_target_update_mode = mode
	if mode == SubViewport.UPDATE_ALWAYS:
		_update()


func _update() -> void:
	if player == null:
		return
	# The picture at the screen's own pixels (the GUI scale may change).
	var to_screen := get_viewport().get_final_transform() * get_global_transform_with_canvas()
	var pixels := Vector2i((size * to_screen.get_scale()).round())
	if _viewport.size != pixels and pixels.x > 0 and pixels.y > 0:
		_viewport.size = pixels
	var mouse := (get_parent() as Control).get_local_mouse_position() / P
	var dx := FEET.x - mouse.x
	var dy := EYES.y - mouse.y
	var turn := atan(dx / 40.0) * deg_to_rad(20.0)
	var tilt := -atan(dy / 40.0) * deg_to_rad(20.0)
	_tilt.rotation.x = tilt
	# PlayerModel faces -z; half a turn faces it to the camera.
	_model.rotation.y = PI - turn
	# (PlayerModel's own pieces: the held item, the parts, the armor.)
	_model._update_held()
	_model._update_carry()
	var parts: Dictionary = _model._model.parts
	MobAnimation.pose_biped(parts, Time.get_ticks_msec() / 50.0, 0.0, 0.0, _model._held != null, 0.0, 0.0, 0.0)
	if _model._carry:
		PlayerModel.carry_arms(parts)
		FallingBlocks.light(_model._carry, 1.0)
	var head := parts.head as Node3D
	head.rotation = Vector3(tilt, -turn, 0)
	if _model._held:
		FallingBlocks.light(_model._held, 1.0)
	if _model._pumpkin:
		_model._pumpkin.set_instance_shader_parameter("entity_light", 1.0)
	var hurt := 1.0 if player.hurt_ticks > 0 else 0.0
	for mesh: MeshInstance3D in _model._model.meshes + _model._armor_meshes:
		if not is_instance_valid(mesh) or mesh.is_queued_for_deletion():
			continue
		mesh.material_override = _gui_material(mesh.mesh.surface_get_material(0) as ShaderMaterial)
		mesh.set_instance_shader_parameter("hurt", hurt)


## The skin of a model's material, lit like the inventory's (cached).
func _gui_material(material: ShaderMaterial) -> ShaderMaterial:
	if material == null:
		return null
	if not _materials.has(material):
		var gui := ShaderMaterial.new()
		gui.shader = preload("res://shaders/mob_gui.gdshader")
		gui.set_shader_parameter("skin", material.get_shader_parameter("skin"))
		_materials[material] = gui
	return _materials[material]
