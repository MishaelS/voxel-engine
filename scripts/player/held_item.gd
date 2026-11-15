class_name HeldItem
extends Node3D
## The block in the player's hand, bottom right of the view, like the
## classic game's first-person item:
## - swing: a quick arc when breaking or placing (6 ticks);
## - equip: when the item in hand changes, the old one lowers out of view
##   and the new one rises;
## - lit by the light at the player (sky light and time of day);
## - with nothing in hand, the player's right arm (their skin) shows instead,
##   placed and swung exactly like the classic game's empty hand;
## - a map is held in both hands like the classic game's: low in the view
##   while looking ahead, rising toward the eyes when looking down, with the
##   player's marker (textures/misc/mapicons.png) on it (the coordinates
##   are shown by a compass in the inventory: DebugScreen.item_lines).
## It is a child of the camera and is drawn over the world.

## Ticks of one swing (the game's 6).
const SWING_TICKS := 6.0
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

## The empty hand, like the classic game's (ItemRenderer, no item): rests
## at (0.64, -0.6, -0.72), turned 45 degrees; then the arm's own turns.
static var ARM_IN_VIEW := Transform3D(Basis.IDENTITY, Vector3(-1, 3.6, 3.5)) \
	* Transform3D(Basis(Vector3.BACK, deg_to_rad(120.0)), Vector3.ZERO) \
	* Transform3D(Basis(Vector3.RIGHT, deg_to_rad(200.0)), Vector3.ZERO) \
	* Transform3D(Basis(Vector3.UP, deg_to_rad(-135.0)), Vector3.ZERO) \
	* Transform3D(Basis.IDENTITY, Vector3(5.6, 0, 0)) \
	* Transform3D(Basis.IDENTITY, Vector3(-5, 2, 0) / 16.0) \
	* Transform3D(Basis(Vector3.RIGHT, PI).scaled(Vector3.ONE / 16.0), Vector3.ZERO)

var player: Player
## Hidden while another camera is used (isometric view, screenshots): the
## block floats next to the player's eyes in the world.
var hidden := false
## Hidden by the player's own view: the third-person body or a map in hand.
var covered := false
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
	_plant_material.set_shader_parameter("items", TexturePacks.load_texture(Blocks.ATLAS_PATH))
	_plant_material.render_priority = 100
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)


## How far the current swing is (0..1), -1 when not swinging.
func swing_progress() -> float:
	return _swing


## Starts a swing, like the game's: a new one once the current swing is
## past its middle (quick clicks each get theirs). `continuous` (breaking,
## asked every frame): only after the current one ends, so holding the
## button gives one whole swing after another instead of a twitch.
func swing(continuous: bool = false) -> bool:
	if _swing < 0.0 or (not continuous and _swing >= 0.5):
		_swing = 0.0
		return true
	return false


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
	visible = not hidden and not covered
	var map := _shown != Blocks.AIR and Items.name_of(_shown) == "map"
	_mesh_instance.visible = _shown != Blocks.AIR and not map
	_arm_instance().visible = _shown == Blocks.AIR
	_map_node().visible = map
	if visible and map:
		_map_pose()
	elif visible and _shown == Blocks.AIR:
		_arm_pose()
	elif visible:
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
## The drawn bow's picture for `ticks` drawn (Items.BOW_PULL_TILES), like
## the game: the first after a moment, the last after 18 ticks.
static func bow_pull_tile(ticks: float) -> int:
	return Items.BOW_PULL_TILES[2 if ticks >= 18.0 else (1 if ticks > 13.0 else 0)]


## Drawing the bow like the game (Beta 1.8's first-person bow): held up in
## front, a little turned, pulled toward the eye and shaking when fully
## drawn.
func _bow_pose() -> void:
	var ticks := player.bow_pull
	var power := BlockInteraction.bow_power(ticks)
	var t := Transform3D(Basis.IDENTITY, REST + Vector3(0, -(1.0 - _equip) * 0.6, 0))
	t *= Transform3D(Basis(Vector3.UP, deg_to_rad(45.0)), Vector3.ZERO)
	t *= Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * SCALE), Vector3.ZERO)
	t *= Transform3D(Basis(Vector3.BACK, deg_to_rad(-18.0)), Vector3.ZERO)
	t *= Transform3D(Basis(Vector3.UP, deg_to_rad(-12.0)), Vector3.ZERO)
	t *= Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-8.0)), Vector3.ZERO)
	t *= Transform3D(Basis.IDENTITY, Vector3(-0.9, 0.2, 0.0))
	if power > 0.1:
		t *= Transform3D(Basis.IDENTITY, Vector3(0, sin((ticks - 0.1) * 1.3) * 0.01 * (power - 0.1), 0))
	t *= Transform3D(Basis.IDENTITY, Vector3(0, 0, power * 0.1))
	t *= Transform3D(Basis(Vector3.BACK, deg_to_rad(-335.0)), Vector3.ZERO)
	t *= Transform3D(Basis(Vector3.UP, deg_to_rad(-50.0)), Vector3.ZERO)
	t *= Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0))
	t *= Transform3D(Basis.IDENTITY.scaled(Vector3(1, 1, 1.0 + power * 0.2)), Vector3.ZERO)
	t *= Transform3D(Basis.IDENTITY, Vector3(0, -0.5, 0))
	t *= Transform3D(Basis(Vector3.UP, deg_to_rad(50.0)), Vector3.ZERO)
	t *= Transform3D(Basis(Vector3.BACK, deg_to_rad(335.0)), Vector3.ZERO)
	transform = t
	_mesh_instance.mesh = ItemMeshes.extruded(_shown, _item_material, bow_pull_tile(ticks))
	_mesh_instance.transform = ITEM_IN_HAND


