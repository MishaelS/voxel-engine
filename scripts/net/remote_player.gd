class_name RemotePlayer
extends Node3D
## Another player in a network game (Net): the player model with the skin,
## the name above the head, following the positions it sends (20 a second,
## moved evenly from one to the next), and everything its own third-person
## view shows (PlayerModel): walking, jumping and falling, sneaking,
## sitting, sleeping, the arm swinging, the item in hand, the armor (and a
## pumpkin) it wears, the bow being drawn, eating (with crumbs and bites),
## flinching red when hurt, falling over dead, burning; and what it does to
## the world: the cracks on the block it is breaking (with the chips and
## hits), its fishing rod's bobber and line, its steps. Lit by the light
## where it stands.
## On a dedicated server (nothing is drawn) it only keeps its place.

## Seconds to get to a new position (states come every 0.05: a little more,
## so a late one doesn't make it stop and jump).
const GLIDE := 0.075
## State flags (Net._send_own_state).
const SNEAKING := 1
const RIDING := 2
const DEAD := 4
const ASLEEP := 8
const CREATIVE := 16
const EATING := 32
const DRAWING := 64
const BURNING := 128
const HURT := 256
const GROUNDED := 512
const SWIMMING := 1024
## Both hands carry a chest or a furnace (the held id is that block).
const CARRYING := 2048
const FLAGS := 4095
## `gear` (Net._send_own_state): the four armor ids, the block being broken
## (x, y, z) and its crack stage (-1: none).
const GEAR_SIZE := 8

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
var _glide_from := Vector3.ZERO
var _glide := 1.0
var _jump := 0.0
var _fall := 0.0
var _gear := PackedInt32Array()
var _armor := Inventory.new(4)
var _armor_meshes: Array[MeshInstance3D] = []
var _pumpkin: MeshInstance3D
var _hook := Vector3.INF
var _bobber: Sprite3D
var _line: MeshInstance3D
var _line_mesh: ImmediateMesh
var _flames: MeshInstance3D
var _cracks: MeshInstance3D
var _crack_material: ShaderMaterial
var _hurt_time := 0.0 # seconds left of the flinch
var _death_time := -1.0 # seconds since it died
var _eat_time := 0.0
var _mine_time := 0.0
var _mine_hits := 0
var _walked := 0.0
var _next_step := 1.0
var _shown := Vector2(-1, -1)
var _burn_tick := -1
var _carry: MeshInstance3D
var _carry_family := ""
var _shown_meshes := -1
var _light_turn := -1
var _light := 1.0


func _ready() -> void:
	if Net.dedicated:
		return
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
	if Net.dedicated:
		return
	if _model.is_empty():
		await ready
	var material := MobModels.material_with_skin("player", skin)
	for mesh: MeshInstance3D in _model.meshes:
		mesh.material_override = material


# --- Like a Player to creatures and other players (Mob, Arrow, BlockInteraction) ---------

func eye_position() -> Vector3:
	return global_position + Vector3(0, 1.62, 0)


func is_creative() -> bool:
	return _flags & CREATIVE != 0


func is_sleeping() -> bool:
	return _flags & ASLEEP != 0


## Sneaking (creatures notice it from less far, Mob._notices).
func is_sneaking() -> bool:
	return _flags & SNEAKING != 0


## The item in its hand (animals follow their food, Mob._tempter).
func held_block() -> int:
	return maxi(_held_id, Blocks.AIR)


func look_direction() -> Vector3:
	return Vector3(-sin(_target_yaw) * cos(_pitch), sin(_pitch), -cos(_target_yaw) * cos(_pitch))


func damage(amount: int, _always: bool = false) -> void:
	if not dead and not is_creative():
		Net.hurt_peer(peer_id, amount, Vector3.INF)


## Pushed away from `from` (sent with the damage that comes with it).
func knockback(from: Vector3) -> void:
	Net.hurt_peer(peer_id, 0, from)


