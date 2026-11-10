class_name Player
extends Node3D
## The player: movement with the physics of the classic game, the camera
## (eyes), the game mode and the inventory.
##
## Movement runs at a fixed 20 steps per second with the classic constants
## (velocities are in blocks per tick) and is interpolated between steps for
## rendering, so it feels the same at any frame rate:
## - walking: ground acceleration 0.1 scaled by ground friction (0.6, ice
##   0.98), air control 0.02, gravity 0.08 with drag 0.98, jump 0.42;
## - sprinting (Ctrl or double-tap W): x1.3 speed, sprint-jumps push
##   forward, FOV widens; stops when hitting a wall or sneaking;
## - sneaking (Shift): x0.3 speed, eyes slightly lower, can't walk off edges;
## - stepping up 0.6 blocks without jumping is allowed (like slabs later);
## - swimming: slow, gravity 0.02, Space swims up;
## - creative flying (double-tap Space): Space / Shift up and down, ends on
##   landing;
## - view bobbing while walking.
## Collision is box vs. block grid (the player is 0.6 x 1.8 x 0.6, eyes at
## 1.62), resolved axis by axis: Y, then X, then Z. The node's position is
## the feet; setting it from outside (spawn, /tp) teleports.

signal game_mode_changed(mode: GameMode)
## Health went to 0 (survival); the death screen offers to respawn.
signal died
## A message for the chat ("You can only sleep at night").
signal message(text: String)

enum GameMode { SURVIVAL, CREATIVE }

const TICK := 1.0 / 20.0
const HALF_WIDTH := 0.3
const HEIGHT := 1.8
const EYE_HEIGHT := 1.62
const SNEAK_EYE_DROP := 0.08
const STEP_HEIGHT := 0.6
const GRAVITY := 0.08
const AIR_DRAG := 0.98
const JUMP_VELOCITY := 0.42
const SPRINT_JUMP_BOOST := 0.2
const WALK_ACCELERATION := 0.1
const AIR_ACCELERATION := 0.02
const SPRINT_FACTOR := 1.3
const SNEAK_FACTOR := 0.3
const FLY_ACCELERATION := 0.05
const FLY_VERTICAL := 0.15
const DOUBLE_TAP_TICKS := 7
## Reach for breaking / placing: 4.5 blocks in survival, 5 in creative.
const REACH_SURVIVAL := 4.5
const REACH_CREATIVE := 5.0
const MOUSE_SENSITIVITY := 0.002
const MAX_HEALTH := 20
const HURT_TICKS := 10
## After a hit no damage is taken for 20 ticks, except a stronger hit in
## the first half (only the difference counts), like the classic game.
const INVULNERABLE_TICKS := 20
## Ticks of the death animation (the view falls over).
const DEATH_TICKS := 20
## Falls longer than this many blocks hurt: 1 half heart per extra block.
const SAFE_FALL := 3.0
## Below this height the void hurts (4 per half second), even in creative.
const VOID_Y := -64.0
## Ticks asleep before the night is skipped (the classic 100).
const SLEEP_TICKS := 100
## Blocks in a new player's hotbar (registry names).
const STARTING_BLOCKS := [
	"grass_plains", "dirt", "stone", "cobblestone", "oak_planks",
	"oak_log", "glass", "oak_leaves", "sand",
]

@export var world: VoxelWorld
@export var game_mode: GameMode = GameMode.CREATIVE:
	set(value):
		game_mode = value
		if value != GameMode.CREATIVE:
			flying = false
		game_mode_changed.emit(value)

var inventory := Inventory.new()
## Hotbar slot in hand (0..8).
var selected_slot := 0
var camera: Camera3D
## The block drawn in the hand (child of the camera).
var held_item: HeldItem

