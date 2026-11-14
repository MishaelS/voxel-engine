class_name Boat
extends Entity
## Boats like Beta 1.7.3 (EntityBoat):
## - floats: pushed up by the share of it under water (sampled in 5 slices),
##   settling at the surface; on land it slides to a stop;
## - solid like the game's: the player and creatures bump into it and can
##   stand on it, boats bump into each other (EntityPhysics.solid_entities);
## - right-click gets in; walking forward rows it the way the player looks:
##   slower than Beta's (about 4.5 blocks a second), picking up speed
##   smoothly and gliding on when the rowing stops, slowing down little by
##   little (water drag);
## - pushed aside by the player and creatures pressing against it (the
##   game's entity collision);
## - burns up in lava;
## - running into the shore at full speed smashes it into 3 planks and 2
##   sticks; hits break it whole (it drops itself).

## Speed added per tick while rowing and the share kept per tick on water:
## together a smooth rise to about 0.22 blocks a tick and a long glide.
const ROW_PUSH := 0.007
const WATER_DRAG := 0.97
const MAX_SPEED := 0.25
const CRASH_SPEED := 0.2

var _model := {}
var _wear := 0.0
var _yaw := 0.0
var _rider_forward := 0.0
var _rider_look := Vector3.ZERO


func type_name() -> String:
	return "boat"


func _ready() -> void:
	half_width = 0.75
	height = 0.6
	max_health = 1000
	health = max_health
	_model = MobModels.build("boat")
	add_child(_model.root)
	EntityPhysics.solid_entities.append(self)


func _exit_tree() -> void:
	EntityPhysics.solid_entities.erase(self)


func seat_height() -> float:
	return 0.25 # inside, on its bottom


func steer(forward: float, look: Vector3) -> void:
	_rider_forward = forward
	_rider_look = look


func tick() -> void:
	_prev = Vector3(_x, _y, _z)
	age += 1
	_wear = maxf(_wear - 1.0, 0.0)
	# How much of the boat is in water (5 slices).
	var under := 0.0
	for i in 5:
		if _slice_in_water(_y + height * i / 5.0 - 0.125, _y + height * (i + 1) / 5.0 - 0.125):
			under += 0.2
	if under < 1.0:
		velocity.y += 0.04 * (under * 2.0 - 1.0)
	else:
		if velocity.y < 0.0:
			velocity.y /= 2.0
		velocity.y += 0.007
	if EntityPhysics.touches_liquid(world, _x, _y, _z, half_width, height, "lava"):
		# Burns up: smoke, flames, embers and a hiss; nothing is left.
		world.particles.burn(center(), true)
		Sounds.play("random/fizz", center(), 0.6, randf_range(2.0, 2.6))
		_gone()
		return
	_pushed()
	take_creature(Vector2(velocity.x, velocity.z).length_squared() > 0.0004)
	var ridden := _ridden()
	if ridden and _rider_forward != 0.0 and under > 0.0:
		# Rowing: a little push a tick (backwards at half strength).
		var row := Vector2(_rider_look.x, _rider_look.z).normalized() * ROW_PUSH \
			* (_rider_forward if _rider_forward > 0.0 else _rider_forward * 0.5)
		velocity.x += row.x
		velocity.z += row.y
	var flat := Vector2(velocity.x, velocity.z)
	if flat.length() > MAX_SPEED:
		flat = flat.normalized() * MAX_SPEED
		velocity.x = flat.x
		velocity.z = flat.y
	var speed_before := flat.length()
	if on_ground and under <= 0.0:
		velocity.x *= 0.5
		velocity.z *= 0.5
	move(velocity)
	if horizontal_collision and speed_before > CRASH_SPEED and ridden:
		# Rowed into the shore (pushes by creatures don't smash it).
		_smash()
		return
	# Water drag: the speed falls off little by little (inertia); on land
	# it stops sooner.
	var drag := WATER_DRAG if under > 0.0 else 0.9
	velocity.x *= drag
	velocity.z *= drag
	velocity.y *= 0.95
	flat = Vector2(velocity.x, velocity.z)
	if flat.length_squared() > 1e-4:
		# Turns toward where it goes (rowing backwards it keeps its heading).
		var heading := atan2(flat.x, flat.y)
		if _rider_forward < 0.0 and ridden:
			heading = wrapf(heading + PI, -PI, PI)
		_yaw = lerp_angle(_yaw, heading, 0.25)
	if _y < Player.VOID_Y:
		removed = true