func set_state(at: Vector3, yaw: float, pitch: float, flags: int, held: int, swings: int,
		gear: PackedInt32Array = PackedInt32Array(), hook: Vector3 = Vector3.INF) -> void:
	if at != target_position:
		_glide_from = global_position if is_inside_tree() else at
		_glide = 0.0
	target_position = at
	var was := _flags
	dead = flags & DEAD != 0
	_target_yaw = yaw
	_pitch = pitch
	_flags = flags
	_hook = hook
	if Net.dedicated:
		_held_id = held
		return
	if flags & HURT and not was & HURT and not dead:
		_hurt_time = Player.HURT_TICKS / 20.0
		Sounds.play("damage/hurt", global_position + Vector3(0, 1.2, 0), 1.0, Sounds.beta_pitch())
	if dead and not was & DEAD:
		_death_time = 0.0
		Sounds.play("damage/hurt", global_position + Vector3(0, 1.2, 0), 1.0, 0.7)
	elif not dead:
		_death_time = -1.0
	if swings != _swings:
		if _swings >= 0:
			_swing = 0.0
		_swings = swings
	# A chest or furnace in both hands (PlayerModel's look), not in one.
	var family := Blocks.family_of(held) if flags & CARRYING and held > Blocks.AIR and held < Blocks.count() else ""
	if not family in ["chest", "furnace", "furnace_lit"]:
		family = ""
	if family != _carry_family:
		_carry_family = family
		if _carry:
			_carry.queue_free()
			_carry = null
		if family != "":
			_carry = PlayerModel.carry_node(family)
			(_model.root as Node3D).add_child(_carry)
		_shown = Vector2(-1, -1)
	if family != "":
		held = Blocks.AIR
	if flags & ASLEEP:
		held = Blocks.AIR # (nothing in the hand in bed)
	if held != _held_id:
		_held_id = held
		if _held:
			_held.queue_free()
		_held = MobModels.held_item("player", held)
		if _held:
			(_model.parts.right_arm as Node3D).add_child(_held)
		_shown = Vector2(-1, -1)
	if gear.size() == GEAR_SIZE:
		if _gear.size() != GEAR_SIZE or gear.slice(0, 4) != _gear.slice(0, 4):
			_gear = gear
			_update_armor()
		_gear = gear


## The armor pieces over the body (and a carved pumpkin on the head), like
## PlayerModel's.
func _update_armor() -> void:
	if _model.is_empty():
		return
	if _pumpkin:
		_pumpkin.queue_free()
		_pumpkin = null
	for mesh in _armor_meshes:
		mesh.queue_free()
	_armor_meshes.clear()
	for slot in 4:
		var id := _gear[slot]
		var fits := id != Blocks.AIR and Items.exists(id) and Items.armor_slot_of(id) == slot
		_armor.set_slot(slot, id if fits else Blocks.AIR, 1 if fits else 0)
	var helmet := _armor.id_at(0)
	if _armor.count_at(0) > 0 and Items.is_block(helmet):
		var pumpkin := MeshInstance3D.new()
		pumpkin.mesh = FallingBlocks.block_mesh(Blocks.variant("carved_pumpkin", 0))
		pumpkin.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 10.0), Vector3(-5, -1, -5))
		pumpkin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(_model.parts.head as Node3D).add_child(pumpkin)
		_pumpkin = pumpkin
	_armor_meshes = MobModels.armor_pieces(_model, _armor)
	_shown = Vector2(-1, -1)