## Velocity in blocks per tick.
var velocity := Vector3.ZERO
var on_ground := false
var flying := false
## Health in half hearts (20 = 10 hearts), like the classic game. Only
## survival takes damage (falling, the void).
var health := MAX_HEALTH
var dead := false
## Ticks left of the hurt effect (camera tilt, blinking hearts); no new
## damage while it lasts.
var hurt_ticks := 0
## Hunger (food, saturation, exhaustion); heals and starves (survival).
var food := FoodStats.new()
## Ticks since death (the death animation).
var death_ticks := 0
var _invulnerable := 0
var _last_damage := 0
var sprinting := false
var sneaking := false
var in_water := false
var in_lava := false
## Ticks the player keeps burning (lava sets on fire for 15 s), like the
## classic game: 1 damage per second; water puts it out.
var fire_ticks := 0
## How fast the current pushes (blocks per tick per tick), the classic 0.014.
const CURRENT_PUSH := 0.014
const FIRE_TICKS := 300
const LAVA_DAMAGE := 4
var horizontal_collision := false
## Where the player respawns: the last bed slept in (INF = world spawn).
var spawn_point := Vector3.INF
## Asleep in a bed (ticks asleep), like the classic game.
var sleeping := false
## Eating progress 0..1 (-1 = not eating), for the hand animation.
var eating := -1.0
var sleep_ticks := 0
var _bed := Vector3i.ZERO
var _sleep_fade: ColorRect
var _fire: TextureRect

# Physics state in 64-bit floats (Vector3 is 32-bit: not precise enough for
# collision far from the origin). Feet, center of the box.
var _x := 0.0
var _y := 0.0
var _z := 0.0
var _prev := Vector3.ZERO
var _fall_distance := 0.0
var _accumulator := 0.0
var _last_rendered := Vector3.INF
var _yaw := 0.0
var _pitch := 0.0
var _jump_tap := 0  # ticks left to double-tap jump (toggle flying)
var _forward_tap := 0 # ticks left to double-tap forward (sprint)
var _eye := EYE_HEIGHT
# View bobbing and FOV (previous / current tick values, interpolated).
var _walked := 0.0
var _next_step := 1.0
var _prev_walked := 0.0
var _bob := 0.0
var _prev_bob := 0.0
var _fov_factor := 1.0
var _prev_fov_factor := 1.0


func _ready() -> void:
	camera = get_node_or_null("Camera")
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera"
		add_child(camera)
	camera.current = true
	held_item = HeldItem.new()
	held_item.player = self
	camera.add_child(held_item)
	_yaw = rotation.y
	rotation = Vector3(0, _yaw, 0)
	_teleported()
	# Falling asleep darkens the screen.
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_sleep_fade = ColorRect.new()
	_sleep_fade.color = Color(0.03, 0.03, 0.06, 0.0)
	_sleep_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sleep_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_sleep_fade)
	# Burning: flames rise from the bottom of the screen.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.85, 0.2, 0.0))
	gradient.set_color(1, Color(1.0, 0.35, 0.0, 0.85))
	gradient.add_point(0.6, Color(1.0, 0.55, 0.05, 0.25))
	var flames := GradientTexture2D.new()
	flames.gradient = gradient
	flames.fill_from = Vector2(0.5, 0.45)
	flames.fill_to = Vector2(0.5, 1.0)
	_fire = TextureRect.new()
	_fire.texture = flames
	_fire.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fire.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fire.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fire.visible = false
	layer.add_child(_fire)
	var save := WorldSave.current
	if save:
		game_mode = save.game_mode as GameMode
	var saved: Dictionary = save.state.get("player", {}) if save else {}
	if not saved.is_empty():
		load_state(saved)
	elif is_creative():
		# A new creative world starts with some blocks; survival with nothing.
		for block_name: String in STARTING_BLOCKS:
			inventory.add(Blocks.id_of(block_name), 1)


## Player state for the world save (the position is restored by VoxelWorld).
func save_state() -> Dictionary:
	return {
		"position": Vector3(_x, _y, _z), "yaw": _yaw, "pitch": _pitch,
		"flying": flying, "selected_slot": selected_slot,
		"inventory": inventory.save_state(), "spawn": spawn_point,
		"health": health if not dead else MAX_HEALTH,
		"food": food.save_state() if not dead else FoodStats.new().save_state(),
	}


func load_state(saved: Dictionary) -> void:
	_yaw = saved.get("yaw", _yaw)
	_pitch = saved.get("pitch", 0.0)
	flying = saved.get("flying", false) and is_creative()
	selected_slot = saved.get("selected_slot", 0)
	health = clampi(saved.get("health", MAX_HEALTH), 1, MAX_HEALTH)
	food.load_state(saved.get("food", {}))
	spawn_point = saved.get("spawn", Vector3.INF)
	if saved.has("inventory"):
		inventory.load_state(saved.inventory)
	else: # older saves
		inventory.load_state({"ids": saved.get("inventory_ids", PackedInt32Array()),
			"counts": saved.get("inventory_counts", PackedInt32Array())})


