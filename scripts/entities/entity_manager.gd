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


func _exit_tree() -> void:
	TickLoop.remove_listener(_tick)


func count() -> int:
	return _entities.size()


func all() -> Array[Entity]:
	return _entities


## Adds an entity at `position` (feet).
func spawn(entity: Entity, position: Vector3) -> Entity:
	entity.world = world
	add_child(entity)
	entity.teleport(position)
	_entities.append(entity)
	return entity


## A new entity of a registered type (mobs by their name), or null.
func create(type: String) -> Entity:
	if Mob.TYPES.has(type):
		return Mob.create(type)
	if type == "arrow":
		return Arrow.new()
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


func _tick(_tick_index: int) -> void:
	if spawner == null and world:
		spawner = MobSpawner.new(world)
	if spawner:
		spawner.tick()
	var i := 0
	while i < _entities.size():
		var entity := _entities[i]
		if not entity.removed and world.is_inside(Vector3i(entity.feet().floor())):
			entity.tick()
		if entity.removed:
			entity.queue_free()
			_entities.remove_at(i)
			continue
		i += 1


func save_state() -> Array:
	var result := []
	for entity in _entities:
		if not entity.is_dead() and not entity.removed:
			result.append(entity.save_state())
	return result


func load_state(saved: Array) -> void:
	for state: Dictionary in saved:
		var entity := create(state.get("type", ""))
		if entity:
			spawn(entity, state.get("position", Vector3.ZERO))
			entity.load_state(state)
