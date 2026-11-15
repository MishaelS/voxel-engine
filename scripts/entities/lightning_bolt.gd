class_name LightningBolt
extends Entity
## A lightning bolt like the classic game (EntityLightningBolt): a jagged
## white bolt from the sky to the ground that flickers for a few ticks,
## lights up the sky, thunders (heard everywhere) and cracks nearby; on
## Normal and Hard it sets the struck block and a few around it on fire;
## creatures and the player within 3 blocks take 5 damage and catch fire.

const LIFE := 2
const REACH := 3.0

var _life := LIFE
var _flashes := 0
var _mesh := ImmediateMesh.new()
var _seed := 0


static func strike(world: VoxelWorld, pos: Vector3i) -> LightningBolt:
	var bolt := LightningBolt.new()
	world.entities.spawn(bolt, Vector3(pos) + Vector3(0.5, 0, 0.5))
	bolt._flashes = randi_range(1, 3)
	bolt._ignite(4)
	bolt._hurt()
	var player := world.player as Player
	Sounds.play("ambient/thunder", player.eye_position() if player else Vector3(pos), 1.0, randf_range(0.8, 1.0))
	Sounds.play("random/explode", Vector3(pos), 2.0, randf_range(0.5, 0.7))
	return bolt


func type_name() -> String:
	return "lightning_bolt"


func can_be_hit() -> bool:
	return false


func _ready() -> void:
	gravity = 0.0
	_seed = randi()
	var instance := MeshInstance3D.new()
	instance.mesh = _mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.extra_cull_margin = 256.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(0.45, 0.45, 0.7, 0.3)
	instance.material_override = material
	add_child(instance)
	_build()


## The bolt: a zigzag line of short segments up to the sky, with a few forks.
func _build() -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	for layer in 4: # wider and fainter layers make the glow
		var width := 0.1 + layer * 0.08
		var top := float(WorldGenerator.HEIGHT)
		var point := Vector3(0, top - _y, 0)
		var step_height := (top - _y) / 8.0
		var line: Array[Vector3] = [point]
		rng.seed = _seed
		for i in 8:
			point = Vector3(point.x + rng.randf_range(-1.5, 1.5), point.y - step_height, point.z + rng.randf_range(-1.5, 1.5))
			if i == 7:
				point = Vector3(0, 0, 0)
			line.append(point)
		for k in line.size() - 1:
			_segment(line[k], line[k + 1], width)
	_mesh.surface_end()


func _segment(a: Vector3, b: Vector3, width: float) -> void:
	for side: Vector3 in [Vector3(width, 0, 0), Vector3(0, 0, width)]:
		var quad := [a - side, a + side, b + side, b - side]
		for k: int in [0, 1, 2, 0, 2, 3]:
			_mesh.surface_add_vertex(quad[k])


func tick() -> void:
	_prev = Vector3(_x, _y, _z)
	age += 1
	_life -= 1
	if _life < 0:
		if _flashes == 0:
			removed = true
			return
		if _life < -randi_range(0, 9):
			# Flickers back: a new zigzag, more fire, more harm.
			_flashes -= 1
			_life = 1
			_seed = randi()
			_build()
			_ignite(0)
			_hurt()
	visible = _life >= 0
	var atmosphere := Atmosphere.find(world.get_tree())
	if atmosphere and _life >= 0:
		atmosphere.lightning_flash = 1.0


## Sets fire where it struck (and `around` more spots nearby), on Normal
## and Hard only, like the game.
func _ignite(around: int) -> void:
	if Settings.get_value("difficulty") < 2:
		return
	var at := Vector3i(feet().floor())
	var spots: Array[Vector3i] = [at]
	for i in around:
		spots.append(at + Vector3i(randi_range(-1, 1), randi_range(-1, 1), randi_range(-1, 1)))
	for spot in spots:
		if world.get_block(spot) == Blocks.AIR and FireBehavior.can_burn_at(world, spot):
			FireBehavior.ignite(world, spot)


func _hurt() -> void:
	var middle := feet() + Vector3(0, 1, 0)
	for entity in world.entities.near(middle, REACH):
		if entity != self and entity.can_be_hit():
			entity.damage(5)
			entity.fire_ticks = maxi(entity.fire_ticks, 160)
			if entity is Mob:
				(entity as Mob).struck_by_lightning() # (a creeper is charged)
	var player := world.player as Player
	if player and not player.dead and player.global_position.distance_to(middle) <= REACH + 1.0:
		player.damage(5)
		player.fire_ticks = maxi(player.fire_ticks, 160)
	if Net.is_host():
		for avatar: RemotePlayer in Net.avatars.values():
			if is_instance_valid(avatar) and not avatar.dead and avatar.target_position.distance_to(middle) <= REACH + 1.0:
				avatar.damage(5)
