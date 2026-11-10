class_name Mob
extends Entity
## Mobs like the classic game (Beta 1.7.3), all from one class driven by
## TYPES: the model (MobModels), size, health, speed, drops, sounds and the
## kind of behavior.
##
## Animals (pig, cow, sheep, chicken, wolf) wander about, look at the player
## now and then and run away when hurt. Sheep can be sheared and dyed and
## eat grass to grow their wool back; chickens lay eggs and flutter down;
## wolves are tamed with bones (then follow the player, sit on a click and
## fight what hurts the player). Squid swim in water.
## Monsters (zombie, skeleton, creeper, spider, slime) go after the player
## they can see within 16 blocks: zombies and spiders hit, skeletons shoot
## arrows from a distance, creepers swell up and explode, slimes jump at
## you and split when they die. Zombies and skeletons burn in daylight;
## spiders are calm in the light unless hurt. Monsters far from the player
## disappear.
## All of them walk with the entity physics, jump up blocks in the way and
## swim; the model swings its legs while walking, turns its head toward
## what it looks at, flashes red when hurt and falls over when it dies.

## type -> spec. speed: walking speed in blocks per tick; hostile: attacks
## the player; damage: per hit (Normal); drops: [item, min, max].
const TYPES := {
	"pig": {"health": 10, "speed": 0.09, "drops": [["porkchop", 0, 2]], "sound": "pig"},
	"cow": {"health": 10, "speed": 0.08, "drops": [["leather", 0, 2]], "sound": "cow"},
	"sheep": {"health": 10, "speed": 0.09, "drops": [], "sound": "sheep"},
	"chicken": {"health": 4, "speed": 0.09, "drops": [["feather", 0, 2]], "sound": "chicken"},
	"wolf": {"health": 8, "speed": 0.12, "drops": [], "sound": "wolf"},
	"squid": {"health": 10, "speed": 0.04, "drops": [["ink_sac", 1, 3]], "sound": "", "water": true},
	"zombie": {"health": 20, "speed": 0.1, "hostile": true, "damage": 4, "drops": [["feather", 0, 2]], "sound": "zombie", "burns": true},
	"skeleton": {"health": 20, "speed": 0.1, "hostile": true, "damage": 4, "drops": [["bone", 0, 2], ["arrow", 0, 2]], "sound": "skeleton", "burns": true},
	"creeper": {"health": 20, "speed": 0.1, "hostile": true, "damage": 0, "drops": [["gunpowder", 0, 2]], "sound": "creeper"},
	"spider": {"health": 16, "speed": 0.13, "hostile": true, "damage": 2, "drops": [["string", 0, 2]], "sound": "spider"},
	"slime": {"health": 4, "speed": 0.1, "hostile": true, "damage": 1, "drops": [["slimeball", 0, 2]], "sound": "slime"},
}
const ANIMALS := ["pig", "cow", "sheep", "chicken"]
const MONSTERS := ["zombie", "skeleton", "creeper", "spider"]
const SIGHT := 16.0
const ATTACK_COOLDOWN := 20
const CREEPER_FUSE := 30
const CREEPER_POWER := 3.0
## Sheep wool colors (wool block names).
const WOOL_COLORS := ["white", "orange", "magenta", "light_blue", "yellow", "lime", "pink", "gray",
	"light_gray", "cyan", "purple", "blue", "brown", "green", "red", "black"]
const WOOL_TINTS := {
	"white": Color(1, 1, 1), "orange": Color(0.92, 0.53, 0.25), "magenta": Color(0.7, 0.33, 0.8),
	"light_blue": Color(0.4, 0.55, 0.85), "yellow": Color(0.88, 0.85, 0.3), "lime": Color(0.45, 0.8, 0.25),
	"pink": Color(0.9, 0.55, 0.65), "gray": Color(0.3, 0.3, 0.3), "light_gray": Color(0.65, 0.65, 0.65),
	"cyan": Color(0.2, 0.5, 0.6), "purple": Color(0.5, 0.25, 0.7), "blue": Color(0.2, 0.25, 0.65),
	"brown": Color(0.4, 0.27, 0.15), "green": Color(0.25, 0.37, 0.15), "red": Color(0.65, 0.2, 0.2),
	"black": Color(0.1, 0.1, 0.1),
}

