class_name Arrow
extends Entity
## Arrows like the classic game: shot from a bow (the player, skeletons),
## they fly along a falling curve (gravity 0.05, drag 0.99, slower in
## water), hurt the first creature they hit (4, pushing it back) and stick
## in blocks, where they stay for a minute and can be picked up.

const DAMAGE := 4
const STUCK_TICKS := 1200

var shooter: Node3D
var stuck := false
var _stuck_ticks := 0
var _model: Node3D


## Shoots an arrow from `from` toward `at` (speed in blocks per tick, spread
## in degrees-ish, like the game's).
static func shoot(world: VoxelWorld, from: Vector3, at: Vector3, speed: float, spread: float, by: Node3D) -> Arrow:
	var arrow := Arrow.new()
	arrow.shooter = by
	var dir := (at - from).normalized()
	dir.y += Vector3(at - from).length() * 0.02 # aims a little high, like skeletons
	dir = dir.normalized() + Vector3(randfn(0, 1), randfn(0, 1), randfn(0, 1)) * 0.0075 * spread
	world.entities.spawn(arrow, from)
	arrow.velocity = dir.normalized() * speed
	Sounds.play("random/bow", from, 1.0, 1.0 / (randf() * 0.4 + 0.8))
	return arrow


func type_name() -> String:
	return "arrow"


func can_be_hit() -> bool:
	return false


func _ready() -> void:
	half_width = 0.25
	height = 0.5
	_model = Node3D.new()
	add_child(_model)
	var wood := StandardMaterial3D.new()
	wood.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wood.albedo_color = Color(0.45, 0.32, 0.18)
	var stone := wood.duplicate() as StandardMaterial3D
	stone.albedo_color = Color(0.5, 0.5, 0.5)
	var feather := wood.duplicate() as StandardMaterial3D
	feather.albedo_color = Color(0.92, 0.92, 0.92)
	for piece: Array in [[Vector3(0.04, 0.04, 0.5), Vector3.ZERO, wood], [Vector3(0.07, 0.07, 0.08), Vector3(0, 0, 0.27), stone],
			[Vector3(0.12, 0.01, 0.12), Vector3(0, 0, -0.2), feather], [Vector3(0.01, 0.12, 0.12), Vector3(0, 0, -0.2), feather]]:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = piece[0]
		box.material = piece[2]
		mesh.mesh = box
		mesh.position = piece[1]
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_model.add_child(mesh)


func tick() -> void:
	_prev = Vector3(_x, _y, _z)
	age += 1
	if stuck:
		_stuck_ticks += 1
		if _stuck_ticks > STUCK_TICKS:
			removed = true
		_try_pickup()
		return
	var start := Vector3(_x, _y, _z)
	var length := velocity.length()
	var end := start + velocity
	var block_hit := world.raycast(start, velocity, length)
	var block_distance := length + 1.0
	if block_hit.get("hit", false) and Blocks.collides_table[block_hit.block] == 1:
		block_distance = block_hit.distance
	else:
		block_hit = {}
	# Creatures on the way (not the shooter right after the shot).
	var ignore := shooter as Entity if age < 5 else null
	var hit := world.entities.raycast(start, velocity, minf(length, block_distance), ignore)
	var player := world.player as Player
	if player and (shooter != player or age >= 5) and not player.dead:
		var box := AABB(player.global_position - Vector3(Player.HALF_WIDTH, 0, Player.HALF_WIDTH),
			Vector3(Player.HALF_WIDTH * 2, Player.HEIGHT, Player.HALF_WIDTH * 2))
		var point: Variant = box.intersects_segment(start, end)
		if point != null and start.distance_to(point) < (hit[1] if not hit.is_empty() else block_distance):
			player.damage(Mob._scaled_damage(DAMAGE) if shooter is Mob else DAMAGE)
			player.knockback(start)
			removed = true
			return
	if not hit.is_empty():
		var target: Entity = hit[0]
		target.damage(DAMAGE, start)
		if target is Mob and shooter == player:
			(target as Mob).angry = true
		removed = true
		return
	if block_hit.get("hit", false):
		var point := start + velocity.normalized() * block_distance
		_x = point.x
		_y = point.y
		_z = point.z
		stuck = true
		Sounds.play("random/bowhit", point, 1.0, 1.2 / (randf() * 0.2 + 0.9))
		return
	_x = end.x
	_y = end.y
	_z = end.z
	var drag := 0.8 if EntityPhysics.touches_liquid(world, _x, _y, _z, 0.1, 0.1, "water") else 0.99
	velocity *= drag
	velocity.y -= 0.05
	if _y < Player.VOID_Y:
		removed = true


## Stuck arrows go back into the player's inventory when walked over.
func _try_pickup() -> void:
	var player := world.player as Player
	if player == null or player.dead or player.global_position.distance_to(Vector3(_x, _y, _z)) > 1.5:
		return
	if player.inventory.room_for(Items.id_of("arrow")) <= 0:
		return
	player.inventory.add(Items.id_of("arrow"), 1)
	Sounds.play("random/pop", null, 0.2, ((randf() - randf()) * 0.7 + 1.0) * 2.0)
	removed = true


func _process(delta: float) -> void:
	super(delta)
	if velocity.length_squared() > 1e-6 and not stuck:
		_model.look_at(global_position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT)
		_model.rotate_object_local(Vector3.UP, PI)
