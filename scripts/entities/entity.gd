class_name Entity
extends Node3D
## The base of everything that moves in the world on its own (mobs, later
## arrows, minecarts, boats, primed TNT), like the classic game's Entity:
## - a box (half width, height; the node's position is the middle of its
##   bottom) moved by `velocity` (blocks per tick) every game tick, colliding
##   with blocks (EntityPhysics), stepping up STEP_HEIGHT if `step_height`;
## - gravity and air drag, ground friction (ice is slippery), swimming in
##   water and lava (slower, lava burns), fall damage;
## - health, hurt time and invulnerability after a hit, knockback, death
##   (a short animation, then removal and `_on_death()` for drops);
## - interpolated between ticks for drawing (TickLoop.alpha);
## - saved with the world: `type_name()` and save_state() / load_state()
##   (EntityManager keeps the list and ticks them).
## Subclasses override _ai_tick() (what it wants to do this tick),
## _on_death() and add their model as children.

const TICK := 1.0 / 20.0
const DEATH_TICKS := 20
const INVULNERABLE_TICKS := 10
const SAFE_FALL := 3.0
const FIRE_TICKS := 300

## Set by EntityManager.
var world: VoxelWorld
var half_width := 0.3
var height := 1.8
var step_height := 0.0
var gravity := 0.08
var drag := 0.98
## Velocity in blocks per tick.
var velocity := Vector3.ZERO
var on_ground := false
var horizontal_collision := false
var in_water := false
var in_lava := false
var max_health := 10
var health := 10
var hurt_ticks := 0
var death_ticks := -1 # -1 = alive
var fire_ticks := 0
var age := 0
## Remove at the next tick (despawned, picked up...).
var removed := false

# 64-bit position (Vector3 is 32-bit), previous tick for interpolation.
var _x := 0.0
var _y := 0.0
var _z := 0.0
var _prev := Vector3.ZERO
var _invulnerable := 0
var _last_damage := 0
var _fall_distance := 0.0


## Registry name, for saves (see EntityManager.TYPES).
func type_name() -> String:
	return "entity"


## Whether attacks and arrows can hit it (arrows themselves can't).
func can_be_hit() -> bool:
	return true


func is_dead() -> bool:
	return death_ticks >= 0


## Puts the entity at `position` (feet), without interpolation.
func teleport(position: Vector3) -> void:
	_x = position.x
	_y = position.y
	_z = position.z
	_prev = position
	global_position = position


func feet() -> Vector3:
	return Vector3(_x, _y, _z)


## Center of the box (for distances, looking at it).
func center() -> Vector3:
	return Vector3(_x, _y + height * 0.5, _z)


# --- Tick ----------------------------------------------------------------------------

## One game tick (EntityManager calls it).
func tick() -> void:
	_prev = Vector3(_x, _y, _z)
	age += 1
	hurt_ticks = maxi(hurt_ticks - 1, 0)
	_invulnerable = maxi(_invulnerable - 1, 0)
	if is_dead():
		death_ticks += 1
		if death_ticks >= DEATH_TICKS:
			removed = true
		return
	in_water = EntityPhysics.touches_liquid(world, _x, _y, _z, half_width, height, "water")
	in_lava = EntityPhysics.touches_liquid(world, _x, _y, _z, half_width, height, "lava")
	_burn()
	_ai_tick()
	_physics()
	if _y < Player.VOID_Y:
		damage(4)


## What the entity wants to do this tick (subclasses: walk, jump...).
func _ai_tick() -> void:
	pass


func _physics() -> void:
	if in_water or in_lava:
		move(velocity)
		velocity *= 0.5 if in_lava else 0.8
		velocity.y -= 0.02
		return
	var friction := 0.91
	if on_ground:
		var below := world.get_block(Vector3i(floori(_x), floori(_y - 0.5), floori(_z)))
		friction = (Blocks.get_type(below).slipperiness if below != Blocks.AIR else 0.6) * 0.91
	var start_y := _y
	move(velocity)
	velocity.y = (velocity.y - gravity) * drag
	velocity.x *= friction
	velocity.z *= friction
	_track_fall(start_y)