func _process(delta: float) -> void:
	# Evenly from where it was to the latest position.
	if global_position.distance_to(target_position) > 8.0:
		global_position = target_position # teleported
		_glide = 1.0
	elif _glide < 1.0:
		_glide = minf(_glide + delta / GLIDE, 1.0)
		global_position = _glide_from.lerp(target_position, _glide)
	if Net.dedicated or _model.is_empty():
		return
	rotation.y = lerp_angle(rotation.y, _target_yaw, minf(delta * 16.0, 1.0))
	var here := global_position
	var step := Vector3.ZERO if _last == Vector3.INF else here - _last
	_last = here
	var moved := Vector2(step.x, step.z).length()
	var per_tick := 1.0 / maxf(delta, 1e-4) / 20.0
	var speed := moved * per_tick
	if _body_yaw == INF or dead or _flags & ASLEEP:
		_body_yaw = rotation.y
	else:
		_body_yaw = MobAnimation.body_yaw(_body_yaw, rotation.y, Vector2(here.x - _last_here.x, here.z - _last_here.z), delta)
	_last_here = here
	if _flags & RIDING:
		speed = 0.0 # sitting: the legs and arms keep still
	_limb_amount = lerpf(_limb_amount, minf(speed * 4.0, 1.0), minf(delta * 10.0, 1.0))
	_limb_swing += speed * 4.0 * delta * 20.0
	var grounded := _flags & (GROUNDED | RIDING | ASLEEP) != 0
	var smooth := minf(delta * 12.0, 1.0)
	_jump = lerpf(_jump, MobAnimation.jump_amount(step.y * per_tick, grounded, _flags & SWIMMING != 0), smooth)
	_fall = lerpf(_fall, MobAnimation.fall_amount(step.y * per_tick, grounded, _flags & SWIMMING != 0), smooth)
	if _swing >= 0.0:
		_swing += delta * 20.0 / HeldItem.SWING_TICKS
		if _swing >= 1.0:
			_swing = -1.0
	_hurt_time = maxf(_hurt_time - delta, 0.0)
	if _death_time >= 0.0:
		_death_time += delta
	_pose()
	_steps(moved)
	_eat(delta)
	_show_mining(delta)
	_show_hook()
	_show_flames()
	# The light where it stands (taken every other tick), set on the meshes
	# only when it looks different.
	var turn := TickLoop.tick_count >> 1
	if turn != _light_turn:
		_light_turn = turn
		_light = world.brightness_at(here + Vector3(0, 1, 0)) if world else 1.0
	var look := Vector2(_light, 1.0 if _hurt_time > 0.0 or dead else 0.0)
	var meshes: int = _model.meshes.size() + _armor_meshes.size()
	if look != _shown or meshes != _shown_meshes:
		_shown = look
		_shown_meshes = meshes
		for mesh: MeshInstance3D in _model.meshes + _armor_meshes:
			mesh.set_instance_shader_parameter("brightness", look.x)
			mesh.set_instance_shader_parameter("hurt", look.y)
		if _held:
			FallingBlocks.light(_held, look.x)
		if _carry:
			FallingBlocks.light(_carry, look.x)
		if _pumpkin:
			_pumpkin.set_instance_shader_parameter("entity_light", look.x)
	_label.visible = not (_flags & SNEAKING) # hidden while sneaking, like the game's
	_label.modulate = PlayerProfile.color_of(_name_color)


