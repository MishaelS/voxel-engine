class_name ThrownItem
extends Entity
## Snowballs and eggs thrown by the player or shot from a dispenser, like
## Beta 1.7.3's EntitySnowball and EntityEgg: they fly at 1.5 blocks a tick
## (a dispenser's 1.1) along a falling curve (gravity 0.03, drag 0.99, 0.8
## in water) and break on the first block or creature they meet, in a puff
## of bits of their picture. A creature hit takes Beta's "0 damage": it
## flinches red, says its hurt sound, is pushed back and turns on the
## thrower; players are not touched (Beta's EntityPlayer ignores 0 damage).
## An egg that breaks hatches a chick 1 time in 8 (and then 1 in 32 four of
## them: chicks, like our breeding; Beta's were grown hens).
## Drawn like Beta's RenderSnowball: the item's picture always facing the
## camera, half a block wide.

const SPEED := 1.5
const SPREAD := 1.0
const GRAVITY := 0.03
const HATCH_CHANCE := 8
const FOUR_CHANCE := 32

## "snowball" or "egg".
var kind := "snowball"
## Who threw it (the player, a network player; null from a dispenser):
## not hit by it right away, and what is hit turns on it.
var thrower: Node3D
var _sprite: Sprite3D


## Throws `kind` from `from` along `direction` (speed in blocks a tick,
## spread like the game's inaccuracy).
static func throw(world: VoxelWorld, item_kind: String, from: Vector3, direction: Vector3, by: Node3D,
		speed: float = SPEED, spread: float = SPREAD) -> ThrownItem:
	var thrown := ThrownItem.new()
	thrown.kind = item_kind
	thrown.thrower = by
	world.entities.spawn(thrown, from)
	var heading := direction.normalized() + Vector3(randfn(0, 1), randfn(0, 1), randfn(0, 1)) * 0.0075 * spread
	thrown.velocity = heading.normalized() * speed
	Sounds.play("random/bow", from, 0.5, 0.4 / (randf() * 0.4 + 0.8))
	return thrown


static func create(type: String) -> ThrownItem:
	var thrown := ThrownItem.new()
	thrown.kind = type
	return thrown


func type_name() -> String:
	return kind


func can_be_hit() -> bool:
	return false


func _ready() -> void:
	half_width = 0.125
	height = 0.25
	var id := Items.id_of(kind)
	var item := Items.get_type(id)
	_sprite = Sprite3D.new()
	_sprite.texture = ItemMeshes.atlas_texture(id)
	_sprite.region_enabled = true
	_sprite.region_rect = Rect2((item.icon % 16) * 16, (item.icon / 16) * 16, 16, 16)
	_sprite.pixel_size = 0.5 / 16.0
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.shaded = false
	_sprite.position = Vector3(0, height * 0.5, 0)
	_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sprite)


func tick() -> void:
	_prev = Vector3(_x, _y, _z)
	age += 1
	var start := Vector3(_x, _y + height * 0.5, _z)
	var length := velocity.length()
	if length < 1e-6:
		length = 1e-6
	var end := start + velocity
	var block_hit := world.raycast(start, velocity, length)
	var block_distance := length + 1.0
	if block_hit.get("hit", false) and Blocks.collides_table[block_hit.block] == 1:
		block_distance = block_hit.distance
	else:
		block_hit = {}
	# Creatures on the way (not the thrower right after the throw).
	var ignore := thrower as Entity if age < 5 else null
	var hit := world.entities.raycast(start, velocity, minf(length, block_distance), ignore)
	var player := world.player as Player
	if player and (thrower != player or age >= 5) and not player.dead:
		var box := AABB(player.global_position - Vector3(Player.HALF_WIDTH, 0, Player.HALF_WIDTH),
			Vector3(Player.HALF_WIDTH * 2, Player.HEIGHT, Player.HALF_WIDTH * 2))
		var point: Variant = box.intersects_segment(start, end)
		if point != null and start.distance_to(point) < (hit[1] if not hit.is_empty() else block_distance):
			_break(point) # (a player takes nothing from it)
			return
	if Net.is_host():
		for avatar: RemotePlayer in Net.avatars.values():
			if not is_instance_valid(avatar) or avatar.dead or (avatar == thrower and age < 5):
				continue
			var avatar_box := AABB(avatar.target_position - Vector3(0.3, 0, 0.3), Vector3(0.6, 1.8, 0.6))
			var through: Variant = avatar_box.intersects_segment(start, end)
			if through != null and start.distance_to(through) < (hit[1] if not hit.is_empty() else block_distance):
				_break(through)
				return
	if not hit.is_empty():
		var target: Entity = hit[0]
		_strike(target, start)
		_break(start + velocity.normalized() * float(hit[1]))
		return
	if not block_hit.is_empty():
		_break(start + velocity.normalized() * block_distance)
		return
	_x = end.x
	_y = end.y - height * 0.5
	_z = end.z
	var water := EntityPhysics.touches_liquid(world, _x, _y, _z, half_width, height, "water")
	velocity *= 0.8 if water else 0.99
	velocity.y -= GRAVITY
	if _y < Player.VOID_Y:
		removed = true


## Beta's 0 damage: a flinch, the hurt sound, a push back and the creature
## turning on the thrower; nothing taken off its health.
func _strike(target: Entity, from: Vector3) -> void:
	if target.is_dead():
		return
	target.hurt_ticks = Entity.INVULNERABLE_TICKS
	target.knockback(target.center() - from)
	if target is Mob:
		target.call("_sound", "hurt", 1.0)
		if thrower and is_instance_valid(thrower):
			(target as Mob).hurt_by(thrower)


## Breaks where it hit: bits of its picture fly about; an egg may hatch.
func _break(point: Vector3) -> void:
	removed = true
	var id := Items.id_of(kind)
	for i in 8:
		world.particles.item_crumbs(id, point, Vector3(randf_range(-1, 1), randf_range(0, 1), randf_range(-1, 1)) * 0.5, 1, 0.5)
	if kind != "egg" or world.remote or randi_range(0, HATCH_CHANCE - 1) != 0:
		return
	var count := 4 if randi_range(0, FOUR_CHANCE - 1) == 0 else 1
	for i in count:
		var chick := Mob.create("chicken")
		chick.baby_ticks = Mob.GROW_TICKS
		world.entities.spawn(chick, Vector3(point.x, maxf(point.y - 0.2, floorf(point.y)), point.z))
		chick.rotation.y = randf() * TAU
		chick.set("_yaw", chick.rotation.y)
		chick.set("_prev_yaw", chick.rotation.y)


func save_state() -> Dictionary:
	var state := super()
	state["kind"] = kind
	return state


func load_state(saved: Dictionary) -> void:
	super(saved)
	var saved_kind: Variant = saved.get("kind", kind)
	if saved_kind is String and saved_kind in ["snowball", "egg"]:
		kind = saved_kind


func _process(delta: float) -> void:
	super(delta)
	if world and _sprite and Engine.get_process_frames() % 6 == 0:
		var light := world.brightness_at(global_position + Vector3(0, height * 0.5, 0))
		_sprite.modulate = Color(light, light, light)
