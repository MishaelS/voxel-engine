class_name FishingBobber
extends Entity
## The fishing rod's bobber, like the classic game (EntityFish):
## - cast from the rod it flies along a falling curve, floats on water and
##   catches on a creature it touches;
## - in water a fish bites now and then (1 in 500 ticks): the bobber dips
##   with a splash, and for 10..40 ticks reeling in catches a raw fish,
##   which flies to the player;
## - reeling in a caught creature (or a boat or a minecart) pulls it toward
##   the player: a yank toward them and up, Beta's (pull()); in a network
##   game the host does the pulling (Net.send_pull);
## - it is gone when reeled in, when the player stops holding the rod or
##   goes more than 32 blocks away.
## A thin line goes from the rod to the bobber; the bobber is the game's
## picture (in particles.png at 8, 16, like Beta's).

const BITE_CHANCE := 500
const MAX_DISTANCE := 32.0

var owner_player: Player
var hooked: Entity
## Ticks left while a fish is on the hook (reeling in now catches it).
var catchable := 0

var _line: MeshInstance3D
var _sprite: Sprite3D
var _line_mesh: ImmediateMesh


## Casts a bobber from the player's eyes along their view.
static func cast(player: Player) -> FishingBobber:
	var bobber := FishingBobber.new()
	bobber.owner_player = player
	var look := player.look_direction()
	player.world.entities.spawn(bobber, player.eye_position() + look * 0.3 - Vector3(0, 0.1, 0))
	var direction := (look + Vector3(randfn(0, 1), randfn(0, 1), randfn(0, 1)) * 0.0075).normalized()
	bobber.velocity = direction * 1.0
	Sounds.play("random/bow", player.global_position, 0.5, 0.4 / (randf() * 0.4 + 0.8))
	return bobber


func type_name() -> String:
	return "fishing_bobber"


func can_be_hit() -> bool:
	return false


func _ready() -> void:
	half_width = 0.125
	height = 0.25
	# The game's bobber: its 8 x 8 picture always facing the camera.
	_sprite = Sprite3D.new()
	# The hook in particles.png, at its Beta place.
	_sprite.texture = ImageTexture.create_from_image(TexturePacks.region("particles.png", Rect2i(8, 16, 8, 8)))
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.shaded = false
	_sprite.pixel_size = 0.5 / 8.0
	_sprite.position.y = 0.2
	_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sprite)
	_line_mesh = ImmediateMesh.new()
	_line = MeshInstance3D.new()
	_line.mesh = _line_mesh
	_line.top_level = true
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color(0.05, 0.05, 0.05)
	_line.material_override = black
	add_child(_line)


func tick() -> void:
	_prev = Vector3(_x, _y, _z)
	age += 1
	var player := owner_player
	if player == null or player.dead or Items.name_of(player.held_block()) != "fishing_rod" \
			or player.global_position.distance_to(feet()) > MAX_DISTANCE:
		_gone()
		return
	if hooked:
		if hooked.is_dead() or hooked.removed:
			hooked = null
		else:
			var at := hooked.feet() + Vector3(0, hooked.height * 0.8, 0)
			_x = at.x
			_y = at.y
			_z = at.z
			return
	in_water = EntityPhysics.touches_liquid(world, _x, _y, _z, half_width, height, "water")
	if not in_water and not on_ground:
		# Catches on a creature it flies into.
		var found := world.entities.raycast(feet(), velocity, velocity.length() + 0.1, self)
		if not found.is_empty() and can_hook(found[0]):
			hooked = found[0]
			return
	if in_water:
		# Floats: pushed up while under the surface, settles on it.
		var surface := _water_surface()
		velocity.y += clampf((surface - _y - 0.12) * 0.08, -0.04, 0.04)
		velocity *= Vector3(0.9, 0.8, 0.9)
		if catchable > 0:
			catchable -= 1
		elif randi_range(1, BITE_CHANCE) == 1:
			catchable = randi_range(10, 40)
			velocity.y -= 0.2
			Sounds.play("random/splash", feet(), 0.25, 1.0 + (randf() - randf()) * 0.4)
			world.particles.splash(feet() + Vector3(0, 0.1, 0))
	else:
		velocity.y -= 0.04
		velocity *= 0.92 if not on_ground else 0.5
	move(velocity)


## The top of the water the bobber is in.
func _water_surface() -> float:
	var cell := Vector3i(floori(_x), floori(_y), floori(_z))
	while Blocks.liquid_table[world.get_block(cell + Vector3i.UP)] == 1:
		cell += Vector3i.UP
	return cell.y + 1.0 - 0.12


## Reels the line in: a fish if one is biting, a caught creature is pulled
## closer. Returns how much the rod wears (like the game: 1, 2 on the
## ground, 3 for a creature).
func reel_in() -> int:
	var wear := 0
	var player := owner_player
	if hooked:
		if world.remote:
			Net.send_pull(hooked.net_id) # (the host's creature: the host pulls it)
		else:
			pull(hooked, player.global_position)
		wear = 3
	elif catchable > 0:
		var to := player.eye_position() - feet()
		world.items.spawn(Items.id_of("raw_fish"), 1, feet() + Vector3(0, 0.2, 0),
			Vector3(to.x * 0.1, to.y * 0.1 + sqrt(to.length()) * 0.08, to.z * 0.1))
		wear = 1
		Stats.add("fish_caught")
		if Stats.value("fish_caught") >= 10:
			Stats.grant("fisherman")
	elif on_ground:
		wear = 2
	_gone()
	return wear


## What a bobber catches on: creatures, boats and minecarts.
static func can_hook(entity: Entity) -> bool:
	return (entity is Mob or entity is Boat or entity is Minecart) and not entity.removed and not entity.is_dead()


## The yank of reeling in, like Beta's EntityFish.catchFish: a tenth of the
## way to the player a tick, and up by the distance's root.
static func pull(entity: Entity, toward: Vector3) -> void:
	var way := toward - entity.feet()
	entity.velocity += way * 0.1 + Vector3(0, sqrt(way.length()) * 0.08, 0)
	entity.on_ground = false


func _gone() -> void:
	removed = true
	if owner_player and owner_player.fishing_bobber == self:
		owner_player.fishing_bobber = null


func _process(delta: float) -> void:
	super(delta)
	if owner_player == null or _line_mesh == null:
		return
	# The line: from the rod's tip (in front of the right hand) to the bobber.
	var look := owner_player.look_direction()
	var right := look.cross(Vector3.UP).normalized()
	var tip := owner_player.eye_position() + look * 0.6 + right * 0.35 - Vector3(0, 0.25, 0)
	if owner_player.third_person:
		tip = owner_player.global_position + Vector3(0, 1.6, 0) + right * 0.4 + Vector3(look.x, 0, look.z) * 0.8
	var end := global_position + Vector3(0, 0.25, 0)
	_line_mesh.clear_surfaces()
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in 17:
		var t := i / 16.0
		var point := tip.lerp(end, t)
		point.y -= sin(t * PI) * minf(tip.distance_to(end) * 0.05, 1.0) # a little sag
		_line_mesh.surface_add_vertex(point)
	_line_mesh.surface_end()