func _pose() -> void:
	var parts: Dictionary = _model.parts
	for part_name: String in _rest:
		(parts[part_name] as Node3D).position = _rest[part_name]
	var turn := angle_difference(rotation.y, _body_yaw) if _body_yaw != INF else 0.0
	_model.root.transform = Transform3D(Basis(Vector3.UP, PI + turn).scaled(Vector3.ONE * _scale), Vector3.ZERO)
	var t := Time.get_ticks_msec() / 50.0
	MobAnimation.pose_biped(parts, t, _limb_swing, _limb_amount, _held != null, 0.0, _jump, _fall)
	var right_arm := parts.right_arm as Node3D
	var left_arm := parts.left_arm as Node3D
	var head := parts.head as Node3D
	if _flags & RIDING:
		# Sitting in a boat or a minecart.
		for side: Array in [["right_leg", -1.0], ["left_leg", 1.0]]:
			(parts[side[0]] as Node3D).rotation = Vector3(-PI * 2.0 / 5.0, float(side[1]) * PI / 10.0, 0)
		right_arm.rotation.x += -PI / 5.0
		left_arm.rotation.x += -PI / 5.0
	if _swing >= 0.0:
		right_arm.rotation.x -= sin(sqrt(_swing) * PI) * 1.6
	head.rotation = Vector3(-_pitch, -turn, 0)
	if _flags & DRAWING:
		# Drawing the bow: both arms up along the view (PlayerModel's pose).
		right_arm.rotation = Vector3(-PI / 2.0 - _pitch, 0.1, 0)
		left_arm.rotation = Vector3(-PI / 2.0 - _pitch, -0.5, 0)
	if _flags & EATING:
		# Eating: the hand at the mouth, bobbing as it chews.
		var chew := absf(cos(_eat_time * 20.0 / 4.0 * PI)) * 0.15
		right_arm.rotation = Vector3(-1.35 + chew, -0.45, 0)
	if _carry:
		PlayerModel.carry_arms(parts)
	(parts.body as Node3D).rotation.x = 0.0
	if _flags & SNEAKING:
		(parts.body as Node3D).rotation.x = 0.5
		right_arm.rotation.x += 0.4
		left_arm.rotation.x += 0.4
		for leg: String in ["right_leg", "left_leg"]:
			(parts[leg] as Node3D).position += Vector3(0, 3, -4)
		head.position.y -= 1.0
		_model.root.position.y = -0.125
	if _flags & ASLEEP:
		# Asleep: lying on the back.
		_model.root.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0).scaled(Vector3.ONE * _scale), Vector3(0, 0.3, 0))
	elif dead and _death_time >= 0.0:
		# Falls over sideways, like the game's.
		var fall_t := minf(_death_time * 20.0 / Player.DEATH_TICKS * 1.6, 1.0)
		_model.root.rotation.z = sqrt(fall_t) * PI / 2.0
	elif _hurt_time > 0.0:
		_model.root.rotation.x = 0.18 * MobAnimation.flinch(ceili(_hurt_time * 20.0), 0.0, Player.HURT_TICKS)


## Its steps heard, like the player's own: one every step's distance, not
## while sneaking; splashes when swimming.
func _steps(moved: float) -> void:
	_walked += moved * 0.6
	if _walked <= _next_step or world == null:
		return
	_next_step = floorf(_walked) + 1.0
	if _flags & SWIMMING:
		Sounds.play_swim(global_position, Vector3(0, 0, 0.1), "players")
	elif _flags & GROUNDED and not _flags & (SNEAKING | RIDING):
		var below := world.get_block(Vector3i((global_position - Vector3(0, 0.2, 0)).floor()))
		if below != Blocks.AIR:
			Sounds.play_block("step", below, global_position, "players")


## Chewing: crumbs of the food from the mouth and a bite every 4 ticks.
func _eat(delta: float) -> void:
	if not _flags & EATING or world == null:
		_eat_time = 0.0
		return
	var before := int(_eat_time * 5.0)
	_eat_time += delta
	if int(_eat_time * 5.0) != before and _eat_time > 0.3 and _held_id > Blocks.AIR:
		var look := look_direction()
		var mouth := eye_position() + look * 0.3 - Vector3(0, 0.15, 0)
		world.particles.item_crumbs(_held_id, mouth, look, 5, 0.5)
		Sounds.play("random/eat", mouth, 0.5 + 0.5 * randi_range(0, 1), randf_range(0.8, 1.2))


