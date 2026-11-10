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


## A new entity of a registered type, or null.
func create(type: String) -> Entity:
	var script: Script = TYPES.get(type)
	return script.new() if script else null


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
