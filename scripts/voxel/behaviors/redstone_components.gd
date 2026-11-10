class_name RedstoneComponents
extends RefCounted
## The redstone parts like Beta 1.7.3 (their power is in Redstone):
## - redstone torch: on until the block it stands on or hangs from gets
##   power (2 ticks later), then off - an inverter; on, it powers everything
##   around except its own block and strongly the block above it; light 7.
##   Toggling more than 8 times in 100 ticks burns it out (a fizz and smoke)
##   for a while;
## - repeater: power at its back reaches its front after 1..4 delays of 2
##   ticks (right-click changes the delay), strongly powering the block in
##   front; it only takes and gives power along its line;
## - lever: right-click switches it; on, it powers around and strongly the
##   block it is on;
## - stone button: right-click pushes it for 20 ticks;
## - stone and wooden pressure plates: pushed while the player or a creature
##   (wooden: also dropped items) is on them, checked every 20 ticks; they
##   strongly power the block under them.
## Levers, buttons and torches drop when what holds them goes.

const SOURCES := ["redstone_torch", "redstone_wall_torch", "unlit_redstone_torch", "unlit_redstone_wall_torch",
	"lever", "stone_button", "stone_pressure_plate", "wooden_pressure_plate"]
const TORCH_DELAY := 2
const BUTTON_TICKS := 20
const PLATE_TICKS := 20
const BURNOUT_TOGGLES := 8
const BURNOUT_TICKS := 100

## pos -> game times the torch there toggled (burnout).
static var _toggles := {}


# --- States ---------------------------------------------------------------------------

## Torch: lit, attached direction (from the torch to its block).
static func torch_info(id: int) -> Array:
	var family := Blocks.family_of(id)
	var lit := not family.begins_with("unlit_")
	if family.ends_with("wall_torch"):
		return [lit, -Blocks.FACING_DIRECTIONS[Blocks.family_ids(family).find(id)]]
	return [lit, Vector3i.DOWN]


static func torch_id(lit: bool, attached: Vector3i) -> int:
	var prefix := "" if lit else "unlit_"
	if attached == Vector3i.DOWN:
		return Blocks.variant(prefix + "redstone_torch")
	return Blocks.variant(prefix + "redstone_wall_torch", Blocks.FACING_DIRECTIONS.find(-attached))


## Lever: [on, attached direction, axis (floor levers: 0 along x, 1 along z)].
static func lever_info(id: int) -> Array:
	var index := Blocks.family_ids("lever").find(id)
	var place := index / 2
	var attached := Vector3i.DOWN if place < 2 else -Blocks.FACING_DIRECTIONS[place - 2]
	return [index % 2 == 1, attached, place]


static func lever_id(on: bool, place: int) -> int:
	return Blocks.family_ids("lever")[place * 2 + (1 if on else 0)]


## Button: [pressed, attached direction].
static func button_info(id: int) -> Array:
	var index := Blocks.family_ids("stone_button").find(id)
	return [index % 2 == 1, -Blocks.FACING_DIRECTIONS[index / 2]]


## Repeater: facing (output direction index), delay 1..4, powered.
static func repeater_info(id: int) -> Array:
	var index := Blocks.family_ids("repeater").find(id)
	return [index / 8, (index / 2) % 4 + 1, index % 2 == 1]


static func repeater_id(facing: int, delay: int, powered: bool) -> int:
	return Blocks.family_ids("repeater")[(facing * 4 + delay - 1) * 2 + (1 if powered else 0)]


static func repeater_out(id: int) -> Vector3i:
	return Blocks.FACING_DIRECTIONS[repeater_info(id)[0]]


static func plate_pressed(id: int) -> bool:
	return Blocks.family_ids(Blocks.family_of(id)).find(id) == 1


# --- Power ------------------------------------------------------------------------------