func is_creative() -> bool:
	return game_mode == GameMode.CREATIVE


func held_block() -> int:
	return inventory.id_at(selected_slot)


## Throws items out in front of the player (Q, or out of the inventory window).
func throw_items(id: int, count: int, damage: int = 0) -> void:
	if world and id != Blocks.AIR and count > 0:
		world.items.throw_from(eye_position(), look_direction(), id, count, damage)


## Where to respawn: next to the bed if it is still there, else the world spawn.
func spawn_position() -> Vector3:
	if world and spawn_point != Vector3.INF:
		var bed := Vector3i(spawn_point.floor())
		if Blocks.family_of(world.get_block(bed)).begins_with("bed_"):
			return Vector3(bed) + Vector3(0.5, Blocks.height_table[world.get_block(bed)], 0.5)
		spawn_point = Vector3.INF
		message.emit(Lang.t("Your home bed was missing or obstructed"))
	return world.find_spawn() if world else Vector3.ZERO


## Lies down in the bed at `bed` (its head half) like the classic game:
## only at night; the bed becomes the spawn point; after SLEEP_TICKS the
## night is skipped to the morning.
func sleep_in(bed: Vector3i) -> void:
	if world == null or sleeping or dead:
		return
	if not DayNightCycle.is_night(world.clock.day_time):
		message.emit(Lang.t("You can only sleep at night"))
		return
	if Vector3(bed).distance_to(global_position) > 3.0:
		message.emit(Lang.t("You may not rest now, the bed is too far away"))
		return
	sleeping = true
	sleep_ticks = 0
	_bed = bed
	spawn_point = Vector3(bed) + Vector3(0.5, 0.0, 0.5)
	velocity = Vector3.ZERO
	sprinting = false
	global_position = Vector3(bed) + Vector3(0.5, Blocks.height_table[world.get_block(bed)], 0.5)
	_teleported()


func wake_up() -> void:
	if not sleeping:
		return
	sleeping = false
	sleep_ticks = 0
	_sleep_fade.color.a = 0.0


## Arm swing (breaking, placing), shown by the block in hand.
func swing() -> void:
	held_item.swing()


func reach() -> float:
	return REACH_CREATIVE if is_creative() else REACH_SURVIVAL


## Eye position and look direction without view bobbing (for targeting).
func eye_position() -> Vector3:
	return global_position + Vector3(0, _eye, 0)


func look_direction() -> Vector3:
	return Vector3(-sin(_yaw) * cos(_pitch), sin(_pitch), -cos(_yaw) * cos(_pitch))


## True if a block at `pos` would overlap the player (placing is refused).
func intersects_block(pos: Vector3i) -> bool:
	return _x + HALF_WIDTH > pos.x and _x - HALF_WIDTH < pos.x + 1 \
		and _y + HEIGHT > pos.y and _y < pos.y + 1 \
		and _z + HALF_WIDTH > pos.z and _z - HALF_WIDTH < pos.z + 1


# --- Input ----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if GameInput.is_blocked():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled() # this click only captures
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity: float = MOUSE_SENSITIVITY * Settings.get_value("mouse_sensitivity") / 100.0
		var invert := -1.0 if Settings.get_value("invert_mouse") else 1.0
		_yaw -= event.relative.x * sensitivity
		_pitch = clampf(_pitch - event.relative.y * sensitivity * invert, -PI / 2 + 0.001, PI / 2 - 0.001)
	elif event.is_action_pressed("jump") and not event.is_echo():
		if is_creative():
			if _jump_tap > 0:
				flying = not flying
				_jump_tap = 0
			else:
				_jump_tap = DOUBLE_TAP_TICKS
	elif event.is_action_pressed("move_forward") and not event.is_echo():
		if _forward_tap > 0 and not sneaking:
			sprinting = true
		_forward_tap = DOUBLE_TAP_TICKS


# --- Frame: interpolation and camera ------------------------------------------

