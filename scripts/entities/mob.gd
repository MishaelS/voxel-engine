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
	"zombie": {"health": 20, "speed": 0.1, "hostile": true, "damage": 4, "drops": [["feather", 0, 2]], "sound": "zombie", "undead": true},
	"skeleton": {"health": 20, "speed": 0.1, "hostile": true, "damage": 4, "drops": [["bone", 0, 2], ["arrow", 0, 2]], "sound": "skeleton", "undead": true},
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
## Pigs: wearing a saddle (the player can ride them).
var saddled := false
var _squid_push := 0.0
var _squid_pitch := 0.0
var angry := false

var target: Node3D
var _wander := Vector3.INF
var _panic := 0
var _attack_cooldown := 0
var _fuse := 0
var _look_at := Vector3.INF
var _look_ticks := 0
## Idle look-around: where the head turns (yaw, pitch) and when next.
var _idle_look := Vector2.ZERO
var _next_look := 0
var _jump := 0.0
var _fall := 0.0
var _squish := 0.0
var _was_on_ground := true
var _base_scale := 1.0 / 16.0
var _frame_delta := 0.0
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


## The undead (zombies, skeletons) fear the sun: they catch fire in
## daylight under the open sky, like the game's.
func is_undead() -> bool:
	return spec.get("undead", false)


func is_hostile() -> bool:
	return spec.get("hostile", false) and not (mob_type == "wolf")


var _held: MeshInstance3D


func _ready() -> void:
	spec = TYPES[mob_type]
	step_height = 0.5
	_model = MobModels.build(mob_type)
	add_child(_model.root)
	if mob_type == "skeleton":
		# Skeletons hold their bow, like the game's.
		_held = MobModels.held_item(mob_type, Items.id_of("bow"))
		(_model.parts.right_arm as Node3D).add_child(_held)
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
	if mob_type == "wolf" and tamed:
		max_health = 20
	var scale := float(model.get("scale", 1.0)) / 16.0
	if mob_type == "slime":
		half_width *= size
		height *= size
		max_health = size * size
		scale *= size
	_base_scale = scale
	if not _model.is_empty():
		_model.root.scale = Vector3.ONE * scale


func _ai_tick() -> void:
	_attack_cooldown = maxi(_attack_cooldown - 1, 0)
	_look_ticks -= 1
	if _look_ticks <= 0:
		_look_at = Vector3.INF
	_panic = maxi(_panic - 1, 0)
	var player = _player()
	if is_hostile() and _despawn(player):
		return
	if is_hostile() and Settings.get_value("difficulty") == 0:
		removed = true # peaceful: no monsters
		return
	_say_timer -= 1
	if _say_timer <= 0:
		_say_timer = randi_range(80, 400)
		_sound("say", 1.0)
	if is_undead():
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


## The player it goes after or looks at: the nearest one alive and not in
## creative (in a network game the others too: RemotePlayer acts like one).
func _player():
	var best = null
	var best_distance := INF
	for who in _players():
		if who == null or who.dead or who.is_creative():
			continue
		var distance: float = (who.global_position as Vector3).distance_squared_to(feet())
		if distance < best_distance:
			best_distance = distance
			best = who
	return best


## Every player in the world (the local one, the network game's others).
func _players() -> Array:
	var result := [world.player]
	if Net.is_host():
		for avatar: RemotePlayer in Net.avatars.values():
			if is_instance_valid(avatar):
				result.append(avatar)
	return result


static func _is_player(who) -> bool:
	return who is Player or who is RemotePlayer


## Monsters far from the player disappear (128+ at once, 32+ now and then).
func _despawn(_player_near) -> bool:
	var distance := INF
	for who in _players():
		if who != null:
			distance = minf(distance, (who.global_position as Vector3).distance_to(feet()))
	if distance == INF:
		return false
	if distance > 128.0 or (distance > 32.0 and randi_range(0, 799) == 0):
		removed = true
		return true
	return false


func _animal_tick(player) -> void:
	if _panic > 0:
		if _wander == Vector3.INF or randi_range(0, 9) == 0:
			_wander = feet() + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
		_walk_toward(_wander, spec.speed * 1.6)
		return
	if player and randi_range(0, 49) == 0 and player.global_position.distance_to(feet()) < 6.0:
		_look_at = player.eye_position()
		_look_ticks = randi_range(20, 60) # like the game: looks for a while
	if _wander == Vector3.INF and randi_range(0, 119) == 0:
		_wander = feet() + Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
	if _wander != Vector3.INF:
		if Vector2(_wander.x - _x, _wander.z - _z).length() < 1.0 or randi_range(0, 199) == 0:
			_wander = Vector3.INF
		else:
			_walk_toward(_wander, spec.speed)