## Pushed aside by whoever presses against it, like the game's
## applyEntityCollision: within 0.2 of its sides, a push of up to 0.05 a
## tick away from them.
func _pushed() -> void:
	var others: Array[Array] = [] # [feet, half width, height]
	var player := world.player as Player
	if player and player.vehicle != self and not player.dead:
		others.append([player.global_position, Player.HALF_WIDTH, Player.HEIGHT])
	for entity in world.entities.all():
		if entity is Mob and entity != rider and entity.vehicle == null and not entity.removed \
				and entity.feet().distance_squared_to(feet()) < 9.0:
			others.append([entity.feet(), entity.half_width, entity.height])
	for other: Array in others:
		var at: Vector3 = other[0]
		var reach: float = half_width + float(other[1]) + 0.2
		if absf(at.x - _x) >= reach or absf(at.z - _z) >= reach or at.y >= _y + height or at.y + float(other[2]) <= _y:
			continue
		var dx := at.x - _x
		var dz := at.z - _z
		var d := maxf(absf(dx), absf(dz))
		if d < 0.01:
			continue
		d = sqrt(d)
		var f := minf(1.0 / d, 1.0)
		velocity.x -= dx / d * f * 0.05
		velocity.z -= dz / d * f * 0.05


## Whether water fills any block a horizontal slice of the boat (heights y0..y1)
## passes through.
func _slice_in_water(y0: float, y1: float) -> bool:
	for by in range(floori(y0), floori(y1 - 0.001) + 1):
		for bz in range(floori(_z - half_width + 0.001), floori(_z + half_width - 0.001) + 1):
			for bx in range(floori(_x - half_width + 0.001), floori(_x + half_width - 0.001) + 1):
				var id := world.get_block(Vector3i(bx, by, bz))
				if Blocks.liquid_table[id] == 1 and Blocks.family_of(id) == "water":
					return true
	return false


func _ridden() -> bool:
	var player := world.player as Player
	return (player != null and player.vehicle == self) or (remote_rider != 0 and Net.players.has(remote_rider))


func interact(player: Player, _item_id: int) -> bool:
	if player.vehicle == null and seat_free():
		player.mount(self)
		return true
	return false


func damage(amount: int, from: Variant = null) -> bool:
	if removed:
		return false
	_wear += amount * 10.0
	if from is Vector3:
		var away := Vector2(_x - (from as Vector3).x, _z - (from as Vector3).z).normalized() * 0.1
		velocity.x += away.x
		velocity.z += away.y
	var player := world.player as Player
	if _wear > 40.0 or (player and player.is_creative()):
		_gone()
		if player == null or not player.is_creative():
			world.items.spawn(Items.id_of("boat"), 1, center(), Vector3(0, 0.2, 0))
	return true


## Crashed: in pieces.
func _smash() -> void:
	_gone()
	world.items.scatter(center(), Blocks.id_of("oak_planks"), 3)
	world.items.scatter(center(), Items.id_of("stick"), 2)
	Sounds.play_block("break", Blocks.id_of("oak_planks"), center())


func _gone() -> void:
	removed = true
	if rider and is_instance_valid(rider):
		rider.vehicle = null
	var player := world.player as Player
	if player and player.vehicle == self:
		player.vehicle = null


func _process(delta: float) -> void:
	super(delta)
	if _model.is_empty():
		return
	rotation.y = lerp_angle(rotation.y, _yaw, minf(delta * 8.0, 1.0))
	var light := world.brightness_at(center()) if world else 1.0
	for mesh: MeshInstance3D in _model.meshes:
		mesh.set_instance_shader_parameter("brightness", light)


## Puts a boat where the player is looking: on water (the surface) or on a
## block. Returns the boat or null.
static func place(world: VoxelWorld, player: Player) -> Boat:
	var hit := world.raycast(player.eye_position(), player.look_direction(), player.reach(), true)
	if not hit.get("hit", false):
		return null
	var pos: Vector3i = hit.pos
	var at := Vector3(pos) + Vector3(0.5, 1.0, 0.5)
	if Blocks.liquid_table[hit.block] == 0 and hit.normal != Vector3i.UP:
		return null
	var boat := Boat.new()
	world.entities.spawn(boat, at)
	# Nose along the player's look (yaw 0 = toward +Z, as it moves), so it
	# doesn't turn around when rowed off.
	var look := player.look_direction()
	boat._yaw = atan2(look.x, look.z)
	boat.rotation.y = boat._yaw
	return boat