## Moves by `motion` (blocks), sliding along blocks and stepping up to
## `step_height` without jumping.
func move(motion: Vector3) -> void:
	var result := EntityPhysics.sweep(world, _x, _y, _z, half_width, height, motion.x, motion.y, motion.z)
	var blocked := result[0] != motion.x or result[2] != motion.z
	if blocked and step_height > 0.0 and (on_ground or motion.y < 0.0):
		var up := EntityPhysics.sweep(world, _x, _y, _z, half_width, height, 0.0, step_height, 0.0)
		var side := EntityPhysics.sweep(world, _x, _y + up[1], _z, half_width, height, motion.x, 0.0, motion.z)
		var down := EntityPhysics.sweep(world, _x + side[0], _y + up[1], _z + side[2], half_width, height,
			0.0, -up[1] + minf(motion.y, 0.0), 0.0)
		if side[0] * side[0] + side[2] * side[2] > result[0] * result[0] + result[2] * result[2]:
			result = PackedFloat64Array([side[0], up[1] + down[1], side[2]])
	_x += result[0]
	_y += result[1]
	_z += result[2]
	horizontal_collision = result[0] != motion.x or result[2] != motion.z
	on_ground = motion.y < 0.0 and result[1] != motion.y
	if result[0] != motion.x:
		velocity.x = 0.0
	if result[2] != motion.z:
		velocity.z = 0.0
	if result[1] != motion.y:
		velocity.y = 0.0


func _track_fall(start_y: float) -> void:
	if in_water or in_lava:
		_fall_distance = 0.0
		return
	if start_y > _y:
		_fall_distance += start_y - _y
	if on_ground:
		if _fall_distance > SAFE_FALL:
			damage(ceili(_fall_distance - SAFE_FALL))
		_fall_distance = 0.0


## Lava: 4 damage and 15 s of fire; fire 1 damage per second; water puts it out.
func _burn() -> void:
	if in_lava:
		damage(4)
		fire_ticks = FIRE_TICKS
	if EntityPhysics.touches_cactus(world, _x, _y, _z, half_width, height):
		damage(1)
	if not in_lava and EntityPhysics.touches_fire(world, _x, _y, _z, half_width, height):
		damage(1)
		fire_ticks = maxi(fire_ticks, 160)
	if in_water:
		fire_ticks = 0
	if fire_ticks > 0:
		fire_ticks -= 1
		if fire_ticks % 20 == 0:
			damage(1)


# --- Health ---------------------------------------------------------------------------

## Takes damage like the classic game: after a hit, for 10 ticks only a
## stronger hit counts (the difference). `from` pushes the entity away
## (knockback) when given. Returns true if it was hurt.
func damage(amount: int, from: Variant = null) -> bool:
	if is_dead() or amount <= 0:
		return false
	if _invulnerable > 0:
		if amount <= _last_damage:
			return false
		health -= amount - _last_damage
	else:
		health -= amount
		hurt_ticks = INVULNERABLE_TICKS
		_invulnerable = INVULNERABLE_TICKS
	_last_damage = amount
	if from is Vector3:
		knockback(center() - (from as Vector3))
	if health <= 0:
		health = 0
		die()
	return true


## The classic knockback: away from the hit, 0.4 blocks per tick and a hop.
func knockback(direction: Vector3) -> void:
	var flat := Vector2(direction.x, direction.z)
	if flat.length_squared() < 1e-6:
		flat = Vector2(randf() - 0.5, randf() - 0.5)
	flat = flat.normalized() * 0.4
	velocity.x = velocity.x * 0.5 + flat.x
	velocity.z = velocity.z * 0.5 + flat.y
	velocity.y = minf(velocity.y * 0.5 + 0.4, 0.4)


func die() -> void:
	if is_dead():
		return
	death_ticks = 0
	_on_death()


## Drops and effects when it dies (subclasses).
func _on_death() -> void:
	pass


# --- Drawing --------------------------------------------------------------------------

func _process(_delta: float) -> void:
	global_position = _prev.lerp(Vector3(_x, _y, _z), TickLoop.alpha)


# --- Saving ---------------------------------------------------------------------------

func save_state() -> Dictionary:
	return {"type": type_name(), "position": Vector3(_x, _y, _z), "velocity": velocity,
		"health": health, "fire": fire_ticks, "age": age, "yaw": rotation.y}


func load_state(saved: Dictionary) -> void:
	teleport(saved.get("position", Vector3.ZERO))
	velocity = saved.get("velocity", Vector3.ZERO)
	health = saved.get("health", max_health)
	fire_ticks = saved.get("fire", 0)
	age = saved.get("age", 0)
	rotation.y = saved.get("yaw", 0.0)
