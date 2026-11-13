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


## In water or out in the rain (puts out burning, like the game's isWet).
func is_wet() -> bool:
	return in_water or WeatherEffects.rains_at(world, Vector3i(floori(_x), floori(_y), floori(_z))) \
		or WeatherEffects.rains_at(world, Vector3i(floori(_x), floori(_y + height), floori(_z)))


## The box attacks and arrows hit (its body by default).
func hit_box() -> AABB:
	return AABB(feet() - Vector3(half_width, 0, half_width), Vector3(half_width * 2, height, half_width * 2))


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


## How high above its feet a rider sits (the floor of a boat or cart, a
## pig's back).
func seat_height() -> float:
	return height * 0.9


# --- Network (Net): the host's entities seen by clients ----------------------------------

## The host's number for this entity (0: not shared yet).
var net_id := 0
## A client's copy of a host entity: no thinking or physics of its own, it
## follows the host's snapshots (Net).
var puppet := false
## A client's player riding this vehicle (its peer id; host).
var remote_rider := 0
var _net_target := Vector3.ZERO
var _net_yaw := 0.0


## What changes often and shows: sent 10 times a second (with the position
## and the facing). Subclasses add their own (a creeper's fuse...).
func net_state() -> Dictionary:
	return {"hurt": hurt_ticks, "death": death_ticks, "fire": fire_ticks}


## A client applies the host's snapshot.
func apply_net_state(at: Vector3, yaw: float, state: Dictionary) -> void:
	_net_target = at
	_net_yaw = yaw
	hurt_ticks = int(state.get("hurt", 0))
	death_ticks = int(state.get("death", -1))
	fire_ticks = int(state.get("fire", 0))


## The facing the host sends (vehicles keep their own heading).
func net_yaw() -> float:
	return float(get("_yaw")) if "_yaw" in self else rotation.y


## A client's tick of a host entity: one step toward the latest snapshot.
func puppet_tick() -> void:
	_prev = Vector3(_x, _y, _z)
	age += 1
	velocity = _net_target - _prev
	_x = _net_target.x
	_y = _net_target.y
	_z = _net_target.z
	if "_yaw" in self:
		set("_yaw", _net_yaw)
	else:
		rotation.y = lerp_angle(rotation.y, _net_yaw, 0.6)


# --- Riding (boats and minecarts carry one rider) ------------------------------------

## The boat or minecart this creature sits in.
var vehicle: Entity
## The creature in this boat or minecart (the player rides through
## Player.vehicle).
var rider: Entity
## Creatures that get into a free boat or minecart they bump into, like the
## game's (one each).
const RIDING_MOBS: Array[String] = ["zombie", "skeleton"]
## A sitting rider's hips above its feet (Player.HIP_HEIGHT).
const RIDER_HIPS := 0.625


## Nobody (no creature, not the player) sits in this vehicle.
func seat_free() -> bool:
	if remote_rider != 0 and Net.players.has(remote_rider):
		return false
	remote_rider = 0
	if rider and is_instance_valid(rider) and not rider.removed and not rider.is_dead() and rider.vehicle == self:
		return false
	rider = null
	var player := world.player as Player if world else null
	return player == null or player.vehicle != self


## A vehicle's tick: a zombie or skeleton touching it (within 0.2 of its
## sides) gets in when either of them is moving, like the game's minecart.
func take_creature(moving: bool) -> void:
	if not seat_free():
		return
	for entity in world.entities.all():
		if not (entity is Mob) or not ((entity as Mob).mob_type in RIDING_MOBS) or entity.vehicle != null \
				or entity.removed or entity.is_dead():
			continue
		var at := entity.feet()
		var reach := half_width + entity.half_width + 0.2
		if absf(at.x - _x) >= reach or absf(at.z - _z) >= reach or at.y >= _y + height or at.y + entity.height <= _y:
			continue
		var walking := Vector2(entity.velocity.x, entity.velocity.z).length_squared() > 0.0004
		if moving or walking:
			entity.vehicle = self
			rider = entity
			return


## Where a creature riding `vehicle` has its feet (sitting on the seat).
func _seat_feet(at: Vector3) -> Vector3:
	return at + Vector3(0, vehicle.seat_height() - RIDER_HIPS, 0)


