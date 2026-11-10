class_name Boat
extends Entity
## Boats like Beta 1.7.3 (EntityBoat):
## - floats: pushed up by the share of it under water (sampled in 5 slices),
##   settling at the surface; on land it slides to a stop;
## - right-click gets in; walking forward rows it the way the player looks
##   (at most 0.4 blocks a tick);
## - running into the shore fast (over 0.15 a tick) smashes it into 3
##   planks and 2 sticks; hits break it whole (it drops itself).

const MAX_SPEED := 0.4
const CRASH_SPEED := 0.15

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
	var rider := _ridden()
	if rider and _rider_forward != 0.0:
		var row := Vector2(_rider_look.x, _rider_look.z).normalized() * 0.02 * _rider_forward
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
	if horizontal_collision and speed_before > CRASH_SPEED:
		_smash()
		return
	velocity.x *= 0.99
	velocity.z *= 0.99
	velocity.y *= 0.95
	if flat.length_squared() > 1e-5:
		_yaw = atan2(flat.x, flat.y)
	if _y < Player.VOID_Y:
		removed = true


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
	return player != null and player.vehicle == self


func interact(player: Player, _item_id: int) -> bool:
	if player.vehicle == null:
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
	var player := world.player as Player
	if player and player.vehicle == self:
		player.vehicle = null


func _process(delta: float) -> void:
	super(delta)
	if _model.is_empty():
		return
	rotation.y = lerp_angle(rotation.y, _yaw, minf(delta * 6.0, 1.0))
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
	boat.rotation.y = player.rotation.y
	boat._yaw = player.rotation.y
	return boat
