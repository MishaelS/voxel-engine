class_name HeldItem
extends Node3D
## The block in the player's hand, bottom right of the view, like the
## classic game's first-person item:
## - swing: a quick arc when breaking or placing (6 ticks);
## - equip: when the item in hand changes, the old one lowers out of view
##   and the new one rises;
## - lit by the light at the player (sky light and time of day).
## It is a child of the camera and is drawn over the world.

const SWING_TICKS := 6.0
## Equip speed: share of the motion per tick (the classic 0.4).
const EQUIP_STEP := 0.4
## Position in front of the camera (camera space) and size.
const REST := Vector3(0.56, -0.52, -0.72)
const SCALE := 0.4
## Size of flat items in hand.
const ITEM_SCALE := 0.5

var player: Player
## Hidden while another camera is used (isometric view, screenshots): the
## block floats next to the player's eyes in the world.
var hidden := false

var _mesh_instance := MeshInstance3D.new()
var _material := ShaderMaterial.new()
var _item_material := ShaderMaterial.new()
var _meshes := {} # block id -> mesh
var _shown := Blocks.AIR
var _swing := -1.0 # 0..1 while swinging
var _equip := 0.0  # 0 = lowered, 1 = in hand


func _ready() -> void:
	_material.shader = preload("res://shaders/block_held.gdshader")
	_material.set_shader_parameter("tiles",
		BlockMaterials.tiles())
	_material.render_priority = 100
	_item_material.shader = preload("res://shaders/item_held.gdshader")
	_item_material.set_shader_parameter("items", load(Items.ICONS_PATH))
	_item_material.render_priority = 100
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)


## Starts a swing (restarts it once past halfway, like the classic game).
func swing() -> void:
	if _swing < 0.0 or _swing > 0.5:
		_swing = 0.0


func _process(delta: float) -> void:
	if player == null:
		return
	var ticks := delta * 20.0
	var wanted := player.held_block()
	if not Settings.get_value("hand_animation"):
		# No swing or equip motion: the block just changes in place.
		_swing = -1.0
		_equip = 1.0
		if wanted != _shown:
			_show(wanted)
	# Lower the old item, swap at the bottom, raise the new one.
	if wanted != _shown:
		_equip = maxf(_equip - EQUIP_STEP * ticks, 0.0)
		if _equip <= 0.0:
			_show(wanted)
	else:
		_equip = minf(_equip + EQUIP_STEP * ticks, 1.0)
	if _swing >= 0.0:
		_swing += ticks / SWING_TICKS
		if _swing >= 1.0:
			_swing = -1.0
	visible = _shown != Blocks.AIR and not hidden
	if visible:
		_pose()
		var brightness := _brightness()
		_material.set_shader_parameter("brightness", brightness)
		_item_material.set_shader_parameter("brightness", brightness)


func _show(id: int) -> void:
	_shown = id
	if id == Blocks.AIR:
		return
	if not _meshes.has(id):
		if Items.is_block(id):
			_meshes[id] = ChunkMesher.block_mesh(id, _material)
		else:
			_meshes[id] = ItemMeshes.extruded(id, _item_material)
	_mesh_instance.mesh = _meshes[id]


## The classic first-person block transform: resting pose, equip offset
## and the swing arc.
func _pose() -> void:
	var swing := maxf(_swing, 0.0)
	var arc := sin(swing * PI)
	var arc_sqrt := sin(sqrt(swing) * PI)
	var offset := Vector3(-arc_sqrt * 0.4, sin(sqrt(swing) * TAU) * 0.2, -arc * 0.2)
	var position_3d := REST + offset + Vector3(0, -(1.0 - _equip) * 0.6, 0)
	var basis_3d := Basis(Vector3.UP, deg_to_rad(45.0 - sin(swing * swing * PI) * 20.0))
	basis_3d = Basis(Vector3.BACK, deg_to_rad(-arc_sqrt * 20.0)) * basis_3d
	basis_3d = Basis(Vector3.RIGHT, deg_to_rad(-arc_sqrt * 80.0)) * basis_3d
	if player.eating >= 0.0:
		# Eating: the food comes to the mouth and bobs.
		var t := minf(player.eating * 4.0, 1.0)
		position_3d = position_3d.lerp(Vector3(0.2, -0.38, -0.8), t)
		position_3d.y += absf(cos(player.eating * 32.0 / 4.0 * PI)) * 0.05 * t
	if not Items.is_block(_shown):
		# Flat items like the classic hand: seen from behind at an angle, the
		# tool's head toward the middle of the view.
		basis_3d = Basis(Vector3.UP, deg_to_rad(-168.0 - sin(swing * swing * PI) * 20.0))
		basis_3d = Basis(Vector3.BACK, deg_to_rad(-20.0 - arc_sqrt * 20.0)) * basis_3d
		basis_3d = Basis(Vector3.RIGHT, deg_to_rad(-arc_sqrt * 80.0)) * basis_3d
		transform = Transform3D(basis_3d.scaled(Vector3.ONE * ITEM_SCALE), position_3d + Vector3(0.0, 0.05, 0.0))
		_mesh_instance.position = Vector3(-0.5, -0.35, -1.0 / 32.0)
		return
	transform = Transform3D(basis_3d.scaled(Vector3.ONE * SCALE), position_3d)
	# The block's mesh spans 0..1: center it on the pivot.
	_mesh_instance.position = Vector3(-0.5, -0.5, -0.5)


func _brightness() -> float:
	var light := SkyLight.MAX
	if player.world:
		light = player.world.get_light(Vector3i(player.eye_position().floor()))
	var atmosphere := Atmosphere.find(get_tree())
	if atmosphere == null:
		return ChunkMesher.LIGHT_BRIGHTNESS[light]
	# Like the blocks: Classic takes light levels away at night, Dynamic
	# Lighting dims with the daylight.
	var level := clampi(roundi(light - atmosphere.sky_darkness), 0, SkyLight.MAX)
	var brightness := ChunkMesher.LIGHT_BRIGHTNESS[level]
	if atmosphere.sky_darkness <= 0.0:
		brightness *= 0.25 + 0.75 * atmosphere.daylight
	return brightness
