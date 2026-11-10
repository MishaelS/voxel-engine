class_name HeldItem
extends Node3D
## The block in the player's hand, bottom right of the view, like the
## classic game's first-person item:
## - swing: a quick arc when breaking or placing (6 ticks);
## - equip: when the item in hand changes, the old one lowers out of view
##   and the new one rises;
## - lit by the light at the player (sky light and time of day).
## It is a child of the camera and is drawn over the world.

## Ticks of one swing (a bit slower than the classic 6, smoother).
const SWING_TICKS := 8.0
## Equip speed: share of the motion per tick (the classic 0.4).
const EQUIP_STEP := 0.4
## Position in front of the camera (camera space) and size.
const REST := Vector3(0.56, -0.52, -0.72)
const SCALE := 0.4
## Flat items in hand, exactly as the classic game places them inside the
## hand's 0.4 scale: down 0.3, x1.5, turned 50 degrees around Y and 335
## around Z, the picture's corner moved to the pivot, drawn mirrored
## (seen from behind) with its front at z = 0.
static var ITEM_IN_HAND := Transform3D(Basis.IDENTITY, Vector3(0, -0.3, 0)) \
	* Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 1.5), Vector3.ZERO) \
	* Transform3D(Basis(Vector3.UP, deg_to_rad(50.0)), Vector3.ZERO) \
	* Transform3D(Basis(Vector3.BACK, deg_to_rad(335.0)), Vector3.ZERO) \
	* Transform3D(Basis.IDENTITY, Vector3(-0.9375, -0.0625, 0.0)) \
	* Transform3D(Basis.IDENTITY.scaled(Vector3(-1, 1, 1)), Vector3(1, 0, -1.0 / 16.0))

var player: Player
## Hidden while another camera is used (isometric view, screenshots): the
## block floats next to the player's eyes in the world.
var hidden := false
## Items drawn turned half around in hand, like the classic game's.
const TURNED_AROUND: Array[String] = ["fishing_rod"]

var _mesh_instance := MeshInstance3D.new()
var _material := ShaderMaterial.new()
var _item_material := ShaderMaterial.new()
var _plant_material := ShaderMaterial.new()
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
	_item_material.set_shader_parameter("items", Items.icons_texture())
	_item_material.render_priority = 100
	_plant_material.shader = _item_material.shader
	_plant_material.set_shader_parameter("items", load(Blocks.ATLAS_PATH))
	_plant_material.render_priority = 100
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)


## How far the current swing is (0..1), -1 when not swinging.
func swing_progress() -> float:
	return _swing


## Starts a swing; while one is playing it finishes first, so holding the
## button gives one smooth swing after another instead of a twitch.
func swing() -> void:
	if _swing < 0.0:
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
		_plant_material.set_shader_parameter("brightness", brightness)


func _show(id: int) -> void:
	_shown = id
	if id == Blocks.AIR:
		return
	if not _meshes.has(id):
		if not ItemMeshes.is_flat(id):
			_meshes[id] = ChunkMesher.block_mesh(id, _material)
		else:
			_meshes[id] = ItemMeshes.extruded(id, _item_material if not Items.is_block(id) else _plant_material)
	_mesh_instance.mesh = _meshes[id]


## The classic first-person block transform: resting pose, equip offset
## and the swing arc.
func _pose() -> void:
	var swing := maxf(_swing, 0.0)
	var arc := sin(swing * PI)
	var arc_sqrt := sin(sqrt(swing) * PI)
	var offset := Vector3(-arc_sqrt * 0.4, sin(sqrt(swing) * TAU) * 0.2, -arc * 0.2)
	var position_3d := REST + offset + Vector3(0, -(1.0 - _equip) * 0.6, 0)
	# The classic order: turned 45 degrees, then the swing turns around Y,
	# Z and X in the item's own space (each rotation after the previous).
	var basis_3d := Basis(Vector3.UP, deg_to_rad(45.0 - sin(swing * swing * PI) * 20.0)) \
		* Basis(Vector3.BACK, deg_to_rad(-arc_sqrt * 20.0)) \
		* Basis(Vector3.RIGHT, deg_to_rad(-arc_sqrt * 80.0))
	if player.eating >= 0.0:
		# Eating: the food comes to the mouth and bobs.
		var t := minf(player.eating * 4.0, 1.0)
		position_3d = position_3d.lerp(Vector3(0.2, -0.38, -0.8), t)
		position_3d.y += absf(cos(player.eating * 32.0 / 4.0 * PI)) * 0.05 * t
	transform = Transform3D(basis_3d.scaled(Vector3.ONE * SCALE), position_3d)
	if not ItemMeshes.is_flat(_shown):
		# The block's mesh spans 0..1: center it on the pivot.
		_mesh_instance.transform = Transform3D(Basis.IDENTITY, Vector3(-0.5, -0.5, -0.5))
	elif Items.name_of(_shown) in TURNED_AROUND:
		# Like the game's "rotate around when rendering" items: the rod is
		# held turned half around, so its line hangs from the far side.
		_mesh_instance.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) * ITEM_IN_HAND
	else:
		_mesh_instance.transform = ITEM_IN_HAND


func _brightness() -> float:
	if player.world == null:
		return 1.0
	return player.world.brightness_at(player.eye_position())