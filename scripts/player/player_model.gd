class_name PlayerModel
extends Node3D
## The player's body, seen in the third-person view (F5): the "player"
## model from assets/models/mobs.json with its skin, and the worn armor
## drawn over it like the game's armor layers (helmet, chestplate and boots
## 1 pixel bigger than the parts, leggings half a pixel; textures
## armor_<material>_1 / _2 from tools/make_armor_textures.py). Posed like
## Beta's player (MobAnimation): idle arm sway, walking, the arm raised
## with an item, sneaking, jumping and falling, the swing of a hit, the
## flinch when hurt, falling over when dead, lying in a bed asleep; the
## head follows the view.

var player: Player
var _model := {}
var _armor_meshes: Array[MeshInstance3D] = []
var _pumpkin: MeshInstance3D
var _limb_swing := 0.0
var _limb_amount := 0.0
var _last := Vector3.INF
var _last_step := Vector3.INF
var _held: MeshInstance3D
var _held_id := -1
var _jump := 0.0
var _fall := 0.0
var _rest := {} # part name -> its pivot's place in the model
var _scale := 1.0 / 16.0
var _body_yaw := INF # (world yaw of the body; the head turns from it)
## The chest or furnace carried in both hands (Player.carried), in front
## of the body.
var _carry: MeshInstance3D
var _carry_family := ""


func _ready() -> void:
	_model = MobModels.build("player")
	_scale = _model.root.scale.x
	_model.root.rotation.y = PI # the model faces +Z, the player looks along -Z
	add_child(_model.root)
	for part_name: String in _model.parts:
		_rest[part_name] = (_model.parts[part_name] as Node3D).position
	if player:
		player.armor.changed.connect(_update_armor)
	_update_armor()


## Rebuilds the armor pieces over the body from what the player wears.
func _update_armor() -> void:
	if _pumpkin:
		_pumpkin.queue_free()
		_pumpkin = null
	for mesh in _armor_meshes:
		mesh.queue_free()
	_armor_meshes.clear()
	if player == null:
		return
	var helmet := player.armor.id_at(0)
	if player.armor.count_at(0) > 0 and Items.armor_slot_of(helmet) == 0 and Items.is_block(helmet):
		# A carved pumpkin on the head, a little bigger than it (10 pixels),
		# its face forward, like the game.
		var pumpkin := MeshInstance3D.new()
		pumpkin.mesh = FallingBlocks.block_mesh(Blocks.variant("carved_pumpkin", 0))
		pumpkin.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 10.0), Vector3(-5, -1, -5))
		pumpkin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(_model.parts.head as Node3D).add_child(pumpkin)
		_pumpkin = pumpkin
	_armor_meshes = MobModels.armor_pieces(_model, player.armor)


## A carried block's mesh for a player model: `family` ("chest", "furnace",
## "furnace_lit") in front of the body, in the model's own pixels (the
## model faces +Z), its front forward.
static func carry_node(family: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = FallingBlocks.block_mesh(Blocks.variant(family, CARRY_FACING))
	node.set_meta("block", true)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 10.0), Vector3(-5, 9.5, 2.5))
	return node


## The facing of a carried block whose front looks the way the model does.
const CARRY_FACING := 0


## Both arms out in front, under the block they hold.
static func carry_arms(parts: Dictionary) -> void:
	(parts.right_arm as Node3D).rotation = Vector3(-1.05, -0.12, 0)
	(parts.left_arm as Node3D).rotation = Vector3(-1.05, 0.12, 0)


## Shows (or takes away) the block the player carries.
func _update_carry() -> void:
	var family := str(player.carried.get("family", "")) if player.carrying() else ""
	if family == _carry_family:
		return
	_carry_family = family
	if _carry:
		_carry.queue_free()
		_carry = null
	if family != "":
		_carry = carry_node(family)
		(_model.root as Node3D).add_child(_carry)


## The held item in the right hand, like the game's third-person view.
func _update_held() -> void:
	var id := player.held_block() if player.inventory.count_at(player.selected_slot) > 0 and not player.sleeping else Blocks.AIR
	if id == _held_id:
		return
	_held_id = id
	if _held:
		_held.queue_free()
	_held = MobModels.held_item("player", id)
	if _held:
		(_model.parts.right_arm as Node3D).add_child(_held)


## Asleep: lying on the back along the bed, the head on the pillow, arms
## at the sides, like the game's sleeping player.
func _pose_asleep(parts: Dictionary) -> void:
	for part_name: String in parts:
		(parts[part_name] as Node3D).rotation = Vector3.ZERO
	var bed_id := player.world.get_block(player.bed_position()) if player.world else Blocks.AIR
	var facing := Blocks.facing_table[bed_id] if Blocks.family_of(bed_id).begins_with("bed_") else 0
	var toward_head := Vector3(Blocks.FACING_DIRECTIONS[facing])
	# The model's up (its head) along the bed, its front to the sky.
	var up := toward_head
	var front := Vector3.UP
	var lying := Basis(up.cross(front), up, front)
	var scale := _scale
	var length := 32.0 * scale # the model's height in blocks
	var head_top := player.global_position + toward_head * 0.45
	var feet := head_top - toward_head * length + Vector3(0, 2.0 * scale, 0)
	_model.root.global_transform = Transform3D(lying.scaled(Vector3.ONE * scale), feet)