func _process(delta: float) -> void:
	if global_position.distance_squared_to(_last_rendered) > 1e-6:
		_teleported() # moved from outside (spawn, /tp)
	_accumulator += delta
	var steps := 0
	while _accumulator >= TICK and steps < 10:
		_accumulator -= TICK
		_tick()
		steps += 1
	if steps == 10:
		_accumulator = 0.0
	var alpha := _accumulator / TICK
	var current := Vector3(_x, _y, _z)
	global_position = _prev.lerp(current, alpha)
	_last_rendered = global_position
	rotation = Vector3(0, _yaw, 0)
	_update_camera(alpha, delta)
	_sleep_fade.color.a = clampf((sleep_ticks + alpha) / SLEEP_TICKS, 0.0, 1.0) * 0.95 if sleeping else 0.0
	_fire.visible = fire_ticks > 0 and not dead
	if _fire.visible:
		_fire.modulate.a = 0.75 + 0.25 * sin(Time.get_ticks_msec() / 60.0)


func _teleported() -> void:
	_x = global_position.x
	_y = global_position.y
	_z = global_position.z
	_prev = global_position
	_last_rendered = global_position
	velocity = Vector3.ZERO
	_accumulator = 0.0
	_fall_distance = 0.0


func _update_camera(alpha: float, delta: float) -> void:
	var target_eye := EYE_HEIGHT - (SNEAK_EYE_DROP if sneaking else 0.0)
	if sleeping:
		target_eye = 0.25 # lying in the bed
	_eye = move_toward(_eye, target_eye, delta * 1.0)
	var eye := _eye
	var death_roll := 0.0
	if dead:
		# The classic death: the body falls over sideways, the view with it.
		var t := minf((death_ticks + alpha) / DEATH_TICKS, 1.0)
		t = sqrt(t)
		eye = lerpf(_eye, 0.2, t)
		death_roll = deg_to_rad(40.0) * t
	var transform_3d := Transform3D(Basis(Vector3.BACK, death_roll) * Basis(Vector3.RIGHT, _pitch), Vector3(0, eye, 0))
	if Settings.get_value("view_bobbing"):
		# The classic view bobbing: a figure-eight sway that follows steps.
		var walked := -lerpf(_prev_walked, _walked, alpha)
		var bob := lerpf(_prev_bob, _bob, alpha)
		var phase := walked * PI
		var sway := Transform3D(Basis(), Vector3(sin(phase) * bob * 0.5, -absf(cos(phase) * bob), 0))
		sway = sway * Transform3D(Basis(Vector3.BACK, deg_to_rad(sin(phase) * bob * 3.0)), Vector3.ZERO)
		sway = sway * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(absf(cos(phase - 0.2) * bob) * 5.0)), Vector3.ZERO)
		transform_3d = Transform3D(Basis(), transform_3d.origin) * sway * Transform3D(transform_3d.basis, Vector3.ZERO)
	if hurt_ticks > 0:
		# The classic hurt tilt: a quick roll that settles back.
		var f := clampf((hurt_ticks - alpha) / HURT_TICKS, 0.0, 1.0)
		var roll := sin(f * f * f * f * PI) * deg_to_rad(14.0)
		transform_3d = Transform3D(Basis(Vector3.BACK, -roll), Vector3.ZERO) * transform_3d
	camera.transform = transform_3d
	var base_fov: float = Settings.get_value("fov")
	camera.fov = clampf(base_fov * lerpf(_prev_fov_factor, _fov_factor, alpha), 1.0, 170.0)


# --- Tick: physics ----------------------------------------------------------------

