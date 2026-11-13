class_name RemotePlayer
extends Node3D
## Another player in a network game (Net): the player model with the skin,
## the name above the head, following the positions it sends (20 a second,
## smoothed between them), walking, sneaking, sitting, sleeping, swinging
## the arm and holding the item in hand, lit by the light where it stands.

const SMOOTHING := 12.0 # share per second toward the latest state

var world: VoxelWorld
var player_name := ""
## Its peer (Net): damage goes there.
var peer_id := 0
## As its player last said (the state flags).
var dead := false
## The latest position sent (the host keeps the columns around it loaded).
var target_position := Vector3.ZERO

var _model := {}
var _rest := {}
var _scale := 1.0 / 16.0
var _label: Label3D
var _target_yaw := 0.0
var _pitch := 0.0
var _flags := 0
var _held_id := -1
var _held: MeshInstance3D
var _swings := -1
var _swing := -1.0 # 0..1 while swinging
var _limb_swing := 0.0
var _limb_amount := 0.0
var _last := Vector3.INF
var _last_here := Vector3.ZERO
var _body_yaw := INF # (the head turns from it, MobAnimation.body_yaw)
var _name_color := 0


func _ready() -> void:
	_model = MobModels.build("player")
	_scale = _model.root.scale.x
	_model.root.rotation.y = PI
	add_child(_model.root)
	for part_name: String in _model.parts:
		_rest[part_name] = (_model.parts[part_name] as Node3D).position
	_label = Label3D.new()
	_label.text = player_name
	_label.font = UiTheme.font()
	_label.font_size = 32
	_label.pixel_size = 0.008
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.outline_size = 0
	_label.modulate = Color.WHITE
	_label.position = Vector3(0, 2.1, 0)
	add_child(_label)


## Their name color and skin (Net.looks; null skin: the default one).
func set_look(name_color: int, skin: Texture2D) -> void:
	_name_color = name_color
	if _model.is_empty():
		await ready
	var material := MobModels.material_with_skin("player", skin)
	for mesh: MeshInstance3D in _model.meshes:
		mesh.material_override = material


# --- Like a Player to creatures and other players (Mob, Arrow, BlockInteraction) ---------

func eye_position() -> Vector3:
	return global_position + Vector3(0, 1.62, 0)


func is_creative() -> bool:
	return _flags & 16 != 0


func is_sleeping() -> bool:
	return _flags & 8 != 0


func damage(amount: int, _always: bool = false) -> void:
	if not dead and not is_creative():
		Net.hurt_peer(peer_id, amount, Vector3.INF)


## Pushed away from `from` (sent with the damage that comes with it).
func knockback(from: Vector3) -> void:
	Net.hurt_peer(peer_id, 0, from)


func set_state(at: Vector3, yaw: float, pitch: float, flags: int, held: int, swings: int) -> void:
	target_position = at
	dead = flags & 4 != 0
	_target_yaw = yaw
	_pitch = pitch
	_flags = flags
	if swings != _swings:
		if _swings >= 0:
			_swing = 0.0
		_swings = swings
	if held != _held_id:
		_held_id = held
		if _held:
			_held.queue_free()
		_held = MobModels.held_item("player", held)
		if _held:
			(_model.parts.right_arm as Node3D).add_child(_held)


func _process(delta: float) -> void:
	var follow := minf(delta * SMOOTHING, 1.0)
	if global_position.distance_to(target_position) > 8.0:
		global_position = target_position # teleported
	global_position = global_position.lerp(target_position, follow)
	rotation.y = lerp_angle(rotation.y, _target_yaw, follow)
	var here := global_position
	var moved := 0.0 if _last == Vector3.INF else Vector2(here.x - _last.x, here.z - _last.z).length()
	_last = here
	var speed := moved / maxf(delta, 1e-4) / 20.0
	if _body_yaw == INF or dead:
		_body_yaw = rotation.y
	else:
		_body_yaw = MobAnimation.body_yaw(_body_yaw, rotation.y, Vector2(here.x - _last_here.x, here.z - _last_here.z), delta)
	_last_here = here
	if _flags & 2:
		speed = 0.0 # sitting: the legs and arms keep still
	_limb_amount = lerpf(_limb_amount, minf(speed * 4.0, 1.0), minf(delta * 10.0, 1.0))
	_limb_swing += speed * 4.0 * delta * 20.0
	if _swing >= 0.0:
		_swing += delta * 20.0 / HeldItem.SWING_TICKS
		if _swing >= 1.0:
			_swing = -1.0
	_pose()
	var brightness := world.brightness_at(here + Vector3(0, 1, 0)) if world else 1.0
	for mesh: MeshInstance3D in _model.meshes:
		mesh.set_instance_shader_parameter("brightness", brightness)
		mesh.set_instance_shader_parameter("hurt", 1.0 if _flags & 4 else 0.0)
	if _held:
		FallingBlocks.light(_held, brightness)
	_label.visible = not (_flags & 1) # hidden while sneaking, like the game's
	_label.modulate = PlayerProfile.color_of(_name_color)


func _pose() -> void:
	var parts: Dictionary = _model.parts
	for part_name: String in _rest:
		(parts[part_name] as Node3D).position = _rest[part_name]
	var turn := angle_difference(rotation.y, _body_yaw) if _body_yaw != INF else 0.0
	_model.root.transform = Transform3D(Basis(Vector3.UP, PI + turn).scaled(Vector3.ONE * _scale), Vector3.ZERO)
	var t := Time.get_ticks_msec() / 50.0
	MobAnimation.pose_biped(parts, t, _limb_swing, _limb_amount, _held != null, false, 0.0, 0.0)
	var right_arm := parts.right_arm as Node3D
	var left_arm := parts.left_arm as Node3D
	if _flags & 2:
		# Sitting in a boat or a minecart.
		for side: Array in [["right_leg", -1.0], ["left_leg", 1.0]]:
			(parts[side[0]] as Node3D).rotation = Vector3(-PI * 2.0 / 5.0, float(side[1]) * PI / 10.0, 0)
		right_arm.rotation.x += -PI / 5.0
		left_arm.rotation.x += -PI / 5.0
	if _swing >= 0.0:
		right_arm.rotation.x -= sin(sqrt(_swing) * PI) * 1.6
	(parts.head as Node3D).rotation = Vector3(-_pitch, -turn, 0)
	(parts.body as Node3D).rotation.x = 0.0
	if _flags & 1:
		(parts.body as Node3D).rotation.x = 0.5
		right_arm.rotation.x += 0.4
		left_arm.rotation.x += 0.4
		for leg: String in ["right_leg", "left_leg"]:
			(parts[leg] as Node3D).position += Vector3(0, 3, -4)
		(parts.head as Node3D).position.y -= 1.0
		_model.root.position.y = -0.125
	if _flags & 8:
		# Asleep: lying on the back.
		_model.root.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0).scaled(Vector3.ONE * _scale), Vector3(0, 0.3, 0))