func _process(delta: float) -> void:
	if player == null or not visible:
		_last = Vector3.INF
		return
	var here := player.global_position
	var moved := 0.0 if _last == Vector3.INF else Vector2(here.x - _last.x, here.z - _last.z).length()
	_last = here
	var speed := moved / maxf(delta, 1e-4) / 20.0 # blocks per tick
	var step := Vector2(here.x - _last_step.x, here.z - _last_step.z) if _last_step != Vector3.INF else Vector2.ZERO
	_last_step = here
	var yaw := player.rotation.y
	if _body_yaw == INF or player.sleeping or player.dead:
		_body_yaw = yaw
	elif player.vehicle and player.vehicle.type_name() == "minecart":
		_body_yaw = yaw # (turns round in the cart with the view)
	else:
		# The head turns first; the body (a boat, a pig under it) follows
		# where it goes.
		_body_yaw = MobAnimation.body_yaw(_body_yaw, yaw, step, delta)
	if player.vehicle:
		speed = 0.0 # sitting: the legs and arms keep still
	_limb_amount = lerpf(_limb_amount, minf(speed * 4.0, 1.0), minf(delta * 10.0, 1.0))
	_limb_swing += speed * 4.0 * delta * 20.0
	var parts: Dictionary = _model.parts
	_update_held()
	_update_carry()
	var alpha := TickLoop.alpha
	var t := Time.get_ticks_msec() / 50.0
	var smooth := minf(delta * 12.0, 1.0)
	var swimming := player.in_water
	var flying := player.flying
	_jump = lerpf(_jump, MobAnimation.jump_amount(player.velocity.y, player.on_ground or flying, swimming), smooth)
	_fall = lerpf(_fall, MobAnimation.fall_amount(player.velocity.y, player.on_ground or flying, swimming), smooth)
	for part_name: String in _rest:
		(parts[part_name] as Node3D).position = _rest[part_name]
	_model.root.transform = Transform3D(Basis(Vector3.UP, PI + angle_difference(yaw, _body_yaw)).scaled(Vector3.ONE * _scale), Vector3.ZERO)
	if player.sleeping:
		_pose_asleep(parts)
	else:
		MobAnimation.pose_biped(parts, t, _limb_swing, _limb_amount, _held != null, 0.0, _jump, _fall)
		if player.vehicle:
			# Sitting (a boat, a minecart, a pig), like the game's riding pose:
			# the legs straight ahead and a little apart, the arms forward.
			for side: Array in [["right_leg", -1.0], ["left_leg", 1.0]]:
				(parts[side[0]] as Node3D).rotation = Vector3(-PI * 2.0 / 5.0, float(side[1]) * PI / 10.0, 0)
			(parts.right_arm as Node3D).rotation.x += -PI / 5.0
			(parts.left_arm as Node3D).rotation.x += -PI / 5.0
		var right_arm := parts.right_arm as Node3D
		var hit := player.held_item.swing_progress() if player.held_item else -1.0
		if hit >= 0.0:
			right_arm.rotation.x -= sin(sqrt(hit) * PI) * 1.6
		var head := parts.head as Node3D
		head.rotation = Vector3(-player.pitch(), angle_difference(_body_yaw, yaw), 0)
		if player.bow_pull >= 0.0:
			# Drawing the bow: both arms up along the view, the left one
			# reaching across to the string (the game's bow pose).
			right_arm.rotation = Vector3(-PI / 2.0 - player.pitch(), 0.1, 0)
			(parts.left_arm as Node3D).rotation = Vector3(-PI / 2.0 - player.pitch(), -0.5, 0)
		if player.eating >= 0.0:
			# Eating: the hand at the mouth, bobbing as it chews.
			var chew := absf(cos(player.eating * BlockInteraction.EAT_TICKS / 4.0 * PI)) * 0.15
			right_arm.rotation = Vector3(-1.35 + chew, -0.45, 0)
		if _carry:
			carry_arms(parts)
		(parts.body as Node3D).rotation.x = 0.0
		if player.sneaking:
			# Beta's sneaking: the body bends forward, the arms come along, the
			# legs step back under it and the head drops a pixel.
			(parts.body as Node3D).rotation.x = 0.5
			right_arm.rotation.x += 0.4
			(parts.left_arm as Node3D).rotation.x += 0.4
			for leg: String in ["right_leg", "left_leg"]:
				(parts[leg] as Node3D).position += Vector3(0, 3, -4)
			head.position.y -= 1.0
			_model.root.position.y = -0.125
		if player.dead:
			# Falls over sideways, like the game's.
			var fall_t := minf((player.death_ticks + alpha) / Player.DEATH_TICKS * 1.6, 1.0)
			_model.root.rotation.z = sqrt(fall_t) * PI / 2.0
		elif player.hurt_ticks > 0:
			_model.root.rotation.x = 0.18 * MobAnimation.flinch(player.hurt_ticks, alpha, Player.HURT_TICKS)
	var brightness := player.world.brightness_at(here + Vector3(0, 1, 0)) if player.world else 1.0
	var hurt := 1.0 if player.hurt_ticks > 0 or player.dead else 0.0
	if _held:
		FallingBlocks.light(_held, brightness)
	if _carry:
		FallingBlocks.light(_carry, brightness)
	if _pumpkin:
		_pumpkin.set_instance_shader_parameter("entity_light", brightness)
	for mesh: MeshInstance3D in _model.meshes + _armor_meshes:
		mesh.set_instance_shader_parameter("brightness", brightness)
		mesh.set_instance_shader_parameter("hurt", hurt)