var mob_type := "pig"
var spec := {}
## Sheep: sheared, wool color; slime: size 1, 2 or 4; wolf: tamed, sitting.
var sheared := false
var wool_color := "white"
var size := 1
var tamed := false
var sitting := false
var angry := false

var target: Node3D
var _wander := Vector3.INF
var _panic := 0
var _attack_cooldown := 0
var _fuse := 0
var _look_at := Vector3.INF
var _limb_swing := 0.0
var _limb_amount := 0.0
var _prev_limb := 0.0
var _egg_timer := 0
var _jump_timer := 0
var _say_timer := 0
var _model := {}


static func create(type: String) -> Mob:
	var mob := Mob.new()
	mob.mob_type = type
	return mob


## A spawned sheep's wool like the classic game: mostly white, some gray,
## light gray, black and brown, pink very rarely.
static func natural_wool() -> String:
	var roll := randi_range(0, 99)
	if roll < 5:
		return "black"
	if roll < 10:
		return "gray"
	if roll < 15:
		return "light_gray"
	if roll < 18:
		return "brown"
	return "pink" if randi_range(0, 499) == 0 else "white"


func type_name() -> String:
	return mob_type


func is_hostile() -> bool:
	return spec.get("hostile", false) and not (mob_type == "wolf")


func _ready() -> void:
	spec = TYPES[mob_type]
	step_height = 0.5
	_model = MobModels.build(mob_type)
	add_child(_model.root)
	_apply_size()
	health = max_health
	_egg_timer = randi_range(6000, 12000)
	_say_timer = randi_range(80, 400)
	_update_wool()


# --- Behavior --------------------------------------------------------------------------

## Box, health and model size (slimes come in sizes 1, 2 and 4).
func _apply_size() -> void:
	var model := MobModels.model(mob_type)
	half_width = float(model.get("width", 0.6)) / 2.0
	height = float(model.get("height", 1.0))
	max_health = spec.health
	var scale := float(model.get("scale", 1.0)) / 16.0
	if mob_type == "slime":
		half_width *= size
		height *= size
		max_health = size * size
		scale *= size
	if not _model.is_empty():
		_model.root.scale = Vector3.ONE * scale


func _ai_tick() -> void:
	_attack_cooldown = maxi(_attack_cooldown - 1, 0)
	_panic = maxi(_panic - 1, 0)
	var player := _player()
	if is_hostile() and _despawn(player):
		return
	if is_hostile() and Settings.get_value("difficulty") == 0:
		removed = true # peaceful: no monsters
		return
	_say_timer -= 1
	if _say_timer <= 0:
		_say_timer = randi_range(80, 400)
		_sound("say", 1.0)
	if spec.get("burns", false):
		_burn_in_daylight()
	if spec.get("water", false):
		_squid_tick()
		return
	match mob_type:
		"creeper":
			_monster_tick(player)
			_creeper_tick(player)
		"skeleton":
			_skeleton_tick(player)
		"slime":
			_slime_tick(player)
		"spider":
			_monster_tick(player)
			if horizontal_collision:
				velocity.y = 0.2 # climbs walls
		"zombie":
			_monster_tick(player)
		"wolf":
			_wolf_tick(player)
		_:
			_animal_tick(player)
	if mob_type == "chicken":
		velocity.y = maxf(velocity.y, -0.06) # flutters down
		_egg_timer -= 1
		if _egg_timer <= 0:
			_egg_timer = randi_range(6000, 12000)
			world.items.spawn(Items.id_of("egg"), 1, center(), Vector3(0, 0.1, 0))
	if mob_type == "sheep" and sheared and randi_range(0, 999) == 0:
		_eat_grass()
	if in_water:
		velocity.y += 0.04 # keeps its head above water


func _player() -> Player:
	var player := world.player as Player
	if player == null or player.dead or player.is_creative():
		return null
	return player


## Monsters far from the player disappear (128+ at once, 32+ now and then).
func _despawn(player: Node3D) -> bool:
	var who := world.player as Node3D
	if who == null:
		return false
	var distance := who.global_position.distance_to(feet())
	if distance > 128.0 or (distance > 32.0 and randi_range(0, 799) == 0):
		removed = true
		return true
	return false