static func weak(_world: VoxelWorld, _pos: Vector3i, id: int, toward: Vector3i) -> bool:
	var family := Blocks.family_of(id)
	match family:
		"redstone_torch", "redstone_wall_torch":
			return toward != torch_info(id)[1]
		"lever":
			return lever_info(id)[0]
		"stone_button":
			return button_info(id)[0]
		"stone_pressure_plate", "wooden_pressure_plate":
			return plate_pressed(id)
		"repeater":
			var info := repeater_info(id)
			return info[2] and toward == Blocks.FACING_DIRECTIONS[info[0]]
	return false


static func strong(world: VoxelWorld, pos: Vector3i, id: int, toward: Vector3i) -> bool:
	var family := Blocks.family_of(id)
	match family:
		"redstone_torch", "redstone_wall_torch":
			return toward == Vector3i.UP
		"lever":
			var info := lever_info(id)
			return info[0] and toward == info[1]
		"stone_button":
			var info := button_info(id)
			return info[0] and toward == info[1]
		"stone_pressure_plate", "wooden_pressure_plate":
			return plate_pressed(id) and toward == Vector3i.DOWN
		"repeater":
			return weak(world, pos, id, toward)
	return false


# --- Torches --------------------------------------------------------------------------

static func on_torch_update(world: VoxelWorld, pos: Vector3i) -> void:
	TorchBehavior.on_update(world, pos)
	var id := world.get_block(pos)
	if not Blocks.family_of(id).ends_with("redstone_torch") and not Blocks.family_of(id).ends_with("redstone_wall_torch"):
		return
	var info := torch_info(id)
	if _torch_input(world, pos, info[1]) == info[0]:
		world.schedule_tick(pos, TORCH_DELAY)


## The block the torch is on gives it power (it turns off then).
static func _torch_input(world: VoxelWorld, pos: Vector3i, attached: Vector3i) -> bool:
	return Redstone.provides(world, pos + attached, -attached)