func _sees(player) -> bool:
	if player == null:
		return false
	var eye := center() + Vector3(0, height * 0.35, 0)
	var to: Vector3 = player.eye_position()
	if eye.distance_to(to) > SIGHT:
		return false
	var hit := world.raycast(eye, to - eye, eye.distance_to(to))
	return not hit.get("hit", false)


## Zombies, spiders and creepers: walk at the player they can see, hit it
## when close (spiders leap).
func _monster_tick(player) -> void:
	if mob_type == "spider" and not angry and world.get_combined_light(Vector3i(center().floor())) > 7:
		target = null
	elif _sees(player):
		target = player
	elif target and _is_player(target) and target.dead:
		target = null
	if target == null:
		_animal_tick(null)
		return
	var goal: Vector3 = target.global_position
	_look_at = target.eye_position()
	_look_ticks = 5
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
		target.damage(_scaled_damage(spec.damage))
		target.knockback(center())


## Damage by difficulty like Beta: easy half + 1, hard x1.5.
static func _scaled_damage(amount: int) -> int:
	match Settings.get_value("difficulty"):
		1:
			return amount / 2 + 1
		3:
			return amount * 3 / 2
	return amount


func _creeper_tick(player) -> void:
	var close: bool = player != null and player.global_position.distance_to(feet()) < 3.0 and _sees(player)
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
func _skeleton_tick(player) -> void:
	target = player if _sees(player) else null
	if target == null:
		_animal_tick(null)
		return
	_look_at = player.eye_position()
	_look_ticks = 5
	var distance: float = player.global_position.distance_to(feet())
	if distance > 10.0:
		_walk_toward(player.global_position, spec.speed)
	else:
		_face(player.global_position)
	if _attack_cooldown == 0 and distance < 16.0:
		_attack_cooldown = 60
		Arrow.shoot(world, center() + Vector3(0, height * 0.3, 0), player.eye_position() - Vector3(0, 0.4, 0), 0.6 * 1.6, 12.0, self)


## Slimes hop toward the player (or about) and hurt it on touch (big ones).
func _slime_tick(player) -> void:
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
func _wolf_tick(player) -> void:
	if sitting:
		return
	if angry and target and target is Entity and not (target as Entity).is_dead():
		var goal := (target as Entity).feet()
		_walk_toward(goal, spec.speed * 1.2)
		if (target as Entity).center().distance_to(center()) < 1.5 and _attack_cooldown == 0:
			_attack_cooldown = ATTACK_COOLDOWN
			(target as Entity).damage(4 if tamed else 2, center())
		return
	if angry and _is_player(target) and player:
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


## Squid like Beta's: under water they swim in pushes (a new, mostly level
## direction now and then, the push fading), staying under the surface;
## the body leans into the way it goes. Out of water they flop.
func _squid_tick() -> void:
	if in_water:
		_squid_push *= 0.9
		if _wander == Vector3.INF or randi_range(0, 49) == 0 or horizontal_collision:
			var angle := randf() * TAU
			_wander = Vector3(cos(angle), randf_range(-0.1, 0.1), sin(angle)).normalized()
		if _squid_push < 0.05 and randi_range(0, 19) == 0:
			_squid_push = 1.0 # a new push of the tentacles
		var push: Vector3 = _wander * float(spec.speed) * 2.0 * _squid_push
		velocity.x = push.x
		velocity.z = push.z
		velocity.y = push.y + 0.02 # cancels the water's pull: no rising or sinking
		# Stay under the surface.
		if Blocks.liquid_table[world.get_block(Vector3i(floori(_x), floori(_y + height + 0.1), floori(_z)))] == 0:
			velocity.y = minf(velocity.y, -0.02)
		if Vector2(velocity.x, velocity.z).length_squared() > 1e-5:
			rotation.y = atan2(velocity.x, velocity.z)
	else:
		velocity.x *= 0.5
		velocity.z *= 0.5


func _burn_in_daylight() -> void:
	var atmosphere := Atmosphere.find(world.get_tree())
	var daylight := atmosphere.daylight if atmosphere else 1.0
	if daylight > 0.5 and not is_wet() and world.get_light(Vector3i((center() + Vector3(0, height * 0.4, 0)).floor())) >= SkyLight.MAX:
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
		"pig":
			if not saddled and item_name == "saddle":
				saddled = true
				_update_wool()
				if not player.is_creative():
					player.inventory.take(player.selected_slot)
				return true
			if saddled and player.vehicle == null:
				player.mount(self)
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
					max_health = 20 # tame wolves have 20 health, like Beta
					Stats.grant("tamer")
					health = max_health
					_update_wool()
					world.particles.hearts(center() + Vector3(0, height * 0.5, 0))
				else:
					world.particles.smoke(center(), 4)
				return true
			if tamed:
				sitting = not sitting
				velocity = Vector3.ZERO
				return true
	return false


