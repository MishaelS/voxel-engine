class_name CommandTargets
extends RefCounted
## What commands act on (selectors, /tp, /kill...), whatever it is:
## - Player: the player on this computer;
## - RemotePlayer: a client's player as the host sees it (network game);
## - Entity: a creature, arrow, primed TNT, boat, minecart...;
## - Dictionary: a dropped item (ItemEntities).
## These helpers give each the same face: type, name, position, facing,
## and moving, hurting or killing it.

## Entity types for selectors (type=...) besides the mobs (Mob.TYPES).
const OTHER_TYPES: Array[String] = ["player", "item", "arrow", "tnt", "boat", "minecart", "chest_minecart",
	"furnace_minecart", "painting", "lightning_bolt", "fishing_bobber"]


## Every type name a selector may ask for.
static func type_names() -> PackedStringArray:
	var names := PackedStringArray(Mob.TYPES.keys())
	names.append_array(OTHER_TYPES)
	names.sort()
	return names


## The players: this one and, hosting, the clients' (their avatars).
static func players(world: VoxelWorld) -> Array:
	var result := []
	if world and world.player is Player:
		result.append(world.player)
	if Net.is_host():
		for avatar: Variant in Net.avatars.values():
			if is_instance_valid(avatar):
				result.append(avatar)
	return result


## Everything: the players, the world's entities and the dropped items.
static func everything(world: VoxelWorld) -> Array:
	var result := players(world)
	if world == null:
		return result
	if world.entities:
		for entity in world.entities.all():
			if not entity.removed and not entity.is_dead():
				result.append(entity)
	if world.items:
		for item: Dictionary in world.items.get("_items"):
			if int(item.picked) < 0:
				result.append(item)
	return result


static func is_player(target: Variant) -> bool:
	return target is Player or target is RemotePlayer


static func type_of(target: Variant) -> String:
	if is_player(target):
		return "player"
	if target is Dictionary:
		return "item"
	if target is Entity:
		return (target as Entity).type_name()
	return ""


static func name_of(target: Variant) -> String:
	if target is Player:
		return Net.player_name if Net.player_name != "" else "Player"
	if target is RemotePlayer:
		return (target as RemotePlayer).player_name
	if target is Dictionary:
		return Items.display_name(int(target.id))
	return Lang.t(type_of(target).capitalize())


## Where its feet are.
static func position_of(target: Variant) -> Vector3:
	if target is Dictionary:
		return target.pos
	if target is RemotePlayer:
		return (target as RemotePlayer).target_position
	if target is Entity:
		return (target as Entity).feet()
	if target is Node3D:
		return (target as Node3D).global_position
	return Vector3.ZERO


## Where its eyes are (/execute anchored eyes, @s facing).
static func eyes_of(target: Variant) -> Vector3:
	if target is Player:
		return (target as Player).eye_position()
	if target is RemotePlayer:
		return position_of(target) + Vector3(0, Player.EYE_HEIGHT, 0)
	if target is Entity:
		return position_of(target) + Vector3(0, (target as Entity).height * 0.85, 0)
	return position_of(target)


## Facing as (yaw, pitch) in the classic game's degrees: yaw 0 = south
## (+z), 90 = west (-x); pitch 90 = down.
static func rotation_of(target: Variant) -> Vector2:
	if target is Player or target is RemotePlayer:
		# The player's yaw 0 looks north (-z), up is a positive pitch.
		var yaw := float(target.get("_yaw") if target is Player else target.get("_target_yaw"))
		return Vector2(wrapf(rad_to_deg(PI - yaw), -180.0, 180.0), -rad_to_deg(float(target.get("_pitch"))))
	if target is Entity:
		# Creatures face +z at yaw 0 (Mob._face), turning toward +x.
		var yaw := float(target.get("_yaw")) if "_yaw" in target else (target as Node3D).rotation.y
		return Vector2(wrapf(-rad_to_deg(yaw), -180.0, 180.0), 0.0)
	return Vector2.ZERO


## Turns it to face (yaw, pitch) in degrees (see rotation_of).
static func set_rotation(target: Variant, rotation: Vector2) -> void:
	if target is Player:
		target.set("_yaw", PI - deg_to_rad(rotation.x))
		target.set("_pitch", clampf(-deg_to_rad(rotation.y), -PI / 2 + 0.001, PI / 2 - 0.001))
	elif target is Entity:
		var yaw := -deg_to_rad(rotation.x)
		if "_yaw" in target:
			target.set("_yaw", yaw)
		if "_prev_yaw" in target:
			target.set("_prev_yaw", yaw)
		(target as Node3D).rotation.y = yaw


## Moves it to `position` (feet), and turns it when `rotation` is not
## Vector2.INF. Returns "" or why it can't be moved.
static func teleport(target: Variant, position: Vector3, rotation: Vector2 = Vector2.INF) -> String:
	if target is RemotePlayer:
		return Lang.t("Another player can't be moved from here")
	if target is Player:
		var player := target as Player
		if player.vehicle:
			if player.vehicle.puppet:
				Net.send_dismount(player.vehicle.net_id)
			player.vehicle = null
		player.wake_up()
		player.global_position = position # (the player picks it up as a teleport)
		player.velocity = Vector3.ZERO
	elif target is Entity:
		var entity := target as Entity
		if entity.puppet:
			return Lang.t("Only the host can move creatures")
		entity.teleport(position)
		entity.velocity = Vector3.ZERO
	elif target is Dictionary:
		target.pos = position
		target.prev = position
		target.vel = Vector3.ZERO
	if rotation != Vector2.INF:
		set_rotation(target, rotation)
	return ""


## Kills it like /kill (players in creative too; items and things vanish).
## Returns true if something died.
static func kill(target: Variant) -> bool:
	if target is Player:
		var player := target as Player
		if player.dead:
			return false
		player.health = 0
		player.call("_die")
		return true
	if target is RemotePlayer:
		var avatar := target as RemotePlayer
		if avatar.dead:
			return false
		Net.hurt_peer(avatar.peer_id, 20, Vector3.INF) # (as much as the network allows)
		return true
	if target is Mob:
		var mob := target as Mob
		if mob.is_dead() or mob.puppet:
			return false
		mob.health = 0
		mob.die()
		return true
	if target is Entity:
		var entity := target as Entity
		if entity.removed or entity.puppet:
			return false
		entity.removed = true
		return true
	if target is Dictionary:
		target.age = ItemEntities.LIFETIME # gone at the next tick
		return true
	return false


## Hurts it like a hit without a direction (/damage). Returns true if hurt.
static func damage(target: Variant, amount: int) -> bool:
	if target is Player:
		var player := target as Player
		var before := player.health
		player.damage(amount)
		return player.health < before
	if target is RemotePlayer:
		Net.hurt_peer((target as RemotePlayer).peer_id, amount, Vector3.INF)
		return true
	if target is Entity:
		if (target as Entity).puppet:
			return false
		return (target as Entity).damage(amount)
	return false


## The inventory of a player on this computer, or null.
static func inventory_of(target: Variant) -> Inventory:
	return (target as Player).inventory if target is Player else null
