class_name EntityManager
extends Node3D
## Keeps the world's entities (Entity): adds and removes them, ticks them
## every game tick (TickLoop, Phase.ENTITIES) while the ground under them is
## loaded, and saves / loads them with the world.
## Entity types are registered by name in TYPES (the save keeps the name).

## Type name -> script. Add new entity types here.
const TYPES := {
	"entity": preload("res://scripts/entities/entity.gd"),
}

var world: VoxelWorld
var _entities: Array[Entity] = []
## Natural mob spawning around the player.
var spawner: MobSpawner


func _ready() -> void:
	TickLoop.add_listener(_tick, TickLoop.Phase.ENTITIES)
	# Every creature's model made once now, while the world loads (its
	# meshes and textures are kept): the first of a kind to spawn stalled
	# a tick building them.
	for type: String in Mob.TYPES:
		MobModels.build(type).root.free()


func _exit_tree() -> void:
	TickLoop.remove_listener(_tick)


func count() -> int:
	return _entities.size()


func all() -> Array[Entity]:
	return _entities


## Adds an entity at `position` (feet). On a network client the host makes
## the world's entities: one made here (an arrow shot, a boat put down) is
## sent to the host (Net.send_spawn, with its state and speed set just
## after) and goes; the host's copy comes back in its snapshots.
func spawn(entity: Entity, position: Vector3) -> Entity:
	entity.world = world
	add_child(entity)
	entity.teleport(position)
	_entities.append(entity)
	if world and world.remote and not entity.puppet and entity.type_name() != "fishing_bobber": # (each player's own)
		_hand_to_host.call_deferred(entity)
	return entity


func _hand_to_host(entity: Entity) -> void:
	if not is_instance_valid(entity) or entity.removed:
		return
	Net.send_spawn(entity)
	entity.removed = true


## A client: the entity with the host's number, or null.
func by_net_id(id: int) -> Entity:
	for entity in _entities:
		if entity.net_id == id and not entity.removed:
			return entity
	return null


## A new entity of a registered type (mobs by their name), or null.
func create(type: String) -> Entity:
	if Mob.TYPES.has(type):
		return Mob.create(type)
	if type == "arrow":
		return Arrow.new()
	if type == "snowball" or type == "egg":
		return ThrownItem.create(type)
	if type == "painting":
		return Painting.new()
	if type == "tnt":
		return PrimedTnt.new()
	if type in ["minecart", "chest_minecart", "furnace_minecart"]:
		return Minecart.create(type)
	if type == "boat":
		return Boat.new()
	var script: Script = TYPES.get(type)
	return script.new() if script else null


## The entity hit first by a ray (its box), within `max_distance`:
## [entity, distance], or [] when none.
func raycast(origin: Vector3, direction: Vector3, max_distance: float, ignore: Entity = null) -> Array:
	var best: Entity = null
	var best_distance := max_distance
	var to := origin + direction.normalized() * max_distance
	for entity in _entities:
		if entity == ignore or entity.is_dead() or entity.removed or not entity.can_be_hit():
			continue
		var box := entity.hit_box().grow(0.1)
		var hit: Variant = box.intersects_segment(origin, to)
		if hit != null:
			var distance := origin.distance_to(hit)
			if distance < best_distance:
				best_distance = distance
				best = entity
	return [best, best_distance] if best else []


## Mobs of a type within `radius` of a point.
func count_near(type: String, point: Vector3, radius: float) -> int:
	var total := 0
	for entity in _entities:
		if entity.type_name() == type and entity.feet().distance_to(point) <= radius:
			total += 1
	return total


## Entities whose middle is within `radius` of `point`.
func near(point: Vector3, radius: float) -> Array[Entity]:
	var result: Array[Entity] = []
	for entity in _entities:
		if not entity.is_dead() and entity.center().distance_squared_to(point) <= radius * radius:
			result.append(entity)
	return result


func clear() -> void:
	for entity in _entities:
		entity.queue_free()
	_entities.clear()


## Time of the last tick by entity type, and "spawner" (microseconds), for
## profiling.
var tick_times := {}


func _tick(_tick_index: int) -> void:
	tick_times.clear()
	var started := Time.get_ticks_usec()
	if spawner == null and world and not world.remote: # (a client's creatures come from the host: next step)
		spawner = MobSpawner.new(world)
	if spawner:
		spawner.tick()
	tick_times["spawner"] = Time.get_ticks_usec() - started
	var i := 0
	while i < _entities.size():
		var entity := _entities[i]
		if entity.puppet and not entity.removed:
			entity.puppet_tick() # (a client: the host's snapshots move it)
		elif not entity.removed and world.is_inside(Vector3i(entity.feet().floor())):
			var before := Time.get_ticks_usec()
			entity.tick()
			var kind := entity.type_name()
			tick_times[kind] = tick_times.get(kind, 0) + Time.get_ticks_usec() - before
		if entity.removed:
			entity.queue_free()
			_entities.remove_at(i)
			continue
		i += 1


func save_state() -> Array:
	var result := []
	for entity in _entities:
		if not entity.is_dead() and not entity.removed:
			if entity.vehicle is Mob and is_instance_valid(entity.vehicle) and not entity.vehicle.removed:
				continue # (a spider jockey's skeleton: saved with its spider, Mob.save_state)
			result.append(entity.save_state())
	return result


func load_state(saved: Array) -> void:
	for state: Dictionary in saved:
		var entity := create(state.get("type", ""))
		if entity:
			spawn(entity, state.get("position", Vector3.ZERO))
			entity.load_state(state)
