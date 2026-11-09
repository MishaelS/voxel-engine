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
var horizontal_collision := false

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
		"inventory_ids": inventory.ids, "inventory_counts": inventory.counts,
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
	var ids: PackedInt32Array = saved.get("inventory_ids", PackedInt32Array())
	var counts: PackedInt32Array = saved.get("inventory_counts", PackedInt32Array())
	for slot in mini(ids.size(), Inventory.SIZE):
		# Ids of blocks that no longer exist are dropped.
		var id := ids[slot] if ids[slot] < Blocks.count() else Blocks.AIR
		inventory.set_slot(slot, id, counts[slot] if slot < counts.size() else 0)


func is_creative() -> bool:
	return game_mode == GameMode.CREATIVE


func held_block() -> int:
	return inventory.id_at(selected_slot)


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
	in_water = _touches_water()

	if flying:
		if sneak_key:
			velocity.y -= FLY_VERTICAL
		if jumping:
			velocity.y += FLY_VERTICAL

	var start_x := _x
	var start_z := _z
	if in_water and not flying:
		if jumping:
			velocity.y += 0.04
		_move_relative(strafe, forward, AIR_ACCELERATION)
		_move(velocity)
		velocity *= 0.8
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
		var vertical := velocity.y
		_move(velocity)
		if flying:
			velocity.y = vertical * 0.6
		else:
			velocity.y = (velocity.y - GRAVITY) * AIR_DRAG
		velocity.x *= friction
		velocity.z *= friction

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


## The part of the move (dx, dy, dz) possible from feet (x, y, z): clipped
## against every solid block on the way, Y first, then X, then Z.
## Returned as 64-bit floats: Vector3 would round the clipped distances and
## let the box sink into blocks.
func _sweep(x: float, y: float, z: float, dx: float, dy: float, dz: float) -> PackedFloat64Array:
	var min_x := x - HALF_WIDTH
	var max_x := x + HALF_WIDTH
	var min_y := y
	var max_y := y + HEIGHT
	var min_z := z - HALF_WIDTH
	var max_z := z + HALF_WIDTH
	var boxes := _solid_blocks(
		minf(min_x, min_x + dx), minf(min_y, min_y + dy), minf(min_z, min_z + dz),
		maxf(max_x, max_x + dx), maxf(max_y, max_y + dy), maxf(max_z, max_z + dz))

	for b in boxes:
		if max_x > b.x and min_x < b.x + 1 and max_z > b.z and min_z < b.z + 1:
			if dy > 0.0 and max_y <= b.y:
				dy = minf(dy, b.y - max_y)
			elif dy < 0.0 and min_y >= b.y + 1:
				dy = maxf(dy, b.y + 1 - min_y)
	min_y += dy
	max_y += dy
	for b in boxes:
		if max_y > b.y and min_y < b.y + 1 and max_z > b.z and min_z < b.z + 1:
			if dx > 0.0 and max_x <= b.x:
				dx = minf(dx, b.x - max_x)
			elif dx < 0.0 and min_x >= b.x + 1:
				dx = maxf(dx, b.x + 1 - min_x)
	min_x += dx
	max_x += dx
	for b in boxes:
		if max_x > b.x and min_x < b.x + 1 and max_y > b.y and min_y < b.y + 1:
			if dz > 0.0 and max_z <= b.z:
				dz = minf(dz, b.z - max_z)
			elif dz < 0.0 and min_z >= b.z + 1:
				dz = maxf(dz, b.z + 1 - min_z)
	return PackedFloat64Array([dx, dy, dz])


## Positions of the colliding blocks touching the given box.
func _solid_blocks(min_x: float, min_y: float, min_z: float, max_x: float, max_y: float, max_z: float) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if world == null:
		return result
	var collides := Blocks.collides_table
	for y in range(floori(min_y), floori(max_y) + 1):
		if y < 0 or y >= WorldGenerator.HEIGHT:
			continue
		for z in range(floori(min_z), floori(max_z) + 1):
			for x in range(floori(min_x), floori(max_x) + 1):
				var pos := Vector3i(x, y, z)
				if collides[world.get_block(pos)] == 1:
					result.append(pos)
	return result


## True if the player's box at feet (x, y, z) touches no solid block.
func _free(x: float, y: float, z: float) -> bool:
	const E := 0.001
	return _solid_blocks(x - HALF_WIDTH + E, y + E, z - HALF_WIDTH + E,
		x + HALF_WIDTH - E, y + HEIGHT - E, z + HALF_WIDTH - E).is_empty()


func _fits(x: float, y: float, z: float) -> bool:
	return _free(x, y, z) and not _touches_water_at(x, y, z)


func _touches_water() -> bool:
	return _touches_water_at(_x, _y, _z)


## Water inside the box shrunk by 0.4 vertically (the classic check: feet
## and head have to be really in it).
func _touches_water_at(x: float, y: float, z: float) -> bool:
	if world == null:
		return false
	var water := Blocks.id_of("water")
	for by in range(floori(y + 0.4), floori(y + HEIGHT - 0.4) + 1):
		for bz in range(floori(z - HALF_WIDTH + 0.001), floori(z + HALF_WIDTH - 0.001) + 1):
			for bx in range(floori(x - HALF_WIDTH + 0.001), floori(x + HALF_WIDTH - 0.001) + 1):
				if world.get_block(Vector3i(bx, by, bz)) == water:
					return true
	return false


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
	if health == 0:
		_die()


func heal(amount: int) -> void:
	if not dead:
		health = mini(health + amount, MAX_HEALTH)


## Back to life at `position` with full health and food (death screen).
func respawn(position: Vector3) -> void:
	dead = false
	death_ticks = 0
	health = MAX_HEALTH
	food.reset()
	hurt_ticks = 0
	_invulnerable = 0
	flying = false
	global_position = position # picked up as a teleport


func _die() -> void:
	dead = true
	death_ticks = 0
	velocity = Vector3.ZERO
	sprinting = false
	# The classic game drops everything; there are no item entities yet, so
	# the items are lost (unless the keepInventory game rule is on).
	if world == null or not world.keep_inventory:
		inventory.clear()
	died.emit()


func _update_health() -> void:
	if _y < VOID_Y:
		damage(4, true)
	if not is_creative():
		food.tick(self, world == null or world.natural_regeneration)


func _can_sprint() -> bool:
	return is_creative() or flying or food.can_sprint()


## Hunger only in survival.
func _exhaust(amount: float) -> void:
	if not is_creative():
		food.add_exhaustion(amount)


## Exhaustion from breaking a block (BlockInteraction).
func block_broken() -> void:
	_exhaust(FoodStats.BREAK_BLOCK)


## Fall damage like the classic game: distance fallen since last standing,
## minus 3 blocks, when landing. Water and flying reset it.
func _track_fall() -> void:
	if flying or in_water:
		_fall_distance = 0.0
		return
	var dropped := _prev.y - _y
	if dropped > 0.0:
		_fall_distance += dropped
	if on_ground:
		if _fall_distance > SAFE_FALL:
			damage(ceili(_fall_distance - SAFE_FALL))
		_fall_distance = 0.0