## Where the entity is drawn this frame (between the last two ticks).
func render_feet() -> Vector3:
	return _prev.lerp(Vector3(_x, _y, _z), TickLoop.alpha)


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
			_death_puff()
		return
	in_water = EntityPhysics.touches_liquid(world, _x, _y, _z, half_width, height, "water")
	in_lava = EntityPhysics.touches_liquid(world, _x, _y, _z, half_width, height, "lava")
	_burn()
	if world and on_ground:
		RedstoneComponents.step_on(world, Vector3i(floori(_x), floori(_y + 0.01), floori(_z)))
	_ai_tick()
	if vehicle and (not is_instance_valid(vehicle) or vehicle.removed):
		vehicle = null # its boat or cart is gone
	if vehicle:
		# Sitting: carried along (it still looks about and attacks).
		var seat := _seat_feet(vehicle.feet())
		_x = seat.x
		_y = seat.y
		_z = seat.z
		velocity = Vector3.ZERO
		on_ground = true
		return
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
	var result := EntityPhysics.sweep(world, _x, _y, _z, half_width, height, motion.x, motion.y, motion.z, self)
	var blocked := result[0] != motion.x or result[2] != motion.z
	if blocked and step_height > 0.0 and (on_ground or motion.y < 0.0):
		var up := EntityPhysics.sweep(world, _x, _y, _z, half_width, height, 0.0, step_height, 0.0, self)
		var side := EntityPhysics.sweep(world, _x, _y + up[1], _z, half_width, height, motion.x, 0.0, motion.z, self)
		var down := EntityPhysics.sweep(world, _x + side[0], _y + up[1], _z + side[2], half_width, height,
			0.0, -up[1] + minf(motion.y, 0.0), 0.0, self)
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
	if is_wet():
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


## When the body is gone (after falling over): a puff of smoke for
## creatures, like the game's (subclasses).
func _death_puff() -> void:
	pass


## Drops and effects when it dies (subclasses).
func _on_death() -> void:
	pass


# --- Drawing --------------------------------------------------------------------------

var _flames: MeshInstance3D


func _process(_delta: float) -> void:
	global_position = _prev.lerp(Vector3(_x, _y, _z), TickLoop.alpha)
	if vehicle and is_instance_valid(vehicle) and not vehicle.removed:
		global_position = _seat_feet(vehicle.render_feet()) # where its seat is drawn
	_show_flames()
	_show_shadow()


## Beta's round shadow (Render.renderShadow), this wide around the feet (0:
## none): misc/shadow.png laid on the tops of the solid blocks under it,
## fainter the higher it floats over them, the darker the spot and the
## farther the camera (gone at 16 blocks); with Fancy graphics only.
var shadow_size := 0.0
var _shadow: MeshInstance3D
static var _shadow_material: ShaderMaterial


func _show_shadow() -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var opacity := 0.0
	if shadow_size > 0.0 and world and camera and not is_dead() and not Blocks.is_fast_graphics() and visible:
		opacity = 1.0 - camera.global_position.distance_squared_to(global_position) / 256.0
	if opacity <= 0.0:
		if _shadow:
			_shadow.visible = false
		return
	if _shadow == null:
		if _shadow_material == null:
			_shadow_material = ShaderMaterial.new()
			_shadow_material.shader = load("res://shaders/entity_shadow.gdshader")
			_shadow_material.set_shader_parameter("shadow_texture",
				TexturePacks.load_texture("res://assets/textures/misc/shadow.png"))
		_shadow = MeshInstance3D.new()
		_shadow.top_level = true # (laid on the world, not turned with the creature)
		_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_shadow.mesh = ImmediateMesh.new()
		add_child(_shadow)
	_shadow.visible = true
	_shadow.global_transform = Transform3D.IDENTITY
	var mesh := _shadow.mesh as ImmediateMesh
	mesh.clear_surfaces()
	var at := global_position
	var size := shadow_size
	var quads := 0
	for bx in range(floori(at.x - size), floori(at.x + size) + 1):
		for by in range(floori(at.y - size), floori(at.y) + 1):
			for bz in range(floori(at.z - size), floori(at.z + size) + 1):
				var below := world.get_block(Vector3i(bx, by - 1, bz))
				if Blocks.is_opaque_table[below] == 0:
					continue # (Beta: on full blocks only)
				var light := world.brightness_at(Vector3(bx + 0.5, by + 0.5, bz + 0.5))
				var alpha := clampf((opacity - (at.y - by) / 2.0) * 0.5 * light, 0.0, 1.0)
				if alpha <= 0.0:
					continue
				if quads == 0:
					mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _shadow_material)
				quads += 1
				var y := by + 0.015625
				var corners := [Vector2(bx, bz), Vector2(bx + 1, bz), Vector2(bx + 1, bz + 1), Vector2(bx, bz + 1)]
				for i: int in [0, 1, 2, 0, 2, 3]:
					var corner: Vector2 = corners[i]
					mesh.surface_set_color(Color(1, 1, 1, alpha))
					mesh.surface_set_uv(Vector2((corner.x - at.x) / 2.0 / size + 0.5, (corner.y - at.z) / 2.0 / size + 0.5))
					mesh.surface_add_vertex(Vector3(corner.x, y, corner.y))
	if quads > 0:
		mesh.surface_end()


## Burning creatures are wrapped in flames like the game's: the animated
## fire block's crossed pictures, as big as the creature.
func _show_flames() -> void:
	var burning := fire_ticks > 0 and not is_dead()
	if not burning:
		if _flames:
			_flames.visible = false
		return
	if _flames == null:
		_flames = MeshInstance3D.new()
		_flames.mesh = FallingBlocks.block_mesh(Blocks.variant("fire"))
		_flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_flames)
	var width := half_width * 2.0 * 1.4
	_flames.visible = true
	_flames.scale = Vector3(width, height * 1.15, width)
	_flames.position = Vector3(-width * 0.5, 0.0, -width * 0.5)


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