func _pose() -> void:
	if player.bow_pull >= 0.0 and Items.name_of(_shown) == "bow":
		_bow_pose()
		return
	if Items.name_of(_shown) == "bow":
		_mesh_instance.mesh = _meshes[_shown] # back to the bow at rest
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


var _arm: MeshInstance3D


## The arm: the player's right arm box with their skin.
func _arm_instance() -> MeshInstance3D:
	if _arm == null:
		_arm = MeshInstance3D.new()
		var part := {"name": "first_person_arm", "size": [4, 12, 4], "from": [-3, -10, -2], "pivot": [0, 0, 0],
			"uv": [40, 16], "texture": "player"}
		var mesh := MobModels.part_mesh("player", part).duplicate() as ArrayMesh
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/hand.gdshader")
		material.set_shader_parameter("skin", MobModels.skin_texture("player"))
		material.render_priority = 100
		mesh.surface_set_material(0, material)
		_arm.mesh = mesh
		_arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_arm)
	return _arm


## The classic empty-hand pose: rest, equip and swing, then the arm.
func _arm_pose() -> void:
	transform = Transform3D.IDENTITY
	var swing := maxf(_swing, 0.0)
	var arc := sin(swing * PI)
	var arc_sqrt := sin(sqrt(swing) * PI)
	var placed := Transform3D(Basis.IDENTITY, Vector3(-arc_sqrt * 0.3, sin(sqrt(swing) * TAU) * 0.4, -arc * 0.4)) \
		* Transform3D(Basis.IDENTITY, Vector3(0.64, -0.6 - (1.0 - _equip) * 0.6, -0.72)) \
		* Transform3D(Basis(Vector3.UP, deg_to_rad(45.0)), Vector3.ZERO) \
		* Transform3D(Basis(Vector3.UP, deg_to_rad(arc_sqrt * 70.0)), Vector3.ZERO) \
		* Transform3D(Basis(Vector3.BACK, deg_to_rad(-sin(swing * swing * PI) * 20.0)), Vector3.ZERO)
	_arm.transform = placed * ARM_IN_VIEW
	# The player's skin (it can change in Player Settings).
	((_arm.mesh as ArrayMesh).surface_get_material(0) as ShaderMaterial).set_shader_parameter("skin", MobModels.skin_texture("player"))
	_arm.set_instance_shader_parameter("brightness", _brightness())


# --- The map in both hands ------------------------------------------------------

## The arm model's own placement (the classic drawFirstPersonHand: the right
## arm at its pivot, the model upside down), as at the end of ARM_IN_VIEW.
static var ARM_MODEL := Transform3D(Basis.IDENTITY, Vector3(-5, 2, 0) / 16.0) \
	* Transform3D(Basis(Vector3.RIGHT, PI).scaled(Vector3.ONE / 16.0), Vector3.ZERO)
const MAP_ICONS := "res://assets/textures/misc/mapicons.png"
const MAP_BACKGROUND := "res://assets/textures/misc/mapbg.png"

var _map: Node3D
var _map_arms: Array[MeshInstance3D] = []
var _map_picture: MeshInstance3D
var _map_marker: MeshInstance3D
var _map_materials: Array[ShaderMaterial] = []
var _marker_mesh := ImmediateMesh.new()