func _tick() -> void:
	_prev = Vector3(_x, _y, _z)
	_prev_walked = _walked
	_prev_bob = _bob
	_prev_fov_factor = _fov_factor
	_jump_tap = maxi(_jump_tap - 1, 0)
	_forward_tap = maxi(_forward_tap - 1, 0)
	hurt_ticks = maxi(hurt_ticks - 1, 0)
	_invulnerable = maxi(_invulnerable - 1, 0)
	if dead:
		death_ticks += 1
		return
	_update_health()
	if sleeping:
		_tick_sleep()
		return
	if world and not world.is_inside(Vector3i(floori(_x), 0, floori(_z))) and _y > 0.0:
		return # the ground is not loaded yet: wait in place

	var playing := not GameInput.is_blocked()
	var forward := 0.0
	var strafe := 0.0
	var jumping := false
	var sneak_key := false
	if playing:
		forward = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
		strafe = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
		jumping = Input.is_action_pressed("jump")
		sneak_key = Input.is_action_pressed("sneak")
		if Input.is_action_pressed("sprint") and forward > 0.0 and _can_sprint():
			sprinting = true
	sneaking = sneak_key and not flying
	if sneaking:
		forward *= SNEAK_FACTOR
		strafe *= SNEAK_FACTOR
	if forward <= 0.0 or sneaking or horizontal_collision or not _can_sprint():
		sprinting = false
	forward *= 0.98
	strafe *= 0.98
	var was_in_water := in_water
	in_water = _touches_liquid_at(_x, _y, _z, "water")
	if in_water and not was_in_water and velocity.y < -0.2:
		# Falling into water: a splash, louder the faster.
		Sounds.play("random/splash", Vector3(_x, _y, _z), clampf(-velocity.y, 0.2, 1.0), randf_range(0.6, 1.4))
	in_lava = _touches_liquid_at(_x, _y, _z, "lava")
	_burn()

	if flying:
		if sneak_key:
			velocity.y -= FLY_VERTICAL
		if jumping:
			velocity.y += FLY_VERTICAL

	var start_x := _x
	var start_z := _z
	if (in_water or in_lava) and not flying:
		if jumping:
			velocity.y += 0.04
		_move_relative(strafe, forward, AIR_ACCELERATION)
		if in_water:
			velocity += _current() * CURRENT_PUSH
		_move(velocity)
		# Lava is thicker than water: much slower.
		velocity *= 0.5 if in_lava else 0.8
		velocity.y -= 0.02
		if horizontal_collision and _fits(_x + velocity.x, _y + velocity.y + 0.6, _z + velocity.z):
			velocity.y = 0.3 # climb out onto the shore
	else:
		if jumping and on_ground and not flying:
			velocity.y = JUMP_VELOCITY
			_exhaust(FoodStats.SPRINT_JUMP if sprinting else FoodStats.JUMP)
			if sprinting:
				velocity.x -= sin(_yaw) * SPRINT_JUMP_BOOST
				velocity.z -= cos(_yaw) * SPRINT_JUMP_BOOST
		var friction := 0.91
		if on_ground:
			friction = _ground_slipperiness() * 0.91
		var acceleration := AIR_ACCELERATION * (SPRINT_FACTOR if sprinting else 1.0)
		if flying:
			acceleration = FLY_ACCELERATION * (2.0 if sprinting else 1.0)
		elif on_ground:
			acceleration = WALK_ACCELERATION * (SPRINT_FACTOR if sprinting else 1.0) \
				* 0.16277136 / (friction * friction * friction)
		_move_relative(strafe, forward, acceleration)
		# Ladders like the classic game: slow sideways, slow fall (none while
		# sneaking), walking into the ladder climbs it.
		var climbing := not flying and _on_ladder()
		if climbing:
			velocity.x = clampf(velocity.x, -0.15, 0.15)
			velocity.z = clampf(velocity.z, -0.15, 0.15)
			velocity.y = maxf(velocity.y, -0.15)
			if sneaking and velocity.y < 0.0:
				velocity.y = 0.0
			_fall_distance = 0.0
		var vertical := velocity.y
		_move(velocity)
		if climbing and horizontal_collision:
			velocity.y = 0.2
		if flying:
			velocity.y = vertical * 0.6
		else:
			velocity.y = (velocity.y - GRAVITY) * AIR_DRAG
		velocity.x *= friction
		velocity.z *= friction
		if _in_web():
			# Cobwebs hold you: almost no movement (the classic game).
			velocity.x *= 0.25
			velocity.y *= 0.05
			velocity.z *= 0.25
			_fall_distance = 0.0

	if flying and on_ground:
		flying = false # landed
	_track_fall()

	# View bobbing and FOV follow the movement of this tick.
	var moved := sqrt((_x - start_x) * (_x - start_x) + (_z - start_z) * (_z - start_z))
	if in_water:
		_exhaust(moved * FoodStats.SWIM_PER_BLOCK)
	elif on_ground:
		_exhaust(moved * (FoodStats.SPRINT_PER_BLOCK if sprinting else FoodStats.WALK_PER_BLOCK))
	_walked += moved * 0.6
	# A step sound every whole step (the classic distance), not while sneaking.
	if on_ground and not sneaking and not in_water and _walked > _next_step:
		_next_step = floorf(_walked) + 1.0
		var below := world.get_block(Vector3i(floori(_x), floori(_y - 0.2), floori(_z))) if world else Blocks.AIR
		if below != Blocks.AIR:
			Sounds.play_block("step", below, Vector3(_x, _y, _z))
	var bob_target := minf(0.1, sqrt(velocity.x * velocity.x + velocity.z * velocity.z))
	if not on_ground or flying:
		bob_target = 0.0
	_bob += (bob_target - _bob) * 0.4
	var fov_target := 1.0
	if sprinting:
		fov_target = (SPRINT_FACTOR + 1.0) / 2.0
	if flying:
		fov_target *= 1.1
	_fov_factor += (fov_target - _fov_factor) * 0.5


