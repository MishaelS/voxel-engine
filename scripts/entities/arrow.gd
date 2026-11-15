class_name Arrow
extends Entity
## Arrows like the classic game: shot from a bow (the player, skeletons),
## they fly along a falling curve (gravity 0.05, drag 0.99, slower in
## water), hurt the first creature they hit (4, pushing it back) and stick
## in blocks, where they stay for a minute and can be picked up.

const DAMAGE := 4
const STUCK_TICKS := 2400 # two minutes

var shooter: Node3D
## How hard the bow was drawn (0.1..1): the damage scales with it.
var power := 1.0
var stuck := false
## The block it is stuck in: when that is gone, the arrow falls again.
var _stuck_in := Vector3i.ZERO
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
	var mesh := MeshInstance3D.new()
	mesh.mesh = _arrow_mesh()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_model.add_child(mesh)


static var _mesh: ArrayMesh


## The arrow like the game's: two crossed pictures 16 x 5 pixels (feathers
## to tip along +Z) turned 45 degrees, and the 5 x 5 back seen from behind;
## textures/item/arrows.png (32 x 32, like Beta's), 0.05625 blocks a pixel.
static func _arrow_mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	const S := 0.05625
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quad := func(corners: Array, uvs: Array) -> void:
		for k: int in [0, 1, 2, 0, 2, 3]:
			tool.set_uv(uvs[k])
			tool.add_vertex(corners[k] * S)
	for plane in 2:
		var turn := Basis(Vector3.BACK, deg_to_rad(45.0 + plane * 90.0))
		quad.call([turn * Vector3(0, 2, -12), turn * Vector3(0, 2, 4), turn * Vector3(0, -2, 4), turn * Vector3(0, -2, -12)],
			[Vector2(0, 0), Vector2(0.5, 0), Vector2(0.5, 5.0 / 32.0), Vector2(0, 5.0 / 32.0)])
	quad.call([Vector3(-2, 2, -11), Vector3(2, 2, -11), Vector3(2, -2, -11), Vector3(-2, -2, -11)],
		[Vector2(0, 5.0 / 32.0), Vector2(5.0 / 32.0, 5.0 / 32.0), Vector2(5.0 / 32.0, 10.0 / 32.0), Vector2(0, 10.0 / 32.0)])
	_mesh = tool.commit()
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/entity_flat.gdshader")
	material.set_shader_parameter("picture", TexturePacks.load_texture("res://assets/textures/item/arrows.png"))
	_mesh.surface_set_material(0, material)
	return _mesh


func tick() -> void:
	_prev = Vector3(_x, _y, _z)
	age += 1
	if stuck and Blocks.collides_table[world.get_block(_stuck_in)] == 0:
		# The block it was in is gone: it falls, like the game's.
		stuck = false
		velocity = Vector3(randf_range(-0.02, 0.02), 0.0, randf_range(-0.02, 0.02))
		_stuck_ticks = 0
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
	if not hit.is_empty() and shooter is Entity and is_instance_valid(shooter) and hit[0] == (shooter as Entity).vehicle:
		# (a spider jockey's skeleton doesn't shoot its own spider)
		hit = world.entities.raycast(start, velocity, minf(length, block_distance), hit[0])
	var player := world.player as Player
	if player and (shooter != player or age >= 5) and not player.dead:
		var box := AABB(player.global_position - Vector3(Player.HALF_WIDTH, 0, Player.HALF_WIDTH),
			Vector3(Player.HALF_WIDTH * 2, Player.HEIGHT, Player.HALF_WIDTH * 2))
		var point: Variant = box.intersects_segment(start, end)
		if point != null and start.distance_to(point) < (hit[1] if not hit.is_empty() else block_distance):
			player.damage(Mob._scaled_damage(DAMAGE) if shooter is Mob else DAMAGE)
			Mob.guard_owner(shooter) # (the player's tame wolves go after the shooter)
			player.knockback(start)
			removed = true
			return
	# The network game's other players (the host's arrows reach them too).
	if Net.is_host():
		for avatar: RemotePlayer in Net.avatars.values():
			if not is_instance_valid(avatar) or avatar.dead or (avatar == shooter and age < 5):
				continue
			var avatar_box := AABB(avatar.target_position - Vector3(0.3, 0, 0.3), Vector3(0.6, 1.8, 0.6))
			var through: Variant = avatar_box.intersects_segment(start, end)
			if through != null and start.distance_to(through) < (hit[1] if not hit.is_empty() else block_distance):
				avatar.damage(Mob._scaled_damage(DAMAGE) if shooter is Mob else maxi(ceili(DAMAGE * power), 1))
				avatar.knockback(start)
				removed = true
				return
	if not hit.is_empty():
		var target: Entity = hit[0]
		target.damage(maxi(ceili(DAMAGE * power), 1), start)
		if target is Mob and shooter and is_instance_valid(shooter):
			(target as Mob).hurt_by(shooter)
		if target is Mob and shooter == player and target.is_dead():
			Stats.killed(target, player.global_position)
		removed = true
		return
	if block_hit.get("hit", false):
		var point := start + velocity.normalized() * block_distance
		_x = point.x
		_y = point.y
		_z = point.z
		stuck = true
		_stuck_in = block_hit.pos
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
	# (into a quiver first, if there is one with room)
	if Quiver.store(player.inventory, 1) > 0:
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
	if world and Engine.get_process_frames() % 6 == 0:
		# The light where its shaft is (behind the tip: a stuck tip is inside
		# the block, in the dark).
		var light := world.brightness_at(global_position - _model.global_basis.z.normalized() * 0.4)
		for child in _model.get_children():
			(child as GeometryInstance3D).set_instance_shader_parameter("brightness", light)