func _animal_tick(player: Player) -> void:
	if _panic > 0:
		if _wander == Vector3.INF or randi_range(0, 9) == 0:
			_wander = feet() + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
		_walk_toward(_wander, spec.speed * 1.6)
		return
	if player and randi_range(0, 49) == 0 and player.global_position.distance_to(feet()) < 6.0:
		_look_at = player.eye_position()
	if _wander == Vector3.INF and randi_range(0, 119) == 0:
		_wander = feet() + Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
	if _wander != Vector3.INF:
		if Vector2(_wander.x - _x, _wander.z - _z).length() < 1.0 or randi_range(0, 199) == 0:
			_wander = Vector3.INF
		else:
			_walk_toward(_wander, spec.speed)


func _sees(player: Player) -> bool:
	if player == null:
		return false
	var eye := center() + Vector3(0, height * 0.35, 0)
	var to := player.eye_position()
	if eye.distance_to(to) > SIGHT:
		return false
	var hit := world.raycast(eye, to - eye, eye.distance_to(to))
	return not hit.get("hit", false)


## Zombies, spiders and creepers: walk at the player they can see, hit it
## when close (spiders leap).
func _monster_tick(player: Player) -> void:
	if mob_type == "spider" and not angry and world.get_combined_light(Vector3i(center().floor())) > 7:
		target = null
	elif _sees(player):
		target = player
	elif target and target is Player and (target as Player).dead:
		target = null
	if target == null:
		_animal_tick(null)
		return
	var goal := (target as Player).global_position
	_look_at = (target as Player).eye_position()
	var flat := Vector2(goal.x - _x, goal.z - _z).length()
	if mob_type == "creeper" and _fuse > 0:
		return # stands still while it swells
	if mob_type == "spider" and flat < 3.0 and flat > 1.5 and on_ground and randi_range(0, 9) == 0:
		var leap := Vector3(goal.x - _x, 0, goal.z - _z).normalized()
		velocity = Vector3(leap.x * 0.4, 0.4, leap.z * 0.4)
		return
	_walk_toward(goal, spec.speed)
	if mob_type != "creeper" and flat < half_width + 0.9 and absf(goal.y - _y) < height and _attack_cooldown == 0:
		_attack_cooldown = ATTACK_COOLDOWN
		(target as Player).damage(_scaled_damage(spec.damage))
		(target as Player).knockback(center())


## Damage by difficulty like Beta: easy half + 1, hard x1.5.
static func _scaled_damage(amount: int) -> int:
	match Settings.get_value("difficulty"):
		1:
			return amount / 2 + 1
		3:
			return amount * 3 / 2
	return amount


func _creeper_tick(player: Player) -> void:
	var close := player != null and player.global_position.distance_to(feet()) < 3.0 and _sees(player)
	if close or (_fuse > 0 and player != null and player.global_position.distance_to(feet()) < 7.0):
		if _fuse == 0:
			Sounds.play("mob/creeper/fuse", center(), 1.0, 0.5)
		_fuse += 1
		if _fuse >= CREEPER_FUSE:
			removed = true
			Explosion.explode(world, center(), CREEPER_POWER, self)
	else:
		_fuse = maxi(_fuse - 1, 0)


## Skeletons keep their distance and shoot.
func _skeleton_tick(player: Player) -> void:
	target = player if _sees(player) else null
	if target == null:
		_animal_tick(null)
		return
	_look_at = player.eye_position()
	var distance := player.global_position.distance_to(feet())
	if distance > 10.0:
		_walk_toward(player.global_position, spec.speed)
	else:
		_face(player.global_position)
	if _attack_cooldown == 0 and distance < 16.0:
		_attack_cooldown = 60
		Arrow.shoot(world, center() + Vector3(0, height * 0.3, 0), player.eye_position() - Vector3(0, 0.4, 0), 0.6 * 1.6, 12.0, self)