## Accelerates along the look direction (yaw only) like the classic game.
func _move_relative(strafe: float, forward: float, acceleration: float) -> void:
	var length := strafe * strafe + forward * forward
	if length < 1e-4:
		return
	length = maxf(sqrt(length), 1.0)
	var f := acceleration / length
	strafe *= f
	forward *= f
	var s := sin(_yaw)
	var c := cos(_yaw)
	velocity.x += strafe * c - forward * s
	velocity.z += -strafe * s - forward * c


# --- Collision ----------------------------------------------------------------------

## Moves by `motion` (blocks), sliding along blocks, stepping up to
## STEP_HEIGHT and (while sneaking) not walking off edges.
func _move(motion: Vector3) -> void:
	var dx := motion.x
	var dy := motion.y
	var dz := motion.z

	if sneaking and on_ground:
		# Shrink the move until there is ground under the player again.
		while dx != 0.0 and _free(_x + dx, _y - 1.0, _z):
			dx = 0.0 if absf(dx) < 0.05 else dx - signf(dx) * 0.05
		while dz != 0.0 and _free(_x, _y - 1.0, _z + dz):
			dz = 0.0 if absf(dz) < 0.05 else dz - signf(dz) * 0.05
		while dx != 0.0 and dz != 0.0 and _free(_x + dx, _y - 1.0, _z + dz):
			dx = 0.0 if absf(dx) < 0.05 else dx - signf(dx) * 0.05
			dz = 0.0 if absf(dz) < 0.05 else dz - signf(dz) * 0.05

	var wanted_x := dx
	var wanted_y := dy
	var wanted_z := dz
	var result := _sweep(_x, _y, _z, dx, dy, dz)

	# Step up: retry the horizontal move from STEP_HEIGHT higher, then settle
	# down; keep it if it got further.
	var blocked := result[0] != wanted_x or result[2] != wanted_z
	if blocked and (on_ground or (wanted_y < 0.0 and result[1] != wanted_y)):
		var up := _sweep(_x, _y, _z, 0.0, STEP_HEIGHT, 0.0)
		var side := _sweep(_x, _y + up[1], _z, wanted_x, 0.0, wanted_z)
		var down := _sweep(_x + side[0], _y + up[1], _z + side[2], 0.0, -up[1] + minf(wanted_y, 0.0), 0.0)
		if side[0] * side[0] + side[2] * side[2] > result[0] * result[0] + result[2] * result[2]:
			result = PackedFloat64Array([side[0], up[1] + down[1], side[2]])

	_x += result[0]
	_y += result[1]
	_z += result[2]
	horizontal_collision = result[0] != wanted_x or result[2] != wanted_z
	on_ground = wanted_y < 0.0 and result[1] != wanted_y
	if result[0] != wanted_x:
		velocity.x = 0.0
	if result[2] != wanted_z:
		velocity.z = 0.0
	if result[1] != wanted_y:
		velocity.y = 0.0


## The part of the move (dx, dy, dz) possible from feet (x, y, z), see
## EntityPhysics.sweep().
func _sweep(x: float, y: float, z: float, dx: float, dy: float, dz: float) -> PackedFloat64Array:
	return EntityPhysics.sweep(world, x, y, z, HALF_WIDTH, HEIGHT, dx, dy, dz)


func _solid_blocks(min_x: float, min_y: float, min_z: float, max_x: float, max_y: float, max_z: float) -> Array[AABB]:
	return EntityPhysics.solid_boxes(world, min_x, min_y, min_z, max_x, max_y, max_z)