## The block it is breaking: the cracks over it, chips off it every tick
## and a hit every 4, like the player's own (BlockInteraction).
func _show_mining(delta: float) -> void:
	var stage := _gear[7] if _gear.size() == GEAR_SIZE else -1
	var pos := Vector3i(_gear[4], _gear[5], _gear[6]) if stage >= 0 else Vector3i.ZERO
	var id := world.get_block(pos) if stage >= 0 and world else Blocks.AIR
	if stage < 0 or id == Blocks.AIR or dead:
		if _cracks:
			_cracks.visible = false
		_mine_time = 0.0
		return
	var interaction := world.get_node_or_null("../BlockInteraction") as BlockInteraction
	if interaction == null:
		return
	if _cracks == null:
		_crack_material = ShaderMaterial.new()
		_crack_material.shader = preload("res://shaders/block_cracks.gdshader")
		_crack_material.set_shader_parameter("tiles", BlockMaterials.tiles())
		_cracks = MeshInstance3D.new()
		_cracks.top_level = true
		_cracks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_cracks.material_override = _crack_material
		add_child(_cracks)
	_cracks.visible = true
	_cracks.mesh = interaction._crack_mesh_for(id)
	_cracks.global_transform = Transform3D(Basis.IDENTITY, Vector3(pos))
	_crack_material.set_shader_parameter("stage", BlockInteraction.CRACK_TILE + clampi(stage, 0, 9))
	_mine_time += delta * 20.0
	while _mine_time >= 1.0:
		_mine_time -= 1.0
		_mine_hits += 1
		world.particles.hit_block(pos, Vector3i.UP, id)
		if _mine_hits % 4 == 0:
			Sounds.play_block("hit", id, Vector3(pos) + Vector3(0.5, 0.5, 0.5))


## Its fishing rod's bobber and the line to it (FishingBobber's look).
func _show_hook() -> void:
	if _hook == Vector3.INF or dead:
		if _bobber:
			_bobber.visible = false
			_line.visible = false
		return
	if _bobber == null:
		_bobber = Sprite3D.new()
		_bobber.texture = ImageTexture.create_from_image(TexturePacks.region("particles.png", Rect2i(8, 16, 8, 8)))
		_bobber.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_bobber.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_bobber.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		_bobber.shaded = false
		_bobber.pixel_size = 0.5 / 8.0
		_bobber.top_level = true
		_bobber.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_bobber)
		_line_mesh = ImmediateMesh.new()
		_line = MeshInstance3D.new()
		_line.mesh = _line_mesh
		_line.top_level = true
		var black := StandardMaterial3D.new()
		black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		black.albedo_color = Color(0.05, 0.05, 0.05)
		_line.material_override = black
		add_child(_line)
	_bobber.visible = true
	_line.visible = true
	_line.global_transform = Transform3D.IDENTITY
	var end := _bobber.global_position.lerp(_hook + Vector3(0, 0.2, 0), 0.5) if _bobber.global_position.distance_to(_hook) < 4.0 else _hook + Vector3(0, 0.2, 0)
	_bobber.global_position = end
	var look := look_direction()
	var right := look.cross(Vector3.UP).normalized()
	var tip := global_position + Vector3(0, 1.6, 0) + right * 0.4 + Vector3(look.x, 0, look.z) * 0.8
	_line_mesh.clear_surfaces()
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in 17:
		var t := i / 16.0
		var point := tip.lerp(end, t)
		point.y -= sin(t * PI) * minf(tip.distance_to(end) * 0.05, 1.0) # a little sag
		_line_mesh.surface_add_vertex(point)
	_line_mesh.surface_end()


## On fire: the creatures' flames around it (Entity._show_flames).
func _show_flames() -> void:
	if not _flags & BURNING or dead:
		if _flames:
			_flames.visible = false
		return
	var size := Player.HALF_WIDTH * 2.0 * 1.4
	if _flames == null:
		_flames = MeshInstance3D.new()
		_flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flames.mesh = Entity.flames_mesh(Player.HEIGHT / size)
		add_child(_flames)
	_flames.visible = true
	if world and TickLoop.tick_count != _burn_tick and TickLoop.tick_count % 3 == 0:
		_burn_tick = TickLoop.tick_count
		world.particles.burning(AABB(global_position - Vector3(Player.HALF_WIDTH, 0, Player.HALF_WIDTH),
			Vector3(Player.HALF_WIDTH * 2.0, Player.HEIGHT, Player.HALF_WIDTH * 2.0)))
	var camera := get_viewport().get_camera_3d()
	var yaw := 0.0
	if camera:
		var toward := camera.global_position - global_position
		yaw = atan2(toward.x, toward.z)
	_flames.global_transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), global_position)