## Slimes hop toward the player (or about) and hurt it on touch (big ones).
func _slime_tick(player: Player) -> void:
	_jump_timer -= 1
	if on_ground:
		velocity.x = 0.0
		velocity.z = 0.0
	if _jump_timer <= 0 and on_ground:
		_jump_timer = randi_range(10, 30)
		var dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		if _sees(player):
			dir = Vector3(player.global_position.x - _x, 0, player.global_position.z - _z).normalized()
			_jump_timer /= 3
			_face(player.global_position)
		velocity = Vector3(dir.x * 0.15 * size, 0.42, dir.z * 0.15 * size)
		Sounds.play("mob/slime/" + ("big" if size > 1 else "small"), center(), 0.4 * size, randf_range(0.8, 1.2))
	if player and size > 1 and _attack_cooldown == 0 and player.global_position.distance_to(feet()) < half_width + 0.8:
		_attack_cooldown = ATTACK_COOLDOWN
		player.damage(_scaled_damage(size))


## Wolves: wild ones wander (and turn on what hurts them); tame ones follow
## their player, sit when told and go after what hurts the player.
func _wolf_tick(player: Player) -> void:
	if sitting:
		return
	if angry and target and target is Entity and not (target as Entity).is_dead():
		var goal := (target as Entity).feet()
		_walk_toward(goal, spec.speed * 1.2)
		if (target as Entity).center().distance_to(center()) < 1.5 and _attack_cooldown == 0:
			_attack_cooldown = ATTACK_COOLDOWN
			(target as Entity).damage(4 if tamed else 2, center())
		return
	if angry and target is Player and player:
		_walk_toward(player.global_position, spec.speed * 1.2)
		if player.global_position.distance_to(feet()) < 1.4 and _attack_cooldown == 0:
			_attack_cooldown = ATTACK_COOLDOWN
			player.damage(_scaled_damage(2))
		return
	if tamed and world.player:
		var owner := world.player.global_position
		var distance := owner.distance_to(feet())
		if distance > 12.0:
			teleport(owner + Vector3(randf_range(-2, 2), 0.5, randf_range(-2, 2)))
		elif distance > 4.0:
			_walk_toward(owner, spec.speed * 1.3)
		return
	_animal_tick(player)


func _squid_tick() -> void:
	if in_water:
		velocity.y += 0.02 # floats
		if _wander == Vector3.INF or randi_range(0, 49) == 0:
			_wander = Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)).normalized() * spec.speed
		velocity += _wander * 0.2
	else:
		velocity.x *= 0.5
		velocity.z *= 0.5


func _burn_in_daylight() -> void:
	var atmosphere := Atmosphere.find(world.get_tree())
	var daylight := atmosphere.daylight if atmosphere else 1.0
	if daylight > 0.5 and not in_water and world.get_light(Vector3i((center() + Vector3(0, height * 0.4, 0)).floor())) >= SkyLight.MAX:
		fire_ticks = maxi(fire_ticks, 160)


## Walks toward a point: turns to it, sets the horizontal speed, jumps up
## a block in the way.
func _walk_toward(point: Vector3, speed: float) -> void:
	var dir := Vector3(point.x - _x, 0, point.z - _z)
	if dir.length_squared() < 0.01:
		return
	dir = dir.normalized()
	_face(point)
	var control := 1.0 if on_ground or in_water else 0.3
	velocity.x = lerpf(velocity.x, dir.x * speed, control)
	velocity.z = lerpf(velocity.z, dir.z * speed, control)
	if horizontal_collision and on_ground:
		velocity.y = 0.42


func _face(point: Vector3) -> void:
	var dir := Vector3(point.x - _x, 0, point.z - _z)
	if dir.length_squared() < 0.0001:
		return
	var wanted := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, wanted, 0.35)


func _eat_grass() -> void:
	var below := Vector3i(floori(_x), floori(_y - 0.5), floori(_z))
	if Blocks.get_type(world.get_block(below)).name.begins_with("grass_"):
		world.set_block(below, Blocks.id_of("dirt"))
		sheared = false
		_update_wool()


# --- Interaction ---------------------------------------------------------------------