## True if the player's box at feet (x, y, z) touches no solid block.
func _free(x: float, y: float, z: float) -> bool:
	const E := 0.001
	return _solid_blocks(x - HALF_WIDTH + E, y + E, z - HALF_WIDTH + E,
		x + HALF_WIDTH - E, y + HEIGHT - E, z + HALF_WIDTH - E).is_empty()


func _fits(x: float, y: float, z: float) -> bool:
	return _free(x, y, z) and not _touches_liquid_at(x, y, z, "water") and not _touches_liquid_at(x, y, z, "lava")


## Liquid of a family ("water", "lava") inside the box shrunk by 0.4
## vertically (the classic check: feet and head have to be really in it).
func _touches_liquid_at(x: float, y: float, z: float, family: String) -> bool:
	if world == null:
		return false
	var liquid := Blocks.liquid_table
	for by in range(floori(y + 0.4), floori(y + HEIGHT - 0.4) + 1):
		for bz in range(floori(z - HALF_WIDTH + 0.001), floori(z + HALF_WIDTH - 0.001) + 1):
			for bx in range(floori(x - HALF_WIDTH + 0.001), floori(x + HALF_WIDTH - 0.001) + 1):
				var id := world.get_block(Vector3i(bx, by, bz))
				if liquid[id] == 1 and Blocks.family_of(id) == family:
					return true
	return false


## On a ladder: the block at the feet is climbable.
func _on_ladder() -> bool:
	return world != null and Blocks.get_type(world.get_block(Vector3i(floori(_x), floori(_y), floori(_z)))).climbable


func _in_web() -> bool:
	if world == null:
		return false
	for y in [floori(_y + 0.1), floori(_y + 1.0)]:
		if Blocks.get_type(world.get_block(Vector3i(floori(_x), y, floori(_z)))).name == "cobweb":
			return true
	return false


## The push of flowing water on the player: the currents of all water
## blocks the box touches, as one direction (the classic game).
func _current() -> Vector3:
	var flow := Vector3.ZERO
	for by in range(floori(_y + 0.4), floori(_y + HEIGHT - 0.4) + 1):
		for bz in range(floori(_z - HALF_WIDTH + 0.001), floori(_z + HALF_WIDTH - 0.001) + 1):
			for bx in range(floori(_x - HALF_WIDTH + 0.001), floori(_x + HALF_WIDTH - 0.001) + 1):
				flow += LiquidBehavior.flow_vector(world, Vector3i(bx, by, bz))
	return flow.normalized() if flow.length_squared() > 1e-6 else Vector3.ZERO


## Lava hurts (4 at a time) and sets on fire; burning hurts 1 per second;
## water puts the fire out (the classic game). Creative players don't burn.
func _burn() -> void:
	if in_lava and not is_creative():
		damage(LAVA_DAMAGE)
		fire_ticks = FIRE_TICKS
	if EntityPhysics.touches_cactus(world, _x, _y, _z, HALF_WIDTH, HEIGHT):
		damage(1) # cactus pricks
	if not in_lava and not is_creative() and EntityPhysics.touches_fire(world, _x, _y, _z, HALF_WIDTH, HEIGHT):
		# Walking in fire: 1 damage and 8 seconds of burning (the classic game).
		damage(1)
		fire_ticks = maxi(fire_ticks, 160)
	if in_water:
		fire_ticks = 0
	if fire_ticks > 0:
		fire_ticks -= 1
		if fire_ticks % 20 == 0 and not in_lava:
			damage(1)
	if is_creative():
		fire_ticks = 0


func _ground_slipperiness() -> float:
	if world == null:
		return 0.6
	var below := world.get_block(Vector3i(floori(_x), floori(_y - 0.5), floori(_z)))
	return Blocks.get_type(below).slipperiness if below != Blocks.AIR else 0.6


# --- Health ---------------------------------------------------------------------------

## Takes `amount` half hearts of damage, like the classic game: survival
## only (unless `always`, as for the void); for 20 ticks after a hit only a
## stronger hit counts (just the difference), and the hurt effect (camera
## tilt, blinking hearts) plays for full hits only.
func damage(amount: int, always: bool = false) -> void:
	if dead or amount <= 0 or (is_creative() and not always):
		return
	wake_up()
	if _invulnerable > INVULNERABLE_TICKS / 2:
		if amount <= _last_damage:
			return
		health = maxi(health - (amount - _last_damage), 0)
		_last_damage = amount
	else:
		health = maxi(health - amount, 0)
		_last_damage = amount
		_invulnerable = INVULNERABLE_TICKS
		hurt_ticks = HURT_TICKS
	_exhaust(FoodStats.DAMAGE)
	Sounds.play("damage/hurt", null, 1.0, randf_range(0.8, 1.2))
	if health == 0:
		_die()