## The wool color a dye gives.
static func _dye_color(item_name: String) -> String:
	return Items.DYE_COLORS.get(item_name, "")


func _update_wool() -> void:
	if _model.is_empty():
		return
	for part: Dictionary in _model.spec.parts:
		if part.get("saddle", false):
			(_model.instances[part.name] as MeshInstance3D).visible = saddled
		if part.get("collar", false):
			# A red collar on tame wolves.
			var collar: MeshInstance3D = _model.instances[part.name]
			collar.visible = tamed
			collar.set_instance_shader_parameter("tint", Color(0.85, 0.15, 0.15))
	if mob_type != "sheep":
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
	var moved := Vector2(_x - _prev.x, _z - _prev.z).length() if vehicle == null else 0.0 # carried, not walking
	_limb_amount = lerpf(_limb_amount, minf(moved * 4.0, 1.0), minf(delta * 10.0, 1.0))
	_limb_swing += moved * 4.0 * delta * 20.0
	var swing := cos(_limb_swing * 0.6662) * 1.4 * _limb_amount
	_frame_delta = delta
	var t := age + alpha
	var smooth := minf(delta * 12.0, 1.0)
	_jump = lerpf(_jump, MobAnimation.jump_amount(velocity.y, on_ground, in_water), smooth)
	_fall = lerpf(_fall, MobAnimation.fall_amount(velocity.y, on_ground, in_water), smooth)
	if age >= _next_look:
		# Now and then glances somewhere else, or back ahead.
		_next_look = age + randi_range(MobAnimation.LOOK_AROUND.x, MobAnimation.LOOK_AROUND.y)
		_idle_look = Vector2(randf_range(-0.7, 0.7), randf_range(-0.3, 0.2)) if randf() < 0.6 else Vector2.ZERO
	var parts: Dictionary = _model.parts
	var biped := parts.has("right_arm") and parts.has("right_leg")
	if biped:
		MobAnimation.pose_biped(parts, t, _limb_swing, _limb_amount, _held != null,
			mob_type == "zombie" or mob_type == "skeleton", _jump, _fall)
		if vehicle:
			# Sitting in a boat or minecart: the legs straight ahead, a little apart.
			for side: Array in [["right_leg", -1.0], ["left_leg", 1.0]]:
				(parts[side[0]] as Node3D).rotation = Vector3(-PI * 2.0 / 5.0, float(side[1]) * PI / 10.0, 0)
	for part: Dictionary in _model.spec.parts:
		var node: Node3D = parts.get(part.name)
		if node == null:
			continue # moves with its parent part
		match str(part.role):
			"leg_a", "leg_b":
				if not biped:
					var front := str(part.name).begins_with("leg_f") or mob_type == "chicken"
					MobAnimation.pose_quadruped_leg(node, front, part.role == "leg_a", _limb_swing, _limb_amount, _jump, _fall)
			"arm_right", "arm_left":
				pass # posed with the legs (pose_biped)
			"wing_right", "wing_left":
				var flap := 0.0 if on_ground else sin(Time.get_ticks_msec() / 40.0) * 0.8 + 0.8
				node.rotation.z = flap if part.role == "wing_left" else -flap
			"tentacle":
				node.rotation.x = sin(Time.get_ticks_msec() / 300.0) * 0.3
			"tail":
				# Wild wolves hold the tail low; tame ones high, lower when hurt
				# (the classic health gauge).
				node.rotation.x = (0.55 - (max_health - health) * 0.02) * PI if tamed else PI / 5.0
				if sitting:
					node.rotation.x = PI / 4.0
			"head":
				_turn_head(node)
			_:
				if str(part.role).begins_with("spider_leg"):
					MobAnimation.pose_spider_leg(node, str(part.role), swing)
	if mob_type == "wolf" and sitting:
		_model.root.position.y = -0.15
	if mob_type == "slime":
		# The game's squish: stretched up when it jumps, squashed on landing.
		if on_ground and not _was_on_ground:
			_squish = -0.5
		elif not on_ground and _was_on_ground and velocity.y > 0.0:
			_squish = 1.0
		_was_on_ground = on_ground
		_squish *= pow(0.6, delta * 20.0)
		_model.root.scale = MobAnimation.slime_scale(_squish, size) * _base_scale
	if mob_type != "squid" and not is_dead():
		# A short flinch back when hurt (red too, below).
		_model.root.rotation.x = -0.18 * MobAnimation.flinch(hurt_ticks, alpha, Entity.INVULNERABLE_TICKS)
	if mob_type == "squid":
		# Leans into the way it swims (level when still), around its middle.
		var moving := Vector2(velocity.x, velocity.z).length()
		var target := atan2(moving, velocity.y) if moving > 0.005 or absf(velocity.y) > 0.005 else 0.0
		if not in_water:
			target = 0.0
		_squid_pitch = lerpf(_squid_pitch, target, minf(delta * 3.0, 1.0))
		var middle := Vector3(0, height * 0.5, 0)
		var size := float(MobModels.model("squid").get("scale", 1.0)) / 16.0
		_model.root.transform = Transform3D(Basis(Vector3.RIGHT, _squid_pitch), middle) \
			* Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), -middle)
	var brightness := world.brightness_at(center()) if world else 1.0
	var flash := 0.0
	if mob_type == "creeper" and _fuse > 0:
		flash = 1.0 if int(_fuse / 2.0) % 2 == 0 else 0.0
		_model.root.scale = Vector3.ONE * float(MobModels.model(mob_type).get("scale", 1.0)) / 16.0 * (1.0 + _fuse / float(CREEPER_FUSE) * 0.2)
	if _held:
		FallingBlocks.light(_held, brightness)
	for mesh: MeshInstance3D in _model.meshes:
		mesh.set_instance_shader_parameter("brightness", brightness)
		mesh.set_instance_shader_parameter("hurt", 1.0 if hurt_ticks > 0 or is_dead() else 0.0)
		mesh.set_instance_shader_parameter("flash", flash)
	if is_dead():
		# Falls over sideways, like the classic game.
		var fall_t := minf((death_ticks + alpha) / DEATH_TICKS * 1.6, 1.0)
		_model.root.rotation.z = sqrt(fall_t) * PI / 2.0