## The player right-clicks the mob with an item. Returns true if it did
## something (shearing, dyeing, milking, taming, sitting).
func interact(player: Player, item_id: int) -> bool:
	if is_dead():
		return false
	var item_name := Items.name_of(item_id) if item_id != Blocks.AIR else ""
	match mob_type:
		"sheep":
			if item_name == "shears" and not sheared:
				sheared = true
				_update_wool()
				var wool := Blocks.id_of(wool_color + "_wool")
				for i in randi_range(1, 3):
					world.items.spawn(wool, 1, center(), Vector3(randf_range(-0.1, 0.1), 0.2, randf_range(-0.1, 0.1)))
				if not player.is_creative():
					player.inventory.wear(player.selected_slot)
				return true
			var dye := _dye_color(item_name)
			if dye != "" and not sheared and dye != wool_color:
				wool_color = dye
				_update_wool()
				if not player.is_creative():
					player.inventory.take(player.selected_slot)
				return true
		"cow":
			if item_name == "bucket":
				if not player.is_creative():
					var slot := player.selected_slot
					if player.inventory.count_at(slot) == 1:
						player.inventory.set_slot(slot, Items.id_of("milk_bucket"), 1)
					else:
						player.inventory.take(slot)
						player.inventory.add(Items.id_of("milk_bucket"), 1)
				return true
		"wolf":
			if not tamed and item_name == "bone":
				if not player.is_creative():
					player.inventory.take(player.selected_slot)
				if randi_range(0, 2) == 0:
					tamed = true
					angry = false
					target = null
					world.particles.hearts(center() + Vector3(0, height * 0.5, 0))
				else:
					world.particles.smoke(center(), 4)
				return true
			if tamed:
				sitting = not sitting
				velocity = Vector3.ZERO
				return true
	return false


## The wool color a dye gives (the dyes in the game so far).
static func _dye_color(item_name: String) -> String:
	return {"bone_meal": "white", "cactus_green": "green", "cocoa_beans": "brown", "ink_sac": "black"}.get(item_name, "")


func _update_wool() -> void:
	if _model.is_empty() or mob_type != "sheep":
		return
	# The fleece: the model's parts marked "wool" (body, head and legs).
	for part: Dictionary in _model.spec.parts:
		if part.get("wool", false):
			var instance: MeshInstance3D = _model.instances[part.name]
			instance.visible = not sheared
			instance.set_instance_shader_parameter("tint", WOOL_TINTS.get(wool_color, Color.WHITE))


# --- Health ---------------------------------------------------------------------------

func damage(amount: int, from: Variant = null) -> bool:
	var hurt := super(amount, from)
	if hurt and not is_dead():
		_sound("hurt", 1.0)
		_panic = 60
		_wander = Vector3.INF
		if mob_type == "spider" or mob_type == "wolf":
			angry = true
			target = world.player
	return hurt


## Hit by the player (or something else): monsters and wolves fight back,
## tamed wolves forgive their owner.
func hurt_by(attacker: Node3D) -> void:
	if is_dead() or (mob_type == "wolf" and tamed and attacker is Player):
		if mob_type == "wolf":
			angry = false
		return
	var spec: Dictionary = TYPES[mob_type]
	if spec.get("hostile", false) or mob_type == "wolf":
		target = attacker
		angry = mob_type == "wolf" or mob_type == "spider" or angry


func _on_death() -> void:
	_sound("death", 1.0)
	if mob_type == "slime" and size > 1:
		for i in randi_range(2, 4):
			var child := Mob.create("slime")
			child.size = size / 2
			world.entities.spawn(child, feet() + Vector3(randf_range(-0.5, 0.5), 0.5, randf_range(-0.5, 0.5)))
		return
	for drop: Array in spec.drops:
		var count := randi_range(drop[1], drop[2])
		var item: String = drop[0]
		if item == "porkchop" and fire_ticks > 0:
			item = "cooked_porkchop"
		if count > 0:
			world.items.spawn(Items.id_of(item), count, center(), Vector3(randf_range(-0.1, 0.1), 0.2, randf_range(-0.1, 0.1)))
	if mob_type == "sheep" and not sheared:
		world.items.spawn(Blocks.id_of(wool_color + "_wool"), 1, center(), Vector3(0, 0.2, 0))


func _sound(kind: String, volume: float) -> void:
	var group: String = spec.get("sound", "")
	if group != "":
		Sounds.play("mob/%s/%s" % [group, kind], center(), volume, randf_range(0.8, 1.2) * (1.5 if mob_type == "slime" and size == 1 else 1.0))


# --- Drawing --------------------------------------------------------------------------