func heal(amount: int) -> void:
	if not dead:
		health = mini(health + amount, MAX_HEALTH)


## Back to life at `position` with full health and food (death screen).
func respawn(position: Vector3) -> void:
	wake_up()
	fire_ticks = 0
	dead = false
	death_ticks = 0
	health = MAX_HEALTH
	food.reset()
	hurt_ticks = 0
	_invulnerable = 0
	flying = false
	global_position = position # picked up as a teleport


func _die() -> void:
	Sounds.play("damage/hurt", null, 1.0, 0.7)
	dead = true
	death_ticks = 0
	velocity = Vector3.ZERO
	sprinting = false
	wake_up()
	# The classic game drops everything around the player (unless the
	# keepInventory game rule is on).
	if world == null or not world.keep_inventory:
		if world:
			var center := global_position + Vector3(0, 1.0, 0)
			for slot in inventory.size():
				if inventory.count_at(slot) > 0:
					world.items.scatter(center, inventory.id_at(slot), inventory.count_at(slot), inventory.damage_at(slot))
		inventory.clear()
	died.emit()


func _update_health() -> void:
	if _y < VOID_Y:
		damage(4, true)
	if not is_creative():
		if world == null or world.hunger:
			food.tick(self, world == null or world.natural_regeneration)


func _can_sprint() -> bool:
	return is_creative() or flying or food.can_sprint() or (world != null and not world.hunger)


## Hunger only in survival.
func _exhaust(amount: float) -> void:
	if not is_creative():
		food.add_exhaustion(amount)


## Asleep: after SLEEP_TICKS the night is skipped to the morning (06:00
## of the next day) and the player wakes up; getting hurt, the bed
## disappearing or the day coming wakes up early.
func _tick_sleep() -> void:
	sleep_ticks += 1
	if not Blocks.family_of(world.get_block(_bed)).begins_with("bed_"):
		wake_up()
		return
	if sleep_ticks >= SLEEP_TICKS:
		var day_time := world.clock.day_time
		world.clock.add_day_time(WorldClock.TICKS_PER_DAY - fposmod(day_time, WorldClock.TICKS_PER_DAY))
		wake_up()


## Eats a food item (BlockInteraction, after holding the use button).
## Eats a food item: with hunger it fills the food bar; without (Beta
## 1.7.3) it heals right away. A golden apple always heals fully.
func eat(item_id: int) -> void:
	var item := Items.get_type(item_id)
	if item == null or item.food <= 0:
		return
	if world == null or world.hunger:
		food.eat(item.food, item.saturation)
		if item.name == "golden_apple":
			heal(item.heal)
	else:
		heal(item.heal)


## Whether eating makes sense now (hunger: not full; Beta: hurt), golden
## apples always.
func can_eat(item_id: int) -> bool:
	var item := Items.get_type(item_id)
	if item == null or item.food <= 0:
		return false
	if is_creative() or item.name == "golden_apple":
		return true
	if world == null or world.hunger:
		return food.food < FoodStats.MAX_FOOD
	return health < MAX_HEALTH


## Exhaustion from breaking a block (BlockInteraction).
func block_broken() -> void:
	_exhaust(FoodStats.BREAK_BLOCK)


## Fall damage like the classic game: distance fallen since last standing,
## minus 3 blocks, when landing. Water and flying reset it.
func _track_fall() -> void:
	if flying or in_water or in_lava:
		_fall_distance = 0.0
		return
	var dropped := _prev.y - _y
	if dropped > 0.0:
		_fall_distance += dropped
	if on_ground:
		if _fall_distance > SAFE_FALL:
			damage(ceili(_fall_distance - SAFE_FALL))
		if _fall_distance > 0.75 and world:
			# Landing on farmland tramples it.
			FarmBehavior.trample(world, Vector3i(floori(_x), floori(_y - 0.1), floori(_z)))
		_fall_distance = 0.0