func _death_puff() -> void:
	if world:
		world.particles.smoke(center(), 20)


func _turn_head(node: Node3D) -> void:
	if _look_at == Vector3.INF:
		# Idle: turns slowly toward where it glances, with a little nod.
		var ease := minf(_frame_delta * 3.0, 1.0)
		var idle := _idle_look if _limb_amount < 0.3 else Vector2.ZERO
		node.rotation.y = lerpf(node.rotation.y, idle.x, ease)
		node.rotation.x = lerpf(node.rotation.x, idle.y + MobAnimation.head_bob(age + TickLoop.alpha), ease)
		node.rotation.z = 0.0
		return
	var local := global_transform.affine_inverse() * _look_at
	var head := node.global_position
	var to := _look_at - head
	var yaw := atan2(local.x, local.z)
	node.rotation.y = clampf(yaw, -1.2, 1.2)
	node.rotation.x = clampf(-atan2(to.y, Vector2(to.x, to.z).length()), -0.8, 0.8)


# --- Saving ---------------------------------------------------------------------------

func net_state() -> Dictionary:
	var state := super()
	state.merge({"fuse": _fuse, "angry": angry, "sheared": sheared, "sitting": sitting, "saddled": saddled, "tamed": tamed})
	return state


func apply_net_state(at: Vector3, yaw: float, state: Dictionary) -> void:
	var was_hurt := hurt_ticks > 0
	super(at, yaw, state)
	if hurt_ticks > 0 and not was_hurt and death_ticks < 0:
		_sound("hurt", 1.0) # (the host's creature was hit)
	_fuse = int(state.get("fuse", 0))
	angry = bool(state.get("angry", false))
	sitting = bool(state.get("sitting", false))
	saddled = bool(state.get("saddled", false))
	tamed = bool(state.get("tamed", false))
	if bool(state.get("sheared", false)) != sheared:
		sheared = not sheared
		_update_wool()


func save_state() -> Dictionary:
	var state := super()
	state.merge({"sheared": sheared, "wool": wool_color, "size": size, "tamed": tamed, "sitting": sitting, "saddled": saddled})
	return state


func load_state(saved: Dictionary) -> void:
	super(saved)
	sheared = saved.get("sheared", false)
	wool_color = saved.get("wool", "white")
	size = saved.get("size", 1)
	tamed = saved.get("tamed", false)
	sitting = saved.get("sitting", false)
	saddled = saved.get("saddled", false)
	_update_wool()
	_apply_size()
	health = mini(saved.get("health", max_health), max_health)
	_update_wool()