func _process(delta: float) -> void:
	super(delta)
	if _model.is_empty():
		return
	var alpha := TickLoop.alpha
	var moved := Vector2(_x - _prev.x, _z - _prev.z).length()
	_limb_amount = lerpf(_limb_amount, minf(moved * 4.0, 1.0), minf(delta * 10.0, 1.0))
	_limb_swing += moved * 4.0 * delta * 20.0
	var swing := cos(_limb_swing * 0.6662) * 1.4 * _limb_amount
	var parts: Dictionary = _model.parts
	for part: Dictionary in _model.spec.parts:
		var node: Node3D = parts.get(part.name)
		if node == null:
			continue # moves with its parent part
		match str(part.role):
			"leg_a":
				node.rotation.x = swing
			"leg_b":
				node.rotation.x = -swing
			"arm_right", "arm_left":
				if mob_type == "zombie" or mob_type == "skeleton":
					node.rotation.x = -PI / 2.0 + (swing * 0.1 if part.role == "arm_right" else -swing * 0.1)
				else:
					node.rotation.x = -swing if part.role == "arm_right" else swing
			"wing_right", "wing_left":
				var flap := 0.0 if on_ground else sin(Time.get_ticks_msec() / 40.0) * 0.8 + 0.8
				node.rotation.z = flap if part.role == "wing_left" else -flap
			"tentacle":
				node.rotation.x = sin(Time.get_ticks_msec() / 300.0) * 0.3
			"tail":
				node.rotation.x = 0.6 + (0.3 if tamed else 0.0) - (0.4 if sitting else 0.0)
			"head":
				_turn_head(node)
			_:
				if str(part.role).begins_with("spider_leg"):
					var side := 1.0 if str(part.role).contains("_l_") else -1.0
					var index := int(str(part.role).right(1))
					# Legs slope down to the ground like the game's: the front
					# and back pairs at 45 degrees, the middle ones flatter.
					node.rotation.z = -side * (PI / 4.0 if index == 0 or index == 3 else PI / 4.0 * 0.74)
					node.rotation.y = side * ((index - 1.5) * 0.4) + side * swing * 0.4 * (1 if index % 2 == 0 else -1)
	if mob_type == "wolf" and sitting:
		_model.root.position.y = -0.15
	var brightness := world.brightness_at(center()) if world else 1.0
	var flash := 0.0
	if mob_type == "creeper" and _fuse > 0:
		flash = 1.0 if int(_fuse / 2.0) % 2 == 0 else 0.0
		_model.root.scale = Vector3.ONE * float(MobModels.model(mob_type).get("scale", 1.0)) / 16.0 * (1.0 + _fuse / float(CREEPER_FUSE) * 0.2)
	for mesh: MeshInstance3D in _model.meshes:
		mesh.set_instance_shader_parameter("brightness", brightness)
		mesh.set_instance_shader_parameter("hurt", 1.0 if hurt_ticks > 0 or is_dead() else 0.0)
		mesh.set_instance_shader_parameter("flash", flash)
	if is_dead():
		# Falls over sideways, like the classic game.
		var t := minf((death_ticks + alpha) / DEATH_TICKS * 1.6, 1.0)
		_model.root.rotation.z = sqrt(t) * PI / 2.0


func _turn_head(node: Node3D) -> void:
	if _look_at == Vector3.INF:
		node.rotation = node.rotation.lerp(Vector3.ZERO, 0.1)
		return
	var local := global_transform.affine_inverse() * _look_at
	var head := node.global_position
	var to := _look_at - head
	var yaw := atan2(local.x, local.z)
	node.rotation.y = clampf(yaw, -1.2, 1.2)
	node.rotation.x = clampf(-atan2(to.y, Vector2(to.x, to.z).length()), -0.8, 0.8)


# --- Saving ---------------------------------------------------------------------------

func save_state() -> Dictionary:
	var state := super()
	state.merge({"sheared": sheared, "wool": wool_color, "size": size, "tamed": tamed, "sitting": sitting})
	return state


func load_state(saved: Dictionary) -> void:
	super(saved)
	sheared = saved.get("sheared", false)
	wool_color = saved.get("wool", "white")
	size = saved.get("size", 1)
	tamed = saved.get("tamed", false)
	sitting = saved.get("sitting", false)
	_apply_size()
	health = mini(saved.get("health", max_health), max_health)
	_update_wool()