func _map_node() -> Node3D:
	if _map:
		return _map
	_map = Node3D.new()
	add_child(_map)
	var arm := _arm_instance()
	for side in 2:
		var hand := MeshInstance3D.new()
		hand.mesh = arm.mesh
		hand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_map.add_child(hand)
		_map_arms.append(hand)
	# The parchment (142 pixels, the map's 128 in the middle) and the map,
	# in the game's map units (1 = a map pixel).
	var paper := MeshInstance3D.new()
	paper.mesh = _map_quad(Rect2(-7, -7, 142, 142), 0.0)
	paper.material_override = _map_material(TexturePacks.load_texture(MAP_BACKGROUND), 101)
	_map.add_child(paper)
	_map_picture = MeshInstance3D.new()
	_map_picture.mesh = _map_quad(Rect2(0, 0, Maps.SIZE, Maps.SIZE), -0.01)
	_map_picture.material_override = _map_material(null, 102)
	_map.add_child(_map_picture)
	_map_marker = MeshInstance3D.new()
	_map_marker.mesh = _marker_mesh
	_map_marker.material_override = _map_material(TexturePacks.load_texture(MAP_ICONS), 103)
	_map.add_child(_map_marker)
	for child in _map.get_children():
		(child as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return _map


func _map_material(texture: Texture2D, priority: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/held_map.gdshader")
	material.set_shader_parameter("picture", texture)
	material.render_priority = priority
	_map_materials.append(material)
	return material


## A quad in map units (y down like the picture), the picture's top at the top.
static func _map_quad(rect: Rect2, z: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for k: int in [0, 1, 2, 0, 2, 3]:
		tool.set_uv(uvs[k])
		tool.add_vertex(Vector3(corners[k].x, corners[k].y, z))
	return tool.commit()


## The classic first-person map (ItemRenderer, Beta 1.8): held in both
## hands; the lower the eyes look, the higher the map comes up (looking
## straight ahead it sits low, half out of the view); swings like an item.
func _map_pose() -> void:
	transform = Transform3D.IDENTITY
	var swing := maxf(_swing, 0.0)
	var arc := sin(swing * PI)
	var arc_sqrt := sin(sqrt(swing) * PI)
	# The game's pitch: degrees, looking down positive.
	var pitch := rad_to_deg(-asin(clampf(player.look_direction().y, -1.0, 1.0)))
	var lift := clampf(1.0 - pitch / 45.0 + 0.1, 0.0, 1.0)
	lift = -cos(lift * PI) * 0.5 + 0.5
	const HOLD := 0.8
	var root := Transform3D(Basis.IDENTITY, Vector3(-arc_sqrt * 0.4, sin(sqrt(swing) * TAU) * 0.2, -arc * 0.2)) \
		* Transform3D(Basis.IDENTITY, Vector3(0, -(1.0 - _equip) * 1.2 - lift * 0.5 + 0.04, -0.9 * HOLD)) \
		* Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3.ZERO) \
		* Transform3D(Basis(Vector3.BACK, deg_to_rad(lift * -85.0)), Vector3.ZERO)
	var brightness := _brightness()
	for side in 2:
		var s := float(side * 2 - 1)
		_map_arms[side].transform = root \
			* Transform3D(Basis.IDENTITY, Vector3(0, -0.6, 1.1 * s)) \
			* Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-45.0 * s)), Vector3.ZERO) \
			* Transform3D(Basis(Vector3.BACK, deg_to_rad(-90.0 + 59.0)), Vector3.ZERO) \
			* Transform3D(Basis(Vector3.UP, deg_to_rad(-65.0 * s)), Vector3.ZERO) \
			* ARM_MODEL
		_map_arms[side].set_instance_shader_parameter("brightness", brightness)
	var swing_turn := sin(swing * swing * PI)
	_map.transform = Transform3D.IDENTITY
	var paper := root \
		* Transform3D(Basis(Vector3.UP, deg_to_rad(-swing_turn * 20.0)), Vector3.ZERO) \
		* Transform3D(Basis(Vector3.BACK, deg_to_rad(-arc_sqrt * 20.0)), Vector3.ZERO) \
		* Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-arc_sqrt * 80.0)), Vector3.ZERO) \
		* Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.38), Vector3.ZERO) \
		* Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3.ZERO) \
		* Transform3D(Basis(Vector3.BACK, deg_to_rad(180.0)), Vector3.ZERO) \
		* Transform3D(Basis.IDENTITY, Vector3(-1, -1, 0)) \
		* Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.015625), Vector3.ZERO)
	for child in [_map.get_child(2), _map_picture, _map_marker]:
		(child as Node3D).transform = paper
	var view := player.map_view
	if view and view.texture:
		_map_materials[1].set_shader_parameter("picture", view.texture)
	for material in _map_materials:
		material.set_shader_parameter("brightness", brightness)
	_draw_marker(view.marker() if view else [Vector2(64, 64), 0, true])


## The player's icon: the white marker turned the way they look (16 steps,
## like the game), or a white dot at the edge when they are off the map.
func _draw_marker(marker: Array) -> void:
	_marker_mesh.clear_surfaces()
	var at: Vector2 = marker[0]
	var inside: bool = marker[2]
	var icon := 0 if inside else 6
	var angle := float(marker[1]) / 16.0 * TAU if inside else 0.0
	var uv0 := Vector2(icon % 4, icon / 4) / 4.0
	# Map space has y down: turning by `angle` clockwise on the map.
	var right := Vector2(cos(angle), sin(angle)) * 4.0
	var down := Vector2(-sin(angle), cos(angle)) * 4.0
	var corners := [at - right - down, at + right - down, at + right + down, at - right + down]
	var uvs := [uv0, uv0 + Vector2(0.25, 0), uv0 + Vector2(0.25, 0.25), uv0 + Vector2(0, 0.25)]
	_marker_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for k: int in [0, 1, 2, 0, 2, 3]:
		_marker_mesh.surface_set_uv(uvs[k])
		_marker_mesh.surface_add_vertex(Vector3(corners[k].x, corners[k].y, -0.02))
	_marker_mesh.surface_end()


func _brightness() -> float:
	if player.world == null:
		return 1.0
	return player.world.brightness_at(player.eye_position())