static func torch_tick(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	var info := torch_info(id)
	var times: Array = _toggles.get(pos, [])
	var now := world.clock.game_time
	times = times.filter(func(t: int) -> bool: return now - t < BURNOUT_TICKS)
	_toggles[pos] = times
	var powered := _torch_input(world, pos, info[1])
	if info[0] and powered:
		_set_torch(world, pos, false, info[1])
		times.append(now)
		if times.size() > BURNOUT_TOGGLES:
			# Burnt out: a fizz and smoke; it stays off until things settle.
			Sounds.play("random/fizz", Vector3(pos) + Vector3(0.5, 0.5, 0.5), 0.5, 2.6 + (randf() - randf()) * 0.8)
			world.particles.smoke(Vector3(pos) + Vector3(0.5, 0.6, 0.5), 5)
	elif not info[0] and not powered and times.size() <= BURNOUT_TOGGLES:
		_set_torch(world, pos, true, info[1])
		times.append(now)
	elif not info[0] and not powered:
		world.schedule_tick(pos, 160) # burnt out: try again later


static func _set_torch(world: VoxelWorld, pos: Vector3i, lit: bool, attached: Vector3i) -> void:
	world.set_block(pos, torch_id(lit, attached), false)
	Redstone.notify_around(world, pos)


static func torch_display_tick(world: VoxelWorld, pos: Vector3i, rng: RandomNumberGenerator) -> void:
	var info := torch_info(world.get_block(pos))
	if not info[0]:
		return
	var point := Vector3(pos) + Vector3(0.5 + rng.randf_range(-0.1, 0.1), 0.75, 0.5 + rng.randf_range(-0.1, 0.1))
	if info[1] != Vector3i.DOWN:
		point += -Vector3(info[1]) * 0.27 + Vector3(0, 0.1, 0)
	world.particles.redstone(point, 15)


# --- Repeaters --------------------------------------------------------------------------

static func on_repeater_update(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	if Blocks.family_of(id) != "repeater":
		return
	if not Redstone.is_solid(world.get_block(pos + Vector3i.DOWN)):
		world.destroy_block(pos, true, true)
		return
	var info := repeater_info(id)
	if _repeater_input(world, pos, info[0]) != info[2]:
		world.schedule_tick(pos, info[1] * 2)


static func _repeater_input(world: VoxelWorld, pos: Vector3i, facing: int) -> bool:
	var out := Blocks.FACING_DIRECTIONS[facing]
	var back := pos - out
	return Redstone.provides(world, back, out) or Redstone.wire_power(world.get_block(back)) > 0


static func repeater_tick(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	var info := repeater_info(id)
	var input := _repeater_input(world, pos, info[0])
	if input != info[2]:
		world.set_block(pos, repeater_id(info[0], info[1], input), false)
		Redstone.notify_around(world, pos)
		Redstone.notify_around(world, pos + Blocks.FACING_DIRECTIONS[info[0]])


## Right-click: the next delay (1 -> 4 -> 1).
static func cycle_delay(world: VoxelWorld, pos: Vector3i) -> void:
	var info := repeater_info(world.get_block(pos))
	world.set_block(pos, repeater_id(info[0], info[1] % 4 + 1, info[2]), false)
	Sounds.play("random/click", Vector3(pos) + Vector3(0.5, 0.5, 0.5), 0.3, 0.6)


# --- Levers and buttons -------------------------------------------------------------------

static func toggle_lever(world: VoxelWorld, pos: Vector3i) -> void:
	var info := lever_info(world.get_block(pos))
	world.set_block(pos, lever_id(not info[0], info[2]), false)
	Sounds.play("random/click", Vector3(pos) + Vector3(0.5, 0.5, 0.5), 0.3, 0.6 if not info[0] else 0.5)
	Redstone.notify_around(world, pos)
	Redstone.notify_around(world, pos + info[1])


static func press_button(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	var info := button_info(id)
	if info[0]:
		return
	world.set_block(pos, Blocks.family_ids("stone_button")[Blocks.family_ids("stone_button").find(id) + 1], false)
	Sounds.play("random/click", Vector3(pos) + Vector3(0.5, 0.5, 0.5), 0.3, 0.6)
	Redstone.notify_around(world, pos)
	Redstone.notify_around(world, pos + info[1])
	world.schedule_tick(pos, BUTTON_TICKS)


static func button_tick(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	var info := button_info(id)
	if not info[0]:
		return
	world.set_block(pos, Blocks.family_ids("stone_button")[Blocks.family_ids("stone_button").find(id) - 1], false)
	Sounds.play("random/click", Vector3(pos) + Vector3(0.5, 0.5, 0.5), 0.3, 0.5)
	Redstone.notify_around(world, pos)
	Redstone.notify_around(world, pos + info[1])


## Levers and buttons fall off without the block that holds them.
static func on_attached_update(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	var family := Blocks.family_of(id)
	var attached: Vector3i = lever_info(id)[1] if family == "lever" else button_info(id)[1]
	if not Redstone.is_solid(world.get_block(pos + attached)):
		world.destroy_block(pos, true, true)


# --- Pressure plates ------------------------------------------------------------------------

## Something is on the plate at pos: push it (called by the player, mobs and
## dropped items standing in its cell).
static func step_on(world: VoxelWorld, pos: Vector3i, is_item: bool = false) -> void:
	var id := world.get_block(pos)
	var family := Blocks.family_of(id)
	if family != "stone_pressure_plate" and family != "wooden_pressure_plate":
		return
	if is_item and family == "stone_pressure_plate":
		return
	if not plate_pressed(id):
		world.set_block(pos, Blocks.family_ids(family)[1], false)
		Sounds.play("random/click", Vector3(pos) + Vector3(0.5, 0.1, 0.5), 0.3, 0.6)
		Redstone.notify_around(world, pos)
		Redstone.notify_around(world, pos + Vector3i.DOWN)
		world.schedule_tick(pos, PLATE_TICKS)


static func plate_tick(world: VoxelWorld, pos: Vector3i) -> void:
	var id := world.get_block(pos)
	var family := Blocks.family_of(id)
	if not plate_pressed(id):
		return
	if _something_on(world, pos, family == "wooden_pressure_plate"):
		world.schedule_tick(pos, PLATE_TICKS)
		return
	world.set_block(pos, Blocks.family_ids(family)[0], false)
	Sounds.play("random/click", Vector3(pos) + Vector3(0.5, 0.1, 0.5), 0.3, 0.5)
	Redstone.notify_around(world, pos)
	Redstone.notify_around(world, pos + Vector3i.DOWN)


static func _something_on(world: VoxelWorld, pos: Vector3i, items_count: bool) -> bool:
	var box := AABB(Vector3(pos) + Vector3(0.125, 0, 0.125), Vector3(0.75, 0.25, 0.75))
	var player := world.player as Player
	if player and not player.dead:
		var feet := player.global_position
		var body := AABB(feet - Vector3(Player.HALF_WIDTH, 0, Player.HALF_WIDTH), Vector3(Player.HALF_WIDTH * 2, Player.HEIGHT, Player.HALF_WIDTH * 2))
		if body.intersects(box):
			return true
	for entity in world.entities.all():
		if entity is Mob and not entity.is_dead() and entity.hit_box().intersects(box):
			return true
	if items_count and world.items.any_in(box):
		return true
	return false


## Plates need solid ground.
static func on_plate_update(world: VoxelWorld, pos: Vector3i) -> void:
	if not Redstone.is_solid(world.get_block(pos + Vector3i.DOWN)) \
			and Blocks.get_type(world.get_block(pos + Vector3i.DOWN)).name != "fence":
		world.destroy_block(pos, true, true)


# --- Placing and using ------------------------------------------------------------------------

## The block to place for a redstone part clicked onto face `normal` (the
## new cell is pos), or -1 if it can't go there.
static func placement(world: VoxelWorld, family: String, pos: Vector3i, normal: Vector3i, look: Vector3) -> int:
	var below_solid := Redstone.is_solid(world.get_block(pos + Vector3i.DOWN))
	var horizontal := Blocks.FACING_DIRECTIONS.find(_horizontal(look))
	match family:
		"redstone_wire":
			return Redstone.wire_id(0, 0) if below_solid or Blocks.get_type(world.get_block(pos + Vector3i.DOWN)).name == "glowstone" else -1
		"redstone_torch", "redstone_wall_torch":
			if normal == Vector3i.UP or normal == Vector3i.ZERO:
				return torch_id(true, Vector3i.DOWN) if TorchBehavior.can_hold(world, pos + Vector3i.DOWN) else -1
			if normal.y != 0 or not TorchBehavior.can_hold(world, pos - normal):
				return -1
			return torch_id(true, -normal)
		"lever":
			if normal == Vector3i.UP:
				return lever_id(false, 0 if absf(look.x) > absf(look.z) else 1) if below_solid else -1
			if normal.y != 0 or not Redstone.is_solid(world.get_block(pos - normal)):
				return -1
			return lever_id(false, 2 + Blocks.FACING_DIRECTIONS.find(normal))
		"stone_button":
			if normal.y != 0 or normal == Vector3i.ZERO or not Redstone.is_solid(world.get_block(pos - normal)):
				return -1
			return Blocks.family_ids("stone_button")[Blocks.FACING_DIRECTIONS.find(normal) * 2]
		"stone_pressure_plate", "wooden_pressure_plate":
			return Blocks.family_ids(family)[0] if below_solid else -1
		"repeater":
			return repeater_id(horizontal, 1, false) if below_solid else -1
	return -2 # not a redstone part


static func _horizontal(look: Vector3) -> Vector3i:
	if absf(look.x) > absf(look.z):
		return Vector3i(1, 0, 0) if look.x > 0.0 else Vector3i(-1, 0, 0)
	return Vector3i(0, 0, 1) if look.z > 0.0 else Vector3i(0, 0, -1)


## Right-click on a redstone part. Returns true if it did something.
static func use(world: VoxelWorld, pos: Vector3i, id: int) -> bool:
	match Blocks.family_of(id):
		"lever":
			toggle_lever(world, pos)
			return true
		"stone_button":
			press_button(world, pos)
			return true
		"repeater":
			cycle_delay(world, pos)
			return true
	return false
